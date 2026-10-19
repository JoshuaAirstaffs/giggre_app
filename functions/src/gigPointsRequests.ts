import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { sendPushToUser } from "./push";
import { firestoreTriggerRegion } from "./region";

// Same region pinning as gigPoints.ts (imports are hoisted above
// setGlobalOptions in index.ts).
const OPTS = { region: firestoreTriggerRegion(), maxInstances: 10 } as const;

// ── Gig Points requests: deposit / withdraw / transfer ─────────────────────
// Users REQUEST a movement of points; an admin approves or rejects it in
// giggre-admin (Gig Points → Requests). Nothing moves without that approval.
// Cash is settled by admins outside the app (no payment integration yet).
//
//   deposit   user pays the admin outside the app → on approval the points
//             are credited. Nothing is held while pending.
//   withdraw  points are HELD (balance → heldPoints) the moment the request
//             is made, so they can't be spent twice. Approval finalises it
//             (admin pays out); rejection/cancel returns them.
//   transfer  held like a withdrawal; approval moves them to the recipient.
//
// Limits (general_config/gig_points_requests, super-admin edited):
//   enabled                       master switch
//   {deposit|withdraw|transfer}.enabled / min / max / dailyMax
//   min/max apply per request; dailyMax is the most one user can request of
//   that type per Manila calendar day. Rejected/cancelled requests stop
//   counting. A missing doc or a disabled type = requests are closed.
//   A user may have only ONE pending request at a time, of any type.
//
// Data (all server-write only — see firestore.rules)
//   gig_points_requests/{id}                       the request + decision
//   gig_points/{uid}.heldPoints                    points reserved by
//                                                  pending withdraw/transfer
//   gig_points/{uid}/transactions/req__{id}        ledger line per request
//   gig_points/{uid}/transactions/adm__{id}        ledger line, admin action
//   gig_points/{uid}/daily/{YYYY-MM-DD}            per-type daily totals
//
// Exactly-once: requests use a client-supplied id (retries are no-ops) and
// every decision is a transaction that only moves a request out of pending.

const db = () => admin.firestore();
const FV = admin.firestore.FieldValue;

export const REQUEST_TYPES = ["deposit", "withdraw", "transfer"] as const;
export type RequestType = (typeof REQUEST_TYPES)[number];
const ADMIN_PERMISSION = "gig-points";
/** Pending requests a user may have at once, across all types. */
const MAX_OPEN_REQUESTS = 1;
const NOTE_MAX = 200;
const ABS_MAX_POINTS = 1_000_000;
const LIMITS_DOC = "gig_points_requests";

const TYPE_LABEL: Record<RequestType, string> = {
  deposit: "Deposit",
  withdraw: "Withdrawal",
  transfer: "Transfer",
};
const holds = (t: RequestType) => t === "withdraw" || t === "transfer";

const str = (v: unknown): string | null => (typeof v === "string" && v.trim() ? v.trim() : null);
const nonNegInt = (v: unknown): number =>
  typeof v === "number" && Number.isFinite(v) && v > 0 ? Math.floor(v) : 0;
/** Positive whole number within the absolute cap, else null. Never rounds. */
const posInt = (v: unknown): number | null =>
  typeof v === "number" && Number.isInteger(v) && v > 0 && v <= ABS_MAX_POINTS ? v : null;
const fmt = (n: number) => n.toLocaleString("en-US");

/** Calendar day in Manila (UTC+8, no DST) — the daily-cap bucket. */
export const manilaDayKey = (ms = Date.now()) =>
  new Date(ms + 8 * 3600_000).toISOString().slice(0, 10);

// ── Limits ──────────────────────────────────────────────────────────────────

export interface TypeLimits { enabled: boolean; min: number | null; max: number | null; dailyMax: number | null }
export interface RequestLimits { exists: boolean; enabled: boolean; byType: Record<RequestType, TypeLimits> }

export function parseLimits(d: FirebaseFirestore.DocumentData | undefined): RequestLimits {
  const byType = {} as Record<RequestType, TypeLimits>;
  for (const t of REQUEST_TYPES) {
    const raw = (d?.[t] ?? {}) as Record<string, unknown>;
    byType[t] = {
      enabled: raw.enabled === true,
      min: posInt(raw.min),
      max: posInt(raw.max),
      dailyMax: posInt(raw.dailyMax),
    };
  }
  return { exists: !!d, enabled: !!d && d.enabled !== false, byType };
}

