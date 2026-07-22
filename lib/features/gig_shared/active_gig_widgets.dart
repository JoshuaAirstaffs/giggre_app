import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'active_gig_theme.dart';
import 'active_gig_step.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Header — compact gradient app bar
// ─────────────────────────────────────────────────────────────────────────────
class ActiveGigHeader extends StatelessWidget {
  final String title;
  final String statusLabel;
  final VoidCallback onBack;
  final ActiveGigAccent accent;
  const ActiveGigHeader({
    super.key,
    required this.title,
    required this.statusLabel,
    required this.onBack,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 108,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.gradientStart, accent.gradientEnd],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
      ),
      padding: const EdgeInsets.only(left: 4, right: 16),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 18),
          ),
          Text(
            title,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(
              '●  $statusLabel',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  6-step horizontal tracker
// ─────────────────────────────────────────────────────────────────────────────
class StepTracker extends StatelessWidget {
  final int currentIndex;
  final ActiveGigAccent accent;
  final List<String> labels;
  const StepTracker({
    super.key,
    required this.currentIndex,
    required this.accent,
    this.labels = kStepLabels,
  });

  @override
  Widget build(BuildContext context) {
    final total = labels.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final segment = constraints.maxWidth / total;
        final fillFraction =
            total <= 1 ? 1.0 : currentIndex / (total - 1);
        return Column(
          children: [
            SizedBox(
              height: 22,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: segment / 2,
                    right: segment / 2,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: activeGigTrackBg(isDark),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Positioned(
                    left: segment / 2,
                    right: segment / 2,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fillFraction.clamp(0.0, 1.0),
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: accent.solid,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(total, (i) {
                      return Expanded(
                        child: Center(
                          child: StepDot(
                            isDone: i < currentIndex,
                            isCurrent: i == currentIndex,
                            accent: accent,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: List.generate(total, (i) {
                final isCurrent = i == currentIndex;
                final isDone = i < currentIndex;
                final color = isCurrent
                    ? accent.solid
                    : isDone
                        ? activeGigTextSecondary(isDark)
                        : activeGigTextDisabled(isDark);
                return Expanded(
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 8,
                      color: color,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }
}

class StepDot extends StatelessWidget {
  final bool isDone;
  final bool isCurrent;
  final ActiveGigAccent accent;
  const StepDot({
    super.key,
    required this.isDone,
    required this.isCurrent,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isCurrent) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: accent.solid.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: accent.solid,
            shape: BoxShape.circle,
            border: Border.all(color: activeGigCardBg(isDark), width: 3),
          ),
        ),
      );
    }
    if (isDone) {
      return Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: accent.solid, shape: BoxShape.circle),
      );
    }
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: activeGigCardBg(isDark),
        shape: BoxShape.circle,
        border: Border.all(color: activeGigCardBorder(isDark), width: 2),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Progress card — step tracker + instruction block (single source of truth:
//  the same step/stepIndex the header chip and tracker fill derive from)
// ─────────────────────────────────────────────────────────────────────────────
class ActiveGigProgressCard extends StatelessWidget {
  final int stepIndex;
  final String title;
  final String body;
  final String? elapsed;
  final bool arrivedPromptVisible;
  final VoidCallback onConfirmArrival;
  final bool isCancelPending;
  final bool showStartGig;
  final VoidCallback onStartGig;
  final bool showGigComplete;
  final VoidCallback onGigComplete;
  final ActiveGigAccent accent;
  final List<String> stepLabels;

  const ActiveGigProgressCard({
    super.key,
    required this.stepIndex,
    required this.title,
    required this.body,
    this.elapsed,
    required this.arrivedPromptVisible,
    required this.onConfirmArrival,
    required this.isCancelPending,
    required this.showStartGig,
    required this.onStartGig,
    required this.showGigComplete,
    required this.onGigComplete,
    required this.accent,
    this.stepLabels = kStepLabels,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: activeGigCardBg(isDark),
        borderRadius: BorderRadius.circular(kActiveGigCardRadius),
        border: Border.all(color: activeGigCardBorder(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: StepTracker(
                currentIndex: stepIndex, accent: accent, labels: stepLabels),
          ),
          Divider(height: 0, thickness: 1, color: activeGigDividerColor(isDark)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: activeGigTextPrimary(isDark),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (elapsed != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: kActiveGigSuccessGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          elapsed!,
                          style: const TextStyle(
                            color: kActiveGigSuccessGreen,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                      color: activeGigTextMuted(isDark), fontSize: 11, height: 1.4),
                ),
                if (arrivedPromptVisible) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kActiveGigSuccessGreen.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: kActiveGigSuccessGreen.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_rounded,
                            color: kActiveGigSuccessGreen, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            "You're at the location — confirm your arrival.",
                            style: TextStyle(
                                color: kActiveGigSuccessGreen,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: onConfirmArrival,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kActiveGigSuccessGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Confirm Arrival',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
                if (isCancelPending) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kAmber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kAmber.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.hourglass_top_rounded,
                            color: kAmber, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Cancellation pending — admin is reviewing your request.',
                            style: TextStyle(
                                color: kAmber,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (showStartGig) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: onStartGig,
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('Start Gig',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent.solid,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
                if (showGigComplete) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: onGigComplete,
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          size: 20),
                      label: const Text('Gig Complete',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kActiveGigSuccessGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small round icon button overlaid on the tracking map (expand / close).
// ─────────────────────────────────────────────────────────────────────────────
class MapRoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const MapRoundButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: Colors.black87),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Overlay chip on the tracking map showing a two-party legend + distance.
// ─────────────────────────────────────────────────────────────────────────────
class MapInfoChip extends StatelessWidget {
  final String primaryLabel;
  final Color primaryDotColor;
  final String secondaryLabel;
  final Color secondaryDotColor;
  const MapInfoChip({
    super.key,
    required this.primaryLabel,
    required this.primaryDotColor,
    required this.secondaryLabel,
    required this.secondaryDotColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: primaryDotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(primaryLabel,
              style: const TextStyle(color: Color(0xFF5A6778), fontSize: 9)),
          const SizedBox(width: 8),
          Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: secondaryDotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(secondaryLabel,
              style: const TextStyle(color: Color(0xFF5A6778), fontSize: 9)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Solid "LIVE" pill shown over the map while location updates are flowing.
// ─────────────────────────────────────────────────────────────────────────────
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kActiveGigSuccessGreen,
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  38px circular action button (call/video/chat) on a gig/worker/host card.
// ─────────────────────────────────────────────────────────────────────────────
class PartyActionCircle extends StatelessWidget {
  final Color bg;
  final Widget child;
  const PartyActionCircle({super.key, required this.bg, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Center(child: child),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Cancel gig section
// ─────────────────────────────────────────────────────────────────────────────
class CancelGigSection extends StatelessWidget {
  final VoidCallback onPressed;
  final String caption;
  final String label;
  const CancelGigSection({
    super.key,
    required this.onPressed,
    required this.caption,
    this.label = 'Cancel gig',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.close_rounded,
                size: 18, color: kActiveGigDestructiveRed),
            label: Text(
              label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: kActiveGigDestructiveRed),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: activeGigCardBg(isDark),
              side: BorderSide(
                  color: activeGigDestructiveBorder(isDark), width: 1),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          caption,
          textAlign: TextAlign.center,
          style: TextStyle(color: activeGigTextDisabled(isDark), fontSize: 9.5),
        ),
      ],
    );
  }
}
