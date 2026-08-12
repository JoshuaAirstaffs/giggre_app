import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../widgets/demo_fade_in.dart';
import '../../widgets/demo_theme.dart';

/// Closing slide of the "What is Giggre?" explainer — points the viewer
/// back at the hub's Host/Worker demo list with a gently bouncing chevron.
class MockGetStartedScene extends StatelessWidget {
  const MockGetStartedScene({super.key});

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
                color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: Color(0xFF22C55E), size: 36),
            ),
            const SizedBox(height: 20),
            const Text(
              "That's Giggre in a nutshell",
              textAlign: TextAlign.center,
              style: TextStyle(color: dTitle, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            DemoFadeIn(
              delay: const Duration(milliseconds: 300),
              child: const Text(
                'Pick a Host or Worker demo below to see it in action.',
                textAlign: TextAlign.center,
                style: TextStyle(color: dBody, fontSize: 13, height: 1.4),
              ),
            ),
            const SizedBox(height: 20),
            const _BouncingChevron(),
          ],
        ),
      ),
    );
  }
}

class _BouncingChevron extends StatefulWidget {
  const _BouncingChevron();

  @override
  State<_BouncingChevron> createState() => _BouncingChevronState();
}

class _BouncingChevronState extends State<_BouncingChevron>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  late final Animation<double> _offset = Tween<double>(begin: 0, end: 8).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (context, _) => Transform.translate(
        offset: Offset(0, _offset.value),
        child: const Icon(Icons.keyboard_arrow_down_rounded, color: kGold, size: 32),
      ),
    );
  }
}