async function loadLimits(): Promise<RequestLimits> {
  return parseLimits((await db().collection("general_config").doc(LIMITS_DOC).get()).data());
}

// ── Helpers ─────────────────────────────────────────────────────────────────

interface Actor { uid: string; name: string; email: string | null }

async function requireGigPointsAdmin(uid: string | undefined): Promise<Actor> {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const a = (await db().collection("admins").doc(uid).get()).data();
  if (!a || a.isActive !== true || a.isPending !== false) {
    throw new HttpsError("permission-denied", "Admins only.");
  }
  const perms: unknown[] = Array.isArray(a.permissions) ? a.permissions : [];
  if (a.role !== "super_admin" && !perms.includes(ADMIN_PERMISSION)) {
    throw new HttpsError("permission-denied", "You need the Gig Points permission.");
  }
  return { uid, name: str(a.name) ?? str(a.email) ?? "Admin", email: str(a.email) };
}

interface UserInfo { uid: string; name: string; code: string | null; photoUrl: string | null }
const userInfo = (snap: FirebaseFirestore.DocumentSnapshot): UserInfo => {
  const d = snap.data() ?? {};
  return { uid: snap.id, name: str(d.name) ?? "Giggre user", code: str(d.userId), photoUrl: str(d.photoUrl) };
};

/** "Juan Dela Cruz" → "Juan D." — enough to confirm, without exposing it all. */
const maskName = (name: string) => {
  const parts = name.split(/\s+/).filter(Boolean);
  if (parts.length < 2) return parts[0] ?? name;
  return `${parts[0]} ${parts[parts.length - 1][0].toUpperCase()}.`;
};

/** Variants a stored phone might use for the same number. */
function phoneCandidates(input: string): string[] {
  const digits = input.replace(/[^\d]/g, "");
  if (digits.length < 7) return [];
  const out = new Set<string>([input.replace(/[\s-]/g, ""), digits, `+${digits}`]);
  let national: string | null = null;
  if (digits.startsWith("63") && digits.length === 12) national = digits.slice(2);
  else if (digits.startsWith("0") && digits.length === 11) national = digits.slice(1);
  else if (digits.length === 10 && digits.startsWith("9")) national = digits;
  if (national) {
    out.add(`+63${national}`);
    out.add(`63${national}`);
    out.add(`0${national}`);
    out.add(national);
  }
  return [...out].slice(0, 10); // Firestore `in` takes at most 30; keep it small
}

async function findUser(query: string): Promise<FirebaseFirestore.DocumentSnapshot> {
  const q = query.trim();
  if (!q || q.length > 40) throw new HttpsError("invalid-argument", "Enter a Giggre ID or phone number.");
  const users = db().collection("users");
  let docs: FirebaseFirestore.QueryDocumentSnapshot[] = [];
  if (/^[A-Za-z]{3}\d{6}$/.test(q)) {
    docs = (await users.where("userId", "==", q.toUpperCase()).limit(2).get()).docs;
  } else {
    const c = phoneCandidates(q);
    if (c.length) docs = (await users.where("phone", "in", c).limit(2).get()).docs;
  }
  if (docs.length === 0) throw new HttpsError("not-found", "No Giggre user matches that ID or phone number.");
  if (docs.length > 1) throw new HttpsError("failed-precondition", "More than one account uses that phone number. Use their Giggre ID instead.");
  return docs[0];
}

async function notifyUser(uid: string, title: string, message: string, data: Record<string, string>) {
  try {
    await db().collection("notifications").add({
      userId: uid,
      category: "gig_points",
      request_status: data.status ?? null,
      requestId: data.requestId ?? null,
      title,
      message,
      createdAt: FV.serverTimestamp(),
    });
  } catch (err) {
    logger.warn("[gigPointsRequests] notification doc failed", { uid, error: String(err) });
  }
  try {
    await sendPushToUser(uid, { title, body: message, channelId: "gig_points_v1", data: { type: "gig_points_request", ...data } });
  } catch (err) {
    logger.warn("[gigPointsRequests] push failed", { uid, error: String(err) });
  }
}

