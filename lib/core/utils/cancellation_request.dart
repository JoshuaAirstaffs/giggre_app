import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Who asked for a cancellation that's still awaiting admin review.
//
//  Every writer stamps the entry it appends to `cancellation_reason` with a
//  `requestedBy` — 'host' (host_gig_card / gig_detail_sheet), 'worker'
//  (working_ui) or 'system' (the auto-cancel function) — and the last entry is
//  the live one. Same convention as the two notification sheets and
//  autoApproveIfStaleWorkerCancellation in functions/src/index.ts; do not read
//  this field any other way.
//
//  Worker-side UI used to ignore it entirely, so a host-initiated request
//  surfaced to the worker as "admin is reviewing your request".
// ─────────────────────────────────────────────────────────────────────────────

const String kCancelRequesterHost = 'host';
const String kCancelRequesterWorker = 'worker';

/// `requestedBy` of the newest cancellation entry, or null when the doc
/// carries no cancellation request at all (or a legacy one without the field).
String? cancellationRequestedBy(Map<String, dynamic>? data) {
  final reasons = data?['cancellation_reason'] as List?;
  if (reasons == null || reasons.isEmpty) return null;
  final last = reasons.last;
  if (last is! Map) return null;
  return last['requestedBy'] as String?;
}

/// Worker-side reading of [cancellationRequestedBy]: true only when the host
/// is the one who asked. Missing/legacy `requestedBy` falls back to false —
/// worker-initiated was the only case that existed before hosts could request.
bool isHostRequestedCancellation(Map<String, dynamic>? data) =>
    cancellationRequestedBy(data) == kCancelRequesterHost;

/// True when the newest cancellation entry was approved by the auto-approve
/// function (`approvedBy: 'system'` — autoApproveIfStaleWorkerCancellation in
/// functions/src/index.ts), which frees the slot itself; the worker's own
/// cleanup must not free it a second time.
bool cancellationApprovedBySystem(Map<String, dynamic>? data) {
  final reasons = data?['cancellation_reason'] as List?;
  if (reasons == null || reasons.isEmpty) return false;
  final last = reasons.last;
  return last is Map && last['approvedBy'] == 'system';
}

/// Copy for the worker-side snackbars that block applying for / accepting a
/// new gig while a cancellation is still unapproved. [requestedBy] is what
/// workerPendingCancellationRequestedBy returned.
String pendingCancellationBlockMessage(String requestedBy) =>
    requestedBy == kCancelRequesterHost
    ? "The host's request to cancel your gig hasn't been reviewed by the admin yet."
    : "Your cancellation request hasn't been approved by the admin yet.";

// ── Writing a host's request ────────────────────────────────────────────────
//  Cancellation is adjudicated per worker: on a multi-worker gig each
//  `workers/{workerId}` doc carries its own request, so the worker's own
//  listener (WorkingUI._targetRef) actually sees it, admin rules on one slot
//  without touching the others, and the existing slot cleanup — decrement
//  filledSlotCount, reopen for backfill (autoApproveIfStaleWorkerCancellation
//  in functions/src/index.ts) — applies unchanged. Writing only the gig doc,
//  as the host side used to, reached nobody on those gigs.

/// Slot statuses a host can request cancellation for: same values as
/// WorkerSlotModel.activeStatuses / kWorkerActiveGigStatuses, minus
/// 'cancellation_requested' (one is already pending). Do not invent new
/// status values here.
const List<String> kHostCancellableSlotStatuses = [
  'navigating',
  'arrived',
  'working',
  'task_complete',
  'payment',
];

