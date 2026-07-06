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
import 'package:giggre_app/features/gig_host/presentation/widgets/gig_detail_sheet.dart';
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
  StreamSubscription? _supportRoomsSubscription;
  StreamSubscription? _applicationsNotifSub;
  StreamSubscription? _gigOffersNotifSub;
  final Map<String, StreamSubscription> _chatMessageSubs = {};
  final Set<String> _supportRoomIds = {};
  Timestamp? _chatListenStart;

  final _audioPlayer = AudioPlayer(); // ← new
  final _appNotifPlayer = AudioPlayer();

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

    // Explicitly create channels so importance is set correctly on first install.
    // Android locks channel importance after first creation — explicit creation
    // here guarantees HIGH importance before any notification is shown.
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
        'gig_applications_v2',
        'Gig Applications',
        description: 'Notifications when a worker applies to your gig',
        importance: Importance.max,
        // Sound is played manually via gig_sound.mp3 in
        // _showApplicationNotification, so the channel itself stays silent.
        playSound: false,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'gig_offers',
        'Gig Offers',
        description: 'Notifications when a host offers you a gig directly',
        importance: Importance.max,
        // Sound is played manually via gig_sound.mp3 in
        // _showGigOfferNotification, so the channel itself stays silent.
        playSound: false,
      ),
    );

    _notificationsInitialized = true;
  }

  static void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
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

      if (data['type'] == 'gig_offered') {
        // Tapping just brings the app to the foreground — the gig worker
        // screen's own Firestore listener surfaces the pending offer card.
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
    _listenToGigApplications(uid);
    _listenToGigOffers(uid);
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
    _supportRoomsSubscription?.cancel();
    _supportRoomsSubscription = null;
    for (final sub in _chatMessageSubs.values) {
      sub.cancel();
    }
    _chatMessageSubs.clear();
    _supportRoomIds.clear();
    _chatListenStart = null;
    _applicationsNotifSub?.cancel();
    _applicationsNotifSub = null;
    _gigOffersNotifSub?.cancel();
    _gigOffersNotifSub = null;
    _stopRingtone();
    _audioPlayer.dispose(); // ← clean up
    _appNotifPlayer.dispose();
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

    // Keep the original login timestamp so repeated setCurrentUserInfo calls
    // (home screen reload) don't reset the cutoff and miss in-flight messages.
    _chatListenStart ??= Timestamp.now();
    final listenStart = _chatListenStart!;

    _chatRoomsSubscription?.cancel();
    _supportRoomsSubscription?.cancel();
    for (final sub in _chatMessageSubs.values) sub.cancel();
    _chatMessageSubs.clear();
    _supportRoomIds.clear();

    debugPrint('[ChatNotif] listener started for uid=$uid, cutoff=${listenStart.toDate()}');

    void subscribeRoom(QueryDocumentSnapshot<Map<String, dynamic>> room) {
      if (_chatMessageSubs.containsKey(room.id)) return;

      final data = room.data();
      final participants = (data['participants'] as List<dynamic>?) ?? [];
      final isSupport = data['isSupport'] as bool? ?? false;

      // For rooms without participants (e.g. old support rooms), fall back to
      // 'support' as the peer so auto-reply messages still trigger notifications.
      final peerUid = participants.isNotEmpty
          ? participants.firstWhere(
                (p) => p != uid,
                orElse: () => isSupport ? 'support' : '',
              ) as String
          : isSupport
              ? 'support'
              : '';

      debugPrint('[ChatNotif] room ${room.id}: participants=$participants, peerUid=$peerUid, isSupport=$isSupport');

      if (peerUid.isEmpty) {
        debugPrint('[ChatNotif] skipping room ${room.id}: peerUid is empty');
        return;
      }

      final gigId = data['gigId'] as String? ?? '';
      final createdByUid = data['createdByUid'] as String? ?? '';
      final createdByName = data['createdByName'] as String? ?? '';
      final sendTo = data['sendTo'] as String? ?? 'Someone';
      final peerName = (createdByUid.isNotEmpty && uid != createdByUid)
          ? (createdByName.isNotEmpty ? createdByName : sendTo)
          : sendTo;

      debugPrint('[ChatNotif] subscribing to messages in room ${room.id}, peerName=$peerName');

      final sub = FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(room.id)
          .collection('messages')
          .orderBy('createdAt')
          .startAfter([listenStart])
          .snapshots()
          .listen(
            (msgSnap) {
              debugPrint('[ChatNotif] room ${room.id}: ${msgSnap.docChanges.length} changes');
              for (final change in msgSnap.docChanges) {
                if (change.type != DocumentChangeType.added) continue;
                final msgData = change.doc.data() ?? {};
                final senderId = msgData['senderId'];
                final hasSeen = msgData['hasSeen'] as bool? ?? false;
                debugPrint('[ChatNotif] new msg: senderId=$senderId, peerUid=$peerUid, hasSeen=$hasSeen');
                if (senderId != peerUid) {
                  debugPrint('[ChatNotif] skipped: senderId != peerUid');
                  continue;
                }
                if (hasSeen) {
                  debugPrint('[ChatNotif] skipped: hasSeen=true');
                  continue;
                }
                final text = msgData['text'] as String? ?? 'New message';
                debugPrint('[ChatNotif] firing notification from $peerName: "$text"');
                _showChatNotification(peerName, text, room.id, gigId, peerUid);
              }
            },
            onError: (e) =>
                debugPrint('[ChatNotif] msg stream error in ${room.id}: $e'),
          );
      _chatMessageSubs[room.id] = sub;
    }

    _chatRoomsSubscription = FirebaseFirestore.instance
        .collection('chat_rooms')
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen(
          (roomsSnap) {
            debugPrint('[ChatNotif] rooms snapshot: ${roomsSnap.docs.length} rooms');
            // Remove subs for rooms that disappeared, but keep support-room subs.
            final liveIds = roomsSnap.docs.map((d) => d.id).toSet();
            final gone = _chatMessageSubs.keys
                .where((id) => !liveIds.contains(id) && !_supportRoomIds.contains(id))
                .toList();
            for (final id in gone) {
              _chatMessageSubs[id]?.cancel();
              _chatMessageSubs.remove(id);
            }
            for (final room in roomsSnap.docs) {
              subscribeRoom(room);
            }
          },
          onError: (e) =>
              debugPrint('[ChatNotif] rooms stream error: $e'),
        );

    // Second listener: catches support rooms that don't have a participants field
    // (e.g. rooms created before the field was added, or via contact_us flow).
    _supportRoomsSubscription = FirebaseFirestore.instance
        .collection('chat_rooms')
        .where('userId', isEqualTo: uid)
        .where('isSupport', isEqualTo: true)
        .snapshots()
        .listen(
          (roomsSnap) {
            debugPrint('[ChatNotif] support rooms snapshot: ${roomsSnap.docs.length} rooms');
            for (final room in roomsSnap.docs) {
              _supportRoomIds.add(room.id);
              subscribeRoom(room);
            }
          },
          onError: (e) =>
              debugPrint('[ChatNotif] support rooms stream error: $e'),
        );
  }

  Future<void> _showChatNotification(
    String peerName,
    String message,
    String roomId,
    String gigId,
    String peerUid,
  ) async {
    try {
      final payload = jsonEncode({
        'roomId': roomId,
        'gigId': gigId,
        'peerUid': peerUid,
        'peerName': peerName,
      });
      debugPrint('[ChatNotif] calling _notifications.show id=${roomId.hashCode.abs() % 100000}');
      await Future.wait([
        _notifications.show(
          roomId.hashCode.abs() % 100000,
          peerName,
          message,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'gig_chat',
              'Gig Chat',
              importance: Importance.max,
              priority: Priority.max,
              playSound: true,
            ),
            iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
          ),
          payload: payload,
        ),
        showBrowserNotification(peerName, message, '/icons/Icon-192.png'),
      ]);
      debugPrint('[ChatNotif] notification shown successfully');
    } catch (e, st) {
      debugPrint('[ChatNotif] notification error: $e\n$st');
    }
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

  // ── Gig-application listener (host side) ─────────────────────────────────

  void _listenToGigApplications(String? uid) {
    if (uid == null) return;
    _applicationsNotifSub?.cancel();

    final listenStart = Timestamp.now();

    _applicationsNotifSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen(
          (snap) {
            for (final change in snap.docChanges) {
              if (change.type != DocumentChangeType.added) continue;
              final data = change.doc.data() ?? {};
              if (data['category'] != 'new_applicant') continue;
              final createdAt = data['createdAt'];
              if (createdAt is Timestamp && createdAt.compareTo(listenStart) <= 0) continue;
              final workerName = data['workerName'] as String? ?? 'Someone';
              final gigTitle = data['gigTitle'] as String? ?? 'your gig';
              final gigId = data['gigId'] as String? ?? '';
              _showApplicationNotification(workerName, gigTitle, gigId);
            }
          },
          onError: (e) =>
              debugPrint('[AppNotif] stream error: $e'),
        );
  }

  Future<void> _showApplicationNotification(
      String workerName, String gigTitle, String gigId) async {
    final payload = jsonEncode({
      'type': 'new_applicant',
      'gigId': gigId,
    });
    await Future.wait([
      _notifications.show(
        ('$workerName$gigTitle').hashCode.abs() % 100000,
        'New Application',
        'A worker applied to your gig — $workerName wants "$gigTitle"',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'gig_applications_v2',
            'Gig Applications',
            importance: Importance.max,
            priority: Priority.high,
            playSound: false,
          ),
          iOS: DarwinNotificationDetails(presentAlert: true, presentSound: false),
        ),
        payload: payload,
      ),
      _appNotifPlayer.play(AssetSource('sounds/gig_sound.mp3')),
    ]);
  }

  // ── Gig-offer listener (worker side) ──────────────────────────────────────

  void _listenToGigOffers(String? uid) {
    if (uid == null) return;
    _gigOffersNotifSub?.cancel();

    final listenStart = Timestamp.now();

    _gigOffersNotifSub = FirebaseFirestore.instance
        .collection('offered_gigs')
        .where('workerId', isEqualTo: uid)
        .where('status', isEqualTo: 'offered')
        .snapshots()
        .listen(
          (snap) {
            for (final change in snap.docChanges) {
              if (change.type != DocumentChangeType.added) continue;
              final data = change.doc.data() ?? {};
              final createdAt = data['createdAt'];
              if (createdAt is Timestamp && createdAt.compareTo(listenStart) <= 0) continue;
              final hostName = data['hostName'] as String? ?? 'A host';
              final gigTitle = data['title'] as String? ?? 'a gig';
              _showGigOfferNotification(hostName, gigTitle, change.doc.id);
            }
          },
          onError: (e) =>
              debugPrint('[GigOfferNotif] stream error: $e'),
        );
  }

  Future<void> _showGigOfferNotification(
      String hostName, String gigTitle, String gigId) async {
    final payload = jsonEncode({
      'type': 'gig_offered',
      'gigId': gigId,
    });
    await Future.wait([
      _notifications.show(
        ('$hostName$gigTitle').hashCode.abs() % 100000,
        'New Gig Offer',
        '$hostName offered you a gig — "$gigTitle"',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'gig_offers',
            'Gig Offers',
            importance: Importance.max,
            priority: Priority.high,
            playSound: false,
          ),
          iOS: DarwinNotificationDetails(presentAlert: true, presentSound: false),
        ),
        payload: payload,
      ),
      _appNotifPlayer.play(AssetSource('sounds/gig_sound.mp3')),
    ]);
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