/** Same shape giggre-admin's writeLog() uses, so it shows in Activity Logs. */
async function logActivity(actor: Actor, action: string, description: string, targetId: string, targetName: string, other: Record<string, unknown>) {
  try {
    await db().collection("activityLogs").add({
      actorId: actor.uid,
      actorName: actor.name,
      actorEmail: actor.email,
      module: "gig_points",
      action,
      description,
      targetSection: null,
      targetId,
      targetName,
      affectedFiles: [],
      meta: { from: null, to: null, other },
      createdAt: FV.serverTimestamp(),
    });
  } catch (err) {
    logger.warn("[gigPointsRequests] activity log failed", { error: String(err) });
  }
}

const balanceRef = (uid: string) => db().collection("gig_points").doc(uid);
const ledgerRef = (uid: string, id: string) => balanceRef(uid).collection("transactions").doc(id);
const dailyRef = (uid: string, day: string) => balanceRef(uid).collection("daily").doc(day);

const parseNote = (v: unknown, required = false): string | null => {
  if (v == null || v === "") {
    if (required) throw new HttpsError("invalid-argument", "A reason (3–300 characters) is required.");
    return null;
  }
  if (typeof v !== "string") throw new HttpsError("invalid-argument", "Note must be text.");
  const t = v.trim();
  const max = required ? 300 : NOTE_MAX;
  if (required && t.length < 3) throw new HttpsError("invalid-argument", "A reason (3–300 characters) is required.");
  if (t.length > max) throw new HttpsError("invalid-argument", `Keep the note under ${max} characters.`);
  return t || null;
};

// ── App: limits + recipient lookup ──────────────────────────────────────────

/** Recipient preview for a transfer. users/{uid} is already public-read; this
 *  only resolves an ID/phone to a uid and a masked name for confirmation. */
export const lookupGigPointsRecipient = onCall(OPTS, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const snap = await findUser(String((request.data ?? {}).query ?? ""));
  if (snap.id === uid) throw new HttpsError("invalid-argument", "You can't transfer points to yourself.");
  const u = userInfo(snap);
  return { recipientId: u.uid, name: maskName(u.name), code: u.code, photoUrl: u.photoUrl };
});

// ── App: create a request ───────────────────────────────────────────────────

