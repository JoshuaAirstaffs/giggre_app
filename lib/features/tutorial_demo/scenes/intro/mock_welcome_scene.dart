import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../widgets/demo_fade_in.dart';
import '../../widgets/demo_logo_badge.dart';
import '../../widgets/demo_pulse_highlight.dart';
import '../../widgets/demo_theme.dart';

/// Opening slide of the "What is Giggre?" explainer — the real logo with a
/// pulsing ring, then the real tagline (`welcome_screen.dart`) fading in.
class MockWelcomeScene extends StatelessWidget {
  const MockWelcomeScene({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DemoPulseRing(
            color: kGold,
            child: DemoLogoBadge(size: 96),
          ),
          const SizedBox(height: 24),
          DemoFadeIn(
            delay: const Duration(milliseconds: 300),
            child: const Text(
              'Welcome to Giggre',
              style: TextStyle(color: dTitle, fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 10),
          DemoFadeIn(
            delay: const Duration(milliseconds: 600),
            child: const Text(
              'Every gig, right in your area.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kGold, fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          DemoFadeIn(
            delay: const Duration(milliseconds: 850),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Find work or get trusted help near you — fast, fair, and local.',
                textAlign: TextAlign.center,
                style: TextStyle(color: dBody, fontSize: 13, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
