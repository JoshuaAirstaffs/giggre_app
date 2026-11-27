import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The "Drop-off point" card on the post-gig forms, shown under the pick-up
/// location for delivery and errand gigs (see core/utils/gig_route.dart).
/// Tapping it opens the screen's own map picker via [onPick].
class DropoffPointField extends StatelessWidget {
  const DropoffPointField({
    super.key,
    required this.address,
    required this.hasPoint,
    required this.onPick,
    this.distanceKm,
    this.showError = false,
  });

  final String address;
  final bool hasPoint;
  final double? distanceKm;
  final bool showError;
  final VoidCallback onPick;

  static const accent = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final error = showError && !hasPoint;
    final color = error ? Colors.redAccent : accent;

    return Semantics(
      button: true,
      label: hasPoint ? 'Drop-off point: $address. Tap to change' : 'Choose a drop-off point',
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: error
                  ? Colors.redAccent.withValues(alpha: 0.5)
                  : hasPoint
                      ? accent.withValues(alpha: 0.5)
                      : Theme.of(context).dividerColor,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.flag_rounded, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasPoint
                          ? (address.isNotEmpty ? address : 'Drop-off point set')
                          : 'Choose where it goes',
                      style: TextStyle(
                        color: hasPoint ? onSurface : (error ? Colors.redAccent : kSub),
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      error
                          ? 'A drop-off point is required for this skill'
                          : hasPoint
                              ? (distanceKm != null
                                  ? '${distanceKm!.toStringAsFixed(1)} km from pick-up (straight line)'
                                  : 'Map-selected drop-off')
                              : 'Tap to select on the map',
                      style: TextStyle(
                        color: error ? Colors.redAccent : (hasPoint ? accent : kSub),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                hasPoint ? Icons.edit_location_alt_outlined : Icons.chevron_right_rounded,
                color: kSub,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
