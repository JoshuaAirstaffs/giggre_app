import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { sendPushToUser } from "./push";
import { firestoreTriggerRegion } from "./region";
import { loadFx, perUsd } from "./fx";

// Same region pinning as gigPoints.ts (imports are hoisted above
// setGlobalOptions in index.ts).
const OPTS = { region: firestoreTriggerRegion(), maxInstances: 10 } as const;

// ── Gig Points ⇄ GigCash conversion ────────────────────────────────────────
// Users REQUEST a conversion between Gig Points (gig_points/{uid}) and their
// Gig Wallet balance (GigCash, wallets/{uid} — see wallet.ts). An admin
// approves or rejects it in giggre-admin (Gig Points → Requests). Nothing is
// converted without that approval.
//
//   to_cash    Points → GigCash. The points are HELD (balance → heldPoints)
//              when requested; approval credits the wallet.
//   to_points  GigCash → Points. The pesos are taken from the wallet when
//              requested (a 'pending' wallet entry = the hold); approval
//              credits the points. Rejection/cancel refunds the wallet.
//
// Rates and limits — general_config/gig_points_requests (super-admin edited):
//   enabled                         master switch
//   rates.toCash                    points per US$1 when cashing out
//                                   (e.g. 100 → 100 pts = $1)
//   rates.toPoints                  points per US$1 when buying points
//                                   (e.g. 80 → $1 = 80 pts)
//   Rates are in USD. A PHP wallet is converted with the live USD→PHP rate
//   (fx.ts): 100 pts at 100 pts/$1 and 1 USD = 56 PHP → ₱56.00. Both the
//   points rate and the exchange rate are locked onto the request.
//   toCash / toPoints .enabled / min / max / dailyMax   (all in POINTS)
// The rate is LOCKED onto each request when it's made; later rate changes
// never alter a pending or past conversion. A missing doc, a disabled
// direction or a missing rate = that direction is closed.
// A user may have only ONE pending request at a time.
//
// Data (server-write only — see firestore.rules)
//   gig_points_requests/{id}                    request + decision
//   gig_points/{uid}.heldPoints                 points held by pending to_cash
//   gig_points/{uid}/transactions/req__{id}     points ledger line
//   gig_points/{uid}/daily/{YYYY-MM-DD}         per-direction daily totals
//   wallets/{uid}/transactions/gpconv_{id}[_hold|_refund]   wallet lines
//
// Exactly-once: requests use a client-supplied id (retries are no-ops) and
// every decision is one transaction that only moves a request out of pending.

const db = () => admin.firestore();
const FV = admin.firestore.FieldValue;

export const REQUEST_TYPES = ["to_cash", "to_points"] as const;
export type RequestType = (typeof REQUEST_TYPES)[number];
const LIMIT_KEY: Record<RequestType, "toCash" | "toPoints"> = { to_cash: "toCash", to_points: "toPoints" };
const ADMIN_PERMISSION = "gig-points";
/** Pending requests a user may have at once, across both directions. */
const MAX_OPEN_REQUESTS = 1;
const NOTE_MAX = 200;
const ABS_MAX_POINTS = 10_000_000;
const LIMITS_DOC = "gig_points_requests";

const TYPE_LABEL: Record<RequestType, string> = {
  to_cash: "Points → GigCash",
  to_points: "GigCash → Points",
};
const TYPE_NOUN: Record<RequestType, string> = {
  to_cash: "conversion to GigCash",
  to_points: "conversion to Gig Points",
};

const str = (v: unknown): string | null => (typeof v === "string" && v.trim() ? v.trim() : null);
const nonNegInt = (v: unknown): number =>
  typeof v === "number" && Number.isFinite(v) && v > 0 ? Math.floor(v) : 0;
/** Positive whole number within the absolute cap, else null. Never rounds. */
const posInt = (v: unknown): number | null =>
  typeof v === "number" && Number.isInteger(v) && v > 0 && v <= ABS_MAX_POINTS ? v : null;
