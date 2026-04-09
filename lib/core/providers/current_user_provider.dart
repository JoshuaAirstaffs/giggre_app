import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class CurrentUserProvider extends ChangeNotifier {
  String? _currentEmail;
  String? _currentName;
  String? _uid;
  StreamSubscription? _ticketSubscription;

  static final _notifications = FlutterLocalNotificationsPlugin();
  static bool _notificationsInitialized = false;

  String? get currentEmail => _currentEmail;
  String? get currentName => _currentName;
  String? get uid => _uid;
  bool get isLoggedIn => _uid != null;

static Future<void> initNotifications() async {
  if (_notificationsInitialized) return;
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  await _notifications.initialize(settings);

  // Request permission for Android 13+
  final androidPlugin = _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.requestNotificationsPermission();

  _notificationsInitialized = true;
}

  void setCurrentUserInfo(String? email, String? name, String? uid) {
    _currentEmail = email;
    _currentName = name;
    _uid = uid;
    notifyListeners();
    _listenToTicketUpdates(uid);
  }

  void clearUser() {
    _currentEmail = null;
    _currentName = null;
    _uid = null;
    _ticketSubscription?.cancel();
    _ticketSubscription = null;
    notifyListeners();
  }

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