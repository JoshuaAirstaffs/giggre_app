import 'package:flutter/material.dart';

/// Worker ⇄ Host switch in both dashboard headers: a mini two-sided toggle
/// in the title row. The current mode shows its icon and name on a white
/// thumb; the other side is just its icon — person (Gig Worker) or briefcase
/// (Gig Host). Tapping the other side slides the thumb across and switches.
///
/// Always the same width (in both modes, mid-slide too), so nothing else in
/// the header moves when the mode changes.
class ModeSwitch extends StatefulWidget {
  /// true on the Gig Host dashboard, false on the Gig Worker dashboard.
  final bool isHost;
  final VoidCallback onSwitch;

  const ModeSwitch({super.key, required this.isHost, required this.onSwitch});

  static const double width = _kThumbW + _kIconW + _kPad * 2;
  static const double height = 34;

  @override
  State<ModeSwitch> createState() => _ModeSwitchState();
}

const double _kPad = 3;
const double _kThumbW = 78; // icon + "Worker" / "Host"
const double _kIconW = 34; // the other side's icon
const _kWorkerText = Color(0xFF1F4D80); // worker blue, dark enough on white
const _kHostText = Color(0xFFB06E00); // host gold, dark enough on white
const _kSlide = Duration(milliseconds: 240);

class _ModeSwitchState extends State<ModeSwitch> {
  // Where the thumb is drawn; flips at once on tap so it slides while the
  // dashboards cross-fade, then follows isHost.
  late bool _thumbHost = widget.isHost;
  // One rebuild with no animation (snapping the thumb back, see _tap).
  bool _instant = false;
  Duration get _d => _instant ? Duration.zero : _kSlide;

  @override
  void didUpdateWidget(ModeSwitch old) {
    super.didUpdateWidget(old);
    if (old.isHost != widget.isHost) _thumbHost = widget.isHost;
  }

  void _tap() {
    if (_thumbHost != widget.isHost) return; // already switching
    setState(() => _thumbHost = !widget.isHost);
    widget.onSwitch();
    // This dashboard is hidden once the cross-fade ends; put its thumb back
    // (without animating) so it's right the next time it's shown.
    Future.delayed(_kSlide + const Duration(milliseconds: 200), () {
      if (!mounted || _thumbHost == widget.isHost) return;
      setState(() {
        _instant = true;
        _thumbHost = widget.isHost;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _instant = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final host = _thumbHost;
    return Semantics(
      container: true,
      label: widget.isHost ? 'Mode: Gig Host' : 'Mode: Gig Worker',
      child: Container(
        width: ModeSwitch.width,
        height: ModeSwitch.height,
        padding: const EdgeInsets.all(_kPad),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Stack(
          children: [
            // Sliding white thumb.
            AnimatedPositioned(
              duration: _d,
              curve: Curves.easeOutCubic,
              left: host ? _kIconW : 0,
              top: 0,
              bottom: 0,
              width: _kThumbW,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(color: Color(0x22000000), blurRadius: 3, offset: Offset(0, 1)),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                _side(
                  icon: Icons.person_outline_rounded,
                  label: 'Worker',
                  selected: !host,
                  color: _kWorkerText,
                  tooltip: 'Switch to Gig Worker',
                ),
                _side(
                  icon: Icons.work_outline_rounded,
                  label: 'Host',
                  selected: host,
                  color: _kHostText,
                  tooltip: 'Switch to Gig Host',
                ),
              ],
            ),
          ],
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
    final fg = selected ? color : Colors.white;
    final content = AnimatedContainer(
      duration: _d,
      curve: Curves.easeOutCubic,
      width: selected ? _kThumbW : _kIconW,
      height: double.infinity,
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: fg),
            duration: _d,
            builder: (_, c, _) => Icon(icon, size: selected ? 15 : 16, color: c),
          ),
          // Name fades/clips in on the side the thumb moves to.
          ClipRect(
            child: AnimatedSize(
              duration: _d,
              curve: Curves.easeOutCubic,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
    if (selected) {
      return Semantics(
        selected: true,
        label: 'Gig $label (current)',
        excludeSemantics: true,
        child: content,
      );
    }
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          child: content,
        ),
      ),
    );
  }
}
