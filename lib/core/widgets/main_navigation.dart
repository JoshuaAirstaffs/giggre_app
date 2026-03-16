import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/playground/presentation/playground_screen.dart';

class MainNavigation extends StatelessWidget {
  const MainNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _GiggreLogoSmall(),
            const SizedBox(height: 24),
            const Text(
              'Welcome to Giggre!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Home screen coming soon.',
              style: TextStyle(color: kSub, fontSize: 14),
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlaygroundScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kAmber.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.science_rounded, color: kAmber, size: 20),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Flutter Playground',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Widgets · Animations · State · Layout',
                          style: TextStyle(color: kSub, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.arrow_forward_ios_rounded, color: kSub, size: 14),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GiggreLogoSmall extends StatelessWidget {
  const _GiggreLogoSmall();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: kBlue.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: kBlue.withValues(alpha: 0.4)),
          ),
          child: const Icon(Icons.person_rounded, color: kBlue, size: 20),
        ),
        const SizedBox(width: 4),
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: kAmber.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: kAmber.withValues(alpha: 0.4)),
          ),
          child: const Icon(Icons.person_rounded, color: kAmber, size: 20),
        ),
        const SizedBox(width: 10),
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
            children: [
              TextSpan(text: 'gi', style: TextStyle(color: kBlue)),
              TextSpan(text: 'gg', style: TextStyle(color: kAmber)),
              TextSpan(text: 're', style: TextStyle(color: kBlue)),
            ],
          ),
        ),
      ],
    );
  }
}