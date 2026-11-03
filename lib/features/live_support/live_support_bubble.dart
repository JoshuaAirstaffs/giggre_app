// ── Live support (TEMPORARY) ─────────────────────────────────────────────────
// A floating bubble, on every screen except chats and full-screen maps, that
// opens a chat with the real "Giggre Support" account — a public account
// anyone can message (no request to accept). The account is set per project:
//   general_config/live_support { enabled: bool, supportUid: string }
// so the bubble can be turned off there without an app update.
//
// To remove the feature:
//   1. delete lib/features/live_support/
//   2. in main.dart, remove the LiveSupportBubble line, the
//      liveSupportRouteObserver entry and the import (all marked TEMP)
//   3. in chat.dart, remove `with HidesLiveSupport`, _isLiveSupportPeer and
//      its uses, and the import; in the 4 call screens, `HidesLiveSupport`
//      and the import
//   4. delete functions/src/liveSupport.ts and its use in directMessages.ts
//   5. remove the general_config/live_support block in firestore.rules

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:giggre_app/features/chat/user_search_screen.dart'
    show openDirectChat;

const _supportName = 'Giggre Support';

// The configured support account, kept current by the bubble (which runs
// whenever someone is signed in).
String? _currentSupportUid;

/// Whether [uid] is the Giggre Support account. Chats with it have no call,
/// block or report actions (chat.dart).
bool isLiveSupportAccount(String? uid) =>
    uid != null && uid.isNotEmpty && uid == _currentSupportUid;

/// Why the bubble is hidden right now: the top route (popups, full-screen
/// maps) or a chat screen that's open.
class _Visibility {
  static final ValueNotifier<bool> hidden = ValueNotifier<bool>(false);
  static bool _routeHides = false;
  static int _chatHolds = 0;

  static void _update() {
    // Called from navigator callbacks and initState, which can run mid-build
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => hidden.value = _routeHides || _chatHolds > 0,
    );
    WidgetsBinding.instance.scheduleFrame();
  }
}

/// Hides the bubble while the top route is a dialog/sheet/menu (it would sit
/// on their buttons) or a full-screen dialog page — every full-screen map
/// opens as one (gig_host_screen, gig_map_section, gig_detail_sheet).
class LiveSupportRouteObserver extends NavigatorObserver {
  // The root navigator's stack, bottom to top
  final List<Route<dynamic>> _stack = [];

  void _changed() {
    final top = _stack.isEmpty ? null : _stack.last;
    _Visibility._routeHides =
        top is PopupRoute ||
        (top is PageRoute && top.fullscreenDialog) ||
        (top?.settings.name?.startsWith('/chat/') ?? false);
    _Visibility._update();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (newRoute != null) {
      i >= 0 ? _stack[i] = newRoute : _stack.add(newRoute);
    } else if (i >= 0) {
      _stack.removeAt(i);
    }
    _changed();
  }
}

final liveSupportRouteObserver = LiveSupportRouteObserver();

/// Add to a chat screen's State to hide the bubble while it's open.
mixin HidesLiveSupport<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    _Visibility._chatHolds++;
    _Visibility._update();
  }

  @override
  void dispose() {
    if (_Visibility._chatHolds > 0) _Visibility._chatHolds--;
    _Visibility._update();
    super.dispose();
  }
}

/// Place in MaterialApp.builder's Stack, above the navigator. Shows nothing
/// while signed out, until general_config/live_support is enabled, and never
/// for the support account itself.
class LiveSupportBubble extends StatefulWidget {
  const LiveSupportBubble({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<LiveSupportBubble> createState() => _LiveSupportBubbleState();
}

class _LiveSupportBubbleState extends State<LiveSupportBubble> {
  static const _size = 58.0;

  Offset? _pos;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _configSub;
  StreamSubscription<bool>? _unreadSub;
  String? _myUid;
  String? _supportUid;
  bool _hasUnread = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    // The config is only readable signed in, so (re)subscribe per account
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onUser);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _configSub?.cancel();
    _unreadSub?.cancel();
    super.dispose();
  }

  void _onUser(User? user) {
    if (user?.uid == _myUid) return;
    _configSub?.cancel();
    _unreadSub?.cancel();
    _currentSupportUid = null;
    setState(() {
      _myUid = user?.uid;
      _supportUid = null;
      _hasUnread = false;
    });
    if (user == null) return;
    _configSub = FirebaseFirestore.instance
        .collection('general_config')
        .doc('live_support')
        .snapshots()
        .listen(
          _onConfig,
          onError: (Object e) {
            if (FirebaseAuth.instance.currentUser == null) return;
            debugPrint('[LiveSupport] config: $e');
          },
        );
  }

