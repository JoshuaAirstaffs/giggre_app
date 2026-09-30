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

  IconData get _gigTypeIcon {
    switch (gig.gigType) {
      case 'quick':
        return Icons.bolt_rounded;
      case 'open':
        return Icons.work_outline_rounded;
      case 'offered':
        return Icons.handshake_outlined;
      default:
        return Icons.work_outline_rounded;
    }
  }

  // Hourly gigs show the per-hour rate; flat gigs show the flat amount as
  // a per-day figure — matches the "/hr" vs "/day" convention used
  // everywhere else pay is displayed in the app.
  String get _payLabel {
    if (gig.payType == 'hourly' && gig.hourlyRate != null) {
      return '${CurrencyFormatter.format(gig.hourlyRate!, gig.currencyCode)}/hr';
    }
    return '${CurrencyFormatter.format(gig.budget, gig.currencyCode)}/day';
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final divider = Theme.of(context).dividerColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const green = Color(0xFF22C55E);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Success icon + checkmark badge ───────────────────────────
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_gigTypeIcon, color: green, size: 28),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: green,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).cardColor,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Heading ────────────────────────────────────────────────
            const Text(
              'ASSIGNED',
              style: TextStyle(
                color: green,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'You got the gig!',
              style: TextStyle(
                color: onSurface,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Everything is confirmed. Here's what you need before you head out.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: kSub, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 18),
            Divider(color: divider, height: 1),
            const SizedBox(height: 16),

            // ── Shift + Pay ────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SHIFT',
                        style: TextStyle(
                          color: kSub,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        gig.title,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            color: kSub,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              gig.hostName.isNotEmpty ? gig.hostName : 'Host',
                              style: const TextStyle(
                                color: kSub,
                                fontSize: 12.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (gig.isMultiWorker) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.groups_rounded,
                              color: kSub,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${gig.openSlots} of ${gig.workerSlots} spots open',
                              style: const TextStyle(
                                color: kSub,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'PAY',
                      style: TextStyle(
                        color: kSub,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _payLabel,
                      style: const TextStyle(
                        color: green,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: divider, height: 1),
            const SizedBox(height: 16),

            // ── Location ───────────────────────────────────────────────
            if (gig.address.isNotEmpty) ...[
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'LOCATION',
                value: gig.address,
                accent: green,
                isDark: isDark,
              ),
              const SizedBox(height: 14),
            ],

            // ── Schedule ───────────────────────────────────────────────
            if (gig.scheduledDate != null)
              _InfoRow(
                icon: Icons.calendar_today_rounded,
                label: 'SCHEDULE',
                value: DateFormat(
                  'EEE, MMM d · h:mm a',
                ).format(gig.scheduledDate!),
                accent: green,
                isDark: isDark,
              ),
            const SizedBox(height: 18),

            // ── Info box ───────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: green.withValues(alpha: isDark ? 0.12 : 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: green, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Head to the gig location and get ready to start working.',
                      style: TextStyle(
                        color: kSub,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Go to Location button ─────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onGoToLocation,
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text(
                  'Go to location',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 6),

            // ── Dismiss link ───────────────────────────────────────────
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final bool isDark;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: isDark ? 0.16 : 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: accent, size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: kSub,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: onSurface,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
