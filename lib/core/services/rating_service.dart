import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/pending_rating.dart';
import '../models/rating_review.dart';
import '../models/submitted_rating.dart';

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

  /// The three gig collections a rating may cite — same list the `ratings`
  /// create rule enforces.
  static const gigCollections = ['quick_gigs', 'open_gigs', 'offered_gigs'];

  /// Mirrors REVEAL_AFTER_DAYS in functions/src/ratings.ts. Past this, the
  /// counterpart rating has already been revealed by the scheduled sweep,
  /// so a rating submitted now is no longer blind.
  static const revealAfterDays = 7;

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

  /// What [raterId] (the signed-in user by default) already submitted for
  /// this gig, or null if they never rated it. One doc read against a
  /// deterministic id — no query, no index.
  ///
  /// A rater can always read their own rating whether or not it has been
  /// revealed, so this never trips the read rule.
  static Future<SubmittedRating?> myRating({
    required String gigCollection,
    required String gigId,
    required String rateeId,
    String? raterId,
  }) async {
    final uid = raterId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || rateeId.isEmpty) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(
            ratingId(
              gigCollection: gigCollection,
              gigId: gigId,
              raterId: uid,
              rateeId: rateeId,
            ),
          )
          .get();
      return SubmittedRating.fromDoc(snap);
    } on FirebaseException catch (e) {
      // The read rule dereferences `resource.data`, which on a document that
      // does not exist evaluates against a null resource and denies rather
      // than returning an empty snapshot — so the unrated case, the common
      // one here, arrives as permission-denied.
      //
      // Reading that as "not rated" is sound only because the id embeds the
      // rater's own uid: any document under it necessarily has
      // `raterId == uid`, which the rule always allows. A denial therefore
      // means there is nothing there.
      if (e.code == 'permission-denied') return null;
      rethrow;
    }
  }

  /// Every rating this user has given, keyed by rating id. One query, and
  /// cheaper than a doc read per gig once a list is involved — [pendingFor]
  /// subtracts these from the completed gigs rather than probing each one,
  /// and a list of finished gigs can render what it left from the same
  /// result instead of re-reading each rating.
  static Future<Map<String, SubmittedRating>> ratingsGivenBy(
    String raterId,
  ) async {
    if (raterId.isEmpty) return {};
    final snap = await FirebaseFirestore.instance
        .collection(_collection)
        .where('raterId', isEqualTo: raterId)
        .get();
    return {
      for (final doc in snap.docs) doc.id: SubmittedRating.fromData(doc.data()),
    };
  }

  /// Completed gigs this user can still rate, newest first.
  ///
  /// Covers both directions and both gig shapes: the gig doc itself for
  /// single-worker gigs, and `workers/{workerId}` slot docs for multi-worker
  /// ones, where the top-level `workerId`/`status` fields are never set.
  ///
  /// Nothing server-side expires the right to rate — the create rule has no
  /// time window and a completed gig keeps its document — so this deliberately
  /// returns everything outstanding rather than only recent gigs. Callers that
  /// want to cut it off can filter on [PendingRating.isPastRevealWindow].
  static Future<List<PendingRating>> pendingFor(String uid) async {
    if (uid.isEmpty) return [];
    final db = FirebaseFirestore.instance;

    Query<Map<String, dynamic>> completed(String collection, String field) => db
        .collection(collection)
        .where(field, isEqualTo: uid)
        .where('status', isEqualTo: 'completed');

    // Quick/open gigs identify their worker with `assignedWorkerId`, offered
    // gigs with `workerId`, and the open-gig selection path writes both —
    // hence both queries per collection rather than one. Duplicates are
    // collapsed by rating id below.
    final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[
      for (final collection in gigCollections) ...[
        completed(collection, 'hostId').get(),
        completed(collection, 'workerId').get(),
        completed(collection, 'assignedWorkerId').get(),
      ],
      db
          .collectionGroup('workers')
          .where('hostId', isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .get(),
      db
          .collectionGroup('workers')
          .where('workerId', isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .get(),
    ];

    final List<QuerySnapshot<Map<String, dynamic>>> snaps;
    final Set<String> alreadyRated;
    try {
      final results = await Future.wait([
        Future.wait(futures),
        ratingsGivenBy(uid),
      ]);
      snaps = results[0] as List<QuerySnapshot<Map<String, dynamic>>>;
      alreadyRated = (results[1] as Map<String, SubmittedRating>).keys.toSet();
    } catch (e) {
      debugPrint('[RatingService] pendingFor lookup failed: $e');
      return [];
    }

    final gigSnaps = snaps.take(gigCollections.length * 3).toList();
    final slotSnaps = snaps.skip(gigCollections.length * 3).toList();

    // Keyed by rating id so a gig matched by two of the queries above — or a
    // multi-worker gig reached from both its slot doc and its gig doc — only
    // ever yields one entry.
    final pending = <String, PendingRating>{};

    void add(PendingRating p) {
      if (p.rateeId.isEmpty || p.rateeId == uid) return;
      final id = p.ratingIdFor(uid);
      if (alreadyRated.contains(id)) return;
      pending[id] = p;
    }

    for (var i = 0; i < gigSnaps.length; i++) {
      final collection = gigCollections[i ~/ 3];
      for (final doc in gigSnaps[i].docs) {
        final d = doc.data();
        // A multi-worker gig's workers are rated per slot, below — its gig
        // doc carries no single counterparty for the host to rate.
        final isMultiWorker = ((d['workerSlots'] as num?)?.toInt() ?? 1) > 1;
        final hostId = d['hostId'] as String? ?? '';
        final workerId =
            d['assignedWorkerId'] as String? ?? d['workerId'] as String? ?? '';
        final isHost = hostId == uid;
        if (isHost && isMultiWorker) continue;
        add(
          PendingRating(
            gigId: doc.id,
            gigCollection: collection,
            gigTitle: d['title'] as String? ?? 'Gig',
            rateeId: isHost ? workerId : hostId,
            rateeName: isHost
                ? (d['assignedWorkerName'] as String? ??
                      d['workerName'] as String? ??
                      'Worker')
                : (d['hostName'] as String? ?? 'Host'),
            rateeRole: isHost ? RateeRole.worker : RateeRole.host,
            completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
          ),
        );
      }
    }

    // Slot docs carry both parties but not the gig title, so resolve the
    // titles in one pass over the distinct gigs rather than a read per slot.
    final slotDocs = [for (final snap in slotSnaps) ...snap.docs];
    final titles = await _gigTitles({
      for (final doc in slotDocs)
        if ((doc.data()['gigCollection'] as String? ?? '').isNotEmpty &&
            (doc.data()['gigId'] as String? ?? '').isNotEmpty)
          '${doc.data()['gigCollection']}/${doc.data()['gigId']}',
    });

    for (final doc in slotDocs) {
      final d = doc.data();
      final gigId = d['gigId'] as String? ?? '';
      final gigCollection = d['gigCollection'] as String? ?? '';
      if (gigId.isEmpty || !gigCollections.contains(gigCollection)) continue;
      final hostId = d['hostId'] as String? ?? '';
      final workerId = d['workerId'] as String? ?? doc.id;
      final isHost = hostId == uid;
      add(
        PendingRating(
          gigId: gigId,
          gigCollection: gigCollection,
          gigTitle: titles['$gigCollection/$gigId'] ?? 'Gig',
          rateeId: isHost ? workerId : hostId,
          rateeName: isHost
              ? (d['workerName'] as String? ?? 'Worker')
              : (d['hostName'] as String? ?? 'Host'),
          rateeRole: isHost ? RateeRole.worker : RateeRole.host,
          // Every rating on a multi-worker gig is scoped to the slot, in both
          // directions — the worker's rating of the host belongs to their own
          // slot on that gig, not to the gig as a whole.
          slotWorkerId: workerId,
          completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
        ),
      );
    }

    final entries = pending.values.toList()
      ..sort((a, b) {
        final at = a.completedAt, bt = b.completedAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
    return entries;
  }

  /// Titles for `{collection}/{gigId}` paths, best-effort — a gig that fails
  /// to load just falls back to the generic label rather than dropping the
  /// pending rating it belongs to.
  static Future<Map<String, String>> _gigTitles(Set<String> paths) async {
    if (paths.isEmpty) return {};
    final db = FirebaseFirestore.instance;
    final entries = await Future.wait(
      paths.map((path) async {
        final parts = path.split('/');
        try {
          final snap = await db.collection(parts[0]).doc(parts[1]).get();
          return MapEntry(path, snap.data()?['title'] as String? ?? 'Gig');
        } catch (e) {
          debugPrint('[RatingService] gig title lookup failed for $path: $e');
          return MapEntry(path, 'Gig');
        }
      }),
    );
    return Map.fromEntries(entries);
  }
}
