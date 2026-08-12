import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'demo_theme.dart';

/// Animated "Gig Host ↔ Gig Worker" connector — two role cards with a row
/// of dots pulsing between them to visualize gigs flowing from one side of
/// the marketplace to the other. Shared by the compact hub hero and the
/// full-screen "What is Giggre?" slideshow.
class DemoHostWorkerConnector extends StatefulWidget {
  final double scale;
  const DemoHostWorkerConnector({super.key, this.scale = 1.0});

  @override
  State<DemoHostWorkerConnector> createState() => _DemoHostWorkerConnectorState();
}

class _DemoHostWorkerConnectorState extends State<DemoHostWorkerConnector>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DemoRoleCard(
            icon: Icons.home_work_outlined,
            color: kBlue,
            title: 'Gig Host',
            description: 'Post work and get it done by a nearby worker.',
            scale: scale,
          ),
        ),
        SizedBox(
          width: 46 * scale,
          height: 68 * scale,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final t = (_controller.value - i * 0.2) % 1.0;
                  final opacity = (1 - (t * 2 - 1).abs()).clamp(0.15, 1.0);
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2 * scale),
                    child: Opacity(
                      opacity: opacity,
                      child: Container(
                        width: 6 * scale,
                        height: 6 * scale,
                        decoration: const BoxDecoration(
                          color: kGold,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ),
        Expanded(
          child: DemoRoleCard(
            icon: Icons.construction_rounded,
            color: kGold,
            title: 'Gig Worker',
            description: 'Find gigs that match your skills and get paid.',
            scale: scale,
          ),
        ),
      ],
    );
  }
}

class DemoRoleCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final double scale;

  const DemoRoleCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 44 * scale,
          height: 44 * scale,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22 * scale),
        ),
        SizedBox(height: 8 * scale),
        Text(
          title,
          style: TextStyle(
            color: dTitle,
            fontSize: 13 * scale,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 4 * scale),
        Text(
          description,
          textAlign: TextAlign.center,
          style: TextStyle(color: dBody, fontSize: 10.5 * scale, height: 1.3),
        ),
      ],
    );
  }
}
