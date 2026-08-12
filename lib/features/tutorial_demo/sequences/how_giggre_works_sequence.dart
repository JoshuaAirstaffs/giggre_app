import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/demo_sequence.dart';
import '../models/demo_step.dart';
import '../models/reading_time.dart';
import '../scenes/intro/mock_concept_slide_scene.dart';
import '../scenes/intro/mock_get_started_scene.dart';
import '../scenes/intro/mock_two_sided_scene.dart';
import '../scenes/intro/mock_welcome_scene.dart';
import '../scenes/shared/mock_info_panel_scene.dart';

const _purple = Color(0xFF8B5CF6);
const _green = Color(0xFF22C55E);

/// "How Giggre Works" — the comprehensive, fully-automated walkthrough:
/// what Giggre is, then every Host gig type and every Worker feature
/// (including Offered Gig from both sides), one concept per slide.
final howGiggreWorksSequence = DemoSequence(
  id: 'demo.intro.howItWorks',
  title: 'How Giggre Works',
  subtitle: 'The complete walkthrough — every gig type, both sides',
  icon: Icons.auto_stories_rounded,
  steps: [
    DemoStep(
      id: 'welcome',
      duration: readingDurationFor(const [
        'Welcome to Giggre',
        'Every gig, right in your area.',
        'Find work or get trusted help near you — fast, fair, and local.',
      ]),
      builder: (_) => const MockWelcomeScene(),
    ),
    DemoStep(
      id: 'twoSided',
      duration: readingDurationFor(const [
        'One app, two sides',
        'Every gig on Giggre connects a Host who needs something done '
            'with a Worker ready to do it.',
        'Gig Host',
        'Post work and get it done by a nearby worker.',
        'Gig Worker',
        'Find gigs that match your skills and get paid.',
      ]),
      builder: (_) => const MockTwoSidedScene(),
    ),
    // ── Gig Host: every gig type ──────────────────────────────────────
    DemoStep(
      id: 'hostQuickGig',
      duration: readingDurationFor(const [
        'Quick Gig',
        "An instant gig that doesn't need a specific skill — post it "
            'and get matched with a nearby worker right away.',
      ]),
      builder: (_) => const MockConceptSlideScene(
        icon: Icons.flash_on_rounded,
        color: kAmber,
        roleLabel: 'Gig Host',
        title: 'Quick Gig',
        definition:
            "An instant gig that doesn't need a specific skill — post it "
            'and get matched with a nearby worker right away.',
      ),
    ),
    DemoStep(
      id: 'hostOpenGig',
      duration: readingDurationFor(const [
        'Open Gig',
        'Post a gig when you need a worker with a specific skill or '
            'qualification — skilled workers apply and you pick one.',
      ]),
      builder: (_) => const MockConceptSlideScene(
        icon: Icons.work_outline_rounded,
        color: kBlue,
        roleLabel: 'Gig Host',
        title: 'Open Gig',
        definition:
            'Post a gig when you need a worker with a specific skill or '
            'qualification — skilled workers apply and you pick one.',
      ),
    ),
    DemoStep(
      id: 'hostOfferedGig',
      duration: readingDurationFor(const [
        'Offered Gig',
        'Directly offer a gig to a worker you already know or have '
            'worked with before — no need to post it publicly.',
      ]),
      builder: (_) => const MockConceptSlideScene(
        icon: Icons.send_rounded,
        color: _purple,
        roleLabel: 'Gig Host',
        title: 'Offered Gig',
        definition:
            'Directly offer a gig to a worker you already know or have '
            'worked with before — no need to post it publicly.',
      ),
    ),
    // ── Gig Worker: every feature ──────────────────────────────────────
    DemoStep(
      id: 'workerActiveMode',
      duration: readingDurationFor(const [
        'Active Mode',
        "Go online so hosts can see you're currently available for work.",
      ]),
      builder: (_) => const MockConceptSlideScene(
        icon: Icons.wifi_tethering_rounded,
        color: _green,
        roleLabel: 'Gig Worker',
        title: 'Active Mode',
        definition:
            "Go online so hosts can see you're currently available for "
            'work.',
      ),
    ),
    DemoStep(
      id: 'workerQuickGigs',
      duration: readingDurationFor(const [
        'Quick Gigs',
        "Instant gig opportunities that don't require a specific "
            'skill — Take It or Pass on each one.',
      ]),
      builder: (_) => const MockConceptSlideScene(
        icon: Icons.flash_on_rounded,
        color: kAmber,
        roleLabel: 'Gig Worker',
        title: 'Quick Gigs',
        definition:
            "Instant gig opportunities that don't require a specific "
            'skill — Take It or Pass on each one.',
      ),
    ),
    DemoStep(
      id: 'workerOpenGigs',
      duration: readingDurationFor(const [
        'Open Gigs',
        'Browse the map or list and take a gig once your verified '
            'skills match what it needs.',
      ]),
      builder: (_) => const MockConceptSlideScene(
        icon: Icons.map_outlined,
        color: kBlue,
        roleLabel: 'Gig Worker',
        title: 'Open Gigs',
        definition:
            'Browse the map or list and take a gig once your verified '
            'skills match what it needs.',
      ),
    ),
    DemoStep(
      id: 'workerToolchest',
      duration: readingDurationFor(const [
        'My Toolchest',
        'Manage your skills — new ones need admin approval before you '
            'can take gigs that require them.',
      ]),
      builder: (_) => const MockConceptSlideScene(
        icon: Icons.construction_rounded,
        color: kGold,
        roleLabel: 'Gig Worker',
        title: 'My Toolchest',
        definition:
            'Manage your skills — new ones need admin approval before you '
            'can take gigs that require them.',
      ),
    ),
    DemoStep(
      id: 'workerOfferedGig',
      duration: readingDurationFor(const [
        'Offered Gig',
        "Receive a gig offered straight to you by a host you've worked "
            'with before, and accept it right from the notification.',
      ]),
      builder: (_) => const MockConceptSlideScene(
        icon: Icons.send_rounded,
        color: _purple,
        roleLabel: 'Gig Worker',
        title: 'Offered Gig',
        definition:
            "Receive a gig offered straight to you by a host you've "
            'worked with before, and accept it right from the notification.',
      ),
    ),
    // ── Wrap-up ──────────────────────────────────────────────────────
    DemoStep(
      id: 'trust',
      duration: readingDurationFor(const [
        'Fast, fair, and local',
        'Verified accounts and skills you can trust.',
        'Gigs matched to workers nearby.',
        'Clear pay and status every step of the way.',
      ]),
      builder: (_) => const MockInfoPanelScene(
        title: 'Fast, fair, and local',
        bullets: [
          'Verified accounts and skills you can trust.',
          'Gigs matched to workers nearby.',
          'Clear pay and status every step of the way.',
        ],
      ),
    ),
    DemoStep(
      id: 'getStarted',
      duration: readingDurationFor(const [
        "That's Giggre in a nutshell",
        'Pick a Host or Worker demo below to see it in action.',
      ]),
      builder: (_) => const MockGetStartedScene(),
    ),
  ],
);
