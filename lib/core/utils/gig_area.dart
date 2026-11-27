// The general area of a gig — city and province/state, never the street — for
// workers who haven't been accepted yet. The full address is only shown once
// the worker is on the gig (assigned popup, active gig, history).

/// "Makati, Metro Manila" / "Mountain View, California". From the place the
/// gig saved when it was posted; for older gigs without one, the address
/// minus its street line (first part) and any part with a house number.
/// Empty when nothing safe is left.
/// Text the post-gig forms show while they can't look up a street address.
/// Never a real address, so never shown on a card or saved as one.
const _placeholderAddresses = {
  'gps location ready',
  'selected location',
  'could not get address',
  'location ready',
  'detecting location...',
};

bool isPlaceholderAddress(String address) =>
    address.trim().isEmpty ||
    _placeholderAddresses.contains(address.trim().toLowerCase());

/// The address to save or show: [address], or "City, Province" from [place]
/// when the street lookup failed and [address] is only a placeholder.
String addressOrPlace(String address, [Map<String, String>? place]) {
  final a = stripPlusCode(address);
  return isPlaceholderAddress(a) ? gigAreaLabel('', place ?? const {}) : a;
}

// Open Location Code ("MFF8+JFJ" / "7Q63MFF8+JFJ") at the start of an
// address, plus the comma/space after it. Google returns these for rural
// spots with no street ("MFF8+JFJ, Cordon, Isabela").
final _plusCodePrefix = RegExp(
  r'^[23456789CFGHJMPQRVWX]{2,8}\+[23456789CFGHJMPQRVWX]{0,3}[,\s]*',
  caseSensitive: false,
);

/// [address] without a leading plus code — also cleans gigs saved before
/// the geocoder dropped it.
String stripPlusCode(String address) =>
    address.trim().replaceFirst(_plusCodePrefix, '').trim();

String gigAreaLabel(String address, [Map<String, String> place = const {}]) {
  final city = place['city'];
  final upper = place['province'] ?? place['state'] ?? place['region'] ?? place['county'];
  final fromPlace = [
    if (city != null && city.isNotEmpty) city,
    if (upper != null && upper.isNotEmpty && upper != city) upper,
  ];
  if (fromPlace.isNotEmpty) return fromPlace.join(', ');
  address = stripPlusCode(address);
  if (isPlaceholderAddress(address)) return '';

  final segs = address
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (segs.length <= 1) {
    // One line only: fine if it's just a place name, not a street.
    final only = segs.isEmpty ? '' : segs.first;
    return RegExp(r'\d').hasMatch(only) ? '' : only;
  }
  final rest = segs
      .sublist(1) // first part is the street / building
      .map((s) => s.replaceAll(RegExp(r'\b\d{3,6}\b'), '').trim()) // ZIP codes
      .where((s) => s.isNotEmpty && !RegExp(r'^\d').hasMatch(s))
      .toList();
  if (rest.isEmpty) return '';
  return rest.length <= 2 ? rest.join(', ') : rest.sublist(rest.length - 2).join(', ');
}

/// What to show for a not-yet-accepted worker.
String gigAreaOrHidden(String address, [Map<String, String> place = const {}]) {
  final a = gigAreaLabel(address, place);
  return a.isEmpty ? 'Area shown after you\'re accepted' : a;
}

/// Coordinates rounded to ~1 km, so "View area" shows the neighbourhood
/// without pinpointing the address.
(double, double) approximateCoords(double lat, double lng) =>
    ((lat * 100).roundToDouble() / 100, (lng * 100).roundToDouble() / 100);
