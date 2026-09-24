import '../services/rating_service.dart';

/// A completed gig whose rating this user never submitted.
///
/// The rating dialog used to be offered exactly once, inline at the moment
/// payment was confirmed, and skipping it (or the app dying between the
/// payment sheet and the dialog) lost that rating for good. This is the
/// record that makes a later prompt possible: everything
/// [RatingService.submit] needs, resolved from the gig rather than from
/// whatever screen happened to be open at completion time.
class PendingRating {
  final String gigId;
  final String gigCollection;
  final String gigTitle;

  /// Who this user still owes a rating to, and in which direction.
  final String rateeId;
  final String rateeName;
  final RateeRole rateeRole;

  /// Set only for multi-worker gigs, where the completion lives on the
  /// worker's own `workers/{workerId}` slot doc rather than the gig doc.
  final String? slotWorkerId;

  /// When the gig (or this worker's slot on it) completed — the sort key,
  /// and what decides whether the blind-reveal window has already closed.
  final DateTime? completedAt;

  const PendingRating({
    required this.gigId,
    required this.gigCollection,
    required this.gigTitle,
    required this.rateeId,
    required this.rateeName,
    required this.rateeRole,
    this.slotWorkerId,
    this.completedAt,
  });

  /// The id the rating will be written under — also what identifies this
  /// entry, since one (gig, rater, ratee) triple can only ever be rated once.
  String ratingIdFor(String raterId) => RatingService.ratingId(
    gigCollection: gigCollection,
    gigId: gigId,
    raterId: raterId,
    rateeId: rateeId,
  );

  /// True once the counterpart rating has been revealed on its own by the
  /// `revealStaleRatings` sweep, meaning a rating submitted now is no longer
  /// blind — this rater could have read what the other side said first.
  ///
  /// Nothing blocks a late rating on this; it is here so a surface can say
  /// so, and so [RatingService.pendingFor] can be filtered if that policy
  /// ever changes.
  bool get isPastRevealWindow {
    final at = completedAt;
    if (at == null) return false;
    return DateTime.now().difference(at) >
        const Duration(days: RatingService.revealAfterDays);
  }
}
