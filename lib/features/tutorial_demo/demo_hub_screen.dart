import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_provider.dart';
import 'demo_hub_dev_flag.dart';
import 'models/demo_sequence.dart';
import 'player/demo_player_screen.dart';
import 'sequences/host_offered_gig_sequence.dart';
import 'sequences/host_open_gig_sequence.dart';
import 'sequences/host_quick_gig_sequence.dart';
import 'sequences/how_giggre_works_sequence.dart';
import 'sequences/intro_what_is_giggre_sequence.dart';
import 'sequences/master_walkthrough_sequence.dart';
import 'sequences/worker_active_mode_sequence.dart';
import 'sequences/worker_direct_offer_sequence.dart';
import 'sequences/worker_open_gigs_sequence.dart';
import 'sequences/worker_quick_gigs_sequence.dart';
import 'sequences/worker_toolchest_sequence.dart';
import 'widgets/demo_fade_in.dart';
import 'widgets/demo_intro_hero.dart';
import 'widgets/demo_theme.dart';

/// Landing screen for the automated, mock-data-only product demo. Pick any
/// sequence and it plays itself end-to-end — no taps required to advance.
///
/// "What is Giggre?" and both the Gig Host and Gig Worker demos are always
/// visible. "How Giggre Works" and the full master walkthrough are
/// dev-only — off by default, flippable from the app's existing
/// "Developer Options" modal (see `dev_toggles.dart`).
class TutorialDemoHubScreen extends StatefulWidget {
  const TutorialDemoHubScreen({super.key});

  @override
  State<TutorialDemoHubScreen> createState() => _TutorialDemoHubScreenState();
}

class _TutorialDemoHubScreenState extends State<TutorialDemoHubScreen> {
  static final _hostSequences = <DemoSequence>[
    hostQuickGigSequence,
    hostOpenGigSequence,
    hostOfferedGigSequence,
  ];

  static final _workerSequences = <DemoSequence>[
    workerActiveModeSequence,
    workerQuickGigsSequence,
    workerOpenGigsSequence,
    workerToolchestSequence,
    workerDirectOfferSequence,
  ];

  bool _showFullLibrary = false;

  @override
  void initState() {
    super.initState();
    isDemoHubFullLibraryEnabled().then((enabled) {
      if (mounted) setState(() => _showFullLibrary = enabled);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Forced light, same reasoning as `DemoPlayerScreen` — this is meant to
    // look like the real (light) Giggre screens regardless of the viewer's
    // own dark-mode setting.
    return Theme(
      data: ThemeProvider.lightTheme,
      child: Scaffold(
        backgroundColor: dBg,
        appBar: AppBar(
          backgroundColor: dCard,
          elevation: 0,
          foregroundColor: dTitle,
          title: const Text('Watch Demo'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            DemoFadeIn(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                decoration: BoxDecoration(
                  color: dCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: dBorder),
                ),
                child: const DemoIntroHero(),
              ),
            ),
            const SizedBox(height: 14),
            DemoFadeIn(
              delay: const Duration(milliseconds: 150),
              child: _FeaturedIntroRow(sequence: introWhatIsGiggreSequence),
            ),
            if (_showFullLibrary) ...[
              const SizedBox(height: 10),
              DemoFadeIn(
                delay: const Duration(milliseconds: 200),
                child: _FeaturedIntroRow(
                  sequence: howGiggreWorksSequence,
                  devTag: true,
                ),
              ),
              const SizedBox(height: 10),
              DemoFadeIn(
                delay: const Duration(milliseconds: 250),
                child: _FeaturedIntroRow(
                  sequence: masterWalkthroughSequence,
                  accentColor: kBlue,
                  label: 'Watch the full walkthrough',
                  devTag: true,
                ),
              ),
            ],
            const SizedBox(height: 20),
            DemoFadeIn(
              delay: const Duration(milliseconds: 300),
              child: const Text(
                'Sit back and watch — each demo plays on its own using sample '
                'data. Nothing here creates a real gig, notification, or match.',
                style: TextStyle(color: dBody, fontSize: 13, height: 1.4),
              ),
            ),
            const SizedBox(height: 20),
            DemoFadeIn(
              delay: const Duration(milliseconds: 400),
              child: const _SectionLabel(
                'Gig Host',
                description: 'Post gigs, find nearby workers, and get things done.',
              ),
            ),
            const SizedBox(height: 8),
            DemoFadeIn(
              delay: const Duration(milliseconds: 500),
              child: _SequenceCard(sequences: _hostSequences),
            ),
            const SizedBox(height: 20),
            DemoFadeIn(
              delay: const Duration(milliseconds: 600),
              child: const _SectionLabel(
                'Gig Worker',
                description: 'Browse gigs, use your skills, and get paid.',
              ),
            ),
            const SizedBox(height: 8),
            DemoFadeIn(
              delay: const Duration(milliseconds: 700),
              child: _SequenceCard(sequences: _workerSequences),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small "DEV" pill marking a section that's only visible because the
/// Developer Options "Watch Demo: full library" toggle is on.
class _DevTag extends StatelessWidget {
  const _DevTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: kBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'DEV',
        style: TextStyle(
          color: kBlue,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Standout entry point for a featured, non-Host/Worker-specific sequence
/// (the intro slideshows, the master walkthrough) — visually distinct from
/// the plain Host/Worker rows below since these aren't a single functional
/// flow. [accentColor]/[label] let the master walkthrough stand out further
/// from the two explainer slideshows; [devTag] marks a dev-only row.
class _FeaturedIntroRow extends StatelessWidget {
  final DemoSequence sequence;
  final Color accentColor;
  final String? label;
  final bool devTag;

  const _FeaturedIntroRow({
    required this.sequence,
    this.accentColor = kGold,
    this.label,
    this.devTag = false,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = sequence;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DemoPlayerScreen(sequence: resolved)),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.play_circle_fill_rounded, color: accentColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label ?? 'Watch: ${resolved.title}',
                          style: const TextStyle(
                            color: dTitle,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (devTag) const _DevTag(),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    resolved.subtitle,
                    style: const TextStyle(color: dBody, fontSize: 12, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final String description;
  const _SectionLabel(this.label, {required this.description});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: kGold,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          description,
          style: const TextStyle(color: dBody, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _SequenceCard extends StatelessWidget {
  final List<DemoSequence> sequences;
  const _SequenceCard({required this.sequences});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: dCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < sequences.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: dBorder),
            DemoFadeIn(
              delay: Duration(milliseconds: i * 120),
              child: _SequenceRow(sequence: sequences[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _SequenceRow extends StatelessWidget {
  final DemoSequence sequence;
  const _SequenceRow({required this.sequence});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DemoPlayerScreen(sequence: sequence),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(sequence.icon, color: kGold, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sequence.title,
                    style: const TextStyle(
                      color: dTitle,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    sequence.subtitle,
                    style: const TextStyle(color: dBody, fontSize: 12, height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.play_circle_fill_rounded, color: kGold, size: 26),
          ],
        ),
      ),
    );
  }
}
