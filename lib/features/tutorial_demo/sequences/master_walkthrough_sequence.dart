import 'package:flutter/material.dart';
import '../models/demo_sequence.dart';
import '../models/demo_step.dart';
import 'host_offered_gig_sequence.dart';
import 'host_open_gig_sequence.dart';
import 'host_quick_gig_sequence.dart';
import 'intro_what_is_giggre_sequence.dart';
import 'worker_active_mode_sequence.dart';
import 'worker_direct_offer_sequence.dart';
import 'worker_open_gigs_sequence.dart';
import 'worker_quick_gigs_sequence.dart';
import 'worker_toolchest_sequence.dart';

/// Every individual demo, back to back, exactly as each one plays on its
/// own — nothing shortened or skipped. Order: "What is Giggre?", then
/// every Host gig type, then every Worker feature.
final _sourceSequences = <DemoSequence>[
  introWhatIsGiggreSequence,
  hostQuickGigSequence,
  hostOpenGigSequence,
  hostOfferedGigSequence,
  workerActiveModeSequence,
  workerQuickGigsSequence,
  workerOpenGigsSequence,
  workerToolchestSequence,
  workerDirectOfferSequence,
];

/// Total number of individual steps in the master walkthrough — exposed so
/// the hub can show the viewer roughly how much they're starting.
final masterWalkthroughStepCount = _sourceSequences
    .map((s) => s.steps.length)
    .fold(0, (a, b) => a + b);

/// "The Complete Giggre Walkthrough" — every individual demo/tutorial
/// concatenated into one continuous, fully-automated sequence: the
/// "What is Giggre?" intro, then every Host gig type (Quick/Open/Offered),
/// then every Worker feature (Active Mode/Quick Gigs/Open Gigs/My
/// Toolchest/Offered Gig). Each source sequence's steps are reused as-is —
/// same durations, same scenes, same mock data — just run one after
/// another. Step ids are namespaced per source sequence (`sourceId::stepId`)
/// so two unrelated steps never accidentally share a key across the
/// combined list.
final masterWalkthroughSequence = DemoSequence(
  id: 'demo.master.walkthrough',
  title: 'The Complete Giggre Walkthrough',
  subtitle:
      'Every demo, back to back — from "What is Giggre?" through every '
      'Host and Worker feature ($masterWalkthroughStepCount steps)',
  icon: Icons.auto_awesome_rounded,
  steps: [
    for (final sequence in _sourceSequences)
      for (final step in sequence.steps)
        DemoStep(
          id: '${sequence.id}::${step.id}',
          duration: step.duration,
          builder: step.builder,
        ),
  ],
);
