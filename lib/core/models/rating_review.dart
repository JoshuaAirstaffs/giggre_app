import 'package:cloud_firestore/cloud_firestore.dart';

/// One revealed rating, as shown on someone's profile.
///
/// Reads straight off a `ratings` document — the gig title and both parties'
/// names are denormalised there at submit time, so rendering a review never
/// has to fetch the gig or the rater.
class RatingReview {
  final String id;
  final int stars;
  final List<String> tags;
  final String? comment;

  /// The rating's author. Profiles deliberately never render the name: a
  /// review is attributed by the reviewer's verification standing
  /// ([raterVerified]) instead, so it reads as a trust signal rather than a
  /// name-to-name exchange. Both are kept because reporting and moderation
  /// still need to know who wrote it.
  final String raterId;
  final String raterName;

  /// Whether the reviewer's identity is verified — null while unknown (the
  /// lookup failed, or nothing resolved it).
  ///
  /// Resolved when the reviews are fetched rather than stored on the rating
  /// document: a denormalised copy would be written by the rater's own
  /// client, and it would go stale the moment they verified.
  final bool? raterVerified;

  final String gigTitle;
  final DateTime? ratedAt;

  /// Ordering key for the reviews list, and the cursor for paging it —
  /// distinct from [ratedAt], which is when the rating was written rather
  /// than when it became visible.
  final DateTime? revealedAt;

  const RatingReview({
    required this.id,
    required this.stars,
    required this.raterId,
    required this.raterName,
    required this.gigTitle,
    this.raterVerified,
    this.tags = const [],
    this.comment,
    this.ratedAt,
    this.revealedAt,
  });

  bool get hasDetail => tags.isNotEmpty || (comment?.isNotEmpty ?? false);

  /// Same review with the reviewer's verification standing filled in. Takes
  /// the value positionally so that passing null explicitly means "still
  /// unknown" rather than "leave what was there", as a copyWith would.
  RatingReview withRaterVerified(bool? verified) => RatingReview(
    id: id,
    stars: stars,
    raterId: raterId,
    raterName: raterName,
    gigTitle: gigTitle,
    raterVerified: verified,
    tags: tags,
    comment: comment,
    ratedAt: ratedAt,
    revealedAt: revealedAt,
  );

  factory RatingReview.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    return RatingReview(
      id: doc.id,
      stars: (d['stars'] as num?)?.toInt() ?? 0,
      tags: List<String>.from(d['tags'] as List? ?? const []),
      comment: (d['comment'] as String?)?.trim(),
      raterId: d['raterId'] as String? ?? '',
      raterName: d['raterName'] as String? ?? '',
      gigTitle: d['gigTitle'] as String? ?? 'Gig',
      ratedAt: (d['createdAt'] as Timestamp?)?.toDate(),
      revealedAt: (d['revealedAt'] as Timestamp?)?.toDate(),
    );
  }
}
