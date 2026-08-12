import 'package:flutter/material.dart';
import '../../mock/mock_match.dart';
import '../../widgets/demo_theme.dart';
import '../../widgets/demo_worker_tile.dart';

/// Narrows the candidate list down to the worker the demo will show
/// receiving the offer, greying out the others.
class MockMatchingScene extends StatelessWidget {
  final MockMatchData match;
  const MockMatchingScene({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Matching…',
            style: TextStyle(
              color: dTitle,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          for (final worker in match.candidates)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 500),
              opacity: worker.name == match.selected.name ? 1 : 0.35,
              child: DemoWorkerTile(
                worker: worker,
                selected: worker.name == match.selected.name,
                trailingLabel:
                    worker.name == match.selected.name ? 'Best match' : null,
              ),
            ),
        ],
      ),
    );
  }
}
