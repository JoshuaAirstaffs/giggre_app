// Loads and validates the JSON configs in ../config. Pure: no Firebase, no I/O
// beyond reading the config files.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const CONFIG_DIR = path.join(ROOT, 'config');
export const STATE_DIR = path.join(ROOT, 'state');
export const REPORTS_DIR = path.join(ROOT, 'reports');

const FILES = ['stages', 'environments', 'thresholds', 'safety', 'pricing', 'workload'];

export function loadConfig() {
  const cfg = {};
  for (const f of FILES) {
    const p = path.join(CONFIG_DIR, `${f}.json`);
    try {
      cfg[f] = JSON.parse(readFileSync(p, 'utf8'));
    } catch (e) {
      throw new Error(`config/${f}.json: ${e.message}`);
    }
  }
  return cfg;
}

const sum = (xs) => xs.reduce((a, b) => a + b, 0);
const near1 = (x) => Math.abs(x - 1) < 0.011;

/** Returns a list of problems; empty means valid. */
export function validateConfig(cfg) {
  const errs = [];
  const { stages, environments, workload, thresholds, safety, pricing } = cfg;

  for (const [id, s] of Object.entries(stages.stages ?? {})) {
    for (const k of ['users', 'compressedDurationMin', 'maxConcurrency', 'maxOpsPerSec', 'maxRegistrationsPerMin', 'generatorProcesses']) {
      if (!(Number.isFinite(s[k]) && s[k] > 0)) errs.push(`stages.${id}.${k} must be a positive number`);
    }
    if (!environments[s.defaultEnvironment]) errs.push(`stages.${id}.defaultEnvironment '${s.defaultEnvironment}' is not in environments.json`);
    if (!safety.maxReadsPerStage?.[id]) errs.push(`safety.maxReadsPerStage.${id} missing`);
    if (!safety.maxWritesPerStage?.[id]) errs.push(`safety.maxWritesPerStage.${id} missing`);
  }
  const ids = Object.keys(stages.stages ?? {}).map(Number).sort((a, b) => a - b);
  ids.forEach((v, i) => { if (v !== i + 1) errs.push('stage ids must be 1..N with no gaps'); });

  if (environments.production?.enabled || environments.production?.locked !== true) {
    errs.push('environments.production must stay enabled:false, locked:true');
  }
  for (const [name, env] of Object.entries(environments)) {
    if (name.startsWith('$')) continue;
    if (env.projectId === 'giggre-prod' && name !== 'production') errs.push(`environment '${name}' points at giggre-prod`);
  }
  if (environments.emulator && !String(environments.emulator.projectId).startsWith('demo-')) {
    errs.push("emulator projectId must start with 'demo-' so the emulator can never reach a real project");
  }

  if (!near1(workload.roles.worker + workload.roles.host)) errs.push('workload.roles must sum to 1');
  const intents = Object.entries(workload.primaryIntent).filter(([k]) => !k.startsWith('$'));
  if (!near1(sum(intents.map(([, v]) => v)))) errs.push('workload.primaryIntent must sum to 1');
  if (workload.hourlyArrivalWeights.weights.length !== 24) errs.push('hourlyArrivalWeights.weights needs 24 values');
  if (!near1(sum(Object.values(workload.population.sessionsPerUser)))) errs.push('population.sessionsPerUser must sum to 1');
  if (!near1(workload.gigMix.open + workload.gigMix.offered)) errs.push('gigMix open+offered must sum to 1');

  for (const [op, t] of Object.entries(thresholds.latencyP95)) {
    if (!(t.warn <= t.fail)) errs.push(`thresholds.latencyP95.${op}: warn must be <= fail`);
  }
  if (!(pricing.firestore?.readsPer100k > 0)) errs.push('pricing.firestore.readsPer100k missing');
  return errs;
}

/** Smoke test: a tiny emulator-only run that exercises every scenario once
 *  so script bugs surface before an approved stage. Not a stage; no approval. */
export const SMOKE = { users: 12, compressedDurationMin: 3, maxConcurrency: 12, maxOpsPerSec: 20, maxRegistrationsPerMin: 10, generatorProcesses: 1, defaultEnvironment: 'emulator' };

export function smokeConfig(cfg) {
  const c = structuredClone(cfg);
  c.workload.contention = { ...c.workload.contention, raceGigsPerStage: 2, applicantsPerRaceGig: 4 };
  c.workload.sessionLength = { ...c.workload.sessionLength, medianSec: 60, maxSec: 100, thinkTimeSec: [1, 3] };
  c.workload.securityProbeShare = 1;
  // Coverage over realism: enough hosts and every intent so post, select and
  // paired chat delivery all run at least once.
  c.workload.roles = { worker: 0.5, host: 0.5 };
  c.workload.primaryIntent = { browse: 0.1, explore: 0.1, apply: 0.3, chat: 0.25, post: 0.2, register: 0.05 };
  c.workload.intentRoleFit = { worker: { post: 'apply' }, host: { apply: 'manage', browse: 'post' } };
  c.workload.chat = { ...c.workload.chat, pairedDeliveryShare: 1, messagesPerChatSession: [2, 4] };
  c.workload.seedData = { ...c.workload.seedData, existingOpenGigsPerThousandUsers: 500, existingChatRoomsPerThousandUsers: 500, historyMessagesPerRoom: [3, 6] };
  c.workload.population = { ...c.workload.population, newUserShare: 0.2 };
  c.safety = { ...c.safety, rampUpMin: 0, maxReadsPerStage: { ...c.safety.maxReadsPerStage, 0: 200000 }, maxWritesPerStage: { ...c.safety.maxWritesPerStage, 0: 50000 } };
  return c;
}

/** The stage preset after applying CLI overrides. */
export function resolveStage(cfg, stageId, opts = {}) {
  const base = opts.smoke ? SMOKE : cfg.stages.stages[String(stageId)];
  if (opts.smoke) stageId = 0;
  if (!base) throw new Error(`Unknown stage ${stageId}. Known: ${Object.keys(cfg.stages.stages).join(', ')}`);
  const envName = opts.env ?? base.defaultEnvironment;
  const env = cfg.environments[envName];
  if (!env) throw new Error(`Unknown environment '${envName}'`);
  return {
    stage: Number(stageId),
    envName,
    env,
    users: base.users,
    compressedDurationMin: opts.fullDay ? cfg.stages.fullDayMode.compressedDurationMin : (opts.durationMin ?? base.compressedDurationMin),
    maxConcurrency: base.maxConcurrency,
    maxOpsPerSec: base.maxOpsPerSec,
    maxRegistrationsPerMin: base.maxRegistrationsPerMin,
    generatorProcesses: base.generatorProcesses,
    withFunctions: Boolean(opts.withFunctions),
    seed: opts.seed ?? 20261123 + Number(stageId),
  };
}

/** Stable hash of everything that defines what a run will do. An approval is
 *  bound to this hash, so editing any config after approving invalidates it. */
export function planHash(stageSpec, cfg) {
  const material = JSON.stringify({
    stageSpec: { ...stageSpec, env: undefined },
    env: stageSpec.env,
    workload: cfg.workload,
    safety: cfg.safety,
    thresholds: cfg.thresholds,
    pricing: cfg.pricing,
  });
  return createHash('sha256').update(material).digest('hex');
}
