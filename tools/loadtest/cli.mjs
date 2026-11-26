#!/usr/bin/env node
// Giggre load-test CLI. See README.md and .claude/skills/giggre-load-testing/SKILL.md.
//
//   status                          current stage, results, pending approvals (never resumes)
//   validate                        static checks: configs, plans, modules — no Firebase traffic
//   plan     --stage N [opts]       show the schedule, concurrency, usage and cost estimate
//   approve  --stage N [opts]       PERSON ONLY (needs a terminal): mint a single-use approval
//   run      --stage N [opts]       execute one approved stage, then stop and report
//   smoke                           12 users, 3 min, LOCAL EMULATOR ONLY — exercises every scenario; not a stage
//   stop                            emergency stop for a running stage
//   report                          regenerate the cross-stage comparison report
//   emulator [--with-functions]     start the Firebase emulators for the 'emulator' environment
//   cleanup  --env NAME             delete synthetic data (typed confirmation for non-emulator)
//
// opts: --env emulator|staging   --full-day   --with-functions   --seed N
import { spawn, execFileSync, spawnSync } from 'node:child_process';
import { writeFileSync, existsSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { loadConfig, validateConfig, ROOT, STATE_DIR } from './src/config.mjs';
import { buildPlan, formatPlan } from './src/plan.mjs';
import { loadState, saveState, reconcileInterrupted, activeRun, nextStage, stageOrderProblem, logEvent, STOP_FILE } from './src/state.mjs';
import { mintApproval, pendingApprovals, confirmationPhrase } from './src/approval.mjs';
import { guardEnvironment } from './src/runner.mjs';

const args = process.argv.slice(2);
const cmd = args[0];
const flag = (name) => args.includes(`--${name}`);
const opt = (name) => { const i = args.indexOf(`--${name}`); return i >= 0 ? args[i + 1] : undefined; };
const planOpts = () => ({ env: opt('env'), fullDay: flag('full-day'), durationMin: opt('duration-min') ? Number(opt('duration-min')) : undefined, withFunctions: flag('with-functions'), seed: opt('seed') ? Number(opt('seed')) : undefined });
const stageArg = () => { const s = Number(opt('stage')); if (!s) throw new Error('--stage N is required'); return s; };
const log = (...a) => console.log(...a);

async function main() {
  switch (cmd) {
    case 'status': return status();
    case 'validate': return validate();
    case 'plan': return plan();
    case 'approve': return approve();
    case 'run': { const { runStage } = await import('./src/runner.mjs'); await runStage(stageArg(), planOpts()); return; }
    case 'smoke': { const { runStage } = await import('./src/runner.mjs'); await runStage(0, { smoke: true, withFunctions: flag('with-functions') }); return; }
    case 'stop': return stop();
    case 'report': { const { writeComparisonReport } = await import('./src/report.mjs'); log(writeComparisonReport(loadState(), loadConfig())); return; }
    case 'emulator': return emulator();
    case 'cleanup': { const { cleanup } = await import('./src/cleanup.mjs'); await cleanup({ cfg: loadConfig(), envName: opt('env') ?? 'emulator', log }); return; }
    default:
      log(readHelp());
  }
}

function readHelp() {
  return `Usage: node cli.mjs <status|validate|plan|approve|run|stop|report|emulator|cleanup> [--stage N] [--env emulator|staging] [--full-day] [--with-functions]`;
}

function status() {
  const cfg = loadConfig();
  const state = loadState();
  const interrupted = reconcileInterrupted(state);
  const ids = Object.keys(cfg.stages.stages).map(Number);
  log('Giggre load test — status (nothing is resumed automatically)\n');
  if (interrupted) log(`! Run ${interrupted.runId} (stage ${interrupted.stage}) was interrupted. Marked INTERRUPTED; needs a fresh approval to retest.\n`);
  const act = activeRun(state);
  if (act) log(`RUNNING: stage ${act.stage}, run ${act.runId}, pid ${act.pid}, since ${act.startedAt}. Emergency stop: node cli.mjs stop\n`);
  for (const id of ids) {
    const s = state.stages[String(id)];
    const last = s?.runs?.at(-1);
    log(`Stage ${id} (${cfg.stages.stages[id].users.toLocaleString()} users): ${s?.status ?? 'not_started'}${s?.lastResult ? ` — last result ${s.lastResult}` : ''}${last?.reportPath ? `\n    report: ${path.relative(process.cwd(), last.reportPath)}` : ''}`);
  }
  const next = nextStage(state, ids);
  log(`\nNext stage: ${next ?? 'none — all stages completed'}`);
  const pend = pendingApprovals();
  log(pend.length ? `Unused approvals: ${pend.map((a) => `stage ${a.stage} (${a.envName}, expires ${a.expiresAt})`).join('; ')}` : 'Unused approvals: none');
  if (next) log(`To proceed, a person runs:  node cli.mjs plan --stage ${next}   then   node cli.mjs approve --stage ${next}`);
}

function validate() {
  const cfg = loadConfig();
  const problems = validateConfig(cfg);
  const ok = (m) => log(`  ok   ${m}`), bad = (m) => { log(`  FAIL ${m}`); problems.push(m); };
  log('Static validation (no Firebase traffic)\n');
  if (problems.length) problems.forEach((p) => log(`  FAIL ${p}`)); else ok('configs valid');
  for (const f of ['firestore.rules', 'firestore.indexes.json', 'firebase.json']) {
    existsSync(path.join(ROOT, '..', '..', f)) ? ok(`${f} present (emulator loads it)`) : bad(`${f} missing`);
  }
  const src = [path.join(ROOT, 'cli.mjs'), ...readdirSync(path.join(ROOT, 'src')).filter((f) => f.endsWith('.mjs')).map((f) => path.join(ROOT, 'src', f)),
    ...readdirSync(path.join(ROOT, 'src', 'scenarios')).map((f) => path.join(ROOT, 'src', 'scenarios', f))];
  for (const f of src) {
    try { execFileSync(process.execPath, ['--check', f], { stdio: 'pipe' }); } catch (e) { bad(`syntax ${path.relative(ROOT, f)}: ${e.stderr}`); }
  }
  ok(`${src.length} source files parse`);
  for (const id of Object.keys(cfg.stages.stages)) {
    try {
      const { plan, schedule } = buildPlan(cfg, id, {});
      if (schedule.sessions.length < plan.users) bad(`stage ${id}: fewer sessions than users`);
      if (schedule.sessions.some((s, i) => i && s.realStartSec < schedule.sessions[i - 1].realStartSec)) bad(`stage ${id}: schedule unsorted`);
      if (schedule.sessions.at(-1).realStartSec > plan.compressedDurationMin * 60) bad(`stage ${id}: sessions past the end`);
      ok(`stage ${id}: ${plan.users} users → ${plan.sessionsTotal} sessions, peak ${plan.expectedPeakConcurrency} concurrent${plan.concurrencyCapped ? ' (capped)' : ''}, est. ${Math.round(plan.usage.client.reads).toLocaleString()} reads`);
      try { guardEnvironment(plan); ok(`stage ${id}: environment '${plan.envName}' allowed`); } catch (e) { bad(`stage ${id}: ${e.message}`); }
    } catch (e) { bad(`stage ${id}: ${e.message}`); }
  }
  try { guardEnvironment({ envName: 'production', env: cfg.environments.production }); bad('production NOT locked'); } catch { ok('production refused by the runner'); }
  log(problems.length ? `\n${problems.length} problem(s).` : '\nAll static checks passed. No load was generated.');
  process.exitCode = problems.length ? 1 : 0;
}

function plan() {
  const cfg = loadConfig();
  const { plan: p } = buildPlan(cfg, stageArg(), planOpts());
  log(formatPlan(p));
  const state = loadState();
  const order = stageOrderProblem(state, p.stage);
  log(`\nStage order: ${order ?? 'ok'}`);
  try { guardEnvironment(p); } catch (e) { log(`Environment: REFUSED — ${e.message}`); return; }
  log(`\nThis plan needs a person to run, in a terminal:\n  cd tools/loadtest && node cli.mjs approve --stage ${p.stage}${p.envName !== p.env.defaultEnvironment && opt('env') ? ` --env ${p.envName}` : ''}${flag('full-day') ? ' --full-day' : ''}${flag('with-functions') ? ' --with-functions' : ''}${opt('duration-min') ? ` --duration-min ${opt('duration-min')}` : ''}`);
  log(`and type:  ${confirmationPhrase(p)}`);
}

async function approve() {
  const cfg = loadConfig();
  const problems = validateConfig(cfg);
  if (problems.length) throw new Error(`Config invalid; fix before approving:\n  - ${problems.join('\n  - ')}`);
  const state = loadState();
  reconcileInterrupted(state);
  const { plan: p } = buildPlan(cfg, stageArg(), planOpts());
  guardEnvironment(p);
  const order = stageOrderProblem(state, p.stage);
  if (order) throw new Error(order);
  log(formatPlan(p));
  if (p.env.hosts) log('\n  Note: the emulator project is wiped and re-seeded at the start of the run.');
  log(`\n  Approval covers ONE execution of stage ${p.stage} only, expires in ${cfg.safety.approvalTtlMinutes} min, and is void if any config changes.`);
  const { approval, file } = await mintApproval(p, { ttlMinutes: cfg.safety.approvalTtlMinutes });
  logEvent(state, 'approved', { stage: p.stage, env: p.envName, approvalId: approval.approvalId });
  saveState(state);
  log(`\nApproved (single use, until ${approval.expiresAt}).\nStart it with:  node cli.mjs run --stage ${p.stage}${opt('env') ? ` --env ${p.envName}` : ''}${flag('full-day') ? ' --full-day' : ''}${flag('with-functions') ? ' --with-functions' : ''}${opt('duration-min') ? ` --duration-min ${opt('duration-min')}` : ''}\n(${path.relative(process.cwd(), file)})`);
}

function stop() {
  writeFileSync(STOP_FILE, new Date().toISOString());
  const state = loadState();
  const act = activeRun(state);
  if (act) { try { process.kill(act.pid, 'SIGTERM'); } catch { /* gone */ } log(`Stop requested for run ${act.runId} (pid ${act.pid}). The controller stops generators, collects metrics and writes an ABORTED report.`); }
  else log('No active run. Stop flag written anyway; it is cleared when the next approved run starts.');
}

function emulator() {
  const cfg = loadConfig();
  const env = cfg.environments.emulator;
  const only = flag('with-functions') ? 'auth,firestore,functions' : 'auth,firestore';
  // firebase-tools requires a JDK; Android Studio bundles a compatible one (JBR) we can fall
  // back to when the system `java` is missing or too old.
  const MIN_JAVA = 21;
  const jbrCandidates = process.platform === 'win32'
    ? ['C:\\Program Files\\Android\\Android Studio\\jbr']
    : ['/Applications/Android Studio.app/Contents/jbr/Contents/Home'];
  const childEnv = { ...process.env };
  const sysJava = spawnSync('java', ['-version'], { encoding: 'utf8' });
  const versionMatch = `${sysJava.stdout || ''}${sysJava.stderr || ''}`.match(/version "(\d+)(?:\.(\d+))?/);
  const sysJavaMajor = versionMatch ? (versionMatch[1] === '1' ? Number(versionMatch[2]) : Number(versionMatch[1])) : null;
  if (sysJavaMajor == null || sysJavaMajor < MIN_JAVA) {
    const jbr = jbrCandidates.find(existsSync);
    if (jbr) {
      childEnv.JAVA_HOME = jbr;
      childEnv.PATH = `${path.join(jbr, 'bin')}${path.delimiter}${childEnv.PATH}`;
      log(`System Java (${sysJavaMajor ?? 'not found'}) is below the required ${MIN_JAVA}; using Android Studio's JDK: ${jbr}`);
    } else {
      log(`Warning: system Java is ${sysJavaMajor ?? 'not found'}, but firebase-tools requires ${MIN_JAVA}+. No Android Studio JDK found at ${jbrCandidates.join(' or ')} — the emulator will likely fail to start.`);
    }
  }
  if (flag('with-functions')) {
    log('Building functions (npm --prefix functions run build)...');
    execFileSync('npm', ['--prefix', path.join(ROOT, '..', '..', 'functions'), 'run', 'build'], { stdio: 'inherit' });
  }
  log(`Starting emulators (${only}) for ${env.projectId} with firestore.rules from the repo. Ctrl-C to stop; data is in memory only.`);
  // Own config (repo-root firebase.loadtest.json — the CLI only loads rules
  // from inside the config's folder): same rules/indexes/functions as the app,
  // plus the auth + emulator sections the app's firebase.json doesn't have.
  // The app's firebase.json is never touched.
  const child = spawn('firebase', ['emulators:start', '--config', 'firebase.loadtest.json', '--project', env.projectId, '--only', only], { cwd: path.join(ROOT, '..', '..'), env: childEnv, stdio: 'inherit', shell: process.platform === 'win32' });
  child.on('exit', (c) => process.exit(c ?? 0));
}

main().catch((e) => { console.error(`\nError: ${e.message}`); process.exitCode = 1; });
