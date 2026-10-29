import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { sendPushToUser } from "./push";
import { loadFx, perUsd } from "./fx";
import { firestoreTriggerRegion } from "./region";
import { findUser, userInfo } from "./gigPointsRequests";

// ── Transaction limit for unverified accounts ──────────────────────────────
// Unverified users (users.isVerified != 'verified') may only transact up to a
// total an admin sets (giggre-admin → Settings → Unverified Account Limit):
//
//   general_config/unverified_limits { enabled, maxUsd,
//     resetPeriod: never|daily|weekly|monthly|yearly,   // automatic reset
//     resetEpoch: ms | null }                          // "Reset all now"
//
// "Transact" = everything a user does on gigs, as a worker (what they were
// paid) AND as a host (what they paid), counted in total while unverified.
// Totals are kept per currency (converted to USD with the live rate in
// fx.ts when compared), server-only:
//
//   transaction_totals/{uid} { periodKey, worker: {PHP, USD},
//                              host: {PHP, USD}, gigs, updatedAt,
//                              limitNotifiedAt }
//   transaction_totals/{uid}/gigs/{ledgerId}   one marker per completed task
//                                              per side (exactly-once)
//
// Resets are lazy: the totals only count while their periodKey equals the
// current one (see periodKey — calendar periods in Philippine time, weeks
// start Monday). A new period, a changed reset period or "Reset all now"
// (bumps resetEpoch) gives a new key, so old totals simply stop counting and
// the next completed task starts fresh. No scheduled job needed. The app
// mirrors periodKey in lib/core/services/unverified_limit.dart — keep both
// in sync. An admin can also reset one user (adminUnverifiedUsage).
//
// Recorded from gigPoints.ts when a host-approved task completes. The app
// checks the total before an unverified user applies to / accepts a gig or
// posts one, and asks them to verify once the limit is reached.

const db = () => admin.firestore();
const FV = admin.firestore.FieldValue;
const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) && v > 0 ? v : null);

export const RESET_PERIODS = ["never", "daily", "weekly", "monthly", "yearly"] as const;
export type ResetPeriod = (typeof RESET_PERIODS)[number];

export interface LimitConfig {
  enabled: boolean;
  maxUsd: number | null;
  resetPeriod: ResetPeriod;
  resetEpoch: number;
}

export async function loadLimitConfig(): Promise<LimitConfig> {
  const d = (await db().collection("general_config").doc("unverified_limits").get()).data();
  const period = RESET_PERIODS.includes(d?.resetPeriod) ? (d!.resetPeriod as ResetPeriod) : "never";
  return {
    enabled: !!d && d.enabled === true,
    maxUsd: num(d?.maxUsd),
    resetPeriod: period,
    resetEpoch: num(d?.resetEpoch) ?? 0,
  };
}

const PH_OFFSET_MS = 8 * 60 * 60 * 1000; // Asia/Manila, no DST
const pad = (n: number) => String(n).padStart(2, "0");

/** Key of the current counting period. Totals with another key are stale (= 0). */
export function periodKey(cfg: Pick<LimitConfig, "resetPeriod" | "resetEpoch">, nowMs = Date.now()): string {
  const t = new Date(nowMs + PH_OFFSET_MS); // read with getUTC* = Manila wall clock
  const y = t.getUTCFullYear(), m = t.getUTCMonth() + 1, d = t.getUTCDate();
  let bucket: string;
  switch (cfg.resetPeriod) {
    case "daily": bucket = `${y}-${pad(m)}-${pad(d)}`; break;
    case "weekly": {
      const mon = new Date(Date.UTC(y, m - 1, d - ((t.getUTCDay() + 6) % 7)));
      bucket = `${mon.getUTCFullYear()}-${pad(mon.getUTCMonth() + 1)}-${pad(mon.getUTCDate())}`;
      break;
    }
    case "monthly": bucket = `${y}-${pad(m)}`; break;
    case "yearly": bucket = `${y}`; break;
    default: bucket = "all";
  }
  return `${Math.round(cfg.resetEpoch)}|${cfg.resetPeriod}|${bucket}`;
}

// Totals written before resets existed have no periodKey: they belong to
// the default "never reset" period.
const keyOf = (t: FirebaseFirestore.DocumentData | undefined) => (t ? t.periodKey ?? "0|never|all" : null);

