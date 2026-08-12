import 'package:flutter/material.dart';
import '../../widgets/demo_availability_card.dart';
import '../../widgets/demo_work_preferences_card.dart';
import '../../widgets/demo_worker_header_bar.dart';

/// Worker dashboard backdrop reused by the Active Mode and Quick Gigs
/// sequences — a self-contained visual fork of the real dashboard (see
/// [DemoWorkerHeaderBar]/[DemoAvailabilityCard]/[DemoWorkPreferencesCard]
/// for why this isn't the production widget tree).
class MockWorkerDashboardScene extends StatelessWidget {
  final String workerName;
  final bool activeModeOn;
  final Duration? activeModeFlipAfter;
  final bool quickGigsOn;
  final Duration? quickGigsFlipAfter;

  const MockWorkerDashboardScene({
    super.key,
    required this.workerName,
    this.activeModeOn = false,
    this.activeModeFlipAfter,
    this.quickGigsOn = false,
    this.quickGigsFlipAfter,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DemoWorkerHeaderBar(name: workerName),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              DemoAvailabilityCard(
                initiallyOnline: activeModeOn,
                flipAfter: activeModeFlipAfter,
              ),
              const SizedBox(height: 12),
              DemoWorkPreferencesCard(
                initiallyOn: quickGigsOn,
                flipAfter: quickGigsFlipAfter,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
