import 'package:flutter/material.dart';
import '../../widgets/demo_fade_in.dart';
import '../../widgets/demo_theme.dart';

/// A single "X = Y" concept slide — icon, a Host/Worker role tag, the
/// concept's name, and its one-line definition. Reused for every gig type
/// and worker feature in the "How Giggre Works" walkthrough so each gets
/// the exact same treatment.
class MockConceptSlideScene extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String roleLabel;
  final String title;
  final String definition;

  const MockConceptSlideScene({
    super.key,
    required this.icon,
    required this.color,
    required this.roleLabel,
    required this.title,
    required this.definition,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                roleLabel.toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 34),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: dTitle, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            DemoFadeIn(
              delay: const Duration(milliseconds: 300),
              child: Text(
                definition,
                textAlign: TextAlign.center,
                style: const TextStyle(color: dBody, fontSize: 14, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
