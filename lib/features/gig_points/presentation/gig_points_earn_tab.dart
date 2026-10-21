import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/gig_points_models.dart';
import 'reward_stage_style.dart';

/// "How to earn" tab: the configured reward per gig type, the steps from
/// finishing a gig to credited points, and what each reward label means.
/// Values come from general_config/gig_points (display only).
class GigPointsEarnTab extends StatelessWidget {
  final Future<GigPointsConfig?> config;

  const GigPointsEarnTab({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GigPointsConfig?>(
      future: config,
      builder: (context, snap) {
        final loaded = snap.connectionState == ConnectionState.done;
        final c = snap.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionCard(
              title: 'Points per finished gig',
              child: !loaded
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                        child: CircularProgressIndicator(color: kGold),
                      ),
                    )
                  : c == null
                  ? const Text(
                      "Couldn't load the current reward values. Pull down to "
                      'retry.',
                      style: TextStyle(color: kSub, fontSize: 13),
                    )
                  : !c.enabled
                  ? const Text(
                      'Gig Points rewards are paused right now. Points you '
                      'already have are safe.',
                      style: TextStyle(color: kSub, fontSize: 13, height: 1.4),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _RewardTile(
                                icon: Icons.bolt_rounded,
                                label: 'Quick Gig',
                                points: c.pointsFor('quick'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _RewardTile(
                                icon: Icons.campaign_rounded,
                                label: 'Posted Gig',
                                points: c.pointsFor('open'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _RewardTile(
                                icon: Icons.handshake_rounded,
                                label: 'Offered Gig',
                                points: c.pointsFor('offered'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          [
                            'Some gigs carry their own reward, shown on the gig.',
                            if (c.maxPointsPerGig != null)
                              'Max ${c.maxPointsPerGig} pts per gig.',
                            if (!c.hasAnyTypeReward)
                              'Standard rewards aren\'t set up yet.',
                          ].join(' '),
                          style: const TextStyle(
                            color: kSub,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            const _SectionCard(title: 'How it works', child: _Steps()),
            const SizedBox(height: 12),
            const _SectionCard(
              title: 'What the labels mean',
              child: RewardStageLegend(),
            ),
          ],
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _RewardTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? points;

  const _RewardTile({
    required this.icon,
    required this.label,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final p = points;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: kGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kGold.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: kGold, size: 22),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              p == null ? '—' : '$p',
              style: TextStyle(
                color: p == null ? kSub : Theme.of(context).colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            p == null ? 'not set' : 'pts',
            style: const TextStyle(color: kSub, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  static const _steps = [
    (Icons.task_alt_rounded, 'Finish the gig', 'Complete the work as a worker.'),
    (
      Icons.rate_review_outlined,
      'Host approves',
      'The reward is locked in and shows as processing.',
    ),
    (
      Icons.check_circle_rounded,
      'Points credited',
      'Once payment is confirmed they join your available balance.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      children: [
        for (final (i, (icon, title, body)) in _steps.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: kGold.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: kGold, size: 17),
                    ),
                    if (i < _steps.length - 1)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: kGold.withValues(alpha: 0.25),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: 5,
                      bottom: i < _steps.length - 1 ? 16 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: onSurface,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: const TextStyle(
                            color: kSub,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Key to the five reward stages. Used in the tab and the info sheet.
class RewardStageLegend extends StatelessWidget {
  const RewardStageLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final stage in RewardStage.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  rewardStageStyle(stage).icon,
                  size: 18,
                  color: rewardStageStyle(stage).color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stage.label,
                        style: TextStyle(
                          color: rewardStageStyle(stage).color,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stage.countsTowardBalance
                            ? '${stage.explanation} Counts toward your '
                                  'available balance.'
                            : '${stage.explanation} Not part of your '
                                  'available balance.',
                        style: const TextStyle(
                          color: kSub,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
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

/// Opened from the balance card's (i) button.
Future<void> showGigPointsInfoSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final onSurface = Theme.of(ctx).colorScheme.onSurface;
      Widget para(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: onSurface,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              body,
              style: const TextStyle(color: kSub, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'How Gig Points work',
              style: TextStyle(
                color: onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            para(
              'Available balance',
              'Only credited points. You can convert these to GigCash.',
            ),
            para(
              'Processing',
              'Rewards the host has approved, waiting for payment to be '
                  'confirmed. Not spendable yet.',
            ),
            para(
              'On hold',
              'Points reserved by a conversion to GigCash that a Giggre admin '
                  'is reviewing. They come back if it is rejected or you '
                  'cancel it.',
            ),
            para(
              'Conversion',
              'Turn points into GigCash in your Gig Wallet, or GigCash into '
                  'points, at the rates Giggre sets. Each conversion is '
                  'reviewed by a Giggre admin before it goes through, and you '
                  'can have one waiting at a time.',
            ),
            const SizedBox(height: 4),
            const RewardStageLegend(),
          ],
        ),
      );
    },
  );
}
