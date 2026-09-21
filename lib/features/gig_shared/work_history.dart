import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/services/rating_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Work history — the completed gigs behind a profile, and the three signals
//  read off them: how recently this person worked, how often the other side
//  came back for more, and whether the two of you have worked together.
//
//  A lifetime gig count says nothing about either. Forty gigs and nothing
//  since spring is a different proposition from four gigs last week, and a
//  worker eleven of whose fourteen hosts booked them again is a different
//  proposition from one whose fourteen never did.
// ─────────────────────────────────────────────────────────────────────────────

/// Gig collections a completed engagement can live in.
const List<String> kGigCollections = ['quick_gigs', 'open_gigs', 'offered_gigs'];

/// How recent still counts as "active". A month is short enough that the
/// label means something and long enough to survive a quiet fortnight.
const Duration kWorkHistoryRecentWindow = Duration(days: 30);

/// Below this many distinct counterparties there is no repeat rate worth
/// showing: one host who did not come back is not a pattern, it is one host.
const int kRepeatRateMinPartners = 2;

/// One finished piece of work, seen from whichever side the profile is for.
///
/// [counterpartyId] is always *the other side*: the host who booked this
/// worker, or the worker this host booked. Resolving it at fetch time is what
/// lets [WorkHistoryStats] treat both roles identically.
class CompletedEngagement {
  final String gigId;
  final String gigCollection;
  final String counterpartyId;
  final DateTime completedAt;

  const CompletedEngagement({
    required this.gigId,
    required this.gigCollection,
    required this.counterpartyId,
    required this.completedAt,
  });

  /// Identity of the engagement rather than of the gig: on a multi-worker gig
  /// the host has one engagement per worker, all sharing a gig id.
  String get key => '$gigCollection/$gigId/$counterpartyId';

  /// Identity of the gig itself — what "gigs completed recently" counts, so a
  /// four-worker gig is one gig however many slots it carried.
  String get gigKey => '$gigCollection/$gigId';
}

/// What a profile says about someone's track record.
///
/// Derived entirely from [CompletedEngagement]s, so it can be built from a
/// fixture in a test without Firestore.
class WorkHistoryStats {
  /// Distinct gigs completed inside [kWorkHistoryRecentWindow].
  final int recentGigs;

  /// When the most recent one finished — null if there are none at all.
  final DateTime? lastCompletedAt;

  /// Distinct people on the other side.
  final int partners;

  /// How many of those came back for a second gig.
  final int repeatPartners;

  /// Gigs this profile and whoever is looking at it have both been on.
  final int sharedGigs;
  final DateTime? lastSharedAt;

  const WorkHistoryStats({
    this.recentGigs = 0,
    this.lastCompletedAt,
    this.partners = 0,
    this.repeatPartners = 0,
    this.sharedGigs = 0,
    this.lastSharedAt,
  });

  static const empty = WorkHistoryStats();

  bool get hasHistory => lastCompletedAt != null;

  bool get isActive => recentGigs > 0;

  bool get hasSharedHistory => sharedGigs > 0;

  /// True only once there are enough counterparties for the rate to mean
  /// anything — see [kRepeatRateMinPartners].
  bool get hasRepeatRate => partners >= kRepeatRateMinPartners;

  /// 0–1, or null when [hasRepeatRate] is false. Never invent a rate for
  /// someone with a single gig: 0 of 1 reads as a black mark rather than as
  /// the absence of evidence it actually is.
  double? get repeatRate =>
      hasRepeatRate ? repeatPartners / partners : null;

