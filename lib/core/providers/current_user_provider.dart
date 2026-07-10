import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:giggre_app/features/call/incoming_call_screen.dart';
import 'package:giggre_app/features/call/incoming_video_call_screen.dart';
import 'package:giggre_app/features/gig_host/presentation/widgets/gig_detail_sheet.dart';
import 'package:giggre_app/features/gig_worker/presentation/verification_screen.dart';
import 'package:giggre_app/features/gig_worker/presentation/widgets/toolchest_sheet.dart';
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

    // Explicitly create channels so importance/sound are set correctly on
    // first install. Android locks these after first creation — every
    // channel below carries a version suffix bumped alongside this change so
    // existing installs pick up the custom gig_sound.mp3 too, not just fresh
    // ones. The file backing this must exist as a raw resource at
    // android/app/src/main/res/raw/gig_sound.mp3, not just the Flutter asset.
    const gigSound = RawResourceAndroidNotificationSound('gig_sound');
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'gig_chat_v2',
        'Gig Chat',
        description: 'Notifications for new chat messages',
        importance: Importance.max,
        sound: gigSound,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'gig_assignments_v2',
        'Gig Assignments',
        description: 'Notifications for gig assignments',
        importance: Importance.max,
        sound: gigSound,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'ticket_updates_v2',
        'Ticket Updates',
        description: 'Notifications for support ticket updates',
        importance: Importance.high,
        sound: gigSound,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'gig_applications_v4',
        'Gig Applications',
        description: 'Notifications when a worker applies to your gig',
        importance: Importance.max,
        sound: gigSound,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'gig_offers_v3',
        'Gig Offers',
        description: 'Notifications when a host offers you a gig directly',
        importance: Importance.max,
        sound: gigSound,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'gig_auto_cancelled_v3',
        'Gig Auto-Cancelled',
        description:
            'Notifications when a gig is auto-cancelled because its scheduled time passed with no worker selected',
        importance: Importance.max,
        sound: gigSound,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'gig_worker_progress_v3',
        'Worker Progress',
        description:
            'Notifications when your worker arrives, starts, or completes a gig',
        importance: Importance.max,
        sound: gigSound,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'nearby_gigs_v2',
        'Nearby Gigs',
        description: 'Notifications when a new gig is posted within 10km of you',
        importance: Importance.max,
        sound: gigSound,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'verification_status_v1',
        'Verification Status',
        description: 'Notifications when an admin approves or rejects your verification',
        importance: Importance.max,
        sound: gigSound,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'skill_request_status_v1',
        'Skill Request Status',
        description: 'Notifications when an admin approves or rejects a skill request',
        importance: Importance.max,
        sound: gigSound,
      ),
    );
    // Distinct from gigSound — used only for the two tester-facing
    // broadcasts (daily 7am reminder + new-build announcement), not any
    // real gig event. Requires android/app/src/main/res/raw/test_sound.mp3.
    const testSound = RawResourceAndroidNotificationSound('test_sound');
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'tester_reminder_v3',
        'Testing Reminder',
        description: 'Daily reminder for closed-testing testers (dev builds only)',
        importance: Importance.high,
        sound: testSound,
      ),
    );

    // Every ID this app has ever created under a previous name, now
    // superseded — Android never deletes channels on its own, so without
    // this they pile up in system Settings as visually-identical duplicates
    // (same display name, different backing ID) each time a channel gets
    // renamed to fix its importance/sound/etc.
    const staleChannelIds = [
      'gig_chat',
      'gig_assignments',
      'ticket_updates',
      'gig_applications_v2',
      'gig_applications_v3',
      'gig_offers',
      'gig_offers_v2',
      'gig_auto_cancelled',
      'gig_auto_cancelled_v2',
      'gig_worker_progress',
      'gig_worker_progress_v2',
      'nearby_gigs',
      'tester_reminder',
      'tester_reminder_v2',
    ];
    for (final id in staleChannelIds) {
      await androidPlugin?.deleteNotificationChannel(id);
    }

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

    if (data['type'] == 'verification_status') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VerificationScreen()),
        );
      });
      return;
    }

    if (data['type'] == 'skill_request_status') {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ToolchestSheet.show(context, uid);
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
