// Load generator process (forked by runner.mjs). Runs its share of the
// schedule: starts each session at its planned real time, never more than its
// concurrency share at once (excess sessions wait and are counted as queued),
// and streams metric snapshots to the controller. Never started directly.
import { monitorEventLoopDelay } from 'node:perf_hooks';
import os from 'node:os';
import { loadConfig, smokeConfig } from './config.mjs';
import { buildPlan } from './plan.mjs';
import { Metrics } from './metrics.mjs';
import { Limiter, PerMinute, stopRequested } from './safety.mjs';
import { loadPopulation, passwordFn } from './seed.mjs';
import { runSession } from './scenarios/session.mjs';
import { runRaces } from './scenarios/race.mjs';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const send = (msg) => process.send?.(msg);
const log = (text) => send({ type: 'log', text: `[gen${process.env.LT_GEN_INDEX}] ${text}` });

async function main(job) {
  const cfg = job.planOpts?.smoke ? smokeConfig(loadConfig()) : loadConfig();
  const { plan, schedule } = buildPlan(cfg, job.stage, job.planOpts);
  if (plan.hash !== job.planHash) throw new Error('plan hash mismatch between controller and generator');
  const P = plan.generatorProcesses, me = job.index;
  const mine = schedule.sessions.filter((_, i) => i % P === me);
  const maxConc = Math.ceil(plan.maxConcurrency / P);

  const m = new Metrics();
  const world = {
    cfg, plan, env: plan.env, runId: job.runId, m,
    limiter: new Limiter(plan.maxOpsPerSec / P, cfg.safety.rampUpMin * 60),
    regLimiter: new PerMinute(Math.max(1, Math.floor(plan.maxRegistrationsPerMin / P))),
    population: loadPopulation(plan.envName, plan.stage),
    password: passwordFn(plan.env),
    active: new Map(), pendingVisibility: new Map(), applications: [], assignments: [],
    createdGigs: [], sentMessages: [], stopping: false,
  };
  if (!world.population) throw new Error('population file missing; seeding did not run');

  // Generator self-monitoring: if this process is saturated, latency numbers
  // are inflated by the generator, not the backend.
  const loop = monitorEventLoopDelay({ resolution: 20 }); loop.enable();
  let lastCpu = process.cpuUsage(), lastT = Date.now();
  const res = { cpuPct: [], loopP99: [], rssMb: [] };
  const sampleRes = () => {
    const c = process.cpuUsage(lastCpu), now = Date.now();
    res.cpuPct.push(((c.user + c.system) / 1000 / (now - lastT)) * 100);
    res.loopP99.push(loop.percentile(99) / 1e6);
    res.rssMb.push(process.memoryUsage().rss / 1e6);
    lastCpu = process.cpuUsage(); lastT = now; loop.reset();
  };

  const stopAll = () => { world.stopping = true; world.limiter.stopped = true; };
  process.on('message', (msg) => { if (msg?.type === 'stop') stopAll(); });

  const reporter = setInterval(() => {
    if (stopRequested()) stopAll();
    sampleRes(); m.noteActive();
    send({ type: 'metrics', snapshot: m.toJSON(), window: m.windowErrorRate(cfg.safety.errorRateWindowSec), res: lastRes(res) });
  }, 5000);

  const t0 = Date.now();
  if (me === 0 && cfg.workload.contention.raceGigsPerStage > 0) {
    setTimeout(() => runRaces(world, log).catch((e) => log(`race failed: ${e.message}`)), plan.compressedDurationMin * 60_000 * 0.3);
  }

  const running = new Set();
  for (const s of mine) {
    if (world.stopping) break;
    const wait = t0 + s.realStartSec * 1000 - Date.now();
    if (wait > 0) await sleep(wait);
    if (running.size >= maxConc) m.queued++;
    while (running.size >= maxConc && !world.stopping) await Promise.race(running);
    if (world.stopping) break;
    const p = runSession(world, s).finally(() => running.delete(p));
    running.add(p);
  }
  await Promise.all(running);
  clearInterval(reporter);
  sampleRes();
  send({
    type: 'done',
    snapshot: m.toJSON(),
    res,
    world: {
      createdGigs: world.createdGigs, sentMessages: world.sentMessages.slice(0, 5000),
      applications: world.applications.length, assignments: world.assignments,
    },
    stopped: world.stopping,
  });
}

const lastRes = (r) => ({ cpuPct: r.cpuPct.at(-1) ?? 0, loopP99: r.loopP99.at(-1) ?? 0, rssMb: r.rssMb.at(-1) ?? 0, cores: os.cpus().length });

process.once('message', (job) => {
  main(job).then(() => process.exit(0)).catch((e) => { send({ type: 'fatal', error: e.stack ?? String(e) }); process.exit(1); });
});
