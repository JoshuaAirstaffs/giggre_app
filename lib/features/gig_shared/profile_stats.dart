import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import 'active_gig_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Profile dashboard pieces — the animated stat tiles, count-up numbers, star
//  rows and rating bars shared by the full profile screen. Kept together so a
//  host's dashboard and a worker's animate identically and only their labels
//  and accent differ.
// ─────────────────────────────────────────────────────────────────────────────

const Duration kProfileStatDuration = Duration(milliseconds: 900);
const Curve kProfileStatCurve = Curves.easeOutCubic;

/// A number that counts up from zero the first time it is shown, and tweens
/// between values after that.
///
/// [placeholder] takes over entirely while the value is null — an unrated
/// user's average must read as "no rating yet", not as a 0.0 that counted up
/// to nothing.
class AnimatedCountText extends StatelessWidget {
  final double? value;
  final int decimals;
  final String placeholder;
  final TextStyle style;
  final Duration duration;

  const AnimatedCountText({
    super.key,
    required this.value,
    required this.style,
    this.decimals = 0,
    this.placeholder = '—',
    this.duration = kProfileStatDuration,
  });

  @override
  Widget build(BuildContext context) {
    final target = value;
    if (target == null) {
      return Text(placeholder, style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target),
      duration: duration,
      curve: kProfileStatCurve,
      builder: (_, v, _) => Text(
        v.toStringAsFixed(decimals),
        style: style,
        // The digits change every frame; a fixed baseline keeps the row from
        // twitching as the glyph widths do.
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
        ),
      ),
    );
  }
}

/// Five stars filled to a fractional rating, sweeping up to it on first
/// build. Fills by clipping a solid row rather than swapping in half-star
/// glyphs, so 4.3 and 4.7 don't both land on the same half star.
class AnimatedStarRating extends StatelessWidget {
  final double rating;
  final double size;
  final double gap;
  final Color color;
  final Color emptyColor;
  final bool animate;

  const AnimatedStarRating({
    super.key,
    required this.rating,
    this.size = 14,
    this.gap = 1,
    this.color = kGold,
    required this.emptyColor,
    this.animate = true,
  });

  Widget _row(Color c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 5; i++)
        Padding(
          padding: EdgeInsets.only(right: i == 4 ? 0 : gap),
          child: Icon(Icons.star_rounded, size: size, color: c),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final fraction = (rating / 5).clamp(0.0, 1.0);
    Widget stack(double t) => Stack(
      children: [
        _row(emptyColor),
        ClipRect(clipper: _FractionClipper(t), child: _row(color)),
      ],
    );

    if (!animate) return stack(fraction);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fraction),
      duration: kProfileStatDuration,
      curve: kProfileStatCurve,
      builder: (_, t, _) => stack(t),
    );
  }
}

class _FractionClipper extends CustomClipper<Rect> {
  final double fraction;
  const _FractionClipper(this.fraction);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_FractionClipper oldClipper) =>
      oldClipper.fraction != fraction;
}

/// One dashboard tile: tinted icon, a count-up value and a caption.
///
/// Tapping scales it down and fires [onTap] — used to jump to the section of
/// the profile the number came from, so the dashboard doubles as navigation.
class ProfileStatCard extends StatefulWidget {
  final IconData icon;
  final Color accent;
  final String label;

  /// The number to count up to, or null to show [valuePlaceholder] instead.
  final double? value;
  final int decimals;
  final String valuePlaceholder;

  /// Drawn after the value — the star beside an average rating.
  final IconData? valueSuffixIcon;
  final Color? valueColor;
  final bool isDark;
  final VoidCallback? onTap;

  const ProfileStatCard({
    super.key,
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    required this.isDark,
    this.decimals = 0,
    this.valuePlaceholder = '—',
    this.valueSuffixIcon,
    this.valueColor,
    this.onTap,
  });

  @override
  State<ProfileStatCard> createState() => _ProfileStatCardState();
}

