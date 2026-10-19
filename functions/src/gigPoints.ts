import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { sendPushToUser } from "./push";
import { firestoreTriggerRegion } from "./region";

// Pinned here rather than inherited from setGlobalOptions in index.ts: this
// module is evaluated (imports are hoisted) before that call runs. Same
// reasoning as ratings.ts / badges.ts.
const TRIGGER_REGION = firestoreTriggerRegion();
const OPTS = { region: TRIGGER_REGION, maxInstances: 10 } as const;

// ── Gig Points ──────────────────────────────────────────────────────────────
// Workers earn Gig Points for every gig the host has approved as complete.
// Everything here runs server-side (Admin SDK); clients can only READ their
// balance and history (see firestore.rules → gig_points).
//
// Lifecycle of one task's ledger entry
//   Each (gig, worker) pair has exactly one ledger entry, id
//   `{collection}__{gigId}__{workerId}`, that moves through:
//
//     (none) ──host approves──▶ pending ──gig completed──▶ credited
//                                  │
//                                  └──gig cancelled/no_worker/declined──▶ voided
//
//   "Host approves" = `paymentInitiatedAt` appears on the gig doc
//   (single-worker) or the worker's `workers/{uid}` slot doc (multi-worker).
//   gig_detail_sheet.dart writes it with status 'payment' and the payment
//   code when the host confirms the work, and firestore.rules lets no one but
//   the host/admin write it. "Completed" = status enters 'completed' on a doc
//   carrying that approval — after the worker enters the code
//   (worker_payment_confirm_sheet) or the host confirms manually
//   (host_payment_code_sheet), including while a cancellation request is
//   pending. A completion with no approval on it (e.g. a multi-worker gig's
//   parent doc) awards nothing.
//
//   Only `credited` points count toward the spendable balance. Pending points
//   are tracked separately so the app can show "on the way" without ever
//   presenting them as credited. If the pending step was missed (e.g. a gig
//   already in 'payment' when this was deployed), completion credits directly.
//
// Exactly-once
//   Every transition is a Firestore transaction that reads the ledger entry
//   first and only moves it forward. Retries, duplicate deliveries and
//   concurrent triggers no-op once the entry is in the target state, and the
//   id is the same whether the event came from a gig doc or a slot doc.
//
// Data
//   gig_points/{uid}                       balance, pendingPoints,
//                                          lifetimeEarned, gigsRewarded, …
//   gig_points/{uid}/transactions/{txId}   one entry per task (+ admin
//                                          adjustments)
//   general_config/gig_points              admin-editable reward config

export const GIG_COLLECTIONS = ["quick_gigs", "open_gigs", "offered_gigs"] as const;
type GigCollection = (typeof GIG_COLLECTIONS)[number];
export const GIG_TYPES = ["quick", "open", "offered"] as const;

const GIG_TYPE_BY_COLLECTION: Record<GigCollection, "quick" | "open" | "offered"> = {
  quick_gigs: "quick",
  open_gigs: "open",
  offered_gigs: "offered",
};

// ── Reward configuration ────────────────────────────────────────────────────
// There are NO built-in reward values. Every amount comes from data admins
// control:
//
//   gig doc  .gigPointsReward              per-task reward   (admin-only field)
//   general_config/gig_points
//            .pointsByGigType.{quick|open|offered}   per-type reward
//            .maxPointsPerGig               optional safety cap
//            .enabled                       kill switch (default on)
//
// Precedence (quoteReward):
//   1. A valid per-task reward.
//   2. Otherwise the valid reward for the task's type.
//   3. Otherwise nothing is awarded. The task is parked on a config issue
//      (gig_points_config_issues) and admins are notified; once the config is
//      fixed, an admin runs retryGigPointsAwards to award it.
//
// "Valid" = a non-negative safe integer. 12.5, -3, "10", NaN are rejected —
// never rounded — and the rejection itself is surfaced as a config issue.
// An explicit 0 is valid and means "this task pays no points".
//
// The amount is locked onto the ledger entry when the host approves the work
// (with the basis and the config version used), so later config changes never
// alter recorded or pending awards.

