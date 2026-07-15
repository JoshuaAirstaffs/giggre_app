import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../core/providers/current_user_provider.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/gig_host/presentation/gig_host_screen.dart';
import '../../features/gig_host/presentation/host_gigs_screen.dart';
import '../../features/gig_host/presentation/post_quick_gig_screen.dart';
import '../../features/gig_host/presentation/post_open_gig_screen.dart';
import '../../features/gig_host/presentation/post_offered_gig_screen.dart';
import '../../features/home/presentation/profile_tab.dart';
import '../chat/home_chat.dart';
import '../worker/worker_shell.dart';
import 'host_speed_dial.dart';

const _kNavActive = Color(0xFFD88810);
const _kNavInactive = Color(0xFF9AA5B5);
const _kPostGigLabel = Color(0xFFB06E00);
const _kFlatBarHeight = 64.0;

// ─────────────────────────────────────────────────────────────────────────────
//  Host mode nav shell — Home / My gigs / Post Gig (speed dial) / Chat /
//  Profile. Pushed once from the mode-selection homepage's "Continue as Gig
//  Host"; everything below lives on the same root Navigator, mirroring
//  WorkerShell's structure. Post Gig doesn't switch tabs — it toggles a
//  speed-dial overlay that reuses the exact same posting destinations the
//  old dashboard's "Post a Gig" cards used to.
// ─────────────────────────────────────────────────────────────────────────────
class HostShell extends StatefulWidget {
  const HostShell({super.key});

  @override
  State<HostShell> createState() => _HostShellState();
}

class _HostShellState extends State<HostShell> with SingleTickerProviderStateMixin {
  int _tabIndex = 0;
  bool _dialOpen = false;
  late final AnimationController _dialCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );

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
    _dialCtrl.dispose();
    super.dispose();
  }

  // Mirrors WorkerShell's unread-chat definition so the badge stays consistent
  // across modes.
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
      debugPrint('[HostShell] support unread stream error: $e');
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
      debugPrint('[HostShell] gig unread stream error: $e');
    });
  }

  void _toggleDial() {
    setState(() => _dialOpen = !_dialOpen);
    if (_dialOpen) {
      _dialCtrl.forward();
    } else {
      _dialCtrl.reverse();
    }
  }

  void _closeDial() {
    if (!_dialOpen) return;
    setState(() => _dialOpen = false);
    _dialCtrl.reverse();
  }

  void _selectTab(int i) {
    if (_dialOpen) _closeDial();
    setState(() => _tabIndex = i);
  }

  void _openQuickGig() {
    _closeDial();
    final provider = context.read<CurrentUserProvider>();
    if (provider.isVerified == 'verified') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostQuickGigScreen(hostName: provider.currentName ?? ''),
        ),
      );
    } else {
      showUnverifiedHostModal(context);
    }
  }

  void _openOpenGig() {
    _closeDial();
    final provider = context.read<CurrentUserProvider>();
    if (provider.isVerified == 'verified') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostOpenGigScreen(hostName: provider.currentName ?? ''),
        ),
      );
    } else {
      showUnverifiedHostModal(context);
    }
  }

  void _openOfferedGig() {
    _closeDial();
    final provider = context.read<CurrentUserProvider>();
    if (provider.isVerified == 'verified') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostOfferedGigScreen(hostName: provider.currentName ?? ''),
        ),
      );
    } else {
      showUnverifiedHostModal(context);
    }
  }

  Future<void> _performLogout() async {
    if (!mounted) return;
    context.read<CurrentUserProvider>().clearUser();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
    await WidgetsBinding.instance.endOfFrame;
    await GoogleSignIn().disconnect();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final navBarHeight = _kFlatBarHeight + MediaQuery.of(context).padding.bottom;

    final tabs = [
      const GigHostScreen(isTabRoot: true),
      HostGigsScreen(uid: uid, isTabRoot: true),
      const HomeChat(showBackButton: false),
      Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: ProfileTab(
          initialRole: 'host',
          onSwitchRole: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const WorkerShell()),
          ),
          onLogout: _performLogout,
        ),
      ),
    ];

    return PopScope(
      canPop: !_dialOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _dialOpen) _closeDial();
      },
      child: Stack(
        children: [
          Scaffold(
            body: IndexedStack(index: _tabIndex, children: tabs),
            bottomNavigationBar: _HostBottomNavBar(
              currentIndex: _tabIndex,
              hasUnreadChat: _hasUnreadSupport || _hasUnreadGig,
              onTap: _selectTab,
              onPostGigTap: _toggleDial,
            ),
          ),
          Positioned.fill(
            child: HostSpeedDialOverlay(
              controller: _dialCtrl,
              navBarHeight: navBarHeight,
              onClose: _closeDial,
              onQuickGig: _openQuickGig,
              onOpenGig: _openOpenGig,
              onOfferedGig: _openOfferedGig,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: navBarHeight - 30,
            child: Center(
              child: HostSpeedDialButton(controller: _dialCtrl, onTap: _toggleDial),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Flat bottom nav bar — Home / My gigs / [Post Gig label] / Chat / Profile.
//  The raised button itself is rendered in HostShell's outer Stack so it can
//  protrude above this bar unclipped; this widget only reserves its label.
// ─────────────────────────────────────────────────────────────────────────────
class _HostBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final bool hasUnreadChat;
  final ValueChanged<int> onTap;
  final VoidCallback onPostGigTap;

  const _HostBottomNavBar({
    required this.currentIndex,
    required this.hasUnreadChat,
    required this.onTap,
    required this.onPostGigTap,
  });

  Widget _item({
    required IconData icon,
    required String label,
    required bool active,
    bool showDot = false,
    required VoidCallback onTap,
  }) {
    final color = active ? _kNavActive : _kNavInactive;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 22, color: color),
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
              label,
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
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _kFlatBarHeight,
          child: Row(
            children: [
              _item(
                icon: Icons.home_outlined,
                label: 'Home',
                active: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _item(
                icon: Icons.assignment_outlined,
                label: 'My gigs',
                active: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              // Post Gig — the hit area for this slot plus the floating
              // button above it act together as one tap target.
              Expanded(
                child: InkWell(
                  onTap: onPostGigTap,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(height: 36),
                      Text(
                        'Post Gig',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: _kPostGigLabel,
                        ),
                      ),
                      SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
              _item(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Chat',
                active: currentIndex == 2,
                showDot: hasUnreadChat,
                onTap: () => onTap(2),
              ),
              _item(
                icon: Icons.person_outline_rounded,
                label: 'Profile',
                active: currentIndex == 3,
                onTap: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
