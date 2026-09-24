import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/models/submitted_rating.dart';
import '../../core/services/rating_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/rating_dialog.dart';
import '../reports/models/report_content_type.dart';
import '../reports/report_service.dart';
import 'active_gig_theme.dart';

/// "Rate & review" + "Report" for a gig that has already finished.
///
/// The rating dialog is otherwise offered exactly once, inline at the moment
/// payment is confirmed (gig_detail_sheet, gig_progress_tracker, working_ui),
/// and it has a Skip button — so skipping, or the app dying between the
/// payment sheet and the dialog, used to lose that rating permanently. Nothing
/// server-side expires the right to rate: a completed gig keeps its document
/// and the `ratings` create rule has no time window, so this offers it again
/// from any surface that lists finished gigs.
///
/// Reporting had the same shape of gap: the flow itself is generic, but its
/// only entry points (profile, live gig map, chat) are all reachable while the
/// gig is live and mostly gone once it closes.
class PostGigActions extends StatefulWidget {
  final String gigId;
  final String gigCollection;
  final String gigTitle;

  /// Who is being rated/reported, and in which direction.
  final String rateeId;
  final String rateeName;
  final RateeRole rateeRole;

  /// Set for multi-worker gigs — the rating is scoped to that worker's own
  /// slot doc rather than the gig doc.
  final String? slotWorkerId;

  /// Recorded on the report so an admin can see where it came from.
  final String surface;

  /// Compact lays everything out as one short row for a list card; the
  /// default is a full-width stack for a detail sheet.
  final bool compact;

  /// Fired after a rating is actually stored, for callers that show their own
  /// summary of what is still outstanding.
  final VoidCallback? onRated;

  /// Every rating the signed-in user has given, keyed by rating id, for
  /// callers rendering many of these — one [RatingService.ratingsGivenBy]
  /// query instead of a read per row. Null looks this gig up on its own.
  final Map<String, SubmittedRating>? ratingsGiven;

  const PostGigActions({
    super.key,
    required this.gigId,
    required this.gigCollection,
    required this.gigTitle,
    required this.rateeId,
    required this.rateeName,
    required this.rateeRole,
    required this.surface,
    this.slotWorkerId,
    this.compact = false,
    this.onRated,
    this.ratingsGiven,
  });

  @override
  State<PostGigActions> createState() => _PostGigActionsState();
}

class _PostGigActionsState extends State<PostGigActions> {
  /// False until we know one way or the other. Neither the invitation to rate
  /// nor the summary of an existing rating is shown before then, so a gig
  /// that turns out to be rated never flashes a "Rate & review" button first.
  bool _resolved = false;

