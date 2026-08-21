import 'dart:async';
import 'package:flutter/material.dart';

/// Fades + slides its child in after an optional [delay], used to stagger
/// mock data appearing on screen (form fields filling in, workers showing
/// up one by one, applicants trickling in) without a bespoke
/// `AnimationController` at every call site.
class DemoFadeIn extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const DemoFadeIn({super.key, required this.child, this.delay = Duration.zero});

  @override
  State<DemoFadeIn> createState() => _DemoFadeInState();
}

class _DemoFadeInState extends State<DemoFadeIn> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      offset: _visible ? Offset.zero : const Offset(0, 0.12),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        opacity: _visible ? 1 : 0,
        child: widget.child,
      ),
    );
  }
}
