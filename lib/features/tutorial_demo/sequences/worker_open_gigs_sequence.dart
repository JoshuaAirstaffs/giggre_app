import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../mock/mock_gig.dart';
import '../mock/mock_worker.dart';
import '../models/demo_sequence.dart';
import '../models/demo_step.dart';
import '../models/reading_time.dart';
import '../scenes/intro/mock_concept_slide_scene.dart';
import '../scenes/shared/mock_info_panel_scene.dart';
import '../scenes/worker/mock_gig_apply_scene.dart';
import '../scenes/worker/mock_map_list_scene.dart';

/// Worker → Open Gigs: browse the Map/List, check required skills against
/// your verified skills, and take one.
final workerOpenGigsSequence = DemoSequence(
  id: 'demo.worker.openGigs',
  title: 'Worker: Open Gigs',
  subtitle: 'Browse the map or list and take a gig with your verified skills',
  icon: Icons.map_outlined,
  steps: [
    DemoStep(
      id: 'titleCard',
      duration: readingDurationFor(const [
        'Open Gigs',
        'Watch a worker browse gigs and take one that matches their '
            'verified skills.',
      ]),
      builder: (_) => const MockConceptSlideScene(
        icon: Icons.map_outlined,
        color: kBlue,
        roleLabel: 'Gig Worker',
        title: 'Open Gigs',
        definition:
            'Watch a worker browse gigs and take one that matches their '
            'verified skills.',
      ),
    ),
    DemoStep(
      id: 'mapView',
      duration: readingDuration(
        '${mockOpenGigElectrician.title} Clean the yard Move furniture',
      ),
      builder: (_) => const MockOpenGigMapListScene(isMapView: true),
    ),
    DemoStep(
      id: 'listView',
      duration: readingDuration(
        '${mockOpenGigElectrician.title} Clean the yard Move furniture',
      ),
      builder: (_) => const MockOpenGigMapListScene(isMapView: false),
    ),
    DemoStep(
      id: 'detailNoMatch',
      duration: readingDurationFor([
        mockOpenGigElectrician.title,
        mockOpenGigElectrician.description,
        'Missing skill: ${mockOpenGigElectrician.requiredSkill}',
        "You can pass anytime before you're selected",
      ]),
      builder: (_) => const MockGigApplyScene(
        gig: mockOpenGigElectrician,
        worker: carloGarcia,
        skillMatches: false,
      ),
    ),
    DemoStep(
      id: 'explain',
      duration: readingDurationFor(const [
        'Only verified skills unlock Take Gig',
        'The Take Gig button is greyed out until your verified skills match what the gig needs.',
        'Manage your skills any time in My Toolchest.',
      ]),
      builder: (_) => const MockInfoPanelScene(
        title: 'Only verified skills unlock Take Gig',
        bullets: [
          'The Take Gig button is greyed out until your verified skills match what the gig needs.',
          'Manage your skills any time in My Toolchest.',
        ],
      ),
    ),
    DemoStep(
      id: 'detailMatch',
      duration: readingDurationFor([
        mockOpenGigElectrician.title,
        mockOpenGigElectrician.description,
        "You have this skill (Verified) You can pass anytime before you're selected",
      ]),
      builder: (_) => const MockGigApplyScene(
        gig: mockOpenGigElectrician,
        worker: juanDelaCruz,
        skillMatches: true,
      ),
    ),
    DemoStep(
      id: 'applied',
      duration: readingDuration(mockOpenGigElectrician.title),
      builder: (_) => const MockGigApplyScene(
        gig: mockOpenGigElectrician,
        worker: juanDelaCruz,
        skillMatches: true,
        applied: true,
      ),
    ),
  ],
);
