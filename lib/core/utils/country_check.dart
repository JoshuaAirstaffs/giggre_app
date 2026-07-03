import 'dart:convert';
import 'package:http/http.dart' as http;

// Reverse-geocodes a coordinate via Nominatim to find its 2-letter country
// code. Works on every platform including web, unlike the `geocoding` plugin
// (which has no web implementation and silently fails there).
// Returns null if the lookup fails for any reason.
Future<String?> countryCodeFromCoordinates(double lat, double lng) async {
  try {
    final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse').replace(
      queryParameters: {
        'lat': '$lat',
        'lon': '$lng',
        'format': 'json',
        'zoom': '3',
      },
    );
    final res = await http
        .get(uri, headers: {'User-Agent': 'GiggreApp/1.0'})
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final addr = data['address'] as Map<String, dynamic>?;
    final code = addr?['country_code'] as String?;
    return code?.toUpperCase();
  } catch (_) {
    return null;
  }
}

// Reverse-geocodes both points and reports whether they fall in different
// countries. Fails open (returns false) if either point can't be resolved,
// so a geocoding hiccup never blocks a legitimate post.
Future<bool> isDifferentCountry({
  required double lat,
  required double lng,
  required double otherLat,
  required double otherLng,
}) async {
  final results = await Future.wait([
    countryCodeFromCoordinates(lat, lng),
    countryCodeFromCoordinates(otherLat, otherLng),
  ]);
  final countryA = results[0];
  final countryB = results[1];
  if (countryA == null || countryB == null) return false;
  return countryA != countryB;
}
