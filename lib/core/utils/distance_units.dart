import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../features/tutorial_videos/tutorial_region.dart';

/// Distance units by region: US users see miles (and feet up close),
/// Philippines and everyone else see km (and metres).
///
/// Region uses the same detection as Gig Wallet ₱ / $ and the tutorial
/// videos ([TutorialRegion]): wallet currency first (USD → miles), then the
/// detected country. km while still unknown. Distances are always stored and
/// compared in km/metres; only what's shown changes.
class DistanceUnits {
  DistanceUnits._();

  static const double kmPerMile = 1.609344;
  static const double _metersPerMile = 1609.344;
  static const double _feetPerMeter = 3.28084;

  /// Rebuild on this to switch units as soon as the region is known.
  static ValueListenable<bool?> get region => TutorialRegion.isPhilippines;

  /// Starts region detection (cheap; safe to call from initState).
  static void ensure(BuildContext context) => TutorialRegion.ensure(context);

  static bool get miles => TutorialRegion.isPhilippines.value == false;

  /// "mi" or "km".
  static String get unit => miles ? 'mi' : 'km';

  /// 450 m / 1.2 km — or 300 ft / 0.8 mi.
  static String format(double meters) {
    if (miles) {
      final mi = meters / _metersPerMile;
      if (mi < 0.1) return '${(meters * _feetPerMeter).round()} ft';
      return '${mi.toStringAsFixed(1)} mi';
    }
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  /// Whole units, e.g. "31 mi" / "50 km".
  static String formatKmRounded(double km) => '${fromKm(km).round()} $unit';

  /// km → shown unit.
  static double fromKm(double km) => miles ? km / kmPerMile : km;

  /// shown unit → km.
  static double toKm(double value) => miles ? value * kmPerMile : value;

  // ── Quick Gig max search radius (admin: Quick Gigs Configuration) ────────
  // quick_gig_config/matching_engine has one value per region:
  //   max_search_radius_km     — Philippines & everyone else, in km
  //   max_search_radius_mi_us  — United States, in miles
  // A field set to null means "Unlimited". A missing field falls back: US →
  // the km value, km → 10 km (the original default).
  static const double defaultQuickGigRadiusKm = 10;

  /// Max search radius in km for a gig region (US = gig currency USD), or
  /// null for no limit.
  static double? quickGigRadiusKm(Map<String, dynamic> config, {required bool us}) {
    if (us && config.containsKey('max_search_radius_mi_us')) {
      final mi = config['max_search_radius_mi_us'];
      return mi is num ? mi.toDouble() * kmPerMile : null;
    }
    if (config.containsKey('max_search_radius_km')) {
      final km = config['max_search_radius_km'];
      return km is num ? km.toDouble() : null;
    }
    return defaultQuickGigRadiusKm;
  }

  /// "10 km" / "6 mi" / "Unlimited" — the radius this viewer's region uses.
  static String quickGigRadiusLabel(Map<String, dynamic> config) {
    final km = quickGigRadiusKm(config, us: miles);
    if (km == null) return 'Unlimited';
    final v = fromKm(km);
    final text = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '$text $unit';
  }
}
