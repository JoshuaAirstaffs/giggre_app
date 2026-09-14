import * as admin from "firebase-admin";

// Server-side backstop for ContentFilterService (lib/core/services/
// content_filter_service.dart) — the client already blocks submission
// before it round-trips to Firestore, but a modified client or a direct API
// call could bypass that. These triggers re-check the same
// app_content/word_filter list after the write lands and scrub anything
// that slipped through.
//
// Matching rules mirror the client exactly: case-insensitive, whole-word/
// phrase only (bounded by `(?<![a-z0-9])term(?![a-z0-9])`, same as the
// client's RegExp) so "asshole" never matches inside "assholetown", and a
// multi-word phrase like "sex for cash" matches as one literal unit.

let cachedTerms: Set<string> | null = null;
let cachedEnabled = false;
let cacheExpiresAt = 0;
const CACHE_TTL_MS = 60_000;

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

async function loadConfig(): Promise<{ enabled: boolean; terms: Set<string> }> {
  const now = Date.now();
  if (cachedTerms && now < cacheExpiresAt) {
    return { enabled: cachedEnabled, terms: cachedTerms };
  }
  const snap = await admin
    .firestore()
    .collection("app_content")
    .doc("word_filter")
    .get();
  const data = snap.data();
  cachedEnabled = data?.enabled === true;
  cachedTerms = new Set(
    ((data?.blockedTerms as string[] | undefined) ?? [])
      .map((t) => t.toLowerCase().trim())
      .filter((t) => t.length > 0)
  );
  cacheExpiresAt = now + CACHE_TTL_MS;
  return { enabled: cachedEnabled, terms: cachedTerms };
}

// True if any of [texts] contains a blocked term/phrase as a whole word.
export async function containsBlockedTerm(
  ...texts: (string | null | undefined)[]
): Promise<boolean> {
  const { enabled, terms } = await loadConfig();
  if (!enabled || terms.size === 0) return false;
  for (const text of texts) {
    if (!text) continue;
    const normalized = text.toLowerCase();
    for (const term of terms) {
      const pattern = new RegExp(`(?<![a-z0-9])${escapeRegExp(term)}(?![a-z0-9])`);
      if (pattern.test(normalized)) return true;
    }
  }
  return false;
}

// Lightweight audit trail so an admin can see what got auto-removed/redacted
// without digging through logs — mirrors the existing activityLogs
// collection's purpose (see firestore.rules).
export async function logAutoModeration(
  collection: string,
  docId: string,
  action: "deleted" | "redacted",
  matchedFields: string[]
): Promise<void> {
  try {
    await admin.firestore().collection("activityLogs").add({
      type: "word_filter_auto_moderation",
      collection,
      docId,
      action,
      matchedFields,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.error("[wordFilter] failed to write activity log:", e);
  }
}
