import 'package:cloud_firestore/cloud_firestore.dart';

class OfferedGigModel {
  final String? id;
  final String hostId;
  final String hostName;
  final String workerId;
  final String workerName;
  final String title;
  final String description;
  final String skillRequired;
  final String experienceLevel; // 'entry' | 'intermediate' | 'expert'
  final double budget;
  final String status;
  final GeoPoint location;
  final String address;
  final DateTime createdAt;
  final DateTime? scheduledDate;

  OfferedGigModel({
    this.id,
    required this.hostId,
    required this.hostName,
    required this.workerId,
    required this.workerName,
    required this.title,
    required this.description,
    required this.skillRequired,
    required this.experienceLevel,
    required this.budget,
    required this.location,
    required this.address,
    this.status = 'offered',
    DateTime? createdAt,
    this.scheduledDate,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'hostId': hostId,
        'hostName': hostName,
        'workerId': workerId,
        'workerName': workerName,
        'title': title,
        'description': description,
        'skillRequired': skillRequired,
        'experienceLevel': experienceLevel,
        'budget': budget,
        'location': location,
        'address': address,
        'status': status,
        'gigType': 'offered',
        'createdAt': Timestamp.fromDate(createdAt),
        if (scheduledDate != null)
          'scheduledDate': Timestamp.fromDate(scheduledDate!),
      };

  factory OfferedGigModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return OfferedGigModel(
      id: doc.id,
      hostId: d['hostId'] ?? '',
      hostName: d['hostName'] ?? '',
      workerId: d['workerId'] ?? '',
      workerName: d['workerName'] ?? '',
      title: d['title'] ?? '',
      description: d['description'] ?? '',
      skillRequired: d['skillRequired'] ?? '',
      experienceLevel: d['experienceLevel'] ?? 'entry',
      budget: (d['budget'] ?? 0).toDouble(),
      location: d['location'] as GeoPoint,
      address: d['address'] ?? '',
      status: d['status'] ?? 'offered',
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      scheduledDate: d['scheduledDate'] != null
          ? (d['scheduledDate'] as Timestamp).toDate()
          : null,
    );
  }
}
