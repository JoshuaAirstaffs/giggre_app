import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/gig_points_models.dart';

const kGigPointsGreen = Color(0xFF22C55E);
const _kPurple = Color(0xFF8B5CF6);

/// One colour + icon per reward stage, used everywhere a stage is shown so
/// the five states are always visually distinct. Gold stays reserved for the
/// available balance — no un-credited stage uses it.
({Color color, IconData icon}) rewardStageStyle(RewardStage stage) =>
    switch (stage) {
      RewardStage.notYetEarned => (color: kBlue, icon: Icons.flag_outlined),
      RewardStage.awaitingApproval => (
        color: _kPurple,
        icon: Icons.rate_review_outlined,
      ),
      RewardStage.approvedProcessing => (
        color: kAmber,
        icon: Icons.hourglass_top_rounded,
      ),
      RewardStage.credited => (
        color: kGigPointsGreen,
        icon: Icons.check_circle_rounded,
      ),
      RewardStage.notEligible => (color: kSub, icon: Icons.block_rounded),
    };

/// Small rounded label in the stage's colour.
class RewardStagePill extends StatelessWidget {
  final RewardStage stage;

  const RewardStagePill({super.key, required this.stage});

  @override
  Widget build(BuildContext context) {
    final color = rewardStageStyle(stage).color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        stage.label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
