import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Three separate cards matching the dashboard redesign mockup:
//  AvailabilityCard (rendered by the caller so it can overlap the header),
//  EarningsSummaryCard, and WorkPreferencesCard (Quick Gigs + Auto Accept).
//  Replaces the old _AvailabilityHeroCard / EarningsCard / TogglesCard.
// ─────────────────────────────────────────────────────────────────────────────
class AvailabilityCard extends StatelessWidget {
  final bool isOnline;
  final ValueChanged<bool> onChanged;
  final String isVerified;
  final VoidCallback onVerificationRequired;

  const AvailabilityCard({
    super.key,
    required this.isOnline,
    required this.onChanged,
    required this.isVerified,
    required this.onVerificationRequired,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isOnline ? const Color(0xFF2BB673) : kSub,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isOnline
                            ? "You're online · available for gigs"
                            : "You're offline",
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isOnline
                      ? 'Hosts nearby can see and offer you gigs'
                      : "You're hidden from hosts",
                  style: const TextStyle(color: kSub, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Transform.scale(
            scale: 0.75,
            child: Switch(
              value: isOnline,
              onChanged: (v) {
                if (isVerified == 'verified') {
                  onChanged(v);
                } else {
                  onVerificationRequired();
                }
              },
              activeThumbColor: const Color(0xFF2BB673),
            ),
          ),
        ],
      ),
    );
  }
}

class EarningsSummaryCard extends StatelessWidget {
  final Map<String, double> totalByCurrency;
  final Map<String, double> weeklyByCurrency;
  final int completedGigs;

  const EarningsSummaryCard({
    super.key,
    required this.totalByCurrency,
    required this.weeklyByCurrency,
    required this.completedGigs,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final entries = totalByCurrency.isEmpty
        ? [const MapEntry('PHP', 0.0)]
        : (totalByCurrency.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key)));
    final primary = entries.first;
    final weeklyAmount = weeklyByCurrency[primary.key] ?? 0;
    final subtitle =
        '$completedGigs gigs completed · '
        '${CurrencyFormatter.format(weeklyAmount, primary.key)} this week';

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Earned so far',
            style: TextStyle(
              color: kSub,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            CurrencyFormatter.format(primary.value, primary.key),
            style: TextStyle(
              color: onSurface,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: kSub, fontSize: 12)),
          if (entries.length > 1)
            for (final e in entries.skip(1))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+ ${CurrencyFormatter.format(e.value, e.key)}',
                  style: const TextStyle(color: kSub, fontSize: 12),
                ),
              ),
        ],
      ),
    );
  }
}

class WorkPreferencesCard extends StatelessWidget {
  final bool seekingQuickGigs;
  final ValueChanged<bool> onQuickGigsChanged;
  final bool autoAccept;
  final ValueChanged<bool> onAutoAcceptChanged;
  final String isVerified;
  final VoidCallback onVerificationRequired;

  const WorkPreferencesCard({
    super.key,
    required this.seekingQuickGigs,
    required this.onQuickGigsChanged,
    required this.autoAccept,
    required this.onAutoAcceptChanged,
    required this.isVerified,
    required this.onVerificationRequired,
  });

  void _guarded(ValueChanged<bool> onChanged, bool value) {
    if (isVerified == 'verified') {
      onChanged(value);
    } else {
      onVerificationRequired();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).dividerColor;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dividerColor),
      ),
      child: Column(
        children: [
          _ToggleRow(
            label: 'Quick Gigs',
            description: 'Get instant offers while online',
            value: seekingQuickGigs,
            activeColor: const Color(0xFF2BB673),
            onChanged: (v) => _guarded(onQuickGigsChanged, v),
          ),
          Divider(height: 1, color: dividerColor),
          _ToggleRow(
            label: 'Auto Accept',
            description: 'Auto-book gigs matching your skills',
            value: autoAccept,
            activeColor: kGold,
            onChanged: (v) => _guarded(onAutoAcceptChanged, v),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String description;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.description,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(color: kSub, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Transform.scale(
            scale: 0.75,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: activeColor,
            ),
          ),
        ],
      ),
    );
  }
}
