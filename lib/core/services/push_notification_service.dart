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

  final FlutterLocalNotificationsPlugin _notifications;
  final void Function(Map<String, dynamic> data) _onTap;

  String? _registeredToken;
  String? _registeredUid;

  Future<void> registerForUser(String uid) async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    final token = await messaging.getToken();
    if (token != null) {
      await _saveToken(uid, token);
    }
    _registeredUid = uid;
    _registeredToken = token;

    messaging.onTokenRefresh.listen((newToken) async {
      final currentUid = _registeredUid;
      if (currentUid == null) return;
      await _saveToken(currentUid, newToken);
      _registeredToken = newToken;
    });
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
    final token = _registeredToken ?? await FirebaseMessaging.instance.getToken();
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
    final notification = message.notification;
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
