import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/demo_sequence.dart';

/// Drives automatic, timed progression through a [DemoSequence]. This is the
/// only place a timer for the demo lives — scenes never schedule their own
/// delays, they just render whatever step is current.
///
/// Entirely local/in-memory: no persistence, no Firestore, no side effects
/// outside of this object's own state.
class DemoController extends ChangeNotifier {
  DemoController(this.sequence, {Set<int> narratedSteps = const {}})
      : _narratedSteps = narratedSteps;

  final DemoSequence sequence;

  /// Step indices with narration audio. For these, [_beginStep] withholds
  /// the auto-advance timer until [setCurrentStepDuration] reports the
  /// step's real duration, instead of starting it immediately with the
  /// unrelated text-based reading-time estimate. That estimate is often
  /// shorter than the real narration, especially for the very first step
  /// (whose narration takes the longest to start, since it's also when the
  /// native audio player is being created for the first time) — letting
  /// that short timer fire before narration finishes loading is what
  /// advanced the demo, and started the *next* step's narration, while the
  /// current step's clip was still starting up, playing both at once.
  final Set<int> _narratedSteps;

  int _stepIndex = 0;
  bool _isCompleted = false;
  Timer? _timer;

  int get stepIndex => _stepIndex;
  bool get isCompleted => _isCompleted;
  int get stepCount => sequence.steps.length;
  double get progress => (_stepIndex + 1) / stepCount;

  void start() {
    _beginStep(_stepIndex);
  }

  void _advance() {
    if (_stepIndex >= sequence.steps.length - 1) {
      _isCompleted = true;
      notifyListeners();
      return;
    }
    _stepIndex++;
    notifyListeners();
    _beginStep(_stepIndex);
  }

  void _beginStep(int index) {
    _timer?.cancel();
    if (_narratedSteps.contains(index)) return;
    _timer = Timer(sequence.steps[index].duration, _advance);
  }

  /// Schedules the current step's auto-advance to fire [duration] from now —
  /// called once a narrated step's actual audio length is known (so the
  /// slide gets the narration's length plus a trailing pause instead of the
  /// unrelated text-based reading-time estimate), or as a fallback with that
  /// same text-based duration if narration playback fails, so a narrated
  /// step can never get stuck with no timer at all. Deliberately doesn't try
  /// to account for how long the step has already been on screen while its
  /// audio was loading — that's at most a couple of seconds, negligible next
  /// to the trailing pause already built in, and erring long is by design:
  /// the bug this replaced was a step's timer firing *too early*. A no-op
  /// once the step has finished.
  void setCurrentStepDuration(Duration duration) {
    if (_isCompleted) return;
    _timer?.cancel();
    _timer = Timer(duration, _advance);
  }

  /// Manually jump to the next step (or finish, if this is the last one) —
  /// backs the "tap to advance" gesture. Purely an optional shortcut: the
  /// demo still plays itself on the auto-timer if this is never called.
  /// Cancels the pending auto-advance timer first so the two never fire
  /// back-to-back.
  void skipToNext() {
    if (_isCompleted) return;
    _timer?.cancel();
    _advance();
  }

  void replay() {
    _timer?.cancel();
    _stepIndex = 0;
    _isCompleted = false;
    notifyListeners();
    start();
  }

  void stop() {
    _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
