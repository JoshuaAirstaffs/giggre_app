import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { sendPushToUser } from "./push";
import { firestoreTriggerRegion } from "./region";
import { findUser, userInfo, currencySymbol, walletCurrency, type UserInfo } from "./gigPointsRequests";
import { loadFx, fromUsd, convertDown, perUsd } from "./fx";

const OPTS = { region: firestoreTriggerRegion(), maxInstances: 10 } as const;

// ── Gig Wallet requests: Top Up (deposit), Send (transfer), Withdraw ───────
// Users REQUEST a wallet movement; an admin approves or rejects it in
// giggre-admin (Wallet → Requests). Nothing moves without that approval.
// PayMongo/GCash checkout is postponed, so top-ups are paid OUTSIDE the app
// using a method admins list — e-wallet transfer, cash at the office, or a
// remittance center — and the user submits the reference / official receipt
// / control number (plus an optional photo) as proof. Withdrawals are paid
// out the same ways, by an admin, outside the app.
//
//   deposit   nothing is held. A 'pending' top_up entry shows in the
//             user's history; approval credits the wallet.
//   transfer  verified users only. The amount is taken from the sender's
//             wallet when requested (a 'pending' send entry = the hold);
//             approval credits the recipient; rejection/cancel refunds.
//   withdraw  verified users only. The amount is taken from the wallet when
//             requested (a 'pending' withdraw entry = the hold). The user
//             picks a payout method an admin listed and gives their payout
//             details (e-wallet: account name + number; remittance: full
//             name as on their ID + mobile; office: pick up in person). The
//             admin pays it out, then approves with the payout reference /
//             control number (required except for office pickup);
//             rejection/cancel refunds.
//
// Config — general_config/wallet_requests (super-admin edited):
//   enabled, deposit|transfer.{enabled, min, max, dailyMax} — in USD; a PHP
//   wallet is checked against them converted at the live rate (fx.ts).
//   A Send between a PHP and a USD wallet converts too: the recipient gets
//   the amount at the rate locked when the request was made.
//   depositAccounts [{kind: ewallet|office|remittance, method, accountName,
//                     accountNumber, details}], depositNote
//   withdrawMethods [{kind: ewallet|office|remittance, method, details}],
//                    withdrawNote
// A user may have only ONE pending wallet request at a time.
//
// Data (server-write only — see firestore.rules)
//   wallet_requests/{id}
//   wallets/{uid}/transactions/wreq_{id}[_in|_refund]
//   wallets/{uid}/daily/{YYYY-MM-DD}   per-type daily totals (centavos)

const db = () => admin.firestore();
const FV = admin.firestore.FieldValue;

export const WALLET_REQUEST_TYPES = ["deposit", "transfer", "withdraw"] as const;
type WType = (typeof WALLET_REQUEST_TYPES)[number];
const ADMIN_PERMISSION = "wallet";
const MAX_OPEN_REQUESTS = 1;
const ABS_MAX = 1_000_000;
const CONFIG_DOC = "wallet_requests";
const LABEL: Record<WType, string> = { deposit: "Top up", transfer: "Send", withdraw: "Withdraw" };
const METHOD_KINDS = ["ewallet", "office", "remittance"] as const;

