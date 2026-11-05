import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { firestoreTriggerRegion } from "./region";

// ── Lookups the app needs BEFORE the user is signed in ─────────────────────
// users/{uid} is readable only by signed-in users (firestore.rules), so the
// two pre-sign-in checks go through these callables instead of querying the
// users collection directly. They return the minimum: a yes/no, or the
// referrer's id + display name — never email, phone or other profile data.
//
//   checkAccountExists({email})   Google / Apple sign-in: existing account
//                                 or a new sign-up?
//   lookupReferralCode({code})    validate a referral code at sign-up

const OPTS = { region: firestoreTriggerRegion(), maxInstances: 10 } as const;
const db = () => admin.firestore();

export const checkAccountExists = onCall(OPTS, async (request) => {
  const email = String((request.data ?? {}).email ?? "").trim();
  if (!email || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpsError("invalid-argument", "Enter a valid email.");
  }
  // Stored as the provider gave it; also try lowercase (Google/Apple are
  // case-insensitive).
  const candidates = Array.from(new Set([email, email.toLowerCase()]));
  const snap = await db().collection("users").where("email", "in", candidates).limit(1).get();
  return { exists: !snap.empty };
});

export const lookupReferralCode = onCall(OPTS, async (request) => {
  const code = String((request.data ?? {}).code ?? "").trim().toUpperCase();
  if (!/^[A-Z0-9]{8}$/.test(code)) throw new HttpsError("invalid-argument", "Referral code must be 8 characters.");
  const snap = await db().collection("users").where("referrals.referral_code", "==", code).limit(1).get();
  if (snap.empty) return { found: false };
  const d = snap.docs[0].data();
  return { found: true, userId: snap.docs[0].id, name: typeof d.name === "string" && d.name ? d.name : "User" };
});
