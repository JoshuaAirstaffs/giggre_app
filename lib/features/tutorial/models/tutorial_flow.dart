import 'tutorial_step.dart';

class TutorialFlow {
  final String id;
  final List<TutorialStep> steps;
  // Flows still being validated internally are gated behind Developer Mode
  // (see TutorialController.startIfNeeded) instead of shown to everyone.
  final bool devOnly;

  const TutorialFlow({
    required this.id,
    required this.steps,
    this.devOnly = false,
  });
}