/** worker/host maps of a totals doc, or empty when they belong to an old period. */
function currentTotals(t: FirebaseFirestore.DocumentData | undefined, key: string) {
  if (!t || keyOf(t) !== key) return { worker: {}, host: {}, gigs: 0, limitNotifiedAt: null };
  return { worker: t.worker ?? {}, host: t.host ?? {}, gigs: Number(t.gigs) || 0, limitNotifiedAt: t.limitNotifiedAt ?? null };
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

  const key = periodKey(await loadLimitConfig());

  const counted = await db().runTransaction(async (tx) => {
    const refs = sides.map(([uid]) => db().collection("transaction_totals").doc(uid));
    const markers = await Promise.all(refs.map((ref) => tx.get(ref.collection("gigs").doc(e.ledgerId))));
    const totals = await Promise.all(refs.map((ref) => tx.get(ref)));
    const now = FV.serverTimestamp();
    const done: string[] = [];
    sides.forEach(([uid, side], i) => {
      if (markers[i].exists) return; // already counted (retry / duplicate event)
      tx.create(markers[i].ref, { side, amount: e.amount, currencyCode: ccy, periodKey: key, createdAt: now });
      if (keyOf(totals[i].data()) === key) {
        tx.set(refs[i], { [side]: { [ccy]: FV.increment(e.amount) }, gigs: FV.increment(1), updatedAt: now }, { merge: true });
      } else {
        // New period (or reset): start the totals over with this task.
        tx.set(refs[i], {
          periodKey: key, worker: {}, host: {}, [side]: { [ccy]: e.amount }, gigs: 1,
          limitNotifiedAt: null, periodStartedAt: now, updatedAt: now,
        });
      }
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
  const t = currentTotals(totalsSnap.data(), periodKey(config));
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


// ── Admin: look up / reset one user's totals ───────────────────────────────
// adminUnverifiedUsage({query, reset?}) — super admins (Settings page).
// Returns the user's usage in the current period; with reset: true, starts
// their totals over now (logged in activityLogs).
export const adminUnverifiedUsage = onCall({ region: firestoreTriggerRegion(), maxInstances: 10 }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const a = (await db().collection("admins").doc(uid).get()).data();
  if (!a || a.isActive !== true || a.isPending !== false || a.role !== "super_admin") {
    throw new HttpsError("permission-denied", "Only super admins can do this.");
  }
  const data = request.data ?? {};
  const snap = await findUser(String(data.query ?? ""));
  const u = userInfo(snap);
  const config = await loadLimitConfig();
  const key = periodKey(config);
  const ref = db().collection("transaction_totals").doc(u.uid);

  if (data.reset === true) {
    await ref.set({
      periodKey: key, worker: {}, host: {}, gigs: 0, limitNotifiedAt: null,
      periodStartedAt: FV.serverTimestamp(), updatedAt: FV.serverTimestamp(),
      resetAt: FV.serverTimestamp(), resetBy: uid,
    });
    try {
      await db().collection("activityLogs").add({
        actorId: uid, actorName: String(a.name ?? a.email ?? "Admin"), actorEmail: a.email ?? null,
        module: "settings", action: "settings_updated",
        description: `Reset the unverified account limit usage of ${u.name}${u.code ? ` (${u.code})` : ""}`,
        targetSection: null, targetId: `transaction_totals/${u.uid}`, targetName: u.name,
        affectedFiles: [], meta: { from: null, to: null, other: { periodKey: key } }, createdAt: FV.serverTimestamp(),
      });
    } catch (err) {
      logger.warn("[unverifiedLimits] activity log failed", { error: String(err) });
    }
  }

  const t = currentTotals((await ref.get()).data(), key);
  let rates: Record<string, number> = { USD: 1 };
  try {
    rates = { USD: 1, PHP: perUsd(await loadFx(), "PHP") };
  } catch {
    // No PHP rate yet.
  }
  return {
    uid: u.uid, name: u.name, code: u.code, photoUrl: u.photoUrl,
    isVerified: typeof snap.data()?.isVerified === "string" ? snap.data()!.isVerified : "unverified",
    usedUsd: Math.round(totalUsd(rates, t.worker, t.host) * 100) / 100,
    workerUsd: Math.round(totalUsd(rates, t.worker) * 100) / 100,
    hostUsd: Math.round(totalUsd(rates, t.host) * 100) / 100,
    gigs: t.gigs, maxUsd: config.maxUsd, resetPeriod: config.resetPeriod,
  };
});
