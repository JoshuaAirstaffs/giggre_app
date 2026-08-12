import 'package:flutter/material.dart';
import '../../widgets/demo_pulse_highlight.dart';
import '../../widgets/demo_theme.dart';

/// Generic "accepted!" beat reused wherever the demo shows a worker
/// accepting a gig/offer.
class MockAcceptedScene extends StatelessWidget {
  final String message;
  const MockAcceptedScene({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DemoTapPulse(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: Color(0x2222C55E),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Color(0xFF22C55E),
                size: 44,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: dTitle,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
