import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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
///   1. signed in → the same region Gig Wallet uses for ₱ / $ (see
///      [syncUser]): the wallet's currency (wallets/{uid}.currencyCode,
///      PHP = Philippines); with no wallet yet, the country the app detects
///      from GPS at login (CurrentUserProvider.countryCode) or the account
///      currency; if none is known it runs the same GPS detection
///      (ensureCountryCode) and updates as soon as it lands
///   2. the last country seen on this device (saved from 1 or 3)
///   3. GPS, only if location permission was already granted
///   4. a hint from the phone: Philippine time zone, or a PH / Filipino locale
///   5. otherwise English
class TutorialRegion {
  TutorialRegion._();

  static const _prefsKey = 'tutorial_videos_country';
  // A manual English/Tagalog switch existed briefly; its saved choice is
  // cleared so only the detection decides.
  static const _oldManualKey = 'tutorial_videos_lang';
  static bool _cleanedUp = false;

  /// null while still unknown; rows wait for it so the right language shows
  /// from the start.
  static final ValueNotifier<bool?> isPhilippines = ValueNotifier(null);

  static bool _started = false;
  static bool _gpsTried = false;

  /// Starts (or refreshes) detection. Cheap to call from every row.
  static Future<void> ensure(BuildContext context) async {
    if (!_cleanedUp) {
      _cleanedUp = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_oldManualKey);
      } catch (_) {}
    }
    if (!context.mounted) return;
    CurrentUserProvider? user;
    try {
      user = context.read<CurrentUserProvider>();
    } catch (_) {
      // No provider above this context.
    }
    if (user != null && syncUser(user)) return;
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

  /// Follows the signed-in user's geolocation (the same detection Gig Wallet
  /// uses for ₱ / $). Call whenever CurrentUserProvider changes. Returns true
  /// when it decided the region.
  static bool syncUser(CurrentUserProvider user) {
    final uid = user.uid;
    if (uid == null) return false;
    _watchWallet(uid);
    // Same rule as Gig Wallet: its currency decides ₱ (Philippines) or $.
    final walletCcy = _walletCcy;
    if (walletCcy != null) {
      _set(walletCcy == 'PHP');
      return true;
    }
    final country = user.countryCode;
    if (country != null && country.isNotEmpty) {
      _set(country == 'PH');
      _save(country);
      return true;
    }
    // Country not detected yet: start the GPS detection (no-op if running or
    // done); meanwhile a PHP currency already means the Philippines.
    user.ensureCountryCode();
    if (user.currencyCode == 'PHP') {
      _set(true);
      return true;
    }
    return false;
  }

  // ── Gig Wallet currency (wallets/{uid}.currencyCode) ──────────────────────
  static String? _walletUid;
  static String? _walletCcy;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _walletSub;

  static void _watchWallet(String uid) {
    if (_walletUid == uid) return;
    _walletSub?.cancel();
    _walletUid = uid;
    _walletCcy = null;
    _walletSub = FirebaseFirestore.instance.collection('wallets').doc(uid).snapshots().listen(
      (s) {
        if (_walletUid != uid) return;
        final c = s.data()?['currencyCode'];
        if (c is String && c.trim().isNotEmpty) {
          _walletCcy = c.trim().toUpperCase();
          _set(_walletCcy == 'PHP');
          _save(_walletCcy == 'PHP' ? 'PH' : 'US');
        }
      },
      onError: (Object e) => debugPrint('[TutorialRegion] wallet: $e'),
    );
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
