import 'package:flutter/material.dart';

/// Worker ⇄ Host switch shown in both dashboard headers (Option B of the
/// mode-switch mockup): a segmented toggle with both modes always visible —
/// "Gig Worker" and "Gig Host" — and the current one
/// highlighted in white. Tapping the other side calls [onSwitch].
class ModeSwitch extends StatelessWidget {
  /// true on the Gig Host dashboard, false on the Gig Worker dashboard.
  final bool isHost;
  final VoidCallback onSwitch;

  const ModeSwitch({super.key, required this.isHost, required this.onSwitch});

  // Text/icon color of the highlighted side — the header's own color, dark
  // enough to read on white.
  static const _hostText = Color(0xFFB06E00);
  static const _workerText = Color(0xFF1F4D80);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Mode',
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            _segment(
              label: 'Gig Worker',
              icon: Icons.person_search_rounded,
              selected: !isHost,
              selectedColor: _workerText,
              tooltip: 'Switch to Gig Worker',
            ),
            const SizedBox(width: 4),
            _segment(
              label: 'Gig Host',
              icon: Icons.work_outline_rounded,
              selected: isHost,
              selectedColor: _hostText,
              tooltip: 'Switch to Gig Host',
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment({
    required String label,
    required IconData icon,
    required bool selected,
    required Color selectedColor,
    required String tooltip,
  }) {
    final fg = selected ? selectedColor : Colors.white;
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: selected
            ? child
            : Tooltip(
                message: tooltip,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onSwitch,
                    borderRadius: BorderRadius.circular(18),
                    child: child,
                  ),
                ),
              ),
      ),
    );
  }
}
