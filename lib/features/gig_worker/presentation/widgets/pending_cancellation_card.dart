import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Small dashboard banner for the gap left by ActiveGigBar hiding immediately
//  once a cancellation is requested (see watchActiveWorkerGig in
//  active_gig_bar.dart) — this is the worker's only feedback that their
//  request is still awaiting host/admin approval.
// ─────────────────────────────────────────────────────────────────────────────

/// Live stream of whether the current user has a cancellation request still
/// awaiting approval, across quick_gigs/open_gigs (multi-worker slot docs,
/// same scoping as watchActiveWorkerGig) and the legacy top-level
/// workerId/status fields on quick_gigs/open_gigs/offered_gigs.
Stream<bool> watchPendingCancellation(String uid) {
  late final StreamController<bool> controller;
  StreamSubscription? slotSub, quickSub, openSub, offeredSub;
  bool slotPending = false;
  bool quickPending = false;
  bool openPending = false;
  bool offeredPending = false;

  void emit() {
    if (controller.isClosed) return;
    controller.add(slotPending || quickPending || openPending || offeredPending);
  }

  controller = StreamController<bool>.broadcast(
    onListen: () {
      slotSub = FirebaseFirestore.instance
          .collectionGroup('workers')
          .where('workerId', isEqualTo: uid)
          .where('status', isEqualTo: 'cancellation_requested')
          .snapshots()
          .listen((snap) {
        slotPending = snap.docs.any((d) {
          final collection = d.data()['gigCollection'] as String?;
          return collection == 'quick_gigs' || collection == 'open_gigs';
        });
        emit();
      }, onError: (_) {});
      quickSub = FirebaseFirestore.instance
          .collection('quick_gigs')
          .where('workerId', isEqualTo: uid)
          .where('status', isEqualTo: 'cancellation_requested')
          .limit(1)
          .snapshots()
          .listen((snap) {
        quickPending = snap.docs.isNotEmpty;
        emit();
      }, onError: (_) {});
      openSub = FirebaseFirestore.instance
          .collection('open_gigs')
          .where('workerId', isEqualTo: uid)
          .where('status', isEqualTo: 'cancellation_requested')
          .limit(1)
          .snapshots()
          .listen((snap) {
        openPending = snap.docs.isNotEmpty;
        emit();
      }, onError: (_) {});
      offeredSub = FirebaseFirestore.instance
          .collection('offered_gigs')
          .where('workerId', isEqualTo: uid)
          .where('status', isEqualTo: 'cancellation_requested')
          .limit(1)
          .snapshots()
          .listen((snap) {
        offeredPending = snap.docs.isNotEmpty;
        emit();
      }, onError: (_) {});
    },
    onCancel: () {
      slotSub?.cancel();
      quickSub?.cancel();
      openSub?.cancel();
      offeredSub?.cancel();
    },
  );
  return controller.stream;
}

class PendingCancellationCard extends StatelessWidget {
  const PendingCancellationCard({super.key});

  static const Color _color = Color(0xFFB45309);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_top_rounded, color: _color, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waiting for the admin to approve your cancellation',
                  style: TextStyle(
                    color: _color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  "You'll be able to apply for new gigs once it's approved",
                  style: TextStyle(
                    color: _color,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
