// Giggre AI support — "Talk to a person": opens a support ticket with the AI
// chat attached, then the ticket's chat.
//
// Writes the same documents as Contact Us → Submit a ticket
// (contact_us.dart, _submitTicket, signed-in path): a support_tickets doc, a
// chat_rooms support room, the first message and the optional auto-reply.
// Keep the two in sync. AI tickets differ only in subject/message and the
// extra `origin` and `aiTranscript` fields — `source` stays 'user', because
// contact_us.dart's _resolveRoomId treats any other source as an admin
// broadcast and would open an empty room instead of this one.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/providers/current_user_provider.dart';
import '../../../core/services/content_filter_service.dart';
import 'support_chat_store.dart';

Future<void> handOffAiChatToSupport({
  required GlobalKey<NavigatorState> navigatorKey,
  required CurrentUserProvider user,
  required List<SupportMessage> transcript,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final name = user.currentName ?? '';
  final email =
      user.currentEmail ?? FirebaseAuth.instance.currentUser?.email ?? '';
  const subject = 'Giggre Help: talk to a person';
  final message = transcript.isEmpty
      ? 'I’d like to talk to a person. (From Giggre Help, before asking the AI anything.)'
      : 'I’d like to talk to a person. My Giggre Help (AI) chat:\n\n${transcript.map((m) => '${m.isUser ? 'Me' : 'Giggre Help'}: ${m.text}').join('\n\n')}';

  void notify(String text) => _messenger(navigatorKey)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  // Same check Contact Us runs before submitting; onSupportTicketWordFilter
  // would delete the ticket anyway and strand the room.
  if (ContentFilterService.instance.check(message)) {
    notify(ContentFilterService.rejectionMessage);
    return;
  }

  notify('Connecting you with the Giggre team…');

  try {
    final db = FirebaseFirestore.instance;
    final ticketNumber = await _generateTicketNumber();
    final roomRef = db.collection('chat_rooms').doc();

    await db.collection('support_tickets').add({
      'source': 'user',
      'origin': 'ai_chat',
      'aiTranscript': transcript
          .map((m) => {'role': m.role, 'text': m.text})
          .toList(),
      'ticket_number': ticketNumber,
      'userId': uid,
      'name': name,
      'email': email,
      'subject': subject,
      'message': message,
      'roomId': roomRef.id,
      'status': 'open',
      'hasRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      'recipientType': null,
      'recipients': [],
      'createdBy': null,
    });

    await roomRef.set({
      'userId': uid,
      'name': name,
      'subject': subject,
      'sendTo': 'Giggre Support',
      'status': 'open',
      'isSupport': true,
      'ticketId': null,
      'lastMessage': message,
      'lastMessageSender': 'You',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    final autoReplySnap = await db
        .collection('support_settings')
        .doc('qGDefSx1JYdx86VxlznN')
        .get();
    final isAutoReplyEnabled =
        autoReplySnap.data()?['enabled_auto_reply'] ?? false;
    final autoReply = autoReplySnap.data()?['auto_reply_message'] ??
        "Thank you for contacting us! We'll get back to you shortly.";

    await roomRef.collection('messages').add({
      'senderId': uid,
      'isSupport': false,
      'name': name,
      'text': message,
      'hasSeen': true,
      'hasSeenByAdmin': isAutoReplyEnabled ? true : false,
      'createdAt': FieldValue.serverTimestamp(),
      'isAutoReply': false,
    });

    _messenger(navigatorKey)?.hideCurrentSnackBar();
    navigatorKey.currentState?.pushNamed('/chat/${roomRef.id}');

    // Contact Us waits 2 s before the auto-reply; do the same, after the chat
    // is already open.
    if (isAutoReplyEnabled) {
      await Future.delayed(const Duration(seconds: 2));
      await roomRef.collection('messages').add({
        'senderId': 'support',
        'isSupport': true,
        'name': 'Giggre Support',
        'text': autoReply,
        'hasSeen': false,
        'hasSeenByAdmin': true,
        'createdAt': FieldValue.serverTimestamp(),
        'isAutoReply': true,
      });
      await roomRef.update({
        'lastMessage': autoReply,
        'lastMessageSender': 'Support',
        'lastMessageAt': FieldValue.serverTimestamp(),
      });
    }
  } catch (e) {
    debugPrint('[SupportAI] hand-off to support failed: $e');
    notify('Couldn’t reach the Giggre team. Please try again, or use Contact Us.');
  }
}

// The bubble sits above the navigator, so snackbars go through the app's
// navigator context, read fresh each time.
ScaffoldMessengerState? _messenger(GlobalKey<NavigatorState> navigatorKey) {
  final ctx = navigatorKey.currentContext;
  return ctx == null ? null : ScaffoldMessenger.maybeOf(ctx);
}

// Same counter and format as contact_us.dart's _generateTicketNumber.
Future<String> _generateTicketNumber() async {
  final counterRef = FirebaseFirestore.instance
      .collection('_counters')
      .doc('support_tickets');
  final year = DateTime.now().year;

  final count = await FirebaseFirestore.instance.runTransaction<int>((t) async {
    final snap = await t.get(counterRef);
    final current = (snap.data()?['count_$year'] as int?) ?? 0;
    final next = current + 1;
    t.set(counterRef, {'count_$year': next}, SetOptions(merge: true));
    return next;
  });

  return 'TKT-$year-${count.toString().padLeft(6, '0')}';
}
