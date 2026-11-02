import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// App-wide rotation rule: phones stay portrait (no screen is laid out for
// landscape on a phone), tablets rotate freely. Info.plist still lists the
// landscape orientations so screens like the full screen carousel video can
// switch to landscape for a moment — they call [restoreAppOrientations] when
// they close instead of forcing portrait, which used to lock iPads too.
// Foldables change class at runtime (narrow cover screen ↔ wide inner
// screen), so the rule is re-applied whenever the device class flips.

/// Shortest side, in logical pixels, from which a device counts as a tablet
/// (Material's compact/medium window size class boundary).
const double _kTabletShortestSide = 600;

bool _isTablet() {
  final views = PlatformDispatcher.instance.views;
  if (views.isEmpty) return false;
  final view = views.first;
  final size = view.physicalSize / view.devicePixelRatio;
  return size.shortestSide >= _kTabletShortestSide;
}

/// Applies the app-wide rule. Call once at startup and whenever a screen
/// that changed the orientation closes.
Future<void> restoreAppOrientations() {
  _FoldWatcher.ensureInstalled();
  _FoldWatcher.lastWasTablet = _isTablet();
  return SystemChrome.setPreferredOrientations(
    // Empty means every orientation the platform config allows
    _isTablet() ? const [] : const [DeviceOrientation.portraitUp],
  );
}

/// Re-applies the rule when the window crosses the phone/tablet boundary,
/// e.g. a foldable opened from its cover screen or closed again. Only a flip
/// in class triggers it, so a screen that forced landscape (full screen
/// video) keeps it on ordinary rotations.
class _FoldWatcher with WidgetsBindingObserver {
  static _FoldWatcher? _instance;
  static bool? lastWasTablet;

  static void ensureInstalled() {
    if (_instance != null) return;
    _instance = _FoldWatcher();
    WidgetsBinding.instance.addObserver(_instance!);
  }

  @override
  void didChangeMetrics() {
    final isTablet = _isTablet();
    if (isTablet == lastWasTablet) return;
    restoreAppOrientations();
  }
}
