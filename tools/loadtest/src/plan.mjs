// Builds the deterministic schedule for a stage (who arrives when, doing
// what), computes the expected peak concurrency, and estimates Firestore /
// Functions / Maps usage and cost. `plan` and `approve` show this; `run`
// executes exactly this schedule. No Firebase access.
import { rng, identity } from './synthetic.mjs';
import { planHash, resolveStage } from './config.mjs';
import { estimateUsage } from './costModel.mjs';

const DAY = 86_400;

function pickIntent(r, workload, role, isRegistration) {
  if (isRegistration) return 'register';
  let intent = r.weighted(workload.primaryIntent);
  if (intent === 'register') intent = 'explore'; // returning users don't re-register
  return workload.intentRoleFit[role]?.[intent] ?? intent;
}

/** Full schedule: one entry per session, sorted by real start time. */
export function buildSchedule(spec, cfg) {
  const { workload, safety } = cfg;
  const r = rng(spec.seed);
  const realDurationSec = spec.compressedDurationMin * 60;
  const scale = realDurationSec / DAY; // real seconds per simulated second
  const weights = workload.hourlyArrivalWeights.weights;
  const sl = workload.sessionLength;
  const sessions = [];
  const users = [];

  for (let i = 0; i < spec.users; i++) {
    const id = identity({ seed: spec.seed, index: i, roles: workload.roles, emailDomain: safety.syntheticEmailDomain, runTag: `s${spec.stage}` });
    const isNew = r.chance(workload.population.newUserShare);
    const nSessions = Number(r.weighted(workload.population.sessionsPerUser));
    users.push({ index: i, role: id.role, isNew, sessions: nSessions });
    const starts = [];
    for (let s = 0; s < nSessions; s++) {
      const hour = Number(r.weighted(Object.fromEntries(weights.map((w, h) => [h, w]))));
      starts.push(hour * 3600 + r.float(0, 3600));
    }
    starts.sort((a, b) => a - b);
    starts.forEach((simStartSec, s) => {
      const dur = Math.min(sl.maxSec, Math.max(30, r.lognormal(sl.medianSec, sl.sigma)));
      sessions.push({
        user: i,
        role: id.role,
        seq: s,
        intent: pickIntent(r, workload, id.role, isNew && s === 0),
        simStartSec,
        realStartSec: simStartSec * scale,
        realDurationSec: dur,
        sessionSeed: (spec.seed * 7919 + i * 131 + s) >>> 0,
      });
    });
  }
  sessions.sort((a, b) => a.realStartSec - b.realStartSec);
  return { users, sessions, scale, realDurationSec };
}

/** Peak simultaneous sessions if nothing were capped, and per-minute arrivals. */
export function concurrencyProfile(sessions, realDurationSec) {
  const ev = [];
  for (const s of sessions) { ev.push([s.realStartSec, 1]); ev.push([s.realStartSec + s.realDurationSec, -1]); }
  ev.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  let cur = 0, peak = 0, peakAt = 0;
  for (const [t, d] of ev) { cur += d; if (cur > peak) { peak = cur; peakAt = t; } }
  const buckets = Math.max(1, Math.ceil(realDurationSec / 60));
  const arrivalsPerMin = new Array(buckets).fill(0);
  for (const s of sessions) arrivalsPerMin[Math.min(buckets - 1, Math.floor(s.realStartSec / 60))]++;
  return { peak, peakAtSec: peakAt, arrivalsPerMin, peakArrivalsPerMin: Math.max(...arrivalsPerMin) };
}

export function buildPlan(cfg, stageId, opts = {}) {
  const spec = resolveStage(cfg, stageId, opts);
  const schedule = buildSchedule(spec, cfg);
  const conc = concurrencyProfile(schedule.sessions, schedule.realDurationSec);
  // Same sessions on an uncompressed 24 h clock = what production would see.
  const realWorld = concurrencyProfile(schedule.sessions.map((s) => ({ realStartSec: s.simStartSec, realDurationSec: s.realDurationSec })), 86_400);
  const intents = {};
  for (const s of schedule.sessions) intents[`${s.role}:${s.intent}`] = (intents[`${s.role}:${s.intent}`] ?? 0) + 1;
  const roleCount = { worker: 0, host: 0 };
  for (const u of schedule.users) roleCount[u.role]++;
  const usage = estimateUsage({ spec, cfg, schedule, conc, intents, roleCount });
  // The same day at production pace (24 h, uncapped): what Giggre would pay daily.
  const prodDay = estimateUsage({
    spec: { ...spec, maxConcurrency: Infinity, env: { ...spec.env, billable: true } },
    cfg, schedule: { ...schedule, realDurationSec: 86_400 }, conc: realWorld, intents, roleCount,
  });
  usage.productionDay = {
    reads: prodDay.client.reads,
    writes: prodDay.client.writes - prodDay.client.setupWrites,
    functionReads: prodDay.functions.reads,
    usd: prodDay.cost.equivalentUsd,
  };

  const plan = {
    ...spec,
    hash: planHash(spec, cfg),
    sessionsTotal: schedule.sessions.length,
    newUsers: schedule.users.filter((u) => u.isNew).length,
    roleCount,
    intents,
    expectedPeakConcurrency: conc.peak,
    realWorldPeakConcurrency: realWorld.peak,
    stressFactor: Math.round((conc.peak / Math.max(1, realWorld.peak)) * 10) / 10,
    effectivePeakConcurrency: Math.min(conc.peak, spec.maxConcurrency),
    concurrencyCapped: conc.peak > spec.maxConcurrency,
    peakArrivalsPerMin: conc.peakArrivalsPerMin,
    arrivalsPerMin: conc.arrivalsPerMin,
    timeScale: `1 real min = ${(1 / schedule.scale).toFixed(1)} simulated min; sessions themselves run in real time`,
    usage,
    cost: usage.cost,
    limits: {
      maxReads: cfg.safety.maxReadsPerStage[String(spec.stage)],
      maxWrites: cfg.safety.maxWritesPerStage[String(spec.stage)],
      maxRunMinutes: spec.compressedDurationMin + cfg.safety.maxRunMinutesOverPlan,
    },
  };
  return { plan, schedule };
}

