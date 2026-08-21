import 'package:flutter/material.dart';
import '../../widgets/demo_fade_in.dart';
import '../../widgets/demo_host_worker_connector.dart';
import '../../widgets/demo_theme.dart';

/// Second slide — explains the two-sided marketplace with a bigger version
/// of the same Host↔Worker connector shown on the hub screen.
class MockTwoSidedScene extends StatelessWidget {
  const MockTwoSidedScene({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'One app, two sides',
              style: TextStyle(color: dTitle, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text(
              'Every gig on Giggre connects a Host who needs something done '
              'with a Worker ready to do it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: dBody, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 32),
            DemoFadeIn(
              delay: const Duration(milliseconds: 300),
              child: const DemoHostWorkerConnector(scale: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
