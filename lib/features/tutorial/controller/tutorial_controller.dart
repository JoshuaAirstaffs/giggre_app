import 'package:flutter/material.dart';
import '../models/tutorial_flow.dart';
import '../models/tutorial_step.dart';
import '../services/tutorial_service.dart';

// Anchors register themselves here as they mount (see TutorialAnchor), so a
// step whose target lives on a route that hasn't been pushed yet — or inside
// a bottom sheet that only appears once a real match comes back from
// Firestore — simply has no key until that widget exists. The controller
// doesn't need to know *where* an anchor lives, only whether it's mounted.
class TutorialController extends ChangeNotifier {
  final TutorialService _service;
  TutorialController(this._service);

  TutorialFlow? _flow;
  int _stepIndex = 0;
  final Map<String, GlobalKey> _anchors = {};

  TutorialFlow? get activeFlow => _flow;
  TutorialStep? get currentStep =>
      _flow == null ? null : _flow!.steps[_stepIndex];
  GlobalKey? get currentAnchorKey =>
      currentStep == null ? null : _anchors[currentStep!.anchorId];
  bool get isWaitingForAnchor =>
      currentStep != null && currentAnchorKey == null;

  // Whether this flow should be visible/launchable at all right now — used
  // by screens to decide whether to render their "Tutorial" button. Regular
  // flows are always available; devOnly flows need their Developer Mode
  // toggle on.
  Future<bool> isAvailable(TutorialFlow flow) async {
    if (!flow.devOnly) return true;
    return _service.isDevEnabled(flow.id);
  }

  Future<void> startIfNeeded(TutorialFlow flow) async {
    if (_flow != null) return; // a flow (this or another) is already running
    if (flow.devOnly && !await _service.isDevEnabled(flow.id)) return;
    if (await _service.hasCompleted(flow.id)) return;
    _flow = flow;
    _stepIndex = 0;
    notifyListeners();
  }

  // Explicit replay, e.g. from a "Tutorial" button — ignores completed
  // state entirely (both to enter and, since `complete()` only ever writes
  // `true`, to leave: finishing a replay can't un-complete the flow).
  void restart(TutorialFlow flow) {
    _flow = flow;
    _stepIndex = 0;
    notifyListeners();
  }

  void registerAnchor(String anchorId, GlobalKey key) {
    _anchors[anchorId] = key;
    if (currentStep?.anchorId == anchorId) notifyListeners();
  }

  void unregisterAnchor(String anchorId, GlobalKey key) {
    // Only clear if this call owns the current mapping — otherwise a
    // widget that just replaced an old anchor's key would get wiped out by
    // the old widget's disposal running after the new one already mounted.
    if (_anchors[anchorId] == key) {
      _anchors.remove(anchorId);
      notifyListeners();
    }
  }

  void next() {
    if (_flow == null) return;
    if (_stepIndex >= _flow!.steps.length - 1) {
      complete();
      return;
    }
    _stepIndex++;
    notifyListeners();
  }

  void skip() => complete();

  Future<void> complete() async {
    final flow = _flow;
    if (flow == null) return;
    _flow = null;
    _stepIndex = 0;
    notifyListeners();
    await _service.markCompleted(flow.id);
  }
}
