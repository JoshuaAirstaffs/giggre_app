import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:giggre_app/main.dart' show flavor;

import '../models/gig_points_models.dart';
import '../models/gig_points_request_models.dart';

// Callables live in the same region as the project's Firestore triggers
// (see functions/src/region.ts).
final _functionsRegion = flavor == 'prod' ? 'us-central1' : 'asia-east2';

/// A request the server refused, with a message fit to show the user.
class GigPointsRequestException implements Exception {
  final String message;
  const GigPointsRequestException(this.message);
  @override
  String toString() => message;
}

/// Access to a user's Gig Points.
///
/// Points are recorded exclusively by Cloud Functions
/// (functions/src/gigPoints.ts, gigPointsRequests.ts). Nothing here writes a
/// balance or a ledger entry: converting points to/from GigCash is a REQUEST
/// sent through a callable, which an admin then approves or rejects.
class GigPointsService {
  GigPointsService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _balanceRef(String uid) =>
      _db.collection('gig_points').doc(uid);

  /// Live balance summary. A user with no awards yet reads as all zeros.
  /// Metadata changes are included so a cached (offline) value is flagged
  /// and the flag clears once the server confirms it.
  static Stream<GigPointsBalance> balanceStream(String uid) => _balanceRef(uid)
      .snapshots(includeMetadataChanges: true)
      .map(GigPointsBalance.fromSnapshot);

  /// The ledger entry for one task, if the backend has created it yet.
  /// Same id scheme as ledgerId() in functions/src/gigPoints.ts.
  static Stream<GigPointsTransaction?> taskEntryStream(
    String uid, {
    required String gigCollection,
    required String gigId,
  }) => _balanceRef(uid)
      .collection('transactions')
      .doc('${gigCollection}__${gigId}__$uid')
      .snapshots()
      .map((s) => s.exists ? GigPointsTransaction.fromSnapshot(s) : null);

  /// A gig doc, for its type and any per-gig reward override.
  static Stream<Map<String, dynamic>?> gigStream(
    String gigCollection,
    String gigId,
  ) => _db
      .collection(gigCollection)
      .doc(gigId)
      .snapshots()
      .map((s) => s.data());

  /// Newest-first ledger query, used by GigPointsHistoryController.
  /// [types] narrows it to those ledger types (needs the type+createdAt
  /// index in firestore.indexes.json).
  static Query<Map<String, dynamic>> transactionsQuery(
    String uid, {
    required int limit,
    List<String>? types,
  }) {
    Query<Map<String, dynamic>> q = _balanceRef(uid).collection('transactions');
    if (types != null && types.isNotEmpty) {
      q = q.where('type', whereIn: types);
    }
    return q.orderBy('createdAt', descending: true).limit(limit);
  }

  /// The centrally configured reward values, for display. A missing doc
  /// reads as [GigPointsConfig.notConfigured]; a failed read returns null
  /// (unknown) rather than inventing values.
  static Future<GigPointsConfig?> fetchConfig() async {
    try {
      final snap = await _db
          .collection('general_config')
          .doc('gig_points')
          .get();
      return GigPointsConfig.fromMap(snap.data());
    } catch (e) {
      debugPrint('[GigPointsService] config read failed: $e');
      return null;
    }
  }

  // ── Requests ─────────────────────────────────────────────────────────────

  /// The user's newest requests (owner-readable; see firestore.rules).
  static Stream<List<GigPointsRequest>> requestsStream(
    String uid, {
    int limit = 20,
  }) => _db
      .collection('gig_points_requests')
      .where('userId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (s) => s.docs
            .map(GigPointsRequest.fromSnapshot)
            .toList(),
      );

  /// Live request limits. A missing doc (or a failed read) = closed.
  static Stream<PointsRequestLimits> limitsStream() => _db
      .collection('general_config')
      .doc('gig_points_requests')
      .snapshots()
      .map((s) => PointsRequestLimits.fromMap(s.data()))
      .handleError((Object e) {
        debugPrint('[GigPointsService] limits read failed: $e');
      });

  static HttpsCallable _fn(String name) =>
      FirebaseFunctions.instanceFor(region: _functionsRegion)
          .httpsCallable(name);

  static Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[GigPointsService] ${e.code}: ${e.message}');
      final msg = switch (e.code) {
        'unavailable' || 'deadline-exceeded' =>
          "Couldn't reach Giggre. Check your connection and try again.",
        'internal' || 'unknown' => 'Something went wrong. Please try again.',
        _ => e.message ?? 'Something went wrong. Please try again.',
      };
      throw GigPointsRequestException(msg);
    }
  }

  /// Live Gig Wallet (GigCash) balance. Missing doc = 0.
  static Stream<WalletBalance> walletStream(String uid) => _db
      .collection('wallets')
      .doc(uid)
      .snapshots()
      .map((s) => WalletBalance.fromMap(s.data()));

  /// A fresh id per request attempt, so a retried call can't create two.
  static String newClientRequestId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(20, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// Sends a conversion request for admin review. Returns the request id.
  static Future<String> createRequest({
    required PointsRequestType type,
    required int points,
    required String clientRequestId,
    String? note,
  }) => _guard(() async {
    final res = await _fn('createGigPointsRequest').call({
      'type': type.wire,
      'points': points,
      'clientRequestId': clientRequestId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return (res.data as Map)['requestId'] as String;
  });

  /// Cancels the user's own pending request (held points are returned).
  static Future<void> cancelRequest(String requestId) => _guard(
    () => _fn('cancelGigPointsRequest').call({'requestId': requestId}),
  );
}
