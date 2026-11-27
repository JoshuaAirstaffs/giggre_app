import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../constants/api_keys.dart';
import 'gig_area.dart';

// Reverse geocoding through Google's Geocoding API — the first choice for
// gig addresses (better Philippine street data than OpenStreetMap, and no
// public rate limit). Uses the same key as Places search
// (kGoogleMapsApiKey, "Google Map Android" in Cloud Console, which must
// list "Geocoding API" under its API restrictions). Callers fall back to
// Nominatim / the device geocoder when this returns null.

class GoogleGeocodeResult {
  const GoogleGeocodeResult(this.address, this.parts);

  /// "075 Sta. Maria St, Osmena (Centro Sur Este), Cordon, Isabela,
  /// Philippines" — street, barangay, city, province, country, led by the
  /// building's name when the pin is on one. Plus codes dropped; parts
  /// Google doesn't know are left out.
  final String address;

  /// Same keys as GigPlace: country, countryCode, region, province, city,
  /// postcode — only the ones Google returned.
  final Map<String, String> parts;
}

Future<GoogleGeocodeResult?> googleReverseGeocode(double lat, double lng) async {
  try {
    final landmarkFuture = _nearestLandmark(lat, lng);
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'latlng': '$lat,$lng',
      'key': kGoogleMapsApiKey,
      'language': 'en',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['status'] != 'OK') return null;
    final results = ((data['results'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (results.isEmpty) return null;

    List<String> typesOf(Map<String, dynamic> m) =>
        (m['types'] as List?)?.cast<String>() ?? const [];
    List<Map<String, dynamic>> compsOf(Map<String, dynamic> r) =>
        ((r['address_components'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();

    // City / province / country from the first result that isn't a bare
    // plus code.
    final best = results.firstWhere(
      (r) => !typesOf(r).contains('plus_code'),
      orElse: () => results.first,
    );
    final parts = <String, String>{};
    String countryLong = '';
    for (final m in compsOf(best)) {
      final types = typesOf(m);
      final long = (m['long_name'] as String?)?.trim() ?? '';
      final short = (m['short_name'] as String?)?.trim() ?? '';
      if (long.isEmpty) continue;
      if (types.contains('country')) {
        countryLong = long;
        parts['country'] = long;
        if (short.isNotEmpty) parts['countryCode'] = short.toUpperCase();
      } else if (types.contains('administrative_area_level_1')) {
        parts['region'] = long;
      } else if (types.contains('administrative_area_level_2')) {
        parts['province'] = long;
      } else if (types.contains('locality')) {
        parts['city'] = long;
      } else if (types.contains('postal_code')) {
        parts['postcode'] = long;
      }
    }
    final city = parts['city'] ?? '';
    final province = parts['province'] ?? '';

    // Street: the nearest result with a real road name. Rural pins often
    // come back first as a plus code ("MFG9+5JP, Cordon"), with the street
    // ("075 Sta. Maria St") a few results down.
    String street = '';
    for (final r in results) {
      if (!compsOf(r).any((c) => typesOf(c).contains('route'))) continue;
      final segs = stripPlusCode((r['formatted_address'] as String?) ?? '')
          .split(',')
          .map((x) => x.trim())
          .where((x) => x.isNotEmpty)
          .toList();
      final kept = <String>[];
      for (final seg in segs) {
        if (seg == city || seg == province || seg == countryLong) break;
        kept.add(seg);
      }
      if (kept.isNotEmpty) {
        street = kept.join(', ');
        break;
      }
    }

    // Barangay: Google tags it as a sublocality or neighborhood, on any of
    // the results.
    String barangay = '';
    outer:
    for (final r in results) {
      for (final c in compsOf(r)) {
        final t = typesOf(c);
        if (t.any((x) => x.startsWith('sublocality') || x == 'neighborhood')) {
          barangay = (c['long_name'] as String?)?.trim() ?? '';
          if (barangay.isNotEmpty) break outer;
        }
      }
    }

    final landmark = await landmarkFuture;
    final seen = <String>{};
    final address = [
      // A building's name only when the pin is on it — no "Near …".
      if (landmark.onIt) landmark.name,
      street,
      barangay,
      city,
      province,
      countryLong,
    ].where((x) => x.isNotEmpty && seen.add(x.toLowerCase())).join(', ');

    if (address.isEmpty && parts.isEmpty) return null;
    return GoogleGeocodeResult(address, parts);
  } catch (_) {
    return null;
  }
}

/// The closest named place within ~150 m (a store, school, church…), so the
/// worker has something to look for. [onIt] when the pin is on the place
/// itself (within [_onPlaceMeters]) — shown as its name, not "Near …".
/// Empty name when there's none or the lookup fails. Places Nearby Search,
/// same key as autocomplete.
typedef _Landmark = ({String name, bool onIt});
const _noLandmark = (name: '', onIt: false);
const _onPlaceMeters = 30.0;

Future<_Landmark> _nearestLandmark(double lat, double lng) async {
  try {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/nearbysearch/json',
      {
        'location': '$lat,$lng',
        'rankby': 'distance',
        'key': kGoogleMapsApiKey,
        'language': 'en',
      },
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) return _noLandmark;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['status'] != 'OK') return _noLandmark;
    for (final r in ((data['results'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()) {
      final types = (r['types'] as List?)?.cast<String>() ?? const [];
      if (types.contains('political') || types.contains('route')) continue;
      final name = (r['name'] as String?)?.trim() ?? '';
      final loc = (r['geometry'] as Map?)?['location'] as Map?;
      final pLat = (loc?['lat'] as num?)?.toDouble();
      final pLng = (loc?['lng'] as num?)?.toDouble();
      if (name.isEmpty || pLat == null || pLng == null) continue;
      final m = _metersBetween(lat, lng, pLat, pLng);
      if (m > 150) return _noLandmark;
      return (name: name, onIt: m <= _onPlaceMeters);
    }
    return _noLandmark;
  } catch (_) {
    return _noLandmark;
  }
}

double _metersBetween(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final x = rad(lng2 - lng1) * math.cos(rad((lat1 + lat2) / 2));
  final y = rad(lat2 - lat1);
  return r * math.sqrt(x * x + y * y);
}
