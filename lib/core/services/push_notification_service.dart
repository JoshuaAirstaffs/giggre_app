import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Registers this device for FCM push (so notifications keep arriving while
/// the app is backgrounded or fully closed) and renders/dispatches them.
///
/// - Foreground: FCM delivers a [RemoteMessage] with no system UI, so we show
///   it ourselves via [flutterLocalNotifications].
/// - Background/terminated: the OS shows the notification from the FCM
///   payload directly; tapping it is surfaced via [onMessageOpenedApp] /
///   [getInitialMessage].
class PushNotificationService {
  PushNotificationService(this._notifications, this._onTap);

  // Fixed (not per-message-hash) so CurrentUserProvider's incoming-call
  // Firestore listener can cancel this exact notification once the call is
  // no longer ringing (declined/answered elsewhere/timed out/caller hung up).
  static const incomingCallNotificationId = 999999;

  // Fallback only — the real value normally arrives via the push's own
  // `data['channelId']` (see sendIncomingCallPush), kept in sync manually
  // with the channel CurrentUserProvider.initNotifications() creates.
  static const incomingCallChannelId = 'incoming_call_v2';

  final FlutterLocalNotificationsPlugin _notifications;
  final void Function(Map<String, dynamic> data) _onTap;

  String? _registeredToken;
  String? _registeredUid;

  Future<void> registerForUser(String uid) async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // TEMP DEBUG — remove once the push notification investigation is done.
    // Writes to Firestore (not just debugPrint) so this is checkable via the
    // Firebase Console on a TestFlight install, where there's no attached
    // console to read logs from.
    {
      String? apnsToken;
      String? fcmToken;
      String? debugError;
      try {
        apnsToken = await messaging.getAPNSToken();
        debugPrint('🍎 APNs TOKEN: $apnsToken');
      } catch (e) {
        debugError = 'apns: $e';
        debugPrint('🍎 APNs token check failed: $e');
      }
      try {
        fcmToken = await messaging.getToken();
        debugPrint('🔥 FCM TOKEN: $fcmToken');
      } catch (e) {
        debugError = '${debugError ?? ''} fcm: $e';
        debugPrint('🔥 FCM token check failed: $e');
      }
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'debugApnsToken': apnsToken,
          'debugFcmToken': fcmToken,
          'debugTokenError': debugError,
          'debugTokenCheckedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Failed to write debug tokens to Firestore: $e');
      }
    }

    final token = await _getTokenWithRetry(messaging);
    if (token != null) {
      debugPrint('[PushNotificationService] got FCM token on initial request');
      await _saveToken(uid, token);
    }
    _registeredUid = uid;
    _registeredToken = token;

    messaging.onTokenRefresh.listen((newToken) async {
      final currentUid = _registeredUid;
      if (currentUid == null) return;
      debugPrint('[PushNotificationService] got FCM token via onTokenRefresh');
      await _saveToken(currentUid, newToken);
      _registeredToken = newToken;
    });
  }

  // iOS registers with APNs asynchronously after requestPermission()
  // returns, so getToken() can lose that race and throw apns-token-not-set
  // on a cold start — retry before giving up (up to ~30s: a first-time APNs
  // handshake can take longer than a couple seconds). Also throws on iOS
  // Simulator (no real APNs token is ever assigned there), which exhausts
  // these retries and falls through to the null/logged-failure case below —
  // registerForUser's onTokenRefresh listener stays armed regardless, so a
  // token that arrives later still gets saved.
  Future<String?> _getTokenWithRetry(FirebaseMessaging messaging) async {
    const maxAttempts = 10;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await messaging.getToken();
      } catch (e) {
        if (attempt == maxAttempts) {
          debugPrint('[PushNotificationService] failed to get FCM token: $e');
          return null;
        }
        await Future.delayed(const Duration(seconds: 3));
      }
    }
    return null;
  }

  Future<void> _saveToken(String uid, String token) async {
    try {
      // Self-heals stale registrations left by earlier logout races (or any
      // account still holding this token from before this device was
      // reassigned) — a physical device token should only ever live on the
      // currently signed-in user's doc, otherwise every account that ever
      // logged in here keeps getting this device's pushes too.
      final stale = await FirebaseFirestore.instance
          .collection('users')
          .where('fcmTokens', arrayContains: token)
          .get();
      for (final doc in stale.docs) {
        if (doc.id == uid) continue;
        await doc.reference.update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
      });
    } catch (e) {
      debugPrint('[PushNotificationService] failed to save FCM token: $e');
    }
  }

  Future<void> unregisterForUser(String uid) async {
    // Falls back to fetching the live device token when this process never
    // registered one itself (e.g. logging out shortly after a fresh app
    // launch/restore, where _registeredToken is still null) — otherwise the
    // token silently stays attached to the outgoing user's fcmTokens array
    // and they keep receiving that account's pushes on this device.
    String? token = _registeredToken;
    if (token == null) {
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        // On iOS Simulator this always throws (no real APNs token exists),
        // which otherwise propagates up through clearUser() and aborts
        // logout before FirebaseAuth.signOut() ever runs.
        debugPrint('[PushNotificationService] failed to fetch FCM token: $e');
      }
    }
    if (token != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
      } catch (e) {
        debugPrint('[PushNotificationService] failed to remove FCM token: $e');
      }
    }
    _registeredUid = null;
    _registeredToken = null;
  }

  /// Call once at startup (after FCM channels exist) to wire up foreground
  /// display and notification-tap handling.
  void listen() {
    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _onTap(message.data),
    );
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _onTap(message.data);
    });
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final type = message.data['type'];
    // Silent — just tells us to dismiss the incoming-call notification
    // (call answered/declined/timed out/caller hung up). In the foreground
    // this is usually redundant with CurrentUserProvider's own Firestore
    // listener already cancelling it, but cancel() is a harmless no-op if
    // it's already gone, so handling it here too costs nothing.
    if (type == 'cancel_incoming_call') {
      await cancelIncomingCallNotification(_notifications);
      return;
    }

    final isIncomingCall = type == 'incoming_call';
    // The incoming-call push is Android data-only (see sendIncomingCallPush
    // in functions/src/push.ts) so message.notification is null for it —
    // title/body travel in `data` instead for this type specifically.
    if (isIncomingCall) {
      await showIncomingCallNotification(_notifications, message.data);
      return;
    }

    final notification = message.notification;
    debugPrint(
      '[PushNotificationService] received: ${notification?.title} / ${notification?.body}',
    );
    if (notification == null) return;
    final channelId = message.data['channelId'] as String? ?? 'gig_chat_v2';

    await _notifications.show(
      message.hashCode.abs() % 100000,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelId,
          importance: Importance.max,
          priority: Priority.max,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      payload: message.data.isNotEmpty ? jsonEncode(message.data) : null,
    );
  }
}

