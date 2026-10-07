import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import { firestoreTriggerRegion } from "./region";

// ── Monthly "Best host" / "Best worker" badges ──────────────────────────────
// Runs on the 8th of each month and awards the previous calendar month
// (Asia/Manila). The 8th is deliberate: ratings stay hidden for up to
// REVEAL_AFTER_DAYS (7) in ratings.ts, so a month-end gig's rating is only
// countable a week later.
//
// The scoring MUST stay in sync with giggre-admin's Analytics page
// (app/analytics/leaderboard.ts + the bestStats block in page.tsx) — admins
// preview the ranking there, and this is what actually awards it.
//
// Writes:
//   badge_awards/{YYYY-MM}                 — the month's top 5 hosts + workers
//   users/{uid}/badges/{YYYY-MM}_{role}    — one doc per winner, for the app
// The month doc doubles as the "already awarded" marker, so re-runs no-op.

const TRIGGER_REGION = firestoreTriggerRegion();
const TIME_ZONE = "Asia/Manila";
const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000; // UTC+8, no DST

const WEIGHTS = { rating: 50, reliability: 30, activity: 20 };
const MIN_COMPLETED = 5;
const MIN_RATINGS = 3;
const RATING_PRIOR_WEIGHT = 5;
const DEFAULT_PRIOR = 4.5;
const BADGE_SLOTS = 5;

const GIG_COLLECTIONS = ["quick_gigs", "open_gigs", "offered_gigs"] as const;
// Slot states that were only an offer the worker never took
const UNACCEPTED_SLOT_STATUSES = new Set(["declined", "ringing", "calling"]);

type Role = "host" | "worker";
type CancelledBy = "host" | "worker" | "none";

interface Outcome {
  userId: string;
  name: string | null;
  completed: boolean;
}

interface Winner {
  rank: number;
  userId: string;
  name: string;
  score: number;
  avgRating: number;
  ratingCount: number;
  completed: number;
  reliability: number;
}

// ── Helpers ─────────────────────────────────────────────────────────────────

const str = (v: unknown): string | null => (typeof v === "string" && v ? v : null);
const millis = (v: unknown): number | null =>
  v instanceof admin.firestore.Timestamp ? v.toMillis() : null;

/** [start, end) of the calendar month before `now`, in Manila time, as UTC ms. */
function previousManilaMonth(now: number) {
  const local = new Date(now + MANILA_OFFSET_MS);
  const y = local.getUTCFullYear();
  const m = local.getUTCMonth() - 1; // previous month (may be -1 → Dec of last year)
  const start = Date.UTC(y, m, 1) - MANILA_OFFSET_MS;
  const end = Date.UTC(y, m + 1, 1) - MANILA_OFFSET_MS;
  const first = new Date(Date.UTC(y, m, 1));
  const key = `${first.getUTCFullYear()}-${String(first.getUTCMonth() + 1).padStart(2, "0")}`;
  const label = first.toLocaleDateString("en-US", { month: "long", year: "numeric", timeZone: "UTC" });
  return { key, label, start, end };
}

/**
 * Same convention as the app's cancellationRequestedBy(): the newest
 * `cancellation_reason` entry's `requestedBy` decides. Legacy entries without
 * it were worker requests; no request at all means the host cancelled directly.
 */
function cancelledByOf(data: FirebaseFirestore.DocumentData): CancelledBy {
  if (data.cancelledByAdmin === true) return "none";
  const reasons = Array.isArray(data.cancellation_reason) ? data.cancellation_reason : [];
  if (reasons.length === 0) return "host";
  const by = reasons[reasons.length - 1]?.requestedBy;
  if (by === "host") return "host";
  if (by === "system") return "none";
  return "worker";
}

