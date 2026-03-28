import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Earnings Card
// ─────────────────────────────────────────────────────────────────────────────
class EarningsCard extends StatelessWidget {
  final double totalEarnings;
  final double weeklyEarnings;
  final int completedGigs;

  const EarningsCard({
    super.key,
    required this.totalEarnings,
    required this.weeklyEarnings,
    required this.completedGigs,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final divider = Theme.of(context).dividerColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    const green = Color(0xFF22C55E);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: green,
                    size: 20),
              ),
              const SizedBox(width: 10),
              Text('Earnings',
                  style: TextStyle(
                      color: onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _EarningsStat(
                  label: 'This Week',
                  value: '₱${weeklyEarnings.toStringAsFixed(0)}',
                  color: green,
                ),
              ),
              Container(width: 1, height: 40, color: divider),
              Expanded(
                child: _EarningsStat(
                  label: 'Total Earned',
                  value: '₱${totalEarnings.toStringAsFixed(0)}',
                  color: kAmber,
                ),
              ),
              Container(width: 1, height: 40, color: divider),
              Expanded(
                child: _EarningsStat(
                  label: 'Completed',
                  value: '$completedGigs gigs',
                  color: kBlue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EarningsStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _EarningsStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: kSub, fontSize: 11)),
        ],
      );
}