export interface GigPointsConfig {
  exists: boolean;
  enabled: boolean;
  /** Only the valid per-type values. */
  pointsByGigType: Partial<Record<string, number>>;
  /** Per-type values that were present but invalid, for issue reporting. */
  invalidTypeValues: Record<string, unknown>;
  maxPointsPerGig: number | null;
  /** Firestore update time of the config doc — recorded on each award. */
  version: string | null;
}

/** Strict: a non-negative safe integer, else null. Never coerces or rounds. */
export const rewardInt = (v: unknown): number | null =>
  typeof v === "number" && Number.isSafeInteger(v) && v >= 0 ? v : null;

const nonNegInt = (v: unknown): number | null =>
  typeof v === "number" && Number.isFinite(v) && v >= 0 ? Math.floor(v) : null;
const str = (v: unknown): string | null => (typeof v === "string" && v ? v : null);
const db = () => admin.firestore();

export function parseConfig(
  d: FirebaseFirestore.DocumentData | undefined,
  version: string | null = null,
): GigPointsConfig {
  const pointsByGigType: Partial<Record<string, number>> = {};
  const invalidTypeValues: Record<string, unknown> = {};
  const raw = d?.pointsByGigType;
  if (raw && typeof raw === "object") {
    for (const [type, v] of Object.entries(raw as Record<string, unknown>)) {
      const n = rewardInt(v);
      if (n != null) pointsByGigType[type] = n;
      else if (v !== null && v !== undefined) invalidTypeValues[type] = v;
    }
  }
  return {
    exists: d != null,
    enabled: d?.enabled !== false,
    pointsByGigType,
    invalidTypeValues,
    maxPointsPerGig: rewardInt(d?.maxPointsPerGig),
    version,
  };
}

const CONFIG_TTL_MS = 60_000;
let cachedConfig: { value: GigPointsConfig; at: number } | null = null;

async function loadConfig(fresh = false): Promise<GigPointsConfig> {
  if (!fresh && cachedConfig && Date.now() - cachedConfig.at < CONFIG_TTL_MS) {
    return cachedConfig.value;
  }
  const snap = await db().collection("general_config").doc("gig_points").get();
  const value = parseConfig(snap.data(), snap.updateTime?.toDate().toISOString() ?? null);
  cachedConfig = { value, at: Date.now() };
  return value;
}

export type RewardBasis = "task" | "task_type";

export interface RewardQuote {
  points: number;
  basis: RewardBasis;
  /** Value before the optional cap. */
  configuredPoints: number;
  /** Set only when the cap reduced the value. */
  cappedAt: number | null;
}

export type ConfigIssueCode =
  | "missing_type_reward"   // no per-task reward and none for the type
  | "invalid_type_reward"   // type value present but not a valid integer
  | "invalid_task_reward";  // per-task value present but not a valid integer

export interface ConfigProblem {
  code: ConfigIssueCode;
  /** Blocking problems stop the award; others are reported only. */
  blocking: boolean;
  gigType: string;
  detail: string;
}

export interface QuoteResult {
  quote: RewardQuote | null;
  problems: ConfigProblem[];
}

/**
 * Applies the precedence rule. Authoritative — the Dart copy in
 * GigPointsConfig.quote() is display-only and must follow the same rule.
 */