const str = (v: unknown): string | null => (typeof v === "string" && v.trim() ? v.trim() : null);
const toMoney = (n: number) => Math.round(n * 100) / 100;
/** Positive amount with at most 2 decimals, within the cap; else null. */
const amountOf = (v: unknown): number | null => {
  if (typeof v !== "number" || !Number.isFinite(v) || v <= 0 || v > ABS_MAX) return null;
  return Math.abs(toMoney(v) - v) < 1e-9 ? toMoney(v) : null;
};
const cents = (n: number) => Math.round(n * 100);
const money = (n: number, ccy = "USD") =>
  `${currencySymbol(ccy)}${n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const manilaDayKey = (ms = Date.now()) => new Date(ms + 8 * 3600_000).toISOString().slice(0, 10);
const maskName = (name: string) => {
  const parts = name.split(/\s+/).filter(Boolean);
  if (parts.length < 2) return parts[0] ?? name;
  return `${parts[0]} ${parts[parts.length - 1][0].toUpperCase()}.`;
};

const methodKindOf = (v: unknown): string =>
  (METHOD_KINDS as readonly string[]).includes(String(v)) ? String(v) : "ewallet";
/** "0917 *** 4567"-style mask for the user's own history line. */
const maskNumber = (n: string | null) => {
  if (!n) return null;
  const d = n.replace(/\s+/g, "");
  return d.length <= 4 ? d : `${"•".repeat(Math.min(6, d.length - 4))}${d.slice(-4)}`;
};
const withdrawTitle = (method: string | null, kind: string | null) =>
  kind === "office" ? `Withdraw — pickup at ${method ?? "office"}`
    : kind === "remittance" ? `Withdraw via ${method ?? "remittance"}`
      : `Withdraw to ${method ?? "e-wallet"}`;
function withdrawDoneMessage(s: { methodKind: string | null; method: string | null; payoutReference: string | null }, amt: string) {
  if (s.methodKind === "office") return `You received ${amt} in cash at ${s.method ?? "the office"}.`;
  if (s.methodKind === "remittance") {
    return `${amt} is ready to claim at ${s.method ?? "the remittance center"}. Control number: ${s.payoutReference ?? "—"}. Bring a valid ID.`;
  }
  return `${amt} was sent to your ${s.method ?? "account"}.${s.payoutReference ? ` Reference: ${s.payoutReference}.` : ""}`;
}

interface Limits { enabled: boolean; min: number | null; max: number | null; dailyMax: number | null }
interface WithdrawMethod { kind: string; method: string }
interface WalletConfig { enabled: boolean; byType: Record<WType, Limits>; withdrawMethods: WithdrawMethod[] }

function parseConfig(d: FirebaseFirestore.DocumentData | undefined): WalletConfig {
  const byType = {} as Record<WType, Limits>;
  for (const t of WALLET_REQUEST_TYPES) {
    const r = (d?.[t] ?? {}) as Record<string, unknown>;
    byType[t] = { enabled: r.enabled === true, min: amountOf(r.min), max: amountOf(r.max), dailyMax: amountOf(r.dailyMax) };
  }
  const withdrawMethods: WithdrawMethod[] = Array.isArray(d?.withdrawMethods)
    ? (d!.withdrawMethods as Record<string, unknown>[])
      .map((m) => ({ kind: String(m?.kind ?? "ewallet"), method: str(m?.method) ?? "" }))
      .filter((m) => m.method && (METHOD_KINDS as readonly string[]).includes(m.kind))
    : [];
  return { enabled: !!d && d.enabled !== false, byType, withdrawMethods };
}

interface Actor { uid: string; name: string; email: string | null }

export async function requireWalletAdmin(uid: string | undefined): Promise<Actor> {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const a = (await db().collection("admins").doc(uid).get()).data();
  if (!a || a.isActive !== true || a.isPending !== false) throw new HttpsError("permission-denied", "Admins only.");
  const perms: unknown[] = Array.isArray(a.permissions) ? a.permissions : [];
  if (a.role !== "super_admin" && !perms.includes(ADMIN_PERMISSION)) {
    throw new HttpsError("permission-denied", "You need the Wallet permission.");
  }
  return { uid, name: str(a.name) ?? str(a.email) ?? "Admin", email: str(a.email) };
}

export async function notifyWalletUser(uid: string, title: string, message: string, data: Record<string, string>) {
  try {
    await db().collection("notifications").add({
      userId: uid, category: "wallet", request_status: data.status ?? null, requestId: data.requestId ?? null,
      title, message, createdAt: FV.serverTimestamp(),
    });
  } catch (err) {
    logger.warn("[walletRequests] notification doc failed", { uid, error: String(err) });
  }
  try {
    await sendPushToUser(uid, { title, body: message, channelId: "wallet_v1", data: { type: "wallet_request", ...data } });
  } catch (err) {
    logger.warn("[walletRequests] push failed", { uid, error: String(err) });
  }
}

export async function logWalletActivity(actor: Actor, action: string, description: string, targetId: string, targetName: string, other: Record<string, unknown>) {
  try {
    await db().collection("activityLogs").add({
      actorId: actor.uid, actorName: actor.name, actorEmail: actor.email,
      module: "wallet", action, description, targetSection: null, targetId, targetName,
      affectedFiles: [], meta: { from: null, to: null, other }, createdAt: FV.serverTimestamp(),
    });
  } catch (err) {
    logger.warn("[walletRequests] activity log failed", { error: String(err) });
  }
}

const walletRef = (uid: string) => db().collection("wallets").doc(uid);
const txRef = (uid: string, id: string) => walletRef(uid).collection("transactions").doc(id);
const dailyRef = (uid: string, day: string) => walletRef(uid).collection("daily").doc(day);

const optText = (v: unknown, max: number, what: string): string | null => {
  if (v == null || v === "") return null;
  if (typeof v !== "string") throw new HttpsError("invalid-argument", `${what} must be text.`);
  const t = v.trim();
  if (t.length > max) throw new HttpsError("invalid-argument", `${what} must be under ${max} characters.`);
  return t || null;
};

// ── App: recipient lookup for Send ──────────────────────────────────────────

export const lookupWalletRecipient = onCall(OPTS, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const snap = await findUser(String((request.data ?? {}).query ?? ""));
  if (snap.id === uid) throw new HttpsError("invalid-argument", "You can't send money to yourself.");
  const u = userInfo(snap);
  // The recipient's wallet currency, so the app can preview a USD⇄PHP send.
  const currencyCode = walletCurrency((await walletRef(u.uid).get()).data(), snap.data());
  return { recipientId: u.uid, name: maskName(u.name), code: u.code, photoUrl: u.photoUrl, currencyCode };
});

// ── App: create a request ───────────────────────────────────────────────────

export const createWalletRequest = onCall(OPTS, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const d = (request.data ?? {}) as Record<string, unknown>;

  const type = d.type as WType;
  if (!WALLET_REQUEST_TYPES.includes(type)) throw new HttpsError("invalid-argument", "Unknown request type.");
  const amount = amountOf(d.amount);
  if (amount == null) throw new HttpsError("invalid-argument", "Enter an amount above 0 with up to 2 decimals.");
  const note = optText(d.note, 200, "Note");
  const clientRequestId = d.clientRequestId;
  if (typeof clientRequestId !== "string" || !/^[A-Za-z0-9_-]{8,64}$/.test(clientRequestId)) {
    throw new HttpsError("invalid-argument", "clientRequestId is required.");
  }

  // Deposit proof
  const hasMethod = type === "deposit" || type === "withdraw";
  const method = hasMethod ? optText(d.method, 40, "Payment method") : null;
  const methodKind = hasMethod ? methodKindOf(d.methodKind) : null;
  const reference = type === "deposit" ? optText(d.reference, 60, "Reference number") : null;
  if (type === "deposit" && (!reference || reference.length < 4)) {
    throw new HttpsError("invalid-argument", "Enter the reference number of your payment.");
  }
  const proofPath = type === "deposit" ? optText(d.proofPath, 300, "Proof") : null;
  if (proofPath && !proofPath.startsWith(`wallet_proofs/${uid}/`)) throw new HttpsError("invalid-argument", "Bad proof upload.");
  const proofUrl = proofPath ? optText(d.proofUrl, 1000, "Proof") : null;

  // Withdraw payout details
  let payoutName: string | null = null;
  let payoutNumber: string | null = null;
  if (type === "withdraw") {
    payoutName = optText(d.payoutName, 80, "Name");
    payoutNumber = optText(d.payoutNumber, 40, "Account / mobile number");
    if (methodKindOf(d.methodKind) !== "office") {
      if (!payoutName || payoutName.length < 2) throw new HttpsError("invalid-argument", "Enter the name on your account / ID.");
      if (!payoutNumber || payoutNumber.replace(/\D/g, "").length < 7) {
        throw new HttpsError("invalid-argument", "Enter a valid account or mobile number.");
      }
    }
  }

  const config = parseConfig((await db().collection("general_config").doc(CONFIG_DOC).get()).data());
  const lim = config.byType[type];
  if (!config.enabled || !lim.enabled) throw new HttpsError("failed-precondition", `${LABEL[type]} isn't available right now.`);
  if (type === "withdraw" && !config.withdrawMethods.some((m) =>
    m.kind === methodKind && m.method.toLowerCase() === (method ?? "").toLowerCase())) {
    throw new HttpsError("failed-precondition", `${method ?? "That payout method"} isn't available for withdrawals right now.`);
  }
  const fx = await loadFx();

  let recipient: UserInfo | null = null;
  let recipientCcy: string | null = null;
  if (type === "transfer") {
    const rid = str(d.recipientId);
    if (!rid || rid.includes("/")) throw new HttpsError("invalid-argument", "Choose who to send money to.");
    if (rid === uid) throw new HttpsError("invalid-argument", "You can't send money to yourself.");
    const rSnap = await db().collection("users").doc(rid).get();
    if (!rSnap.exists) throw new HttpsError("not-found", "That recipient no longer exists.");
    recipient = userInfo(rSnap);
    recipientCcy = walletCurrency((await walletRef(rid).get()).data(), rSnap.data());
  }

  const reqRef = db().collection("wallet_requests").doc(`${uid}_${clientRequestId}`);
  const day = manilaDayKey();
  const wRef = walletRef(uid);

  const result = await db().runTransaction(async (tx) => {
    const existing = await tx.get(reqRef);
    if (existing.exists) {
      const e = existing.data()!;
      if (e.userId !== uid) throw new HttpsError("already-exists", "Request id in use.");
      return {
        requestId: reqRef.id, status: e.status as string, duplicate: true, requester: null as UserInfo | null,
        ccy: str(e.currencyCode) ?? "USD", recipientAmount: Number(e.recipientAmount) || 0,
      };
    }
    const [userSnap, wSnap, daySnap, openSnap] = await Promise.all([
      tx.get(db().collection("users").doc(uid)),
      tx.get(wRef),
      tx.get(dailyRef(uid, day)),
      tx.get(db().collection("wallet_requests").where("userId", "==", uid).where("status", "==", "pending")),
    ]);
    if (!userSnap.exists) throw new HttpsError("failed-precondition", "Your account profile is missing.");
    if (type !== "deposit" && userSnap.data()?.isVerified !== "verified") {
      throw new HttpsError("permission-denied", type === "transfer"
        ? "Only verified accounts can send money. Verify your account first."
        : "Only verified accounts can withdraw. Verify your account first.");
    }
    if (openSnap.size >= MAX_OPEN_REQUESTS) {
      const o = openSnap.docs[0]?.data();
      const what = o ? `a ${(LABEL[o.type as WType] ?? "wallet").toLowerCase()} request of ${money(Number(o.amount) || 0)}` : "a request";
      throw new HttpsError("resource-exhausted", `You already have ${what} waiting for review. You can make a new one after it's decided, or cancel it.`);
    }
    const ccy = walletCurrency(wSnap.data(), userSnap.data());
    // Limits are set in USD; compare in the wallet's currency.
    const min = lim.min != null ? fromUsd(fx, lim.min, ccy) : null;
    const max = lim.max != null ? fromUsd(fx, lim.max, ccy) : null;
    const dailyMax = lim.dailyMax != null ? fromUsd(fx, lim.dailyMax, ccy) : null;
    if (min != null && amount < min) throw new HttpsError("out-of-range", `The minimum is ${money(min, ccy)}.`);
    if (max != null && amount > max) throw new HttpsError("out-of-range", `The maximum is ${money(max, ccy)} per request.`);
    const usedCents = Number(daySnap.data()?.[type]) || 0;
    if (dailyMax != null && usedCents + cents(amount) > cents(dailyMax)) {
      const left = Math.max(0, cents(dailyMax) - usedCents) / 100;
      throw new HttpsError("out-of-range", left > 0
        ? `The daily limit is ${money(dailyMax, ccy)}. You can request up to ${money(left, ccy)} more today.`
        : `You've reached today's limit of ${money(dailyMax, ccy)}. Try again tomorrow.`);
    }
    // What the recipient gets, in their wallet's currency (locked now).
    const recipientAmount = recipient ? convertDown(fx, amount, ccy, recipientCcy!) : null;
    if (recipient && (recipientAmount ?? 0) <= 0) throw new HttpsError("out-of-range", "That amount is too small to send.");
    const bal = toMoney(Number(wSnap.data()?.balance) || 0);
    if (type !== "deposit" && bal < amount) {
      throw new HttpsError("failed-precondition", `Your GigCash balance is only ${money(bal, ccy)}.`);
    }

    const requester = userInfo(userSnap);
    const now = FV.serverTimestamp();
    tx.create(reqRef, {
      type, status: "pending", amount, currencyCode: ccy, note,
      method, methodKind, reference, proofPath, proofUrl,
      payoutName, payoutNumber, payoutReference: null,
      userId: uid, userName: requester.name, userCode: requester.code,
      recipientId: recipient?.uid ?? null, recipientName: recipient?.name ?? null, recipientCode: recipient?.code ?? null,
      recipientAmount, recipientCurrency: recipientCcy,
      fxRates: recipient && recipientCcy !== ccy ? { [ccy]: perUsd(fx, ccy), [recipientCcy!]: perUsd(fx, recipientCcy!) } : null,
      dayKey: day, source: "app", createdAt: now, updatedAt: now,
    });
    if (type === "deposit") {
      // Shown as pending; not applied to the balance until approved.
      tx.create(txRef(uid, `wreq_${reqRef.id}`), {
        amount, type: "top_up", title: `Top up via ${method ?? "manual payment"}`, currencyCode: ccy,
        status: "pending", balanceAfter: bal, meta: { requestId: reqRef.id, reference, applied: false }, createdAt: now,
      });
    } else {
      // Send / Withdraw: the amount leaves the balance now (= the hold).
      const after = toMoney(bal - amount);
      tx.set(wRef, { balance: after, currencyCode: ccy, updatedAt: now }, { merge: true });
      tx.create(txRef(uid, `wreq_${reqRef.id}`), type === "transfer"
        ? {
          amount: -amount, type: "send", title: `Send to ${recipient!.name}`, currencyCode: ccy,
          status: "pending", balanceAfter: after,
          meta: { requestId: reqRef.id, recipientId: recipient!.uid, recipientName: recipient!.name, note }, createdAt: now,
        }
        : {
          amount: -amount, type: "withdraw", title: withdrawTitle(method, methodKind), currencyCode: ccy,
          status: "pending", balanceAfter: after,
          meta: { requestId: reqRef.id, method, methodKind, payoutName, payoutNumber: maskNumber(payoutNumber), note }, createdAt: now,
        });
    }
    tx.set(dailyRef(uid, day), { dayKey: day, [type]: FV.increment(cents(amount)), updatedAt: now }, { merge: true });
    return { requestId: reqRef.id, status: "pending", duplicate: false, requester, ccy, recipientAmount: recipientAmount ?? 0 };
  });
  const converted = type === "transfer" && recipientCcy && recipientCcy !== result.ccy
    ? ` (they receive ${money(result.recipientAmount, recipientCcy)})` : "";

  if (!result.duplicate && result.requester) {
    const who = `${result.requester.name}${result.requester.code ? ` (${result.requester.code})` : ""}`;
    const what = type === "deposit"
      ? `submitted a top up of ${money(amount, result.ccy)} via ${method ?? "manual payment"} (ref ${reference})`
      : type === "withdraw"
        ? `wants to withdraw ${money(amount, result.ccy)} via ${method}${payoutNumber ? ` to ${payoutName} · ${payoutNumber}` : methodKind === "office" ? " (office pickup)" : ""}`
        : `wants to send ${money(amount, result.ccy)}${converted} to ${recipient!.name}${recipient!.code ? ` (${recipient!.code})` : ""}`;
    try {
      await db().collection("admin_notifications").add({
        type: "wallet_request", requiredPermission: ADMIN_PERMISSION,
        title: `Wallet ${LABEL[type].toLowerCase()} request`,
        message: `${who} ${what}.${note ? ` Note: "${note}"` : ""} Review it before it goes through.`,
        link: "/wallet", sourceCollection: "wallet_requests", sourceId: result.requestId,
        meta: { userId: uid, name: result.requester.name, email: null },
        createdAt: FV.serverTimestamp(), readBy: {},
      });
    } catch (err) {
      logger.error("[walletRequests] admin notification failed", { error: String(err) });
    }
    await notifyWalletUser(uid, `${LABEL[type]} request submitted`,
      type === "deposit"
        ? `Your top up of ${money(amount, result.ccy)} is waiting for Giggre to confirm your payment.`
        : type === "withdraw"
          ? methodKind === "office"
            ? `Your withdrawal of ${money(amount, result.ccy)} is on hold for pickup at ${method}. Bring a valid ID; Giggre completes it when you receive the cash.`
            : `Your withdrawal of ${money(amount, result.ccy)} via ${method} is waiting for Giggre to pay it out. The amount is on hold until then.`
          : `Sending ${money(amount, result.ccy)} to ${recipient!.name} is waiting for review. The amount is on hold until it's decided.`,
      { requestId: result.requestId, status: "pending", requestType: type });
  }
  return { requestId: result.requestId, status: result.status };
});