export const createGigPointsRequest = onCall(OPTS, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const d = (request.data ?? {}) as Record<string, unknown>;

  const type = d.type as RequestType;
  if (!REQUEST_TYPES.includes(type)) throw new HttpsError("invalid-argument", "Unknown request type.");
  const points = posInt(d.points);
  if (points == null) throw new HttpsError("invalid-argument", "Enter a whole number of points greater than 0.");
  const note = parseNote(d.note);
  const clientRequestId = d.clientRequestId;
  if (typeof clientRequestId !== "string" || !/^[A-Za-z0-9_-]{8,64}$/.test(clientRequestId)) {
    throw new HttpsError("invalid-argument", "clientRequestId is required.");
  }

  const limits = await loadLimits();
  const lim = limits.byType[type];
  const label = TYPE_LABEL[type];
  if (!limits.enabled || !lim.enabled) {
    throw new HttpsError("failed-precondition", `${label} requests aren't available right now.`);
  }
  if (lim.min != null && points < lim.min) {
    throw new HttpsError("out-of-range", `The minimum ${label.toLowerCase()} is ${fmt(lim.min)} points.`);
  }
  if (lim.max != null && points > lim.max) {
    throw new HttpsError("out-of-range", `The maximum ${label.toLowerCase()} is ${fmt(lim.max)} points per request.`);
  }

  let recipient: UserInfo | null = null;
  if (type === "transfer") {
    const rid = str(d.recipientId);
    if (!rid || rid.includes("/")) throw new HttpsError("invalid-argument", "Choose who to send the points to.");
    if (rid === uid) throw new HttpsError("invalid-argument", "You can't transfer points to yourself.");
    const rSnap = await db().collection("users").doc(rid).get();
    if (!rSnap.exists) throw new HttpsError("not-found", "That recipient no longer exists.");
    recipient = userInfo(rSnap);
  }

  const reqRef = db().collection("gig_points_requests").doc(`${uid}_${clientRequestId}`);
  const day = manilaDayKey();
  const bRef = balanceRef(uid);

  const result = await db().runTransaction(async (tx) => {
    const existing = await tx.get(reqRef);
    if (existing.exists) {
      const e = existing.data()!;
      if (e.userId !== uid) throw new HttpsError("already-exists", "Request id in use.");
      return { requestId: reqRef.id, status: e.status as string, duplicate: true, requester: null as UserInfo | null };
    }
    const [userSnap, balSnap, daySnap, openSnap] = await Promise.all([
      tx.get(db().collection("users").doc(uid)),
      tx.get(bRef),
      tx.get(dailyRef(uid, day)),
      tx.get(db().collection("gig_points_requests").where("userId", "==", uid).where("status", "==", "pending")),
    ]);
    if (!userSnap.exists) throw new HttpsError("failed-precondition", "Your account profile is missing.");
    if (openSnap.size >= MAX_OPEN_REQUESTS) {
      const open = openSnap.docs[0]?.data();
      const what = open ? `a ${TYPE_LABEL[open.type as RequestType]?.toLowerCase() ?? "points"} request of ${fmt(nonNegInt(open.points))} points` : "a request";
      throw new HttpsError("resource-exhausted", `You already have ${what} waiting for review. You can make a new one after it's decided, or cancel it.`);
    }
    const usedToday = nonNegInt(daySnap.data()?.[type]);
    if (lim.dailyMax != null && usedToday + points > lim.dailyMax) {
      const left = Math.max(0, lim.dailyMax - usedToday);
      throw new HttpsError("out-of-range", left > 0
        ? `Daily ${label.toLowerCase()} limit is ${fmt(lim.dailyMax)} points. You can request up to ${fmt(left)} more today.`
        : `You've reached today's ${label.toLowerCase()} limit of ${fmt(lim.dailyMax)} points. Try again tomorrow.`);
    }
    const balance = nonNegInt(balSnap.data()?.balance);
    if (holds(type) && balance < points) {
      throw new HttpsError("failed-precondition", `You only have ${fmt(balance)} available points.`);
    }

    const requester = userInfo(userSnap);
    const now = FV.serverTimestamp();
    const description = type === "transfer"
      ? `Transfer to ${recipient!.name}`
      : type === "withdraw" ? "Withdrawal request" : "Deposit request";

    tx.create(reqRef, {
      type,
      status: "pending",
      points,
      note,
      userId: uid,
      userName: requester.name,
      userCode: requester.code,
      recipientId: recipient?.uid ?? null,
      recipientName: recipient?.name ?? null,
      recipientCode: recipient?.code ?? null,
      heldPoints: holds(type) ? points : 0,
      dayKey: day,
      source: "app",
      createdAt: now,
      updatedAt: now,
    });
    tx.create(ledgerRef(uid, `req__${reqRef.id}`), {
      type: type === "transfer" ? "transfer_out" : type,
      source: "user_request",
      status: "pending",
      points: type === "deposit" ? points : -points,
      description,
      note,
      requestId: reqRef.id,
      counterpartyId: recipient?.uid ?? null,
      counterpartyName: recipient?.name ?? null,
      counterpartyCode: recipient?.code ?? null,
      createdAt: now,
      updatedAt: now,
    });
    if (holds(type)) {
      tx.set(bRef, { userId: uid, balance: FV.increment(-points), heldPoints: FV.increment(points), updatedAt: now }, { merge: true });
    }
    tx.set(dailyRef(uid, day), { dayKey: day, [type]: FV.increment(points), updatedAt: now }, { merge: true });
    return { requestId: reqRef.id, status: "pending", duplicate: false, requester };
  });

  if (!result.duplicate && result.requester) {
    const who = `${result.requester.name}${result.requester.code ? ` (${result.requester.code})` : ""}`;
    const what = type === "transfer"
      ? `wants to transfer ${fmt(points)} points to ${recipient!.name}${recipient!.code ? ` (${recipient!.code})` : ""}`
      : `requested a ${label.toLowerCase()} of ${fmt(points)} points`;
    try {
      await db().collection("admin_notifications").add({
        type: "gig_points_request",
        requiredPermission: ADMIN_PERMISSION,
        title: `Gig Points ${label.toLowerCase()} request`,
        message: `${who} ${what}.${note ? ` Note: "${note}"` : ""} Review it before it goes through.`,
        link: "/gig-points",
        sourceCollection: "gig_points_requests",
        sourceId: result.requestId,
        meta: { userId: uid, name: result.requester.name, email: null },
        createdAt: FV.serverTimestamp(),
        readBy: {},
      });
    } catch (err) {
      logger.error("[gigPointsRequests] admin notification failed", { error: String(err) });
    }
    await notifyUser(uid, `${label} request submitted`,
      `Your ${label.toLowerCase()} of ${fmt(points)} points is waiting for review.${holds(type) ? " The points are on hold until it's decided." : ""}`,
      { requestId: result.requestId, status: "pending", requestType: type });
  }
  return { requestId: result.requestId, status: result.status };
});

