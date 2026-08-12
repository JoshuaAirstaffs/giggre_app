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
  DemoController(this.sequence);

  final DemoSequence sequence;

  int _stepIndex = 0;
  bool _isCompleted = false;
  Timer? _timer;

  int get stepIndex => _stepIndex;
  bool get isCompleted => _isCompleted;
  int get stepCount => sequence.steps.length;
  double get progress => (_stepIndex + 1) / stepCount;

  void start() {
    _timer?.cancel();
    _timer = Timer(sequence.steps[_stepIndex].duration, _advance);
  }

  void _advance() {
    if (_stepIndex >= sequence.steps.length - 1) {
      _isCompleted = true;
      notifyListeners();
      return;
    }
    _stepIndex++;
    notifyListeners();
    _timer = Timer(sequence.steps[_stepIndex].duration, _advance);
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