// ── Settle ──────────────────────────────────────────────────────────────────

type Outcome = "approved" | "rejected" | "cancelled";
interface Settled { method: string | null; methodKind: string | null; payoutReference: string | null; type: WType; amount: number; ccy: string; userId: string; userName: string; userCode: string | null; recipientId: string | null; recipientName: string | null; recipientAmount: number; recipientCcy: string }

async function settle(requestId: string, outcome: Outcome, opts: { actor?: Actor; ownerUid?: string; note?: string | null; payoutReference?: string | null }): Promise<Settled> {
  const reqRef = db().collection("wallet_requests").doc(requestId);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(reqRef);
    if (!snap.exists) throw new HttpsError("not-found", "Request not found.");
    const r = snap.data()!;
    if (opts.ownerUid && r.userId !== opts.ownerUid) throw new HttpsError("permission-denied", "Not your request.");
    if (r.status !== "pending") throw new HttpsError("failed-precondition", `This request is already ${r.status}.`);
    const type = r.type as WType;
    const amount = amountOf(r.amount);
    if (!WALLET_REQUEST_TYPES.includes(type) || amount == null) throw new HttpsError("data-loss", "Malformed request.");
    const uid = r.userId as string;
    const rid = (r.recipientId as string | null) ?? null;
    const ccy = str(r.currencyCode) ?? "USD";

    const [wSnap, rUser, rWallet] = await Promise.all([
      tx.get(walletRef(uid)),
      outcome === "approved" && rid ? tx.get(db().collection("users").doc(rid)) : Promise.resolve(null),
      outcome === "approved" && rid ? tx.get(walletRef(rid)) : Promise.resolve(null),
    ]);
    if (outcome === "approved" && type === "transfer" && !rUser?.exists) {
      throw new HttpsError("failed-precondition", "The recipient's account no longer exists. Reject this request to refund the sender.");
    }
    const bal = toMoney(Number(wSnap.data()?.balance) || 0);
    const now = FV.serverTimestamp();
    const mainTx = txRef(uid, `wreq_${requestId}`);

    if (outcome === "approved") {
      if (type === "deposit") {
        const after = toMoney(bal + amount);
        tx.set(walletRef(uid), { balance: after, currencyCode: ccy, updatedAt: now, ...(wSnap.exists ? {} : { createdAt: now }) }, { merge: true });
        tx.set(mainTx, { status: "completed", balanceAfter: after, "meta": { requestId, reference: r.reference ?? null, applied: true } }, { merge: true });
      } else if (type === "withdraw") {
        // Already taken from the balance at request time; just complete it.
        if (r.methodKind !== "office" && !opts.payoutReference) {
          throw new HttpsError("invalid-argument", "Enter the payout reference / control number.");
        }
        tx.set(mainTx, { status: "completed", meta: { payoutReference: opts.payoutReference ?? null } }, { merge: true });
      } else {
        tx.set(mainTx, { status: "completed" }, { merge: true });
        const rBal = toMoney(Number(rWallet?.data()?.balance) || 0);
        // Locked at request time; older requests (same currency) fall back to amount.
        const rCcy = str(r.recipientCurrency) ?? str(rWallet?.data()?.currencyCode) ?? str(rUser?.data()?.currencyCode) ?? ccy;
        const rAmount = toMoney(Number(r.recipientAmount) || amount);
        const rAfter = toMoney(rBal + rAmount);
        tx.set(walletRef(rid!), { balance: rAfter, currencyCode: rCcy, updatedAt: now, ...(rWallet?.exists ? {} : { createdAt: now }) }, { merge: true });
        tx.create(txRef(rid!, `wreq_${requestId}_in`), {
          amount: rAmount, type: "receive", title: `From ${r.userName ?? "a Giggre user"}`, currencyCode: rCcy,
          status: "completed", balanceAfter: rAfter,
          meta: { requestId, senderId: uid, senderName: r.userName ?? null, note: r.note ?? null, sentAmount: amount, sentCurrency: ccy }, createdAt: now,
        });
      }
    } else {
      if (type === "deposit") {
        tx.set(mainTx, { status: "failed" }, { merge: true });
      } else {
        const after = toMoney(bal + amount);
        tx.set(mainTx, { status: "reversed" }, { merge: true });
        tx.set(walletRef(uid), { balance: after, updatedAt: now }, { merge: true });
        const what = type === "withdraw" ? "Withdrawal" : "Send";
        tx.create(txRef(uid, `wreq_${requestId}_refund`), {
          amount, type: "refund", title: outcome === "cancelled" ? `${what} cancelled — refund` : `${what} rejected — refund`,
          currencyCode: ccy, status: "completed", balanceAfter: after, meta: { requestId }, createdAt: now,
        });
      }
      if (typeof r.dayKey === "string") {
        tx.set(dailyRef(uid, r.dayKey), { [type]: FV.increment(-cents(amount)), updatedAt: now }, { merge: true });
      }
    }
    tx.update(reqRef, {
      status: outcome, decidedAt: now,
      decidedBy: opts.actor?.uid ?? opts.ownerUid ?? null, decidedByName: opts.actor?.name ?? null,
      decisionNote: opts.note ?? null, updatedAt: now,
      ...(type === "withdraw" && outcome === "approved" ? { payoutReference: opts.payoutReference ?? null } : {}),
    });
    return { method: str(r.method), methodKind: str(r.methodKind), payoutReference: opts.payoutReference ?? null,
      type, amount, ccy, userId: uid, userName: r.userName ?? "Giggre user", userCode: r.userCode ?? null, recipientId: rid, recipientName: r.recipientName ?? null,
      recipientAmount: toMoney(Number(r.recipientAmount) || amount), recipientCcy: str(r.recipientCurrency) ?? ccy };
  });
}

