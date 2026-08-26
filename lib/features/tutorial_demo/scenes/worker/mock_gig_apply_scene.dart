import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../mock/mock_gig.dart';
import '../../mock/mock_worker.dart';
import '../../widgets/demo_fade_in.dart';
import '../../widgets/demo_pulse_highlight.dart';
import '../../widgets/demo_theme.dart';

/// Open Gig detail as seen by a worker — mirrors the real gig-detail sheet
/// (`gig_map_section.dart`) exactly: a "SKILLS NEEDED" section with a
/// green chip when the worker's verified skill matches (grey when it
/// doesn't) plus a red "Missing skill" banner, and a "Take Gig" button
/// that's always visible but only enabled once the skill matches — taking
/// it flips the button to "Pass" (never "Apply" / "Application Submitted",
/// which aren't real Giggre terms).
class MockGigApplyScene extends StatelessWidget {
  final MockGigData gig;
  final MockWorkerData worker;
  final bool skillMatches;
  final bool applied;

  const MockGigApplyScene({
    super.key,
    required this.gig,
    required this.worker,
    required this.skillMatches,
    this.applied = false,
  });

  @override
  Widget build(BuildContext context) {
    final requiredSkill = gig.requiredSkill ?? '';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            gig.title,
            style: const TextStyle(
              color: dTitle,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            gig.description,
            style: const TextStyle(color: dBody, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _chip(Icons.payments_outlined, '\$${gig.payment}', kGold),
              const SizedBox(width: 10),
              _chip(Icons.near_me_rounded, '${gig.distanceMiles} mi', dBody),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'SKILLS NEEDED',
            style: TextStyle(
              color: dMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: skillMatches
                  ? const Color(0xFF2E9E6B).withValues(alpha: 0.12)
                  : dBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              requiredSkill,
              style: TextStyle(
                color: skillMatches ? const Color(0xFF2E9E6B) : dBody,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!skillMatches) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Colors.red, size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Missing skill: $requiredSkill',
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          DemoFadeIn(
            child: DemoTapPulse(
              delay: applied ? Duration.zero : const Duration(milliseconds: 900),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: skillMatches && !applied
                        ? const LinearGradient(
                            colors: [Color(0xFF2B6FB5), Color(0xFF1F4D80)],
                          )
                        : null,
                    color: skillMatches && !applied
                        ? null
                        : applied
                        ? Colors.redAccent.withValues(alpha: 0.08)
                        : dBg,
                    border: applied
                        ? Border.all(color: Colors.redAccent.withValues(alpha: 0.4))
                        : null,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Center(
                    child: Text(
                      applied ? 'Withdraw' : 'Take Gig',
                      style: TextStyle(
                        color: skillMatches && !applied
                            ? Colors.white
                            : applied
                            ? Colors.redAccent
                            : dMuted,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!applied) ...[
            const SizedBox(height: 10),
            const Text(
              "You can pass anytime before you're selected",
              textAlign: TextAlign.center,
              style: TextStyle(color: dMuted, fontSize: 10.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
