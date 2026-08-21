import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'demo_theme.dart';

/// Visual fork of the real `AvailabilityCard` (Active Mode toggle). The
/// production widget is wrapped in a `TutorialAnchor` tied to the real,
/// app-wide tutorial system — reused here it would fight over the same
/// anchor id with the real worker dashboard. This redraws the same look
/// with a self-contained toggle that flips on its own after [flipAfter].
class DemoAvailabilityCard extends StatefulWidget {
  final bool initiallyOnline;
  final Duration? flipAfter;

  const DemoAvailabilityCard({
    super.key,
    this.initiallyOnline = false,
    this.flipAfter,
  });

  @override
  State<DemoAvailabilityCard> createState() => _DemoAvailabilityCardState();
}

class _DemoAvailabilityCardState extends State<DemoAvailabilityCard> {
  late bool _isOnline = widget.initiallyOnline;
  Timer? _flipTimer;

  @override
  void initState() {
    super.initState();
    final delay = widget.flipAfter;
    if (delay != null) {
      _flipTimer = Timer(delay, () {
        if (mounted) setState(() => _isOnline = !_isOnline);
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
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _isOnline ? const Color(0xFF22C55E) : dMuted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Active Mode',
                  style: TextStyle(
                    color: dTitle,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isOnline
                      ? 'Online and available for work'
                      : 'Offline — hosts can\'t see you as available',
                  style: const TextStyle(color: dBody, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(value: _isOnline, onChanged: (_) {}, activeThumbColor: kGold),
        ],
      ),
    );
  }
}
