import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../mock/mock_gig.dart';
import '../mock/mock_skill.dart';
import '../mock/mock_worker.dart';
import '../models/demo_sequence.dart';
import '../models/demo_step.dart';
import '../models/reading_time.dart';
import '../scenes/intro/mock_concept_slide_scene.dart';
import '../scenes/shared/mock_info_panel_scene.dart';
import '../scenes/worker/mock_gig_apply_scene.dart';
import '../scenes/worker/mock_toolchest_scene.dart';

/// Worker → My Toolchest: manage skills, and see how a newly-approved skill
/// unlocks an Open Gig that needs it.
final workerToolchestSequence = DemoSequence(
  id: 'demo.worker.toolchest',
  title: 'Worker: My Toolchest',
  subtitle: 'Manage your skills — new ones need admin approval first',
  icon: Icons.construction_rounded,
  steps: [
    DemoStep(
      id: 'titleCard',
      duration: readingDurationFor(const [
        'My Toolchest',
        'Watch a worker add a new skill and get it approved.',
      ]),
      builder: (_) => const MockConceptSlideScene(
        icon: Icons.construction_rounded,
        color: kGold,
        roleLabel: 'Gig Worker',
        title: 'My Toolchest',
        definition: 'Watch a worker add a new skill and get it approved.',
      ),
    ),
    DemoStep(
      id: 'navigate',
      duration: readingDuration('Profile Avatar My Toolchest'),
      builder: (_) => const MockToolchestEntryScene(),
    ),
    DemoStep(
      id: 'existingSkills',
      duration: readingDurationFor([
        'My Toolchest',
        for (final s in mockExistingSkills) '${s.name} ${s.status}',
      ]),
      builder: (_) =>
          const MockToolchestSkillsScene(skills: mockExistingSkills),
    ),
    DemoStep(
      id: 'addSkillPending',
      duration: readingDuration(
        '${mockNewSkillPending.name} ${mockNewSkillPending.status}',
      ),
      builder: (_) => const MockToolchestSkillsScene(
        skills: mockExistingSkills,
        newSkill: mockNewSkillPending,
      ),
    ),
    DemoStep(
      id: 'addSkillApproved',
      duration: readingDuration(
        '${mockNewSkillApproved.name} ${mockNewSkillApproved.status}',
      ),
      builder: (_) => const MockToolchestSkillsScene(
        skills: mockExistingSkills,
        newSkill: mockNewSkillApproved,
      ),
    ),
    DemoStep(
      id: 'reminder',
      duration: readingDurationFor(const [
        'Keep your skills updated',
        'Add new skills any time in My Toolchest.',
        'New skills need admin approval before you can take gigs that require them.',
      ]),
      builder: (_) => const MockInfoPanelScene(
        title: 'Keep your skills updated',
        bullets: [
          'Add new skills any time in My Toolchest.',
          'New skills need admin approval before you can take gigs that require them.',
        ],
      ),
    ),
    DemoStep(
      id: 'backToOpenGig',
      duration: readingDurationFor([
        mockOpenGigElectrician.title,
        mockOpenGigElectrician.description,
      ]),
      builder: (_) => const MockGigApplyScene(
        gig: mockOpenGigElectrician,
        worker: juanDelaCruz,
        skillMatches: true,
      ),
    ),
  ],
);
