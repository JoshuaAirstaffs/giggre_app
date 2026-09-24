import 'package:flutter_test/flutter_test.dart';

import 'package:giggre_app/core/models/pending_rating.dart';
import 'package:giggre_app/core/services/rating_service.dart';

PendingRating _pending({DateTime? completedAt}) => PendingRating(
  gigId: 'gig1',
  gigCollection: 'open_gigs',
  gigTitle: 'Move a sofa',
  rateeId: 'worker1',
  rateeName: 'Ada',
  rateeRole: RateeRole.worker,
  completedAt: completedAt,
);

void main() {
  test('rating id matches the id RatingService will write under', () {
    // The create rule rejects any other id, so a pending entry that computed
    // its own id differently would look unrated forever — it would never match
    // what ratingsGivenBy returns.
    expect(
      _pending().ratingIdFor('host1'),
      RatingService.ratingId(
        gigCollection: 'open_gigs',
        gigId: 'gig1',
        raterId: 'host1',
        rateeId: 'worker1',
      ),
    );
  });

  group('isPastRevealWindow', () {
    test('is false inside the blind window', () {
      final justInside = DateTime.now().subtract(
        const Duration(days: RatingService.revealAfterDays - 1),
      );
      expect(_pending(completedAt: justInside).isPastRevealWindow, isFalse);
    });

    test('is true once the sweep would have revealed the counterpart', () {
      final past = DateTime.now().subtract(
        const Duration(days: RatingService.revealAfterDays + 1),
      );
      expect(_pending(completedAt: past).isPastRevealWindow, isTrue);
    });

    test('is false when the completion time is unknown', () {
      // Better to treat an undated gig as still blind than to claim the
      // counterpart is already visible on no evidence.
      expect(_pending().isPastRevealWindow, isFalse);
    });
  });
}
