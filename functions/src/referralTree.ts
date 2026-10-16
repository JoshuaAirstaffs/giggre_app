import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

// ── "My referral tree" for the app ──────────────────────────────────────────
// The app's My Referrals tab can only read the caller's own referrals_list
// (see firestore.rules), so levels 2+ and everyone's completed gigs have to
// be gathered here with the Admin SDK. Only what the referrer should see goes
// back: first names, verification, join date and whether each person has
// finished a gig — no emails or other profile fields.
//
// The tree and the earnings math MUST stay in sync with giggre-admin's
// Referral tree (app/referrals/[userId]/page.tsx + lib/referralRewards.ts) —
// admins and users have to see the same numbers.

const GIG_COLLECTIONS = ["quick_gigs", "open_gigs", "offered_gigs"] as const;
// Deep chains are rare; this keeps a bad data loop from running away
const MAX_DEPTH = 10;
// Bounds the work for one call on a very large network
const MAX_MEMBERS = 1000;
// Firestore `in` filters take at most 30 values
const IN_CHUNK = 30;

const LEVEL_LABELS = ["Invited directly", "Level 2", "Level 3"];

interface LevelReward {
  defaultRate: number;
  promoRate: number | null;
  promoFrom: number | null;
  promoUntil: number | null;
  maxEarn: number;
}

// Same factory defaults as giggre-admin's DEFAULT_REWARDS
const DEFAULT_REWARDS: LevelReward[] = [
  { defaultRate: 50, promoRate: null, promoFrom: null, promoUntil: null, maxEarn: 0 },
  { defaultRate: 5, promoRate: null, promoFrom: null, promoUntil: null, maxEarn: 0 },
  { defaultRate: 1, promoRate: null, promoFrom: null, promoUntil: null, maxEarn: 0 },
];

const num = (v: unknown, fallback: number) =>
  typeof v === "number" && isFinite(v) && v >= 0 ? v : fallback;

/** Stored Timestamp, or the older date-only "YYYY-MM-DD" format, → epoch ms. */
function instant(v: unknown, endOfDay: boolean): number | null {
  if (v instanceof admin.firestore.Timestamp) return v.toMillis();
  if (typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v)) {
    // Admins enter these dates in Manila time (UTC+8)
    const ms = new Date(`${v}T${endOfDay ? "23:59:59.999" : "00:00:00"}+08:00`).getTime();
    return isFinite(ms) ? ms : null;
  }
  return null;
}

function parseLevels(raw: Record<string, unknown>): LevelReward[] {
  const levels = raw.levels;
  return DEFAULT_REWARDS.map((d, i) => {
    const l = Array.isArray(levels) ? (levels[i] as Record<string, unknown> | undefined) : undefined;
    return {
      defaultRate: num(l?.defaultRate, d.defaultRate),
      promoRate: typeof l?.promoRate === "number" && l.promoRate >= 0 ? l.promoRate : null,
      promoFrom: instant(l?.promoFrom, false),
      promoUntil: instant(l?.promoUntil, true),
      maxEarn: num(l?.maxEarn, d.maxEarn),
    };
  });
}

function promoActive(level: LevelReward, now: number): boolean {
  return level.promoRate != null && level.promoFrom != null && level.promoUntil != null &&
    now >= level.promoFrom && now < level.promoUntil;
}

const chunks = <T>(items: T[], size: number): T[][] =>
  Array.from({ length: Math.ceil(items.length / size) }, (_, i) => items.slice(i * size, (i + 1) * size));

const firstName = (name: unknown, fallback: string) => {
  const first = typeof name === "string" ? name.trim().split(/\s+/)[0] : "";
  return first || fallback;
};

