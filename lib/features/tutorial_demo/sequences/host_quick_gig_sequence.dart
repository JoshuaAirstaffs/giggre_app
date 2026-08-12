import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../mock/mock_gig.dart';
import '../mock/mock_host.dart';
import '../mock/mock_match.dart';
import '../mock/mock_worker.dart';
import '../models/demo_sequence.dart';
import '../models/demo_step.dart';
import '../models/reading_time.dart';
import '../scenes/host/mock_host_status_scene.dart';
import '../scenes/host/mock_matching_scene.dart';
import '../scenes/host/mock_post_gig_scene.dart';
import '../scenes/host/mock_searching_scene.dart';
import '../scenes/intro/mock_concept_slide_scene.dart';
import '../scenes/shared/mock_accepted_scene.dart';
import '../scenes/shared/mock_quick_gig_offer_scene.dart';

/// Host → Quick Gig: post an instant gig, watch it get matched to a nearby
/// worker, and see the worker get assigned. All timings below are the one
/// place to retune this sequence's pacing.
final hostQuickGigSequence = DemoSequence(
  id: 'demo.host.quickGig',
  title: 'Host: Quick Gig',
  subtitle: 'Create an instant gig and get matched with a nearby worker',
  icon: Icons.flash_on_rounded,
  steps: [
    DemoStep(
      id: 'titleCard',
      duration: readingDurationFor([
        'Quick Gig',
        'Watch ${mockMariaSantos.name} post an instant gig and get matched '
            'with a nearby worker in real time.',
      ]),
      builder: (_) => MockConceptSlideScene(
        icon: Icons.flash_on_rounded,
        color: kAmber,
        roleLabel: 'Gig Host',
        title: 'Quick Gig',
        definition:
            'Watch ${mockMariaSantos.name} post an instant gig and get '
            'matched with a nearby worker in real time.',
      ),
    ),
    DemoStep(
      id: 'post',
      duration: readingDurationFor([
        '${mockMariaSantos.name} posts a Quick Gig',
        mockQuickGigPackage.title,
        mockQuickGigPackage.description,
        'Post Quick Gig',
      ]),
      builder: (_) => MockPostGigFormScene(
        heading: '${mockMariaSantos.name} posts a Quick Gig',
        gig: mockQuickGigPackage,
        submitLabel: 'Post Quick Gig',
      ),
    ),
    DemoStep(
      id: 'posting',
      duration: readingDuration('Posting...'),
      builder: (_) => const MockPostingScene(label: 'Posting...'),
    ),
    DemoStep(
      id: 'searching',
      duration: readingDurationFor(const [
        'Looking for a Worker…',
        'Searching for available workers nearby',
      ]),
      builder: (_) => const MockSearchingScene(),
    ),
    DemoStep(
      id: 'workersFound',
      duration: readingDurationFor([
        'A few workers nearby…',
        for (final w in mockNearbyWorkers) '${w.name} ${w.distanceMiles} mi',
      ]),
      builder: (_) => const MockWorkersFoundScene(workers: mockNearbyWorkers),
    ),
    DemoStep(
      id: 'matching',
      duration: readingDurationFor([
        'Matching…',
        for (final w in mockQuickGigMatch.candidates) w.name,
      ]),
      builder: (_) => const MockMatchingScene(match: mockQuickGigMatch),
    ),
    DemoStep(
      id: 'workerOffer',
      duration: readingDurationFor([
        'Quick Gig Offer!',
        mockQuickGigPackage.title,
        mockQuickGigPackage.description,
        '\$${mockQuickGigPackage.payment}',
        mockQuickGigPackage.location,
      ]),
      builder: (_) => const MockQuickGigOfferScene(gig: mockQuickGigPackage),
    ),
    DemoStep(
      id: 'accepted',
      duration: readingDuration('${juanDelaCruz.name} accepted the gig!'),
      builder: (_) => MockAcceptedScene(
        message: '${juanDelaCruz.name} accepted the gig!',
      ),
    ),
    DemoStep(
      id: 'hostSeesAssigned',
      duration: readingDurationFor([
        '${juanDelaCruz.name} is on the way',
        mockQuickGigPackage.title,
        mockQuickGigPackage.description,
        "${juanDelaCruz.name}'s on the way",
      ]),
      builder: (_) => MockHostStatusScene(
        heading: '${juanDelaCruz.name} is on the way',
        gig: mockQuickGigPackage,
        status: 'Underway',
        subline: "${juanDelaCruz.name}'s on the way",
      ),
    ),
  ],
);
