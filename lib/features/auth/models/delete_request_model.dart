import 'package:cloud_firestore/cloud_firestore.dart';

class DeleteRequestModel {
  final String requestId;
  final String userId;
  final String email;
  final DateTime requestedAt;
  final DateTime deletionScheduledAt;
  final String status; // pending_deletion | cancelled | completed
  final DateTime? cancelledAt;
  final DateTime? deletedAt;
  final String? reason;
  final String? processedBy;
  final String? notes;

  const DeleteRequestModel({
    required this.requestId,
    required this.userId,
    required this.email,
    required this.requestedAt,
    required this.deletionScheduledAt,
    required this.status,
    this.cancelledAt,
    this.deletedAt,
    this.reason,
    this.processedBy,
    this.notes,
  });

  Map<String, dynamic> toMap() => {
        'requestId': requestId,
        'userId': userId,
        'email': email,
        'requestedAt': Timestamp.fromDate(requestedAt),
        'deletionScheduledAt': Timestamp.fromDate(deletionScheduledAt),
        'status': status,
        if (cancelledAt != null)
          'cancelledAt': Timestamp.fromDate(cancelledAt!),
        if (deletedAt != null) 'deletedAt': Timestamp.fromDate(deletedAt!),
        if (reason != null) 'reason': reason,
        if (processedBy != null) 'processedBy': processedBy,
        if (notes != null) 'notes': notes,
      };

  factory DeleteRequestModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return DeleteRequestModel(
      requestId: doc.id,
      userId: d['userId'] ?? '',
      email: d['email'] ?? '',
      requestedAt: (d['requestedAt'] as Timestamp).toDate(),
      deletionScheduledAt: (d['deletionScheduledAt'] as Timestamp).toDate(),
      status: d['status'] ?? 'pending_deletion',
      cancelledAt: d['cancelledAt'] != null
          ? (d['cancelledAt'] as Timestamp).toDate()
          : null,
      deletedAt: d['deletedAt'] != null
          ? (d['deletedAt'] as Timestamp).toDate()
          : null,
      reason: d['reason'] as String?,
      processedBy: d['processedBy'] as String?,
      notes: d['notes'] as String?,
    );
  }
}
