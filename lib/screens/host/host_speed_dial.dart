import 'package:flutter/material.dart';

const _kGoldStart = Color(0xFFF0A830);
const _kGoldEnd = Color(0xFFD88810);
const _kScreenBg = Color(0xFFF4F6FA);
const _kBubbleGold = Color(0xFFD88810);
const _kBubbleBlue = Color(0xFF2B6FB5);
const _kBubblePurple = Color(0xFF8B6FD8);
const _kLabelText = Color(0xFF17263D);

// Hand-picked pastel icon-tile backgrounds rather than a raw alpha blend of
// the accent color — a flat opacity blend washes out warmer hues (gold)
// much more than cooler ones (blue/purple) at the same alpha, so the three
// tiles end up looking inconsistently vivid. Picking each background
// explicitly keeps them visually even.
const _kBubbleGoldBg = Color(0xFFFCEACB);
const _kBubbleBlueBg = Color(0xFFE1EBF7);
const _kBubblePurpleBg = Color(0xFFEDE7FB);

// Bubble circle diameter (54) plus the gap + label height below it (9 + 22),
// i.e. the vertical distance from the circle's center down to the bottom of
// the whole bubble+label column — needed to convert a "circle center" arc
// target into the column-bottom offset Align/Transform actually position by.
const _kBubbleCenterToColumnBottom = 27.0 + 9.0 + 22.0;

// ─────────────────────────────────────────────────────────────────────────────
//  Raised "Post Gig" circle button — 56px gold-gradient circle with a
//  4px screen-bg ring, its +/× icon rotating 45° via the shared controller.
//  Meant to be placed in a parent Stack (outside any clipped bottomNavigationBar)
//  so its protrusion above the flat nav bar is never clipped.
// ─────────────────────────────────────────────────────────────────────────────
class HostSpeedDialButton extends StatelessWidget {
  final Animation<double> controller;
  final VoidCallback onTap;

  const HostSpeedDialButton({
    super.key,
    required this.controller,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(shape: BoxShape.circle, color: _kScreenBg),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [_kGoldStart, _kGoldEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _kGoldEnd.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: RotationTransition(
              turns: Tween<double>(begin: 0, end: 0.125).animate(controller),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Speed dial overlay — dark scrim + three bubbles that pop out in a staggered
//  arc above the Post Gig button. Driven by a single AnimationController
//  (~250ms); each bubble uses its own Interval over the same controller so
//  they pop ~40ms apart with Curves.easeOutBack overshoot.
// ─────────────────────────────────────────────────────────────────────────────
class HostSpeedDialOverlay extends StatefulWidget {
  final AnimationController controller;
  // Height of the flat nav bar (incl. bottom safe-area inset), used to anchor
  // the arc math to the Post Gig button's center.
  final double navBarHeight;
  final VoidCallback onClose;
  final VoidCallback onQuickGig;
  final VoidCallback onOpenGig;
  final VoidCallback onOfferedGig;

  const HostSpeedDialOverlay({
    super.key,
    required this.controller,
    required this.navBarHeight,
    required this.onClose,
    required this.onQuickGig,
    required this.onOpenGig,
    required this.onOfferedGig,
  });

  @override
  State<HostSpeedDialOverlay> createState() => _HostSpeedDialOverlayState();
}

class _HostSpeedDialOverlayState extends State<HostSpeedDialOverlay> {
  late final Animation<double> _quickCurve = CurvedAnimation(
    parent: widget.controller,
    curve: const Interval(0.0, 1.0, curve: Curves.easeOutBack),
  );
  late final Animation<double> _openCurve = CurvedAnimation(
    parent: widget.controller,
    curve: const Interval(0.16, 1.0, curve: Curves.easeOutBack),
  );
  late final Animation<double> _offeredCurve = CurvedAnimation(
    parent: widget.controller,
    curve: const Interval(0.32, 1.0, curve: Curves.easeOutBack),
  );

  @override
  Widget build(BuildContext context) {
    // The button's own vertical center sits ~2px inside the flat bar's top
    // edge (56px circle, 26px of it protruding above that edge).
    final anchorFromBottom = widget.navBarHeight - 2;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        if (widget.controller.value == 0) return const SizedBox.shrink();
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  color: Colors.black
                      .withValues(alpha: 0.55 * widget.controller.value.clamp(0.0, 1.0)),
                ),
              ),
            ),
            _bubble(
              curve: _quickCurve,
              target: const Offset(-88, -46),
              anchorFromBottom: anchorFromBottom,
              tint: _kBubbleGold,
              iconBg: _kBubbleGoldBg,
              icon: Icons.bolt_rounded,
              label: 'Quick Gig',
              onTap: widget.onQuickGig,
            ),
            _bubble(
              curve: _openCurve,
              target: const Offset(0, -100),
              anchorFromBottom: anchorFromBottom,
              tint: _kBubbleBlue,
              iconBg: _kBubbleBlueBg,
              icon: Icons.work_rounded,
              label: 'Open Gig',
              onTap: widget.onOpenGig,
            ),
            _bubble(
              curve: _offeredCurve,
              target: const Offset(88, -46),
              anchorFromBottom: anchorFromBottom,
              tint: _kBubblePurple,
              iconBg: _kBubblePurpleBg,
              icon: Icons.send_rounded,
              label: 'Offered Gig',
              onTap: widget.onOfferedGig,
            ),
          ],
        );
      },
    );
  }

  Widget _bubble({
    required Animation<double> curve,
    required Offset target,
    required double anchorFromBottom,
    required Color tint,
    required Color iconBg,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final t = curve.value;
    final dx = target.dx * t;
    // target.dy is where the bubble's circle center should land relative to
    // the button center; Align(bottomCenter) + Transform.translate below
    // actually position the column's bottom edge, so shift by the distance
    // from the circle's center down to that bottom edge.
    final dy = target.dy * t + _kBubbleCenterToColumnBottom;
    final opacity = t.clamp(0.0, 1.0);
    final scale = t < 0 ? 0.0 : t;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Transform.translate(
        offset: Offset(dx, -anchorFromBottom + dy),
        child: IgnorePointer(
          ignoring: opacity < 0.6,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: GestureDetector(
                onTap: onTap,
                child: _BubbleContent(
                  tint: tint,
                  iconBg: iconBg,
                  icon: icon,
                  label: label,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BubbleContent extends StatelessWidget {
  final Color tint;
  final Color iconBg;
  final IconData icon;
  final String label;

  const _BubbleContent({
    required this.tint,
    required this.iconBg,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.white, Color(0xFFFAFAFC)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
            boxShadow: [
              // Tinted glow (matches the bubble's own accent) plus a tight
              // neutral shadow underneath — flat black-only shadows are what
              // make a floating chip read as a generic template.
              BoxShadow(
                color: tint.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: tint, size: 21),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: const Color(0x1417263D)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          // No `alignment` here: Container+alignment (with a fixed height but
          // no width) expands to fill all available width instead of hugging
          // the text. A Row with mainAxisSize.min shrink-wraps correctly while
          // still centering the label vertically within the fixed height.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _kLabelText,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
