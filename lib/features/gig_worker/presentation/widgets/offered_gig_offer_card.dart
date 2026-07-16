import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
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

  static const _purple = Color(0xFF8B5CF6);
  static const _green = Color(0xFF22C55E);

  String _formatSchedule(DateTime date) {
    return DateFormat('EEE, MMM d · h:mm a').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final divider = Theme.of(context).dividerColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final chips = <_InfoChip>[
      _InfoChip(
        Icons.attach_money_rounded,
        'PAY',
        CurrencyFormatter.format(gig.budget, gig.currencyCode),
      ),
      _InfoChip(
        Icons.event_rounded,
        'SCHEDULE',
        gig.scheduledDate != null
            ? _formatSchedule(gig.scheduledDate!)
            : 'Flexible',
      ),
      if (skillRequired.isNotEmpty)
        _InfoChip(Icons.build_outlined, 'SKILL', skillRequired),
      if (gig.address.isNotEmpty)
        _InfoChip(
          Icons.location_on_outlined,
          'LOCATION',
          gig.address,
          allowWrap: true,
        ),
    ];

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _purple.withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _purple.withValues(alpha: isDark ? 0.2 : 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.send_rounded, color: _purple, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gig Offer for You!',
                      style: TextStyle(
                        color: _purple,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (skillRequired.isNotEmpty &&
                            gig.experienceLevel.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _purple.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              gig.experienceLevel,
                              style: const TextStyle(
                                color: _purple,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            gig.title,
                            style: TextStyle(
                              color: onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.person_outline_rounded,
                          color: kSub,
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            gig.hostName.isNotEmpty ? gig.hostName : 'Host',
                            style: const TextStyle(color: kSub, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _purple.withValues(alpha: 0.35)),
                ),
                child: const Text(
                  'Offered',
                  style: TextStyle(
                    color: _purple,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Info grid: pay / schedule / skill / location ──────────────
          _ChipGrid(chips: chips, isDark: isDark, onSurface: onSurface),

          // ── Description preview ────────────────────────────────────
          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.grey.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                description,
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.7),
                  fontSize: 12,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          const SizedBox(height: 14),
          Divider(color: divider, height: 1),
          const SizedBox(height: 14),

          // ── Actions ─────────────────────────────────────────────────
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
                    backgroundColor: _green,
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

class _InfoChip {
  final IconData icon;
  final String label;
  final String value;
  // Address is the one value long/variable enough that truncating it would
  // hide real information the worker needs (which street, which building) —
  // every other chip's value is short by nature (a price, a date, a skill).
  final bool allowWrap;
  const _InfoChip(this.icon, this.label, this.value, {this.allowWrap = false});
}

class _ChipGrid extends StatelessWidget {
  final List<_InfoChip> chips;
  final bool isDark;
  final Color onSurface;

  const _ChipGrid({
    required this.chips,
    required this.isDark,
    required this.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < chips.length; i++) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(_buildCell(chips[i]));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _buildCell(_InfoChip chip) {
    const purple = OfferedGigOfferCard._purple;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: purple.withValues(alpha: isDark ? 0.1 : 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(chip.icon, size: 14, color: purple),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chip.label,
                  style: const TextStyle(
                    color: kSub,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  chip.value,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: chip.allowWrap ? null : 1,
                  overflow:
                      chip.allowWrap ? TextOverflow.visible : TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