  /// Folds engagements into the numbers a profile shows.
  ///
  /// [viewerId] is whoever is looking — pass null for a logged-out or
  /// self view and the shared-history fields stay at zero. [now] exists so
  /// tests can pin the recency window.
  factory WorkHistoryStats.from(
    Iterable<CompletedEngagement> engagements, {
    String? viewerId,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final cutoff = at.subtract(kWorkHistoryRecentWindow);

    // Latest completion per gig, so a multi-worker gig counts once.
    final gigs = <String, DateTime>{};
    // Counterparty → the gigs they were on, so "came back" is a second gig
    // rather than a second slot on the same one.
    final partnerGigs = <String, Set<String>>{};
    final shared = <String>{};
    DateTime? lastShared;
    DateTime? last;

    for (final e in engagements) {
      final existing = gigs[e.gigKey];
      if (existing == null || e.completedAt.isAfter(existing)) {
        gigs[e.gigKey] = e.completedAt;
      }
      if (last == null || e.completedAt.isAfter(last)) last = e.completedAt;

      if (e.counterpartyId.isEmpty) continue;
      (partnerGigs[e.counterpartyId] ??= <String>{}).add(e.gigKey);

      if (viewerId != null && e.counterpartyId == viewerId) {
        shared.add(e.gigKey);
        if (lastShared == null || e.completedAt.isAfter(lastShared)) {
          lastShared = e.completedAt;
        }
      }
    }

    return WorkHistoryStats(
      recentGigs: gigs.values.where((d) => d.isAfter(cutoff)).length,
      lastCompletedAt: last,
      partners: partnerGigs.length,
      repeatPartners: partnerGigs.values.where((g) => g.length > 1).length,
      sharedGigs: shared.length,
      lastSharedAt: lastShared,
    );
  }
}

/// Every gig [uid] has completed in [role], as engagements.
///
/// Four queries, all equality-only so they need no composite index beyond the
/// `workers` collection-group pair already in firestore.indexes.json:
///
///  * the three gig collections, matched on `workerId` for a worker and
///    `hostId` for a host. `workerId` is the field gig_history_screen reads
///    for all three, and every assignment path writes it — quick gigs on
///    accept, open gigs alongside `assignedWorkerId` when the host picks an
///    applicant, offered gigs from the model itself.
///  * `collectionGroup('workers')`, because a multi-worker gig never sets
///    those top-level fields: each worker's completion lives on their own
///    `workers/{uid}` slot doc, which carries `hostId` and `workerId` both.
///
/// The documents themselves transfer, unlike the count() aggregates behind
/// the headline gig count, so this is the most expensive thing a profile
/// does. [UserProfileScreen] keeps it behind a switch for that reason.
Future<List<CompletedEngagement>> fetchCompletedEngagements(
  String uid,
  RateeRole role,
) async {
  final isWorker = role == RateeRole.worker;
  final matchField = isWorker ? 'workerId' : 'hostId';
  final db = FirebaseFirestore.instance;

  try {
    final snaps = await Future.wait([
      for (final c in kGigCollections)
        db
            .collection(c)
            .where(matchField, isEqualTo: uid)
            .where('status', isEqualTo: 'completed')
            .get(),
      db
          .collectionGroup('workers')
          .where(matchField, isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .get(),
    ]);

    // Keyed so a gig arriving from both its top-level doc and this worker's
    // slot doc lands once.
    final results = <String, CompletedEngagement>{};

    void add(CompletedEngagement? e) {
      if (e != null) results[e.key] = e;
    }

    for (var i = 0; i < kGigCollections.length; i++) {
      final collection = kGigCollections[i];
      for (final doc in snaps[i].docs) {
        final d = doc.data();
        add(
          _engagement(
            gigId: doc.id,
            gigCollection: collection,
            counterpartyId: isWorker
                ? d['hostId'] as String?
                : (d['workerId'] ?? d['assignedWorkerId']) as String?,
            // A completed gig that somehow never got a completedAt falls back
            // to when it was created. Deliberately not DateTime.now(), which
            // would dress a gig from last year up as this week's work.
            completedAt: _time(d['completedAt']) ?? _time(d['createdAt']),
          ),
        );
      }
    }

    for (final doc in snaps.last.docs) {
      final d = doc.data();
      final gigId = d['gigId'] as String?;
      final gigCollection = d['gigCollection'] as String?;
      if (gigId == null || gigCollection == null) continue;
      add(
        _engagement(
          gigId: gigId,
          gigCollection: gigCollection,
          counterpartyId: (isWorker ? d['hostId'] : d['workerId']) as String?,
          completedAt: _time(d['completedAt']) ?? _time(d['acceptedAt']),
        ),
      );
    }

    return results.values.toList();
  } catch (e) {
    // A missing index or a denied read should cost the track record, not the
    // whole profile.
    debugPrint('[WorkHistory] fetch failed: $e');
    return const [];
  }
}

DateTime? _time(Object? raw) => (raw as Timestamp?)?.toDate();

/// Null when the record cannot be dated, since every number here is either a
/// date or derived from one.
CompletedEngagement? _engagement({
  required String gigId,
  required String gigCollection,
  required String? counterpartyId,
  required DateTime? completedAt,
}) {
  if (completedAt == null) return null;
  return CompletedEngagement(
    gigId: gigId,
    gigCollection: gigCollection,
    counterpartyId: counterpartyId?.trim() ?? '',
    completedAt: completedAt,
  );
}