// ── Settle a pending request (approve / reject / cancel) ────────────────────

type Outcome = "approved" | "rejected" | "cancelled";

interface Settled {
  type: RequestType; points: number; userId: string; recipientId: string | null;
  recipientName: string | null; userName: string; userCode: string | null;
}

async function settle(
  requestId: string,
  outcome: Outcome,
  opts: { actor?: Actor; ownerUid?: string; note?: string | null; reference?: string | null },
): Promise<Settled> {
  const reqRef = db().collection("gig_points_requests").doc(requestId);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(reqRef);
    if (!snap.exists) throw new HttpsError("not-found", "Request not found.");
    const r = snap.data()!;
    if (opts.ownerUid && r.userId !== opts.ownerUid) throw new HttpsError("permission-denied", "Not your request.");
    if (r.status !== "pending") throw new HttpsError("failed-precondition", `This request is already ${r.status}.`);
    const type = r.type as RequestType;
    const points = posInt(r.points);
    if (!REQUEST_TYPES.includes(type) || points == null) throw new HttpsError("data-loss", "Malformed request.");
    const uid = r.userId as string;
    const recipientId = (r.recipientId as string | null) ?? null;
    const held = holds(type) ? points : 0;

    // All reads first (Firestore transaction rule).
    let recipientSnap: FirebaseFirestore.DocumentSnapshot | null = null;
    if (outcome === "approved" && type === "transfer") {
      recipientSnap = await tx.get(db().collection("users").doc(recipientId!));
      if (!recipientSnap.exists) {
        throw new HttpsError("failed-precondition", "The recipient's account no longer exists. Reject this request to return the points.");
      }
    }

    const now = FV.serverTimestamp();
    const lRef = ledgerRef(uid, `req__${requestId}`);
    const bRef = balanceRef(uid);

    if (outcome === "approved") {
      tx.set(lRef, { status: "credited", creditedAt: now, updatedAt: now, reference: opts.reference ?? null }, { merge: true });
      if (type === "deposit") {
        tx.set(bRef, { userId: uid, balance: FV.increment(points), updatedAt: now }, { merge: true });
      } else {
        tx.set(bRef, { userId: uid, heldPoints: FV.increment(-held), updatedAt: now }, { merge: true });
      }
      if (type === "transfer") {
        tx.create(ledgerRef(recipientId!, `req__${requestId}`), {
          type: "transfer_in",
          source: "user_request",
          status: "credited",
          points,
          description: `Transfer from ${r.userName ?? "a Giggre user"}`,
          note: r.note ?? null,
          requestId,
          counterpartyId: uid,
          counterpartyName: r.userName ?? null,
          counterpartyCode: r.userCode ?? null,
          createdAt: now,
          creditedAt: now,
          updatedAt: now,
        });
        tx.set(balanceRef(recipientId!), { userId: recipientId, balance: FV.increment(points), updatedAt: now }, { merge: true });
      }
    } else {
      tx.set(lRef, { status: "voided", voidedAt: now, voidReason: outcome, updatedAt: now }, { merge: true });
      if (held) tx.set(bRef, { userId: uid, balance: FV.increment(held), heldPoints: FV.increment(-held), updatedAt: now }, { merge: true });
      if (typeof r.dayKey === "string") {
        tx.set(dailyRef(uid, r.dayKey), { [type]: FV.increment(-points), updatedAt: now }, { merge: true });
      }
    }

    tx.update(reqRef, {
      status: outcome,
      heldPoints: 0,
      decidedAt: now,
      decidedBy: opts.actor?.uid ?? opts.ownerUid ?? null,
      decidedByName: opts.actor?.name ?? null,
      decisionNote: opts.note ?? null,
      reference: opts.reference ?? null,
      updatedAt: now,
    });
    return {
      type, points, userId: uid, recipientId,
      recipientName: r.recipientName ?? null, userName: r.userName ?? "Giggre user", userCode: r.userCode ?? null,
    };
  });
}

// ── Admin: approve / reject ─────────────────────────────────────────────────