export const decideWalletRequest = onCall(OPTS, async (request) => {
  const actor = await requireWalletAdmin(request.auth?.uid);
  const d = (request.data ?? {}) as Record<string, unknown>;
  const requestId = str(d.requestId);
  if (!requestId || requestId.includes("/")) throw new HttpsError("invalid-argument", "requestId is required.");
  if (d.decision !== "approve" && d.decision !== "reject") throw new HttpsError("invalid-argument", "decision must be approve or reject.");
  const outcome: Outcome = d.decision === "approve" ? "approved" : "rejected";
  const note = optText(d.note, 200, "Note");
  if (outcome === "rejected" && !note) throw new HttpsError("invalid-argument", "Give the user a reason for the rejection.");
  const payoutReference = optText(d.reference, 60, "Payout reference");

  const s = await settle(requestId, outcome, { actor, note, payoutReference });
  const amt = money(s.amount, s.ccy);
  if (outcome === "approved") {
    await notifyWalletUser(s.userId, `${LABEL[s.type]} approved`,
      s.type === "deposit" ? `${amt} was added to your Gig Wallet.`
        : s.type === "withdraw" ? withdrawDoneMessage(s, amt)
          : `${amt} was sent to ${s.recipientName ?? "the recipient"}.`,
      { requestId, status: "approved", requestType: s.type });
    if (s.type === "transfer" && s.recipientId) {
      const got = money(s.recipientAmount, s.recipientCcy);
      await notifyWalletUser(s.recipientId, `You received ${got}`, `${s.userName} sent you ${got} GigCash.`,
        { requestId, status: "received", requestType: "transfer" });
    }
  } else {
    await notifyWalletUser(s.userId, `${LABEL[s.type]} request rejected`,
      `Your ${LABEL[s.type].toLowerCase()} of ${amt} was rejected${note ? `: ${note}` : "."}${s.type !== "deposit" ? ` ${amt} was refunded to your Gig Wallet.` : ""}`,
      { requestId, status: "rejected", requestType: s.type });
  }
  await logWalletActivity(actor, outcome === "approved" ? "wallet_request_approved" : "wallet_request_rejected",
    `${outcome === "approved" ? "Approved" : "Rejected"} ${LABEL[s.type].toLowerCase()} of ${amt} for ${s.userName}${s.userCode ? ` (${s.userCode})` : ""}${s.type === "transfer" ? ` → ${s.recipientName}` : ""}${s.type === "withdraw" ? ` via ${s.method ?? "manual payout"}${s.payoutReference ? ` (ref ${s.payoutReference})` : ""}` : ""}${note ? ` — ${note}` : ""}`,
    requestId, s.userName, { type: s.type, amount: s.amount, userId: s.userId, recipientId: s.recipientId, note, payoutReference: s.payoutReference });
  return { status: outcome };
});

export const cancelWalletRequest = onCall(OPTS, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const requestId = str((request.data ?? {}).requestId);
  if (!requestId || requestId.includes("/")) throw new HttpsError("invalid-argument", "requestId is required.");
  await settle(requestId, "cancelled", { ownerUid: uid });
  return { status: "cancelled" };
});

// ── Admin: find a user for a manual balance change ──────────────────────────

export const adminFindWalletUser = onCall(OPTS, async (request) => {
  await requireWalletAdmin(request.auth?.uid);
  const snap = await findUser(String((request.data ?? {}).query ?? ""));
  const u = userInfo(snap);
  const w = (await walletRef(u.uid).get()).data() ?? {};
  return {
    uid: u.uid, name: u.name, code: u.code, photoUrl: u.photoUrl,
    phone: str(snap.data()?.phone), email: str(snap.data()?.email),
    isVerified: str(snap.data()?.isVerified),
    walletBalance: toMoney(Number(w.balance) || 0), currencyCode: walletCurrency(w, snap.data()),
  };
});
