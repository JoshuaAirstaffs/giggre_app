import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Shared small widgets for the worker screen
// ─────────────────────────────────────────────────────────────────────────────

class ToolchestCard extends StatelessWidget {
  final List<String> skills;
  final VoidCallback onTap;
  const ToolchestCard({super.key, required this.skills, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final divider = Theme.of(context).dividerColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final preview = skills.take(3).join(', ');
    final extra = skills.length > 3 ? ' +${skills.length - 3} more' : '';
    final subtitle = skills.isNotEmpty
        ? '$preview$extra'
        : 'Add your skills, tools, and certifications';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: divider),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kAmber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.construction_rounded,
                  color: kAmber, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('My Toolchest',
                          style: TextStyle(
                              color: onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      if (skills.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: kAmber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${skills.length}',
                            style: const TextStyle(
                              color: kAmber,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(color: kSub, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: kSub, size: 14),
          ],
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            color: kSub,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5),
      );
}

class MenuCard extends StatelessWidget {
  final List<Widget> children;
  const MenuCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(children: children),
    );
  }
}

class MenuRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;
  final VoidCallback onTap;
  final bool showArrow;

  const MenuRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.labelColor,
    this.showArrow = true,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    color: labelColor ?? onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
              ),
            ),
            if (showArrow)
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: kSub, size: 14),
          ],
        ),
      ),
    );
  }
}

class WorkerDivider extends StatelessWidget {
  const WorkerDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(
      height: 1,
      color: Theme.of(context).dividerColor,
      indent: 64);
}
