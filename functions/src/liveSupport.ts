import { getFirestore } from "firebase-admin/firestore";

// ── Live support (TEMPORARY) ────────────────────────────────────────────────
// A real "Giggre Support" account people chat with from the app's floating
// bubble (lib/features/live_support/). It's a public account: anyone can open
// a chat with it straight away, no message request, no daily limit, even if
// it hides from search. Configured per project in
//   general_config/live_support { enabled: bool, supportUid: string }
//
// To remove: delete this file and its one use in directMessages.ts.

const CACHE_MS = 60 * 1000;
let cached: { uid: string | null; at: number } | null = null;

async function liveSupportUid(): Promise<string | null> {
  if (cached && Date.now() - cached.at < CACHE_MS) return cached.uid;
  const cfg = (
    await getFirestore().collection("general_config").doc("live_support").get()
  ).data();
  const uid =
    cfg?.enabled === true && typeof cfg.supportUid === "string" && cfg.supportUid
      ? cfg.supportUid
      : null;
  cached = { uid, at: Date.now() };
  return uid;
}

/** True when either side of a direct chat is the live support account. */
export async function involvesLiveSupport(a: string, b: string): Promise<boolean> {
  const uid = await liveSupportUid();
  return uid !== null && (a === uid || b === uid);
}
