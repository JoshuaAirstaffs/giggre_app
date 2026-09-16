import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Which side of the gig is being rated. `worker` means a host is rating the
/// worker they hired; `host` means a worker is rating the host who hired them.
enum RateeRole { worker, host }

/// Writes to the append-only `ratings` collection. Aggregation into the
/// target user's totals happens server-side in `onRatingCreated`
/// (functions/src/ratings.ts) — nothing here touches a user document.
///
/// This replaces three copies of a client-side read-modify-write that each
/// fetched the target's current average, recomputed it locally, and wrote the
/// absolute value back. Two raters landing at once both read the same count
/// and one rating was silently lost; the totals were also client-writable.
class RatingService {
  static const _collection = 'ratings';

  /// Deterministic id for one (gig, rater, ratee) triple. The create rule in
  /// firestore.rules requires the id to equal exactly this, which is what
  /// makes a re-submission fail outright instead of double-counting.
  static String ratingId({
    required String gigCollection,
    required String gigId,
    required String raterId,
    required String rateeId,
  }) => '${gigCollection}__${gigId}__${raterId}__$rateeId';

  /// Suggested tags per direction. Kept short and tappable — a tag costs the
  /// rater nothing and carries more signal than a star on its own.
  static const workerTags = [
    'On time',
    'Did the work well',
    'Good communication',
    'Would book again',
  ];

  static const hostTags = [
    'Clear instructions',
    'Site as described',
    'Paid promptly',
    'Respectful',
  ];

  static List<String> tagsFor(RateeRole role) =>
      role == RateeRole.worker ? workerTags : hostTags;

  /// Submits one rating. Returns normally if the rating was stored *or* if
  /// this rater had already rated this gig — the caller only needs to know
  /// that there is nothing left to ask for. Throws on any other failure so
  /// the dialog can surface it rather than closing as if it had worked.
  ///
  /// [slotWorkerId] is set for multi-worker gigs, where the worker's own
  /// `workers/{workerId}` slot doc — not the gig doc — holds their state.
  static Future<void> submit({
    required String gigCollection,
    required String gigId,
    required String rateeId,
    required RateeRole rateeRole,
    required int stars,
    required String rateeName,
    required String gigTitle,
    List<String> tags = const [],
    String? comment,
    String? slotWorkerId,
  }) async {
    assert(stars >= 1 && stars <= 5);
    final raterId = FirebaseAuth.instance.currentUser?.uid;
    if (raterId == null) {
      throw StateError('Cannot submit a rating while signed out');
    }

    final db = FirebaseFirestore.instance;

    // Denormalised so the history screens can render a rating from the
    // rating document alone. They used to read `hostRating` off the gig doc,
    // which is why multi-worker ratings never appeared in either list.
    final raterName =
        (await db.collection('users').doc(raterId).get()).data()?['name']
            as String? ??
        '';

    final ratingRef = db.collection(_collection).doc(
      ratingId(
        gigCollection: gigCollection,
        gigId: gigId,
        raterId: raterId,
        rateeId: rateeId,
      ),
    );

    final trimmed = comment?.trim();

    try {
      await ratingRef.set({
        'raterId': raterId,
        'rateeId': rateeId,
        'rateeRole': rateeRole.name,
        'gigId': gigId,
        'gigCollection': gigCollection,
        'gigTitle': gigTitle,
        'raterName': raterName,
        'rateeName': rateeName,
        'slotWorkerId': ?slotWorkerId,
        'stars': stars,
        'tags': tags,
        if (trimmed != null && trimmed.isNotEmpty) 'comment': trimmed,
        'createdAt': FieldValue.serverTimestamp(),
        // Both are server-owned and must start empty — the create rule
        // rejects a client that tries to pre-set them.
        'revealedAt': null,
        'aggregated': false,
      });
    } on FirebaseException catch (e) {
      // An already-rated gig fails the create rule (the id is taken and the
      // update rule forbids re-writing the server-owned fields). That is the
      // guard doing its job, not an error worth showing — it's the app
      // restore path in working_ui.dart re-offering a dialog that was
      // previously gated only by an in-memory flag.
      if (e.code == 'permission-denied' && (await ratingRef.get()).exists) {
        return;
      }
      rethrow;
    }
  }
}
