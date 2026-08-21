import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../mock/mock_skill.dart';
import '../../widgets/demo_fade_in.dart';
import '../../widgets/demo_theme.dart';

/// "Profile → Avatar → My Toolchest" breadcrumb, shown before the skills
/// list so the demo narrates the same navigation path the real app uses.
class MockToolchestEntryScene extends StatelessWidget {
  const MockToolchestEntryScene({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _step(Icons.person_outline_rounded, 'Profile'),
          _arrow(),
          _step(Icons.account_circle_outlined, 'Avatar'),
          _arrow(),
          _step(Icons.construction_rounded, 'My Toolchest', highlight: true),
        ],
      ),
    );
  }

  Widget _step(IconData icon, String label, {bool highlight = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? kGold.withValues(alpha: 0.15) : dCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlight ? kGold : dBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: highlight ? kGold : dBody, size: 22),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: highlight ? kGold : dTitle,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _arrow() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 2),
    child: Icon(Icons.chevron_right_rounded, color: dBody, size: 20),
  );
}

/// My Toolchest skills list ("My Skills" tab) — shows existing skills plus,
/// when adding a new one, its request status. Matches the real
/// `_SkillChip`'s look/labels exactly: an "Approved" badge (green check)
/// once an admin approves the request, "Pending" (amber) while it's
/// waiting — never "Verified" / "Pending Verification", which aren't the
/// real Giggre terms.
class MockToolchestSkillsScene extends StatelessWidget {
  final List<MockSkillData> skills;
  final MockSkillData? newSkill;

  const MockToolchestSkillsScene({
    super.key,
    required this.skills,
    this.newSkill,
  });

  @override
  Widget build(BuildContext context) {
    final all = [...skills, ?newSkill];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'My Toolchest',
            style: TextStyle(
              color: dTitle,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'My Skills',
            style: TextStyle(color: dMuted, fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < all.length; i++)
            DemoFadeIn(
              delay: Duration(milliseconds: 100 + i * 200),
              child: _skillRow(all[i]),
            ),
        ],
      ),
    );
  }

  Widget _skillRow(MockSkillData skill) {
    final approved = skill.status == 'approved';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: dCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kAmber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: kAmber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.construction_rounded, color: kAmber, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              skill.name,
              style: const TextStyle(
                color: dTitle,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: Container(
              key: ValueKey(skill.status),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: approved
                    ? const Color(0xFF22C55E).withValues(alpha: 0.12)
                    : kAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: approved
                      ? const Color(0xFF22C55E).withValues(alpha: 0.4)
                      : kAmber.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    approved ? Icons.check_circle_rounded : Icons.hourglass_empty_rounded,
                    color: approved ? const Color(0xFF22C55E) : kAmber,
                    size: 11,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    approved ? 'Approved' : 'Pending',
                    style: TextStyle(
                      color: approved ? const Color(0xFF22C55E) : kAmber,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
