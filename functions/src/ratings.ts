import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import { containsBlockedTerm, logAutoModeration } from "./wordFilter";
import { firestoreTriggerRegion } from "./region";

// ── Rating aggregation ──────────────────────────────────────────────────────
// `ratings/{ratingId}` is append-only and the single source of truth. Clients
// never touch the aggregate fields on a user doc — everything below runs with
// Admin SDK privileges, which is what lets firestore.rules lock those fields
// down to server-only writes.
//
// Doc id is `{gigCollection}__{gigId}__{raterId}__{rateeId}`, which is what
// makes a second submission for the same (gig, rater, ratee) fail at the
// create rule instead of double-counting. Ratings were previously computed
// client-side with a read-modify-write on the target user doc, so two raters
// landing together silently lost one of the two.

// Bayesian shrinkage toward the platform mean. A worker with no ratings
// scores as average rather than as perfect — the old `?? 5.0` default meant a
// worker's first 4-star rating was a strict downgrade from having none, and
// that number feeds dispatch in quick_gig_matching_service.dart.
//   shrunk = (W * M + sum) / (W + count)
export const RATING_PRIOR_MEAN = 4.6;
export const RATING_PRIOR_WEIGHT = 5;

// Blind reveal window. Neither side sees the other's rating until both have
// submitted or this elapses, so nobody is rating the person standing in front
// of them while able to see what that person said about them.
const REVEAL_AFTER_DAYS = 7;

// index.ts calls setGlobalOptions() in its module body, which runs *after*
// this module is evaluated (commonjs `require` hoists), and v2 bakes
// __endpoint — region included — at definition time. Inheriting the global
// would therefore leave these three on the v2 default rather than the
// project's region, so resolve it here directly.
const TRIGGER_REGION = firestoreTriggerRegion();

const MIN_STARS = 1;
const MAX_STARS = 5;

type RateeRole = "worker" | "host";

// Where each direction's aggregate lives. These are caches of the `ratings`
// collection and nothing else: no value from the pre-existing flat fields
// (ratingAsWorker / ratingCount / ratingAsHost / ratingAsHostCount) is read,
// seeded, or written here. Those are dead data now — a user with no ratings
// in this collection has no rating, whatever the old system recorded.
const AGGREGATE_FIELDS: Record<RateeRole, string> = {
  worker: "ratingWorker",
  host: "ratingHost",
};

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

function shrunkAverage(sum: number, count: number): number {
  return round2(
    (RATING_PRIOR_WEIGHT * RATING_PRIOR_MEAN + sum) /
      (RATING_PRIOR_WEIGHT + count)
  );
}

// The counterpart of a rating is the same gig with rater and ratee swapped —
// deterministic, so finding it needs no query.
function counterpartId(rating: admin.firestore.DocumentData): string {
  return [
    rating.gigCollection,
    rating.gigId,
    rating.rateeId,
    rating.raterId,
  ].join("__");
}

// Reads back what this trigger itself last wrote, and nothing else. A user
// with no aggregate yet starts from zero regardless of any rating the old
// client-side system left on their doc.
function currentAggregate(
  userData: admin.firestore.DocumentData,
  role: RateeRole
): { sum: number; count: number; histogram: Record<string, number> } {
  const existing = userData[AGGREGATE_FIELDS[role]] as
    | admin.firestore.DocumentData
    | undefined;

  if (!existing || typeof existing.count !== "number") {
    return { sum: 0, count: 0, histogram: {} };
  }
  return {
    sum: (existing.sum as number) ?? 0,
    count: existing.count,
    histogram: (existing.histogram as Record<string, number>) ?? {},
  };
}

function ratingSnapshotRevealed(
  snap: admin.firestore.DocumentSnapshot
): boolean {
  return snap.exists && snap.data()?.revealedAt != null;
}

