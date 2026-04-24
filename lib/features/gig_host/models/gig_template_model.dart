import 'package:cloud_firestore/cloud_firestore.dart';

class GigTemplateModel {
  final String? id;
  final String hostId;
  final String gigType; // 'quick' | 'open' | 'offered'
  final String name;
  final String title;
  final String description;
  final double budget;
  final String skillRequired;   // open / offered only
  final String experienceLevel; // open / offered only
  final DateTime createdAt;

  const GigTemplateModel({
    this.id,
    required this.hostId,
    required this.gigType,
    required this.name,
    required this.title,
    required this.description,
    required this.budget,
    this.skillRequired = '',
    this.experienceLevel = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'hostId': hostId,
        'gigType': gigType,
        'name': name,
        'title': title,
        'description': description,
        'budget': budget,
        'skillRequired': skillRequired,
        'experienceLevel': experienceLevel,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory GigTemplateModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return GigTemplateModel(
      id: doc.id,
      hostId: d['hostId'] ?? '',
      gigType: d['gigType'] ?? 'quick',
      name: d['name'] ?? '',
      title: d['title'] ?? '',
      description: d['description'] ?? '',
      budget: (d['budget'] as num?)?.toDouble() ?? 0,
      skillRequired: d['skillRequired'] ?? '',
      experienceLevel: d['experienceLevel'] ?? '',
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}