export function quoteReward(
  config: GigPointsConfig,
  collection: GigCollection,
  gig: FirebaseFirestore.DocumentData,
): QuoteResult {
  const gigType = str(gig.gigType) ?? GIG_TYPE_BY_COLLECTION[collection];
  const problems: ConfigProblem[] = [];
  const rawTask = gig.gigPointsReward;
  const task = rewardInt(rawTask);
  if (task == null && rawTask !== undefined && rawTask !== null) {
    problems.push({
      code: "invalid_task_reward", blocking: false, gigType,
      detail: `gigPointsReward ${JSON.stringify(rawTask)} is not a non-negative integer; ignored.`,
    });
  }
  const typeValue = config.pointsByGigType[gigType];

  let configuredPoints: number;
  let basis: RewardBasis;
  if (task != null) {
    configuredPoints = task;
    basis = "task";
  } else if (typeValue != null) {
    configuredPoints = typeValue;
    basis = "task_type";
  } else {
    const invalid = gigType in config.invalidTypeValues;
    problems.push({
      code: invalid ? "invalid_type_reward" : "missing_type_reward",
      blocking: true,
      gigType,
      detail: invalid
        ? `pointsByGigType.${gigType} = ${JSON.stringify(config.invalidTypeValues[gigType])} is not a non-negative integer.`
        : `No reward is configured for "${gigType}" gigs and this task has no reward of its own.`,
    });
    return { quote: null, problems };
  }
  const cap = config.maxPointsPerGig;
  const points = cap != null && configuredPoints > cap ? cap : configuredPoints;
  return {
    quote: { points, basis, configuredPoints, cappedAt: points < configuredPoints ? points : null },
    problems,
  };
}

const quoteFields = (q: RewardQuote, config: GigPointsConfig) => ({
  rewardBasis: q.basis,
  configuredPoints: q.configuredPoints,
  rewardCappedAt: q.cappedAt,
  rewardConfigVersion: config.version,
});

// ── Config issues (admin-facing) ────────────────────────────────────────────
// gig_points_config_issues/{issueId}
//   type-level:  type__{gigType}                  (missing/invalid type reward)
//   task-level:  task__{collection}__{gigId}      (invalid per-task reward)
//   .../tasks/{ledgerId}  every award blocked by this issue, for the retry.
// A new (or re-opened) issue also drops an admin_notifications entry, which
// giggre-admin's notification bell shows to admins holding "gig-points".

interface BlockedTask {
  action: LedgerAction;
  collection: GigCollection;
  gigId: string;
  slotId: string | null;
  workerId: string;
  gigTitle: string;
}

const issueIdFor = (p: ConfigProblem, collection: string, gigId: string) =>
  p.code === "invalid_task_reward" ? `task__${collection}__${gigId}` : `type__${p.gigType}`;

async function recordConfigProblems(
  problems: ConfigProblem[],
  task: BlockedTask,
): Promise<void> {
  const FV = admin.firestore.FieldValue;
  for (const p of problems) {
    const issueRef = db().collection("gig_points_config_issues")
      .doc(issueIdFor(p, task.collection, task.gigId));
    try {
      const opened = await db().runTransaction(async (tx) => {
        const snap = await tx.get(issueRef);
        const wasOpen = snap.exists && snap.data()?.status === "open";
        const now = FV.serverTimestamp();
        tx.set(issueRef, {
          code: p.code,
          gigType: p.gigType,
          detail: p.detail,
          status: "open",
          ...(wasOpen ? {} : { openedAt: now, resolvedAt: null, resolvedBy: null }),
          lastSeenAt: now,
          occurrences: FV.increment(1),
          lastTask: { gigCollection: task.collection, gigId: task.gigId, gigTitle: task.gigTitle },
        }, { merge: true });
        if (p.blocking) {
          tx.set(issueRef.collection("tasks").doc(ledgerId(task.collection, task.gigId, task.workerId)), {
            ...task,
            status: "blocked",
            blockedAt: now,
          }, { merge: true });
        }
        return !wasOpen;
      });
      logger.warn("[gigPoints] config issue", { code: p.code, gigType: p.gigType, gigId: task.gigId, blocking: p.blocking });
      if (opened) {
        await db().collection("admin_notifications").add({
          type: "gig_points_config_issue",
          requiredPermission: "gig-points",
          title: "Gig Points reward not configured",
          message: p.blocking
            ? `${p.detail} Points were NOT awarded for "${task.gigTitle}". Fix the reward, then retry the award.`
            : `${p.detail} The task-type reward was used instead.`,
          link: "/gig-points?tab=issues",
          sourceCollection: "gig_points_config_issues",
          sourceId: issueRef.id,
          meta: { userId: task.workerId, name: null, email: null },
          createdAt: FV.serverTimestamp(),
          readBy: {},
        });
      }
    } catch (err) {
      // Reporting must never break the award path itself.
      logger.error("[gigPoints] failed to record config issue", { error: String(err), code: p.code });
    }
  }
}

