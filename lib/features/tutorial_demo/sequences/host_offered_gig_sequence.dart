import 'package:flutter/material.dart';
import '../mock/mock_gig.dart';
import '../mock/mock_host.dart';
import '../mock/mock_worker.dart';
import '../models/demo_sequence.dart';
import '../models/demo_step.dart';
import '../models/reading_time.dart';
import '../scenes/host/mock_host_status_scene.dart';
import '../scenes/host/mock_post_gig_scene.dart';
import '../scenes/host/mock_worker_picker_scene.dart';
import '../scenes/intro/mock_concept_slide_scene.dart';
import '../scenes/shared/mock_accepted_scene.dart';
import '../scenes/shared/mock_offered_gig_view_scene.dart';

/// Host → Offered Gig: directly offer a gig to a worker you already know.
/// Mirrors the real flow exactly: tapping the Worker field on the Post
/// Offered Gig screen opens the "Select Gig Worker" sheet before the rest
/// of the form is filled in.
final hostOfferedGigSequence = DemoSequence(
  id: 'demo.host.offeredGig',
  title: 'Host: Offered Gig',
  subtitle: 'Directly offer a gig to a worker you already know',
  icon: Icons.send_rounded,
  steps: [
    DemoStep(
      id: 'titleCard',
      duration: readingDurationFor([
        'Offered Gig',
        "Watch ${mockMariaSantos.name} send a gig directly to a worker "
            "she's hired before.",
      ]),
      builder: (_) => MockConceptSlideScene(
        icon: Icons.send_rounded,
        color: const Color(0xFF8B5CF6),
        roleLabel: 'Gig Host',
        title: 'Offered Gig',
        definition:
            "Watch ${mockMariaSantos.name} send a gig directly to a worker "
            "she's hired before.",
      ),
    ),
    DemoStep(
      id: 'workerPicker',
      duration: readingDurationFor([
        'Select Gig Worker',
        for (final w in mockNearbyWorkers) '${w.name} ${w.skill} Favorite',
      ]),
      builder: (_) => const MockWorkerPickerSheetScene(
        favorites: mockNearbyWorkers,
        selected: juanDelaCruz,
      ),
    ),
    DemoStep(
      id: 'post',
      duration: readingDurationFor([
        'Offer a gig to ${juanDelaCruz.name}',
        mockOfferedGigCeilingLight.title,
        mockOfferedGigCeilingLight.description,
        'Send Offer',
      ]),
      builder: (_) => MockPostGigFormScene(
        heading: 'Offer a gig to ${juanDelaCruz.name}',
        gig: mockOfferedGigCeilingLight,
        workerName: juanDelaCruz.name,
        submitLabel: 'Send Offer',
      ),
    ),
    DemoStep(
      id: 'sending',
      duration: readingDuration('Sending Offer...'),
      builder: (_) => const MockPostingScene(label: 'Sending Offer...'),
    ),
    DemoStep(
      id: 'sent',
      duration: readingDuration(
        'Offer sent to ${juanDelaCruz.name} Waiting for a response…',
      ),
      builder: (_) => const MockOfferSentScene(worker: juanDelaCruz),
    ),
    DemoStep(
      id: 'workerView',
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
      id: 'workerAccepts',
      duration: readingDuration("${juanDelaCruz.name} tapped \"I'm In\"!"),
      builder: (_) => MockAcceptedScene(
        message: "${juanDelaCruz.name} tapped \"I'm In\"!",
      ),
    ),
    DemoStep(
      id: 'hostSeesConfirmed',
      duration: readingDurationFor([
        '${juanDelaCruz.name} confirmed',
        mockOfferedGigCeilingLight.title,
        mockOfferedGigCeilingLight.description,
        "${juanDelaCruz.name}'s on the way",
      ]),
      builder: (_) => MockHostStatusScene(
        heading: '${juanDelaCruz.name} confirmed',
        gig: mockOfferedGigCeilingLight,
        status: 'Underway',
        subline: "${juanDelaCruz.name}'s on the way",
      ),
    ),
  ],
);
