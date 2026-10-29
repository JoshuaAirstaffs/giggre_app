import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { sendPushToUser } from "./push";
import { loadFx, perUsd } from "./fx";

// ── Transaction limit for unverified accounts ──────────────────────────────
// Unverified users (users.isVerified != 'verified') may only transact up to a
// total an admin sets (giggre-admin → Settings → Unverified Account Limit):
//
//   general_config/unverified_limits { enabled, maxUsd }
//
// "Transact" = everything a user does on gigs, as a worker (what they were
// paid) AND as a host (what they paid), counted in total while unverified.
// Totals are kept per currency (converted to USD with the live rate in
// fx.ts when compared), server-only:
//
//   transaction_totals/{uid} { worker: {PHP, USD}, host: {PHP, USD},
//                              gigs, updatedAt, limitNotifiedAt }
//   transaction_totals/{uid}/gigs/{ledgerId}   one marker per completed task
//                                              per side (exactly-once)
//
// Recorded from gigPoints.ts when a host-approved task completes. The app
// checks the total before an unverified user applies to / accepts a gig or
// posts one, and asks them to verify once the limit is reached.

const db = () => admin.firestore();
const FV = admin.firestore.FieldValue;
const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) && v > 0 ? v : null);

export interface LimitConfig { enabled: boolean; maxUsd: number | null }

export async function loadLimitConfig(): Promise<LimitConfig> {
  const d = (await db().collection("general_config").doc("unverified_limits").get()).data();
  return { enabled: !!d && d.enabled === true, maxUsd: num(d?.maxUsd) };
}

/** Sum of {currency: amount} maps in USD (currencies without a rate are skipped). */
export function totalUsd(rates: Record<string, number>, ...maps: (Record<string, unknown> | undefined)[]): number {
  let sum = 0;
  for (const m of maps) {
    for (const [ccy, v] of Object.entries(m ?? {})) {
      const r = ccy === "USD" ? 1 : rates[ccy];
      if (typeof v === "number" && v > 0 && r) sum += v / r;
    }
  }
  return sum;
}

/** What one finished task was worth: the confirmed amount, else the budget. */
export function taskAmount(target: FirebaseFirestore.DocumentData, gig: FirebaseFirestore.DocumentData): number {
  return num(target.finalAmount) ?? num(target.adjustedAmount) ?? num(target.budget) ?? num(gig.budget) ?? 0;
}

export async function recordCompletedTask(e: {
  ledgerId: string;
  workerId: string;
  hostId: string | null;
  amount: number;
  currencyCode: string;
}): Promise<void> {
  if (e.amount <= 0) return;
  const ccy = e.currencyCode || "USD";
  const sides: [uid: string, side: "worker" | "host"][] = [[e.workerId, "worker"]];
  if (e.hostId && e.hostId !== e.workerId) sides.push([e.hostId, "host"]);

  const counted = await db().runTransaction(async (tx) => {
    const markers = await Promise.all(sides.map(([uid]) =>
      tx.get(db().collection("transaction_totals").doc(uid).collection("gigs").doc(e.ledgerId))));
    const now = FV.serverTimestamp();
    const done: string[] = [];
    sides.forEach(([uid, side], i) => {
      if (markers[i].exists) return; // already counted (retry / duplicate event)
      const ref = db().collection("transaction_totals").doc(uid);
      tx.create(markers[i].ref, { side, amount: e.amount, currencyCode: ccy, createdAt: now });
      tx.set(ref, { [side]: { [ccy]: FV.increment(e.amount) }, gigs: FV.increment(1), updatedAt: now }, { merge: true });
      done.push(uid);
    });
    return done;
  });

  for (const uid of counted) {
    try {
      await notifyIfLimitReached(uid);
    } catch (err) {
      logger.warn("[unverifiedLimits] limit check failed", { uid, error: String(err) });
    }
  }
}

/** One push + in-app notice the first time an unverified user hits the limit. */
async function notifyIfLimitReached(uid: string): Promise<void> {
  const config = await loadLimitConfig();
  if (!config.enabled || config.maxUsd == null) return;
  const [userSnap, totalsSnap] = await Promise.all([
    db().collection("users").doc(uid).get(),
    db().collection("transaction_totals").doc(uid).get(),
  ]);
  if (userSnap.data()?.isVerified === "verified") return;
  const t = totalsSnap.data() ?? {};
  if (t.limitNotifiedAt) return;
  let rates: Record<string, number> = { USD: 1 };
  try {
    rates = { USD: 1, PHP: perUsd(await loadFx(), "PHP") };
  } catch {
    // No PHP rate yet — only USD amounts can be compared.
  }
  const used = totalUsd(rates, t.worker, t.host);
  if (used < config.maxUsd) return;

  await totalsSnap.ref.set({ limitNotifiedAt: FV.serverTimestamp() }, { merge: true });
  const title = "Verify your account to keep going";
  const message =
    "You've reached the transaction limit for unverified accounts. Verify your account to apply for, accept and post more gigs.";
  await db().collection("notifications").add({
    userId: uid, category: "account_verification", title, message, createdAt: FV.serverTimestamp(),
  });
  await sendPushToUser(uid, { title, body: message, channelId: "verification_status_v1", data: { type: "unverified_limit_reached" } });
}

