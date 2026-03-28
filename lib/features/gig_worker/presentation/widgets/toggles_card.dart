import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Toggles Card — Available for Gigs + Auto Accept switches
// ─────────────────────────────────────────────────────────────────────────────
class TogglesCard extends StatelessWidget {
  final bool availableForGigs;
  final bool autoAccept;
  final ValueChanged<bool> onAvailableChanged;
  final ValueChanged<bool> onAutoAcceptChanged;

  const TogglesCard({
    super.key,
    required this.availableForGigs,
    required this.autoAccept,
    required this.onAvailableChanged,
    required this.onAutoAcceptChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final divider = Theme.of(context).dividerColor;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider),
      ),
      child: Column(
        children: [
          _ToggleRow(
            icon: Icons.circle_rounded,
            iconColor: availableForGigs ? const Color(0xFF22C55E) : kSub,
            label: 'Available for Gigs',
            subtitle: availableForGigs
                ? 'You appear online to hosts'
                : 'You are hidden from hosts',
            value: availableForGigs,
            activeColor: const Color(0xFF22C55E),
            onChanged: onAvailableChanged,
          ),
          Divider(height: 1, color: divider, indent: 56),
          _ToggleRow(
            icon: Icons.bolt_rounded,
            iconColor: autoAccept ? kAmber : kSub,
            label: 'Auto Accept',
            subtitle: autoAccept
                ? 'Gigs matching your skills are auto-accepted'
                : 'You manually review each gig offer',
            value: autoAccept,
            activeColor: kAmber,
            onChanged: onAutoAcceptChanged,
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(color: kSub, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: activeColor,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}
