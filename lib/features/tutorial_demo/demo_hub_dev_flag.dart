import 'package:shared_preferences/shared_preferences.dart';

/// Whether the Watch Demo hub also shows "How Giggre Works" and the full
/// master walkthrough — off by default, flippable from the app's existing
/// "Developer Options" modal (see `dev_toggles.dart`). Everyone always
/// sees "What is Giggre?" and both the Gig Host and Gig Worker demos
/// regardless of this flag.
const _kPrefsKey = 'devToggle.watchDemoHub.showEverything';

Future<bool> isDemoHubFullLibraryEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kPrefsKey) ?? false;
}

Future<void> setDemoHubFullLibraryEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kPrefsKey, enabled);
}
