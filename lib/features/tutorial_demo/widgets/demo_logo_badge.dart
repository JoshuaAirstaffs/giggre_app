import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'demo_theme.dart';

/// The real Giggre logo in a circular badge, sized to always show the
/// whole logo — `BoxFit.contain` inside a padded circle, never
/// `BoxFit.cover`/`ClipOval` directly on the image, which would crop a
/// wide (non-square) logo down to whatever a circle can fit.
class DemoLogoBadge extends StatelessWidget {
  final double size;
  const DemoLogoBadge({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.16),
      decoration: const BoxDecoration(color: dCard, shape: BoxShape.circle),
      child: Image.asset(
        'assets/images/logo.png',
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Icon(
          Icons.bolt_rounded,
          color: kGold,
          size: size * 0.5,
        ),
      ),
    );
  }
}
