// Stage execution controller. The ONLY code path that generates load.
//
// Order of operations (each step can refuse; nothing is generated before the
// gate passes):
//   1. reconcile interrupted runs, refuse if another run is active
//   2. build the plan, refuse locked/disabled environments
//   3. refuse wrong stage order
//   4. verify + consume the single-use, plan-bound approval
//   5. seed, fork generators, watch abort conditions every 5 s
//   6. stop, collect, consistency checks, verdict, report, state
//   7. print the next-stage question — never start it
import { fork, execFileSync, spawn } from 'node:child_process';
import { writeFileSync, mkdirSync, existsSync, unlinkSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadConfig, validateConfig, smokeConfig, REPORTS_DIR } from './config.mjs';
import { buildPlan } from './plan.mjs';
import { loadState, saveState, stageEntry, logEvent, reconcileInterrupted, activeRun, stageOrderProblem, STOP_FILE } from './state.mjs';
import { checkApproval, consumeApproval } from './approval.mjs';
import { mergeSnapshots, percentiles } from './metrics.mjs';
import { checkAbort } from './safety.mjs';
import { seedStage } from './seed.mjs';
import { emulatorUp, wipeEmulator } from './rest.mjs';
import { consistencyChecks, evaluate } from './analyze.mjs';
import { writeStageReport, writeComparisonReport, nextPrompt } from './report.mjs';
import { priceMeasured } from './costModel.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const AUDIT = 'tools/loadtest/docs/architecture-audit.md';
const log = (...a) => console.log(`[${new Date().toISOString().slice(11, 19)}]`, ...a);

function findListenerPid(port) {
  try { return Number(execFileSync('lsof', ['-ti', `tcp:${port}`, '-sTCP:LISTEN'], { encoding: 'utf8' }).split('\n')[0]) || null; } catch { return null; }
}

function sampleProcess(pid) {
  try {
    const [cpu, rss] = execFileSync('ps', ['-o', '%cpu=,rss=', '-p', String(pid)], { encoding: 'utf8' }).trim().split(/\s+/).map(Number);
    return { cpu, rssMb: rss / 1024 };
  } catch { return null; }
}

export function guardEnvironment(plan) {
  if (plan.envName === 'production' || plan.env.locked || plan.env.projectId === 'giggre-prod') {
    throw new Error('Production is locked. The load tester never runs against giggre-prod.');
  }
  if (!plan.env.enabled) throw new Error(`Environment '${plan.envName}' is disabled in config/environments.json.`);
}

