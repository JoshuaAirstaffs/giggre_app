import 'package:cloud_firestore/cloud_firestore.dart';

/// One worker's independent slot on a multi-worker gig.
/// Lives at `{gigCollection}/{gigId}/workers/{workerId}` — doc id == workerId.
///
/// This is the single source of truth for that worker's tracking, payment,
/// and rating on this gig. The parent gig doc only holds the coarse
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
  final int? hostRating;
  final DateTime? hostRatedAt;

  const WorkerSlotModel({
    required this.workerId,
    required this.workerName,
    this.workerPhotoUrl,
    required this.gigId,
    required this.gigCollection,
    required this.hostId,
    this.hostName = '',
    required this.rate,
    this.currencyCode = 'PHP',
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
    this.hostRating,
    this.hostRatedAt,
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
      currencyCode: d['currencyCode'] as String? ?? 'PHP',
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
      hostRating: (d['hostRating'] as num?)?.toInt(),
      hostRatedAt: ts('hostRatedAt'),
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
