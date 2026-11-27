import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'gig_area.dart';

// ── Pick-up → drop-off gigs ─────────────────────────────────────────────────
//
// Delivery and errand gigs have two points. The gig's existing `location` /
// `address` is the PICK-UP point (so the map pin, distance, nearby alerts and
// quick-gig dispatch keep working unchanged), and these fields add the
// DROP-OFF point:
//
//   dropoffLocation  GeoPoint
//   dropoffAddress   String
//   routeDistanceKm  double   straight-line pick-up → drop-off, 1 decimal
//
// A gig is a route gig when it has a dropoffLocation. Which gigs ASK for one
// is decided by the skill (Open / Offered) or task type (Quick) — see
// RouteGigRules.

const kDropoffLocationField = 'dropoffLocation';
const kDropoffAddressField = 'dropoffAddress';
const kRouteDistanceField = 'routeDistanceKm';
// City / province / country of the drop-off, like the gig's `place` for the
// pick-up — so cards can show the drop-off area even when the street lookup
// failed.
const kDropoffPlaceField = 'dropoffPlace';

/// Skills that always ask for a drop-off point, plus any skill whose
/// category is [kRouteSkillCategory] (so admins can add more without an app
/// update).
const kRouteSkillNames = {
  'errand running',
  'personal shopper',
  'courier service',
  'grocery delivery',
  'furniture delivery',
  'moving assistance',
};
const kRouteSkillCategory = 'moving & delivery';

/// Words that make any skill name a route skill, so it works whatever the
/// catalog calls it ("Delivery Services", "Moving & Hauling Services") and
/// for a typed "Other" skill like "Food delivery".
const kRouteSkillKeywords = [
  'deliver',
  'courier',
  'errand',
  'shopper',
  'moving',
  'hauling',
  'pasabuy',
];

bool _hasRouteKeyword(String lowerName) =>
    kRouteSkillKeywords.any(lowerName.contains);

/// GSIN sub-categories whose task types ask for a drop-off point (Quick
/// Gigs pick a task type, not a skill): Grocery & Errands, Moving & Delivery.
const kRouteTaskSubcategories = {'GE', 'MD'};

class RouteGigRules {
  RouteGigRules._();
  static final RouteGigRules instance = RouteGigRules._();

  final Set<String> _skillNames = {...kRouteSkillNames};
  final Set<String> _taskTypeIds = {};
  Future<void>? _loading;

  /// Loads once per app run (skills + task types); a failed load is retried
  /// on the next call. Until it finishes the built-in names still apply.
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final db = FirebaseFirestore.instance;
      final res = await Future.wait([
        db.collection('skills').get(),
        db.collection('gsin_task_types').get(),
      ]);
      final routeSkillIds = <String>{};
      for (final d in res[0].docs) {
        final name = _key(d.data()['name']);
        final category = _key(d.data()['category']);
        if (name.isEmpty) continue;
        if (category == kRouteSkillCategory || _hasRouteKeyword(name)) {
          _skillNames.add(name);
        }
        if (_skillNames.contains(name)) routeSkillIds.add(d.id);
      }
      for (final d in res[1].docs) {
        final sub = (d.data()['subcategoryId'] ?? '').toString().toUpperCase();
        final ids = d.data()['skillIds'];
        final linksRouteSkill =
            ids is List && ids.any((id) => routeSkillIds.contains(id.toString()));
        if (kRouteTaskSubcategories.contains(sub) || linksRouteSkill) {
          _taskTypeIds.add(d.id);
        }
      }
    } catch (_) {
      _loading = null;
    }
  }

  static String _key(Object? v) => (v ?? '').toString().trim().toLowerCase();

  bool isRouteSkill(String? skill) {
    if (skill == null) return false;
    final k = _key(skill);
    return k.isNotEmpty && (_skillNames.contains(k) || _hasRouteKeyword(k));
  }

  bool isRouteTaskType(String? taskTypeId) {
    if (taskTypeId == null || taskTypeId.isEmpty) return false;
    if (_taskTypeIds.contains(taskTypeId)) return true;
    // Task type ids start with their sub-category prefix.
    return taskTypeId.length >= 2 &&
        kRouteTaskSubcategories.contains(taskTypeId.substring(0, 2).toUpperCase());
  }
}

/// Straight-line distance in km between two points (haversine), 1 decimal.
double routeDistanceKm(GeoPoint a, GeoPoint b) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLng = rad(b.longitude - a.longitude);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(a.latitude)) *
          math.cos(rad(b.latitude)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final km = 2 * r * math.asin(math.min(1, math.sqrt(h)));
  return (km * 10).round() / 10;
}

/// Fields to write for a gig. With a drop-off: the three route fields.
/// Without one: nothing on create, or deletes on edit (so switching a gig
/// away from a delivery skill doesn't leave a stale drop-off behind).
Map<String, dynamic> routeFields({
  required GeoPoint pickup,
  required GeoPoint? dropoff,
  required String dropoffAddress,
  required bool isEdit,
  Map<String, String>? dropoffPlace,
}) {
  if (dropoff == null) {
    return isEdit
        ? {
            kDropoffLocationField: FieldValue.delete(),
            kDropoffAddressField: FieldValue.delete(),
            kRouteDistanceField: FieldValue.delete(),
            kDropoffPlaceField: FieldValue.delete(),
          }
        : const {};
  }
  return {
    kDropoffLocationField: dropoff,
    kDropoffAddressField: addressOrPlace(dropoffAddress, dropoffPlace),
    kRouteDistanceField: routeDistanceKm(pickup, dropoff),
    if (dropoffPlace != null && dropoffPlace.isNotEmpty)
      kDropoffPlaceField: dropoffPlace,
    if (isEdit && (dropoffPlace == null || dropoffPlace.isEmpty))
      kDropoffPlaceField: FieldValue.delete(),
  };
}

/// The drop-off point of a gig doc, or null for a normal single-point gig.
class GigDropoff {
  final GeoPoint location;
  final String address;
  final double? distanceKm;
  final Map<String, String> place;
  const GigDropoff(
    this.location,
    this.address,
    this.distanceKm, [
    this.place = const {},
  ]);

  static GigDropoff? fromData(Map<String, dynamic>? d) {
    final loc = d?[kDropoffLocationField];
    if (loc is! GeoPoint) return null;
    return GigDropoff(
      loc,
      (d?[kDropoffAddressField] as String?) ?? '',
      (d?[kRouteDistanceField] as num?)?.toDouble(),
      {
        for (final MapEntry(:key, :value)
            in ((d?[kDropoffPlaceField] as Map?) ?? const {}).entries)
          if (key is String && value is String) key: value,
      },
    );
  }
}