export type LedgerStatus = "pending" | "credited" | "voided";
export type LedgerAction = "approve" | "credit" | "void";

// Terminal states that mean the approved work will never be paid out.
const VOID_STATUSES = new Set(["cancelled", "no_worker", "declined"]);

const isApproved = (d: FirebaseFirestore.DocumentData) =>
  d.paymentInitiatedAt instanceof admin.firestore.Timestamp;

/** What a gig/slot update means for its ledger entry, if anything. */
export function classifyTransition(
  before: FirebaseFirestore.DocumentData,
  after: FirebaseFirestore.DocumentData,
): LedgerAction | null {
  if (!isApproved(after)) return null;
  if (after.status === "completed") return before.status !== "completed" ? "credit" : null;
  if (VOID_STATUSES.has(after.status)) return before.status !== after.status ? "void" : null;
  return isApproved(before) ? null : "approve";
}

/** The action a task's CURRENT state calls for — used by the admin retry. */
export function actionForCurrentState(d: FirebaseFirestore.DocumentData): LedgerAction | null {
  if (!isApproved(d)) return null;
  if (d.status === "completed") return "credit";
  if (VOID_STATUSES.has(d.status)) return null;
  return "approve";
}

/** Back-compat helper: true only for a verified (host-approved) completion. */
export function isVerifiedCompletion(
  before: FirebaseFirestore.DocumentData,
  after: FirebaseFirestore.DocumentData,
): boolean {
  return classifyTransition(before, after) === "credit";
}

export const ledgerId = (collection: string, gigId: string, workerId: string) =>
  `${collection}__${gigId}__${workerId}`;

const GIG_TYPE_LABEL: Record<string, string> = {
  quick: "Quick Gig",
  open: "Open Gig",
  offered: "Offered Gig",
};

interface TaskEvent {
  workerId: string;
  collection: GigCollection;
  gigId: string;
  slotId: string | null;
  gig: FirebaseFirestore.DocumentData;   // parent gig (title, type, reward)
  target: FirebaseFirestore.DocumentData; // doc that carries status/approval
}

interface ActionResult {
  credited: number;
  /** Set when an entry was needed but no valid reward is configured. */
  blocked: ConfigProblem[] | null;
  /** Non-blocking problems seen while creating an entry. */
  warnings: ConfigProblem[];
}

const ts = (v: unknown) => (v instanceof admin.firestore.Timestamp ? v : null);

