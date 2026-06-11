import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/main.dart' show navigatorKey;
import 'package:giggre_app/screens/chat/chat.dart';

class GigChatAction extends StatefulWidget {
  const GigChatAction({
    super.key,
    required this.gigId,
    required this.targetUserId,
    required this.targetUserName,
  });

  final String gigId;
  final String targetUserId;
  final String targetUserName;

  @override
  State<GigChatAction> createState() => _GigChatActionState();
}

class _GigChatActionState extends State<GigChatAction> {
  bool _hasUnread = false;
  StreamSubscription? _roomSub;       // watches the room doc
  StreamSubscription? _msgSub;        // watches messages inside the room
  final List<StreamSubscription> _roomSubs = []; // mirrors home_screen pattern

  @override
  void initState() {
    super.initState();
    _listenForUnread();
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _msgSub?.cancel();
    for (final s in _roomSubs) s.cancel();
    super.dispose();
  }

  // Mirrors _listenForUnreadMessages() in home_screen.dart exactly.
  void _listenForUnread() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final roomId = 'gig_${widget.gigId}';

    _roomSub = FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(roomId)
        .snapshots()
        .listen(
          (roomSnap) {
            // Cancel old message subs before setting up new ones (mirrors home_screen.dart)
            for (final s in _roomSubs) s.cancel();
            _roomSubs.clear();

            if (!roomSnap.exists) {
              if (mounted) setState(() => _hasUnread = false);
              return;
            }

            // Room exists — listen to messages from the other user that are unseen.
            // Uses the same two-equality pattern as home_screen.dart:
            //   isSupport==true  &&  hasSeen==false  (support)
            //   senderId==X      &&  hasSeen==false  (gig)
            final sub = FirebaseFirestore.instance
                .collection('chat_rooms')
                .doc(roomId)
                .collection('messages')
                .where('senderId', isEqualTo: widget.targetUserId)
                .where('hasSeen', isEqualTo: false)
                .limit(1)
                .snapshots()
                .map((s) => s.docs.isNotEmpty)
                .listen(
                  (hasUnread) {
                    if (mounted) setState(() => _hasUnread = hasUnread);
                    debugPrint('[GigChatAction] Badge → $hasUnread');
                  },
                  onError: (e) =>
                      debugPrint('[GigChatAction] message stream error: $e'),
                );
            _roomSubs.add(sub);
          },
          onError: (e) {
            if (FirebaseAuth.instance.currentUser == null) return;
            debugPrint('[GigChatAction] room stream error: $e');
          },
        );
  }

  void _openChat() {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => Chat(
          roomId: 'gig_${widget.gigId}',
          isGigChat: true,
          gigChatParams: GigChatParams(
            gigId: widget.gigId,
            peerUid: widget.targetUserId,
            peerName: widget.targetUserName,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _openChat,
      tooltip: 'Chat with ${widget.targetUserName}',
      color: kBlue,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.chat_bubble_outline_rounded, size: 22),
          if (_hasUnread)
            Positioned(
              top: -3,
              right: -3,
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
    );
  }
}
