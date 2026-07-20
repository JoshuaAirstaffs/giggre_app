import 'package:cloud_firestore/cloud_firestore.dart';

// Same collection/field/status convention as _checkForActiveGig
// (gig_worker_screen.dart) and watchActiveWorkerGig (active_gig_bar.dart) —
// do not invent new status values here.
const List<String> kWorkerActiveGigStatuses = [
  'navigating',
  'arrived',
  'working',
  'task_complete',
  'payment',
  'cancellation_requested',
];

const List<String> _gigCollections = ['quick_gigs', 'open_gigs', 'offered_gigs'];

/// One-shot check: does this worker already have an active gig (in any of
/// the three gig collections, on any multi-worker slot)? Used to block
/// applying/accepting a new gig while one is still in progress.
///
/// Multi-worker gigs record each worker's status on their own
/// `{gigCollection}/{gigId}/workers/{workerId}` doc, so the primary check is
/// a single collection-group query across all three collections. Legacy
/// in-flight gigs (posted before the `workers` subcollection existed) still
/// carry the status on the top-level gig doc under `workerId`, so that query
/// is OR'd in for the transition window — legacy gigs are short-lived, so
/// this dual-read drains naturally without a backfill.
Future<bool> workerHasActiveGig(String uid) async {
  final db = FirebaseFirestore.instance;

  final subcollectionSnap = await db
      .collectionGroup('workers')
      .where('workerId', isEqualTo: uid)
      .where('status', whereIn: kWorkerActiveGigStatuses)
      .limit(1)
      .get();
  if (subcollectionSnap.docs.isNotEmpty) return true;

  final legacyResults = await Future.wait([
    for (final collection in _gigCollections)
      db
          .collection(collection)
          .where('workerId', isEqualTo: uid)
          .where('status', whereIn: kWorkerActiveGigStatuses)
          .limit(1)
          .get(),
  ]);
  return legacyResults.any((snap) => snap.docs.isNotEmpty);
}
