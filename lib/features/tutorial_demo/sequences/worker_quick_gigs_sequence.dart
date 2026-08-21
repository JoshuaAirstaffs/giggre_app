import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../mock/mock_gig.dart';
import '../mock/mock_worker.dart';
import '../models/demo_sequence.dart';
import '../models/demo_step.dart';
import '../models/reading_time.dart';
import '../scenes/intro/mock_concept_slide_scene.dart';
import '../scenes/shared/mock_accepted_scene.dart';
import '../scenes/shared/mock_info_panel_scene.dart';
import '../scenes/shared/mock_quick_gig_offer_scene.dart';
import '../scenes/worker/mock_worker_dashboard_scene.dart';

/// Worker → Quick Gigs: instant gig opportunities that don't require a
/// specific skill.
final workerQuickGigsSequence = DemoSequence(
  id: 'demo.worker.quickGigs',
  title: 'Worker: Quick Gigs',
  subtitle: 'Instant gig opportunities that don\'t require a specific skill',
  icon: Icons.flash_on_rounded,
  steps: [
    DemoStep(
      id: 'titleCard',
      duration: readingDurationFor(const [
        'Quick Gigs',
        'Watch a worker receive and take an instant gig offer.',
      ]),
      builder: (_) => const MockConceptSlideScene(
        icon: Icons.flash_on_rounded,
        color: kAmber,
        roleLabel: 'Gig Worker',
        title: 'Quick Gigs',
        definition: 'Watch a worker receive and take an instant gig offer.',
      ),
    ),
    DemoStep(
      id: 'toggleOn',
      duration: readingDuration(
        'Quick Gigs',
        minimum: const Duration(seconds: 3),
      ),
      builder: (_) => MockWorkerDashboardScene(
        workerName: juanDelaCruz.name,
        activeModeOn: true,
        quickGigsOn: false,
        quickGigsFlipAfter: const Duration(milliseconds: 1200),
      ),
    ),
    DemoStep(
      id: 'explain',
      duration: readingDurationFor(const [
        'What are Quick Gigs?',
        'Instant gig opportunities — no specific skill required.',
        'You can Take It or Pass on each one.',
        'Your availability and distance from the host may be considered.',
      ]),
      builder: (_) => const MockInfoPanelScene(
        title: 'What are Quick Gigs?',
        bullets: [
          'Instant gig opportunities — no specific skill required.',
          'You can Take It or Pass on each one.',
          'Your availability and distance from the host may be considered.',
        ],
      ),
    ),
    DemoStep(
      id: 'offerArrives',
      duration: readingDurationFor([
        'A Quick Gig just came in',
        mockQuickGigPackage.title,
        mockQuickGigPackage.description,
        '\$${mockQuickGigPackage.payment}',
      ]),
      builder: (_) => const MockQuickGigOfferScene(
        gig: mockQuickGigPackage,
        perspectiveLabel: 'A Quick Gig just came in',
      ),
    ),
    DemoStep(
      id: 'accepted',
      duration: readingDuration('Gig taken!'),
      builder: (_) => const MockAcceptedScene(message: 'Gig taken!'),
    ),
    DemoStep(
      id: 'declineInfo',
      duration: readingDurationFor(const [
        'Good to know',
        'Acceptance and performance may be considered when matching future Quick Gigs.',
        'Declines are monitored — check Decline Information for details.',
        'These are illustrative factors, not a guarantee of the exact matching algorithm.',
      ]),
      builder: (_) => const MockInfoPanelScene(
        title: 'Good to know',
        bullets: [
          'Acceptance and performance may be considered when matching future Quick Gigs.',
          'Declines are monitored — check Decline Information for details.',
        ],
        footnote:
            'These are illustrative factors, not a guarantee of the exact matching algorithm.',
      ),
    ),
  ],
);