// Top-level (not a method) so both the running app's foreground handler and
// the isolated background message handler below can call it identically —
// a background isolate has no access to a PushNotificationService instance.
Future<void> showIncomingCallNotification(
  FlutterLocalNotificationsPlugin notifications,
  Map<String, dynamic> data,
) async {
  final title = data['title'] as String? ?? 'Incoming Call';
  final body = data['body'] as String? ?? 'Incoming call';
  final channelId =
      data['channelId'] as String? ??
      PushNotificationService.incomingCallChannelId;

  // Plain, swipeable, no action buttons — tapping the notification (or its
  // body text telling the user to do so) just opens the app, and the
  // already-working full-screen ring UI (its own Firestore listener) takes
  // it from there with real Answer/Decline buttons. Action buttons directly
  // on the notification were tried and dropped: tapping either one just
  // opened the app anyway without reliably running the distinct
  // accept/decline logic, so they added complexity without adding function.
  await notifications.show(
    PushNotificationService.incomingCallNotificationId,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelId,
        importance: Importance.max,
        priority: Priority.max,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        sound: 'incoming_call_sound.caf',
      ),
    ),
    payload: data.isNotEmpty ? jsonEncode(data) : null,
  );
}

/// Dismisses whatever showIncomingCallNotification put up (call
/// answered/declined/timed out/caller hung up, or the user already handled
/// it via the notification's own actions).
Future<void> cancelIncomingCallNotification(
  FlutterLocalNotificationsPlugin notifications,
) => notifications.cancel(PushNotificationService.incomingCallNotificationId);

/// Registered via FirebaseMessaging.onBackgroundMessage in main() — Android
/// invokes this in a separate, minimal background isolate (no access to the
/// running app's state) when an incoming-call push arrives while the app is
/// backgrounded or fully killed, because that push is sent data-only
/// specifically so Android doesn't auto-render a plain, action-less
/// notification instead (see sendIncomingCallPush in functions/src/push.ts).
/// Must stay a top-level function annotated exactly like this — Firebase's
/// plugin requires it to create the background isolate correctly.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final type = message.data['type'];
  if (type == 'cancel_incoming_call') {
    // A killed app has no other way to learn the call stopped ringing
    // (answered/declined/timed out/caller hung up) and dismiss the
    // notification shown below — see sendCancelIncomingCallPush's doc.
    await cancelIncomingCallNotification(FlutterLocalNotificationsPlugin());
    return;
  }
  if (type != 'incoming_call') return;
  await showIncomingCallNotification(
    FlutterLocalNotificationsPlugin(),
    message.data,
  );
}
