import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _StatCard(
            label: 'Total earned',
            value: '₱${totalEarnings.toStringAsFixed(0)}',
            valueColor: kGold,
            subValue: '₱${weeklyEarnings.toStringAsFixed(0)} this week',
            subValueColor: const Color(0xFF2BB673),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Gigs completed',
            value: '$completedGigs',
            valueColor: kBlue,
            subValue: 'All time',
            subValueColor: kSub,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final String subValue;
  final Color subValueColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.subValue,
    required this.subValueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: kSub,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subValue,
            style: TextStyle(color: subValueColor, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
