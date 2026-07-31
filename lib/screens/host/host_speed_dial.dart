import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/profile_tab_theme.dart';

const _kGoldStart = Color(0xFFF0A830);
const _kGoldEnd = Color(0xFFD88810);
const _kScreenBg = Color(0xFFF4F6FA);
const _kBubbleGold = Color(0xFFD88810);
const _kBubbleBlue = Color(0xFF2B6FB5);
const _kBubblePurple = Color(0xFF8B6FD8);

// Hand-picked pastel icon-tile backgrounds rather than a raw alpha blend of
// the accent color — a flat opacity blend washes out warmer hues (gold)
// much more than cooler ones (blue/purple) at the same alpha, so the three
// tiles end up looking inconsistently vivid. Picking each background
// explicitly keeps them visually even.
const _kBubbleGoldBg = Color(0xFFFCEACB);
const _kBubbleBlueBg = Color(0xFFE1EBF7);
const _kBubblePurpleBg = Color(0xFFEDE7FB);

// Tooltip surface — fixed, mode-agnostic neutrals. Never pull from the
// surrounding Worker/Host theme, unlike the bubble tints above.
const _kTooltipBg = Color(0xFF1A1A1A);
const _kTooltipText = Colors.white;

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
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: _kScreenBg,
        ),
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
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 26,
              ),
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
        // This overlay sits as a sibling of Scaffold (not inside it — see
        // host_shell.dart), so it never gets Scaffold's own Material-provided
        // DefaultTextStyle. Without a Material ancestor, Text here fell back
        // to Flutter's built-in "no DefaultTextStyle found" debug style —
        // large red text with a yellow underline — which only wasn't fully
        // obvious because explicit TextStyle properties (size/weight/color)
        // masked most of it, leaving just the underline and wrong font
        // showing through. `transparency` restores normal text/icon
        // rendering without painting any surface of its own.
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: widget.onClose,
                  child: Container(
                    color: Colors.black.withValues(
                      alpha: 0.55 * widget.controller.value.clamp(0.0, 1.0),
                    ),
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
                infoText:
                    "We'll instantly match you with the nearest, most reliable worker available.",
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
                infoText:
                    'Posted publicly. Qualified workers come to you, and you choose who to hire.',
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
                infoText:
                    'Sent directly to one trusted worker you already have in mind.',
                onTap: widget.onOfferedGig,
              ),
            ],
          ),
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
    required String infoText,
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
                  infoText: infoText,
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
  final String infoText;

  const _BubbleContent({
    required this.tint,
    required this.iconBg,
    required this.icon,
    required this.label,
    required this.infoText,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: isDark
                    ? null
                    : const LinearGradient(
                        colors: [Colors.white, Color(0xFFFAFAFC)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                color: isDark ? tokens.cardSurface : null,
                shape: BoxShape.circle,
                border: Border.all(color: tokens.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.08),
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
            Positioned(
              top: -2,
              right: -2,
              child: _InfoBadge(text: infoText, tint: tint, tokens: tokens),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Container(
          // No fixed `height` — a tight cross-axis constraint here previously
          // forced the Row into exactly 22px regardless of the bold 10px
          // text's real line-height, which overflowed by a pixel or two and
          // showed as Flutter's yellow/black debug overflow stripes under the
          // label. Vertical padding lets the pill size itself around the
          // text instead, so it can't overflow.
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
          decoration: BoxDecoration(
            color: tokens.cardSurface,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: tokens.cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                  letterSpacing: 0.1,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Info badge — sits on the corner of the option's icon circle rather than
//  next to its label, so it never touches the label pill's layout. Tap shows
//  a small tooltip near the badge, auto-dismissing after ~2.5s or on an
//  outside tap. Uses its own tap recognizer (not the bubble's) so it never
//  triggers the parent option's onTap — see nested-GestureDetector arena
//  resolution: whichever recognizer accepts the "up" event first (the
//  innermost, here) wins and blocks the ancestor's from also firing.
// ─────────────────────────────────────────────────────────────────────────────
class _InfoBadge extends StatelessWidget {
  final String text;
  // The bubble's own accent (gold/blue/purple) — ties the badge to its
  // option's existing color language. Independent of the Worker/Host
  // screen-wide theme, which this badge never reads from.
  final Color tint;
  // Light/dark surface tokens, unlike `tint` — the badge's own base color
  // still needs to flip with system theme so it doesn't float as a
  // stray light-mode dot on a dark bubble.
  final ProfileTabTokens tokens;

  const _InfoBadge({
    required this.text,
    required this.tint,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) => _InfoTooltip.show(
        context,
        anchor: details.globalPosition,
        text: text,
      ),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: tokens.cardSurface,
          shape: BoxShape.circle,
          border: Border.all(color: tint.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: tint.withValues(alpha: 0.20),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Icon(Icons.info_outline, size: 12, color: tint),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tap-to-show tooltip via a raw OverlayEntry — Flutter's built-in Tooltip is
//  hover/long-press only, so a custom overlay is the lightest option that
//  doesn't pull in a new dependency for this one popup.
// ─────────────────────────────────────────────────────────────────────────────
class _InfoTooltip {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  static void show(
    BuildContext context, {
    required Offset anchor,
    required String text,
  }) {
    dismiss(); // only one tooltip at a time — close any existing one first.

    final screenSize = MediaQuery.of(context).size;
    const maxWidth = 220.0;
    const gap = 10.0;

    // Flip below the icon when there isn't enough room above it to avoid
    // clipping off the top of the screen (the "Open Gig" bubble, centered
    // highest in the arc, is the one most likely to need this).
    final flipBelow = anchor.dy < 160;
    final right = (screenSize.width - anchor.dx).clamp(
      8.0,
      screenSize.width - maxWidth - 8.0,
    );

    final overlay = Overlay.of(context);
    _entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: dismiss,
            ),
          ),
          Positioned(
            right: right,
            top: flipBelow ? anchor.dy + gap : null,
            bottom: flipBelow ? null : screenSize.height - anchor.dy + gap,
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: maxWidth),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _kTooltipBg.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  text,
                  // No explicit fontFamily — inherits the app's Inter default
                  // from ThemeData (see theme_provider.dart), same as every
                  // other Text in the app.
                  style: const TextStyle(
                    color: _kTooltipText,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
    _timer = Timer(const Duration(milliseconds: 2500), dismiss);
  }
}
