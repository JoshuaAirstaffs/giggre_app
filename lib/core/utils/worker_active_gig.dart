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

/// One-shot check: does this worker already have an active gig (in any of
/// the three gig collections)? Used to block applying/accepting a new gig
/// while one is still in progress.
Future<bool> workerHasActiveGig(String uid) async {
  final db = FirebaseFirestore.instance;
  final results = await Future.wait([
    db
        .collection('quick_gigs')
        .where('workerId', isEqualTo: uid)
        .where('status', whereIn: kWorkerActiveGigStatuses)
        .limit(1)
        .get(),
    db
        .collection('open_gigs')
        .where('workerId', isEqualTo: uid)
        .where('status', whereIn: kWorkerActiveGigStatuses)
        .limit(1)
        .get(),
    db
        .collection('offered_gigs')
        .where('workerId', isEqualTo: uid)
        .where('status', whereIn: kWorkerActiveGigStatuses)
        .limit(1)
        .get(),
  ]);
  return results.any((snap) => snap.docs.isNotEmpty);
}