export const decideGigPointsRequest = onCall(OPTS, async (request) => {
  const actor = await requireGigPointsAdmin(request.auth?.uid);
  const d = (request.data ?? {}) as Record<string, unknown>;
  const requestId = str(d.requestId);
  if (!requestId || requestId.includes("/")) throw new HttpsError("invalid-argument", "requestId is required.");
  if (d.decision !== "approve" && d.decision !== "reject") throw new HttpsError("invalid-argument", "decision must be approve or reject.");
  const outcome: Outcome = d.decision === "approve" ? "approved" : "rejected";
  const note = parseNote(d.note);
  if (outcome === "rejected" && !note) throw new HttpsError("invalid-argument", "Give the user a reason for the rejection.");
  const reference = parseNote(d.reference);

  const s = await settle(requestId, outcome, { actor, note, reference });
  const label = TYPE_LABEL[s.type];
  const pts = fmt(s.points);

  if (outcome === "approved") {
    const msg = s.type === "deposit" ? `${pts} points were added to your balance.`
      : s.type === "withdraw" ? `Your withdrawal of ${pts} points was approved.${reference ? ` Reference: ${reference}.` : ""}`
      : `${pts} points were sent to ${s.recipientName ?? "the recipient"}.`;
    await notifyUser(s.userId, `${label} approved`, msg, { requestId, status: "approved", requestType: s.type });
    if (s.type === "transfer" && s.recipientId) {
      await notifyUser(s.recipientId, `You received ${pts} Gig Points`,
        `${s.userName} sent you ${pts} Gig Points.`, { requestId, status: "received", requestType: "transfer" });
    }
  } else {
    await notifyUser(s.userId, `${label} request rejected`,
      `Your ${label.toLowerCase()} of ${pts} points was rejected${note ? `: ${note}` : "."}${holds(s.type) ? " The held points are back in your balance." : ""}`,
      { requestId, status: "rejected", requestType: s.type });
  }
  await logActivity(actor, outcome === "approved" ? "gig_points_request_approved" : "gig_points_request_rejected",
    `${outcome === "approved" ? "Approved" : "Rejected"} ${label.toLowerCase()} of ${pts} points for ${s.userName}${s.userCode ? ` (${s.userCode})` : ""}${s.type === "transfer" ? ` → ${s.recipientName}` : ""}${note ? ` — ${note}` : ""}`,
    requestId, s.userName, { type: s.type, points: s.points, userId: s.userId, recipientId: s.recipientId, reference, note });
  return { status: outcome };
});

// ── App: cancel own pending request ─────────────────────────────────────────

export const cancelGigPointsRequest = onCall(OPTS, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const requestId = str((request.data ?? {}).requestId);
  if (!requestId || requestId.includes("/")) throw new HttpsError("invalid-argument", "requestId is required.");
  await settle(requestId, "cancelled", { ownerUid: uid });
  return { status: "cancelled" };
});

// ── Admin: direct deposit / withdraw / transfer ─────────────────────────────
// For support and settlement done outside the request flow. Applies at once
// (the admin IS the approval), ignores user limits, requires a reason, and is
// recorded as an approved request with source 'admin' for the audit trail.

