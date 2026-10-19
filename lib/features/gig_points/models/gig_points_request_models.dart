import 'package:cloud_firestore/cloud_firestore.dart';

// Read-only views of the request data written by
// functions/src/gigPointsRequests.ts. Requests are created, cancelled and
// decided only through callables (see GigPointsService) — never written here.

int? _posInt(Object? v) {
  if (v is int) return v > 0 ? v : null;
  if (v is double && v.isFinite && v > 0 && v == v.truncateToDouble()) {
    return v.toInt();
  }
  return null;
}

enum PointsRequestType {
  deposit,
  withdraw,
  transfer;

  static PointsRequestType? parse(Object? v) => switch (v) {
    'deposit' => PointsRequestType.deposit,
    'withdraw' => PointsRequestType.withdraw,
    'transfer' => PointsRequestType.transfer,
    _ => null,
  };

  String get label => switch (this) {
    PointsRequestType.deposit => 'Deposit',
    PointsRequestType.withdraw => 'Withdraw',
    PointsRequestType.transfer => 'Transfer',
  };

  /// "a deposit", for sentences.
  String get noun => switch (this) {
    PointsRequestType.deposit => 'deposit',
    PointsRequestType.withdraw => 'withdrawal',
    PointsRequestType.transfer => 'transfer',
  };

  /// Withdrawals and transfers reserve the points while they're reviewed.
  bool get holdsPoints => this != PointsRequestType.deposit;
}

enum PointsRequestStatus {
  pending,
  approved,
  rejected,
  cancelled;

  static PointsRequestStatus parse(Object? v) => switch (v) {
    'approved' => PointsRequestStatus.approved,
    'rejected' => PointsRequestStatus.rejected,
    'cancelled' => PointsRequestStatus.cancelled,
    _ => PointsRequestStatus.pending,
  };

  String get label => switch (this) {
    PointsRequestStatus.pending => 'Pending review',
    PointsRequestStatus.approved => 'Approved',
    PointsRequestStatus.rejected => 'Rejected',
    PointsRequestStatus.cancelled => 'Cancelled',
  };
}

/// gig_points_requests/{id}
class GigPointsRequest {
  final String id;
  final PointsRequestType type;
  final PointsRequestStatus status;
  final int points;
  final String? note;
  final String? recipientName;
  final String? recipientCode;
  final String? decisionNote;
  final String? reference;
  final bool byAdmin;
  final DateTime? createdAt;
  final DateTime? decidedAt;

  const GigPointsRequest({
    required this.id,
    required this.type,
    required this.status,
    required this.points,
    this.note,
    this.recipientName,
    this.recipientCode,
    this.decisionNote,
    this.reference,
    this.byAdmin = false,
    this.createdAt,
    this.decidedAt,
  });

  bool get isPending => status == PointsRequestStatus.pending;

  /// Null for a doc with an unknown type (skipped by callers).
  static GigPointsRequest? fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final d = snap.data() ?? const <String, dynamic>{};
    final type = PointsRequestType.parse(d['type']);
    if (type == null) return null;
    DateTime? date(Object? v) => v is Timestamp ? v.toDate() : null;
    return GigPointsRequest(
      id: snap.id,
      type: type,
      status: PointsRequestStatus.parse(d['status']),
      points: _posInt(d['points']) ?? 0,
      note: d['note'] as String?,
      recipientName: d['recipientName'] as String?,
      recipientCode: d['recipientCode'] as String?,
      // Only rejection reasons are meant for the user.
      decisionNote: d['status'] == 'rejected'
          ? d['decisionNote'] as String?
          : null,
      reference: d['reference'] as String?,
      byAdmin: d['source'] == 'admin',
      createdAt: date(d['createdAt']),
      decidedAt: date(d['decidedAt']),
    );
  }
}

/// One request type's limits. Null = no limit.
class PointsTypeLimits {
  final bool enabled;
  final int? min;
  final int? max;
  final int? dailyMax;

  const PointsTypeLimits({
    required this.enabled,
    this.min,
    this.max,
    this.dailyMax,
  });

  static const closed = PointsTypeLimits(enabled: false);
}

/// general_config/gig_points_requests — mirrors parseLimits() in
/// gigPointsRequests.ts. A missing doc means requests are closed.
class PointsRequestLimits {
  final bool enabled;
  final Map<PointsRequestType, PointsTypeLimits> byType;

  const PointsRequestLimits({required this.enabled, required this.byType});

  static const closed = PointsRequestLimits(enabled: false, byType: {});

  PointsTypeLimits of(PointsRequestType t) =>
      enabled ? (byType[t] ?? PointsTypeLimits.closed) : PointsTypeLimits.closed;

  bool isOpen(PointsRequestType t) => of(t).enabled;

  factory PointsRequestLimits.fromMap(Map<String, dynamic>? d) {
    if (d == null) return closed;
    final byType = <PointsRequestType, PointsTypeLimits>{};
    for (final t in PointsRequestType.values) {
      final raw = d[t.name];
      final m = raw is Map ? raw : const {};
      byType[t] = PointsTypeLimits(
        enabled: m['enabled'] == true,
        min: _posInt(m['min']),
        max: _posInt(m['max']),
        dailyMax: _posInt(m['dailyMax']),
      );
    }
    return PointsRequestLimits(enabled: d['enabled'] != false, byType: byType);
  }
}

/// A transfer recipient resolved by lookupGigPointsRecipient.
class PointsRecipient {
  final String id;

  /// Masked by the server ("Juan D.").
  final String name;
  final String? code;
  final String? photoUrl;

  const PointsRecipient({
    required this.id,
    required this.name,
    this.code,
    this.photoUrl,
  });
}
