import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers/current_user_provider.dart';
import '../../core/utils/country_check.dart';

/// Whether to show the Tagalog version of tutorial videos — i.e. whether the
/// user is in the Philippines. English is the default whenever it's unknown.
///
/// Works before sign-in, without ever showing a permission prompt:
///   1. signed in → the country the app already detected (GPS, the same one
///      that picks ₱ vs $) — CurrentUserProvider.countryCode
///   2. the last country seen on this device (saved from 1 or 3)
///   3. GPS, only if location permission was already granted
///   4. a hint from the phone: Philippine time zone, or a PH / Filipino locale
///   5. otherwise English
class TutorialRegion {
  TutorialRegion._();

  static const _prefsKey = 'tutorial_videos_country';

  /// null while still unknown; rows wait for it so the right language shows
  /// from the start.
  static final ValueNotifier<bool?> isPhilippines = ValueNotifier(null);

  static bool _started = false;
  static bool _gpsTried = false;

  /// Starts (or refreshes) detection. Cheap to call from every row.
  static Future<void> ensure(BuildContext context) async {
    String? signedIn;
    try {
      signedIn = context.read<CurrentUserProvider>().countryCode;
    } catch (_) {
      // No provider above this context.
    }
    if (signedIn != null && signedIn.isNotEmpty) {
      _set(signedIn == 'PH');
      _save(signedIn);
      return;
    }
    if (_started) return;
    _started = true;

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null) {
      _set(saved == 'PH');
    } else {
      _set(_deviceHintsPhilippines());
    }
    _tryGps();
  }

  static void _set(bool ph) {
    if (isPhilippines.value != ph) isPhilippines.value = ph;
  }

  static Future<void> _save(String country) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, country.toUpperCase());
    } catch (_) {}
  }

  /// Philippine Standard Time (UTC+8, abbreviated PST/PHT/PHST — PST alone
  /// is never +8 elsewhere), or a Philippine / Filipino locale.
  static bool _deviceHintsPhilippines() {
    try {
      final now = DateTime.now();
      final name = now.timeZoneName.toUpperCase();
      if (now.timeZoneOffset == const Duration(hours: 8) &&
          (name == 'PST' || name == 'PHT' || name == 'PHST' || name.contains('PHILIPPINE') || name.contains('MANILA'))) {
        return true;
      }
      for (final l in PlatformDispatcher.instance.locales) {
        if (l.countryCode == 'PH' || l.languageCode == 'fil' || l.languageCode == 'tl') return true;
      }
    } catch (_) {}
    return false;
  }

  /// Refines with a GPS fix — never asks for permission.
  static Future<void> _tryGps() async {
    if (_gpsTried || kIsWeb) return;
    _gpsTried = true;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) return;
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 8),
            ),
          );
      final country = await countryCodeFromCoordinates(pos.latitude, pos.longitude);
      if (country == null) return;
      _set(country == 'PH');
      _save(country);
    } catch (e) {
      debugPrint('[TutorialRegion] $e');
    }
  }
}