export async function runStage(stage, opts) {
  const cfg = opts.smoke ? smokeConfig(loadConfig()) : loadConfig();
  const problems = validateConfig(cfg);
  if (problems.length) throw new Error(`Config invalid:\n  - ${problems.join('\n  - ')}`);
  const state = loadState();
  const interrupted = reconcileInterrupted(state);
  if (interrupted) log(`Previous run ${interrupted.runId} (stage ${interrupted.stage}) was interrupted and has been marked so. It will not resume.`);
  const busy = activeRun(state);
  if (busy) throw new Error(`Run ${busy.runId} (stage ${busy.stage}) is still active (pid ${busy.pid}). Stop it first: node cli.mjs stop`);

  const { plan, schedule } = buildPlan(cfg, stage, opts);
  guardEnvironment(plan);
  let approvalRef = null;
  if (opts.smoke) {
    // Smoke: 12 users on the local emulator only. Not a stage; no approval.
    if (!plan.env.hosts || !plan.env.projectId.startsWith('demo-')) throw new Error('smoke runs only against the local emulator');
  } else {
    const order = stageOrderProblem(state, plan.stage);
    if (order) throw new Error(order);
    approvalRef = checkApproval(plan, state); // throws if missing/stale/used/mismatched
  }

  if (plan.env.hosts && !(await emulatorUp(plan.env))) {
    throw new Error('Firebase emulators are not reachable. Start them first: node cli.mjs emulator (in a separate terminal). The approval was NOT used.');
  }

  // Gate passed: spend the approval and record the run before any load.
  const runId = `${new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14)}-s${plan.stage}-${randomBytes(3).toString('hex')}`;
  if (approvalRef) consumeApproval(state, approvalRef);
  const st = stageEntry(state, opts.smoke ? 'smoke' : plan.stage);
  const run = { runId, envName: plan.envName, planHash: plan.hash, approvalId: approvalRef?.approval.approvalId ?? 'smoke (no approval needed)', startedAt: new Date().toISOString(), endedAt: null, result: null };
  st.runs.push(run);
  st.status = 'running';
  state.current = { runId, stage: opts.smoke ? 'smoke' : plan.stage, pid: process.pid, startedAt: run.startedAt, envName: plan.envName };
  logEvent(state, 'run_started', { runId, stage: plan.stage, env: plan.envName, approvalId: run.approvalId });
  saveState(state);
  if (existsSync(STOP_FILE)) unlinkSync(STOP_FILE);
  // Keep the Mac awake for exactly this run: idle sleep froze a stage for
  // 30 min (2026-11-23) and then released every queued session at once.
  // caffeinate -w exits by itself when this process does.
  if (process.platform === 'darwin') {
    try { spawn('caffeinate', ['-i', '-s', '-w', String(process.pid)], { stdio: 'ignore', detached: true }).unref(); log('Sleep prevention on for this run (caffeinate).'); }
    catch { log('WARNING: could not start caffeinate; keep the Mac awake manually.'); }
  }

  let abortReason = null;
  const gens = [];
  const resources = [];
  const emulator = { cpuPct: [], rssMb: [] };
  let setup = null;
  const onSignal = () => { abortReason ??= 'Stopped by operator (stop command or Ctrl-C)'; for (const g of gens) g.child.connected && g.child.send({ type: 'stop' }); };
  process.on('SIGINT', onSignal);
  process.on('SIGTERM', onSignal);

  try {
    if (plan.env.hosts) { log('Wiping the emulator (isolated demo project)...'); await wipeEmulator(plan.env); }
    log('Seeding...');
    const seeded = await seedStage({ plan, schedule, cfg, env: plan.env, runId, log });
    setup = { counters: seeded.counters, gigs: seeded.population.gigs?.length, rooms: seeded.population.rooms?.length };
    if (seeded.counters.failures > seeded.counters.authAccounts * 0.02) throw new Error(`Seeding had ${seeded.counters.failures} failures; aborting before load.`);

    log(`Starting ${plan.generatorProcesses} generator process(es); ${plan.sessionsTotal} sessions over ${plan.compressedDurationMin} min.`);
    for (let i = 0; i < plan.generatorProcesses; i++) {
      const child = fork(path.join(HERE, 'generator.mjs'), [], { env: { ...process.env, LT_GEN_INDEX: String(i) }, stdio: ['ignore', 'inherit', 'inherit', 'ipc'] });
      const g = { child, snapshot: null, window: { n: 0, rate: 0 }, res: null, done: null };
      gens.push(g);
      child.on('message', (msg) => {
        if (msg.type === 'metrics') { g.snapshot = msg.snapshot; g.window = msg.window; resources[i] = { ...(resources[i] ?? { cpuPct: [], loopP99: [], rssMb: [] }), cores: msg.res.cores }; resources[i].cpuPct.push(msg.res.cpuPct); resources[i].loopP99.push(msg.res.loopP99); resources[i].rssMb.push(msg.res.rssMb); }
        else if (msg.type === 'done') { g.done = msg; g.snapshot = msg.snapshot; }
        else if (msg.type === 'log') log(msg.text);
        else if (msg.type === 'fatal') { abortReason ??= `Generator ${i} crashed: ${msg.error.split('\n')[0]}`; log(msg.error); }
      });
      child.send({ index: i, stage: plan.stage, planOpts: opts, planHash: plan.hash, runId });
    }

    // Emulator self-monitoring: if the emulator JVM is pegged, slow numbers
    // describe the emulator, not the app or Cloud Firestore.
    const emuPid = plan.env.hosts ? findListenerPid(plan.env.hosts.firestore.split(':')[1]) : null;
    const t0 = Date.now();
    const exited = gens.map((g) => new Promise((r) => g.child.on('exit', r)));
    let finished = false;
    Promise.all(exited).then(() => { finished = true; });
    while (!finished) {
      await new Promise((r) => setTimeout(r, 5000));
      const snaps = gens.map((g) => g.snapshot).filter(Boolean);
      if (!snaps.length) continue;
      const live = mergeSnapshots(snaps);
      const win = gens.reduce((a, g) => ({ n: a.n + g.window.n, err: a.err + g.window.rate * g.window.n }), { n: 0, err: 0 });
      live.window = { n: win.n, rate: win.n ? win.err / win.n : 0 };
      live.p95 = Object.fromEntries(Object.entries(live.ops).map(([k, o]) => [k, o.latency?.p95 ?? null]));
      live.opCounts = Object.fromEntries(Object.entries(live.ops).map(([k, o]) => [k, o.ok + o.expected + o.unexpected]));
      const elapsedMin = (Date.now() - t0) / 60000;
      const es = emuPid ? sampleProcess(emuPid) : null;
      if (es) { emulator.cpuPct.push(es.cpu); emulator.rssMb.push(es.rssMb); }
      const measuredCostUsd = priceMeasured(cfg.pricing, live.counters);
      log(`t+${elapsedMin.toFixed(1)}m sessions ${live.sessions.started} (active ≤${live.peakActive}) reads ${live.counters.reads} writes ${live.counters.writes} err ${(live.window.rate * 100).toFixed(2)}%${es ? ` emulatorCPU ${Math.round(es.cpu)}%` : ''}`);
      const reason = abortReason ?? checkAbort({ live, plan, safety: cfg.safety, elapsedMin, measuredCostUsd });
      if (reason && !abortReason) abortReason = reason;
      if (reason) {
        log(`STOPPING: ${reason}`);
        for (const g of gens) if (g.child.connected) g.child.send({ type: 'stop' });
        const killAt = Date.now() + 60_000;
        while (!finished && Date.now() < killAt) await new Promise((r) => setTimeout(r, 1000));
        for (const g of gens) if (g.child.exitCode === null) g.child.kill('SIGKILL');
        break;
      }
    }
    await Promise.allSettled(exited);
  } catch (e) {
    abortReason ??= e.message;
    log(`Run failed: ${e.message}`);
    for (const g of gens) if (g.child.exitCode === null) g.child.kill('SIGKILL');
  } finally {
    process.off('SIGINT', onSignal);
    process.off('SIGTERM', onSignal);
  }

  // Collect whatever exists — an aborted stage still gets a report.
  const merged = mergeSnapshots(gens.map((g) => g.snapshot).filter(Boolean));
  for (const g of gens) if (g.done?.res) Object.assign(resources[gens.indexOf(g)] ?? {}, g.done.res);
  let consistency = {};
  try {
    const { loadPopulation, passwordFn } = await import('./seed.mjs');
    const population = loadPopulation(plan.envName, plan.stage);
    if (population && gens.some((g) => g.done)) {
      consistency = await consistencyChecks({ env: plan.env, population, password: passwordFn(plan.env), gens: gens.map((g) => g.done ?? {}), log });
    }
  } catch (e) { log(`consistency checks failed to run: ${e.message}`); }
  const evaluation = evaluate({ merged, checks: consistency, thresholds: cfg.thresholds, resources: resources.filter(Boolean), emulator, aborted: abortReason, isEmulator: Boolean(plan.env.hosts) });

  run.endedAt = new Date().toISOString();
  run.result = abortReason ? 'ABORTED' : evaluation.verdict;
  run.abortReason = abortReason;
  mkdirSync(path.join(REPORTS_DIR, 'raw'), { recursive: true });
  run.rawPath = path.join(REPORTS_DIR, 'raw', `${runId}.json`);
  writeFileSync(run.rawPath, JSON.stringify({ plan: { ...plan, arrivalsPerMin: undefined }, merged, evaluation, setup, run, emulator }, null, 1));
  const stageIds = Object.keys(cfg.stages.stages).map(Number);
  run.reportPath = writeStageReport({ plan, merged, evaluation, consistency, resources: resources.filter(Boolean), run, cfg, setup, stageIds, auditPath: AUDIT });

  const fresh = loadState();
  const fst = stageEntry(fresh, opts.smoke ? 'smoke' : plan.stage);
  const idx = fst.runs.findIndex((r) => r.runId === runId);
  if (idx >= 0) fst.runs[idx] = run; else fst.runs.push(run);
  fst.status = abortReason ? 'aborted' : 'completed';
  fst.lastResult = run.result;
  fresh.current = null;
  logEvent(fresh, abortReason ? 'run_aborted' : 'run_completed', { runId, stage: plan.stage, result: run.result });
  saveState(fresh);
  const cmp = writeComparisonReport(fresh, cfg);

  console.log(`\nReport: ${run.reportPath}\nComparison: ${cmp}\n`);
  if (opts.smoke) { console.log(`Smoke run finished: ${run.result}. This was not a stage and approves nothing.`); return run; }
  console.log(nextPrompt(plan.stage, abortReason ? 'FAIL' : evaluation.verdict, stageIds));
  console.log('\n(No further stage will start. Each stage needs its own approval: node cli.mjs approve --stage N)');
  return run;
}

export { percentiles };
