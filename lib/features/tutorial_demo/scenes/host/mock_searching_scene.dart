import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../mock/mock_worker.dart';
import '../../widgets/demo_fade_in.dart';
import '../../widgets/demo_pulse_highlight.dart';
import '../../widgets/demo_theme.dart';
import '../../widgets/demo_worker_tile.dart';

/// "Searching for a Worker" radar scene, shown right after a Quick Gig is
/// posted.
class MockSearchingScene extends StatelessWidget {
  const MockSearchingScene({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DemoPulseRing(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.travel_explore_rounded,
                color: kGold,
                size: 38,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Looking for a Worker…',
            style: TextStyle(
              color: dTitle,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Searching for available workers nearby',
            style: TextStyle(color: dBody, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Nearby workers appear one by one, each with the sort of factors a match
/// might weigh (distance, Active Mode, Quick Gigs, performance).
class MockWorkersFoundScene extends StatelessWidget {
  final List<MockWorkerData> workers;
  const MockWorkersFoundScene({super.key, required this.workers});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A few workers nearby…',
            style: TextStyle(
              color: dTitle,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Illustrative example — not the exact matching algorithm',
            style: TextStyle(color: dBody, fontSize: 11.5),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < workers.length; i++)
            DemoFadeIn(
              delay: Duration(milliseconds: 200 + i * 350),
              child: DemoWorkerTile(worker: workers[i]),
            ),
        ],
      ),
    );
  }
}
