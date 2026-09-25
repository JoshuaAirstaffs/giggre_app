import 'package:cloud_firestore/cloud_firestore.dart';

class OpenGigModel {
  final String? id;
  final String hostId;
  final String hostName;
  final String title;
  final String description;
  final List<String> requiredSkills;
  final String experienceLevel; // 'entry' | 'intermediate' | 'expert'
  final double budget;
  final String currencyCode;
  // 'flat' (default) or 'hourly' — see quick_gig_model.dart for the
  // budget-stays-an-estimate rationale.
  final String payType;
  final double? hourlyRate;
  // Optional, host-entered approximate hours this gig will take. Purely
  // informational — never used in any pay calculation.
  final double? workDurationHours;
  final String status;
  final GeoPoint location;
  final String address;
  final DateTime createdAt;
  final DateTime? scheduledDate;

  // ── Multi-worker slots ────────────────────────────────────────────────────
  /// Number of worker slots requested. 1 == legacy single-worker gig.
  final int workerSlots;

  /// Pay per worker slot. `budget` is kept in sync (== ratePerSlot) so
  /// existing single-worker readers (EarningsService callers, etc.) keep
  /// working unmodified.
  final double ratePerSlot;

  /// Count of slots currently occupied by a non-terminal worker doc.
  final int filledSlotCount;

  /// Count of worker docs that have reached `completed`.
  final int slotsCompleted;

  OpenGigModel({
    this.id,
    required this.hostId,
    required this.hostName,
    required this.title,
    required this.description,
    required this.requiredSkills,
    required this.experienceLevel,
    required this.budget,
    this.currencyCode = 'USD',
    this.payType = 'flat',
    this.hourlyRate,
    this.workDurationHours,
    required this.location,
    required this.address,
    this.status = 'open',
    DateTime? createdAt,
    this.scheduledDate,
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
    'requiredSkills': requiredSkills,
    'experienceLevel': experienceLevel,
    'budget': budget,
    'currencyCode': currencyCode,
    'payType': payType,
    if (hourlyRate != null) 'hourlyRate': hourlyRate,
    if (workDurationHours != null) 'workDurationHours': workDurationHours,
    'location': location,
    'address': address,
    'status': status,
    'gigType': 'open',
    'createdAt': Timestamp.fromDate(createdAt),
    if (scheduledDate != null)
      'scheduledDate': Timestamp.fromDate(scheduledDate!),
    'workerSlots': workerSlots,
    'ratePerSlot': ratePerSlot,
    'filledSlotCount': filledSlotCount,
    'slotsCompleted': slotsCompleted,
  };

  factory OpenGigModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final budget = (d['budget'] ?? 0).toDouble();
    return OpenGigModel(
      id: doc.id,
      hostId: d['hostId'] ?? '',
      hostName: d['hostName'] ?? '',
      title: d['title'] ?? '',
      description: d['description'] ?? '',
      requiredSkills: List<String>.from(d['requiredSkills'] ?? []),
      experienceLevel: d['experienceLevel'] ?? 'entry',
      budget: budget,
      currencyCode: (d['currencyCode'] as String?) ?? 'USD',
      payType: (d['payType'] as String?) ?? 'flat',
      hourlyRate: (d['hourlyRate'] as num?)?.toDouble(),
      workDurationHours: (d['workDurationHours'] as num?)?.toDouble(),
      location: d['location'] as GeoPoint,
      address: d['address'] ?? '',
      status: d['status'] ?? 'open',
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      scheduledDate: d['scheduledDate'] != null
          ? (d['scheduledDate'] as Timestamp).toDate()
          : null,
      workerSlots: (d['workerSlots'] as num?)?.toInt() ?? 1,
      ratePerSlot: (d['ratePerSlot'] as num?)?.toDouble() ?? budget,
      filledSlotCount: (d['filledSlotCount'] as num?)?.toInt() ?? 0,
      slotsCompleted: (d['slotsCompleted'] as num?)?.toInt() ?? 0,
    );
  }
}
