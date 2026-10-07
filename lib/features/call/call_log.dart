import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// How a call ended, as seen from the caller's call screen — returned by
/// VoiceCallScreen/VideoCallScreen via Navigator.pop.
class CallResult {
  final bool answered;
  final bool declined;
  final int durationSeconds;

  const CallResult({
    required this.answered,
    required this.declined,
    required this.durationSeconds,
  });

  /// 'completed' | 'declined' | 'missed' — stored as the message's
  /// `callStatus`. Anything that never connected and wasn't declined
  /// (timeout, or the caller hanging up while it rang) counts as missed.
  String get status => answered
      ? 'completed'
      : declined
      ? 'declined'
      : 'missed';
}

String formatCallDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600 ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Plain-text fallback for a call-log message — what chat lists, push
/// notifications and the web chat show, since none of them know about
/// `callStatus`. The app's own chat renders a call bubble instead.
String callLogText({required bool isVideo, required CallResult result}) {
  final kind = isVideo ? 'video call' : 'voice call';
  final icon = isVideo ? '🎥' : '📞';
  switch (result.status) {
    case 'completed':
      final label = isVideo ? 'Video call' : 'Voice call';
      return '$icon $label · ${formatCallDuration(result.durationSeconds)}';
    case 'declined':
      return '$icon Declined $kind';
    default:
      return '$icon Missed $kind';
  }
}

/// Records a finished call as a message in the gig's chat room
/// (`gig_{gigId}`), so both participants see it in the conversation.
/// Written once, by the caller — the callee's own call screen never logs.
/// Best-effort: a failure here (e.g. the peer has blocked the caller, which
/// the messages create rule rejects) never surfaces to the user.
Future<void> logCallToGigChat({
  required String gigId,
  required String peerUid,
  required String peerName,
  required String myName,
  required bool? viewerIsWorker,
  required bool isVideo,
  required CallResult result,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final firestore = FirebaseFirestore.instance;
  final roomRef = firestore.collection('chat_rooms').doc('gig_$gigId');
  final text = callLogText(isVideo: isVideo, result: result);

  try {
    // Same lazy room creation as Chat._ensureRoomCreated — a call can be the
    // very first thing that happens between these two on this gig.
    final roomSnap = await roomRef.get();
    if (!roomSnap.exists) {
      await roomRef.set({
        'gigId': gigId,
        'isGigChat': true,
        'participants': [uid, peerUid],
        'sendTo': peerName,
        'createdByUid': uid,
        'createdByName': myName,
        'subject': 'Gig Chat',
        'status': 'open',
        'lastMessage': '',
        'lastMessageSender': '',
        'lastMessageSenderId': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        if (viewerIsWorker != null) 'workerUid': viewerIsWorker ? uid : peerUid,
        if (viewerIsWorker != null) 'hostUid': viewerIsWorker ? peerUid : uid,
      });
    }

    await roomRef.collection('messages').add({
      'senderId': uid,
      'isSupport': false,
      'name': myName,
      'text': text,
      'callType': isVideo ? 'video' : 'voice',
      'callStatus': result.status,
      'callDuration': result.durationSeconds,
      'hasSeen': false,
      'hasSeenByAdmin': false,
      'hasSeenByPeer': false,
      'isAutoReply': false,
      'isDeleted': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await roomRef.update({
      'lastMessage': text,
      'lastMessageSender': 'You',
      'lastMessageSenderId': uid,
      'lastMessageAt': FieldValue.serverTimestamp(),
      // Outstanding missed call, for the chat list's "Missed calls" filter.
      // Set for whoever missed it; any later call between the two that
      // wasn't missed (answered, declined, or the other one calling back)
      // clears it — a newer message alone doesn't.
      if (result.status == 'missed') ...{
        'missedCallFor': peerUid,
        'missedCallType': isVideo ? 'video' : 'voice',
        'missedCallAt': FieldValue.serverTimestamp(),
      } else ...{
        'missedCallFor': FieldValue.delete(),
        'missedCallType': FieldValue.delete(),
        'missedCallAt': FieldValue.delete(),
      },
    });
  } catch (e) {
    debugPrint('[CallLog] failed to log call to gig_$gigId: $e');
  }
}
