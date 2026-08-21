import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../widgets/demo_fade_in.dart';
import '../../widgets/demo_theme.dart';

/// A short heading plus a staggered bullet list — used for the "here's how
/// this works" explainer beats (Quick Gigs factors, decline monitoring,
/// Toolchest verification reminder) that narrate the demo rather than show
/// a screen.
class MockInfoPanelScene extends StatelessWidget {
  final String title;
  final List<String> bullets;
  final String? footnote;

  const MockInfoPanelScene({
    super.key,
    required this.title,
    required this.bullets,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: dTitle,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < bullets.length; i++)
            DemoFadeIn(
              delay: Duration(milliseconds: 150 + i * 250),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.check_circle_rounded,
                        color: kGold,
                        size: 15,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        bullets[i],
                        style: const TextStyle(
                          color: dTitle,
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (footnote != null) ...[
            const SizedBox(height: 8),
            Text(
              footnote!,
              style: const TextStyle(
                color: dMuted,
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