/** Applies one lifecycle step in a transaction. */
async function applyLedgerAction(
  action: LedgerAction,
  e: TaskEvent,
  config: GigPointsConfig | null,
): Promise<ActionResult> {
  const FV = admin.firestore.FieldValue;
  const balanceRef = db().collection("gig_points").doc(e.workerId);
  const txRef = balanceRef.collection("transactions").doc(ledgerId(e.collection, e.gigId, e.workerId));
  const userRef = db().collection("users").doc(e.workerId);
  const quoted = action === "void" || !config ? null : quoteReward(config, e.collection, e.gig);
  const none: ActionResult = { credited: 0, blocked: null, warnings: [] };

  return db().runTransaction(async (tx): Promise<ActionResult> => {
    const [entrySnap, userSnap] = await Promise.all([tx.get(txRef), tx.get(userRef)]);
    const entry = entrySnap.data();
    const status = entry?.status as LedgerStatus | undefined;
    const userOk = userSnap.exists && userSnap.data()?.isDeleted !== true;
    const now = FV.serverTimestamp();
    const gigType = str(e.gig.gigType) ?? GIG_TYPE_BY_COLLECTION[e.collection];
    const title = str(e.gig.title) ?? "Gig";
    const typeLabel = GIG_TYPE_LABEL[gigType] ?? "Gig";

    if (action === "void") {
      if (status !== "pending") return none;
      const points = nonNegInt(entry?.points) ?? 0;
      tx.update(txRef, {
        status: "voided",
        voidReason: str(e.target.status) ?? "cancelled",
        voidedAt: now,
        updatedAt: now,
        description: `${typeLabel} ended as "${str(e.target.status) ?? "cancelled"}" before completion — no points awarded.`,
      });
      tx.set(balanceRef, { pendingPoints: FV.increment(-points), updatedAt: now }, { merge: true });
      return none;
    }

    // Creating an entry needs the program on, the user eligible, and a valid
    // configured reward. Returns why not, if it can't.
    const tryQuote = (): ActionResult | RewardQuote => {
      if (!config?.enabled || !userOk || !quoted) return none;
      if (!quoted.quote) return { credited: 0, blocked: quoted.problems, warnings: [] };
      return quoted.quote;
    };
    const base = {
      gigCollection: e.collection,
      gigType,
      gigId: e.gigId,
      slotId: e.slotId,
      gigTitle: title,
      hostId: str(e.gig.hostId),
      approvedAt: ts(e.target.paymentInitiatedAt),
    };
    const warnings = quoted?.problems.filter((p) => !p.blocking) ?? [];

    if (action === "approve") {
      if (entrySnap.exists) return none;
      const q = tryQuote();
      if (!("basis" in q)) return q;
      if (q.points <= 0) return none; // explicit zero reward
      tx.create(txRef, {
        ...base,
        ...quoteFields(q, config!),
        type: "earn",
        source: "gig_completed",
        status: "pending",
        points: q.points,
        description: `Host approved your work on this ${typeLabel}. Points are credited once payment is confirmed.`,
        createdAt: now,
        updatedAt: now,
      });
      tx.set(balanceRef, {
        userId: e.workerId,
        pendingPoints: FV.increment(q.points),
        updatedAt: now,
      }, { merge: true });
      return { credited: 0, blocked: null, warnings };
    }

    // action === "credit"
    if (status === "credited" || !userOk) return none;
    let points: number;
    let pendingDelta = 0;
    let entryWarnings: ConfigProblem[] = [];
    const credited = {
      status: "credited",
      completedAt: ts(e.target.completedAt) ?? now,
      creditedAt: now,
      updatedAt: now,
      description: `Completed this ${typeLabel} — host approved the work and payment was confirmed.`,
    };
    if (status === "pending") {
      // Honour the value locked in at approval, whatever the config says now.
      points = nonNegInt(entry?.points) ?? 0;
      tx.update(txRef, credited);
      pendingDelta = -points;
    } else {
      // No entry yet (pending step missed or blocked) or a voided one being
      // revived by a genuine completion.
      const q = tryQuote();
      if (!("basis" in q)) return q;
      points = q.points;
      if (points <= 0) return none;
      entryWarnings = warnings;
      tx.set(txRef, {
        ...base,
        ...quoteFields(q, config!),
        type: "earn",
        source: "gig_completed",
        points,
        createdAt: entry?.createdAt ?? now,
        ...credited,
      });
    }
    tx.set(balanceRef, {
      userId: e.workerId,
      balance: FV.increment(points),
      lifetimeEarned: FV.increment(points),
      gigsRewarded: FV.increment(1),
      ...(pendingDelta ? { pendingPoints: FV.increment(pendingDelta) } : {}),
      lastAwardedAt: now,
      updatedAt: now,
    }, { merge: true });
    return { credited: points, blocked: null, warnings: entryWarnings };
  });
}

