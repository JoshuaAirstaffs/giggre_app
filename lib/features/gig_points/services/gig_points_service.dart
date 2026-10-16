import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/gig_points_models.dart';

/// Read-only access to a user's Gig Points.
///
/// Points are recorded exclusively by Cloud Functions
/// (functions/src/gigPoints.ts) — this service intentionally has no way to
/// change a balance or a ledger entry.
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
  static Query<Map<String, dynamic>> transactionsQuery(
    String uid, {
    required int limit,
  }) => _balanceRef(uid)
      .collection('transactions')
      .orderBy('createdAt', descending: true)
      .limit(limit);

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
}
