import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/rating_service.dart';
import 'active_gig_theme.dart';
import 'profile_stats.dart';
import 'work_history.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  The profile's track record — what [WorkHistoryStats] looks like on screen.
//
//  Two pieces, deliberately apart: the shared-history banner is about the
//  reader ("you two have worked together"), so it sits above the dashboard
//  where they will see it first; the track record itself is about the person
//  being read, so it sits with the other numbers.
// ─────────────────────────────────────────────────────────────────────────────

String _monthYear(DateTime d) => DateFormat('MMM y').format(d);

String _count(int n, String singular, String plural) =>
    '$n ${n == 1 ? singular : plural}';

/// "You've worked together 3 times" — shown only when the viewer and the
/// profile have actually finished a gig together.
///
/// The strongest signal on the page when it appears, because it is the one
/// the reader can verify from their own memory, so it gets the full width and
/// a sweep of light as it lands.
class SharedHistoryBanner extends StatelessWidget {
  final WorkHistoryStats stats;
  final bool isDark;

  const SharedHistoryBanner({
    super.key,
    required this.stats,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (!stats.hasSharedHistory) return const SizedBox.shrink();

    const accent = kActiveGigSuccessGreen;
    final times = stats.sharedGigs;
    final last = stats.lastSharedAt;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return ProfileEntrance(
      slideOffset: 16,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.38)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: isDark ? 0.24 : 0.14),
              accent.withValues(alpha: isDark ? 0.10 : 0.05),
            ],
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: isDark ? 0.28 : 0.16),
                      ),
                      child: const Icon(
                        Icons.handshake_rounded,
                        size: 18,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            times == 1
                                ? "You've worked together once"
                                : "You've worked together $times times",
                            style: TextStyle(
                              color: activeGigTextPrimary(isDark),
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          if (last != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Most recently ${_monthYear(last)}',
                              style: TextStyle(
                                color: activeGigTextSecondary(isDark),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!reduceMotion)
                Positioned.fill(
                  child: IgnorePointer(
                    // One pass of light across the banner as it arrives. The
                    // gradient's stops travel rather than a child sliding, so
                    // nothing here can affect the layout it sits over.
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: -0.7, end: 1.7),
                      duration: const Duration(milliseconds: 1500),
                      curve: Curves.easeInOutCubic,
                      builder: (_, t, _) => DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(t - 0.45, -1),
                            end: Alignment(t + 0.45, 1),
                            colors: [
                              Colors.transparent,
                              Colors.white.withValues(
                                alpha: isDark ? 0.09 : 0.3,
                              ),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The body of the "Track record" card: how recently this person worked, and
/// how often the other side came back.
///
/// Rendered without its own card shell so the profile screen can drop it into
/// the same one every other section uses.
class WorkHistoryBody extends StatelessWidget {
  final WorkHistoryStats stats;
  final RateeRole role;

  /// The role accent as it reads on the page background — the repeat bar and
  /// its percentage take it, so the card belongs to the same profile as the
  /// header above it.
  final Color accent;
  final bool isDark;

  const WorkHistoryBody({
    super.key,
    required this.stats,
    required this.role,
    required this.accent,
    required this.isDark,
  });

  /// Who the counterparties are, from the side being looked at.
  String get _partnerWord => role == RateeRole.worker ? 'host' : 'worker';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _activity(),
        if (stats.hasRepeatRate) ...[
          Divider(height: 22, color: activeGigDividerColor(isDark)),
          _repeat(),
        ],
      ],
    );
  }

  /// Recency. A pulsing dot for someone working now, a clock for someone who
  /// isn't — the difference a lifetime total cannot show.
  Widget _activity() {
    final last = stats.lastCompletedAt;
    final active = stats.isActive;

    final title = active
        ? 'Active this month'
        : last == null
        ? 'No completed gigs yet'
        : 'Last gig ${_monthYear(last)}';

    final subtitle = active
        ? '${_count(stats.recentGigs, 'gig', 'gigs')} completed in the last 30 days'
        : last == null
        ? null
        : 'Nothing completed in the last 30 days';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 24,
          child: Center(
            child: active
                ? const PulseDot(color: kActiveGigSuccessGreen)
                : Icon(
                    Icons.history_rounded,
                    size: 17,
                    color: activeGigTextMuted(isDark),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: active
                      ? kActiveGigSuccessGreen
                      : activeGigTextPrimary(isDark),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: activeGigTextSecondary(isDark),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Repeat hires: the count sweeps up while the bar sweeps out, so the
  /// number and the proportion land together.
  Widget _repeat() {
    final rate = stats.repeatRate ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  AnimatedCountText(
                    value: stats.repeatPartners.toDouble(),
                    style: TextStyle(
                      color: accent,
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      height: 1.05,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      role == RateeRole.worker
                          ? 'of ${_count(stats.partners, _partnerWord, '${_partnerWord}s')} booked them again'
                          : 'of ${_count(stats.partners, _partnerWord, '${_partnerWord}s')} came back for more',
                      style: TextStyle(
                        color: activeGigTextSecondary(isDark),
                        fontSize: 12.5,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.2 : 0.11),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedCountText(
                    value: rate * 100,
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '%',
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AnimatedMeterBar(fraction: rate, color: accent, isDark: isDark),
      ],
    );
  }
}
