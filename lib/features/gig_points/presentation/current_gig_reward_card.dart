import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../widgets/active_gig_bar.dart';
import '../models/gig_points_models.dart';
import '../services/gig_points_service.dart';
import 'reward_stage_style.dart';

/// Live reward status of the worker's in-progress gig: how many points it's
/// set to pay, why, and how far along it is toward being credited.
///
/// Reuses watchActiveWorkerGig (active_gig_bar.dart) — the same source the
/// home screen's Active Gig bar uses — so there's no competing notion of
/// "the current gig". Renders nothing when there isn't one.
///
/// Never shows these points as available: until the backend records the
/// reward as credited it's labelled with its stage, in that stage's colour.
class CurrentGigRewardCard extends StatefulWidget {
  final String uid;
  final Future<GigPointsConfig?> config;

  const CurrentGigRewardCard({
    super.key,
    required this.uid,
    required this.config,
  });

  @override
  State<CurrentGigRewardCard> createState() => _CurrentGigRewardCardState();
}

class _CurrentGigRewardCardState extends State<CurrentGigRewardCard> {
  late final Stream<ActiveGigInfo?> _activeGig = watchActiveWorkerGig(
    widget.uid,
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ActiveGigInfo?>(
      stream: _activeGig,
      builder: (context, snap) {
        final gig = snap.data;
        if (gig == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _ActiveGigReward(
            key: ValueKey('${gig.gigCollection}/${gig.id}'),
            uid: widget.uid,
            gig: gig,
            config: widget.config,
          ),
        );
      },
    );
  }
}

class _ActiveGigReward extends StatefulWidget {
  final String uid;
  final ActiveGigInfo gig;
  final Future<GigPointsConfig?> config;

  const _ActiveGigReward({
    super.key,
    required this.uid,
    required this.gig,
    required this.config,
  });

  @override
  State<_ActiveGigReward> createState() => _ActiveGigRewardState();
}

class _ActiveGigRewardState extends State<_ActiveGigReward> {
  late final Stream<Map<String, dynamic>?> _gigDoc = GigPointsService.gigStream(
    widget.gig.gigCollection,
    widget.gig.id,
  );
  late final Stream<GigPointsTransaction?> _entry =
      GigPointsService.taskEntryStream(
        widget.uid,
        gigCollection: widget.gig.gigCollection,
        gigId: widget.gig.id,
      );

  /// Before a ledger entry exists, the stage comes from the gig's own status
  /// (same status values as active_gig_bar.dart / working_ui.dart).
  RewardStage _stageFromGigStatus(String status) => switch (status) {
    'task_complete' => RewardStage.awaitingApproval,
    // Host has approved; the backend is creating the pending entry.
    'payment' => RewardStage.approvedProcessing,
    _ => RewardStage.notYetEarned,
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GigPointsConfig?>(
      future: widget.config,
      builder: (context, configSnap) => StreamBuilder<Map<String, dynamic>?>(
        stream: _gigDoc,
        builder: (context, gigSnap) => StreamBuilder<GigPointsTransaction?>(
          stream: _entry,
          builder: (context, entrySnap) {
            final config = configSnap.data;
            final entry = entrySnap.data;
            final gigData = gigSnap.data;
            if (config == null && entry == null) return const SizedBox.shrink();
            if (entry == null && config?.enabled == false) {
              return const SizedBox.shrink();
            }

            final stage = entry?.stage ?? _stageFromGigStatus(widget.gig.status);
            final int? points;
            final String amountWhy;
            if (entry != null) {
              // Backend-recorded value wins once it exists.
              points = entry.points;
              amountWhy = entry.amountExplanation;
            } else {
              final collection = widget.gig.gigCollection;
              final quote = config!.quote(
                gigType:
                    gigData?['gigType'] as String? ??
                    switch (collection) {
                      'quick_gigs' => 'quick',
                      'open_gigs' => 'open',
                      _ => 'offered',
                    },
                gigPointsReward: gigData?['gigPointsReward'],
              );
              points = quote?.points;
              amountWhy =
                  quote?.explanation ??
                  'No reward has been set for this gig or its type, so no '
                      'points will be awarded automatically. Giggre is '
                      'notified if it reaches approval without one.';
            }
            return _CardBody(
              title: widget.gig.title,
              stage: stage,
              points: points,
              amountWhy: amountWhy,
            );
          },
        ),
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  final String title;
  final RewardStage stage;

  /// Null when no reward is configured for this gig.
  final int? points;
  final String amountWhy;

  const _CardBody({
    required this.title,
    required this.stage,
    required this.points,
    required this.amountWhy,
  });

  @override
  Widget build(BuildContext context) {
    final style = rewardStageStyle(stage);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: style.color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(style.icon, color: style.color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Current gig reward',
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              RewardStagePill(stage: stage),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                points == null ? 'No reward set' : '$points pts',
                style: TextStyle(
                  color: points == null ? kSub : style.color,
                  fontSize: points == null ? 14 : 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              stage == RewardStage.credited ? 'In your balance' : 'Not in your balance yet',
              style: const TextStyle(color: kSub, fontSize: 11.5),
            ),
          ),
          const SizedBox(height: 12),
          _StageProgress(stage: stage),
          const SizedBox(height: 12),
          Text(
            stage.explanation,
            style: TextStyle(color: onSurface, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 6),
          Text(
            amountWhy,
            style: const TextStyle(color: kSub, fontSize: 12.5, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// Four-step track toward credit: earned → approval → processing → credited.
class _StageProgress extends StatelessWidget {
  final RewardStage stage;

  const _StageProgress({required this.stage});

  static const _track = [
    RewardStage.notYetEarned,
    RewardStage.awaitingApproval,
    RewardStage.approvedProcessing,
    RewardStage.credited,
  ];

  @override
  Widget build(BuildContext context) {
    final current = _track.indexOf(stage);
    final activeColor = rewardStageStyle(stage).color;
    return Row(
      children: [
        for (var i = 0; i < _track.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i <= current
                    ? activeColor
                    : Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
