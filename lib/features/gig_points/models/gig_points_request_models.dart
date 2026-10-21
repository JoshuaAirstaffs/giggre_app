import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// Read-only views of the conversion data written by
// functions/src/gigPointsRequests.ts. Requests are created, cancelled and
// decided only through callables (see GigPointsService) — never written here.

int? _posInt(Object? v) {
  if (v is int) return v > 0 ? v : null;
  if (v is double && v.isFinite && v > 0 && v == v.truncateToDouble()) {
    return v.toInt();
  }
  return null;
}

double _money(Object? v) => v is num ? (v * 100).round() / 100 : 0;

/// "₱12.50"
String formatCash(double v, [String currencyCode = 'PHP']) {
  final f = NumberFormat.currency(
    symbol: currencyCode == 'PHP' ? '₱' : '$currencyCode ',
    decimalDigits: 2,
  );
  return f.format(v);
}

/// The two conversion directions. Matches REQUEST_TYPES on the server.
enum PointsRequestType {
  /// Gig Points → GigCash (Gig Wallet). Points are held while pending.
  toCash('to_cash', 'toCash'),

  /// GigCash → Gig Points. The GigCash is taken from the wallet when
  /// requested and refunded if rejected or cancelled.
  toPoints('to_points', 'toPoints');

  final String wire;
  final String configKey;
  const PointsRequestType(this.wire, this.configKey);

  static PointsRequestType? parse(Object? v) => switch (v) {
    'to_cash' => PointsRequestType.toCash,
    'to_points' => PointsRequestType.toPoints,
    _ => null,
  };

  /// Button / tab label.
  String get label => switch (this) {
    PointsRequestType.toCash => 'To GigCash',
    PointsRequestType.toPoints => 'To Points',
  };

  String get title => switch (this) {
    PointsRequestType.toCash => 'Points → GigCash',
    PointsRequestType.toPoints => 'GigCash → Points',
  };

  /// For sentences: "your conversion to GigCash".
  String get noun => switch (this) {
    PointsRequestType.toCash => 'conversion to GigCash',
    PointsRequestType.toPoints => 'conversion to Gig Points',
  };

  /// Peso value of [points] at [rate] points per ₱1. Cashing out rounds
  /// down, buying rounds up (both to the centavo) — same as cashFor() on
  /// the server, which decides the real amount.
  double cashFor(int points, int rate) {
    final exact = points / rate;
    return this == PointsRequestType.toCash
        ? (exact * 100 + 1e-9).floorToDouble() / 100
        : (exact * 100 - 1e-9).ceilToDouble() / 100;
  }
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

  /// Null for an old deposit / withdraw / transfer request from before
  /// conversion replaced them (shown, but only an admin can close it).
  final PointsRequestType? type;
  final PointsRequestStatus status;
  final int points;
  final double cash;
  final String currencyCode;
  final int? rate;
  final String? note;
  final String? decisionNote;
  final bool byAdmin;
  final DateTime? createdAt;
  final DateTime? decidedAt;

  const GigPointsRequest({
    required this.id,
    required this.type,
    required this.status,
    required this.points,
    required this.cash,
    this.currencyCode = 'PHP',
    this.rate,
    this.note,
    this.decisionNote,
    this.byAdmin = false,
    this.createdAt,
    this.decidedAt,
  });

  bool get isPending => status == PointsRequestStatus.pending;
  String get title => type?.title ?? 'Points request';
  String get noun => type?.noun ?? 'request';

  static GigPointsRequest fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final d = snap.data() ?? const <String, dynamic>{};
    DateTime? date(Object? v) => v is Timestamp ? v.toDate() : null;
    return GigPointsRequest(
      id: snap.id,
      type: PointsRequestType.parse(d['type']),
      status: PointsRequestStatus.parse(d['status']),
      points: _posInt(d['points']) ?? 0,
      cash: _money(d['cash']),
      currencyCode: d['currencyCode'] as String? ?? 'PHP',
      rate: _posInt(d['rate']),
      note: d['note'] as String?,
      // Only rejection reasons are meant for the user.
      decisionNote: d['status'] == 'rejected'
          ? d['decisionNote'] as String?
          : null,
      byAdmin: d['source'] == 'admin',
      createdAt: date(d['createdAt']),
      decidedAt: date(d['decidedAt']),
    );
  }
}

/// One direction's rate and limits (limits in points; null = no limit).
class PointsTypeLimits {
  final bool enabled;

  /// Points per ₱1. A direction with no rate is closed.
  final int? rate;
  final int? min;
  final int? max;
  final int? dailyMax;

  const PointsTypeLimits({
    required this.enabled,
    this.rate,
    this.min,
    this.max,
    this.dailyMax,
  });

  static const closed = PointsTypeLimits(enabled: false);
}

/// general_config/gig_points_requests — mirrors parseConversionConfig() in
/// gigPointsRequests.ts. A missing doc means conversion is closed.
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
    final rates = d['rates'] is Map ? d['rates'] as Map : const {};
    final byType = <PointsRequestType, PointsTypeLimits>{};
    for (final t in PointsRequestType.values) {
      final raw = d[t.configKey];
      final m = raw is Map ? raw : const {};
      final rate = _posInt(rates[t.configKey]);
      byType[t] = PointsTypeLimits(
        enabled: m['enabled'] == true && rate != null,
        rate: rate,
        min: _posInt(m['min']),
        max: _posInt(m['max']),
        dailyMax: _posInt(m['dailyMax']),
      );
    }
    return PointsRequestLimits(enabled: d['enabled'] != false, byType: byType);
  }
}

/// wallets/{uid} — the Gig Wallet (GigCash) balance, read-only here.
class WalletBalance {
  final double balance;
  final String currencyCode;

  const WalletBalance({required this.balance, this.currencyCode = 'PHP'});

  factory WalletBalance.fromMap(Map<String, dynamic>? d) => WalletBalance(
    balance: _money(d?['balance']),
    currencyCode: d?['currencyCode'] as String? ?? 'PHP',
  );
}
