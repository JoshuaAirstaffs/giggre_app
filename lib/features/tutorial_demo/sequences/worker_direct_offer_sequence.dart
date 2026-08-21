import 'package:flutter/material.dart';
import '../mock/mock_gig.dart';
import '../mock/mock_host.dart';
import '../models/demo_sequence.dart';
import '../models/demo_step.dart';
import '../models/reading_time.dart';
import '../scenes/intro/mock_concept_slide_scene.dart';
import '../scenes/shared/mock_accepted_scene.dart';
import '../scenes/shared/mock_info_panel_scene.dart';
import '../scenes/shared/mock_offered_gig_view_scene.dart';
import '../scenes/worker/mock_notification_intro_scene.dart';

/// Worker → Offered Gig: a host who already knows the worker sends a gig
/// straight to them.
final workerDirectOfferSequence = DemoSequence(
  id: 'demo.worker.directOffer',
  title: 'Worker: Offered Gig',
  subtitle: 'Receive a gig offered directly to you by a host',
  icon: Icons.send_rounded,
  steps: [
    DemoStep(
      id: 'titleCard',
      duration: readingDurationFor(const [
        'Offered Gig',
        'Watch a worker receive and accept a gig offered directly to them.',
      ]),
      builder: (_) => const MockConceptSlideScene(
        icon: Icons.send_rounded,
        color: Color(0xFF8B5CF6),
        roleLabel: 'Gig Worker',
        title: 'Offered Gig',
        definition:
            'Watch a worker receive and accept a gig offered directly to '
            'them.',
      ),
    ),
    DemoStep(
      id: 'notification',
      duration: readingDuration(
        'New Gig Offer from ${mockMariaSantos.name} '
        '${mockOfferedGigCeilingLight.title}',
      ),
      builder: (_) => const MockNotificationIntroScene(),
    ),
    DemoStep(
      id: 'offerDetail',
      duration: readingDurationFor([
        mockOfferedGigCeilingLight.title,
        mockOfferedGigCeilingLight.description,
        mockOfferedGigCeilingLight.requiredSkill ?? '',
        '\$${mockOfferedGigCeilingLight.payment}',
        mockMariaSantos.name,
      ]),
      builder: (_) => MockOfferedGigViewScene(
        gig: mockOfferedGigCeilingLight,
        hostName: mockMariaSantos.name,
      ),
    ),
    DemoStep(
      id: 'accepted',
      duration: readingDuration(
        'Offer accepted! ${mockMariaSantos.name} has been notified.',
      ),
      builder: (_) => MockAcceptedScene(
        message: 'Offer accepted! ${mockMariaSantos.name} has been notified.',
      ),
    ),
    DemoStep(
      id: 'reminder',
      duration: readingDurationFor(const [
        'Never miss an Offered Gig',
        'Keep Giggre notifications enabled so hosts can reach you directly.',
      ]),
      builder: (_) => const MockInfoPanelScene(
        title: 'Never miss an Offered Gig',
        bullets: [
          'Keep Giggre notifications enabled so hosts can reach you directly.',
        ],
      ),
    ),
  ],
);
