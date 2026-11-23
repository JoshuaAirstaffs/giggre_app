import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Skeleton loading — grey placeholder shapes in the layout of the content
//  that's coming, with a soft shimmer sweeping across. Used instead of a
//  spinner wherever a screen, list or section is loading, so the page feels
//  ready sooner (perceived performance) and nothing jumps when data lands.
//
//  Building blocks: [Shimmer] (one sweep for everything inside it),
//  [SkeletonBox], [SkeletonLine], [SkeletonCircle].
//  Ready-made layouts: [SkeletonList], [SkeletonCards], [SkeletonDetail],
//  [SkeletonProfile], [SkeletonChat], [SkeletonArticle], [SkeletonDashboard].
//  Each preset is wrapped in a Shimmer and a non-scrolling, clipped scroll
//  view, so it works in a bounded slot (Expanded, a sheet) and in an
//  unbounded one (a Column in a scroll view) without overflow errors.
//
//  Keep spinners for actions (a button's "Saving…") and media buffering —
//  there's no layout to preview there.
// ─────────────────────────────────────────────────────────────────────────────

/// Bone colour for the current theme.
Color skeletonBase(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF223047)
        : const Color(0xFFE3E8EF);

Color _skeletonHighlight(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF34465F)
        : const Color(0xFFF6F8FB);

/// Sweeps a soft highlight across every bone inside it.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = skeletonBase(context);
    final hi = _skeletonHighlight(context);
    // Reduce-motion: no sweep, just the bones.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return widget.child;
    }
    return Semantics(
      label: 'Loading',
      liveRegion: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          child: widget.child,
          builder: (context, child) {
            final t = _c.value * 2 - 0.5; // -0.5 → 1.5, off both edges
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [base, hi, base],
                stops: [
                  (t - 0.25).clamp(0.0, 1.0),
                  t.clamp(0.0, 1.0),
                  (t + 0.25).clamp(0.0, 1.0),
                ],
              ).createShader(rect),
              child: child,
            );
          },
        ),
      ),
    );
  }
}

/// A rounded placeholder block. Without a width it fills the row.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;
  const SkeletonBox({super.key, this.width, this.height, this.radius = 10});

  /// Fills its parent (image / banner placeholders), with its own shimmer.
  const factory SkeletonBox.expand({Key? key, double radius}) = _SkeletonFill;

  @override
  Widget build(BuildContext context) => Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: skeletonBase(context),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

class _SkeletonFill extends SkeletonBox {
  const _SkeletonFill({super.key, super.radius = 0});

  @override
  Widget build(BuildContext context) => Shimmer(
        child: SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: skeletonBase(context),
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
        ),
      );
}

/// One line of text.
class SkeletonLine extends StatelessWidget {
  final double? width;
  final double height;
  const SkeletonLine({super.key, this.width, this.height = 11});

  @override
  Widget build(BuildContext context) =>
      SkeletonBox(width: width, height: height, radius: height / 2);
}

class SkeletonCircle extends StatelessWidget {
  final double size;
  const SkeletonCircle({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) =>
      SkeletonBox(width: size, height: size, radius: size / 2);
}

/// Shimmer + clip + no-scroll wrapper shared by the presets.
class _Preset extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final List<Widget> children;
  const _Preset({required this.padding, required this.children});

  @override
  Widget build(BuildContext context) => Shimmer(
        child: ClipRect(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      );
}

// A row: leading shape, two text lines, a short trailing line.
Widget _row({bool circle = true, double lead = 44, bool trailing = true}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          circle
              ? SkeletonCircle(size: lead)
              : SkeletonBox(width: lead, height: lead, radius: 12),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(width: 150, height: 12),
                SizedBox(height: 8),
                SkeletonLine(width: 220, height: 10),
              ],
            ),
          ),
          if (trailing) ...[
            const SizedBox(width: 12),
            const SkeletonLine(width: 36, height: 10),
          ],
        ],
      ),
    );

/// Rows with an avatar / icon and two lines: chats, notifications,
/// people, transactions, settings.
class SkeletonList extends StatelessWidget {
  final int count;
  /// Round leading shape (people) vs rounded square (icons, gigs).
  final bool circle;
  final EdgeInsetsGeometry padding;
  const SkeletonList({
    super.key,
    this.count = 6,
    this.circle = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  Widget build(BuildContext context) => _Preset(
        padding: padding,
        children: [for (var i = 0; i < count; i++) _row(circle: circle)],
      );
}

/// Card-shaped items (gig cards, saved gigs, history, videos).
class SkeletonCards extends StatelessWidget {
  final int count;
  final EdgeInsetsGeometry padding;
  const SkeletonCards({
    super.key,
    this.count = 4,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).dividerColor;
    return _Preset(
      padding: padding,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border),
            ),
            child: const Row(
              children: [
                SkeletonBox(width: 56, height: 56, radius: 12),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: SkeletonLine(height: 13)),
                          SizedBox(width: 24),
                          SkeletonLine(width: 48, height: 13),
                        ],
                      ),
                      SizedBox(height: 9),
                      SkeletonLine(width: 140, height: 10),
                      SizedBox(height: 9),
                      SkeletonLine(width: 190, height: 9),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A detail page: banner, title, a few facts, a paragraph, a card.
class SkeletonDetail extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  const SkeletonDetail({super.key, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) => _Preset(
        padding: padding,
        children: const [
          SkeletonBox(height: 150, radius: 16),
          SizedBox(height: 18),
          SkeletonLine(width: 220, height: 18),
          SizedBox(height: 10),
          SkeletonLine(width: 140, height: 11),
          SizedBox(height: 22),
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 56, radius: 12)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 56, radius: 12)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 56, radius: 12)),
            ],
          ),
          SizedBox(height: 22),
          SkeletonLine(height: 10),
          SizedBox(height: 8),
          SkeletonLine(height: 10),
          SizedBox(height: 8),
          SkeletonLine(width: 200, height: 10),
          SizedBox(height: 22),
          SkeletonBox(height: 90, radius: 14),
        ],
      );
}

