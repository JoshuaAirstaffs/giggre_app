import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/cancellation_request.dart' as cancel_req;

/// One worker's independent slot on a multi-worker gig.
/// Lives at `{gigCollection}/{gigId}/workers/{workerId}` — doc id == workerId.
///
/// This is the single source of truth for that worker's tracking and payment
/// on this gig. Ratings are not stored here — they live in the top-level
/// `ratings` collection, keyed by gig and by both parties. The parent gig doc only holds the coarse
/// aggregate (workerSlots/ratePerSlot/filledSlotCount/slotsCompleted).
class WorkerSlotModel {
  final String workerId;
  final String workerName;
  final String? workerPhotoUrl;
  final String gigId;
  final String gigCollection;
  final String hostId;
  final String hostName;
  final double rate;
  final String currencyCode;
  // What was actually paid — written unconditionally by the host at
  // payment-confirmation time (see gig_detail_sheet.dart). Null until then.
  final double? finalAmount;
  final double? adjustedAmount;
  final String status;
  final GeoPoint? workerLocation;
  final DateTime? locationUpdatedAt;
  final DateTime? dispatchedAt;
  final DateTime? offeredAt;
  final DateTime? acceptedAt;
  final DateTime? arrivedAt;
  final DateTime? workStartedAt;
  final DateTime? workCompletedAt;
  final DateTime? completedAt;
  final int? durationSeconds;
  final String? paymentMethod;
  final String? paymentCode;
  final DateTime? paymentInitiatedAt;
  final DateTime? paymentConfirmedAt;
  final String? paymentConfirmedBy;
  final bool? paymentConfirmedManually;

  /// Who asked for this slot's latest cancellation — 'worker' | 'host' |
  /// 'system' (see cancellationRequestedBy), or null when there's none.
  final String? cancellationRequestedBy;

  const WorkerSlotModel({
    required this.workerId,
    required this.workerName,
    this.workerPhotoUrl,
    required this.gigId,
    required this.gigCollection,
    required this.hostId,
    this.hostName = '',
    required this.rate,
    this.currencyCode = 'USD',
    this.finalAmount,
    this.adjustedAmount,
    this.status = 'navigating',
    this.workerLocation,
    this.locationUpdatedAt,
    this.dispatchedAt,
    this.offeredAt,
    this.acceptedAt,
    this.arrivedAt,
    this.workStartedAt,
    this.workCompletedAt,
    this.completedAt,
    this.durationSeconds,
    this.paymentMethod,
    this.paymentCode,
    this.paymentInitiatedAt,
    this.paymentConfirmedAt,
    this.paymentConfirmedBy,
    this.paymentConfirmedManually,
    this.cancellationRequestedBy,
  });

  Map<String, dynamic> toMap() => {
    'workerId': workerId,
    'workerName': workerName,
    if (workerPhotoUrl != null) 'workerPhotoUrl': workerPhotoUrl,
    'gigId': gigId,
    'gigCollection': gigCollection,
    'hostId': hostId,
    'hostName': hostName,
    'rate': rate,
    'currencyCode': currencyCode,
    'status': status,
  };

  factory WorkerSlotModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    DateTime? ts(String key) => (d[key] as Timestamp?)?.toDate();
    return WorkerSlotModel(
      workerId: d['workerId'] as String? ?? doc.id,
      workerName: d['workerName'] as String? ?? '',
      workerPhotoUrl: d['workerPhotoUrl'] as String?,
      gigId: d['gigId'] as String? ?? '',
      gigCollection: d['gigCollection'] as String? ?? '',
      hostId: d['hostId'] as String? ?? '',
      hostName: d['hostName'] as String? ?? '',
      rate: (d['rate'] as num?)?.toDouble() ?? 0,
      currencyCode: d['currencyCode'] as String? ?? 'USD',
      finalAmount: (d['finalAmount'] as num?)?.toDouble(),
      adjustedAmount: (d['adjustedAmount'] as num?)?.toDouble(),
      status: d['status'] as String? ?? 'navigating',
      workerLocation: d['workerLocation'] as GeoPoint?,
      locationUpdatedAt: ts('locationUpdatedAt'),
      dispatchedAt: ts('dispatchedAt'),
      offeredAt: ts('offeredAt'),
      acceptedAt: ts('acceptedAt'),
      arrivedAt: ts('arrivedAt'),
      workStartedAt: ts('workStartedAt'),
      workCompletedAt: ts('workCompletedAt'),
      completedAt: ts('completedAt'),
      durationSeconds: (d['durationSeconds'] as num?)?.toInt(),
      paymentMethod: d['paymentMethod'] as String?,
      paymentCode: d['paymentCode'] as String?,
      paymentInitiatedAt: ts('paymentInitiatedAt'),
      paymentConfirmedAt: ts('paymentConfirmedAt'),
      paymentConfirmedBy: d['paymentConfirmedBy'] as String?,
      paymentConfirmedManually: d['paymentConfirmedManually'] as bool?,
      cancellationRequestedBy: cancel_req.cancellationRequestedBy(d),
    );
  }

  /// Statuses that count as "this worker is actively on this gig" —
  /// mirrors kWorkerActiveGigStatuses in core/utils/worker_active_gig.dart.
  /// Do not invent new status values here without updating that list too.
  static const activeStatuses = [
    'navigating',
    'arrived',
    'working',
    'task_complete',
    'payment',
    'cancellation_requested',
  ];

  static const terminalStatuses = [
    'completed',
    'declined',
    'cancelled',
    'no_worker',
  ];
}

/// Reference helper for the workers subcollection under a gig doc.
CollectionReference<Map<String, dynamic>> workersRef(
  String gigCollection,
  String gigId,
) {
  return FirebaseFirestore.instance
      .collection(gigCollection)
      .doc(gigId)
      .collection('workers');
}

/// Stable 1-based "Worker N" numbers for a gig's slots, keyed by workerId.
///
/// Numbered in the order workers were put on the gig — `selectedAt` (open),
/// `dispatchedAt` (quick) or `offeredAt` (offered), whichever the slot has —
/// across every slot including cancelled ones, so a worker keeps their number
/// when someone else leaves and a replacement takes the next one. Declined
/// candidates never joined and get no number. [slots] is each slot doc's
/// data with its doc id as `workerId`.
Map<String, int> workerSlotNumbers(Iterable<Map<String, dynamic>> slots) {
  DateTime? joinedAt(Map<String, dynamic> d) {
    for (final key in const [
      'selectedAt',
      'dispatchedAt',
      'offeredAt',
      'acceptedAt',
    ]) {
      final ts = d[key];
      if (ts is Timestamp) return ts.toDate();
    }
    return null;
  }

  final entries = [
    for (final d in slots)
      if (d['status'] != 'declined' &&
          (d['workerId'] as String? ?? '').isNotEmpty)
        (id: d['workerId'] as String, at: joinedAt(d)),
  ];
  // A just-written slot's server timestamp is still null locally — it's the
  // newest, so it sorts last. workerId breaks ties so the order never flips.
  entries.sort((a, b) {
    final at = a.at, bt = b.at;
    if (at == null && bt != null) return 1;
    if (at != null && bt == null) return -1;
    final byTime = (at == null || bt == null) ? 0 : at.compareTo(bt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return {for (var i = 0; i < entries.length; i++) entries[i].id: i + 1};
}
