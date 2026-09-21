import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/rating_review.dart';

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

    final ratingRef = db
        .collection(_collection)
        .doc(
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

  /// The most recent revealed ratings this user received in [role].
  ///
  /// Only revealed ones: an unrevealed rating fails the read rule and would
  /// take the whole query down with it, and surfacing it early would defeat
  /// the blind reveal. A null `revealedAt` is not greater than epoch, which
  /// is what filters them out here.
  /// [startAfterRevealedAt] pages the list: pass the `revealedAt` of the last
  /// review already shown to fetch the next batch.
  static Future<List<RatingReview>> recentReviews({
    required String userId,
    required RateeRole role,
    int limit = 5,
    DateTime? startAfterRevealedAt,
  }) async {
    var query = FirebaseFirestore.instance
        .collection(_collection)
        .where('rateeId', isEqualTo: userId)
        .where('rateeRole', isEqualTo: role.name)
        .where(
          'revealedAt',
          isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(0),
        )
        .orderBy('revealedAt', descending: true);

    if (startAfterRevealedAt != null) {
      query = query.startAfter([Timestamp.fromDate(startAfterRevealedAt)]);
    }

    final snap = await query.limit(limit).get();
    final reviews = snap.docs.map(RatingReview.fromDoc).toList();
    if (reviews.isEmpty) return reviews;

    // Profiles show the reviewer's verification standing in place of their
    // name, so resolve it here — one batched read for the whole page rather
    // than a lookup per card. A failure leaves it unknown, which the card
    // renders as no claim at all; it must never fall back to "unverified"
    // and quietly understate a verified reviewer.
    Set<String>? verified;
    try {
      verified = await verifiedAmong(reviews.map((r) => r.raterId));
    } catch (e) {
      debugPrint('[RatingService] reviewer verification lookup failed: $e');
    }
    return [
      for (final r in reviews)
        r.withRaterVerified(
          verified == null || r.raterId.isEmpty
              ? null
              : verified.contains(r.raterId),
        ),
    ];
  }

  /// Firestore caps a `whereIn` at 30 values, so rater lookups go in batches
  /// of that size.
  static const _idLookupChunk = 30;

  /// Which of [userIds] are identity-verified, by the same `isVerified`
  /// field the profile header badges. `users` is publicly readable, so this
  /// needs no extra rule.
  static Future<Set<String>> verifiedAmong(Iterable<String> userIds) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};

    final db = FirebaseFirestore.instance;
    final verified = <String>{};
    for (var i = 0; i < ids.length; i += _idLookupChunk) {
      final chunk = ids.sublist(i, math.min(i + _idLookupChunk, ids.length));
      final snap = await db
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        if (doc.data()['isVerified'] == 'verified') verified.add(doc.id);
      }
    }
    return verified;
  }
}