/** Runs an action and handles its side effects (issues, push). */
async function runAction(
  action: LedgerAction,
  e: TaskEvent,
  freshConfig = false,
): Promise<ActionResult> {
  const config = action === "void" ? null : await loadConfig(freshConfig);
  const result = await applyLedgerAction(action, e, config);
  const task: BlockedTask = {
    action, collection: e.collection, gigId: e.gigId, slotId: e.slotId,
    workerId: e.workerId, gigTitle: str(e.gig.title) ?? "Gig",
  };
  const problems = [...(result.blocked ?? []), ...result.warnings];
  if (problems.length) await recordConfigProblems(problems, task);
  logger.info("[gigPoints] " + action, {
    workerId: e.workerId, gigId: e.gigId, slotId: e.slotId,
    credited: result.credited, blocked: result.blocked?.map((p) => p.code) ?? null,
  });
  if (action === "credit" && result.credited > 0) {
    try {
      await sendPushToUser(e.workerId, {
        title: `+${result.credited} Gig Points`,
        body: `You earned ${result.credited} Gig Points for completing "${str(e.gig.title) ?? "your gig"}".`,
        channelId: "gig_points_v1",
        data: { type: "gig_points_awarded", gigId: e.gigId, points: String(result.credited) },
      });
    } catch (err) {
      logger.warn("[gigPoints] push failed (points already credited)", { error: String(err) });
    }
  }
  return result;
}

async function handleTransition(
  before: FirebaseFirestore.DocumentData,
  after: FirebaseFirestore.DocumentData,
  e: Omit<TaskEvent, "target">,
): Promise<void> {
  const action = classifyTransition(before, after);
  if (!action || e.workerId === e.gig.hostId) return;
  await runAction(action, { ...e, target: after });
}

// ── Triggers ────────────────────────────────────────────────────────────────

// Single-worker gigs: the worker is on the gig doc itself. Multi-worker gigs
// leave workerId/assignedWorkerId unset and are handled per slot below.
function makeGigTrigger(collection: GigCollection) {
  return onDocumentUpdated({ document: `${collection}/{gigId}`, ...OPTS }, async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    const workerId = str(after.assignedWorkerId) ?? str(after.workerId);
    if (!workerId || !classifyTransition(before, after)) return;
    await handleTransition(before, after, {
      workerId, collection, gigId: event.params.gigId, slotId: null, gig: after,
    });
  });
}

function makeSlotTrigger(collection: GigCollection) {
  return onDocumentUpdated({ document: `${collection}/{gigId}/workers/{workerId}`, ...OPTS }, async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || !classifyTransition(before, after)) return;
    const gig = (await db().collection(collection).doc(event.params.gigId).get()).data();
    if (!gig) return;
    await handleTransition(before, after, {
      workerId: str(after.workerId) ?? event.params.workerId,
      collection, gigId: event.params.gigId, slotId: event.params.workerId, gig,
    });
  });
}

export const onQuickGigPointsAward = makeGigTrigger("quick_gigs");
export const onOpenGigPointsAward = makeGigTrigger("open_gigs");
export const onOfferedGigPointsAward = makeGigTrigger("offered_gigs");
export const onQuickGigSlotPointsAward = makeSlotTrigger("quick_gigs");
export const onOpenGigSlotPointsAward = makeSlotTrigger("open_gigs");
export const onOfferedGigSlotPointsAward = makeSlotTrigger("offered_gigs");

// ── Admin: retry awards blocked by a config issue ───────────────────────────
// After fixing the reward (per-task gigPointsReward or pointsByGigType), an
// admin calls this with the issueId. Each blocked task is re-evaluated from
// its CURRENT state with a freshly loaded config: approved → pending,
// completed → credited, cancelled since → dropped. Idempotent like the
// triggers (same ledger ids). The issue is marked resolved once nothing is
// left blocked.

async function requireActiveAdmin(uid: string | undefined): Promise<string> {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const a = (await db().collection("admins").doc(uid).get()).data();
  if (!a || a.isActive !== true || a.isPending !== false) {
    throw new HttpsError("permission-denied", "Admins only.");
  }
  return uid;
}

