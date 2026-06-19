import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../utils/notification_web_stub.dart'
    if (dart.library.html) '../utils/notification_web_impl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:giggre_app/features/call/incoming_call_screen.dart';
import 'package:giggre_app/features/call/incoming_video_call_screen.dart';
import 'package:giggre_app/screens/chat/chat.dart';

class CurrentUserProvider extends ChangeNotifier {
  String? _currentEmail;
  String? _currentName;
  String? _uid;
  String? _userId;
  String? _isVerified;
  StreamSubscription? _ticketSubscription;
  StreamSubscription? _callSubscription;
  StreamSubscription? _chatRoomsSubscription;
  final Map<String, StreamSubscription> _chatMessageSubs = {};

  final _audioPlayer = AudioPlayer(); // ← new

  static final _notifications = FlutterLocalNotificationsPlugin();
  static bool _notificationsInitialized = false;

  static GlobalKey<NavigatorState>? navigatorKey;

  String? get currentEmail => _currentEmail;
  String? get currentName => _currentName;
  String? get uid => _uid;
  String? get userId => _userId;
  String? get isVerified => _isVerified;
  bool get isLoggedIn => _uid != null;

  static Future<void> initNotifications() async {
    if (_notificationsInitialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();

    _notificationsInitialized = true;
  }

  static void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final roomId = data['roomId'] as String? ?? '';
      final gigId = data['gigId'] as String? ?? '';
      final peerUid = data['peerUid'] as String? ?? '';
      final peerName = data['peerName'] as String? ?? 'Chat';
      if (roomId.isEmpty) return;
      final context = navigatorKey?.currentContext;
      if (context == null) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Chat(
            roomId: roomId,
            isGigChat: true,
            gigChatParams: GigChatParams(
              gigId: gigId,
              peerUid: peerUid,
              peerName: peerName,
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('[CurrentUserProvider] notification tap error: $e');
    }
  }

  void setCurrentUserInfo(
    String? email,
    String? name,
    String? uid,
    String? userId,
    String? isVerified,
  ) {
    _currentEmail = email;
    _currentName = name;
    _uid = uid;
    _userId = userId;
    _isVerified = isVerified;
    notifyListeners();
    _listenToTicketUpdates(uid);
    _listenToIncomingCall(uid);
    _listenToGigChatMessages(uid);
  }

  void clearUser() {
    _currentEmail = null;
    _currentName = null;
    _uid = null;
    _ticketSubscription?.cancel();
    _ticketSubscription = null;
    _callSubscription?.cancel();
    _callSubscription = null;
    _chatRoomsSubscription?.cancel();
    _chatRoomsSubscription = null;
    for (final sub in _chatMessageSubs.values) {
      sub.cancel();
    }
    _chatMessageSubs.clear();
    _stopRingtone();
    _audioPlayer.dispose(); // ← clean up
    notifyListeners();
  }

  // ── Ringtone ──────────────────────────────────────────────────────────────

  Future<void> _startRingtone() async {
    debugPrint('🔊 starting ringtone');
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('sounds/incoming_call_sound.mp3'));
    debugPrint('🔊 play result');
  }

  Future<void> _stopRingtone() async {
    await _audioPlayer.stop();
  }

  // ── Incoming call listener ────────────────────────────────────────────────

