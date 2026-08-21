import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../mock/mock_application.dart';
import '../mock/mock_gig.dart';
import '../mock/mock_host.dart';
import '../models/demo_sequence.dart';
import '../models/demo_step.dart';
import '../models/reading_time.dart';
import '../scenes/host/mock_applicants_scene.dart';
import '../scenes/host/mock_host_status_scene.dart';
import '../scenes/host/mock_post_gig_scene.dart';
import '../scenes/intro/mock_concept_slide_scene.dart';

/// Host → Open Gig: post a gig that needs a specific skill, let skilled
/// workers apply, then pick one.
final hostOpenGigSequence = DemoSequence(
  id: 'demo.host.openGig',
  title: 'Host: Open Gig',
  subtitle: 'Post a gig when a specific skill or qualification is required',
  icon: Icons.work_outline_rounded,
  steps: [
    DemoStep(
      id: 'titleCard',
      duration: readingDurationFor([
        'Open Gig',
        'Watch ${mockMariaSantos.name} post a skill-based gig, review '
            'interested workers, and pick one.',
      ]),
      builder: (_) => MockConceptSlideScene(
        icon: Icons.work_outline_rounded,
        color: kBlue,
        roleLabel: 'Gig Host',
        title: 'Open Gig',
        definition:
            'Watch ${mockMariaSantos.name} post a skill-based gig, review '
            'interested workers, and pick one.',
      ),
    ),
    DemoStep(
      id: 'post',
      duration: readingDurationFor([
        '${mockMariaSantos.name} posts an Open Gig',
        mockOpenGigElectrician.title,
        mockOpenGigElectrician.description,
        mockOpenGigElectrician.requiredSkill ?? '',
        'Post Open Gig',
      ]),
      builder: (_) => MockPostGigFormScene(
        heading: '${mockMariaSantos.name} posts an Open Gig',
        gig: mockOpenGigElectrician,
        requiredSkillLabel: mockOpenGigElectrician.requiredSkill,
        submitLabel: 'Post Open Gig',
      ),
    ),
    DemoStep(
      id: 'posting',
      duration: readingDuration('Posting...'),
      builder: (_) => const MockPostingScene(label: 'Posting...'),
    ),
    DemoStep(
      id: 'liveOnFeed',
      duration: readingDurationFor([
        '"${mockOpenGigElectrician.title}" is now visible to nearby workers',
        '3 skilled workers viewing this gig',
      ]),
      builder: (_) =>
          const MockGigLiveOnWorkerFeedScene(gig: mockOpenGigElectrician),
    ),
    DemoStep(
      id: 'applicantsTrickle',
      duration: readingDurationFor([
        'Interested Workers',
        for (final a in mockOpenGigApplicants)
          '${a.worker.name} ${a.rating} ${a.ratingCount} ${a.completedGigs} gigs done',
      ]),
      builder: (_) =>
          const MockApplicantsScene(applicants: mockOpenGigApplicants),
    ),
    DemoStep(
      id: 'hostSelects',
      duration: readingDurationFor([
        'Host reviews applicants…',
        for (final a in mockOpenGigApplicants) a.worker.name,
      ]),
      builder: (_) => MockApplicantsScene(
        applicants: mockOpenGigApplicants,
        selectedWorkerName: mockOpenGigApplicants.first.worker.name,
      ),
    ),
    DemoStep(
      id: 'hostSeesConfirmed',
      duration: readingDurationFor([
        '${mockOpenGigApplicants.first.worker.name} took the gig',
        mockOpenGigElectrician.title,
        mockOpenGigElectrician.description,
        "${mockOpenGigApplicants.first.worker.name}'s on the way",
      ]),
      builder: (_) => MockHostStatusScene(
        heading:
            '${mockOpenGigApplicants.first.worker.name} took the gig',
        gig: mockOpenGigElectrician,
        status: 'Underway',
        subline: "${mockOpenGigApplicants.first.worker.name}'s on the way",
      ),
    ),
  ],
);