/// A profile: cover, avatar, name, contact lines, toggle, stats, rows.
class SkeletonProfile extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  /// Just the card (a sheet), without the toggle, stats and rows.
  final bool compact;
  const SkeletonProfile({
    super.key,
    this.padding = const EdgeInsets.all(20),
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => _Preset(
        padding: padding,
        children: [
          const SkeletonBox(height: 86, radius: 18),
          Transform.translate(
            offset: const Offset(16, -30),
            child: const SkeletonCircle(size: 68),
          ),
          const SkeletonLine(width: 160, height: 16),
          const SizedBox(height: 8),
          const SkeletonLine(width: 210, height: 10),
          const SizedBox(height: 18),
          _row(lead: 34, trailing: false),
          _row(lead: 34, trailing: false),
          if (!compact) ...[
            const SizedBox(height: 14),
            const SkeletonBox(height: 44, radius: 14),
            const SizedBox(height: 14),
            const SkeletonBox(height: 84, radius: 14),
            const SizedBox(height: 14),
            _row(circle: false, lead: 36),
            _row(circle: false, lead: 36),
          ],
        ],
      );
}

/// Chat bubbles, alternating sides.
class SkeletonChat extends StatelessWidget {
  final int count;
  const SkeletonChat({super.key, this.count = 7});

  @override
  Widget build(BuildContext context) {
    const widths = [180.0, 120.0, 220.0, 90.0, 160.0, 200.0, 110.0];
    return _Preset(
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < count; i++)
          Align(
            alignment: i.isEven ? Alignment.centerLeft : Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SkeletonBox(
                width: widths[i % widths.length],
                height: i % 3 == 2 ? 54 : 36,
                radius: 16,
              ),
            ),
          ),
      ],
    );
  }
}

/// Text pages (Help, Terms, Privacy, About): headings and paragraphs.
class SkeletonArticle extends StatelessWidget {
  const SkeletonArticle({super.key});

  @override
  Widget build(BuildContext context) => _Preset(
        padding: const EdgeInsets.all(20),
        children: [
          for (var s = 0; s < 3; s++) ...[
            const SkeletonLine(width: 180, height: 16),
            const SizedBox(height: 14),
            for (var l = 0; l < 4; l++) ...[
              SkeletonLine(width: l == 3 ? 160 : null, height: 10),
              const SizedBox(height: 9),
            ],
            const SizedBox(height: 18),
          ],
        ],
      );
}

/// A dashboard: coloured header band, overlapping card, banner, list.
class SkeletonDashboard extends StatelessWidget {
  final bool isHost;
  const SkeletonDashboard({super.key, this.isHost = false});

  @override
  Widget build(BuildContext context) {
    final band = isHost
        ? const [Color(0xFFF0A830), Color(0xFFD88810)]
        : const [Color(0xFF2B6FB5), Color(0xFF1F4D80)];
    return ClipRect(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The real header colour right away, so the page reads as
            // "my dashboard" before anything has loaded.
            Container(
              height: MediaQuery.paddingOf(context).top + 110,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: band),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -26),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Shimmer(child: SkeletonBox(height: 92, radius: 16)),
              ),
            ),
            const Shimmer(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 120, radius: 16),
                    SizedBox(height: 22),
                    SkeletonLine(width: 130, height: 16),
                    SizedBox(height: 14),
                    SkeletonBox(height: 200, radius: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// App start (before we know which screen comes next): the logo, gently
/// breathing, instead of a bare spinner.
class SkeletonSplash extends StatefulWidget {
  const SkeletonSplash({super.key});

  @override
  State<SkeletonSplash> createState() => _SkeletonSplashState();
}

class _SkeletonSplashState extends State<SkeletonSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading Giggre',
      child: Center(
        child: FadeTransition(
          opacity: _c.drive(Tween(begin: 0.45, end: 1.0)),
          child: Image.asset('assets/images/logo.png', height: 72),
        ),
      ),
    );
  }
}
