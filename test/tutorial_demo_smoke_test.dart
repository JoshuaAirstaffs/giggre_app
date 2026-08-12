import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giggre_app/features/tutorial_demo/demo_hub_screen.dart';
import 'package:giggre_app/features/tutorial_demo/models/demo_sequence.dart';
import 'package:giggre_app/features/tutorial_demo/player/demo_player_screen.dart';
import 'package:giggre_app/features/tutorial_demo/sequences/host_offered_gig_sequence.dart';
import 'package:giggre_app/features/tutorial_demo/sequences/host_open_gig_sequence.dart';
import 'package:giggre_app/features/tutorial_demo/sequences/host_quick_gig_sequence.dart';
import 'package:giggre_app/features/tutorial_demo/sequences/how_giggre_works_sequence.dart';
import 'package:giggre_app/features/tutorial_demo/sequences/intro_what_is_giggre_sequence.dart';
import 'package:giggre_app/features/tutorial_demo/sequences/master_walkthrough_sequence.dart';
import 'package:giggre_app/features/tutorial_demo/sequences/worker_active_mode_sequence.dart';
import 'package:giggre_app/features/tutorial_demo/sequences/worker_direct_offer_sequence.dart';
import 'package:giggre_app/features/tutorial_demo/sequences/worker_open_gigs_sequence.dart';
import 'package:giggre_app/features/tutorial_demo/sequences/worker_quick_gigs_sequence.dart';
import 'package:giggre_app/features/tutorial_demo/sequences/worker_toolchest_sequence.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Always linked from the hub screen, one plain "<title>" row each: every
// Gig Host demo plus every Gig Worker demo.
final _hubVisibleSequences = <DemoSequence>[
  hostQuickGigSequence,
  hostOpenGigSequence,
  hostOfferedGigSequence,
  workerActiveModeSequence,
  workerQuickGigsSequence,
  workerOpenGigsSequence,
  workerToolchestSequence,
  workerDirectOfferSequence,
];
final _hubFeaturedSequence = introWhatIsGiggreSequence;

// Dev-only: rendered as featured "Watch: <title>" / custom-label rows, only
// when the "Watch Demo: full library" dev toggle is on.
final _hubHiddenSequences = <DemoSequence>[
  howGiggreWorksSequence,
  masterWalkthroughSequence,
];

final _everyPlayableSequence = <DemoSequence>[
  _hubFeaturedSequence,
  ..._hubVisibleSequences,
  ..._hubHiddenSequences,
];

void main() {
  testWidgets(
    'demo hub shows "What is Giggre?" plus Gig Host and Gig Worker by '
    'default',
    (tester) async {
      // No dev toggles set — isDemoHubFullLibraryEnabled() must default to
      // false.
      SharedPreferences.setMockInitialValues({});

      // Tall enough viewport that every sequence row is built without
      // scrolling — the hub's ListView otherwise only mounts (and starts
      // animating) rows near the visible viewport, same as any real list.
      tester.view.physicalSize = const Size(400, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: TutorialDemoHubScreen()),
      );
      // The hub's entrance animations settle within ~1.5s, but its pulsing
      // logo ring animation repeats forever — pumpAndSettle would wait for
      // it indefinitely, so pump a bounded amount instead. The initial
      // pump also lets the async dev-flag lookup in initState resolve.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));

      for (final sequence in _hubVisibleSequences) {
        expect(find.text(sequence.title), findsOneWidget);
      }
      expect(
        find.text('Watch: ${_hubFeaturedSequence.title}'),
        findsOneWidget,
      );
      expect(
        find.text('Browse gigs, use your skills, and get paid.'),
        findsOneWidget,
      );

      // The dev-only featured rows should not appear anywhere on the hub
      // screen.
      for (final sequence in _hubHiddenSequences) {
        expect(find.text('Watch: ${sequence.title}'), findsNothing);
      }
      expect(find.text('Watch the full walkthrough'), findsNothing);
      expect(find.text('DEV'), findsNothing);

      await tester.tap(find.text(hostQuickGigSequence.title));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(DemoPlayerScreen), findsOneWidget);
    },
  );

  testWidgets(
    'demo hub also shows "How Giggre Works" and the full walkthrough when '
    'the dev toggle is on',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'devToggle.watchDemoHub.showEverything': true,
      });

      tester.view.physicalSize = const Size(400, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: TutorialDemoHubScreen()),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));

      for (final sequence in _hubVisibleSequences) {
        expect(find.text(sequence.title), findsOneWidget);
      }
      expect(
        find.text('Watch: ${_hubFeaturedSequence.title}'),
        findsOneWidget,
      );
      expect(
        find.text('Watch: ${howGiggreWorksSequence.title}'),
        findsOneWidget,
      );
      expect(find.text('Watch the full walkthrough'), findsOneWidget);
      expect(find.text('DEV'), findsWidgets);
    },
  );

  testWidgets('tapping the content area advances to the next step early', (
    tester,
  ) async {
    final sequence = hostQuickGigSequence;
    await tester.pumpWidget(
      MaterialApp(home: DemoPlayerScreen(sequence: sequence)),
    );
    await tester.pump();

    expect(find.text('1 / ${sequence.steps.length}'), findsOneWidget);

    // Tap well before the first step's own duration would have elapsed.
    await tester.tap(find.byKey(const Key('demoTapToAdvance')));
    await tester.pump();

    expect(find.text('2 / ${sequence.steps.length}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final sequence in _everyPlayableSequence) {
    testWidgets(
      '${sequence.id} plays through every step automatically with no taps',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: DemoPlayerScreen(sequence: sequence)),
        );
        await tester.pump();

        for (final step in sequence.steps) {
          await tester.pump(step.duration + const Duration(milliseconds: 50));
        }
        // Let the completion overlay's own transitions settle.
        await tester.pump(const Duration(milliseconds: 500));

        expect(tester.takeException(), isNull);
        expect(find.text("That's the demo!"), findsOneWidget);

        // Replay resets to the first step without leaving the player.
        await tester.tap(find.text('Replay'));
        await tester.pump();
        expect(find.text("That's the demo!"), findsNothing);
      },
    );
  }
}
