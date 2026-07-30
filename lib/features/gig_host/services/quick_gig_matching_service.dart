import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/worker_slot_model.dart';

/// Smart dispatch engine for quick gigs.
/// Runs entirely client-side (no Cloud Functions).
class QuickGigMatchingService {
  // Fallback defaults (used when Firestore config is unavailable)
  static const _defaultReviewWindowSeconds = 30;
  static const _defaultSearchTimeoutMinutes = 5;
  static const _defaultMaxDispatchAttempts = 10;
  static const _defaultMaxSearchRadiusKm = 10.0;

  static const _retryInterval = Duration(seconds: 15);
  static const _pollInterval = Duration(seconds: 3);

  // ── Fetch remote config ─────────────────────────────────────────────────────
  static Future<({Duration reviewWindow, Duration searchTimeout, int maxAttempts, double maxSearchRadiusKm})>
      _fetchConfig() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('quick_gig_config')
          .doc('matching_engine')
          .get();
      final data = doc.data() ?? {};
      final reviewWindow = Duration(
        seconds: (data['review_window_seconds'] as num?)?.toInt() ??
            _defaultReviewWindowSeconds,
      );
      final searchTimeout = Duration(
        minutes: (data['search_timeout_minutes'] as num?)?.toInt() ??
            _defaultSearchTimeoutMinutes,
      );
      final maxAttempts =
          (data['max_dispatch_attempts'] as num?)?.toInt() ??
              _defaultMaxDispatchAttempts;
      final maxSearchRadiusKm =
          (data['max_search_radius_km'] as num?)?.toDouble() ??
              _defaultMaxSearchRadiusKm;
      return (
        reviewWindow: reviewWindow,
        searchTimeout: searchTimeout,
        maxAttempts: maxAttempts,
        maxSearchRadiusKm: maxSearchRadiusKm,
      );
    } catch (_) {
      return (
        reviewWindow: const Duration(seconds: _defaultReviewWindowSeconds),
        searchTimeout: const Duration(minutes: _defaultSearchTimeoutMinutes),
        maxAttempts: _defaultMaxDispatchAttempts,
        maxSearchRadiusKm: _defaultMaxSearchRadiusKm,
      );
    }
  }

  // Prevent duplicate concurrent searches for the same gig
  static final Set<String> _activeSearches = {};

  // ── Haversine distance in km ────────────────────────────────────────────────
  static double _distanceKm(GeoPoint a, GeoPoint b) {
    const R = 6371.0;
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLon = (b.longitude - a.longitude) * pi / 180;
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    return 2 * R * atan2(sqrt(h), sqrt(1 - h));
  }

  // ── Composite score (higher = better match) ─────────────────────────────────
  // Weights: 50% proximity, 30% acceptance rate, 20% rating
  static double _score({
    required double distanceKm,
    required double acceptanceRate,
    required double rating,
  }) {
    final proximity = 1.0 / (1.0 + distanceKm);
    return 0.50 * proximity +
        0.30 * acceptanceRate.clamp(0.0, 1.0) +
        0.20 * (rating / 5.0).clamp(0.0, 1.0);
  }

  // ── Find best available worker ──────────────────────────────────────────────
  static Future<Map<String, dynamic>?> _findBestWorker({
    required GeoPoint gigLocation,
    required List<String> exclude,
    required double maxSearchRadiusKm,
  }) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('isOnline', isEqualTo: true)
        .where('availableForGigs', isEqualTo: true)
        .where('seekingQuickGigs', isEqualTo: true)
        .where('slot', isEqualTo: 'AVAILABLE')
        .get();

    Map<String, dynamic>? best;
    double bestScore = double.negativeInfinity;

    for (final doc in snap.docs) {
      if (exclude.contains(doc.id)) continue;

      final data = doc.data();
      final geo = data['location'] as GeoPoint?;
      if (geo == null) continue;

      final dist = _distanceKm(gigLocation, geo);
      if (dist > maxSearchRadiusKm) continue;

      final rate = (data['acceptanceRate'] as num?)?.toDouble() ?? 1.0;
      final rating = (data['ratingAsWorker'] as num?)?.toDouble() ?? 5.0;
      final score = _score(distanceKm: dist, acceptanceRate: rate, rating: rating);

      if (score > bestScore) {
        bestScore = score;
        best = {'id': doc.id, 'name': data['name'] as String? ?? 'Worker', 'score': score};
      }
    }
    return best;
  }

  // ── Dispatch gig to a worker (legacy single-worker gig) ─────────────────────
  static Future<void> _dispatchToWorker({
    required String gigId,
    required String workerId,
    required String workerName,
  }) async {
    final db = FirebaseFirestore.instance;
    await Future.wait([
      db.collection('quick_gigs').doc(gigId).update({
        'status': 'in_progress',
        'assignedWorkerId': workerId,
        'assignedWorkerName': workerName,
        'dispatchedAt': FieldValue.serverTimestamp(),
      }),
      db.collection('users').doc(workerId).update({'slot': 'LOCKED'}),
    ]);
  }

  // ── Dispatch gig to a candidate slot (multi-worker gig) ──────────────────────
  // Creates the candidate's own `workers/{workerId}` doc instead of writing
  // singular fields on the gig doc, so this candidate's offer/response never
  // touches any other slot already filled/in-flight on the same gig.
  static Future<void> _dispatchToWorkerSlot({
    required String gigId,
    required String workerId,
    required String workerName,
    required String hostId,
    required String hostName,
    required double rate,
    required String currencyCode,
  }) async {
    final db = FirebaseFirestore.instance;
    await Future.wait([
      db
          .collection('quick_gigs')
          .doc(gigId)
          .collection('workers')
          .doc(workerId)
          .set(
            WorkerSlotModel(
              workerId: workerId,
              workerName: workerName,
              gigId: gigId,
              gigCollection: 'quick_gigs',
              hostId: hostId,
              hostName: hostName,
              rate: rate,
              currencyCode: currencyCode,
              status: 'in_progress',
            ).toMap()
              ..['dispatchedAt'] = FieldValue.serverTimestamp(),
          ),
      db.collection('users').doc(workerId).update({'slot': 'LOCKED'}),
    ]);
  }

  // ── Auto-search loop ────────────────────────────────────────────────────────
  /// Posts, dispatches, waits for response, retries with exclusion list.
  /// Marks gig as 'no_worker' after timeout or max attempts with no acceptance.
  static Future<void> startAutoSearch({
    required String gigId,
    required GeoPoint gigLocation,
  }) async {
    if (_activeSearches.contains(gigId)) return;
    _activeSearches.add(gigId);

    final db = FirebaseFirestore.instance;
    final gigRef = db.collection('quick_gigs').doc(gigId);

    try {
      final initSnap = await gigRef.get();
      if (!initSnap.exists) return;
      final initData = initSnap.data()!;
      final workerSlots = (initData['workerSlots'] as num?)?.toInt() ?? 1;

      if (workerSlots <= 1) {
        await _runSingleSlotSearch(gigId: gigId, gigLocation: gigLocation, gigRef: gigRef);
      } else {
        await _runMultiSlotSearch(gigId: gigId, gigLocation: gigLocation, gigRef: gigRef);
      }
    } finally {
      _activeSearches.remove(gigId);
    }
  }

  // ── Legacy single-worker search — unchanged behavior ────────────────────────
  static Future<void> _runSingleSlotSearch({
    required String gigId,
    required GeoPoint gigLocation,
    required DocumentReference<Map<String, dynamic>> gigRef,
  }) async {
    final db = FirebaseFirestore.instance;
    final config = await _fetchConfig();

    int dispatchAttempts = 0;

    try {
      // ── Authoritative search deadline ───────────────────────────────────────
      // Read the gig first so we can reuse an existing searchStartedAt when
      // resuming after an app restart, rather than resetting the 5-minute clock.
      final initSnap = await gigRef.get();
      if (!initSnap.exists) return;
      final initData = initSnap.data()!;
      final initStatus = initData['status'] as String? ?? '';
      final existingStartedAt =
          (initData['searchStartedAt'] as Timestamp?)?.toDate();

      final bool isResuming = existingStartedAt != null &&
          (initStatus == 'scanning' || initStatus == 'in_progress');

      DateTime searchStartedAt;
      if (isResuming) {
        // Continuing after an app restart — keep the original server clock.
        searchStartedAt = existingStartedAt;
      } else {
        // Fresh search: write the server timestamp then read it back.
        await gigRef.update({
          'searchStartedAt': FieldValue.serverTimestamp(),
          'exclusionList': [],
        });
        final freshSnap = await gigRef.get();
        searchStartedAt =
            (freshSnap.data()!['searchStartedAt'] as Timestamp?)?.toDate() ??
            DateTime.now();
      }

      final searchDeadline = searchStartedAt.add(config.searchTimeout);

      while (true) {
        // ── Global deadline — checked BEFORE dispatching ────────────────────
        // Allows any in-flight review window to complete even if the deadline
        // passes mid-offer; the next iteration writes no_worker immediately.
        if (!DateTime.now().isBefore(searchDeadline)) {
          await gigRef.update({
            'status': 'no_worker',
            'assignedWorkerId': null,
            'assignedWorkerName': null,
          });
          return;
        }

        // ── Max dispatch attempts ──────────────────────────
        if (dispatchAttempts >= config.maxAttempts) {
          await gigRef.update({
            'status': 'no_worker',
            'assignedWorkerId': null,
            'assignedWorkerName': null,
          });
          return;
        }

        // ── Check current gig state ────────────────────────
        final gigSnap = await gigRef.get();
        if (!gigSnap.exists) return;
        final gigData = gigSnap.data()!;
        final status = gigData['status'] as String? ?? '';

        if (['cancelled', 'navigating', 'arrived', 'working', 'completed', 'no_worker']
            .contains(status)) {
          return;
        }

        final hostId = gigData['hostId'] as String? ?? '';
        final excluded = [
          ...List<String>.from(gigData['exclusionList'] ?? []),
          if (hostId.isNotEmpty) hostId,
        ];

        // ── Find best eligible worker ──────────────────────
        final worker = await _findBestWorker(
          gigLocation: gigLocation,
          exclude: excluded,
          maxSearchRadiusKm: config.maxSearchRadiusKm,
        );

        if (worker == null) {
          // No eligible workers right now — wait for a new one to come online
          await Future.delayed(_retryInterval);
          continue;
        }

        // ── Dispatch ───────────────────────────────────────
        dispatchAttempts++;
        await _dispatchToWorker(
          gigId: gigId,
          workerId: worker['id'] as String,
          workerName: worker['name'] as String,
        );

        // ── Wait for worker response ───────────────────────
        final reviewDeadline = DateTime.now().add(config.reviewWindow);
        String finalStatus = 'in_progress';

        while (DateTime.now().isBefore(reviewDeadline)) {
          await Future.delayed(_pollInterval);
          final check = await gigRef.get();
          if (!check.exists) return;
          final cs = check.data()!['status'] as String? ?? '';
          if (cs != 'in_progress') {
            finalStatus = cs;
            break;
          }
        }

        // Worker accepted / gig was cancelled
        if (['navigating', 'arrived', 'working', 'completed', 'cancelled'].contains(finalStatus)) {
          return;
        }

        // Worker declined (client wrote status back to 'scanning')
        if (finalStatus == 'scanning') {
          // exclusionList already updated by the worker's _declineDispatch call;
          // no additional write needed here.
          continue;
        }

        // Review timed out — clean up the worker's slot.
        final timedOutWorkerId = worker['id'] as String;

        // If the global deadline has now passed, write no_worker directly
        // instead of bouncing through scanning and waiting one more iteration.
        if (!DateTime.now().isBefore(searchDeadline)) {
          await Future.wait([
            gigRef.update({
              'status': 'no_worker',
              'assignedWorkerId': null,
              'assignedWorkerName': null,
              'exclusionList': FieldValue.arrayUnion([timedOutWorkerId]),
            }),
            db.collection('users').doc(timedOutWorkerId).update({
              'slot': 'AVAILABLE',
              'acceptanceRate': FieldValue.increment(-0.05),
            }),
          ]);
          return;
        }

        // Deadline not yet passed — reset to scanning and try the next worker.
        await Future.wait([
          gigRef.update({
            'status': 'scanning',
            'assignedWorkerId': null,
            'assignedWorkerName': null,
            'exclusionList': FieldValue.arrayUnion([timedOutWorkerId]),
          }),
          db.collection('users').doc(timedOutWorkerId).update({
            'slot': 'AVAILABLE',
            'acceptanceRate': FieldValue.increment(-0.05),
          }),
        ]);
      }
    } catch (e) {
      debugPrint('[QuickGigMatching] auto-search error for $gigId: $e');
      try {
        await gigRef.update({
          'status': 'no_worker',
          'assignedWorkerId': null,
          'assignedWorkerName': null,
        });
      } catch (_) {}
    }
  }

  // ── Multi-worker search — fills N slots, one candidate at a time ────────────
  // Same accept/decline/timeout mechanics as the legacy loop, but each
  // candidate's offer lives on their own `workers/{workerId}` doc instead of
  // the gig doc, so slots already filled/in-flight are never touched by a
  // later candidate's response. Loops until `filledSlotCount == workerSlots`
  // or the search deadline/max-attempts budget (shared across all slots) runs
  // out — a partial fill (>0 but <workerSlots) is a valid, non-error outcome.
  static Future<void> _runMultiSlotSearch({
    required String gigId,
    required GeoPoint gigLocation,
    required DocumentReference<Map<String, dynamic>> gigRef,
  }) async {
    final db = FirebaseFirestore.instance;
    final config = await _fetchConfig();

    int dispatchAttempts = 0;

    try {
      final initSnap = await gigRef.get();
      if (!initSnap.exists) return;
      final initData = initSnap.data()!;
      final workerSlots = (initData['workerSlots'] as num?)?.toInt() ?? 1;
      final ratePerSlot = (initData['ratePerSlot'] as num?)?.toDouble() ??
          (initData['budget'] as num?)?.toDouble() ??
          0;
      final currencyCode = (initData['currencyCode'] as String?) ?? 'PHP';
      final hostId = initData['hostId'] as String? ?? '';
      final hostName = initData['hostName'] as String? ?? '';
      final initStatus = initData['status'] as String? ?? '';
      final existingStartedAt =
          (initData['searchStartedAt'] as Timestamp?)?.toDate();

      final bool isResuming = existingStartedAt != null &&
          ['scanning', 'partially_filled'].contains(initStatus);

      DateTime searchStartedAt;
      if (isResuming) {
        searchStartedAt = existingStartedAt;
      } else {
        await gigRef.update({
          'searchStartedAt': FieldValue.serverTimestamp(),
          'exclusionList': [],
          'status': 'scanning',
        });
        final freshSnap = await gigRef.get();
        searchStartedAt =
            (freshSnap.data()!['searchStartedAt'] as Timestamp?)?.toDate() ??
            DateTime.now();
      }

      final searchDeadline = searchStartedAt.add(config.searchTimeout);

      while (true) {
        final gigSnap = await gigRef.get();
        if (!gigSnap.exists) return;
        final gigData = gigSnap.data()!;
        final status = gigData['status'] as String? ?? '';
        final filledSlotCount = (gigData['filledSlotCount'] as num?)?.toInt() ?? 0;

        if (['cancelled', 'no_worker', 'filled', 'completed'].contains(status)) {
          return;
        }
        if (filledSlotCount >= workerSlots) {
          await gigRef.update({'status': 'filled'});
          return;
        }

        // ── Search-wide budget checks ────────────────────────────────────
        if (!DateTime.now().isBefore(searchDeadline) ||
            dispatchAttempts >= config.maxAttempts) {
          await _endMultiSlotSearch(gigRef: gigRef, workerSlots: workerSlots);
          return;
        }

        final excluded = [
          ...List<String>.from(gigData['exclusionList'] ?? []),
          if (hostId.isNotEmpty) hostId,
        ];

        final worker = await _findBestWorker(
          gigLocation: gigLocation,
          exclude: excluded,
          maxSearchRadiusKm: config.maxSearchRadiusKm,
        );

        if (worker == null) {
          await Future.delayed(_retryInterval);
          continue;
        }

        final candidateId = worker['id'] as String;
        final candidateName = worker['name'] as String;

        // ── Dispatch to this candidate's own slot doc ────────────────────
        dispatchAttempts++;
        await _dispatchToWorkerSlot(
          gigId: gigId,
          workerId: candidateId,
          workerName: candidateName,
          hostId: hostId,
          hostName: hostName,
          rate: ratePerSlot,
          currencyCode: currencyCode,
        );
        if (filledSlotCount == 0) {
          await gigRef.update({'status': 'scanning'});
        }

        // ── Wait for THIS candidate's response ───────────────────────────
        final slotRef = gigRef.collection('workers').doc(candidateId);
        final reviewDeadline = DateTime.now().add(config.reviewWindow);
        String finalStatus = 'in_progress';

        while (DateTime.now().isBefore(reviewDeadline)) {
          await Future.delayed(_pollInterval);
          final check = await slotRef.get();
          if (!check.exists) {
            finalStatus = 'declined';
            break;
          }
          final cs = check.data()?['status'] as String? ?? '';
          if (cs != 'in_progress') {
            finalStatus = cs;
            break;
          }
        }

        if (finalStatus == 'navigating') {
          // Accepted — claim the slot transactionally, then keep looping to
          // fill any remaining capacity.
          await db.runTransaction((tx) async {
            final snap = await tx.get(gigRef);
            final data = snap.data() ?? {};
            final filled = (data['filledSlotCount'] as num?)?.toInt() ?? 0;
            final newFilled = filled + 1;
            tx.update(gigRef, {
              'filledSlotCount': newFilled,
              'status': newFilled >= workerSlots ? 'filled' : 'partially_filled',
            });
          });
          continue;
        }

        // Cancelled mid-offer (host cancelled the whole gig).
        if (finalStatus == 'cancelled') return;

        // Review window timed out with no response from the candidate — the
        // loop must do the cleanup itself (exclude, free their slot, apply
        // the timeout penalty). If the candidate explicitly declined
        // instead, their own decline handler already did all of this with
        // its own penalty — mirrors the legacy loop's "exclusionList already
        // updated by the worker's _declineDispatch call" comment, so no
        // redundant (double-penalty) write happens here for that case.
        if (finalStatus == 'in_progress') {
          await Future.wait([
            gigRef.update({
              'exclusionList': FieldValue.arrayUnion([candidateId]),
            }),
            db.collection('users').doc(candidateId).update({
              'slot': 'AVAILABLE',
              'acceptanceRate': FieldValue.increment(-0.05),
            }),
            slotRef.update({'status': 'declined'}).catchError((_) {}),
          ]);
        }

        if (!DateTime.now().isBefore(searchDeadline)) {
          await _endMultiSlotSearch(gigRef: gigRef, workerSlots: workerSlots);
          return;
        }
        // Deadline not yet passed — loop again and try the next candidate.
      }
    } catch (e) {
      debugPrint('[QuickGigMatching] multi-slot auto-search error for $gigId: $e');
      try {
        final snap = await gigRef.get();
        final workerSlots = (snap.data()?['workerSlots'] as num?)?.toInt() ?? 1;
        await _endMultiSlotSearch(gigRef: gigRef, workerSlots: workerSlots);
      } catch (_) {}
    }
  }

  // Sets the gig's coarse status based on how many slots ended up filled —
  // 'filled' (all), 'partially_filled' (some — a valid, non-error outcome),
  // or 'no_worker' (none), mirroring the legacy single-slot loop's terminal
  // states.
  static Future<void> _endMultiSlotSearch({
    required DocumentReference<Map<String, dynamic>> gigRef,
    required int workerSlots,
  }) async {
    final snap = await gigRef.get();
    final filled = (snap.data()?['filledSlotCount'] as num?)?.toInt() ?? 0;
    await gigRef.update({
      'status': filled >= workerSlots
          ? 'filled'
          : filled > 0
              ? 'partially_filled'
              : 'no_worker',
    });
  }

  // ── Backfill search — fills one slot freed up by a worker cancellation ────
  // Time-boxed to the same admin-configured `search_timeout_minutes`
  // (quick_gig_config/matching_engine) as the initial search — it either
  // finds a replacement within that window or the search closes and the gig
  // just carries on with whoever's left.

  /// Looks for one replacement worker for a slot a worker just cancelled out
  /// of on an already-dispatched multi-worker quick gig. Closes itself once
  /// `search_timeout_minutes` elapses (or on max dispatch attempts) if nobody
  /// accepts — the gig simply continues with fewer workers, same as a
  /// partial initial fill.
  static Future<void> startBackfillSearch({
    required String gigId,
    required GeoPoint gigLocation,
    required String cancelledWorkerId,
  }) async {
    if (_activeSearches.contains(gigId)) return;
    _activeSearches.add(gigId);
    try {
      final gigRef = FirebaseFirestore.instance.collection('quick_gigs').doc(gigId);
      await _runBackfillSlotSearch(
        gigId: gigId,
        gigLocation: gigLocation,
        gigRef: gigRef,
        cancelledWorkerId: cancelledWorkerId,
      );
    } finally {
      _activeSearches.remove(gigId);
    }
  }

  static Future<void> _runBackfillSlotSearch({
    required String gigId,
    required GeoPoint gigLocation,
    required DocumentReference<Map<String, dynamic>> gigRef,
    required String cancelledWorkerId,
  }) async {
    final db = FirebaseFirestore.instance;
    final config = await _fetchConfig();
    final searchDeadline = DateTime.now().add(config.searchTimeout);
    int dispatchAttempts = 0;

    try {
      await gigRef.update({
        'exclusionList': FieldValue.arrayUnion([cancelledWorkerId]),
      });

      while (DateTime.now().isBefore(searchDeadline)) {
        final gigSnap = await gigRef.get();
        if (!gigSnap.exists) return;
        final gigData = gigSnap.data()!;
        final status = gigData['status'] as String? ?? '';
        final workerSlots = (gigData['workerSlots'] as num?)?.toInt() ?? 1;
        final filledSlotCount = (gigData['filledSlotCount'] as num?)?.toInt() ?? 0;

        // Gig closed out from under us (cancelled/completed) or the freed
        // slot is no longer there to fill (another dispatch beat us to it).
        if (['cancelled', 'completed'].contains(status)) return;
        if (filledSlotCount >= workerSlots) return;
        if (dispatchAttempts >= config.maxAttempts) return;

        final excluded = [
          ...List<String>.from(gigData['exclusionList'] ?? []),
          if ((gigData['hostId'] as String?)?.isNotEmpty ?? false) gigData['hostId'] as String,
        ];

        final worker = await _findBestWorker(
          gigLocation: gigLocation,
          exclude: excluded,
          maxSearchRadiusKm: config.maxSearchRadiusKm,
        );

        if (worker == null) {
          await Future.delayed(_retryInterval);
          continue;
        }

        final candidateId = worker['id'] as String;
        final candidateName = worker['name'] as String;

        dispatchAttempts++;
        await _dispatchToWorkerSlot(
          gigId: gigId,
          workerId: candidateId,
          workerName: candidateName,
          hostId: gigData['hostId'] as String? ?? '',
          hostName: gigData['hostName'] as String? ?? '',
          rate: (gigData['ratePerSlot'] as num?)?.toDouble() ??
              (gigData['budget'] as num?)?.toDouble() ??
              0,
          currencyCode: gigData['currencyCode'] as String? ?? 'PHP',
        );

        final slotRef = gigRef.collection('workers').doc(candidateId);
        final reviewDeadline = DateTime.now().add(config.reviewWindow);
        String finalStatus = 'in_progress';

        while (DateTime.now().isBefore(reviewDeadline) &&
            DateTime.now().isBefore(searchDeadline)) {
          await Future.delayed(_pollInterval);
          final check = await slotRef.get();
          if (!check.exists) {
            finalStatus = 'declined';
            break;
          }
          final cs = check.data()?['status'] as String? ?? '';
          if (cs != 'in_progress') {
            finalStatus = cs;
            break;
          }
        }

        if (finalStatus == 'navigating') {
          // Accepted — claim the slot and stop; the backfill only needed to
          // fill the one freed slot.
          await db.runTransaction((tx) async {
            final snap = await tx.get(gigRef);
            final data = snap.data() ?? {};
            final filled = (data['filledSlotCount'] as num?)?.toInt() ?? 0;
            final newFilled = filled + 1;
            tx.update(gigRef, {
              'filledSlotCount': newFilled,
              'status': newFilled >= workerSlots ? 'filled' : 'partially_filled',
            });
          });
          return;
        }

        if (finalStatus == 'cancelled') return;

        if (finalStatus == 'in_progress') {
          // Review window (or the whole backfill window) timed out with no
          // response — exclude and penalize same as the initial search loop.
          await Future.wait([
            gigRef.update({
              'exclusionList': FieldValue.arrayUnion([candidateId]),
            }),
            db.collection('users').doc(candidateId).update({
              'slot': 'AVAILABLE',
              'acceptanceRate': FieldValue.increment(-0.05),
            }),
            slotRef.update({'status': 'declined'}).catchError((_) {}),
          ]);
        }
        // Otherwise (declined) — loop again if time remains.
      }
    } catch (e) {
      debugPrint('[QuickGigMatching] backfill search error for $gigId: $e');
    }
  }
}
