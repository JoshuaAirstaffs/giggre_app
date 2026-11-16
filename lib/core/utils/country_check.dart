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

// Where a gig is, broken into parts a worker can search by: country,
// state/province/region, city and ZIP/postal code. Saved on each new gig
// as `place`. Only the parts the lookup returned are kept.
class GigPlace {
  const GigPlace(this.parts);

  // e.g. {country: Philippines, countryCode: PH, region: Metro Manila,
  // city: Makati, postcode: 1226}
  final Map<String, String> parts;

  String? get countryCode => parts['countryCode'];

  // Address keys Nominatim may use for each level, in order of preference.
  static const _keys = {
    'country': ['country'],
    'region': ['region'],
    'state': ['state'],
    'province': ['province'],
    'county': ['county', 'state_district'],
    'city': ['city', 'town', 'municipality', 'village'],
    'postcode': ['postcode'],
  };

  static GigPlace fromNominatim(Map<String, dynamic> addr) {
    final parts = <String, String>{};
    for (final MapEntry(:key, value: sources) in _keys.entries) {
      for (final s in sources) {
        final v = (addr[s] as String?)?.trim();
        if (v != null && v.isNotEmpty) {
          parts[key] = v;
          break;
        }
      }
    }
    final code = (addr['country_code'] as String?)?.toUpperCase();
    if (code != null && code.isNotEmpty) parts['countryCode'] = code;
    return GigPlace(parts);
  }
}

// One reverse-geocode for both the gig's currency (country code) and its
// searchable place parts. Null if the lookup fails.
Future<GigPlace?> placeFromCoordinates(double lat, double lng) async {
  try {
    final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse')
        .replace(
          queryParameters: {
            'lat': '$lat',
            'lon': '$lng',
            'format': 'json',
            'addressdetails': '1',
            'accept-language': 'en',
          },
        );
    final res = await http
        .get(uri, headers: {'User-Agent': 'GiggreApp/1.0'})
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final addr = data['address'] as Map<String, dynamic>?;
    if (addr == null) return null;
    return GigPlace.fromNominatim(addr);
  } catch (_) {
    return null;
  }
}
