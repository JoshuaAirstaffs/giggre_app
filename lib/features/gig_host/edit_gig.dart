import 'package:cloud_firestore/cloud_firestore.dart';

/// Host-side gig editing for Open and Offered gigs. Same rules as the website
/// (giggre-website src/lib/host-gigs.ts canEditGig): a gig can only be edited
/// while nobody is committed to it yet.
///
/// - Open: still `open`, slots not closed, no applicants, no filled slots.
/// - Offered: still `offered` and no recipient has accepted/declined yet.
///
/// Quick gigs are never editable (they dispatch immediately).
bool canEditGig(String gigType, Map<String, dynamic>? data) {
  if (data == null) return false;
  final status = data['status'] as String?;
  final filled = (data['filledSlotCount'] as num?)?.toInt() ?? 0;
  switch (gigType) {
    case 'open':
      final applicants = data['applicants'] as List?;
      final workerId =
          data['assignedWorkerId'] as String? ?? data['workerId'] as String?;
      return status == 'open' &&
          data['slotsClosed'] != true &&
          (applicants == null || applicants.isEmpty) &&
          (workerId == null || workerId.isEmpty) &&
          filled == 0;
    case 'offered':
      return status == 'offered' && filled == 0;
    default:
      return false;
  }
}

/// Thrown by [saveGigEdit] when the gig changed (someone applied / accepted)
/// between opening the edit screen and saving.
class GigNoLongerEditable implements Exception {
  final String message;
  const GigNoLongerEditable(this.message);
  @override
  String toString() => message;
}

/// Writes [fields] onto the gig in a transaction that re-checks
/// [canEditGig] against the live doc, so an applicant/acceptance that lands
/// while the host is editing can't be silently overwritten.
///
/// For multi-recipient Offered gigs, [workerSlotIds] are the `workers`
/// subcollection doc ids; every slot must still be `offered`, and each gets
/// [slotFields] (its denormalized copy of the pay fields).
///
/// Never include `taskTypeId` in [fields]: firestore.rules' changesGigCodes()
/// rejects the whole update if it changes (GSIN codes are derived once).
Future<void> saveGigEdit({
  required String gigType,
  required String gigId,
  required Map<String, dynamic> fields,
  List<String> workerSlotIds = const [],
  Map<String, dynamic> slotFields = const {},
}) async {
  final db = FirebaseFirestore.instance;
  final collection = gigType == 'open' ? 'open_gigs' : 'offered_gigs';
  final gigRef = db.collection(collection).doc(gigId);

  await db.runTransaction((tx) async {
    final snap = await tx.get(gigRef);
    if (!canEditGig(gigType, snap.data())) {
      throw GigNoLongerEditable(
        gigType == 'open'
            ? 'Someone already applied to this gig, so it can no longer be edited.'
            : 'A worker already responded to this offer, so it can no longer be edited.',
      );
    }
    final slotRefs = [
      for (final id in workerSlotIds) gigRef.collection('workers').doc(id),
    ];
    final slotSnaps = [for (final r in slotRefs) await tx.get(r)];
    for (final s in slotSnaps) {
      if (s.exists && s.data()?['status'] != 'offered') {
        throw const GigNoLongerEditable(
          'A worker already responded to this offer, so it can no longer be edited.',
        );
      }
    }

    tx.update(gigRef, {...fields, 'editedAt': FieldValue.serverTimestamp()});
    if (slotFields.isNotEmpty) {
      for (final s in slotSnaps) {
        if (s.exists) tx.update(s.reference, slotFields);
      }
    }
  });
}

/// Fields shared by both gig types. A cleared optional value is deleted
/// (not just omitted) — update() merges, so omitting it would leave the old
/// value behind, e.g. a schedule after switching to Flexible.
Map<String, dynamic> commonGigEditFields({
  required String title,
  required String description,
  required double budget,
  required String currencyCode,
  required String payType,
  required double? hourlyRate,
  required double? workDurationHours,
  required GeoPoint location,
  required String address,
  required Map<String, dynamic>? place,
  required DateTime? scheduledDate,
  required String experienceLevel,
}) {
  return {
    'title': title,
    'description': description,
    'budget': budget,
    'ratePerSlot': budget,
    'currencyCode': currencyCode,
    'payType': payType,
    'hourlyRate': hourlyRate ?? FieldValue.delete(),
    'workDurationHours': workDurationHours ?? FieldValue.delete(),
    'location': location,
    'address': address,
    if (place != null && place.isNotEmpty) 'place': place,
    'scheduledDate': scheduledDate != null
        ? Timestamp.fromDate(scheduledDate)
        : FieldValue.delete(),
    'experienceLevel': experienceLevel,
  };
}
