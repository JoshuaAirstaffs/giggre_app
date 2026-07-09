import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:giggre_app/features/call/incoming_call_screen.dart';
import 'package:giggre_app/features/call/incoming_video_call_screen.dart';
import 'package:giggre_app/features/gig_host/presentation/widgets/gig_detail_sheet.dart';
import 'package:giggre_app/screens/chat/chat.dart';
import '../services/currency_service.dart';
import '../services/push_notification_service.dart';

class CurrentUserProvider extends ChangeNotifier {
  String? _currentEmail;
  String? _currentName;
  String? _uid;
  String? _userId;
  String? _isVerified;
  StreamSubscription? _callSubscription;

  final _audioPlayer = AudioPlayer(); // ← new

  static final _notifications = FlutterLocalNotificationsPlugin();
  static bool _notificationsInitialized = false;
  static final _pushService = PushNotificationService(
    _notifications,
    _handleNotificationData,
  );

  static GlobalKey<NavigatorState>? navigatorKey;

  String _currencyCode = 'PHP';
  bool _currencyInitialized = false;

  String? get currentEmail => _currentEmail;
  String? get currentName => _currentName;
  String? get uid => _uid;
  String? get userId => _userId;
  String? get isVerified => _isVerified;
  bool get isLoggedIn => _uid != null;
  String get currencyCode => _currencyCode;

  // Called once per session after setCurrentUserInfo. Reads the stored
  // currencyCode from the user doc; if absent, detects it via GPS and persists
  // it to Firestore. No-op on subsequent calls within the same session.
  Future<void> initCurrencyCode(
      String uid, Map<String, dynamic> userDoc) async {
    if (_currencyInitialized) return;
    _currencyInitialized = true;
    final code = await CurrencyService.initForUser(uid, userDoc);
    _currencyCode = code;
    notifyListeners();
  }

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

    // Explicitly create channels so importance is set correctly on first install.
    // Android locks channel importance/sound after first creation — explicit
    // creation here guarantees correct settings before any notification is shown.
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'gig_chat',
        'Gig Chat',
        description: 'Notifications for new chat messages',
        importance: Importance.max,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'gig_assignments',
        'Gig Assignments',
        description: 'Notifications for gig assignments',
        importance: Importance.max,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'ticket_updates',
        'Ticket Updates',
        description: 'Notifications for support ticket updates',
        importance: Importance.high,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'gig_applications_v3',
        'Gig Applications',
        description: 'Notifications when a worker applies to your gig',
        importance: Importance.max,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'gig_offers_v2',
        'Gig Offers',
        description: 'Notifications when a host offers you a gig directly',
        importance: Importance.max,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'gig_auto_cancelled_v2',
        'Gig Auto-Cancelled',
        description:
            'Notifications when a gig is auto-cancelled because its scheduled time passed with no worker selected',
        importance: Importance.max,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'gig_worker_progress_v2',
        'Worker Progress',
        description:
            'Notifications when your worker arrives, starts, or completes a gig',
        importance: Importance.max,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'nearby_gigs',
        'Nearby Gigs',
        description: 'Notifications when a new gig is posted within 10km of you',
        importance: Importance.max,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'tester_reminder',
        'Testing Reminder',
        description: 'Daily reminder for closed-testing testers (dev builds only)',
        importance: Importance.high,
      ),
    );

    // Foreground display + background/terminated tap handling for FCM push.
    _pushService.listen();

    _notificationsInitialized = true;
  }

  static void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      _handleNotificationData(data);
    } catch (e) {
      debugPrint('[CurrentUserProvider] notification tap error: $e');
    }
  }

  static void _handleNotificationData(Map<String, dynamic> data) {
    final context = navigatorKey?.currentContext;
    if (context == null) return;

    if (data['type'] == 'new_applicant') {
      final gigId = data['gigId'] as String? ?? '';
      if (gigId.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => GigDetailSheet(gigId: gigId, gigType: 'open'),
        );
      });
      return;
    }

    if (data['type'] == 'gig_offered' ||
        data['type'] == 'gig_assigned' ||
        data['type'] == 'gig_auto_cancelled' ||
        data['type'] == 'worker_progress' ||
        data['type'] == 'ticket_updated' ||
        data['type'] == 'tester_reminder' ||
        data['type'] == 'new_version' ||
        data['type'] == 'nearby_gig') {
      // Tapping just brings the app to the foreground — the relevant screen's
      // own Firestore listener surfaces the change.
      return;
    }

    final roomId = data['roomId'] as String? ?? '';
    final gigId = data['gigId'] as String? ?? '';
    final peerUid = data['peerUid'] as String? ?? '';
    final peerName = data['peerName'] as String? ?? 'Chat';
    if (roomId.isEmpty) return;
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
    _listenToIncomingCall(uid);
    if (uid != null) {
      _pushService.registerForUser(uid);
    }
  }

  // For sign-out paths that run before setCurrentUserInfo ever populated this
  // provider (e.g. the pendingDeletion/restoreError screens in main.dart) —
  // clearUser() can't help there since _uid is still null, so those call
  // sites pass FirebaseAuth's uid directly instead.
  static Future<void> unregisterPushForUid(String uid) =>
      _pushService.unregisterForUser(uid);

  void clearUser() {
    final previousUid = _uid;
    _currentEmail = null;
    _currentName = null;
    _uid = null;
    _currencyCode = 'PHP';
    _currencyInitialized = false;
    _callSubscription?.cancel();
    _callSubscription = null;
    _stopRingtone();
    _audioPlayer.dispose(); // ← clean up
    if (previousUid != null) {
      _pushService.unregisterForUser(previousUid);
    }
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
}
