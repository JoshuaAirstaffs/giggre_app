// Persistent local test state (tools/loadtest/state/state.json, gitignored).
// Holds no secrets: stage progress, report paths, approval ids (spent), run
// metadata. Never resumes anything by itself; an orphaned "running" entry
// is marked "interrupted" and needs a fresh approval.
import { readFileSync, writeFileSync, mkdirSync, existsSync, renameSync } from 'node:fs';
import path from 'node:path';
import { STATE_DIR } from './config.mjs';

const STATE_FILE = path.join(STATE_DIR, 'state.json');
export const STOP_FILE = path.join(STATE_DIR, 'STOP');

const empty = () => ({
  version: 1,
  createdAt: new Date().toISOString(),
  stages: {},          // "1": { status, lastResult, runs: [...] }
  current: null,       // { runId, stage, pid, startedAt, envName }
  usedApprovalIds: [],
  events: [],          // append-only audit trail (short)
});

export function loadState() {
  mkdirSync(STATE_DIR, { recursive: true });
  if (!existsSync(STATE_FILE)) return empty();
  return JSON.parse(readFileSync(STATE_FILE, 'utf8'));
}

export function saveState(state) {
  mkdirSync(STATE_DIR, { recursive: true });
  const tmp = `${STATE_FILE}.tmp`;
  writeFileSync(tmp, JSON.stringify(state, null, 2));
  renameSync(tmp, STATE_FILE); // atomic on the same filesystem
}

export function logEvent(state, type, detail = {}) {
  state.events.push({ at: new Date().toISOString(), type, ...detail });
  if (state.events.length > 500) state.events = state.events.slice(-500);
}

export function stageEntry(state, stage) {
  const k = String(stage);
  state.stages[k] ??= { status: 'not_started', lastResult: null, runs: [] };
  return state.stages[k];
}

const pidAlive = (pid) => {
  try { process.kill(pid, 0); return true; } catch { return false; }
};

/** If a run was in progress but its process is gone (crash, reboot, closed
 *  terminal), mark it interrupted. Does NOT restart it. Returns the run that
 *  was reconciled, or null. */
export function reconcileInterrupted(state) {
  const cur = state.current;
  if (!cur || pidAlive(cur.pid)) return null;
  const st = stageEntry(state, cur.stage);
  const run = st.runs.find((r) => r.runId === cur.runId);
  if (run && !run.endedAt) {
    run.endedAt = new Date().toISOString();
    run.result = 'INTERRUPTED';
  }
  st.status = 'interrupted';
  st.lastResult = 'INTERRUPTED';
  state.current = null;
  logEvent(state, 'run_interrupted', { runId: cur.runId, stage: cur.stage });
  saveState(state);
  return cur;
}

export function activeRun(state) {
  const cur = state.current;
  return cur && pidAlive(cur.pid) ? cur : null;
}

/** Next stage the user could approve, plus why. */
export function nextStage(state, stageIds) {
  for (const id of stageIds) {
    const s = state.stages[String(id)];
    if (!s || s.status !== 'completed') return id;
  }
  return null;
}

/** Ordering rule enforced by the runner: stage N needs stage N-1 completed
 *  (any result — the human decides via approval whether to go on after a
 *  WARNING/FAIL). Repeating a completed stage (RETEST) is allowed. */
export function stageOrderProblem(state, stage) {
  if (stage <= 1) return null;
  const prev = state.stages[String(stage - 1)];
  if (!prev || prev.status !== 'completed') {
    return `Stage ${stage} requires stage ${stage - 1} to be completed first (it is '${prev?.status ?? 'not_started'}').`;
  }
  return null;
}
