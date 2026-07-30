import 'package:cloud_firestore/cloud_firestore.dart';

class OfferedGigModel {
  final String? id;
  final String hostId;
  final String hostName;
  // Null for a multi-worker offer (workerSlots > 1) — recipient identity
  // then lives entirely in the `workers` subcollection instead. Still
  // required-in-practice for a legacy/single-recipient offer (workerSlots
  // <= 1), same as before.
  final String? workerId;
  final String? workerName;
  final String title;
  final String description;
  final String skillRequired;
  final String experienceLevel; // 'entry' | 'intermediate' | 'expert'
  final double budget;
  final String currencyCode;
  final String status;
  final GeoPoint location;
  final String address;
  final DateTime createdAt;
  final DateTime? scheduledDate;

  // ── Multi-worker slots ────────────────────────────────────────────────────
  /// Number of worker slots offered. 1 == legacy single-recipient gig.
  final int workerSlots;

  /// Pay per worker slot. `budget` is kept in sync (== ratePerSlot) so
  /// existing single-worker readers keep working unmodified.
  final double ratePerSlot;

  /// Count of slots currently occupied by a non-terminal worker doc.
  final int filledSlotCount;

  /// Count of worker docs that have reached `completed`.
  final int slotsCompleted;

  OfferedGigModel({
    this.id,
    required this.hostId,
    required this.hostName,
    this.workerId,
    this.workerName,
    required this.title,
    required this.description,
    required this.skillRequired,
    required this.experienceLevel,
    required this.budget,
    this.currencyCode = 'PHP',
    required this.location,
    required this.address,
    this.status = 'offered',
    DateTime? createdAt,
    this.scheduledDate,
    int? workerSlots,
    double? ratePerSlot,
    this.filledSlotCount = 0,
    this.slotsCompleted = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        workerSlots = workerSlots ?? 1,
        ratePerSlot = ratePerSlot ?? budget;

  Map<String, dynamic> toMap() => {
        'hostId': hostId,
        'hostName': hostName,
        if (workerId != null) 'workerId': workerId,
        if (workerName != null) 'workerName': workerName,
        'title': title,
        'description': description,
        'skillRequired': skillRequired,
        'experienceLevel': experienceLevel,
        'budget': budget,
        'currencyCode': currencyCode,
        'location': location,
        'address': address,
        'status': status,
        'gigType': 'offered',
        'createdAt': Timestamp.fromDate(createdAt),
        if (scheduledDate != null)
          'scheduledDate': Timestamp.fromDate(scheduledDate!),
        'workerSlots': workerSlots,
        'ratePerSlot': ratePerSlot,
        'filledSlotCount': filledSlotCount,
        'slotsCompleted': slotsCompleted,
      };

  factory OfferedGigModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final budget = (d['budget'] ?? 0).toDouble();
    return OfferedGigModel(
      id: doc.id,
      hostId: d['hostId'] ?? '',
      hostName: d['hostName'] ?? '',
      workerId: d['workerId'] as String?,
      workerName: d['workerName'] as String?,
      title: d['title'] ?? '',
      description: d['description'] ?? '',
      skillRequired: d['skillRequired'] ?? '',
      experienceLevel: d['experienceLevel'] ?? 'entry',
      budget: budget,
      currencyCode: (d['currencyCode'] as String?) ?? 'PHP',
      location: d['location'] as GeoPoint,
      address: d['address'] ?? '',
      status: d['status'] ?? 'offered',
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
