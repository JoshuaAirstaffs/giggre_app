import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:giggre_app/core/services/rating_service.dart';
import 'package:giggre_app/features/gig_shared/active_gig_theme.dart';
import 'package:giggre_app/features/gig_shared/work_history.dart';
import 'package:giggre_app/features/gig_shared/work_history_widgets.dart';

final _now = DateTime(2026, 9, 19);

CompletedEngagement _gig(
  String gigId,
  String counterpartyId, {
  int daysAgo = 1,
  String collection = 'open_gigs',
}) => CompletedEngagement(
  gigId: gigId,
  gigCollection: collection,
  counterpartyId: counterpartyId,
  completedAt: _now.subtract(Duration(days: daysAgo)),
);

/// Pumps without settling: the active-profile pulse never stops, and
/// pumpAndSettle would wait for it forever. One long pump lands every
/// finite animation on its final frame instead.
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
  await tester.pump(const Duration(milliseconds: 1800));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The narrowest phone the app supports — where "of 14 hosts booked them
    // again" beside a count and a percentage would overflow if it were going
    // to.
    TestWidgetsFlutterBinding
        .instance
        .platformDispatcher
        .implicitView!
        .physicalSize = const Size(360 * 3, 780 * 3);
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

  group('WorkHistoryStats', () {
    test('an empty history claims nothing', () {
      final stats = WorkHistoryStats.from(const [], now: _now);
      expect(stats.hasHistory, isFalse);
      expect(stats.isActive, isFalse);
      expect(stats.hasRepeatRate, isFalse);
      expect(stats.repeatRate, isNull);
      expect(stats.lastCompletedAt, isNull);
    });

    test('recency counts the last 30 days and dates the most recent gig', () {
      final stats = WorkHistoryStats.from([
        _gig('a', 'host-1', daysAgo: 2),
        _gig('b', 'host-2', daysAgo: 21),
        _gig('c', 'host-3', daysAgo: 45),
        _gig('d', 'host-4', daysAgo: 400),
      ], now: _now);

      expect(stats.recentGigs, 2);
      expect(stats.isActive, isTrue);
      expect(stats.lastCompletedAt, _now.subtract(const Duration(days: 2)));
    });

    test('a multi-worker gig is one gig, however many slots it carried', () {
      // What a host's four slots on one gig look like coming back: four
      // engagements sharing a gig id. Counting rows here would quadruple the
      // month's work.
      final stats = WorkHistoryStats.from([
        for (final w in ['w1', 'w2', 'w3', 'w4']) _gig('a', w, daysAgo: 3),
      ], now: _now);

      expect(stats.recentGigs, 1);
      expect(stats.partners, 4);
      expect(stats.repeatPartners, 0);
    });

    test('a second gig with the same host is a repeat, a second slot is not', () {
      final stats = WorkHistoryStats.from([
        _gig('a', 'host-1', daysAgo: 60),
        _gig('b', 'host-1', daysAgo: 10),
        _gig('c', 'host-2', daysAgo: 30),
        // Same gig arriving twice — from its top-level doc and from the slot
        // doc — must not read as the host coming back.
        _gig('d', 'host-3', daysAgo: 5),
        _gig('d', 'host-3', daysAgo: 5),
      ], now: _now);

      expect(stats.partners, 3);
      expect(stats.repeatPartners, 1);
      expect(stats.repeatRate, closeTo(1 / 3, 0.001));
    });

    test('one host who did not come back is not a repeat rate', () {
      final stats = WorkHistoryStats.from([
        _gig('a', 'host-1', daysAgo: 4),
      ], now: _now);

      expect(stats.partners, 1);
      expect(stats.hasRepeatRate, isFalse);
      expect(stats.repeatRate, isNull);
    });

    test('shared history counts only gigs with the viewer', () {
      final stats = WorkHistoryStats.from([
        _gig('a', 'host-1', daysAgo: 200),
        _gig('b', 'host-1', daysAgo: 12),
        _gig('c', 'host-2', daysAgo: 3),
      ], viewerId: 'host-1', now: _now);

      expect(stats.sharedGigs, 2);
      expect(stats.lastSharedAt, _now.subtract(const Duration(days: 12)));
      expect(stats.hasSharedHistory, isTrue);
    });

    test('no viewer means no shared history', () {
      final stats = WorkHistoryStats.from([
        _gig('a', 'host-1', daysAgo: 3),
      ], now: _now);

      expect(stats.sharedGigs, 0);
      expect(stats.hasSharedHistory, isFalse);
    });

    test('an engagement with no counterparty still counts as work done', () {
      // A multi-worker gig's top-level document carries no worker id at all.
      final stats = WorkHistoryStats.from([
        _gig('a', '', daysAgo: 6),
      ], now: _now);

      expect(stats.recentGigs, 1);
      expect(stats.partners, 0);
    });
  });

  group('work history widgets', () {
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';

      testWidgets('an active worker reads as active in $theme', (tester) async {
        await _pump(
          tester,
          WorkHistoryBody(
            stats: WorkHistoryStats(
              recentGigs: 4,
              lastCompletedAt: DateTime(2026, 9, 14),
              partners: 14,
              repeatPartners: 5,
            ),
            role: RateeRole.worker,
            accent: const Color(0xFF2B6FB5),
            isDark: dark,
          ),
          dark: dark,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Active this month'), findsOneWidget);
        expect(
          find.text('4 gigs completed in the last 30 days'),
          findsOneWidget,
        );
        expect(find.text('of 14 hosts booked them again'), findsOneWidget);
        expect(find.text('5'), findsOneWidget);
        expect(find.text('36'), findsOneWidget);
      });

      testWidgets('a quiet worker is dated, not called active in $theme', (
        tester,
      ) async {
        await _pump(
          tester,
          WorkHistoryBody(
            stats: WorkHistoryStats(
              lastCompletedAt: DateTime(2026, 4, 2),
              partners: 3,
              repeatPartners: 0,
            ),
            role: RateeRole.worker,
            accent: const Color(0xFF2B6FB5),
            isDark: dark,
          ),
          dark: dark,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Last gig Apr 2026'), findsOneWidget);
        expect(find.text('Nothing completed in the last 30 days'), findsOneWidget);
        expect(find.text('Active this month'), findsNothing);
        expect(find.text('of 3 hosts booked them again'), findsOneWidget);
        // Both the count and the percentage are zero — no repeats is a
        // number the card is willing to show.
        expect(find.text('0'), findsNWidgets(2));
      });

      testWidgets('a host profile talks about workers in $theme', (
        tester,
      ) async {
        await _pump(
          tester,
          WorkHistoryBody(
            stats: WorkHistoryStats(
              recentGigs: 1,
              lastCompletedAt: DateTime(2026, 9, 17),
              partners: 2,
              repeatPartners: 1,
            ),
            role: RateeRole.host,
            accent: const Color(0xFFB06E00),
            isDark: dark,
          ),
          dark: dark,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('1 gig completed in the last 30 days'), findsOneWidget);
        expect(find.text('of 2 workers came back for more'), findsOneWidget);
        expect(find.text('50'), findsOneWidget);
      });

      testWidgets('too few counterparties hides the repeat bar in $theme', (
        tester,
      ) async {
        await _pump(
          tester,
          WorkHistoryBody(
            stats: WorkHistoryStats(
              recentGigs: 1,
              lastCompletedAt: DateTime(2026, 9, 18),
              partners: 1,
            ),
            role: RateeRole.worker,
            accent: const Color(0xFF2B6FB5),
            isDark: dark,
          ),
          dark: dark,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Active this month'), findsOneWidget);
        expect(find.textContaining('booked them again'), findsNothing);
      });

      testWidgets('shared history names the count and the date in $theme', (
        tester,
      ) async {
        await _pump(
          tester,
          SharedHistoryBanner(
            stats: WorkHistoryStats(
              sharedGigs: 3,
              lastSharedAt: DateTime(2026, 7, 9),
            ),
            isDark: dark,
          ),
          dark: dark,
        );

        expect(tester.takeException(), isNull);
        expect(find.text("You've worked together 3 times"), findsOneWidget);
        expect(find.text('Most recently Jul 2026'), findsOneWidget);
      });

      testWidgets('one shared gig reads as once in $theme', (tester) async {
        await _pump(
          tester,
          SharedHistoryBanner(
            stats: WorkHistoryStats(
              sharedGigs: 1,
              lastSharedAt: DateTime(2026, 7, 9),
            ),
            isDark: dark,
          ),
          dark: dark,
        );

        expect(find.text("You've worked together once"), findsOneWidget);
      });

      testWidgets('no shared history draws nothing in $theme', (tester) async {
        await _pump(
          tester,
          const SharedHistoryBanner(
            stats: WorkHistoryStats.empty,
            isDark: false,
          ),
          dark: dark,
        );

        expect(find.byIcon(Icons.handshake_rounded), findsNothing);
      });
    }
  });
}
