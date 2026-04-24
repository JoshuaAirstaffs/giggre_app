import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:giggre_app/features/call/incoming_call_screen.dart';
import 'package:giggre_app/features/call/incoming_video_call_screen.dart';

class CurrentUserProvider extends ChangeNotifier {
  String? _currentEmail;
  String? _currentName;
  String? _uid;
  String? _userId;
  StreamSubscription? _ticketSubscription;
  StreamSubscription? _callSubscription;

  final _audioPlayer = AudioPlayer(); // ← new

  static final _notifications = FlutterLocalNotificationsPlugin();
  static bool _notificationsInitialized = false;

  static GlobalKey<NavigatorState>? navigatorKey;

  String? get currentEmail => _currentEmail;
  String? get currentName => _currentName;
  String? get uid => _uid;
  String? get userId => _userId;
  bool get isLoggedIn => _uid != null;

  static Future<void> initNotifications() async {
    if (_notificationsInitialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _notifications.initialize(settings);

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    _notificationsInitialized = true;
  }

  void setCurrentUserInfo(String? email, String? name, String? uid, String? userId) {
    _currentEmail = email;
    _currentName = name;
    _uid = uid;
    _userId = userId;
    notifyListeners();
    _listenToTicketUpdates(uid);
    _listenToIncomingCall(uid);
  }

  void clearUser() {
    _currentEmail = null;
    _currentName = null;
    _uid = null;
    _ticketSubscription?.cancel();
    _ticketSubscription = null;
    _callSubscription?.cancel();
    _callSubscription = null;
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
                  final data    = change.doc.data()!;
                  final status  = data['status'] as String;
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
}