function rank(
  outcomes: Outcome[],
  stars: Map<string, number[]>,
  users: Map<string, FirebaseFirestore.DocumentData>,
  now: number,
): Winner[] {
  const stats = new Map<string, { name: string | null; completed: number; cancelled: number }>();
  for (const o of outcomes) {
    const s = stats.get(o.userId) ?? { name: null, completed: 0, cancelled: 0 };
    s.name ??= o.name;
    if (o.completed) s.completed++;
    else s.cancelled++;
    stats.set(o.userId, s);
  }
  for (const id of stars.keys()) {
    if (!stats.has(id)) stats.set(id, { name: null, completed: 0, cancelled: 0 });
  }

  const allStars = [...stars.values()].flat();
  const prior = allStars.length ? allStars.reduce((a, b) => a + b, 0) / allStars.length : DEFAULT_PRIOR;
  const maxCompleted = Math.max(1, ...[...stats.values()].map((s) => s.completed));

  const scored = [...stats.entries()].map(([userId, s]) => {
    const user = users.get(userId);
    const own = stars.get(userId) ?? [];
    const sum = own.reduce((a, b) => a + b, 0);
    const adjusted = (RATING_PRIOR_WEIGHT * prior + sum) / (RATING_PRIOR_WEIGHT + own.length);
    const finished = s.completed + s.cancelled;
    const reliability = finished ? s.completed / finished : 0;
    const activity = Math.log1p(s.completed) / Math.log1p(maxCompleted);
    const suspendedUntil = millis(user?.suspended_until);

    const eligible =
      user?.isVerified === "verified" &&
      user?.isDeleted !== true &&
      user?.isBanned !== true &&
      !(suspendedUntil != null && suspendedUntil > now) &&
      s.completed >= MIN_COMPLETED &&
      own.length >= MIN_RATINGS;

    return {
      eligible,
      userId,
      name: str(user?.name) ?? s.name ?? userId.slice(0, 10),
      score: Math.round(
        WEIGHTS.rating * ((adjusted - 1) / 4) +
        WEIGHTS.reliability * reliability +
        WEIGHTS.activity * activity
      ),
      avgRating: own.length ? Math.round((sum / own.length) * 100) / 100 : 0,
      ratingCount: own.length,
      completed: s.completed,
      reliability: Math.round(reliability * 100),
    };
  });

  const ranked = scored
    .filter((e) => e.eligible)
    .sort((a, b) => b.score - a.score || b.completed - a.completed || a.name.localeCompare(b.name));

  const winners: Winner[] = [];
  ranked.forEach((e, i) => {
    const prev = winners[i - 1];
    const { eligible: _eligible, ...rest } = e;
    void _eligible;
    winners.push({ ...rest, rank: prev && prev.score === e.score ? prev.rank : i + 1 });
  });
  // Everyone tied into the last badge slot gets it
  return winners.filter((w) => w.rank <= BADGE_SLOTS);
}

// ── Award ───────────────────────────────────────────────────────────────────

