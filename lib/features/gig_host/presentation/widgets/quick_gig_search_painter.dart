import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Rotating dashed ring drawn around the search hero — shared by
/// [QuickGigSearchSheet]'s searching/found/accepted/empty states.
class QuickGigDashedRingPainter extends CustomPainter {
  final Color color;
  const QuickGigDashedRingPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final radius = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);
    const dashCount = 28;
    const gapFraction = 0.5;
    final sweep = (2 * math.pi) / dashCount;

    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweep,
        sweep * (1 - gapFraction),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant QuickGigDashedRingPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// One of the three orbiting avatar slots around the search hero.
/// [filled] toggles the color fill-in; [confirmed] swaps the icon for a
/// checkmark (used once a worker is confirmed); [scale] drives the
/// bump-in animation when a slot gets confirmed.
class QuickGigAvatarSlot extends StatelessWidget {
  final Offset offset;
  final Color color;
  final bool filled;
  final bool confirmed;
  final double scale;

  const QuickGigAvatarSlot({
    super.key,
    required this.offset,
    required this.color,
    required this.filled,
    this.confirmed = false,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: offset,
      child: Transform.scale(
        scale: scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : Colors.transparent,
            border: Border.all(
              color: filled ? color : Colors.white.withValues(alpha: 0.6),
              width: 1.5,
            ),
          ),
          child: Icon(
            confirmed ? Icons.check : Icons.person,
            size: 18,
            color: filled ? Colors.white : Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}