  /// What this user already left for this gig, null when they never rated it.
  SubmittedRating? _rating;

  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _seedOrLookUp();
  }

  @override
  void didUpdateWidget(PostGigActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rateeId != widget.rateeId ||
        oldWidget.gigId != widget.gigId ||
        oldWidget.gigCollection != widget.gigCollection) {
      _resolved = false;
      _rating = null;
      _seedOrLookUp();
    }
  }

  /// The id this gig's rating is stored under, or null while signed out.
  String? get _ratingId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || widget.rateeId.isEmpty) return null;
    return RatingService.ratingId(
      gigCollection: widget.gigCollection,
      gigId: widget.gigId,
      raterId: uid,
      rateeId: widget.rateeId,
    );
  }

  void _seedOrLookUp() {
    final given = widget.ratingsGiven;
    final id = _ratingId;
    if (given != null && id != null) {
      // The caller resolved every rating in one query — a missing key means
      // unrated, not unknown, so this costs no read at all.
      _resolved = true;
      _rating = given[id];
      return;
    }
    _refreshRating();
  }

  Future<void> _refreshRating() async {
    if (widget.rateeId.isEmpty) return;
    try {
      final rating = await RatingService.myRating(
        gigCollection: widget.gigCollection,
        gigId: widget.gigId,
        rateeId: widget.rateeId,
      );
      if (mounted) {
        setState(() {
          _rating = rating;
          _resolved = true;
        });
      }
    } catch (e) {
      // Leaving it unresolved hides the invitation rather than offering a
      // rating that would be rejected as a duplicate on submit.
      debugPrint('[PostGigActions] rating lookup failed: $e');
    }
  }

  Future<void> _rate() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await RatingDialog.show(
        context: context,
        rateeId: widget.rateeId,
        rateeName: widget.rateeName,
        rateeRole: widget.rateeRole,
        gigId: widget.gigId,
        gigCollection: widget.gigCollection,
        gigTitle: widget.gigTitle,
        slotWorkerId: widget.slotWorkerId,
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
    if (!mounted) return;
    // The dialog resolves to null whether the rating was submitted or
    // skipped, so the stored rating is what decides — not the return value.
    final had = _rating != null;
    await _refreshRating();
    if (mounted && _rating != null && !had) widget.onRated?.call();
  }

  Future<void> _report() => ReportService.show(
    context,
    contentType: ReportContentType.user,
    contentId: widget.rateeId,
    // Left to ReportService, which falls back to the reported user's bio for
    // a user report — there is no authored content to quote here.
    contentSnapshot: '',
    contentAuthorId: widget.rateeId,
    surface: widget.surface,
    gigId: widget.gigId,
    title: 'Report ${widget.rateeName}',
    // What went wrong on the gig, not what someone posted. The default list
    // is content moderation and has no way to say the work was left unfinished
    // or the payment came in under what was agreed.
    reasons: widget.rateeRole == RateeRole.worker
        ? ReportService.gigReasonsAboutWorker
        : ReportService.gigReasonsAboutHost,
  );

  /// What the rater left, for the already-rated state: the stars they gave,
  /// and whether words came with them.
  String get _summaryLabel {
    final rating = _rating;
    if (rating == null) return '';
    return rating.hasReview
        ? 'You reviewed ${widget.rateeName}'
        : 'You rated ${widget.rateeName}';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (widget.rateeId.isEmpty || uid == null || uid == widget.rateeId) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rating = _rating;
    final showRate = _resolved && rating == null;
    final showSummary = _resolved && rating != null;

    if (widget.compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showRate) ...[
            // Loose flex, so a long name ellipsizes inside the chip instead
            // of overflowing a narrow list card.
            Flexible(
              child: _CompactAction(
                icon: Icons.rate_review_rounded,
                label: 'Rate & review ${widget.rateeName}',
                color: kAmber,
                onTap: _opening ? null : _rate,
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (showSummary) ...[
            Flexible(
              child: _CompactAction(
                icon: rating.hasReview
                    ? Icons.rate_review_rounded
                    : Icons.star_rounded,
                label: rating.hasReview
                    ? '${rating.stars}★ · reviewed'
                    : '${rating.stars}★ rated',
                color: kSub,
                onTap: null,
              ),
            ),
            const SizedBox(width: 8),
          ],
          _CompactAction(
            icon: Icons.flag_outlined,
            label: 'Report',
            color: Colors.orange,
            onTap: _report,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showRate) ...[
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _opening ? null : _rate,
              icon: const Icon(Icons.rate_review_rounded, size: 18),
              style: ElevatedButton.styleFrom(
                backgroundColor: kAmber,
                foregroundColor: Colors.black87,
                disabledBackgroundColor: kAmber.withValues(alpha: 0.4),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              label: Text(
                'Rate & review ${widget.rateeName}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This gig is done but unrated — your stars and review still count '
            'toward ${widget.rateeRole == RateeRole.worker ? 'their worker' : 'their host'} profile.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: activeGigTextMuted(isDark),
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (showSummary) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: activeGigCardBg(isDark),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: activeGigCardBorder(isDark)),
            ),
            child: Row(
              children: [
                for (var star = 1; star <= 5; star++)
                  Icon(
                    star <= rating.stars
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 16,
                    color: star <= rating.stars ? kAmber : kSub,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _summaryLabel,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: activeGigTextPrimary(isDark),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (rating.hasReview) ...[
            const SizedBox(height: 8),
            Text(
              '“${rating.comment!.trim()}”',
              style: TextStyle(
                color: activeGigTextMuted(isDark),
                fontSize: 12,
                height: 1.45,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 10),
        ],
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _report,
            icon: const Icon(
              Icons.flag_outlined,
              size: 17,
              color: Colors.orange,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange,
              side: BorderSide(color: Colors.orange.withValues(alpha: 0.45)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            label: Text(
              'Report ${widget.rateeName}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _CompactAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