export const getMyReferralTree = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");
  const db = admin.firestore();

  // ── Walk the tree level by level ──
  interface Edge { uid: string; referrerId: string; listName: unknown; listVerified: unknown; joinedMs: number | null; depth: number }
  const edges: Edge[] = [];
  const seen = new Set<string>([uid]);
  let frontier = [uid];
  for (let depth = 1; depth <= MAX_DEPTH && frontier.length && edges.length < MAX_MEMBERS; depth++) {
    const lists = await Promise.all(
      frontier.map((id) => db.collection("users").doc(id).collection("referrals_list").get()),
    );
    const next: string[] = [];
    lists.forEach((snap, i) => {
      for (const d of snap.docs) {
        if (seen.has(d.id) || edges.length >= MAX_MEMBERS) continue;
        seen.add(d.id);
        const data = d.data();
        edges.push({
          uid: d.id,
          referrerId: frontier[i],
          listName: data.name,
          listVerified: data.isVerified,
          joinedMs: data.joined_at instanceof admin.firestore.Timestamp ? data.joined_at.toMillis() : null,
          depth,
        });
        next.push(d.id);
      }
    });
    frontier = next;
  }

  // ── Profiles: the referrals_list copy of name/verification can be stale ──
  const ids = [uid, ...edges.map((e) => e.uid)];
  const profiles = new Map<string, admin.firestore.DocumentData>();
  for (const part of chunks(ids, 100)) {
    const snaps = await db.getAll(...part.map((id) => db.collection("users").doc(id)));
    for (const s of snaps) if (s.exists) profiles.set(s.id, s.data()!);
  }

  // ── Who has finished at least one gig, as a worker or a host ──
  // Workers: the app's own counter (earnings.completedGigs), or a completed
  // gig naming them. Hosts have no counter, so look for completed gigs.
  const gigDone = new Set<string>();
  for (const id of ids) {
    const completed = profiles.get(id)?.earnings?.completedGigs;
    if (typeof completed === "number" && completed > 0) gigDone.add(id);
  }
  const unknown = ids.filter((id) => !gigDone.has(id));
  const lookups: Promise<void>[] = [];
  for (const part of chunks(unknown, IN_CHUNK)) {
    for (const c of GIG_COLLECTIONS) {
      for (const field of ["hostId", "workerId", "assignedWorkerId"]) {
        lookups.push(
          db.collection(c).where("status", "==", "completed").where(field, "in", part)
            .select(field).get()
            .then((snap) => snap.docs.forEach((g) => {
              const v = g.get(field);
              if (typeof v === "string") gigDone.add(v);
            })),
        );
      }
    }
  }
  await Promise.all(lookups);

  // ── Earnings with the rates in force right now ──
  const levelPeople: number[] = [];
  const levelQualified: number[] = [];
  for (const e of edges) {
    levelPeople[e.depth - 1] = (levelPeople[e.depth - 1] ?? 0) + 1;
    if (gigDone.has(e.uid)) levelQualified[e.depth - 1] = (levelQualified[e.depth - 1] ?? 0) + 1;
  }

  const settingsSnap = await db.collection("referral_settings").doc("rewards").get();
  let earnings: Record<string, unknown> | null = null;
  if (settingsSnap.exists) {
    const raw = settingsSnap.data() ?? {};
    const levels = parseLevels(raw);
    const totalMaxEarn = num(raw.totalMaxEarn, 0);
    const now = Date.now();
    const rows = levels.map((level, i) => {
      const active = promoActive(level, now);
      const rate = active ? level.promoRate! : level.defaultRate;
      const qualified = levelQualified[i] ?? 0;
      const uncapped = qualified * rate;
      const capped = level.maxEarn > 0 && uncapped > level.maxEarn;
      return {
        label: LEVEL_LABELS[i],
        rate,
        promoActive: active,
        promoUntilMs: active ? level.promoUntil : null,
        people: levelPeople[i] ?? 0,
        qualified,
        earned: capped ? level.maxEarn : uncapped,
        capped,
        maxEarn: level.maxEarn,
      };
    });
    const levelsEarned = rows.reduce((s, r) => s + r.earned, 0);
    const totalCapped = totalMaxEarn > 0 && levelsEarned > totalMaxEarn;
    // With no total limit set, per-level limits still bound the total when
    // every level has one — same effective limit giggre-admin shows.
    const levelMaxSum = levels.every((l) => l.maxEarn > 0) ? levels.reduce((s, l) => s + l.maxEarn, 0) : 0;
    const totalMax = totalMaxEarn > 0
      ? (levelMaxSum > 0 ? Math.min(totalMaxEarn, levelMaxSum) : totalMaxEarn)
      : levelMaxSum;
    earnings = {
      levels: rows,
      total: totalCapped ? totalMaxEarn : levelsEarned,
      totalCapped,
      totalMax,
      deeperPeople: levelPeople.slice(levels.length).reduce((s, c) => s + (c ?? 0), 0),
    };
  }

  const root = profiles.get(uid) ?? {};
  const isVerified = (id: string, fallback: unknown) =>
    (profiles.has(id) ? profiles.get(id)!.isVerified : fallback) === "verified";

  return {
    root: {
      uid,
      name: firstName(root.name, "You"),
      referralCode: typeof root.referrals?.referral_code === "string" ? root.referrals.referral_code : null,
      isVerified: root.isVerified === "verified",
      gigDone: gigDone.has(uid),
    },
    members: edges.map((e) => ({
      uid: e.uid,
      referrerId: e.referrerId,
      name: firstName(profiles.get(e.uid)?.name ?? e.listName, "Giggre user"),
      isVerified: isVerified(e.uid, e.listVerified),
      joinedMs: e.joinedMs,
      depth: e.depth,
      gigDone: gigDone.has(e.uid),
    })),
    truncated: edges.length >= MAX_MEMBERS,
    earnings,
  };
});
