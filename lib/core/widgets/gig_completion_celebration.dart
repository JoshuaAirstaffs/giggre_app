import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  GigCompletionCelebration — a full-screen confetti burst behind a "success"
//  card, shown right after payment is confirmed, before the rating dialog
//  (worker: "Thank You!", host: "Gig Complete!"). Dismissed only by the
//  Continue button (or tapping outside) — no auto-close.
// ─────────────────────────────────────────────────────────────────────────────
class GigCompletionCelebration {
  static Future<void> show({
    required BuildContext context,
    required String title,
    required String subtitle,
    IconData icon = Icons.celebration_rounded,
    Color accentColor = const Color(0xFF22C55E),
  }) async {
    final overlayState = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(builder: (_) => const _FullScreenConfetti());
    overlayState.insert(entry);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (_) => _CelebrationCard(
          title: title,
          subtitle: subtitle,
          icon: icon,
          accentColor: accentColor,
        ),
      );
    } finally {
      entry.remove();
    }
  }
}

class _ConfettiParticle {
  final double startX;
  final double delay;
  final double fallDuration;
  final double drift;
  final double rotationSpeed;
  final Color color;
  final double size;

  _ConfettiParticle({
    required this.startX,
    required this.delay,
    required this.fallDuration,
    required this.drift,
    required this.rotationSpeed,
    required this.color,
    required this.size,
  });
}

const _confettiColors = [
  Color(0xFF22C55E),
  Color(0xFFF59E0B),
  Color(0xFF3B82F6),
  Color(0xFFEC4899),
  Color(0xFFA855F7),
];

class _FullScreenConfetti extends StatefulWidget {
  const _FullScreenConfetti();

  @override
  State<_FullScreenConfetti> createState() => _FullScreenConfettiState();
}

class _FullScreenConfettiState extends State<_FullScreenConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiParticle> _particles;

  @override
  void initState() {
    super.initState();
    final rand = Random();
    _particles = List.generate(140, (_) {
      return _ConfettiParticle(
        startX: rand.nextDouble(),
        delay: rand.nextDouble() * 0.3,
        fallDuration: 0.7 + rand.nextDouble() * 0.3,
        drift: (rand.nextDouble() - 0.5) * 0.5,
        rotationSpeed: (rand.nextDouble() - 0.5) * 10,
        color: _confettiColors[rand.nextInt(_confettiColors.length)],
        size: 6 + rand.nextDouble() * 6,
      );
    });
    // Particles need up to delay(0.3) + fallDuration(1.0) = 1.3 "progress"
    // units to finish falling and fade out — upperBound must cover that or
    // the slowest particles freeze mid-fall, fully opaque, once forward()
    // completes at the default upperBound of 1.0.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
      upperBound: 1.3,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, child) => CustomPaint(
            painter: _ConfettiPainter(
              particles: _particles,
              progress: _controller.value,
            ),
          ),
        ),
      ),
    );
  }
}

class _CelebrationCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;

  const _CelebrationCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A2236) : Colors.white;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 42),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: onSurface,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kSub, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles) {
      final localProgress =
          ((progress - p.delay) / p.fallDuration).clamp(0.0, 1.0);
      if (localProgress <= 0) continue;
      final dx = p.startX * size.width +
          sin(localProgress * pi * 2) * p.drift * size.width;
      final dy = localProgress * (size.height + 40) - 20;
      final opacity = localProgress > 0.85 ? (1 - localProgress) / 0.15 : 1.0;
      paint.color = p.color.withValues(alpha: opacity.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(localProgress * p.rotationSpeed * pi);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}