export const onRatingCreated = onDocumentCreated(
  { document: "ratings/{ratingId}", region: TRIGGER_REGION },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const rating = snap.data();
    const rateeId = rating.rateeId as string | undefined;
    const role = rating.rateeRole as RateeRole | undefined;
    const stars = rating.stars as number | undefined;

    if (!rateeId || !role || !AGGREGATE_FIELDS[role]) return;
    if (
      typeof stars !== "number" ||
      !Number.isInteger(stars) ||
      stars < MIN_STARS ||
      stars > MAX_STARS
    ) {
      return;
    }

    const db = admin.firestore();
    const aggregateField = AGGREGATE_FIELDS[role];

    await db.runTransaction(async (tx) => {
      // Trigger delivery is at-least-once, so the `aggregated` marker — set in
      // the same transaction as the increment — is what stops a redelivery
      // from counting the rating twice.
      const ratingSnap = await tx.get(snap.ref);
      if (!ratingSnap.exists) return;
      if (ratingSnap.data()?.aggregated === true) return;

      const userRef = db.collection("users").doc(rateeId);
      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) return;

      const current = currentAggregate(userSnap.data() ?? {}, role);
      const sum = current.sum + stars;
      const count = current.count + 1;
      const histogram = { ...current.histogram };
      const bucket = String(stars);
      histogram[bucket] = (histogram[bucket] ?? 0) + 1;
      const average = round2(sum / count);

      tx.update(userRef, {
        [aggregateField]: {
          sum,
          count,
          histogram,
          average,
          shrunk: shrunkAverage(sum, count),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      });

      tx.update(snap.ref, {
        aggregated: true,
        aggregatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    // Both sides have now rated this gig — reveal the pair together.
    const counterpartRef = db
      .collection("ratings")
      .doc(counterpartId(rating));
    const counterpart = await counterpartRef.get();
    if (!counterpart.exists) return;

    // Each side is checked independently: the counterpart may already have
    // been revealed on its own by revealStaleRatings below, and skipping on
    // that alone would leave this one hidden until the next sweep.
    const revealedAt = admin.firestore.FieldValue.serverTimestamp();
    const batch = db.batch();
    let pending = 0;
    if (!ratingSnapshotRevealed(await snap.ref.get())) {
      batch.update(snap.ref, { revealedAt });
      pending++;
    }
    if (!ratingSnapshotRevealed(counterpart)) {
      batch.update(counterpartRef, { revealedAt });
      pending++;
    }
    if (pending > 0) await batch.commit();
  }
);

// Ratings whose counterpart never arrives would otherwise stay hidden
// forever. Mirrors checkExpiredQuickGigSearches in index.ts.
export const revealStaleRatings = onSchedule(
  { schedule: "every 6 hours", timeZone: "UTC", region: TRIGGER_REGION },
  async () => {
    const db = admin.firestore();
    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - REVEAL_AFTER_DAYS * 24 * 60 * 60 * 1000
    );

    const stale = await db
      .collection("ratings")
      .where("revealedAt", "==", null)
      .where("createdAt", "<=", cutoff)
      .limit(400)
      .get();

    if (stale.empty) return;

    const batch = db.batch();
    for (const doc of stale.docs) {
      batch.update(doc.ref, {
        revealedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    console.log(`[revealStaleRatings] revealed ${stale.size} rating(s)`);
  }
);

// Same treatment as chat/profile/support text. The comment is redacted rather
// than the doc deleted — the stars are a legitimate signal even when the
// note attached to them is not, and deleting would strand the aggregate.
export const onRatingWordFilter = onDocumentCreated(
  { document: "ratings/{ratingId}", region: TRIGGER_REGION },
  async (event) => {
    const rating = event.data?.data();
    if (!rating) return;
    const comment = rating.comment as string | undefined;
    if (!comment) return;
    if (!(await containsBlockedTerm(comment))) return;

    await event.data?.ref.update({
      comment: "[Comment removed for violating community guidelines]",
    });
    await logAutoModeration("ratings", event.params.ratingId, "redacted", [
      "comment",
    ]);
  }
);
