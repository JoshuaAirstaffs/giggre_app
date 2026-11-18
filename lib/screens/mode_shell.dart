import 'package:flutter/material.dart';

import 'host/host_shell.dart';
import 'worker/worker_shell.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Worker ⇄ Host container. Both shells stay mounted once built, so switching
//  mode is a quick cross-fade instead of a new page that reloads everything
//  (blank spinner, maps re-initialising). The other mode is built in the
//  background right after the first frame, so even the first switch is
//  instant.
//
//  The hidden shell gets `modeActive: false`: the worker dashboard goes
//  offline and holds its pop-ups, maps/videos pause (TickerMode + isTabActive)
//  until it's shown again — same as before, when it was disposed.
// ─────────────────────────────────────────────────────────────────────────────
class ModeShell extends StatefulWidget {
  final bool startAsHost;
  const ModeShell({super.key, this.startAsHost = false});

  @override
  State<ModeShell> createState() => _ModeShellState();
}

class _ModeShellState extends State<ModeShell>
    with SingleTickerProviderStateMixin {
  late bool _isHost = widget.startAsHost;
  late bool _hostBuilt = widget.startAsHost;
  late bool _workerBuilt = !widget.startAsHost;
  // The mode we just left; stays painted under the fade until it finishes.
  bool? _leavingIsHost;

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed && _leavingIsHost != null && mounted) {
        setState(() => _leavingIsHost = null);
      }
    });

  // Eased cross-fade; the header layout is identical in both modes
  // (DashboardHeaderBar), so it reads as a colour change while the mode
  // toggle's thumb slides across.
  late final Animation<double> _fadeCurve = CurvedAnimation(
    parent: _fade,
    curve: Curves.easeInOutCubic,
  );

  @override
  void initState() {
    super.initState();
    // Pre-build the other mode right after the first frame, so the mode
    // you opened paints first and the other is ready by the time you tap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _hostBuilt = true;
        _workerBuilt = true;
      });
    });
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _switchTo({required bool host}) {
    if (host == _isHost) return;
    setState(() {
      _leavingIsHost = _isHost;
      _isHost = host;
      if (host) {
        _hostBuilt = true;
      } else {
        _workerBuilt = true;
      }
    });
    _fade.forward(from: 0);
  }

  Widget _layer({required bool host, required Widget child}) {
    final active = host == _isHost;
    final leaving = host == _leavingIsHost;
    // Same widget types in every state, so the shell's State is kept.
    return KeyedSubtree(
      key: ValueKey(host ? 'host' : 'worker'),
      child: Offstage(
        offstage: !active && !leaving,
        child: IgnorePointer(
          ignoring: !active,
          child: TickerMode(
            enabled: active || leaving,
            child: FadeTransition(
              opacity: active ? _fadeCurve : kAlwaysCompleteAnimation,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final host = _hostBuilt
        ? _layer(
            host: true,
            child: HostShell(
              modeActive: _isHost,
              onSwitchMode: () => _switchTo(host: false),
            ),
          )
        : null;
    final worker = _workerBuilt
        ? _layer(
            host: false,
            child: WorkerShell(
              modeActive: !_isHost,
              onSwitchMode: () => _switchTo(host: true),
            ),
          )
        : null;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Stack(
        fit: StackFit.expand,
        // The active mode paints on top.
        children: [
          if (_isHost) ...[?worker, ?host] else ...[?host, ?worker],
        ],
      ),
    );
  }
}