  void _onConfig(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    final uid = data?['supportUid'];
    final next = data?['enabled'] == true && uid is String && uid.isNotEmpty
        ? uid
        : null;
    _currentSupportUid = next;
    if (next == _supportUid) return;
    setState(() {
      _supportUid = next;
      _hasUnread = false;
    });
    _listenUnread();
  }

  /// Unread = a support message in our direct room not yet seen. The room
  /// only exists after the first chat, so watch the room before its messages.
  void _listenUnread() {
    _unreadSub?.cancel();
    final me = _myUid;
    final support = _supportUid;
    if (me == null || support == null || me == support) return;
    final ids = [me, support]..sort();
    final room = FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc('dm_${ids.join('_')}');
    _unreadSub = room
        .snapshots()
        .asyncExpand(
          (r) => r.exists
              ? room
                    .collection('messages')
                    .where('senderId', isEqualTo: support)
                    .where('hasSeen', isEqualTo: false)
                    .limit(1)
                    .snapshots()
                    .map((s) => s.docs.isNotEmpty)
              : Stream.value(false),
        )
        .listen(
          (unread) {
            if (mounted) setState(() => _hasUnread = unread);
          },
          onError: (Object e) {
            if (FirebaseAuth.instance.currentUser == null) return;
            debugPrint('[LiveSupport] unread: $e');
          },
        );
  }

  Future<void> _open() async {
    final support = _supportUid;
    // This widget sits above the navigator, so route through its context
    final navContext = widget.navigatorKey.currentContext;
    if (support == null || navContext == null || _opening) return;
    setState(() => _opening = true);
    await openDirectChat(navContext, peerUid: support, peerName: _supportName);
    if (mounted) setState(() => _opening = false);
  }

  void _snapToEdge(Size screen, EdgeInsets padding) {
    final x = _pos!.dx + _size / 2 < screen.width / 2
        ? 12.0
        : screen.width - _size - 12;
    setState(() => _pos = Offset(x, _clampY(_pos!.dy, screen, padding)));
  }

  // Clear of the status bar and bottom nav bars
  double _clampY(double y, Size screen, EdgeInsets padding) =>
      y.clamp(padding.top + 72, screen.height - padding.bottom - _size - 100);

  @override
  Widget build(BuildContext context) {
    final support = _supportUid;
    final media = MediaQuery.of(context);
    if (support == null || _myUid == null || support == _myUid) {
      return const SizedBox.shrink();
    }

    final screen = media.size;
    // Right side, above where the Gab bubble sits
    _pos ??= Offset(screen.width - _size - 12, screen.height - _size - 220);
    final pos = Offset(
      _pos!.dx.clamp(12.0, screen.width - _size - 12),
      _clampY(_pos!.dy, screen, media.padding),
    );

    return ValueListenableBuilder<bool>(
      valueListenable: _Visibility.hidden,
      builder: (context, hidden, _) {
        // Also hidden while typing, so it never sits on a text field
        if (hidden || media.viewInsets.bottom > 0) {
          return const SizedBox.shrink();
        }
        return AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          left: pos.dx,
          top: pos.dy,
          child: GestureDetector(
            onPanUpdate: (d) => setState(() => _pos = pos + d.delta),
            onPanEnd: (_) => _snapToEdge(screen, media.padding),
            child: Semantics(
              button: true,
              label: _hasUnread
                  ? 'Chat with $_supportName, new message'
                  : 'Chat with $_supportName',
              child: _BubbleFace(
                size: _size,
                opening: _opening,
                hasUnread: _hasUnread,
                onTap: _open,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The Giggre logo on a white disc (it's orange and blue, so it reads on
/// white in both themes), with a red dot for an unread reply.
class _BubbleFace extends StatelessWidget {
  const _BubbleFace({
    required this.size,
    required this.opening,
    required this.hasUnread,
    required this.onTap,
  });

  final double size;
  final bool opening;
  final bool hasUnread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.white,
            shape: CircleBorder(
              side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
            ),
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.35),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: opening
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      )
                    : Image.asset(
                        'assets/icons/logo_app.png',
                        filterQuality: FilterQuality.medium,
                      ),
              ),
            ),
          ),
          if (hasUnread)
            Positioned(
              top: 1,
              right: 1,
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