const fmt = (n) => Math.round(n).toLocaleString('en-US');

export function formatPlan(plan) {
  const u = plan.usage;
  const lines = [
    `Stage ${plan.stage} plan  (hash ${plan.hash.slice(0, 12)})`,
    `  Environment          : ${plan.envName} (${plan.env.projectId})${plan.env.billable ? '  ** BILLABLE **' : '  (local emulator, no billing)'}`,
    `  Unique daily users   : ${fmt(plan.users)}  (workers ${fmt(plan.roleCount.worker)}, hosts ${fmt(plan.roleCount.host)}, new registrations ${fmt(plan.newUsers)})`,
    `  Sessions in the day  : ${fmt(plan.sessionsTotal)}`,
    `  Real duration        : ${plan.compressedDurationMin} min  (${plan.timeScale})`,
    `  Peak concurrent      : ${fmt(plan.expectedPeakConcurrency)} expected` + (plan.concurrencyCapped ? `, CAPPED to ${plan.maxConcurrency} (excess sessions queue and are reported)` : ` (cap ${plan.maxConcurrency})`),
    `  Real-world peak      : ~${fmt(plan.realWorldPeakConcurrency)} concurrent if the same day ran over 24 h → this test is ~${plan.stressFactor}x that peak`,
    `  Peak arrivals        : ${fmt(plan.peakArrivalsPerMin)} sessions/min`,
    `  Rate limits          : ${plan.maxOpsPerSec} ops/s, ${plan.maxRegistrationsPerMin} registrations/min, ramp-up over first minutes`,
    `  Functions emulated   : ${plan.withFunctions ? 'yes (server-side trigger load measured)' : 'no (trigger cost estimated only)'}`,
    `  Intents              : ${Object.entries(plan.intents).sort().map(([k, v]) => `${k}=${fmt(v)}`).join(', ')}`,
    '',
    '  Estimated usage (client SDK, from the cost model — see docs/architecture-audit.md):',
    `    Firestore reads    : ${fmt(u.client.reads)}  (browse listener alone ${fmt(u.client.breakdown.browse ?? 0)})`,
    `    Firestore writes   : ${fmt(u.client.writes)}`,
    `    Functions invocations (if deployed triggers ran): ${fmt(u.functions.invocations)}, their reads ${fmt(u.functions.reads)} (onOpenGigPosted ${fmt(u.functions.breakdown.onOpenGigPosted ?? 0)})`,
    `    Google Maps Platform requests sent by this test: 0`,
    `  Hard safety limits   : reads ${fmt(plan.limits.maxReads)}, writes ${fmt(plan.limits.maxWrites)}, run time ${plan.limits.maxRunMinutes} min`,
    `  Estimated cost       : $${plan.cost.estimateUsd.toFixed(2)} if billed; ceiling for approval $${plan.cost.maxUsd.toFixed(2)}` +
      (plan.env.billable ? '' : `  (emulator: actual $0.00; equivalent cloud cost ~$${plan.cost.equivalentUsd.toFixed(2)})`),
    `  Same day in production (24 h pace): ~${fmt(u.productionDay.reads)} client reads, ~${fmt(u.productionDay.functionReads)} function reads, ~$${u.productionDay.usd.toFixed(2)}/day [estimate]`,
    `  Pricing verified on  : ${plan.cost.pricingVerifiedOn}`,
  ];
  if (plan.env.warnings?.length) lines.push('', '  Environment warnings:', ...plan.env.warnings.map((w) => `    ! ${w}`));
  return lines.join('\n');
}
