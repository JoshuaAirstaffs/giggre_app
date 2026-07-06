import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/screens/chat/chat.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Worker Message Action — opens (or lazily creates) a direct chat room with
//  a worker, independent of any specific gig. Mirrors GigChatAction, but the
//  room id is derived from the two participant uids instead of a gig id.
// ─────────────────────────────────────────────────────────────────────────────
String directMessageRoomId(String uidA, String uidB) {
  final ids = [uidA, uidB]..sort();
  return 'dm_${ids.join('_')}';
}

class WorkerMessageAction extends StatefulWidget {
  const WorkerMessageAction({
    super.key,
    required this.workerId,
    required this.workerName,
  });

  final String workerId;
  final String workerName;

  @override
  State<WorkerMessageAction> createState() => _WorkerMessageActionState();
}

class _WorkerMessageActionState extends State<WorkerMessageAction> {
  bool _hasUnread = false;
  StreamSubscription? _unreadSub;

  @override
  void initState() {
    super.initState();
    _listenForUnread();
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    super.dispose();
  }

  void _listenForUnread() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final roomId = directMessageRoomId(uid, widget.workerId);

    _unreadSub = FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .where('senderId', isEqualTo: widget.workerId)
        .where('hasSeen', isEqualTo: false)
        .limit(1)
        .snapshots()
        .listen(
          (snap) {
            if (mounted) setState(() => _hasUnread = snap.docs.isNotEmpty);
          },
          onError: (e) =>
              debugPrint('[WorkerMessageAction] unread stream error: $e'),
        );
  }

  void _openChat() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Chat(
          roomId: directMessageRoomId(uid, widget.workerId),
          isGigChat: true,
          gigChatParams: GigChatParams(
            gigId: '',
            peerUid: widget.workerId,
            peerName: widget.workerName,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openChat,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: kBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.chat_bubble_outline_rounded,
                color: kBlue, size: 18),
            if (_hasUnread)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