export async function awardBadgesForPreviousMonth(now = Date.now()) {
  const db = admin.firestore();
  const month = previousManilaMonth(now);
  const awardRef = db.collection("badge_awards").doc(month.key);

  if ((await awardRef.get()).exists) {
    console.log(`[badges] ${month.key} already awarded — skipping`);
    return;
  }

  const inMonth = (ms: number | null) => ms != null && ms >= month.start && ms < month.end;

  const [userSnap, slotSnap, ratingSnap, ...gigSnaps] = await Promise.all([
    db.collection("users").get(),
    db.collectionGroup("workers").get(),
    db.collection("ratings").where("revealedAt", "!=", null).get(),
    ...GIG_COLLECTIONS.map((c) => db.collection(c).get()),
  ]);

  const users = new Map(userSnap.docs.map((d) => [d.id, d.data()]));

  // Multi-worker slots, keyed by their parent gig
  const slotsByGig = new Map<string, FirebaseFirestore.DocumentData[]>();
  for (const d of slotSnap.docs) {
    const gigRef = d.ref.parent.parent;
    if (!gigRef || !(GIG_COLLECTIONS as readonly string[]).includes(gigRef.parent.id)) continue;
    const data = d.data();
    if (UNACCEPTED_SLOT_STATUSES.has(data.status)) continue;
    const key = `${gigRef.parent.id}/${gigRef.id}`;
    slotsByGig.set(key, [...(slotsByGig.get(key) ?? []), { ...data, workerId: str(data.workerId) ?? d.id }]);
  }

  const hostOutcomes: Outcome[] = [];
  const workerOutcomes: Outcome[] = [];
  gigSnaps.forEach((snap, i) => {
    for (const d of snap.docs) {
      const g = d.data();
      const status = String(g.status ?? "").toLowerCase();
      const createdMs = millis(g.createdAt);
      const completedMs = millis(g.completedAt) ?? createdMs;
      const cancelledMs = millis(g.cancelledAt) ?? createdMs;
      const cancelledBy = cancelledByOf(g);
      const slots = slotsByGig.get(`${GIG_COLLECTIONS[i]}/${d.id}`) ?? [];
      const workerId = str(g.workerId) ?? str(g.assignedWorkerId);
      const hostId = str(g.hostId);

      // Hosts: completed gigs, and cancellations they caused after hiring someone
      if (hostId) {
        const hostName = str(g.hostName) ?? str(g.postedBy);
        if (status === "completed" && inMonth(completedMs)) {
          hostOutcomes.push({ userId: hostId, name: hostName, completed: true });
        } else if (status === "cancelled" && (slots.length > 0 || workerId) && cancelledBy === "host" && inMonth(cancelledMs)) {
          hostOutcomes.push({ userId: hostId, name: hostName, completed: false });
        }
      }

      // Workers: per slot on multi-worker gigs, else the gig's own worker
      if (slots.length) {
        for (const sl of slots) {
          const name = str(sl.workerName);
          if (sl.status === "completed" && inMonth(millis(sl.completedAt) ?? completedMs)) {
            workerOutcomes.push({ userId: sl.workerId, name, completed: true });
          } else if (sl.status === "cancelled" && cancelledByOf(sl) === "worker" && inMonth(cancelledMs)) {
            workerOutcomes.push({ userId: sl.workerId, name, completed: false });
          }
        }
      } else if (workerId) {
        const name = str(g.assignedWorkerName) ?? str(g.workerName);
        if (status === "completed" && inMonth(completedMs)) {
          workerOutcomes.push({ userId: workerId, name, completed: true });
        } else if (status === "cancelled" && cancelledBy === "worker" && inMonth(cancelledMs)) {
          workerOutcomes.push({ userId: workerId, name, completed: false });
        }
      }
    }
  });

  const starsFor = (role: Role) => {
    const map = new Map<string, number[]>();
    for (const d of ratingSnap.docs) {
      const r = d.data();
      const stars = Number(r.stars);
      if (r.rateeRole !== role || !str(r.rateeId) || !(stars >= 1 && stars <= 5)) continue;
      if (!inMonth(millis(r.createdAt))) continue;
      map.set(r.rateeId, [...(map.get(r.rateeId) ?? []), stars]);
    }
    return map;
  };

  const hosts = rank(hostOutcomes, starsFor("host"), users, now);
  const workers = rank(workerOutcomes, starsFor("worker"), users, now);

  const batch = db.batch();
  const awardedAt = admin.firestore.FieldValue.serverTimestamp();
  batch.set(awardRef, {
    month: month.key,
    label: month.label,
    awardedAt,
    hosts,
    workers,
    rules: { weights: WEIGHTS, minCompleted: MIN_COMPLETED, minRatings: MIN_RATINGS, slots: BADGE_SLOTS },
  });
  for (const [role, winners] of [["host", hosts], ["worker", workers]] as const) {
    for (const w of winners) {
      batch.set(db.collection("users").doc(w.userId).collection("badges").doc(`${month.key}_${role}`), {
        type: role === "host" ? "best_host" : "best_worker",
        month: month.key,
        label: `Best ${role === "host" ? "Host" : "Worker"} · ${month.label}`,
        rank: w.rank,
        score: w.score,
        awardedAt,
      });
    }
  }
  await batch.commit();
  console.log(`[badges] ${month.key}: awarded ${hosts.length} host(s), ${workers.length} worker(s)`);
}

export const awardMonthlyBadges = onSchedule(
  { schedule: "0 3 8 * *", timeZone: TIME_ZONE, region: TRIGGER_REGION },
  async () => {
    await awardBadgesForPreviousMonth();
  }
);
