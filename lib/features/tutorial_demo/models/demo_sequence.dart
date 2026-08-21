import 'package:flutter/widgets.dart';
import 'demo_step.dart';

/// A fully self-contained, independently-playable demo (e.g. "Host: Quick
/// Gig"). Shown as one card in the demo hub and played end-to-end by
/// [DemoController]/[DemoPlayerScreen].
class DemoSequence {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<DemoStep> steps;

  const DemoSequence({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.steps,
  });
}
