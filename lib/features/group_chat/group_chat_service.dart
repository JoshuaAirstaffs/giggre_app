import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:giggre_app/features/live_support/live_support_bubble.dart'
    show isLiveSupportAccount; // TEMP: live support
import 'package:giggre_app/main.dart' show flavor;

// Group chats: data access for lib/features/group_chat/. Membership changes
// go through the callables in functions/src/groupChats.ts; members write only
// messages, their own read marker and their own mute (firestore.rules).

final _functionsRegion = flavor == 'prod' ? 'us-central1' : 'asia-east2';

const maxGroupMembers = 50;
const maxGroupNameLength = 50;

/// An error the UI can show as is.
class GroupChatException implements Exception {
  GroupChatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Name and photo of a person, from publicProfiles (readable by any
/// signed-in user, never carries an email or phone).
class GroupPerson {
  const GroupPerson({
    required this.uid,
    required this.name,
    this.photoUrl,
    this.isVerified = false,
    this.workerRating,
    this.hostRating,
  });
  final String uid;
  final String name;
  final String? photoUrl;
  final bool isVerified;
  // Averages; null when they have no ratings in that role yet.
  final double? workerRating;
  final double? hostRating;

  /// Same wording as user search results: "★ 4.8 as Gig Worker · ★ 4.6 as
  /// Gig Host", or null when there are no ratings.
  String? get ratingLine {
    final parts = [
      if (workerRating != null)
        '★ ${workerRating!.toStringAsFixed(1)} as Gig Worker',
      if (hostRating != null) '★ ${hostRating!.toStringAsFixed(1)} as Gig Host',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

double? _average(Object? v) {
  if (v is! Map) return null;
  final count = (v['count'] as num?)?.toInt() ?? 0;
  return count > 0 ? (v['average'] as num?)?.toDouble() : null;
}

class GroupChatService {
  GroupChatService._();

  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get groups =>
      _db.collection('group_chats');

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ── reads ────────────────────────────────────────────────────────────────

  static Stream<QuerySnapshot<Map<String, dynamic>>> myGroups(String uid) =>
      groups
          .where('participants', arrayContains: uid)
          .orderBy('lastMessageAt', descending: true)
          .snapshots();

  static Stream<DocumentSnapshot<Map<String, dynamic>>> group(String id) =>
      groups.doc(id).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> messages(
    String groupId, {
    int limit = 200,
  }) => groups
      .doc(groupId)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots();

  /// True when something newer than [uid]'s read marker was posted by
  /// someone else (or by the group itself: joins, renames).
  static bool isUnread(Map<String, dynamic> group, String uid) {
    final last = group['lastMessageAt'];
    if (last is! Timestamp) return false;
    if (group['lastMessageSenderId'] == uid) return false;
    final read = (group['lastRead'] as Map?)?[uid];
    return read is! Timestamp || read.compareTo(last) < 0;
  }

  /// Whether any of [uid]'s groups is unread, for the Chats badges.
  static Stream<bool> anyUnread(String uid) => myGroups(uid)
      .map((s) => s.docs.any((d) => isUnread(d.data(), uid)))
      .handleError((Object e) => debugPrint('[GroupChat] unread: $e'));

  static bool isMuted(Map<String, dynamic> group, String uid) =>
      (group['mutedBy'] as Map?)?[uid] == true;

  static final Map<String, GroupPerson> _people = {};

  /// Names and photos for [uids], cached for the session.
  static Future<Map<String, GroupPerson>> people(Iterable<String> uids) async {
    final missing = uids.where((u) => !_people.containsKey(u)).toSet().toList();
    for (var i = 0; i < missing.length; i += 30) {
      final chunk = missing.sublist(i, (i + 30).clamp(0, missing.length));
      try {
        final snap = await _db
            .collection('publicProfiles')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final d in snap.docs) {
          final data = d.data();
          final photo = data['photoUrl'] as String?;
          _people[d.id] = GroupPerson(
            uid: d.id,
            name: (data['name'] as String?)?.trim().isNotEmpty == true
                ? (data['name'] as String).trim()
                : 'Giggre user',
            photoUrl: photo != null && photo.isNotEmpty ? photo : null,
            isVerified: data['isVerified'] == true,
            workerRating: _average(data['ratingWorker']),
            hostRating: _average(data['ratingHost']),
          );
        }
        for (final u in chunk) {
          _people.putIfAbsent(
            u,
            () => GroupPerson(uid: u, name: 'Giggre user'),
          );
        }
      } catch (e) {
        debugPrint('[GroupChat] people: $e');
      }
    }
    return {
      for (final u in uids)
        if (_people[u] != null) u: _people[u]!,
    };
  }

  /// Everyone [uid] has an accepted one-to-one chat with (the same test as
  /// connectedPeers in groupChats.ts), sorted by name.
  /// People this user has blocked are left out (the server would refuse
  /// them anyway). Who blocked *them* isn't visible to the app, so those
  /// are only caught by the server's error.
  static Future<List<GroupPerson>> contacts(String uid) async {
    final results = await Future.wait([
      _db
          .collection('chat_rooms')
          .where('participants', arrayContains: uid)
          .get(),
      _db.collection('users').doc(uid).get(),
    ]);
    final rooms = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final me = results[1] as DocumentSnapshot<Map<String, dynamic>>;
    final blocked = ((me.data()?['blockedUsers'] as List?) ?? const [])
        .whereType<String>()
        .toSet();
    final peers = <String>{};
    for (final d in rooms.docs) {
      final room = d.data();
      final status = room['requestStatus'] as String? ?? 'accepted';
      if (status != 'accepted') continue;
      for (final p in (room['participants'] as List? ?? const [])) {
        if (p is String &&
            p != uid &&
            !blocked.contains(p) &&
            !isLiveSupportAccount(p)) {
          peers.add(p);
        }
      }
    }
    final people = await GroupChatService.people(peers);
    return people.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  // ── member writes ──────────────────────────────────────────────────────────

  static Future<void> markRead(String groupId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await groups.doc(groupId).update({
        'lastRead.$uid': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[GroupChat] markRead: $e');
    }
  }

  static Future<void> setMuted(String groupId, bool muted) async {
    final uid = _uid;
    if (uid == null) return;
    await groups.doc(groupId).update({
      'mutedBy.$uid': muted ? true : FieldValue.delete(),
    });
  }

  static Future<void> sendText(String groupId, String text, String myName) =>
      _send(groupId, {'type': 'text', 'text': text}, myName);

  static Future<void> sendImage(
    String groupId,
    File file,
    String myName,
  ) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref = FirebaseStorage.instance.ref(
      'group_attachments/$groupId/${ts}_$_uid.jpg',
    );
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();
    await _send(groupId, {
      'type': 'image',
      'text': '📷 Photo',
      'imageUrl': url,
    }, myName);
  }

  static Future<void> sendLocation(
    String groupId,
    GeoPoint location,
    String address,
    String myName,
  ) => _send(groupId, {
    'type': 'location',
    'text': '📍 $address',
    'location': location,
    'locationAddress': address,
  }, myName);

  static Future<void> _send(
    String groupId,
    Map<String, dynamic> fields,
    String myName,
  ) async {
    final uid = _uid;
    if (uid == null) throw GroupChatException('Sign in to send messages.');
    try {
      await groups.doc(groupId).collection('messages').add({
        ...fields,
        'senderId': uid,
        // The server corrects this; it's here so the bubble shows a name
        // straight away.
        'senderName': myName,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      debugPrint('[GroupChat] send: ${e.code} ${e.message}');
      throw GroupChatException(
        e.code == 'permission-denied'
            ? "You're no longer in this group."
            : "Couldn't send. Check your connection and try again.",
      );
    }
  }

  // ── callables ──────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final result = await FirebaseFunctions.instanceFor(
        region: _functionsRegion,
      ).httpsCallable(name).call<Map<String, dynamic>>(data);
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[GroupChat] $name ${e.code}: ${e.message}');
      // Server messages for these codes are written for people.
      const readable = {
        'invalid-argument',
        'permission-denied',
        'not-found',
        'failed-precondition',
        'resource-exhausted',
      };
      throw GroupChatException(
        readable.contains(e.code) && (e.message ?? '').isNotEmpty
            ? e.message!
            : 'Something went wrong. Check your connection and try again.',
      );
    } catch (e) {
      debugPrint('[GroupChat] $name: $e');
      throw GroupChatException(
        'Something went wrong. Check your connection and try again.',
      );
    }
  }

  static Future<String> create(String name, List<String> memberUids) async {
    final r = await _call('createGroup', {
      'name': name,
      'memberUids': memberUids,
    });
    return r['groupId'] as String;
  }

  static Future<void> addMembers(String groupId, List<String> uids) =>
      _call('addGroupMembers', {'groupId': groupId, 'memberUids': uids});

  static Future<void> removeMember(String groupId, String uid) =>
      _call('removeGroupMember', {'groupId': groupId, 'memberUid': uid});

  static Future<void> makeAdmin(String groupId, String uid) =>
      _call('makeGroupAdmin', {'groupId': groupId, 'memberUid': uid});

  static Future<void> leave(String groupId) =>
      _call('leaveGroup', {'groupId': groupId});

  static Future<void> rename(String groupId, String name) =>
      _call('updateGroup', {'groupId': groupId, 'name': name});

  static Future<void> setPhoto(String groupId, File file) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref = FirebaseStorage.instance.ref('group_photos/$groupId/$ts.jpg');
    try {
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    } on FirebaseException catch (e) {
      debugPrint('[GroupChat] photo upload: ${e.code}');
      throw GroupChatException("Couldn't upload that photo. Try again.");
    }
    await _call('updateGroup', {
      'groupId': groupId,
      'photoUrl': await ref.getDownloadURL(),
    });
  }

  static Future<void> removePhoto(String groupId) =>
      _call('updateGroup', {'groupId': groupId, 'photoUrl': null});
}
