// Manual-tap steps block interaction and wait for the user to hit "Next".
// Auto-on-anchor steps ride along with real app state (a sheet opening once
// a match is found) and never block — the tutorial just narrates whatever
// the user is already doing until that anchor appears.
enum TutorialAdvance { manualTap, autoOnAnchor }

class TutorialStep {
  final String id;
  final String anchorId;
  final String title;
  final String body;
  final TutorialAdvance advance;

  const TutorialStep({
    required this.id,
    required this.anchorId,
    required this.title,
    required this.body,
    this.advance = TutorialAdvance.manualTap,
  });
}