export const retryGigPointsAwards = onCall(OPTS, async (request) => {
  const adminId = await requireActiveAdmin(request.auth?.uid);
  const { issueId } = (request.data ?? {}) as Record<string, unknown>;
  if (typeof issueId !== "string" || !issueId || issueId.includes("/")) {
    throw new HttpsError("invalid-argument", "issueId is required.");
  }
  const issueRef = db().collection("gig_points_config_issues").doc(issueId);
  if (!(await issueRef.get()).exists) throw new HttpsError("not-found", "Issue not found.");

  const tasks = await issueRef.collection("tasks").where("status", "==", "blocked").get();
  const summary = { awarded: 0, pending: 0, stillBlocked: 0, notApplicable: 0 };
  for (const t of tasks.docs) {
    const d = t.data() as BlockedTask;
    const gigSnap = await db().collection(d.collection).doc(d.gigId).get();
    const gig = gigSnap.data();
    const target = d.slotId
      ? (await gigSnap.ref.collection("workers").doc(d.slotId).get()).data()
      : gig;
    const action = gig && target ? actionForCurrentState(target) : null;
    if (!gig || !target || !action || d.workerId === gig.hostId) {
      await t.ref.update({ status: "not_applicable", resolvedAt: admin.firestore.FieldValue.serverTimestamp() });
      summary.notApplicable++;
      continue;
    }
    const r = await runAction(action, {
      workerId: d.workerId, collection: d.collection, gigId: d.gigId,
      slotId: d.slotId, gig, target,
    }, true);
    if (r.blocked) {
      summary.stillBlocked++;
      continue;
    }
    await t.ref.update({ status: "resolved", resolvedAt: admin.firestore.FieldValue.serverTimestamp(), resolvedBy: adminId });
    if (action === "credit") summary.awarded++;
    else summary.pending++;
  }
  if (summary.stillBlocked === 0) {
    await issueRef.update({
      status: "resolved",
      resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      resolvedBy: adminId,
    });
  }
  await db().collection("activityLogs").add({
    type: "gig_points_awards_retried",
    adminId,
    issueId,
    ...summary,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return summary;
});

// ── Admin adjustment ────────────────────────────────────────────────────────
// For support corrections (fraud reversal, goodwill credit). Active admins
// only, mirrors isAdmin() in firestore.rules. Balance never goes negative.
export const adjustGigPoints = onCall(OPTS, async (request) => {
  const callerUid = await requireActiveAdmin(request.auth?.uid);

  const { userId, points, reason } = (request.data ?? {}) as Record<string, unknown>;
  if (typeof userId !== "string" || !userId) throw new HttpsError("invalid-argument", "userId is required.");
  if (typeof points !== "number" || !Number.isInteger(points) || points === 0 || Math.abs(points) > 100000) {
    throw new HttpsError("invalid-argument", "points must be a non-zero integer.");
  }
  if (typeof reason !== "string" || reason.trim().length < 3 || reason.length > 300) {
    throw new HttpsError("invalid-argument", "A reason (3–300 chars) is required.");
  }

  const balanceRef = db().collection("gig_points").doc(userId);
  const txRef = balanceRef.collection("transactions").doc();
  const newBalance = await db().runTransaction(async (tx) => {
    const [userSnap, balSnap] = await Promise.all([
      tx.get(db().collection("users").doc(userId)),
      tx.get(balanceRef),
    ]);
    if (!userSnap.exists) throw new HttpsError("not-found", "User not found.");
    const current = nonNegInt(balSnap.data()?.balance) ?? 0;
    if (current + points < 0) {
      throw new HttpsError("failed-precondition", `Balance is only ${current}.`);
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    tx.create(txRef, {
      type: "adjustment",
      source: "admin",
      status: "credited",
      points,
      reason: reason.trim(),
      description: reason.trim(),
      adminId: callerUid,
      createdAt: now,
      creditedAt: now,
      updatedAt: now,
    });
    tx.set(balanceRef, {
      userId,
      balance: admin.firestore.FieldValue.increment(points),
      ...(points > 0 ? { lifetimeEarned: admin.firestore.FieldValue.increment(points) } : {}),
      updatedAt: now,
    }, { merge: true });
    return current + points;
  });

  await db().collection("activityLogs").add({
    type: "gig_points_adjusted",
    adminId: callerUid,
    targetUserId: userId,
    points,
    reason: reason.trim(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { balance: newBalance, transactionId: txRef.id };
});
