import 'package:cloud_firestore/cloud_firestore.dart';

/// A rating this user has already submitted for one gig.
///
/// Distinct from [RatingReview], which models a rating someone *received* and
/// carries the reveal/verification machinery a profile needs. This is the
/// short read-back: enough to tell a rater what they left, and whether they
/// left words with it.
class SubmittedRating {
  final int stars;
  final String? comment;
  final List<String> tags;

  const SubmittedRating({
    required this.stars,
    this.comment,
    this.tags = const [],
  });

  /// Whether a written review came with the stars — the comment is optional,
  /// so a rating can exist with nothing to show but its star count.
  bool get hasReview => (comment?.trim().isNotEmpty) ?? false;

  static SubmittedRating fromData(Map<String, dynamic> d) => SubmittedRating(
    stars: (d['stars'] as num?)?.toInt() ?? 0,
    comment: d['comment'] as String?,
    tags: (d['tags'] as List?)?.map((t) => t.toString()).toList() ?? const [],
  );

  static SubmittedRating? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return data == null ? null : fromData(data);
  }
}
