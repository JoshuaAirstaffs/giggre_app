import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../controller/tutorial_controller.dart';
import '../models/tutorial_step.dart';

/// Sits above the whole app (wire into MaterialApp.builder). Watches
/// [TutorialController] and, whenever the current step's anchor is mounted
/// anywhere in the tree, paints a spotlight + tooltip over it.
class TutorialOverlayHost extends StatefulWidget {
  final Widget child;
  const TutorialOverlayHost({required this.child, super.key});

  @override
  State<TutorialOverlayHost> createState() => _TutorialOverlayHostState();
}

class _TutorialOverlayHostState extends State<TutorialOverlayHost>
    with TickerProviderStateMixin {
  Ticker? _ticker;
  Duration _elapsed = Duration.zero;
  // Blocking steps swallow drags along with taps (see the bands in
  // _TutorialSpotlight), so a step can't rely on the user manually scrolling
  // its target into view. Instead we scroll to it once, the first time each
  // step's anchor is found mounted — tracked by step id so it only fires
  // once per step rather than fighting the user on every frame.
  String? _scrolledForStepId;

  void _ensureTicking(bool shouldTick) {
    if (shouldTick && _ticker == null) {
      _ticker = createTicker((elapsed) => setState(() => _elapsed = elapsed))
        ..start();
    } else if (!shouldTick && _ticker != null) {
      _ticker!.dispose();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TutorialController>();
    final step = controller.currentStep;
    _ensureTicking(step != null);

    Rect? targetRect;
    final anchorKey = controller.currentAnchorKey;
    final anchorContext = anchorKey?.currentContext;
    if (anchorContext != null && anchorContext.mounted) {
      final renderObject = anchorContext.findRenderObject();
      if (renderObject is RenderBox && renderObject.attached) {
        final origin = renderObject.localToGlobal(Offset.zero);
        targetRect = Rect.fromLTWH(
          origin.dx,
          origin.dy,
          renderObject.size.width,
          renderObject.size.height,
        ).inflate(6);
      }
    }

    if (step == null) {
      _scrolledForStepId = null;
    } else if (anchorContext != null && _scrolledForStepId != step.id) {
      _scrolledForStepId = step.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!anchorContext.mounted) return;
        Scrollable.ensureVisible(
          anchorContext,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          alignment: 0.25,
        );
      });
    }

    final pulse = 0.55 +
        0.25 * math.sin(_elapsed.inMilliseconds / 1000 * math.pi * 2 / 1.6);

    return Stack(
      children: [
        widget.child,
        if (step != null && targetRect != null)
          _TutorialSpotlight(
            key: ValueKey(step.id),
            step: step,
            targetRect: targetRect,
            ringOpacity: pulse,
            onNext: controller.next,
            onSkip: controller.skip,
          ),
      ],
    );
  }
}

class _TutorialSpotlight extends StatelessWidget {
  final TutorialStep step;
  final Rect targetRect;
  final double ringOpacity;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _TutorialSpotlight({
    super.key,
    required this.step,
    required this.targetRect,
    required this.ringOpacity,
    required this.onNext,
    required this.onSkip,
  });

  bool get _blocking => step.advance == TutorialAdvance.manualTap;

  // The scrim itself is purely visual (IgnorePointer) — its painted "hole"
  // would otherwise be cosmetic only, since a single full-screen
  // GestureDetector swallows taps everywhere including over the hole. Real
  // blocking is done with four bands around the hole instead, so the target
  // widget underneath stays genuinely tappable/typeable during the step.
  List<Widget> _blockingBands(Rect hole, Size screen) {
    final h = Rect.fromLTRB(
      hole.left.clamp(0, screen.width),
      hole.top.clamp(0, screen.height),
      hole.right.clamp(0, screen.width),
      hole.bottom.clamp(0, screen.height),
    );
    Widget band(Rect r) => Positioned.fromRect(
          rect: r,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
          ),
        );
    return [
      band(Rect.fromLTRB(0, 0, screen.width, h.top)),
      band(Rect.fromLTRB(0, h.bottom, screen.width, screen.height)),
      band(Rect.fromLTRB(0, h.top, h.left, h.bottom)),
      band(Rect.fromLTRB(h.right, h.top, screen.width, h.bottom)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;

    return Stack(
      children: [
        IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: 1,
            child: CustomPaint(
              size: Size.infinite,
              painter: _SpotlightPainter(targetRect, ringOpacity),
            ),
          ),
        ),
        if (_blocking) ..._blockingBands(targetRect, screen),
        _TutorialTooltip(
          step: step,
          targetRect: targetRect,
          screen: screen,
          onNext: onNext,
          onSkip: onSkip,
        ),
      ],
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect rect;
  final double ringOpacity;
  _SpotlightPainter(this.rect, this.ringOpacity);

  @override
  void paint(Canvas canvas, Size size) {
    final scrimPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
      Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(14))),
    );
    canvas.drawPath(scrimPath, Paint()..color = Colors.black.withValues(alpha: 0.65));
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      Paint()
        ..color = kAmber.withValues(alpha: ringOpacity.clamp(0.3, 0.85))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.rect != rect || oldDelegate.ringOpacity != ringOpacity;
}

class _TutorialTooltip extends StatelessWidget {
  final TutorialStep step;
  final Rect targetRect;
  final Size screen;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _TutorialTooltip({
    required this.step,
    required this.targetRect,
    required this.screen,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    const cardWidth = 300.0;
    const margin = 16.0;
    final spaceBelow = screen.height - targetRect.bottom;
    final placeBelow = spaceBelow > 180 || targetRect.top < 180;
    final top = placeBelow ? targetRect.bottom + 14 : null;
    final bottom = placeBelow ? null : screen.height - targetRect.top + 14;
    final left = targetRect.center.dx - cardWidth / 2 < margin
        ? margin
        : (targetRect.center.dx + cardWidth / 2 > screen.width - margin
            ? screen.width - margin - cardWidth
            : targetRect.center.dx - cardWidth / 2);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      top: top,
      bottom: bottom,
      left: left,
      width: cardWidth,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
        ),
        child: _TooltipCard(step: step, onNext: onNext, onSkip: onSkip),
      ),
    );
  }
}

class _TooltipCard extends StatelessWidget {
  final TutorialStep step;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  const _TooltipCard({
    required this.step,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final waiting = step.advance == TutorialAdvance.autoOnAnchor;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: isDark ? kCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 6)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              step.title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF17263D),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              step.body,
              style: TextStyle(fontSize: 13, height: 1.4, color: kSub),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(foregroundColor: kSub),
                  child: const Text('Skip tutorial'),
                ),
                const Spacer(),
                if (!waiting)
                  ElevatedButton(
                    onPressed: onNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAmber,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('Next'),
                  )
                else
                  Text(
                    'Go ahead — we’ll keep up',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: kSub,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
