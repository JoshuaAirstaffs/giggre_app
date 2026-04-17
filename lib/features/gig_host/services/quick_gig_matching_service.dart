import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  // alwaysExclude: host + workers who declined even as fallback (never dispatched)
  // softExclude:   workers who declined in first pass (skipped normally, eligible as fallback)
  // fallback:      when true, ONLY considers softExclude workers as last resort
  static Future<Map<String, dynamic>?> _findBestWorker({
    required GeoPoint gigLocation,
    required List<String> alwaysExclude,
    required double maxSearchRadiusKm,
    List<String> softExclude = const [],
    bool fallback = false,
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
      if (alwaysExclude.contains(doc.id)) continue;
      // Normal pass: skip declined workers
      // Fallback pass: ONLY consider declined workers
      if (!fallback && softExclude.contains(doc.id)) continue;
      if (fallback && !softExclude.contains(doc.id)) continue;

      final data = doc.data();
      final geo = data['location'] as GeoPoint?;
      if (geo == null) continue;

      final dist = _distanceKm(gigLocation, geo);

      // Skip workers outside the configured radius
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

  // ── Dispatch gig to a worker ────────────────────────────────────────────────
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
    final searchStart = DateTime.now();

    final config = await _fetchConfig();

    // Initialise search metadata on the gig doc
    await gigRef.update({
      'searchStartedAt': FieldValue.serverTimestamp(),
      'exclusionList': FieldValue.arrayUnion([]),
      'hardExcludeList': FieldValue.arrayUnion([]),
    });

    int dispatchAttempts = 0;

    try {
      while (true) {
        // ── Global timeout ─────────────────────────────────
        if (DateTime.now().difference(searchStart) >= config.searchTimeout) {
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
        // hardExclude: host + workers who already declined a fallback dispatch
        final hardExclude = [
          ...List<String>.from(gigData['hardExcludeList'] ?? []),
          if (hostId.isNotEmpty) hostId,
        ];
        // softExclude: workers who declined once — skipped on first pass,
        // eligible as last-resort fallback
        final softExclude =
            List<String>.from(gigData['exclusionList'] ?? []);

        // ── Find best worker (first pass: skip declined workers) ──
        var worker = await _findBestWorker(
          gigLocation: gigLocation,
          alwaysExclude: hardExclude,
          softExclude: softExclude,
          maxSearchRadiusKm: config.maxSearchRadiusKm,
        );

        // ── Fallback pass: no fresh workers — try declined ones ───
        bool isFallbackDispatch = false;
        if (worker == null && softExclude.isNotEmpty) {
          worker = await _findBestWorker(
            gigLocation: gigLocation,
            alwaysExclude: hardExclude,
            softExclude: softExclude,
            maxSearchRadiusKm: config.maxSearchRadiusKm,
            fallback: true,
          );
          if (worker != null) isFallbackDispatch = true;
        }

        if (worker == null) {
          // Truly no available workers right now — wait and retry
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
        final deadline = DateTime.now().add(config.reviewWindow);
        String finalStatus = 'in_progress';

        while (DateTime.now().isBefore(deadline)) {
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

        // Worker declined
        if (finalStatus == 'scanning') {
          final declinedWorkerId = worker['id'] as String;
          if (isFallbackDispatch) {
            // Declined even as last resort — hard exclude permanently
            await gigRef.update({
              'hardExcludeList': FieldValue.arrayUnion([declinedWorkerId]),
              'exclusionList': FieldValue.arrayRemove([declinedWorkerId]),
            });
          } else {
            // First decline — soft exclude, still eligible as fallback later
            await gigRef.update({
              'exclusionList': FieldValue.arrayUnion([declinedWorkerId]),
            });
          }
          continue;
        }

        // Timed out — soft exclude worker and try next
        final timedOutWorkerId = worker['id'] as String;
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
    } finally {
      _activeSearches.remove(gigId);
    }
  }
}
