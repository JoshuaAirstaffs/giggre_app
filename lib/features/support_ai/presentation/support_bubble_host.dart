// Giggre AI support — wires SupportBubble into the app: which mode it's in,
// which screens hide it, and the hand-off to a support ticket.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/current_user_provider.dart';
import '../services/support_ticket_handoff.dart';
import 'support_bubble.dart';

/// Screens that hide the bubble hold it hidden while they're on screen.
///
/// Holds come from initState/dispose and navigator callbacks, which can run
/// mid-build, so the bubble is told after the frame rather than right away.
class SupportBubbleVisibility {
  static final ValueNotifier<bool> hidden = ValueNotifier<bool>(false);
  static int _holds = 0;

  static void hold() => _update(_holds + 1);
  static void release() => _update(_holds > 0 ? _holds - 1 : 0);

  static void _update(int holds) {
    _holds = holds;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => hidden.value = _holds > 0,
    );
    WidgetsBinding.instance.scheduleFrame();
  }
}

/// Add to a screen's State to hide the bubble while that screen is open
/// (calls, active-gig GPS views, camera/scanner screens).
mixin HidesSupportBubble<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    SupportBubbleVisibility.hold();
  }

  @override
  void dispose() {
    SupportBubbleVisibility.release();
    super.dispose();
  }
}

/// The same as [HidesSupportBubble], for screens built inline in a route
/// builder (e.g. the full-screen maps).
class HideSupportBubble extends StatefulWidget {
  const HideSupportBubble({super.key, required this.child});

  final Widget child;

  @override
  State<HideSupportBubble> createState() => _HideSupportBubbleState();
}

class _HideSupportBubbleState extends State<HideSupportBubble>
    with HidesSupportBubble {
  @override
  Widget build(BuildContext context) => widget.child;
}

/// Hides the bubble on support ticket chats. Those open through the
/// `/chat/{roomId}` route (contact_us.dart, home_chat.dart); gig and DM chats
/// use the same route or screen but their room ids start with `gig_` / `dm_`.
class SupportBubbleRouteObserver extends NavigatorObserver {
  final Set<Route<dynamic>> _held = {};

  bool _isSupportChat(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || !name.startsWith('/chat/')) return false;
    final roomId = name.substring('/chat/'.length);
    return !roomId.startsWith('gig_') && !roomId.startsWith('dm_');
  }

  void _add(Route<dynamic>? route) {
    if (route != null && _isSupportChat(route) && _held.add(route)) {
      SupportBubbleVisibility.hold();
    }
  }

  void _remove(Route<dynamic>? route) {
    if (route != null && _held.remove(route)) {
      SupportBubbleVisibility.release();
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _remove(oldRoute);
    _add(newRoute);
  }
}

/// Worker or host, for the bubble's colours and the AI's answers.
///
/// Switching between WorkerShell and HostShell doesn't write `users.role`, so
/// the shells set this when they open; HomeScreen sets it from the saved role
/// and the role picker.
class SupportBubbleMode {
  static final ValueNotifier<GiggreMode> current =
      ValueNotifier<GiggreMode>(GiggreMode.worker);

  static void set(GiggreMode mode) {
    // Called from initState, so wait for the frame like the holds above.
    WidgetsBinding.instance.addPostFrameCallback((_) => current.value = mode);
    WidgetsBinding.instance.scheduleFrame();
  }

  static void setFromRole(String? role) {
    if (role == 'host') set(GiggreMode.host);
    if (role == 'worker') set(GiggreMode.worker);
  }
}

/// The bubble as placed in MaterialApp.builder. Hidden until the user is
/// fully signed in (CurrentUserProvider is only filled after AuthGate's
/// restore), and on the screens above.
class SupportBubbleHost extends StatelessWidget {
  const SupportBubbleHost({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select<CurrentUserProvider, bool>(
      (p) => p.isLoggedIn,
    );
    return ValueListenableBuilder<bool>(
      valueListenable: SupportBubbleVisibility.hidden,
      builder: (context, hidden, _) => ValueListenableBuilder<GiggreMode>(
        valueListenable: SupportBubbleMode.current,
        builder: (context, mode, _) => SupportBubble(
          mode: mode,
          visible: signedIn && !hidden,
          navigatorKey: navigatorKey,
          onTalkToPerson: (transcript) => handOffAiChatToSupport(
            navigatorKey: navigatorKey,
            user: context.read<CurrentUserProvider>(),
            transcript: transcript,
          ),
        ),
      ),
    );
  }
}
