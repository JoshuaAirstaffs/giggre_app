import 'package:cloud_firestore/cloud_firestore.dart';

class CallHelper {
  static final _firestore = FirebaseFirestore.instance;

  /// Returns a status message if the user is on a call, null otherwise.
  static Future<String?> getCallStatus(String userId) async {
    final snap = await _firestore
        .collection('users')
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;

    final data = snap.docs.first.data();

    final outgoing = data['outgoingCall'] as Map<String, dynamic>?;
    if (outgoing != null) return 'User is currently on a call';

    final incoming = data['incomingCall'] as Map<String, dynamic>?;
    if (incoming != null) return 'User is currently on a call';

    return null;
  }
}