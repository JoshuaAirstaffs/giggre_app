import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/rating_review.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/entrance_animation.dart';
import 'active_gig_theme.dart';
import 'profile_stats.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Review card — one revealed rating, shared by the profile sheet and the
//  full profile screen so both render a review identically.
//
//  Reviewers are never named. What a reader needs from a stranger's review is
//  how much to trust it, and that is the reviewer's verification standing, not
//  a first name they have never seen before — so the footer carries a
//  verified/unverified badge where the name used to be.
// ─────────────────────────────────────────────────────────────────────────────
class ReviewCard extends StatelessWidget {
  final RatingReview review;
  final bool isDark;
  final Color onSurface;

  /// Staggers the entrance against the cards above it, so a page of reviews
  /// arrives in sequence instead of all at once.
  final Duration animationDelay;

  const ReviewCard({
    super.key,
    required this.review,
    required this.isDark,
    required this.onSurface,
    this.animationDelay = Duration.zero,
  });

  static const _verifiedGreen = Color(0xFF2E9E6B);

  @override
  Widget build(BuildContext context) {
    final muted = activeGigTextMuted(isDark);
    final secondary = activeGigTextSecondary(isDark);
    final comment = review.comment?.trim() ?? '';

    return EntranceAnimation(
      type: EntranceAnimationType.fadeInSlideUp,
      duration: const Duration(milliseconds: 420),
      delay: animationDelay,
      slideOffset: 16,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
        decoration: BoxDecoration(
          color: activeGigCardBg(isDark),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: activeGigCardBorder(isDark)),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.22)
                  : const Color(0xFF17263D).withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedStarRating(
                  rating: review.stars.toDouble(),
                  size: 15,
                  gap: 1.5,
                  emptyColor: activeGigTrackBg(isDark),
                ),
                const SizedBox(width: 7),
                Text(
                  '${review.stars}.0',
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (review.ratedAt != null)
                  Text(
                    DateFormat('d MMM y').format(review.ratedAt!),
                    style: TextStyle(color: muted, fontSize: 10.5),
                  ),
              ],
            ),
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                comment,
                style: TextStyle(color: secondary, fontSize: 13, height: 1.45),
              ),
            ],
            if (review.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final t in review.tags) _tag(t)],
              ),
            ],
            const SizedBox(height: 11),
            Divider(height: 1, color: activeGigDividerColor(isDark)),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.work_outline_rounded, size: 13, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    review.gigTitle,
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Absent only when the lookup failed — better to say nothing
                // than to imply an unverified reviewer.
                if (review.raterVerified != null) ...[
                  const SizedBox(width: 8),
                  _reviewerBadge(review.raterVerified!),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: kGold.withValues(alpha: isDark ? 0.14 : 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: kGold.withValues(alpha: 0.28)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: isDark ? kGold : const Color(0xFFB06E00),
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  /// Who left this, as far as a reader should care: a verified reviewer has
  /// passed identity checks, an unverified one has not.
  Widget _reviewerBadge(bool verified) {
    final color = verified ? _verifiedGreen : activeGigTextMuted(isDark);
    final label = verified ? 'Verified reviewer' : 'Unverified reviewer';

    return Tooltip(
      message: verified
          ? 'This reviewer has passed identity verification'
          : 'This reviewer has not been identity-verified',
      child: Container(
        padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: verified ? 0.12 : 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              verified ? Icons.verified_rounded : Icons.shield_outlined,
              size: 11,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
