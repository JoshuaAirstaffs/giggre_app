import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/country_check.dart';
import '../utils/currency_formatter.dart';

class CurrencyService {
  // Detect the device's current currency code via GPS → reverse-geocode.
  // Returns 'PHP' for the Philippines, 'USD' for everything else.
  // Returns null if detection is unavailable (permission denied, GPS error),
  // so callers can distinguish "couldn't detect" from a real 'PHP' result.
  // [onPosition] reports the raw GPS fix back to the caller (e.g. so it can
  // be cached for other screens, like the gig map, to reuse as an instant
  // initial center instead of each doing their own separate GPS wait).
  static Future<String?> detectCurrency({
    void Function(double lat, double lng)? onPosition,
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      LocationPermission permission = await Geolocator.checkPermission();
      // Unlike other Geolocator call sites, this one can run before the user
      // has ever been prompted (e.g. right after signup) — checkPermission()
      // alone returns `denied` for "never asked" and would otherwise make
      // detection silently no-op forever instead of prompting.
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
      onPosition?.call(pos.latitude, pos.longitude);
      final countryCode =
          await countryCodeFromCoordinates(pos.latitude, pos.longitude);
      if (countryCode == null) return null;
      return CurrencyFormatter.countryToCurrency(countryCode);
    } catch (_) {
      return null;
    }
  }

  // Called once per session on login. Detects the device's current country and
  // updates Firestore if the currency has changed (e.g. user moved countries).
  // Falls back to the stored value when detection is unavailable, or 'USD' on
  // first use with no stored value.
  static Future<String> initForUser(
    String uid,
    Map<String, dynamic> userDoc, {
    void Function(double lat, double lng)? onPosition,
  }) async {
    final existing = userDoc['currencyCode'] as String?;
    final detected = await detectCurrency(onPosition: onPosition);

    if (detected == null) {
      return existing ?? 'USD';
    }

    if (detected != existing) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'currencyCode': detected});
    }
    return detected;
  }
}
