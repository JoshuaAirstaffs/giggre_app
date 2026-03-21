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
  final String status;
  final GeoPoint location;
  final String address;
  final DateTime createdAt;
  final DateTime? scheduledDate;

  OpenGigModel({
    this.id,
    required this.hostId,
    required this.hostName,
    required this.title,
    required this.description,
    required this.requiredSkills,
    required this.experienceLevel,
    required this.budget,
    required this.location,
    required this.address,
    this.status = 'open',
    DateTime? createdAt,
    this.scheduledDate,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'hostId': hostId,
        'hostName': hostName,
        'title': title,
        'description': description,
        'requiredSkills': requiredSkills,
        'experienceLevel': experienceLevel,
        'budget': budget,
        'location': location,
        'address': address,
        'status': status,
        'gigType': 'open',
        'createdAt': Timestamp.fromDate(createdAt),
        if (scheduledDate != null)
          'scheduledDate': Timestamp.fromDate(scheduledDate!),
      };

  factory OpenGigModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return OpenGigModel(
      id: doc.id,
      hostId: d['hostId'] ?? '',
      hostName: d['hostName'] ?? '',
      title: d['title'] ?? '',
      description: d['description'] ?? '',
      requiredSkills: List<String>.from(d['requiredSkills'] ?? []),
      experienceLevel: d['experienceLevel'] ?? 'entry',
      budget: (d['budget'] ?? 0).toDouble(),
      location: d['location'] as GeoPoint,
      address: d['address'] ?? '',
      status: d['status'] ?? 'open',
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      scheduledDate: d['scheduledDate'] != null
          ? (d['scheduledDate'] as Timestamp).toDate()
          : null,
    );
  }
}
