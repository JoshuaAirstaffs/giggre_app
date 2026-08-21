import 'package:flutter/material.dart';
import '../mock/mock_worker.dart';
import '../models/demo_sequence.dart';
import '../models/demo_step.dart';
import '../models/reading_time.dart';
import '../scenes/intro/mock_concept_slide_scene.dart';
import '../scenes/worker/mock_worker_dashboard_scene.dart';
import '../scenes/worker/mock_worker_status_scene.dart';

/// Worker → Active Mode: go online so hosts can see the worker as
/// available.
final workerActiveModeSequence = DemoSequence(
  id: 'demo.worker.activeMode',
  title: 'Worker: Active Mode',
  subtitle: 'Go online so hosts can see you as available',
  icon: Icons.wifi_tethering_rounded,
  steps: [
    DemoStep(
      id: 'titleCard',
      duration: readingDurationFor(const [
        'Active Mode',
        "Watch a worker go online so hosts can see they're available.",
      ]),
      builder: (_) => const MockConceptSlideScene(
        icon: Icons.wifi_tethering_rounded,
        color: Color(0xFF22C55E),
        roleLabel: 'Gig Worker',
        title: 'Active Mode',
        definition: "Watch a worker go online so hosts can see they're available.",
      ),
    ),
    DemoStep(
      id: 'toggleOn',
      duration: readingDuration(
        'Active Mode Offline hosts can\'t see you as available',
        minimum: const Duration(seconds: 4),
      ),
      builder: (_) => MockWorkerDashboardScene(
        workerName: juanDelaCruz.name,
        activeModeOn: false,
        activeModeFlipAfter: const Duration(milliseconds: 1600),
      ),
    ),
    DemoStep(
      id: 'online',
      duration: readingDurationFor(const [
        "You're online and available for work",
        'Active Mode lets Gig Hosts know you\'re currently available '
            'to take on a gig.',
      ]),
      builder: (_) => const MockWorkerStatusScene(
        icon: Icons.wifi_tethering_rounded,
        title: "You're online and available for work",
        subtitle:
            'Active Mode lets Gig Hosts know you\'re currently available '
            'to take on a gig.',
      ),
    ),
  ],
);
