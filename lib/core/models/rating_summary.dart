import '../services/rating_service.dart';

/// A user's rating in one direction, read from the `ratingWorker` /
/// `ratingHost` aggregate that the `onRatingCreated` Cloud Function maintains
/// from the `ratings` collection.
///
/// Nothing here consults the superseded flat fields (`ratingAsWorker`,
/// `ratingCount`, `ratingAsHost`, `ratingAsHostCount`). A user who has not
/// been rated through the ratings collection has no rating, whatever those
/// fields still say — which after the cutover is almost everyone.
class RatingSummary {
  /// Mirrors RATING_PRIOR_MEAN / RATING_PRIOR_WEIGHT in
  /// functions/src/ratings.ts, which computes the stored `shrunk` value.
  static const priorMean = 4.6;
  static const priorWeight = 5;

  final int count;
  final double sum;

  /// Average shrunk toward [priorMean] — defined even at zero ratings, so
  /// ranking never has to invent a value. Display code should use [average]
  /// and [label] instead; this is for sorting and scoring only.
  final double shrunk;

  /// Star value → how many ratings gave it.
  final Map<int, int> histogram;

  const RatingSummary({
    required this.count,
    required this.sum,
    required this.shrunk,
    this.histogram = const {},
  });

  static const empty = RatingSummary(
    count: 0,
    sum: 0,
    shrunk: (priorWeight * priorMean) / priorWeight,
  );

  bool get hasRatings => count > 0;

  /// Null until the user has been rated at least once — deliberately not a
  /// default like 5.0, which would make every unrated user look perfect.
  double? get average => count == 0 ? null : sum / count;

  /// Which aggregate field holds this direction on a user document.
  static String fieldFor(RateeRole role) =>
      role == RateeRole.worker ? 'ratingWorker' : 'ratingHost';

  factory RatingSummary.fromUserData(
    Map<String, dynamic>? data,
    RateeRole role,
  ) {
    final raw = data?[fieldFor(role)] as Map<String, dynamic>?;
    final count = (raw?['count'] as num?)?.toInt() ?? 0;
    if (raw == null || count <= 0) return empty;

    final sum = (raw['sum'] as num?)?.toDouble() ?? 0;
    return RatingSummary(
      count: count,
      sum: sum,
      shrunk:
          (raw['shrunk'] as num?)?.toDouble() ??
          (priorWeight * priorMean + sum) / (priorWeight + count),
      histogram: {
        for (final e in (raw['histogram'] as Map<String, dynamic>? ?? {}).entries)
          if (int.tryParse(e.key) != null)
            int.parse(e.key): (e.value as num?)?.toInt() ?? 0,
      },
    );
  }

  /// '4.8' once rated, '—' before that. For tight spots like list rows.
  String get shortLabel =>
      hasRatings ? average!.toStringAsFixed(1) : '—';

  /// '4.8 (12)' once rated, 'No ratings yet' before that.
  String get label =>
      hasRatings ? '${average!.toStringAsFixed(1)} ($count)' : 'No ratings yet';
}
