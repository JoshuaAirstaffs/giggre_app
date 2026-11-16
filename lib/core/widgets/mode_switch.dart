import 'package:flutter/material.dart';

/// Worker ⇄ Host switch in both dashboard headers (Option 1 of the compact
/// mockup): a mini two-sided toggle in the title row. The current mode shows
/// its icon and name on a white thumb; the other side is just its icon —
/// person (Gig Worker) or briefcase (Gig Host). Tapping the other side
/// switches. Fits the one-row header (~110 px wide, 34 px tall).
class ModeSwitch extends StatelessWidget {
  /// true on the Gig Host dashboard, false on the Gig Worker dashboard.
  final bool isHost;
  final VoidCallback onSwitch;

  const ModeSwitch({super.key, required this.isHost, required this.onSwitch});

  static const _workerText = Color(0xFF1F4D80); // worker blue, dark enough on white
  static const _hostText = Color(0xFFB06E00); // host gold, dark enough on white

  @override
  Widget build(BuildContext context) {
    final worker = _side(
      icon: Icons.person_outline_rounded,
      label: 'Worker',
      selected: !isHost,
      color: _workerText,
      tooltip: 'Switch to Gig Worker',
    );
    final host = _side(
      icon: Icons.work_outline_rounded,
      label: 'Host',
      selected: isHost,
      color: _hostText,
      tooltip: 'Switch to Gig Host',
    );
    return Semantics(
      container: true,
      label: isHost ? 'Mode: Gig Host' : 'Mode: Gig Worker',
      child: Container(
        height: 34,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [worker, const SizedBox(width: 2), host],
        ),
      ),
    );
  }

  Widget _side({
    required IconData icon,
    required String label,
    required bool selected,
    required Color color,
    required String tooltip,
  }) {
    if (selected) {
      // Current mode: white thumb with icon + name. Not tappable.
      return Semantics(
        selected: true,
        label: 'Gig $label (current)',
        excludeSemantics: true,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    }
    // Other mode: icon only — tap to switch.
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onSwitch,
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 34,
              height: 28,
              child: Icon(icon, size: 16, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
