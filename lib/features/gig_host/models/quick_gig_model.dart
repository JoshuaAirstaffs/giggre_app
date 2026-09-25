import 'package:cloud_firestore/cloud_firestore.dart';

class QuickGigModel {
  final String? id;
  final String hostId;
  final String hostName;
  final String title;
  final String description;
  final String category;
  final double budget;
  final String currencyCode;
  final String duration;
  // 'flat' (default) or 'hourly'. For 'hourly' gigs, `budget`/`ratePerSlot`
  // stay an ESTIMATE (hourlyRate * estimatedHours) so every existing
  // display site that reads budget keeps working unmodified — the actual
  // amount paid is computed from hourlyRate * real tracked work duration
  // at payment-confirmation time instead of trusting this estimate.
  final String payType;
  final double? hourlyRate;
  // Optional, host-entered approximate hours this gig will take. Purely
  // informational (shown to workers so they can gauge time commitment) —
  // it's never used in any pay calculation and isn't a minimum/commitment.
  final double? workDurationHours;
  final GeoPoint location;
  final String address;
  final String status;
  final DateTime createdAt;
  final DateTime? scheduledDate;
  final String? assignedWorkerId;
  final String? assignedWorkerName;
  final List<String> exclusionList;

  // ── Multi-worker slots ────────────────────────────────────────────────────
  /// Number of worker slots requested. 1 == legacy single-worker gig.
  final int workerSlots;

  /// Pay per worker slot. `budget` is kept in sync (== ratePerSlot) so
  /// existing single-worker readers keep working unmodified.
  final double ratePerSlot;

  /// Count of slots currently occupied by a non-terminal worker doc.
  final int filledSlotCount;

  /// Count of worker docs that have reached `completed`.
  final int slotsCompleted;

  QuickGigModel({
    this.id,
    required this.hostId,
    required this.hostName,
    required this.title,
    required this.description,
    required this.category,
    required this.budget,
    this.currencyCode = 'USD',
    this.payType = 'flat',
    this.hourlyRate,
    this.workDurationHours,
    required this.duration,
    required this.location,
    required this.address,
    this.status = 'scanning',
    DateTime? createdAt,
    this.scheduledDate,
    this.assignedWorkerId,
    this.assignedWorkerName,
    this.exclusionList = const [],
    int? workerSlots,
    double? ratePerSlot,
    this.filledSlotCount = 0,
    this.slotsCompleted = 0,
  }) : createdAt = createdAt ?? DateTime.now(),
       workerSlots = workerSlots ?? 1,
       ratePerSlot = ratePerSlot ?? budget;

  Map<String, dynamic> toMap() => {
    'hostId': hostId,
    'hostName': hostName,
    'title': title,
    'description': description,
    'category': category,
    'budget': budget,
    'currencyCode': currencyCode,
    'payType': payType,
    if (hourlyRate != null) 'hourlyRate': hourlyRate,
    if (workDurationHours != null) 'workDurationHours': workDurationHours,
    'duration': duration,
    'location': location,
    'address': address,
    'status': status,
    'gigType': 'quick',
    'createdAt': Timestamp.fromDate(createdAt),
    if (scheduledDate != null)
      'scheduledDate': Timestamp.fromDate(scheduledDate!),
    'workerSlots': workerSlots,
    'ratePerSlot': ratePerSlot,
    'filledSlotCount': filledSlotCount,
    'slotsCompleted': slotsCompleted,
  };

  factory QuickGigModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final budget = (d['budget'] ?? 0).toDouble();
    return QuickGigModel(
      id: doc.id,
      hostId: d['hostId'] ?? '',
      hostName: d['hostName'] ?? '',
      title: d['title'] ?? '',
      description: d['description'] ?? '',
      category: d['category'] ?? '',
      budget: budget,
      currencyCode: (d['currencyCode'] as String?) ?? 'USD',
      payType: (d['payType'] as String?) ?? 'flat',
      hourlyRate: (d['hourlyRate'] as num?)?.toDouble(),
      workDurationHours: (d['workDurationHours'] as num?)?.toDouble(),
      duration: d['duration'] ?? '',
      location: d['location'] as GeoPoint,
      address: d['address'] ?? '',
      status: d['status'] ?? 'scanning',
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      scheduledDate: d['scheduledDate'] != null
          ? (d['scheduledDate'] as Timestamp).toDate()
          : null,
      assignedWorkerId: d['assignedWorkerId'] as String?,
      assignedWorkerName: d['assignedWorkerName'] as String?,
      exclusionList: List<String>.from(d['exclusionList'] ?? []),
      workerSlots: (d['workerSlots'] as num?)?.toInt() ?? 1,
      ratePerSlot: (d['ratePerSlot'] as num?)?.toDouble() ?? budget,
      filledSlotCount: (d['filledSlotCount'] as num?)?.toInt() ?? 0,
      slotsCompleted: (d['slotsCompleted'] as num?)?.toInt() ?? 0,
    );
  }
}