/// The update one host cancellation request writes, to a gig doc or to a
/// single worker's slot doc.
///
/// [lastProgressStatus] freezes the step both sides' progress cards fall back
/// to while the request is pending, and `cancellationRequestedAt` is what the
/// notification sheets key their activity item off (tryAdd bails on a null
/// timestamp) as well as what the auto-approve sweep ages. Omitting either —
/// as the host gig card's cancel used to — makes the request invisible in
/// both notification lists and jumps the host's stepper to 'working'.
Map<String, Object?> hostCancellationRequestUpdate({
  required String reason,
  required String lastProgressStatus,
}) => {
  'cancellation_reason': FieldValue.arrayUnion([
    {'reason': reason, 'approved': null, 'requestedBy': kCancelRequesterHost},
  ]),
  'lastProgressStatus': lastProgressStatus,
  'cancellationRequestedAt': FieldValue.serverTimestamp(),
  'status': 'cancellation_requested',
};

/// Host-side request against one worker's slot on a multi-worker gig.
Future<void> requestHostCancellationForWorker({
  required String gigCollection,
  required String gigId,
  required String workerId,
  required String workerStatus,
  required String reason,
}) {
  return FirebaseFirestore.instance
      .collection(gigCollection)
      .doc(gigId)
      .collection('workers')
      .doc(workerId)
      .update(
        hostCancellationRequestUpdate(
          reason: reason,
          lastProgressStatus: workerStatus,
        ),
      );
}

/// Host-side request against a whole gig: flags the gig doc and fans the same
/// request out to every active worker slot, so each worker is told and each
/// slot is reviewed on its own. A single-worker gig simply has no slot docs —
/// the gig doc that its worker listens to is the only write — so both shapes
/// go through here. Returns how many slots were flagged.
Future<int> requestHostCancellationForGig({
  required String gigCollection,
  required String gigId,
  required String gigStatus,
  required String reason,
}) async {
  final db = FirebaseFirestore.instance;
  final gigRef = db.collection(gigCollection).doc(gigId);

  final slots = await gigRef
      .collection('workers')
      .where('status', whereIn: kHostCancellableSlotStatuses)
      .get();

  final batch = db.batch();
  for (final doc in slots.docs) {
    batch.update(
      doc.reference,
      hostCancellationRequestUpdate(
        reason: reason,
        lastProgressStatus: doc.data()['status'] as String? ?? 'working',
      ),
    );
  }
  batch.update(
    gigRef,
    hostCancellationRequestUpdate(
      reason: reason,
      lastProgressStatus: gigStatus,
    ),
  );
  await batch.commit();
  return slots.docs.length;
}

// ── Workers released from a multi-worker gig ────────────────────────────────
//  Once a slot's cancellation is approved the worker drops off the host's
//  list, but the host still needs to know who left and on whose request.
//  Approval never deletes the slot doc — admin by hand or
//  autoApproveIfStaleWorkerCancellation (functions/src/index.ts) both leave
//  it at status 'cancelled' — so the slot itself is the record.

class ReleasedWorker {
  final String workerId;
  final String workerName;

  /// 'worker' | 'host' | 'system', same as cancellationRequestedBy.
  final String requestedBy;

  const ReleasedWorker({
    required this.workerId,
    required this.workerName,
    required this.requestedBy,
  });

  bool get byHost => requestedBy == kCancelRequesterHost;
}

/// Everyone who has come off this gig through an approved cancellation, from
/// [slots] — every slot doc's data, doc id as `workerId`. A worker who is back
/// on the gig under a live slot is left out.
List<ReleasedWorker> releasedWorkersFor(Iterable<Map<String, dynamic>> slots) {
  final byId = <String, ReleasedWorker>{};
  final stillOn = <String>{};

  for (final slot in slots) {
    final id = slot['workerId'] as String?;
    if (id == null || id.isEmpty) continue;
    if (slot['status'] != 'cancelled') {
      stillOn.add(id);
      continue;
    }
    byId[id] = ReleasedWorker(
      workerId: id,
      workerName: slot['workerName'] as String? ?? '',
      requestedBy: cancellationRequestedBy(slot) ?? kCancelRequesterWorker,
    );
  }

  return [
    for (final w in byId.values)
      if (!stillOn.contains(w.workerId)) w,
  ];
}
