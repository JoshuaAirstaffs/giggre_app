import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';

class EarningsCard extends StatelessWidget {
  final Map<String, double> totalByCurrency;
  final Map<String, double> weeklyByCurrency;
  final int completedGigs;

  const EarningsCard({
    super.key,
    required this.totalByCurrency,
    required this.weeklyByCurrency,
    required this.completedGigs,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _EarningsStatCard(
            totalByCurrency: totalByCurrency,
            weeklyByCurrency: weeklyByCurrency,
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

// Shows one total+weekly row per currency code.
class _EarningsStatCard extends StatelessWidget {
  final Map<String, double> totalByCurrency;
  final Map<String, double> weeklyByCurrency;

  const _EarningsStatCard({
    required this.totalByCurrency,
    required this.weeklyByCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final entries = totalByCurrency.isEmpty
        ? [const MapEntry('PHP', 0.0)]
        : totalByCurrency.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));

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
          const Text(
            'Total earned',
            style: TextStyle(
              color: kSub,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          for (final e in entries) ...[
            Text(
              CurrencyFormatter.format(e.value, e.key),
              style: const TextStyle(
                color: kGold,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${CurrencyFormatter.format(weeklyByCurrency[e.key] ?? 0, e.key)} this week',
              style: const TextStyle(color: Color(0xFF2BB673), fontSize: 12),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
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
