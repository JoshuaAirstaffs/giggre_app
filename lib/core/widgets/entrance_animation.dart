import 'dart:async';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

enum EntranceAnimationType { fadeIn, fadeInSlideUp }

// Plays once the first time it scrolls into view — wrap any widget to have
// it fade in (and optionally slide up) as it enters the screen, instead of
// every instance firing together as soon as the page mounts. Give staggered
// children increasing `delay` values for a sequenced reveal.
class EntranceAnimation extends StatefulWidget {
  const EntranceAnimation({
    super.key,
    required this.child,
    this.type = EntranceAnimationType.fadeIn,
    this.duration = const Duration(milliseconds: 450),
    this.delay = Duration.zero,
    this.curve = Curves.easeOut,
    this.slideOffset = 24,
    this.visibleFraction = 0.2,
  });

  final Widget child;
  final EntranceAnimationType type;
  final Duration duration;
  final Duration delay;
  final Curve curve;

  // Pixels the child travels from (fadeInSlideUp only), ignored for fadeIn.
  final double slideOffset;

  // Fraction of the child's area that must be on-screen before it triggers.
  final double visibleFraction;

  @override
  State<EntranceAnimation> createState() => _EntranceAnimationState();
}

class _EntranceAnimationState extends State<EntranceAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  final _visibilityKey = UniqueKey();
  Timer? _delayTimer;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _progress = CurvedAnimation(parent: _controller, curve: widget.curve);
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (_triggered || info.visibleFraction < widget.visibleFraction) return;
    _triggered = true;
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: _onVisibilityChanged,
      child: AnimatedBuilder(
        animation: _progress,
        child: widget.child,
        builder: (context, child) {
          Widget result = Opacity(opacity: _progress.value, child: child);
          if (widget.type == EntranceAnimationType.fadeInSlideUp) {
            result = Transform.translate(
              offset: Offset(0, (1 - _progress.value) * widget.slideOffset),
              child: result,
            );
          }
          return result;
        },
      ),
    );
  }
}
