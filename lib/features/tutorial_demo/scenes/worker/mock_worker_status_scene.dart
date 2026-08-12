import 'package:flutter/material.dart';
import '../../widgets/demo_theme.dart';

/// Full-screen "you're now online / status changed" confirmation, reused
/// wherever the demo wants to narrate a state change plainly.
class MockWorkerStatusScene extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const MockWorkerStatusScene({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color = const Color(0xFF22C55E),
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
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 34),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: dTitle,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: dBody, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