export const adminGigPointsAction = onCall(OPTS, async (request) => {
  const actor = await requireGigPointsAdmin(request.auth?.uid);
  const d = (request.data ?? {}) as Record<string, unknown>;
  const type = d.action as RequestType;
  if (!REQUEST_TYPES.includes(type)) throw new HttpsError("invalid-argument", "action must be deposit, withdraw or transfer.");
  const points = posInt(d.points);
  if (points == null) throw new HttpsError("invalid-argument", "Enter a whole number of points greater than 0.");
  const reason = parseNote(d.reason, true)!;
  const userId = str(d.userId);
  if (!userId || userId.includes("/")) throw new HttpsError("invalid-argument", "userId is required.");
  const toUserId = type === "transfer" ? str(d.toUserId) : null;
  if (type === "transfer" && (!toUserId || toUserId.includes("/") || toUserId === userId)) {
    throw new HttpsError("invalid-argument", "Choose a different recipient.");
  }

  const reqRef = db().collection("gig_points_requests").doc();
  const result = await db().runTransaction(async (tx) => {
    const [uSnap, bSnap, tSnap] = await Promise.all([
      tx.get(db().collection("users").doc(userId)),
      tx.get(balanceRef(userId)),
      toUserId ? tx.get(db().collection("users").doc(toUserId)) : Promise.resolve(null),
    ]);
    if (!uSnap.exists) throw new HttpsError("not-found", "User not found.");
    if (toUserId && !tSnap?.exists) throw new HttpsError("not-found", "Recipient not found.");
    const balance = nonNegInt(bSnap.data()?.balance);
    if (type !== "deposit" && balance < points) {
      throw new HttpsError("failed-precondition", `${userInfo(uSnap).name} only has ${fmt(balance)} available points.`);
    }
    const u = userInfo(uSnap);
    const t = tSnap ? userInfo(tSnap) : null;
    const now = FV.serverTimestamp();
    const sign = type === "deposit" ? 1 : -1;

    tx.create(reqRef, {
      type, status: "approved", points, note: reason, userId,
      userName: u.name, userCode: u.code,
      recipientId: t?.uid ?? null, recipientName: t?.name ?? null, recipientCode: t?.code ?? null,
      heldPoints: 0, dayKey: manilaDayKey(), source: "admin",
      createdAt: now, updatedAt: now, decidedAt: now,
      decidedBy: actor.uid, decidedByName: actor.name, decisionNote: reason, reference: null,
    });
    tx.create(ledgerRef(userId, `adm__${reqRef.id}`), {
      type: type === "transfer" ? "transfer_out" : type,
      source: "admin", status: "credited", points: sign * points,
      description: type === "transfer" ? `Transfer to ${t!.name}` : reason,
      note: reason, requestId: reqRef.id, adminId: actor.uid,
      counterpartyId: t?.uid ?? null, counterpartyName: t?.name ?? null, counterpartyCode: t?.code ?? null,
      createdAt: now, creditedAt: now, updatedAt: now,
    });
    tx.set(balanceRef(userId), { userId, balance: FV.increment(sign * points), updatedAt: now }, { merge: true });
    if (t) {
      tx.create(ledgerRef(t.uid, `adm__${reqRef.id}`), {
        type: "transfer_in", source: "admin", status: "credited", points,
        description: `Transfer from ${u.name}`, note: reason, requestId: reqRef.id, adminId: actor.uid,
        counterpartyId: u.uid, counterpartyName: u.name, counterpartyCode: u.code,
        createdAt: now, creditedAt: now, updatedAt: now,
      });
      tx.set(balanceRef(t.uid), { userId: t.uid, balance: FV.increment(points), updatedAt: now }, { merge: true });
    }
    return { u, t, newBalance: balance + sign * points };
  });

  const pts = fmt(points);
  const { u, t } = result;
  if (type === "deposit") {
    await notifyUser(userId, `+${pts} Gig Points`, `${pts} points were added to your balance by Giggre.`, { requestId: reqRef.id, status: "approved", requestType: type });
  } else if (type === "withdraw") {
    await notifyUser(userId, `${pts} Gig Points withdrawn`, `${pts} points were withdrawn from your balance by Giggre: ${reason}`, { requestId: reqRef.id, status: "approved", requestType: type });
  } else {
    await notifyUser(userId, `${pts} Gig Points transferred`, `Giggre transferred ${pts} of your points to ${t!.name}: ${reason}`, { requestId: reqRef.id, status: "approved", requestType: type });
    await notifyUser(t!.uid, `You received ${pts} Gig Points`, `${u.name} sent you ${pts} Gig Points.`, { requestId: reqRef.id, status: "received", requestType: type });
  }
  await logActivity(actor, `gig_points_admin_${type}`,
    `${TYPE_LABEL[type]} of ${pts} points ${type === "deposit" ? "to" : "from"} ${u.name}${u.code ? ` (${u.code})` : ""}${t ? ` → ${t.name}${t.code ? ` (${t.code})` : ""}` : ""} — ${reason}`,
    reqRef.id, u.name, { type, points, userId, toUserId, reason });
  return { requestId: reqRef.id, balance: result.newBalance };
});

// ── Admin: find a user for a manual action ──────────────────────────────────

export const adminFindGigPointsUser = onCall(OPTS, async (request) => {
  await requireGigPointsAdmin(request.auth?.uid);
  const snap = await findUser(String((request.data ?? {}).query ?? ""));
  const u = userInfo(snap);
  const b = (await balanceRef(u.uid).get()).data() ?? {};
  return {
    uid: u.uid, name: u.name, code: u.code, photoUrl: u.photoUrl,
    phone: str(snap.data()?.phone), email: str(snap.data()?.email),
    balance: nonNegInt(b.balance), heldPoints: nonNegInt(b.heldPoints),
    pendingPoints: nonNegInt(b.pendingPoints), lifetimeEarned: nonNegInt(b.lifetimeEarned),
  };
});
