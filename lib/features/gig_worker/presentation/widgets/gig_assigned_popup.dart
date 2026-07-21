import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import 'gig_map_section.dart';

class GigAssignedDialog extends StatelessWidget {
  final GigMarkerData gig;
  final VoidCallback onGoToLocation;

  const GigAssignedDialog({
    super.key,
    required this.gig,
    required this.onGoToLocation,
  });

  String get _gigTypeLabel {
    switch (gig.gigType) {
      case 'quick':
        return 'Quick Gig';
      case 'open':
        return 'Open Gig';
      case 'offered':
        return 'Offered Gig';
      default:
        return 'Gig';
    }
  }

  IconData get _gigTypeIcon {
    switch (gig.gigType) {
      case 'quick':
        return Icons.flash_on_rounded;
      case 'open':
        return Icons.work_outline_rounded;
      case 'offered':
        return Icons.send_rounded;
      default:
        return Icons.check_circle_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final divider = Theme.of(context).dividerColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const green = Color(0xFF22C55E);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Success icon ────────────────────────────────────────────────
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: green.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(_gigTypeIcon, color: green, size: 30),
            ),
            const SizedBox(height: 16),

            // ── Heading ──────────────────────────────────────────────────────
            const Text(
              'You\'re Assigned!',
              style: TextStyle(
                color: Color(0xFF22C55E),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _gigTypeLabel,
                style: const TextStyle(
                  color: Color(0xFF22C55E),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Divider(color: divider),
            const SizedBox(height: 12),

            // ── Gig details ──────────────────────────────────────────────────
            Text(
              gig.title,
              style: TextStyle(
                color: onSurface,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.person_outline_rounded,
              value: gig.hostName.isNotEmpty ? gig.hostName : 'Host',
            ),
            const SizedBox(height: 6),
            _DetailRow(
              // icon: Icons.attach_money_rounded,
              value: CurrencyFormatter.format(gig.budget, gig.currencyCode),
              valueColor: green,
            ),
            if (gig.address.isNotEmpty) ...[
              const SizedBox(height: 6),
              _DetailRow(
                icon: Icons.location_on_outlined,
                value: gig.address,
              ),
            ],
            if (gig.scheduledDate != null) ...[
              const SizedBox(height: 6),
              _DetailRow(
                icon: Icons.calendar_today_rounded,
                value: DateFormat('EEE, MMM d • h:mm a')
                    .format(gig.scheduledDate!),
              ),
            ],
            const SizedBox(height: 14),

            // ── Info box ────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: green.withValues(alpha: isDark ? 0.1 : 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Color(0xFF22C55E), size: 14),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Head to the gig location and get ready to start working.',
                      style: TextStyle(color: kSub, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Go to Location button ────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onGoToLocation,
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text(
                  'Go to Location',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Dismiss link ────────────────────────────────────────────────
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Dismiss',
                style: TextStyle(color: kSub, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData? icon;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    this.icon,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, color: kSub, size: 14),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? kSub,
              fontSize: 13,
              fontWeight:
                  valueColor != null ? FontWeight.bold : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
