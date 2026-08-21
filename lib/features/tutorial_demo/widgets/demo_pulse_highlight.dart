import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Continuous pulsing ring used to draw the eye to something the demo wants
/// to highlight (a toggle, a card, a "searching" icon) without any real
/// interaction behind it.
class DemoPulseRing extends StatefulWidget {
  final Widget child;
  final Color color;
  const DemoPulseRing({super.key, required this.child, this.color = kAmber});

  @override
  State<DemoPulseRing> createState() => _DemoPulseRingState();
}

class _DemoPulseRingState extends State<DemoPulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The ring is `Positioned.fill` so it never influences the Stack's own
    // size — only `child` (non-positioned) does. That keeps this safe to
    // use inside unbounded-height contexts (a `Column`/`Center`), where a
    // naive `SizedBox.expand` on the ring would try to fill infinite space.
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Transform.scale(
                scale: 1 + t * 0.35,
                child: Opacity(
                  opacity: (1 - t).clamp(0, 1),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: widget.color, width: 2),
                    ),
                  ),
                ),
              ),
            ),
            child!,
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// Simulates a user pressing something: a one-shot press-down/release
/// animation that plays automatically once this widget mounts, then settles.
/// Wrap a button-like widget in this to make the demo look like it was
/// tapped, without wiring up a real [GestureDetector] the viewer could tap.
class DemoTapPulse extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const DemoTapPulse({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  @override
  State<DemoTapPulse> createState() => _DemoTapPulseState();
}

class _DemoTapPulseState extends State<DemoTapPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.92).chain(
        CurveTween(curve: Curves.easeOut),
      ),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 0.92, end: 1.0).chain(
        CurveTween(curve: Curves.easeOut),
      ),
      weight: 1,
    ),
  ]).animate(_controller);

  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _delayTimer = Timer(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}
