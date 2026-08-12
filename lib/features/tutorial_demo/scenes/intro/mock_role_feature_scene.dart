import 'package:flutter/material.dart';
import '../../widgets/demo_fade_in.dart';
import '../../widgets/demo_theme.dart';

/// A labeled feature chip (icon + short text), used by [MockRoleFeatureScene]
/// to list out what a Host/Worker can do on Giggre.
class RoleFeature {
  final IconData icon;
  final String label;
  const RoleFeature(this.icon, this.label);
}

/// Generic "here's what you can do" slide, reused for the Host and Worker
/// beats of the "What is Giggre?" explainer — a heading, a description, and
/// a row of feature chips that fade in one after another.
class MockRoleFeatureScene extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String heading;
  final String description;
  final List<RoleFeature> features;

  const MockRoleFeatureScene({
    super.key,
    required this.icon,
    required this.color,
    required this.heading,
    required this.description,
    required this.features,
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
              heading,
              textAlign: TextAlign.center,
              style: const TextStyle(color: dTitle, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: dBody, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < features.length; i++)
                  DemoFadeIn(
                    delay: Duration(milliseconds: 200 + i * 220),
                    child: _FeatureChip(feature: features[i], color: color),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final RoleFeature feature;
  final Color color;
  const _FeatureChip({required this.feature, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(feature.icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            feature.label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
