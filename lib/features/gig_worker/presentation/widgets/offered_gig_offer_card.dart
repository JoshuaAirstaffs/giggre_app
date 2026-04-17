import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import 'gig_map_section.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Offered Gig Offer Card — shown when a host directly offers a gig to the
//  worker.  Purple-themed (no countdown; the worker can take time to decide).
// ─────────────────────────────────────────────────────────────────────────────
class OfferedGigOfferCard extends StatelessWidget {
  final GigMarkerData gig;
  final String description;
  final String skillRequired;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const OfferedGigOfferCard({
    super.key,
    required this.gig,
    required this.description,
    required this.skillRequired,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final divider = Theme.of(context).dividerColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const purple = Color(0xFF8B5CF6);
    const green = Color(0xFF22C55E);

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: purple.withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: purple.withValues(alpha: isDark ? 0.2 : 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: purple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.send_rounded, color: purple, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gig Offer for You!',
                      style: TextStyle(
                        color: purple,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      gig.title,
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: purple.withValues(alpha: 0.35)),
                ),
                child: const Text(
                  'Offered',
                  style: TextStyle(
                    color: purple,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: divider),
          const SizedBox(height: 6),

          // ── Host & budget ────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, color: kSub, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  gig.hostName.isNotEmpty ? gig.hostName : 'Host',
                  style: const TextStyle(color: kSub, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.attach_money_rounded, color: purple, size: 14),
              Text(
                '₱${gig.budget.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: purple,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          // ── Skill & level ────────────────────────────────────────────────
          if (skillRequired.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.build_outlined, color: kSub, size: 14),
                const SizedBox(width: 6),
                Text(skillRequired,
                    style: const TextStyle(color: kSub, fontSize: 12)),
                if (gig.experienceLevel.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      gig.experienceLevel,
                      style: const TextStyle(
                        color: purple,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],

          // ── Location ─────────────────────────────────────────────────────
          if (gig.address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: kSub, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    gig.address,
                    style: const TextStyle(color: kSub, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          // ── Description preview ──────────────────────────────────────────
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.7),
                fontSize: 12,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: 14),

          // ── Actions ──────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kSub,
                    side: BorderSide(color: divider),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Decline',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Accept Offer',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
