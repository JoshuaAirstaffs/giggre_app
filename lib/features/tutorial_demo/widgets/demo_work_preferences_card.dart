import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'demo_theme.dart';

/// Visual fork of the real `WorkPreferencesCard` (Quick Gigs toggle). Same
/// reasoning as [DemoAvailabilityCard] — the production widget's toggle is
/// wrapped in a `TutorialAnchor` tied to the real, app-wide tutorial
/// system, so this redraws the look instead of reusing it directly.
class DemoWorkPreferencesCard extends StatefulWidget {
  final bool initiallyOn;
  final Duration? flipAfter;

  const DemoWorkPreferencesCard({
    super.key,
    this.initiallyOn = false,
    this.flipAfter,
  });

  @override
  State<DemoWorkPreferencesCard> createState() =>
      _DemoWorkPreferencesCardState();
}

class _DemoWorkPreferencesCardState extends State<DemoWorkPreferencesCard> {
  late bool _quickGigsOn = widget.initiallyOn;
  Timer? _flipTimer;

  @override
  void initState() {
    super.initState();
    final delay = widget.flipAfter;
    if (delay != null) {
      _flipTimer = Timer(delay, () {
        if (mounted) setState(() => _quickGigsOn = !_quickGigsOn);
      });
    }
  }

  @override
  void dispose() {
    _flipTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: dCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: kAmber.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.flash_on_rounded, color: kAmber, size: 18),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Quick Gigs',
              style: TextStyle(
                color: dTitle,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          Switch(
            value: _quickGigsOn,
            onChanged: (_) {},
            activeThumbColor: kGold,
          ),
        ],
      ),
    );
  }
}
