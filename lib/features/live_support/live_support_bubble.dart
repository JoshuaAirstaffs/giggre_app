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
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

/// Giggre Support's picture in chats (the account has no photo): the logo,
/// shown on a white circle.
const liveSupportAvatar = AssetImage('assets/icons/logo_app.png');

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
  // Drop target shown at the bottom middle while dragging
  static const _hideSize = 56.0;
  static const _hideReach = 64.0;
  // The tab the bubble tucks into once hidden
  static const _tabWidth = 22.0;
  static const _tabHeight = 42.0;
  static const _prefsDocked = 'live_support_docked';
  static const _prefsDockRight = 'live_support_dock_right';

  Offset? _pos;
  bool _dragging = false;
  bool _overHide = false;
  // Hidden into the corner tab (remembered across launches)
  bool _docked = false;
  bool _dockRight = true;
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
    _loadDock();
  }

  Future<void> _loadDock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _docked = prefs.getBool(_prefsDocked) ?? false;
        _dockRight = prefs.getBool(_prefsDockRight) ?? true;
      });
    } catch (e) {
      debugPrint('[LiveSupport] prefs: $e');
    }
  }

  Future<void> _setDocked(bool docked, {bool? right}) async {
    setState(() {
      _docked = docked;
      if (right != null) _dockRight = right;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsDocked, docked);
      await prefs.setBool(_prefsDockRight, _dockRight);
    } catch (e) {
      debugPrint('[LiveSupport] prefs: $e');
    }
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
      y.clamp(padding.top + 72, _maxY(screen, padding));

  double _maxY(Size screen, EdgeInsets padding) =>
      screen.height - padding.bottom - _size - 100;

  Offset _hideCenter(Size screen, EdgeInsets padding) =>
      Offset(screen.width / 2, screen.height - padding.bottom - 72);

  void _onDrag(DragUpdateDetails d, Size screen, EdgeInsets padding) {
    // Free to move anywhere on screen while held, so it can reach the target
    final next = _pos! + d.delta;
    final pos = Offset(
      next.dx.clamp(0.0, screen.width - _size),
      next.dy.clamp(padding.top, screen.height - padding.bottom - _size),
    );
    final center = pos + const Offset(_size / 2, _size / 2);
    final over = (center - _hideCenter(screen, padding)).distance < _hideReach;
    if (over && !_overHide) HapticFeedback.selectionClick();
    setState(() {
      _pos = pos;
      _overHide = over;
    });
  }

  void _onDragEnd(Size screen, EdgeInsets padding) {
    final hide = _overHide;
    setState(() {
      _dragging = false;
      _overHide = false;
    });
    if (hide) {
      _setDocked(true, right: _pos!.dx + _size / 2 >= screen.width / 2);
    } else {
      _snapToEdge(screen, padding);
    }
  }

  /// Out of the corner tab, back to a bubble on the same side.
  void _undock(Size screen, EdgeInsets padding) {
    setState(() {
      _pos = Offset(
        _dockRight ? screen.width - _size - 12 : 12.0,
        _maxY(screen, padding),
      );
    });
    _setDocked(false);
  }

  @override
  Widget build(BuildContext context) {
    final support = _supportUid;
    final media = MediaQuery.of(context);
    if (support == null || _myUid == null || support == _myUid) {
      return const SizedBox.shrink();
    }

    final screen = media.size;
    final padding = media.padding;
    // Right side, above where the Gab bubble sits
    _pos ??= Offset(screen.width - _size - 12, screen.height - _size - 220);
    final pos = _dragging
        ? _pos!
        : Offset(
            _pos!.dx.clamp(12.0, screen.width - _size - 12),
            _clampY(_pos!.dy, screen, padding),
          );
    final hideCenter = _hideCenter(screen, padding);

    return ValueListenableBuilder<bool>(
      valueListenable: _Visibility.hidden,
      builder: (context, hidden, _) {
        // Also hidden while typing, so it never sits on a text field
        if (hidden || media.viewInsets.bottom > 0) {
          return const SizedBox.shrink();
        }
        // Fills the screen but only its children take touches, so the app
        // underneath stays usable.
        return Positioned.fill(
          child: Stack(
            children: [
              if (_dragging)
                Positioned(
                  left: hideCenter.dx - _hideSize / 2,
                  top: hideCenter.dy - _hideSize / 2,
                  child: IgnorePointer(child: _HideTarget(active: _overHide)),
                ),
              if (_docked)
                Positioned(
                  right: _dockRight ? 0 : null,
                  left: _dockRight ? null : 0,
                  top: _maxY(screen, padding) + _size - _tabHeight,
                  child: _CornerTab(
                    right: _dockRight,
                    hasUnread: _hasUnread,
                    onTap: () => _undock(screen, padding),
                  ),
                )
              else
                AnimatedPositioned(
                  // Follows the finger exactly while dragging
                  duration: _dragging
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  left: pos.dx,
                  top: pos.dy,
                  child: GestureDetector(
                    onPanStart: (_) => setState(() {
                      _pos = pos;
                      _dragging = true;
                    }),
                    onPanUpdate: (d) => _onDrag(d, screen, padding),
                    onPanEnd: (_) => _onDragEnd(screen, padding),
                    onPanCancel: () => _onDragEnd(screen, padding),
                    child: Semantics(
                      button: true,
                      label: _hasUnread
                          ? 'Chat with $_supportName, new message'
                          : 'Chat with $_supportName',
                      child: AnimatedScale(
                        scale: _overHide ? 0.8 : 1,
                        duration: const Duration(milliseconds: 120),
                        child: _BubbleFace(
                          size: _size,
                          opening: _opening,
                          hasUnread: _hasUnread,
                          onTap: _open,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The "drop here to hide" circle at the bottom middle while dragging. Grows
/// when the bubble is over it.
class _HideTarget extends StatelessWidget {
  const _HideTarget({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: active ? 1.2 : 1,
      duration: const Duration(milliseconds: 120),
      child: Container(
        width: _LiveSupportBubbleState._hideSize,
        height: _LiveSupportBubbleState._hideSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? const Color(0xFFEF4444)
              : Colors.black.withValues(alpha: 0.55),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.visibility_off_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}

/// The hidden bubble: a small tab flush with the screen edge, near the bottom
/// corner. Tapping it brings the bubble back.
class _CornerTab extends StatelessWidget {
  const _CornerTab({
    required this.right,
    required this.hasUnread,
    required this.onTap,
  });

  final bool right;
  final bool hasUnread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const r = Radius.circular(10);
    final shape = BorderRadius.horizontal(
      left: right ? r : Radius.zero,
      right: right ? Radius.zero : r,
    );
    return Semantics(
      button: true,
      label: hasUnread
          ? 'Show $_supportName, new message'
          : 'Show $_supportName',
      child: SizedBox(
        width: _LiveSupportBubbleState._tabWidth,
        height: _LiveSupportBubbleState._tabHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // See-through so it stays out of the way; the unread dot below
            // stays fully visible.
            Opacity(
              opacity: 0.6,
              child: Material(
                color: _surface(context),
                elevation: 3,
                shadowColor: Colors.black.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: shape,
                  side: BorderSide(color: _edge(context)),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: const SizedBox.expand(
                    child: Padding(
                      padding: EdgeInsets.all(3),
                      child: Image(
                        image: liveSupportAvatar,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (hasUnread)
              Positioned(
                top: -4,
                left: right ? -4 : null,
                right: right ? null : -4,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                    border: Border.all(color: _surface(context), width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bubble and tab surface: white in light mode, the app's dark card colour in
/// dark mode (the logo's orange and blue read on both).
Color _surface(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF1E293B)
    : Colors.white;

Color _edge(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? Colors.white.withValues(alpha: 0.12)
    : Colors.black.withValues(alpha: 0.06);

/// The Giggre logo on a disc, with a red dot for an unread reply.
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
            color: _surface(context),
            shape: CircleBorder(side: BorderSide(color: _edge(context))),
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
                  border: Border.all(color: _surface(context), width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
