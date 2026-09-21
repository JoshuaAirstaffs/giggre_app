import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:giggre_app/core/models/rating_review.dart';
import 'package:giggre_app/features/gig_shared/active_gig_theme.dart';
import 'package:giggre_app/features/gig_shared/profile_stats.dart';
import 'package:giggre_app/features/gig_shared/review_card.dart';

RatingReview _review({
  bool? verified,
  String comment =
      'Turned up early and left the place spotless. Would book again without hesitating.',
}) => RatingReview(
  id: 'r1',
  stars: 5,
  raterId: 'rater-1',
  raterName: 'Jonathan Featherstonehaugh',
  gigTitle: 'Kitchen deep clean at the Riverside cafe',
  raterVerified: verified,
  tags: const ['On time', 'Would book again'],
  comment: comment,
  ratedAt: DateTime(2026, 3, 12),
  revealedAt: DateTime(2026, 3, 14),
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool dark = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Scaffold(
        backgroundColor: activeGigScreenBg(dark),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
  // EntranceAnimation waits on a visibility callback that is throttled by
  // default; zero makes it fire within the test's pump budget.
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  VisibilityDetectorController.instance.updateInterval = Duration.zero;

  setUp(() {
    // The narrowest phone the app supports — where a review footer or a
    // three-tile dashboard would overflow if it were going to.
    TestWidgetsFlutterBinding
        .instance
        .platformDispatcher
        .implicitView!
        .physicalSize = const Size(
      360 * 3,
      780 * 3,
    );
    TestWidgetsFlutterBinding
            .instance
            .platformDispatcher
            .implicitView!
            .devicePixelRatio =
        3;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!
        .resetPhysicalSize();
  });

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets(
      'review card shows the rating, comment, gig and date in $theme',
      (tester) async {
        await _pump(
          tester,
          ReviewCard(
            review: _review(verified: true),
            isDark: dark,
            onSurface: activeGigTextPrimary(dark),
          ),
          dark: dark,
        );

        expect(tester.takeException(), isNull);
        expect(find.textContaining('spotless'), findsOneWidget);
        expect(
          find.text('Kitchen deep clean at the Riverside cafe'),
          findsOneWidget,
        );
        expect(find.text('12 Mar 2026'), findsOneWidget);
        expect(find.text('5.0'), findsOneWidget);
        expect(find.text('On time'), findsOneWidget);
      },
    );

    testWidgets('dashboard row of three tiles fits a narrow phone in $theme', (
      tester,
    ) async {
      await _pump(
        tester,
        ProfileStatRow(
          tiles: [
            ProfileStatCard(
              isDark: dark,
              icon: Icons.post_add_rounded,
              accent: const Color(0xFF046BD2),
              label: 'Gigs Completed',
              value: 1284,
            ),
            ProfileStatCard(
              isDark: dark,
              icon: Icons.reviews_rounded,
              accent: const Color(0xFF2E9E6B),
              label: 'Ratings Given',
              value: 347,
            ),
            ProfileStatCard(
              isDark: dark,
              icon: Icons.star_rounded,
              accent: const Color(0xFFB06E00),
              label: 'Average Rating',
              value: 4.8,
              decimals: 1,
              valueSuffixIcon: Icons.star_rounded,
            ),
          ],
        ),
        dark: dark,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Gigs Completed'), findsOneWidget);
      expect(find.text('Ratings Given'), findsOneWidget);
      expect(find.text('Average Rating'), findsOneWidget);
    });
  }

  testWidgets('a review never names its reviewer', (tester) async {
    await _pump(
      tester,
      ReviewCard(
        review: _review(verified: true),
        isDark: false,
        onSurface: activeGigTextPrimary(false),
      ),
    );

    expect(find.textContaining('Jonathan'), findsNothing);
    expect(find.text('Verified reviewer'), findsOneWidget);
  });

  testWidgets('an unverified reviewer is labelled as such', (tester) async {
    await _pump(
      tester,
      ReviewCard(
        review: _review(verified: false),
        isDark: false,
        onSurface: activeGigTextPrimary(false),
      ),
    );

    expect(find.text('Unverified reviewer'), findsOneWidget);
  });

  testWidgets('an unresolved reviewer claims neither', (tester) async {
    await _pump(
      tester,
      ReviewCard(
        review: _review(verified: null),
        isDark: false,
        onSurface: activeGigTextPrimary(false),
      ),
    );

    expect(find.text('Verified reviewer'), findsNothing);
    expect(find.text('Unverified reviewer'), findsNothing);
  });

  testWidgets('an unrated average shows a placeholder, not a zero', (
    tester,
  ) async {
    await _pump(
      tester,
      ProfileStatCard(
        isDark: false,
        icon: Icons.star_rounded,
        accent: const Color(0xFFB06E00),
        label: 'Average Rating',
        value: null,
        decimals: 1,
      ),
    );

    expect(find.text('—'), findsOneWidget);
    expect(find.text('0.0'), findsNothing);
  });

  testWidgets('a stat counts up to its value rather than snapping', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AnimatedCountText(
              value: 100,
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('100'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('100'), findsOneWidget);
  });
}
