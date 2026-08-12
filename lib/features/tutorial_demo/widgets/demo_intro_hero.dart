import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'demo_host_worker_connector.dart';
import 'demo_logo_badge.dart';
import 'demo_pulse_highlight.dart';
import 'demo_theme.dart';

/// "What is Giggre?" hero shown at the top of the demo hub — the real logo
/// and tagline (`welcome_screen.dart`), a short explainer of the two-sided
/// marketplace, and an animated Host↔Worker connector to set up why the
/// hub below is split into two sections.
class DemoIntroHero extends StatelessWidget {
  const DemoIntroHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const DemoPulseRing(
          color: kGold,
          child: DemoLogoBadge(size: 64),
        ),
        const SizedBox(height: 14),
        const Text(
          'What is Giggre?',
          style: TextStyle(color: dTitle, fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Every gig, right in your area.',
          textAlign: TextAlign.center,
          style: TextStyle(color: dTitle, fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Giggre connects two sides of the same gig: a Gig Host who needs '
            'something done, and a Gig Worker ready to do it — fast, fair, '
            'and local.',
            textAlign: TextAlign.center,
            style: TextStyle(color: dBody, fontSize: 12.5, height: 1.4),
          ),
        ),
        const SizedBox(height: 20),
        const DemoHostWorkerConnector(),
      ],
    );
  }
}
