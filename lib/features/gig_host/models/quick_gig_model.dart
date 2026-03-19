import 'package:cloud_firestore/cloud_firestore.dart';

class QuickGigModel {
  final String? id;
  final String hostId;
  final String hostName;
  final String title;
  final String description;
  final String category;
  final double budget;
  final String duration;
  final GeoPoint location;
  final String address;
  final String status;
  final DateTime createdAt;

  QuickGigModel({
    this.id,
    required this.hostId,
    required this.hostName,
    required this.title,
    required this.description,
    required this.category,
    required this.budget,
    required this.duration,
    required this.location,
    required this.address,
    this.status = 'scanning',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'hostId': hostId,
        'hostName': hostName,
        'title': title,
        'description': description,
        'category': category,
        'budget': budget,
        'duration': duration,
        'location': location,
        'address': address,
        'status': status,
        'gigType': 'quick',
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory QuickGigModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return QuickGigModel(
      id: doc.id,
      hostId: d['hostId'] ?? '',
      hostName: d['hostName'] ?? '',
      title: d['title'] ?? '',
      description: d['description'] ?? '',
      category: d['category'] ?? '',
      budget: (d['budget'] ?? 0).toDouble(),
      duration: d['duration'] ?? '',
      location: d['location'] as GeoPoint,
      address: d['address'] ?? '',
      status: d['status'] ?? 'scanning',
      createdAt: (d['createdAt'] as Timestamp).toDate(),
    );
  }
}