class _ProfileStatCardState extends State<ProfileStatCard> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v && mounted) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final valueColor = widget.valueColor ?? activeGigTextPrimary(isDark);

    return AnimatedScale(
      scale: _pressed ? 0.96 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: GestureDetector(
        onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
        onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
        onTap: widget.onTap == null
            ? null
            : () {
                _setPressed(false);
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: BoxDecoration(
            color: activeGigCardBg(isDark),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: activeGigCardBorder(isDark)),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.28)
                    : widget.accent.withValues(alpha: 0.10),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: isDark ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, size: 14, color: widget.accent),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedCountText(
                        value: widget.value,
                        decimals: widget.decimals,
                        placeholder: widget.valuePlaceholder,
                        style: TextStyle(
                          color: valueColor,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          height: 1.05,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                  if (widget.valueSuffixIcon != null &&
                      widget.value != null) ...[
                    const SizedBox(width: 2),
                    Icon(widget.valueSuffixIcon, size: 15, color: valueColor),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                widget.label,
                style: TextStyle(
                  color: activeGigTextMuted(isDark),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fade-and-rise that starts when it mounts.
///
/// Deliberately not [EntranceAnimation], which waits to be scrolled into
/// view: the profile header and dashboard are already on screen when the page
/// opens, and that visibility check is polled twice a second — long enough to
/// show them as a blank gap first. The reviews further down still use
/// [EntranceAnimation], where waiting for the scroll is the point.
class ProfileEntrance extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double slideOffset;

  /// Scale to grow from — 1 for no scaling, which is what everything but the
  /// avatar wants.
  final double scaleFrom;

  const ProfileEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 440),
    this.slideOffset = 18,
    this.scaleFrom = 1,
  });

  @override
  State<ProfileEntrance> createState() => _ProfileEntranceState();
}

class _ProfileEntranceState extends State<ProfileEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      child: widget.child,
      builder: (_, child) {
        final t = _progress.value.clamp(0.0, 1.0);
        final scaled = widget.scaleFrom == 1
            ? child
            : Transform.scale(
                scale: widget.scaleFrom + (1 - widget.scaleFrom) * t,
                child: child,
              );
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, widget.slideOffset * (1 - t)),
            child: scaled,
          ),
        );
      },
    );
  }
}

/// The dashboard row: equal-width tiles, each sliding in just after the one
/// to its left.
///
/// The tiles carry labels of different lengths, so the tallest sets the row
/// height and the rest stretch to match it. A bare Row cannot do that here —
/// inside a scroll view its own height is unbounded, and a stretched child
/// would be asked to be infinitely tall.
class ProfileStatRow extends StatelessWidget {
  final List<Widget> tiles;
  final double gap;
  final Duration stagger;

  const ProfileStatRow({
    super.key,
    required this.tiles,
    this.gap = 10,
    this.stagger = const Duration(milliseconds: 90),
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(
              child: ProfileEntrance(delay: stagger * i, child: tiles[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// One row of the star histogram, its fill sweeping out on first build.
class AnimatedRatingBar extends StatelessWidget {
  final int star;
  final int count;
  final int total;
  final bool isDark;
  final Duration delay;

  const AnimatedRatingBar({
    super.key,
    required this.star,
    required this.count,
    required this.total,
    required this.isDark,
    this.delay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final muted = activeGigTextMuted(isDark);
    final fraction = total == 0 ? 0.0 : count / total;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 10,
            child: Text('$star', style: TextStyle(color: muted, fontSize: 11)),
          ),
          const Icon(Icons.star_rounded, color: kGold, size: 11),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fraction),
                duration: kProfileStatDuration + delay,
                curve: kProfileStatCurve,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  backgroundColor: activeGigTrackBg(isDark),
                  valueColor: const AlwaysStoppedAnimation(kGold),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 22,
            child: Text(
              '$count',
              style: TextStyle(color: muted, fontSize: 11),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// A dot with a ring breathing out of it — "this person is working now"
/// rather than a static status colour.
///
/// The ring is the one looping animation on the profile, so it is also the
/// one thing here that honours the platform's reduce-motion setting: a pulse
/// that never stops is precisely what that setting exists to switch off. With
/// it on the dot stays, the ring goes.
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;

  const PulseDot({super.key, required this.color, this.size = 8});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  static const _maxScale = 2.8;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final extent = widget.size * _maxScale;
    return SizedBox(
      width: extent,
      height: extent,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (_, _) {
              final t = _controller.value;
              return Opacity(
                // Fades as it grows, so the ring dissolves rather than
                // snapping back to the dot each cycle.
                opacity: (1 - t) * 0.45,
                child: Container(
                  width: widget.size * (1 + (_maxScale - 1) * t),
                  height: widget.size * (1 + (_maxScale - 1) * t),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color,
                  ),
                ),
              );
            },
          ),
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
            ),
          ),
        ],
      ),
    );
  }
}

/// A proportion as a bar that sweeps out to its value on first build.
///
/// [AnimatedRatingBar] is the star histogram's own row — five of them, each
/// with a star and a count. This is the bare meter underneath, for the one
/// place that needs a proportion without either.
class AnimatedMeterBar extends StatelessWidget {
  final double fraction;
  final Color color;
  final bool isDark;
  final double height;
  final Duration delay;

  const AnimatedMeterBar({
    super.key,
    required this.fraction,
    required this.color,
    required this.isDark,
    this.height = 8,
    this.delay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        height: height,
        color: activeGigTrackBg(isDark),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
          duration: kProfileStatDuration + delay,
          curve: kProfileStatCurve,
          builder: (_, v, _) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            // A zero-width child still paints its rounded cap as a sliver of
            // colour at the left edge, which reads as a value that isn't
            // there. Below a hair's width, draw nothing.
            widthFactor: v < 0.001 ? 0 : v,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  colors: [color.withValues(alpha: 0.55), color],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