  void _listenToIncomingCall(String? uid) {
    if (uid == null) return;
    _callSubscription?.cancel();

    _callSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
          debugPrint('🔔 user doc snapshot received');
          if (!snap.exists) return;
          final data = snap.data();
          if (data == null) return;

          final incomingCall = data['incomingCall'];
          debugPrint('📞 incomingCall: $incomingCall');

          // Stop ringtone if call is gone or no longer ringing
          if (incomingCall == null || incomingCall['status'] != 'ringing') {
            _stopRingtone();
            return;
          }

          final context = navigatorKey?.currentContext;
          debugPrint('🧭 navigatorKey context: $context');
          if (context == null) return;

          // Start ringtone
          _startRingtone();

          final isVideo = incomingCall['isVideo'] == true;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => isVideo
                    ? IncomingVideoCallScreen(
                        callerId: incomingCall['callerId'] ?? '',
                        callerName: incomingCall['callerName'] ?? 'Unknown',
                        channelName: incomingCall['channelName'] ?? '',
                        token: incomingCall['token'] ?? '',
                      )
                    : IncomingCallScreen(
                        callerId: incomingCall['callerId'] ?? '',
                        callerName: incomingCall['callerName'] ?? 'Unknown',
                        channelName: incomingCall['channelName'] ?? '',
                        token: incomingCall['token'] ?? '',
                      ),
              ),
            ).then((_) => _stopRingtone());
          });
        });
  }

  // ── Ticket listener ───────────────────────────────────────────────────────

  void _listenToTicketUpdates(String? uid) {
    if (uid == null) return;
    _ticketSubscription?.cancel();

    // Wait for a valid Firebase Auth token before opening the Firestore stream,
    // so request.auth is never null when the rules are evaluated.
    FirebaseAuth.instance.idTokenChanges().first.then((user) {
      if (user == null || user.uid != uid) return;

      _ticketSubscription = FirebaseFirestore.instance
          .collection('support_tickets')
          .where('userId', isEqualTo: uid)
          .snapshots()
          .listen(
            (snapshot) {
              for (final change in snapshot.docChanges) {
                if (change.type == DocumentChangeType.modified) {
                  final data = change.doc.data()!;
                  final status = data['status'] as String;
                  final subject = data['subject'] as String;
                  _showNotification(subject, status);
                }
              }
            },
            onError: (e) {
              // Swallow permission errors (e.g. during sign-out race).
              debugPrint('[CurrentUserProvider] ticket stream error: $e');
            },
          );
    });
    _ticketSubscription = FirebaseFirestore.instance
        .collection('support_tickets')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((snapshot) {
          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.modified) {
              final data = change.doc.data()!;
              final status = data['status'] as String;
              final subject = data['subject'] as String;
              _showNotification(subject, status);
            }
          }
        });
  }

  // ── GigChat message listener ──────────────────────────────────────────────

  void _listenToGigChatMessages(String? uid) {
    if (uid == null) return;
    _chatRoomsSubscription?.cancel();
    for (final sub in _chatMessageSubs.values) {
      sub.cancel();
    }
    _chatMessageSubs.clear();

    _chatRoomsSubscription = FirebaseFirestore.instance
        .collection('chat_rooms')
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen(
          (roomsSnap) {
            // Remove subs for rooms that no longer exist.
            final liveIds = roomsSnap.docs.map((d) => d.id).toSet();
            final gone =
                _chatMessageSubs.keys.where((id) => !liveIds.contains(id)).toList();
            for (final id in gone) {
              _chatMessageSubs[id]?.cancel();
              _chatMessageSubs.remove(id);
            }

            // Add subs only for rooms not yet subscribed — never cancel existing ones.
            // This prevents the rooms snapshot (triggered by lastMessage updates)
            // from resetting the initialLoad flag and swallowing incoming messages.
            for (final room in roomsSnap.docs) {
              if (_chatMessageSubs.containsKey(room.id)) continue;

              final data = room.data();
              final participants =
                  (data['participants'] as List<dynamic>?) ?? [];
              final peerUid = participants.firstWhere(
                (p) => p != uid,
                orElse: () => '',
              ) as String;

              if (peerUid.isEmpty) continue;

              final gigId = data['gigId'] as String? ?? '';
              final createdByUid = data['createdByUid'] as String? ?? '';
              final createdByName = data['createdByName'] as String? ?? '';
              final sendTo = data['sendTo'] as String? ?? 'Someone';
              final peerName =
                  (createdByUid.isNotEmpty && uid != createdByUid)
                      ? (createdByName.isNotEmpty ? createdByName : sendTo)
                      : sendTo;

              bool initialLoad = true;

              final sub = FirebaseFirestore.instance
                  .collection('chat_rooms')
                  .doc(room.id)
                  .collection('messages')
                  .where('senderId', isEqualTo: peerUid)
                  .where('hasSeen', isEqualTo: false)
                  .snapshots()
                  .listen(
                    (msgSnap) {
                      if (initialLoad) {
                        initialLoad = false;
                        return;
                      }
                      for (final change in msgSnap.docChanges) {
                        if (change.type == DocumentChangeType.added) {
                          final text =
                              change.doc.data()?['text'] as String? ??
                              'New message';
                          _showChatNotification(
                            peerName,
                            text,
                            room.id,
                            gigId,
                            peerUid,
                          );
                        }
                      }
                    },
                    onError: (e) => debugPrint(
                        '[CurrentUserProvider] chat msg error: $e'),
                  );
              _chatMessageSubs[room.id] = sub;
            }
          },
          onError: (e) =>
              debugPrint('[CurrentUserProvider] chat rooms error: $e'),
        );
  }

  Future<void> _showChatNotification(
    String peerName,
    String message,
    String roomId,
    String gigId,
    String peerUid,
  ) async {
    final payload = jsonEncode({
      'roomId': roomId,
      'gigId': gigId,
      'peerUid': peerUid,
      'peerName': peerName,
    });
    await Future.wait([
      _notifications.show(
        roomId.hashCode.abs() % 100000,
        peerName,
        message,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'gig_chat',
            'Gig Chat',
            icon: 'ic_chat_notification',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: payload,
      ),
      showBrowserNotification(peerName, message, '/icons/Icon-192.png'),
    ]);
  }

  Future<void> _showNotification(String subject, String status) async {
    await _notifications.show(
      0,
      'Ticket Updated',
      'Your ticket "$subject" is now $status',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'ticket_updates',
          'Ticket Updates',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> showGigAssignedNotification(
      String gigType, String gigTitle) async {
    final label = gigType == 'quick'
        ? 'Quick Gig'
        : gigType == 'offered'
            ? 'Offered Gig'
            : 'Open Gig';
    await _notifications.show(
      1,
      'You\'re Assigned! — $label',
      'You\'ve been assigned to: $gigTitle. Head to the location now.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'gig_assignments',
          'Gig Assignments',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
