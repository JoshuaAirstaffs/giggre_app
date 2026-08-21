import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/demo_sequence.dart';
import '../models/demo_step.dart';
import '../models/reading_time.dart';
import '../scenes/intro/mock_get_started_scene.dart';
import '../scenes/intro/mock_role_feature_scene.dart';
import '../scenes/intro/mock_two_sided_scene.dart';
import '../scenes/intro/mock_welcome_scene.dart';
import '../scenes/shared/mock_info_panel_scene.dart';

/// "What is Giggre?" — a short, fully-automated explainer slideshow, shown
/// before the Host/Worker demos. Not tied to Firestore or any account;
/// purely narrative slides that fade/slide in on their own.
final introWhatIsGiggreSequence = DemoSequence(
  id: 'demo.intro.whatIsGiggre',
  title: 'What is Giggre?',
  subtitle: 'A quick, animated introduction to the app',
  icon: Icons.info_outline_rounded,
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
    DemoStep(
      id: 'forHosts',
      duration: readingDurationFor(const [
        'For Gig Hosts',
        'Need something done? Post a gig in minutes.',
        'Quick Gig',
        'Open Gig',
        'Offered Gig',
      ]),
      builder: (_) => const MockRoleFeatureScene(
        icon: Icons.home_work_outlined,
        color: kBlue,
        heading: 'For Gig Hosts',
        description: 'Need something done? Post a gig in minutes.',
        features: [
          RoleFeature(Icons.flash_on_rounded, 'Quick Gig'),
          RoleFeature(Icons.work_outline_rounded, 'Open Gig'),
          RoleFeature(Icons.send_rounded, 'Offered Gig'),
        ],
      ),
    ),
    DemoStep(
      id: 'forWorkers',
      duration: readingDurationFor(const [
        'For Gig Workers',
        'Ready to work? Find gigs that fit your skills.',
        'Active Mode',
        'My Toolchest',
        'Map & List',
      ]),
      builder: (_) => const MockRoleFeatureScene(
        icon: Icons.construction_rounded,
        color: kGold,
        heading: 'For Gig Workers',
        description: 'Ready to work? Find gigs that fit your skills.',
        features: [
          RoleFeature(Icons.wifi_tethering_rounded, 'Active Mode'),
          RoleFeature(Icons.construction_rounded, 'My Toolchest'),
          RoleFeature(Icons.map_outlined, 'Map & List'),
        ],
      ),
    ),
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
