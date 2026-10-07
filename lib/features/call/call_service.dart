import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'agora_token_service.dart';
import 'call_log.dart';

// Returns how the call ended (from the call screen's Navigator.pop), or null
// if it never got as far as the call screen.
Future<CallResult?> initiateCall({
  required BuildContext context,
  required String targetUserId,
  required String channelName,
  required bool isVideo,
  required void Function(bool) setLoading,
  required Widget Function(String channelName, String token) buildScreen,
}) async {
  final me = FirebaseAuth.instance.currentUser;
  if (me == null) return null;

  final myDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(me.uid)
      .get();
  final myName = myDoc.data()?['name'] ?? 'Unknown';

  setLoading(true);

  final firestore = FirebaseFirestore.instance;
  final targetDocId = targetUserId;

  try {
    final targetSnap = await firestore
        .collection('users')
        .doc(targetDocId)
        .get();

    if (!targetSnap.exists) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not found')),
        );
      }
      return null;
    }

    // One token generated for uid 0 ("any uid") covers both ends of the
    // call — see AgoraTokenService and the callee's own joinChannel(uid: 0)
    // in voice_call_screen.dart/video_call_screen.dart.
    final token = await AgoraTokenService.generateToken(channelName);

    final batch = firestore.batch();

    batch.set(
      firestore.collection('users').doc(me.uid),
      {
        'outgoingCall': {
          'targetId': targetDocId,
          'channelName': channelName,
          'status': 'calling',
          'createdAt': FieldValue.serverTimestamp(),
        },
      },
      SetOptions(merge: true),
    );

    batch.set(
      firestore.collection('users').doc(targetDocId),
      {
        'incomingCall': {
          'callerId': me.uid,
          'callerName': myName,
          'channelName': channelName,
          'token': token,
          'status': 'ringing',
          if (isVideo) 'isVideo': true,
          'createdAt': FieldValue.serverTimestamp(),
        },
      },
      SetOptions(merge: true),
    );

    await batch.commit();

    if (!context.mounted) return null;

    return await Navigator.push<CallResult>(
      context,
      MaterialPageRoute(builder: (_) => buildScreen(channelName, token)),
    );
  } catch (e) {
    debugPrint('Call error: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start call: $e')),
      );
    }
    return null;
  } finally {
    final cleanupBatch = firestore.batch();

    cleanupBatch.update(
      firestore.collection('users').doc(me.uid),
      {'outgoingCall': FieldValue.delete()},
    );

    cleanupBatch.update(
      firestore.collection('users').doc(targetDocId),
      {'incomingCall': FieldValue.delete()},
    );

    await cleanupBatch.commit();
    setLoading(false);
  }
}