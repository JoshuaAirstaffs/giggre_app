import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';

// App-wide rotation rule: phones stay portrait (no screen is laid out for
// landscape on a phone), tablets rotate freely. Info.plist still lists the
// landscape orientations so screens like the full screen carousel video can
// switch to landscape for a moment — they call [restoreAppOrientations] when
// they close instead of forcing portrait, which used to lock iPads too.

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
  return SystemChrome.setPreferredOrientations(
    // Empty means every orientation the platform config allows
    _isTablet() ? const [] : const [DeviceOrientation.portraitUp],
  );
}
