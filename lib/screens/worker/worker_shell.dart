import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../core/providers/current_user_provider.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/gig_worker/presentation/gig_worker_screen.dart';
import '../../features/home/presentation/profile_tab.dart';
import '../chat/home_chat.dart';
import '../host/host_shell.dart';
import 'saved_placeholder.dart';

const _kNavActive = Color(0xFF2B6FB5);
const _kNavInactive = Color(0xFF9AA5B5);

// ─────────────────────────────────────────────────────────────────────────────
//  Worker mode nav shell — Home / Browse / Saved / Chat / Profile.
//  Pushed once from the mode-selection homepage's "Continue as Gig Worker";
//  everything below lives on the same root Navigator, so deep pushes from a
//  tab (gig details, active gig, account screens...) still render full-screen
//  above the bar, and back from those returns into the shell as usual.
// ─────────────────────────────────────────────────────────────────────────────
class WorkerShell extends StatefulWidget {
  const WorkerShell({super.key});

  @override
  State<WorkerShell> createState() => _WorkerShellState();
}

class _WorkerShellState extends State<WorkerShell> {
  int _index = 0;

  bool _hasUnreadSupport = false;
  bool _hasUnreadGig = false;
  StreamSubscription? _supportRoomsSub;
  final List<StreamSubscription> _supportMsgSubs = [];
  StreamSubscription? _gigRoomsSub;
  final List<StreamSubscription> _gigMsgSubs = [];

  @override
  void initState() {
    super.initState();
    _listenForUnreadSupport();
    _listenForUnreadGig();
  }

  @override
  void dispose() {
    _supportRoomsSub?.cancel();
    for (final s in _supportMsgSubs) {
      s.cancel();
    }
    _gigRoomsSub?.cancel();
    for (final s in _gigMsgSubs) {
      s.cancel();
    }
    super.dispose();
  }

  // Mirrors the same chat_rooms queries the mode-selection homepage's chat
  // badge uses, so the Chat tab dot reflects the same "unread" definition.
  void _listenForUnreadSupport() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _supportRoomsSub = FirebaseFirestore.instance
        .collection('chat_rooms')
        .where('userId', isEqualTo: uid)
        .where('isSupport', isEqualTo: true)
        .snapshots()
        .listen((roomsSnap) {
      for (final s in _supportMsgSubs) {
        s.cancel();
      }
      _supportMsgSubs.clear();
      if (roomsSnap.docs.isEmpty) {
        if (mounted) setState(() => _hasUnreadSupport = false);
        return;
      }
      final roomUnread = <int, bool>{};
      for (var i = 0; i < roomsSnap.docs.length; i++) {
        final room = roomsSnap.docs[i];
        final sub = FirebaseFirestore.instance
            .collection('chat_rooms')
            .doc(room.id)
            .collection('messages')
            .where('isSupport', isEqualTo: true)
            .where('hasSeen', isEqualTo: false)
            .limit(1)
            .snapshots()
            .map((s) => s.docs.isNotEmpty)
            .listen((hasUnread) {
          roomUnread[i] = hasUnread;
          final any = roomUnread.values.any((v) => v);
          if (mounted) setState(() => _hasUnreadSupport = any);
        });
        _supportMsgSubs.add(sub);
      }
    }, onError: (e) {
      if (FirebaseAuth.instance.currentUser == null) return;
      debugPrint('[WorkerShell] support unread stream error: $e');
    });
  }

  void _listenForUnreadGig() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _gigRoomsSub = FirebaseFirestore.instance
        .collection('chat_rooms')
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen((roomsSnap) {
      for (final s in _gigMsgSubs) {
        s.cancel();
      }
      _gigMsgSubs.clear();
      if (roomsSnap.docs.isEmpty) {
        if (mounted) setState(() => _hasUnreadGig = false);
        return;
      }
      final roomUnread = <int, bool>{};
      for (var i = 0; i < roomsSnap.docs.length; i++) {
        final room = roomsSnap.docs[i];
        final participants =
            (room.data()['participants'] as List<dynamic>?) ?? [];
        final otherUid =
            participants.firstWhere((p) => p != uid, orElse: () => '')
                as String;
        if (otherUid.isEmpty) continue;
        final sub = FirebaseFirestore.instance
            .collection('chat_rooms')
            .doc(room.id)
            .collection('messages')
            .where('senderId', isEqualTo: otherUid)
            .where('hasSeen', isEqualTo: false)
            .limit(1)
            .snapshots()
            .map((s) => s.docs.isNotEmpty)
            .listen((hasUnread) {
          roomUnread[i] = hasUnread;
          final any = roomUnread.values.any((v) => v);
          if (mounted) setState(() => _hasUnreadGig = any);
        });
        _gigMsgSubs.add(sub);
      }
    }, onError: (e) {
      if (FirebaseAuth.instance.currentUser == null) return;
      debugPrint('[WorkerShell] gig unread stream error: $e');
    });
  }

  void _goToHome() => setState(() => _index = 0);

  Future<void> _performLogout() async {
    if (!mounted) return;
    final clearing = context.read<CurrentUserProvider>().clearUser();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
    await WidgetsBinding.instance.endOfFrame;
    await clearing;
    await GoogleSignIn().disconnect();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const GigWorkerScreen(isTabRoot: true),
      SavedPlaceholder(onGoToDashboard: _goToHome),
      const HomeChat(showBackButton: false),
      Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: ProfileTab(
          initialRole: 'worker',
          onSwitchRole: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HostShell()),
          ),
          onLogout: _performLogout,
        ),
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: _WorkerBottomNavBar(
        currentIndex: _index,
        hasUnreadChat: _hasUnreadSupport || _hasUnreadGig,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bottom nav bar
// ─────────────────────────────────────────────────────────────────────────────
class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

const _kNavItems = [
  _NavItem(Icons.home_outlined, 'Home'),
  _NavItem(Icons.bookmark_outline_rounded, 'Saved'),
  _NavItem(Icons.chat_bubble_outline_rounded, 'Chat'),
  _NavItem(Icons.person_outline_rounded, 'Profile'),
];

class _WorkerBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final bool hasUnreadChat;
  final ValueChanged<int> onTap;

  const _WorkerBottomNavBar({
    required this.currentIndex,
    required this.hasUnreadChat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(_kNavItems.length, (i) {
              final item = _kNavItems[i];
              final active = i == currentIndex;
              final color = active ? _kNavActive : _kNavInactive;
              final showDot = i == 2 && hasUnreadChat;

              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(item.icon, size: 22, color: color),
                          if (showDot)
                            Positioned(
                              top: -2,
                              right: -3,
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF5252),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
