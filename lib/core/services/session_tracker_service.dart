import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TEMPORARY — TESTING ONLY.
// Records each closed-testing session (login → close/background) to the
// `sessions` Firestore collection: userId, email, role, startedAt, endedAt,
// durationSeconds, lastActiveAt, appVersion. Self-contained in this one file
// — the only other touch point is the single
// `SessionTrackerService.instance.start()` call in main.dart. Delete both
// when testing wraps up.
//
// Why a heartbeat: `didChangeAppLifecycleState(paused)` is not a reliable
// "app closed" signal — swiping the app away from recents (or the OS killing
// it under memory pressure) can end the process before the async Firestore
// write in _endSession() finishes, or without calling it at all. A periodic
// heartbeat writes `lastActiveAt` + a running `durationSeconds` while the
// session is active, so an abrupt kill still leaves a recent, close-enough
// value instead of permanently-null endedAt/durationSeconds.
// ─────────────────────────────────────────────────────────────────────────────
class SessionTrackerService with WidgetsBindingObserver {
  SessionTrackerService._();
  static final SessionTrackerService instance = SessionTrackerService._();

  static const _heartbeatInterval = Duration(seconds: 20);

  StreamSubscription<User?>? _authSub;
  Timer? _heartbeatTimer;
  String? _activeSessionId;
  DateTime? _sessionStartedAt;
  String? _appVersion;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _beginSession(user);
      } else {
        _endSession();
      }
    });
  }

  // Not called anywhere today (the service runs for the app's lifetime) —
  // kept so removing this feature later is a clean "call stop(), then
  // delete this file" rather than leaking a stream subscription.
  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _authSub = null;
    _endSession();
  }

  Future<void> _beginSession(User user) async {
    if (_activeSessionId != null) return;
    try {
      _appVersion ??= (await PackageInfo.fromPlatform()).version;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      _sessionStartedAt = DateTime.now();
      final doc = await FirebaseFirestore.instance.collection('sessions').add({
        'userId': user.uid,
        'email': user.email ?? '',
        'role': userDoc.data()?['role'],
        'startedAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
        'endedAt': null,
        'durationSeconds': null,
        'appVersion': _appVersion,
      });
      _activeSessionId = doc.id;
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _sendHeartbeat());
    } catch (_) {}
  }

  Future<void> _sendHeartbeat() async {
    final id = _activeSessionId;
    final startedAt = _sessionStartedAt;
    if (id == null || startedAt == null) return;
    try {
      await FirebaseFirestore.instance.collection('sessions').doc(id).update({
        'lastActiveAt': FieldValue.serverTimestamp(),
        'durationSeconds': DateTime.now().difference(startedAt).inSeconds,
      });
    } catch (_) {}
  }

  Future<void> _endSession() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final id = _activeSessionId;
    final startedAt = _sessionStartedAt;
    if (id == null || startedAt == null) return;
    _activeSessionId = null;
    _sessionStartedAt = null;
    final durationSeconds = DateTime.now().difference(startedAt).inSeconds;
    try {
      await FirebaseFirestore.instance.collection('sessions').doc(id).update({
        'endedAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
        'durationSeconds': durationSeconds,
      });
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _endSession();
    } else if (state == AppLifecycleState.resumed) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) _beginSession(user);
    }
  }
}
