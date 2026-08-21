import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../mock/mock_gig.dart';
import 'demo_theme.dart';

/// Visual fork of the host's gig list card, simplified for the demo. The
/// real `HostGigCard` wraps itself in a `TutorialAnchor` and pushes a live
/// Firestore-backed detail sheet on tap, so this redraws only what the
/// demo needs: a title/pay/status summary with an animated status badge,
/// using the same status labels/colors as `HostGigCard._statusMeta`.
class DemoHostGigStatusCard extends StatelessWidget {
  final MockGigData gig;
  final String status;
  final Color statusColor;
  final String? subline;

  const DemoHostGigStatusCard({
    super.key,
    required this.gig,
    required this.status,
    this.statusColor = kAmber,
    this.subline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: dBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  gig.title,
                  style: const TextStyle(
                    color: dTitle,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    status,
                    key: ValueKey(status),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (subline != null) ...[
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                subline!,
                key: ValueKey(subline),
                style: const TextStyle(
                  color: dMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            gig.description,
            style: const TextStyle(color: dBody, fontSize: 12.5, height: 1.4),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.payments_outlined, size: 14, color: kGold),
              const SizedBox(width: 6),
              Text(
                '\$${gig.payment}',
                style: const TextStyle(
                  color: kGold,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 14),
              const Icon(Icons.location_on_outlined, size: 14, color: dMuted),
              const SizedBox(width: 4),
              Text(
                gig.location,
                style: const TextStyle(color: dMuted, fontSize: 12.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
