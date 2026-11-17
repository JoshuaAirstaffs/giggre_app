import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { firestoreTriggerRegion } from "./region";

// ── Referral counters on sign-up ────────────────────────────────────────────
// Sign-up writes only the new user's profile and their
// users/{referrerId}/referrals_list/{uid} entry. The referrer's own profile
// doc (referrals.* counters + referral_level) is updated here instead of by
// the client, so a burst of sign-ups on one referral code can never fail a
// new user's sign-up on write contention for the referrer's doc.
//
// Counters are RECOUNTED from referrals_list rather than incremented, so the
// function is idempotent (safe to retry) and self-correcting: if several
// sign-ups land at once and one write loses the race, the next one writes the
// right totals anyway. Old app versions that still increment client-side are
// overwritten with the true count on the next sign-up.

const MILESTONES = [
  1, 3, 5, 10, 20, 30, 50, 75, 100, 125, 150, 175, 200,
  300, 350, 400, 450, 500, 550, 600, 700, 800, 900, 1000,
];

/** Same levels the app used (register_screen.dart _updateReferralLevel). */
export function referralLevel(count: number): number {
  let level = 0;
  for (let i = 0; i < MILESTONES.length; i++) if (count >= MILESTONES[i]) level = i + 1;
  return level;
}

/** Recounts a referrer's counters from referrals_list and saves them if changed. */
export async function recountReferrals(referrerId: string): Promise<void> {
  const db = admin.firestore();
  const referrerRef = db.collection("users").doc(referrerId);
  const list = referrerRef.collection("referrals_list");

  const count = async (status?: string) =>
    (await (status ? list.where("isVerified", "==", status) : list).count().get()).data().count;
  const [total, pending, verified, cancelled, rejected] = await Promise.all([
    count(), count("pending"), count("verified"), count("cancelled"), count("rejected"),
  ]);
  // Entries start as 'unverified'; anything without a known status counts as that.
  const notVerified = Math.max(0, total - pending - verified - cancelled - rejected);

  const next = {
    referrals_count: total,
    not_verified_referrals: notVerified,
    pending_referrals: pending,
    verified_referrals: verified,
    cancelled_referrals: cancelled,
    rejected_referrals: rejected,
    referral_level: referralLevel(total),
  };

  const snap = await referrerRef.get();
  if (!snap.exists) return; // referrer deleted
  const current = (snap.get("referrals") ?? {}) as Record<string, unknown>;
  const changed = Object.entries(next).filter(([k, v]) => current[k] !== v);
  if (changed.length === 0) return; // another sign-up's run already saved these totals

  await referrerRef.update(
    Object.fromEntries(changed.map(([k, v]) => [`referrals.${k}`, v])),
  );
}

export const onReferralJoined = onDocumentCreated(
  {
    document: "users/{referrerId}/referrals_list/{userId}",
    region: firestoreTriggerRegion(),
    maxInstances: 50,
    // Recounting is idempotent, so a write that loses a contention race is
    // simply retried.
    retry: true,
  },
  async (event) => {
    // Don't keep retrying an event for hours if something is persistently wrong.
    if (Date.now() - Date.parse(event.time) > 60 * 60 * 1000) return;
    await recountReferrals(event.params.referrerId);
  },
);