const fmt = (n: number) => n.toLocaleString("en-US");
/** Round to centavos so float drift never accumulates (same as wallet.ts). */
const toMoney = (n: number) => Math.round(n * 100) / 100;
/** ₱ for PHP; $ for USD and anything else (the app's rule — default USD,
 *  PHP for users located in the Philippines). */
export const currencySymbol = (ccy: string | null | undefined) => (ccy === "PHP" ? "₱" : "$");
const money = (n: number, ccy: string) =>
  `${currencySymbol(ccy)}${n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
/** Wallet currency: the wallet's own, else the user's (set from location), else USD. */
export const walletCurrency = (
  wallet: FirebaseFirestore.DocumentData | undefined,
  user: FirebaseFirestore.DocumentData | undefined,
) => str(wallet?.currencyCode) ?? str(user?.currencyCode) ?? "USD";

/** Wallet-currency value of a conversion at a locked points rate (points per
 *  US$1) and exchange rate (wallet units per US$1). Cashing out rounds DOWN,
 *  buying rounds UP, both to the cent, so the platform never pays out a
 *  fraction more than the rates allow. */
export function cashFor(type: RequestType, points: number, rate: number, fxRate = 1): number {
  const exact = (points / rate) * fxRate;
  return type === "to_cash" ? Math.floor(exact * 100 + 1e-9) / 100 : Math.ceil(exact * 100 - 1e-9) / 100;
}

/** Calendar day in Manila (UTC+8, no DST) — the daily-cap bucket. */
export const manilaDayKey = (ms = Date.now()) =>
  new Date(ms + 8 * 3600_000).toISOString().slice(0, 10);

// ── Limits + rates ──────────────────────────────────────────────────────────

export interface DirectionLimits { enabled: boolean; min: number | null; max: number | null; dailyMax: number | null; rate: number | null }
export interface ConversionConfig { exists: boolean; enabled: boolean; byType: Record<RequestType, DirectionLimits> }

export function parseConversionConfig(d: FirebaseFirestore.DocumentData | undefined): ConversionConfig {
  const rates = (d?.rates ?? {}) as Record<string, unknown>;
  const byType = {} as Record<RequestType, DirectionLimits>;
  for (const t of REQUEST_TYPES) {
    const k = LIMIT_KEY[t];
    const raw = (d?.[k] ?? {}) as Record<string, unknown>;
    const rate = posInt(rates[k]);
    byType[t] = {
      // A direction without a valid rate can't be priced, so it's closed.
      enabled: raw.enabled === true && rate != null,
      min: posInt(raw.min),
      max: posInt(raw.max),
      dailyMax: posInt(raw.dailyMax),
      rate,
    };
  }
  return { exists: !!d, enabled: !!d && d.enabled !== false, byType };
}

async function loadConfig(): Promise<ConversionConfig> {
  return parseConversionConfig((await db().collection("general_config").doc(LIMITS_DOC).get()).data());
}

// ── Helpers ─────────────────────────────────────────────────────────────────

interface Actor { uid: string; name: string; email: string | null }

export async function requireGigPointsAdmin(uid: string | undefined): Promise<Actor> {
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

export interface UserInfo { uid: string; name: string; code: string | null; photoUrl: string | null }
export const userInfo = (snap: FirebaseFirestore.DocumentSnapshot): UserInfo => {
  const d = snap.data() ?? {};
  return { uid: snap.id, name: str(d.name) ?? "Giggre user", code: str(d.userId), photoUrl: str(d.photoUrl) };
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
  return [...out].slice(0, 10);
}

export async function findUser(query: string): Promise<FirebaseFirestore.DocumentSnapshot> {
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
const walletRef = (uid: string) => db().collection("wallets").doc(uid);
const walletTxRef = (uid: string, id: string) => walletRef(uid).collection("transactions").doc(id);

/** A wallet ledger line in wallet.ts's format. Call after all tx reads. */
function writeWalletEntry(
  tx: FirebaseFirestore.Transaction,
  uid: string,
  id: string,
  e: { amount: number; title: string; status: "completed" | "pending"; balanceAfter: number; currencyCode: string; meta: Record<string, unknown>; type?: string },
) {
  tx.create(walletTxRef(uid, id), {
    amount: toMoney(e.amount),
    type: e.type ?? "points_conversion",
    title: e.title,
    currencyCode: e.currencyCode,
    status: e.status,
    balanceAfter: toMoney(e.balanceAfter),
    meta: e.meta,
    createdAt: FV.serverTimestamp(),
  });
}

const parseNote = (v: unknown): string | null => {
  if (v == null || v === "") return null;
  if (typeof v !== "string") throw new HttpsError("invalid-argument", "Note must be text.");
  const t = v.trim();
  if (t.length > NOTE_MAX) throw new HttpsError("invalid-argument", `Keep the note under ${NOTE_MAX} characters.`);
  return t || null;
};

// ── App: create a conversion request ────────────────────────────────────────

export const createGigPointsRequest = onCall(OPTS, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const d = (request.data ?? {}) as Record<string, unknown>;

  const type = d.type as RequestType;
  if (!REQUEST_TYPES.includes(type)) throw new HttpsError("invalid-argument", "Unknown conversion type.");
  const points = posInt(d.points);
  if (points == null) throw new HttpsError("invalid-argument", "Enter a whole number of points greater than 0.");
  const note = parseNote(d.note);
  const clientRequestId = d.clientRequestId;
  if (typeof clientRequestId !== "string" || !/^[A-Za-z0-9_-]{8,64}$/.test(clientRequestId)) {
    throw new HttpsError("invalid-argument", "clientRequestId is required.");
  }

  const config = await loadConfig();
  const lim = config.byType[type];
  const label = TYPE_LABEL[type];
  if (!config.enabled || !lim.enabled || lim.rate == null) {
    throw new HttpsError("failed-precondition", `${label} isn't available right now.`);
  }
  if (lim.min != null && points < lim.min) {
    throw new HttpsError("out-of-range", `The minimum is ${fmt(lim.min)} points.`);
  }
  if (lim.max != null && points > lim.max) {
    throw new HttpsError("out-of-range", `The maximum is ${fmt(lim.max)} points per request.`);
  }
  const rate = lim.rate;
  const fx = await loadFx();

  const reqRef = db().collection("gig_points_requests").doc(`${uid}_${clientRequestId}`);
  const day = manilaDayKey();
  const bRef = balanceRef(uid);
  const wRef = walletRef(uid);
  const holdId = `gpconv_${reqRef.id}_hold`;

  const result = await db().runTransaction(async (tx) => {
    const existing = await tx.get(reqRef);
    if (existing.exists) {
      const e = existing.data()!;
      if (e.userId !== uid) throw new HttpsError("already-exists", "Request id in use.");
      return {
        requestId: reqRef.id, status: e.status as string, duplicate: true, requester: null as UserInfo | null,
        ccy: str(e.currencyCode) ?? "USD", cash: Number(e.cash) || 0, fxRate: Number(e.fxRate) || 1,
      };
    }
    const [userSnap, balSnap, daySnap, openSnap, walletSnap] = await Promise.all([
      tx.get(db().collection("users").doc(uid)),
      tx.get(bRef),
      tx.get(dailyRef(uid, day)),
      tx.get(db().collection("gig_points_requests").where("userId", "==", uid).where("status", "==", "pending")),
      tx.get(wRef),
    ]);
    if (!userSnap.exists) throw new HttpsError("failed-precondition", "Your account profile is missing.");
    if (openSnap.size >= MAX_OPEN_REQUESTS) {
      const open = openSnap.docs[0]?.data();
      const what = open && REQUEST_TYPES.includes(open.type)
        ? `a ${TYPE_NOUN[open.type as RequestType]} of ${fmt(nonNegInt(open.points))} points`
        : "a request";
      throw new HttpsError("resource-exhausted", `You already have ${what} waiting for review. You can make a new one after it's decided, or cancel it.`);
    }
    const usedToday = nonNegInt(daySnap.data()?.[type]);
    if (lim.dailyMax != null && usedToday + points > lim.dailyMax) {
      const left = Math.max(0, lim.dailyMax - usedToday);
      throw new HttpsError("out-of-range", left > 0
        ? `The daily limit is ${fmt(lim.dailyMax)} points. You can convert up to ${fmt(left)} more today.`
        : `You've reached today's limit of ${fmt(lim.dailyMax)} points. Try again tomorrow.`);
    }
    const ccy = walletCurrency(walletSnap.data(), userSnap.data());
    const fxRate = perUsd(fx, ccy);
    const cash = cashFor(type, points, rate, fxRate);
    if (cash <= 0) {
      throw new HttpsError("out-of-range", `That's worth less than ${money(0.01, ccy)}. Enter more points.`);
    }
    const walletBal = toMoney(Number(walletSnap.data()?.balance) || 0);
    if (type === "to_cash") {
      const balance = nonNegInt(balSnap.data()?.balance);
      if (balance < points) throw new HttpsError("failed-precondition", `You only have ${fmt(balance)} available points.`);
    } else if (walletBal < cash) {
      throw new HttpsError("failed-precondition", `This needs ${money(cash, ccy)}, but your GigCash balance is ${money(walletBal, ccy)}.`);
    }

    const requester = userInfo(userSnap);
    const now = FV.serverTimestamp();
    tx.create(reqRef, {
      type, status: "pending", points, cash, currencyCode: ccy, rate, fxRate, fxBase: "USD", note,
      userId: uid, userName: requester.name, userCode: requester.code,
      heldPoints: type === "to_cash" ? points : 0,
      heldCash: type === "to_points" ? cash : 0,
      dayKey: day, source: "app", createdAt: now, updatedAt: now,
    });
    tx.create(ledgerRef(uid, `req__${reqRef.id}`), {
      type: type === "to_cash" ? "convert_to_cash" : "convert_to_points",
      source: "user_request", status: "pending",
      points: type === "to_cash" ? -points : points,
      cash, currencyCode: ccy, rate, fxRate,
      description: type === "to_cash" ? `Convert to ${money(cash, ccy)} GigCash` : `Bought with ${money(cash, ccy)} GigCash`,
      note, requestId: reqRef.id, createdAt: now, updatedAt: now,
    });
    if (type === "to_cash") {
      tx.set(bRef, { userId: uid, balance: FV.increment(-points), heldPoints: FV.increment(points), updatedAt: now }, { merge: true });
    } else {
      // The wallet debit IS the hold; refunded if rejected or cancelled.
      const after = toMoney(walletBal - cash);
      tx.set(wRef, { balance: after, currencyCode: ccy, updatedAt: now, ...(walletSnap.exists ? {} : { createdAt: now }) }, { merge: true });
      writeWalletEntry(tx, uid, holdId, {
        amount: -cash, title: `Convert to ${fmt(points)} Gig Points`, status: "pending",
        balanceAfter: after, currencyCode: ccy, meta: { requestId: reqRef.id, points, rate, fxRate },
      });
    }
    tx.set(dailyRef(uid, day), { dayKey: day, [type]: FV.increment(points), updatedAt: now }, { merge: true });
    return { requestId: reqRef.id, status: "pending", duplicate: false, requester, ccy, cash, fxRate };
  });
  const cash = result.cash;

  if (!result.duplicate && result.requester) {
    const who = `${result.requester.name}${result.requester.code ? ` (${result.requester.code})` : ""}`;
    const what = type === "to_cash"
      ? `wants to convert ${fmt(points)} points to ${money(cash, result.ccy)} GigCash`
      : `wants to convert ${money(cash, result.ccy)} GigCash to ${fmt(points)} points`;
    try {
      await db().collection("admin_notifications").add({
        type: "gig_points_request",
        requiredPermission: ADMIN_PERMISSION,
        title: `Gig Points conversion request`,
        message: `${who} ${what} (rate ${fmt(rate)} pts per $1${result.ccy !== "USD" ? `, 1 USD = ${result.fxRate} ${result.ccy}` : ""}).${note ? ` Note: "${note}"` : ""} Review it before it goes through.`,
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
    await notifyUser(uid, "Conversion request submitted",
      type === "to_cash"
        ? `Converting ${fmt(points)} points to ${money(cash, result.ccy)} GigCash is waiting for review. The points are on hold until it's decided.`
        : `Converting ${money(cash, result.ccy)} GigCash to ${fmt(points)} points is waiting for review. The GigCash is on hold until it's decided.`,
      { requestId: result.requestId, status: "pending", requestType: type });
  }
  return { requestId: result.requestId, status: result.status, cash };
});

// ── Settle a pending request (approve / reject / cancel) ────────────────────

type Outcome = "approved" | "rejected" | "cancelled";

interface Settled { type: RequestType; points: number; cash: number; ccy: string; userId: string; userName: string; userCode: string | null; legacy?: boolean }

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
    const cash = toMoney(Number(r.cash) || 0);
    const uid = r.userId as string;
    if (!REQUEST_TYPES.includes(type) || points == null || cash <= 0) {
      // Deposit / withdraw / transfer requests from before conversion
      // replaced them. They can only be closed; held points go back.
      if (outcome === "approved") {
        throw new HttpsError("failed-precondition", "This is an old deposit/withdraw/transfer request. Reject it to close it and return any held points.");
      }
      const held = nonNegInt(r.heldPoints);
      const now = FV.serverTimestamp();
      tx.set(ledgerRef(uid, `req__${requestId}`), { status: "voided", voidedAt: now, voidReason: outcome, updatedAt: now }, { merge: true });
      if (held > 0) tx.set(balanceRef(uid), { userId: uid, balance: FV.increment(held), heldPoints: FV.increment(-held), updatedAt: now }, { merge: true });
      tx.update(reqRef, {
        status: outcome, heldPoints: 0, decidedAt: now,
        decidedBy: opts.actor?.uid ?? opts.ownerUid ?? null, decidedByName: opts.actor?.name ?? null,
        decisionNote: opts.note ?? null, reference: null, updatedAt: now,
      });
      return { type, points: nonNegInt(r.points), cash: 0, ccy: "USD", userId: uid, userName: r.userName ?? "Giggre user", userCode: r.userCode ?? null, legacy: true };
    }
    const ccy = str(r.currencyCode) ?? "USD";

    // All reads first (Firestore transaction rule).
    const wSnap = await tx.get(walletRef(uid));
    const walletBal = toMoney(Number(wSnap.data()?.balance) || 0);

    const now = FV.serverTimestamp();
    const lRef = ledgerRef(uid, `req__${requestId}`);
    const bRef = balanceRef(uid);
    const holdRef = walletTxRef(uid, `gpconv_${requestId}_hold`);
    const meta = { requestId, points, rate: r.rate ?? null, fxRate: r.fxRate ?? null };

    if (outcome === "approved") {
      tx.set(lRef, { status: "credited", creditedAt: now, updatedAt: now, reference: opts.reference ?? null }, { merge: true });
      if (type === "to_cash") {
        const after = toMoney(walletBal + cash);
        tx.set(bRef, { userId: uid, heldPoints: FV.increment(-points), updatedAt: now }, { merge: true });
        tx.set(walletRef(uid), { balance: after, currencyCode: ccy, updatedAt: now, ...(wSnap.exists ? {} : { createdAt: now }) }, { merge: true });
        writeWalletEntry(tx, uid, `gpconv_${requestId}`, {
          amount: cash, title: `Converted ${fmt(points)} Gig Points`, status: "completed",
          balanceAfter: after, currencyCode: ccy, meta,
        });
      } else {
        tx.set(bRef, { userId: uid, balance: FV.increment(points), updatedAt: now }, { merge: true });
        tx.set(holdRef, { status: "completed" }, { merge: true });
      }
    } else {
      tx.set(lRef, { status: "voided", voidedAt: now, voidReason: outcome, updatedAt: now }, { merge: true });
      if (type === "to_cash") {
        tx.set(bRef, { userId: uid, balance: FV.increment(points), heldPoints: FV.increment(-points), updatedAt: now }, { merge: true });
      } else {
        const after = toMoney(walletBal + cash);
        tx.set(holdRef, { status: "reversed" }, { merge: true });
        tx.set(walletRef(uid), { balance: after, updatedAt: now }, { merge: true });
        writeWalletEntry(tx, uid, `gpconv_${requestId}_refund`, {
          amount: cash, type: "refund",
          title: outcome === "cancelled" ? "Conversion cancelled — refund" : "Conversion rejected — refund",
          status: "completed", balanceAfter: after, currencyCode: ccy, meta,
        });
      }
      if (typeof r.dayKey === "string") {
        tx.set(dailyRef(uid, r.dayKey), { [type]: FV.increment(-points), updatedAt: now }, { merge: true });
      }
    }

    tx.update(reqRef, {
      status: outcome, heldPoints: 0, heldCash: 0,
      decidedAt: now,
      decidedBy: opts.actor?.uid ?? opts.ownerUid ?? null,
      decidedByName: opts.actor?.name ?? null,
      decisionNote: opts.note ?? null,
      reference: opts.reference ?? null,
      updatedAt: now,
    });
    return { type, points, cash, ccy, userId: uid, userName: r.userName ?? "Giggre user", userCode: r.userCode ?? null };
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
  if (s.legacy) {
    await notifyUser(s.userId, "Points request closed",
      `Your old Gig Points request was closed${note ? `: ${note}` : "."} Any points on hold are back in your balance. You can now convert points to GigCash instead.`,
      { requestId, status: "rejected", requestType: String(s.type) });
    await logActivity(actor, "gig_points_request_rejected", `Closed old points request for ${s.userName}${note ? ` — ${note}` : ""}`, requestId, s.userName, { legacy: true, note });
    return { status: outcome };
  }
  const pts = fmt(s.points);
  const cash = money(s.cash, s.ccy);
  if (outcome === "approved") {
    await notifyUser(s.userId, "Conversion approved",
      s.type === "to_cash"
        ? `${pts} Gig Points were converted to ${cash} GigCash in your Gig Wallet.`
        : `${cash} GigCash was converted to ${pts} Gig Points.`,
      { requestId, status: "approved", requestType: s.type });
  } else {
    await notifyUser(s.userId, "Conversion rejected",
      `Your ${TYPE_NOUN[s.type]} was rejected${note ? `: ${note}` : "."} ${s.type === "to_cash" ? `The ${pts} points are back in your balance.` : `${cash} was refunded to your Gig Wallet.`}`,
      { requestId, status: "rejected", requestType: s.type });
  }
  await logActivity(actor, outcome === "approved" ? "gig_points_request_approved" : "gig_points_request_rejected",
    `${outcome === "approved" ? "Approved" : "Rejected"} ${TYPE_LABEL[s.type]} (${pts} pts ↔ ${cash}) for ${s.userName}${s.userCode ? ` (${s.userCode})` : ""}${note ? ` — ${note}` : ""}`,
    requestId, s.userName, { type: s.type, points: s.points, cash: s.cash, userId: s.userId, reference, note });
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

// ── Admin: find a user for a manual adjustment ──────────────────────────────

export const adminFindGigPointsUser = onCall(OPTS, async (request) => {
  await requireGigPointsAdmin(request.auth?.uid);
  const snap = await findUser(String((request.data ?? {}).query ?? ""));
  const u = userInfo(snap);
  const [b, w] = await Promise.all([balanceRef(u.uid).get(), walletRef(u.uid).get()]);
  const bd = b.data() ?? {};
  return {
    uid: u.uid, name: u.name, code: u.code, photoUrl: u.photoUrl,
    phone: str(snap.data()?.phone), email: str(snap.data()?.email),
    balance: nonNegInt(bd.balance), heldPoints: nonNegInt(bd.heldPoints),
    pendingPoints: nonNegInt(bd.pendingPoints), lifetimeEarned: nonNegInt(bd.lifetimeEarned),
    walletBalance: toMoney(Number(w.data()?.balance) || 0),
    currencyCode: walletCurrency(w.data(), snap.data()),
  };
});
