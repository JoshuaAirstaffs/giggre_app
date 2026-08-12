import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../mock/mock_worker.dart';
import 'demo_theme.dart';

/// Reusable "nearby worker" row for the demo — shows the sort of factors a
/// host might see when a Quick/Open Gig looks for a match (distance, Active
/// Mode, Quick Gigs availability, performance). These are illustrative mock
/// values, not a claim about the exact production matching algorithm.
class DemoWorkerTile extends StatelessWidget {
  final MockWorkerData worker;
  final bool selected;
  final String? trailingLabel;

  const DemoWorkerTile({
    super.key,
    required this.worker,
    this.selected = false,
    this.trailingLabel,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? kGold : dBorder,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                worker.name.isNotEmpty ? worker.name[0] : '?',
                style: const TextStyle(
                  color: kGold,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  worker.name,
                  style: const TextStyle(
                    color: dTitle,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _chip('${worker.distanceMiles} mi', Icons.near_me_rounded),
                    if (worker.activeMode)
                      _chip('Active', Icons.circle, color: const Color(0xFF22C55E)),
                    if (worker.quickGigsOn)
                      _chip('Quick Gigs', Icons.flash_on_rounded),
                    if (worker.performance.isNotEmpty)
                      _chip(worker.performance, Icons.star_rounded),
                  ],
                ),
              ],
            ),
          ),
          if (trailingLabel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                trailingLabel!,
                style: const TextStyle(
                  color: kGold,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon, {Color color = dBody}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: color, fontSize: 10.5)),
      ],
    );
  }
}
