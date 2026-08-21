import 'package:flutter/widgets.dart';

/// One beat of an automated demo sequence. [duration] is how long this step
/// stays on screen before [DemoController] auto-advances to the next one —
/// all timing lives here, never scattered as `Future.delayed` in scene code.
class DemoStep {
  final String id;
  final Duration duration;
  final WidgetBuilder builder;

  const DemoStep({
    required this.id,
    required this.duration,
    required this.builder,
  });
}
  