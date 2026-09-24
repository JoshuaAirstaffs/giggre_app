import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/cancellation_request.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Small dashboard banner for the gap left by ActiveGigBar hiding immediately
//  once a cancellation is requested (see watchActiveWorkerGig in
//  active_gig_bar.dart) — this is the worker's only feedback that a request
//  (theirs or the host's) is still awaiting admin approval.
// ─────────────────────────────────────────────────────────────────────────────

/// A cancellation request still awaiting approval on one of this worker's
/// gigs, carrying who asked for it — the card's copy differs, since either
/// side can request one.
class PendingCancellation {
  /// 'worker' | 'host' | 'system'. Legacy entries with no `requestedBy` read
  /// as 'worker', the only case that existed before hosts could request.
  final String requestedBy;

  const PendingCancellation(this.requestedBy);

  factory PendingCancellation.fromGig(Map<String, dynamic> data) =>
      PendingCancellation(
        cancellationRequestedBy(data) ?? kCancelRequesterWorker,
      );

  bool get byHost => requestedBy == kCancelRequesterHost;
}

/// Live stream of the current user's cancellation request still awaiting
/// approval (null when there is none), across quick_gigs/open_gigs
/// (multi-worker slot docs, same scoping as watchActiveWorkerGig) and the
/// legacy top-level workerId/status fields on
/// quick_gigs/open_gigs/offered_gigs.
Stream<PendingCancellation?> watchPendingCancellation(String uid) {
  late final StreamController<PendingCancellation?> controller;
  StreamSubscription? slotSub, quickSub, openSub, offeredSub;
  PendingCancellation? slotPending;
  PendingCancellation? quickPending;
  PendingCancellation? openPending;
  PendingCancellation? offeredPending;

  void emit() {
    if (controller.isClosed) return;
    controller.add(slotPending ?? quickPending ?? openPending ?? offeredPending);
  }

  PendingCancellation? firstOf(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs.isEmpty
          ? null
          : PendingCancellation.fromGig(snap.docs.first.data());

  controller = StreamController<PendingCancellation?>.broadcast(
    onListen: () {
      slotSub = FirebaseFirestore.instance
          .collectionGroup('workers')
          .where('workerId', isEqualTo: uid)
          .where('status', isEqualTo: 'cancellation_requested')
          .snapshots()
          .listen((snap) {
        final slot = snap.docs.where((d) {
          final collection = d.data()['gigCollection'] as String?;
          return collection == 'quick_gigs' || collection == 'open_gigs';
        });
        slotPending = slot.isEmpty
            ? null
            : PendingCancellation.fromGig(slot.first.data());
        emit();
      }, onError: (_) {});
      quickSub = FirebaseFirestore.instance
          .collection('quick_gigs')
          .where('workerId', isEqualTo: uid)
          .where('status', isEqualTo: 'cancellation_requested')
          .limit(1)
          .snapshots()
          .listen((snap) {
        quickPending = firstOf(snap);
        emit();
      }, onError: (_) {});
      openSub = FirebaseFirestore.instance
          .collection('open_gigs')
          .where('workerId', isEqualTo: uid)
          .where('status', isEqualTo: 'cancellation_requested')
          .limit(1)
          .snapshots()
          .listen((snap) {
        openPending = firstOf(snap);
        emit();
      }, onError: (_) {});
      offeredSub = FirebaseFirestore.instance
          .collection('offered_gigs')
          .where('workerId', isEqualTo: uid)
          .where('status', isEqualTo: 'cancellation_requested')
          .limit(1)
          .snapshots()
          .listen((snap) {
        offeredPending = firstOf(snap);
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
  /// The host asked for this cancellation, not the worker reading the card.
  final bool requestedByHost;

  const PendingCancellationCard({super.key, this.requestedByHost = false});

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_top_rounded, color: _color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  requestedByHost
                      ? 'The host asked to cancel your gig'
                      : 'Waiting for the admin to approve your cancellation',
                  style: const TextStyle(
                    color: _color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  requestedByHost
                      ? "Waiting for the admin to review it — you'll be able to take new gigs once it's settled"
                      : "You'll be able to take new gigs once it's approved",
                  style: const TextStyle(
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
