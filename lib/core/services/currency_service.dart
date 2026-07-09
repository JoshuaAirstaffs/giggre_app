import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/country_check.dart';
import '../utils/currency_formatter.dart';

class CurrencyService {
  // Detect the device's current currency code via GPS → reverse-geocode.
  // Returns 'PHP' for the Philippines, 'USD' for everything else.
  // Returns null if detection is unavailable (permission denied, GPS error),
  // so callers can distinguish "couldn't detect" from a real 'PHP' result.
  static Future<String?> detectCurrency() async {
    try {
      final permission = await Geolocator.checkPermission();
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
      final countryCode =
          await countryCodeFromCoordinates(pos.latitude, pos.longitude);
      return CurrencyFormatter.countryToCurrency(countryCode);
    } catch (_) {
      return null;
    }
  }

  // Called once per session on login. Detects the device's current country and
  // updates Firestore if the currency has changed (e.g. user moved countries).
  // Falls back to the stored value when detection is unavailable, or 'PHP' on
  // first use with no stored value.
  static Future<String> initForUser(
      String uid, Map<String, dynamic> userDoc) async {
    final existing = userDoc['currencyCode'] as String?;
    final detected = await detectCurrency();

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
