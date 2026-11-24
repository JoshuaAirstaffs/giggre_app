// TEMPLATE: copy to integration_test/map_render_perf_test.dart (after adding
// `integration_test: {sdk: flutter}` to dev_dependencies, with permission).
// See ../reference/maps-device-testing.md.
//
// Measures the worker gig map on a real device: time until the GoogleMap
// widget appears, then frame timings while panning and zooming. It signs in
// with an email/password DEV test account passed via --dart-define, so no
// Google sign-in UI is needed. It creates no data.
//
//   flutter drive --profile --flavor dev \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/map_render_perf_test.dart \
//     --dart-define=FLAVOR=dev \
//     --dart-define=LT_EMAIL=<dev test account> --dart-define=LT_PASSWORD=<password>
//
// test_driver/integration_test.dart:
//   import 'package:integration_test/integration_test_driver.dart';
//   Future<void> main() => integrationDriver();
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:giggre_app/main.dart' as app;

const _email = String.fromEnvironment('LT_EMAIL');
const _password = String.fromEnvironment('LT_PASSWORD');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('worker gig map: ready time and pan/zoom frame timings', (tester) async {
    assert(_email.isNotEmpty && _password.isNotEmpty, 'pass LT_EMAIL / LT_PASSWORD');
    app.main(); // initialises Firebase for FLAVOR=dev
    await tester.pumpAndSettle(const Duration(seconds: 5));
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: _email, password: _password);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    }

    // ADAPT: navigate Home → Worker → the map. Keys/texts below match 3.0.7;
    // update them if the UI changes.
    final worker = find.textContaining('Gig Worker');
    if (worker.evaluate().isNotEmpty) {
      await tester.tap(worker.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    }
    final mapToggle = find.byTooltip('Map view');
    if (mapToggle.evaluate().isNotEmpty) {
      await tester.tap(mapToggle.first);
    }

    final sw = Stopwatch()..start();
    while (find.byType(GoogleMap).evaluate().isEmpty && sw.elapsed < const Duration(seconds: 30)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    binding.reportData = <String, dynamic>{'mapWidgetReadyMs': sw.elapsedMilliseconds};
    expect(find.byType(GoogleMap), findsWidgets, reason: 'map did not appear (navigation needs adapting?)');
    await tester.pump(const Duration(seconds: 3)); // tiles + markers

    final map = find.byType(GoogleMap).first;
    await binding.traceAction(() async {
      for (var i = 0; i < 6; i++) {
        await tester.drag(map, Offset(i.isEven ? -250 : 250, i.isEven ? 120 : -120));
        await tester.pump(const Duration(milliseconds: 600));
      }
      // Pinch-zoom approximation: two-finger gestures moving apart, then together.
      for (final spread in [120.0, -120.0, 120.0]) {
        final c = tester.getCenter(map);
        final g1 = await tester.startGesture(c - const Offset(40, 0));
        final g2 = await tester.startGesture(c + const Offset(40, 0));
        await g1.moveBy(Offset(-spread, 0));
        await g2.moveBy(Offset(spread, 0));
        await g1.up();
        await g2.up();
        await tester.pump(const Duration(milliseconds: 800)); // re-cluster on zoom change
      }
    }, reportKey: 'map_pan_zoom');
  });
}
