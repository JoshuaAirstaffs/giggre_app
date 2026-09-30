import 'package:cloud_firestore/cloud_firestore.dart';

class GigTemplateModel {
  final String? id;
  final String hostId;
  final String gigType; // 'quick' | 'open' | 'offered'
  final String name;
  final String title;
  final String description;
  final double budget;
  final String currencyCode;
  final String skillRequired; // open / offered only
  final String experienceLevel; // open / offered only
  // Carried over by "Post Again" (see HostGigCard/GigDetailSheet) so a
  // reposted gig keeps its pay/duration/slot setup — deliberately excludes
  // scheduledDate, since the whole point of reposting is picking a fresh one.
  final String payType;
  final double? hourlyRate;
  final double? workDurationHours;
  final int workerSlots;
  final DateTime createdAt;

  const GigTemplateModel({
    this.id,
    required this.hostId,
    required this.gigType,
    required this.name,
    required this.title,
    required this.description,
    required this.budget,
    this.currencyCode = 'USD',
    this.skillRequired = '',
    this.experienceLevel = '',
    this.payType = 'flat',
    this.hourlyRate,
    this.workDurationHours,
    this.workerSlots = 1,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'hostId': hostId,
    'gigType': gigType,
    'name': name,
    'title': title,
    'description': description,
    'budget': budget,
    'currencyCode': currencyCode,
    'skillRequired': skillRequired,
    'experienceLevel': experienceLevel,
    'payType': payType,
    'hourlyRate': hourlyRate,
    'workDurationHours': workDurationHours,
    'workerSlots': workerSlots,
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
      currencyCode: (d['currencyCode'] as String?) ?? 'USD',
      skillRequired: d['skillRequired'] ?? '',
      experienceLevel: d['experienceLevel'] ?? '',
      payType: (d['payType'] as String?) ?? 'flat',
      hourlyRate: (d['hourlyRate'] as num?)?.toDouble(),
      workDurationHours: (d['workDurationHours'] as num?)?.toDouble(),
      workerSlots: (d['workerSlots'] as num?)?.toInt() ?? 1,
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  // Builds a template in-memory straight from a live gig's own field map —
  // used by "Post Again" (HostGigCard/GigDetailSheet) to seed a fresh
  // PostXGigScreen from a completed/cancelled/no_worker gig, never persisted
  // itself. Differs from fromDoc/toMap (which round-trip a saved
  // /gig_templates doc): a live gig stores skills as a requiredSkills array
  // (open) rather than the single skillRequired string a saved template
  // uses, and has no `name` (a saved template's own display name) at all.
  factory GigTemplateModel.fromGigData(
    Map<String, dynamic> d, {
    required String hostId,
    required String gigType,
  }) {
    final rawSkills = d['requiredSkills'];
    final skillRequired = rawSkills is List
        ? rawSkills.join(', ')
        : (d['skillRequired'] as String?) ?? '';
    return GigTemplateModel(
      hostId: hostId,
      gigType: gigType,
      name: (d['title'] as String?) ?? '',
      title: (d['title'] as String?) ?? '',
      description: (d['description'] as String?) ?? '',
      budget: (d['budget'] as num?)?.toDouble() ?? 0,
      currencyCode: (d['currencyCode'] as String?) ?? 'USD',
      skillRequired: skillRequired,
      experienceLevel: (d['experienceLevel'] as String?) ?? '',
      payType: (d['payType'] as String?) ?? 'flat',
      hourlyRate: (d['hourlyRate'] as num?)?.toDouble(),
      workDurationHours: (d['workDurationHours'] as num?)?.toDouble(),
      workerSlots: (d['workerSlots'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.now(),
    );
  }
}
