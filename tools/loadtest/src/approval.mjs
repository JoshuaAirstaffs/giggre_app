// Programmatic approval gate.
//
// `approve` mints a single-use approval for ONE stage, bound to the exact plan
// (hash of stage preset + environment + workload + safety + thresholds +
// pricing). It only works from an interactive terminal: it opens /dev/tty and
// asks the person to type a confirmation phrase that spells out the stage,
// environment, user count and cost ceiling. An agent's non-interactive shell
// has no controlling terminal, so it cannot mint one.
//
// `run` refuses unless it finds an approval that: matches the stage, matches
// the current plan hash, has not expired, and has not been used. It marks the
// approval spent before generating any load. Nothing here stores a reusable
// credential: each approval authorises exactly one execution of one stage.
//
// Honest limit: this stops accidental and stale runs. It is not a security
// boundary against someone who can edit files in this repo.
import { writeFileSync, readFileSync, readdirSync, mkdirSync, existsSync, unlinkSync } from 'node:fs';
import { askOnTty, normalizeTyped } from './tty.mjs';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { STATE_DIR } from './config.mjs';

const APPROVALS_DIR = path.join(STATE_DIR, 'approvals');

export function confirmationPhrase(plan) {
  return `APPROVE STAGE ${plan.stage} ${plan.envName.toUpperCase()} ${plan.users} USERS MAX $${plan.cost.maxUsd.toFixed(2)}`;
}

export async function mintApproval(plan, { ttlMinutes }) {
  const phrase = confirmationPhrase(plan);
  const typed = await askOnTty(
    `\nTo approve exactly this run, type:\n\n  ${phrase}\n\n> `,
  );
  if (normalizeTyped(typed) !== normalizeTyped(phrase)) {
    throw new Error(`Phrase did not match. Nothing was approved.\n  expected: ${phrase}\n  got:      ${normalizeTyped(typed) || '(nothing)'}`);
  }
  const now = Date.now();
  const approval = {
    approvalId: randomUUID(),
    stage: plan.stage,
    envName: plan.envName,
    projectId: plan.env.projectId,
    users: plan.users,
    compressedDurationMin: plan.compressedDurationMin,
    maxConcurrency: plan.maxConcurrency,
    maxOpsPerSec: plan.maxOpsPerSec,
    estimatedMaxCostUsd: plan.cost.maxUsd,
    planHash: plan.hash,
    approvedVia: 'tty-phrase',
    phrase,
    createdAt: new Date(now).toISOString(),
    expiresAt: new Date(now + ttlMinutes * 60_000).toISOString(),
  };
  mkdirSync(APPROVALS_DIR, { recursive: true });
  // Only one live approval per stage: a new one replaces older unused ones.
  for (const f of listApprovalFiles()) {
    const a = readApproval(f);
    if (a?.stage === plan.stage) unlinkSync(f);
  }
  const file = path.join(APPROVALS_DIR, `stage-${plan.stage}-${approval.approvalId}.json`);
  writeFileSync(file, JSON.stringify(approval, null, 2), { mode: 0o600 });
  return { approval, file };
}

function listApprovalFiles() {
  if (!existsSync(APPROVALS_DIR)) return [];
  return readdirSync(APPROVALS_DIR).filter((f) => f.endsWith('.json')).map((f) => path.join(APPROVALS_DIR, f));
}

function readApproval(file) {
  try { return JSON.parse(readFileSync(file, 'utf8')); } catch { return null; }
}

/** Finds and checks the approval for this plan. Returns {approval, file} or
 *  throws with every reason it is not valid. */
export function checkApproval(plan, state) {
  const candidates = listApprovalFiles()
    .map((file) => ({ file, approval: readApproval(file) }))
    .filter((c) => c.approval?.stage === plan.stage);
  if (candidates.length === 0) {
    throw new Error(`No approval for stage ${plan.stage}. A person must run: node cli.mjs approve --stage ${plan.stage}${plan.envName !== 'emulator' ? ` --env ${plan.envName}` : ''}`);
  }
  const { file, approval: a } = candidates[0];
  const problems = [];
  if (a.approvedVia !== 'tty-phrase' || a.phrase !== confirmationPhrase(plan)) problems.push('approval was not typed for this exact plan');
  if (a.planHash !== plan.hash) problems.push('config or plan changed after approval (plan hash differs)');
  if (a.envName !== plan.envName || a.projectId !== plan.env.projectId) problems.push(`approval is for ${a.envName}/${a.projectId}`);
  if (a.users !== plan.users) problems.push(`approval is for ${a.users} users`);
  if (Date.parse(a.expiresAt) < Date.now()) problems.push(`approval expired at ${a.expiresAt}`);
  if (state.usedApprovalIds.includes(a.approvalId)) problems.push('approval already used (each approval runs once)');
  if (problems.length) {
    throw new Error(`Stage ${plan.stage} approval rejected:\n  - ${problems.join('\n  - ')}\nA person must approve again.`);
  }
  return { file, approval: a };
}

/** Spend it: recorded in state and the file deleted, so it can never be reused. */
export function consumeApproval(state, { file, approval }) {
  state.usedApprovalIds.push(approval.approvalId);
  try { unlinkSync(file); } catch { /* ignore */ }
}

export function pendingApprovals() {
  return listApprovalFiles().map(readApproval).filter(Boolean);
}
