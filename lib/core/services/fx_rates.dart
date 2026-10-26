import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Live USD exchange rates from general_config/fx_rates (refreshed every 6
/// hours by functions/src/fx.ts; an admin override wins).
///
/// Gig Points / Gig Wallet settings (conversion rates, limits) are in USD.
/// Users whose wallet is in PHP see them converted with [fromUsd]. Amounts
/// shown in the app are previews — the server converts with the same rate and
/// locks it onto each request.
class FxRates {
  /// Units of each currency per 1 USD.
  final Map<String, double> perUsdRates;

  const FxRates(this.perUsdRates);

  static const usdOnly = FxRates({'USD': 1});

  /// Units of [currencyCode] per 1 USD, or null if not known yet.
  double? perUsd(String currencyCode) =>
      currencyCode == 'PHP' ? perUsdRates['PHP'] : 1;

  bool knows(String currencyCode) => perUsd(currencyCode) != null;

  /// USD → [currencyCode], rounded to the cent (null if the rate is unknown).
  double? fromUsd(double usd, String currencyCode) {
    final r = perUsd(currencyCode);
    return r == null ? null : (usd * r * 100).round() / 100;
  }

  /// Between two currencies, rounded down (same as convertDown on the server).
  double? convertDown(double amount, String from, String to) {
    if (from == to) return (amount * 100).round() / 100;
    final a = perUsd(from), b = perUsd(to);
    if (a == null || b == null) return null;
    return ((amount / a) * b * 100 + 1e-9).floorToDouble() / 100;
  }

  factory FxRates.fromMap(Map<String, dynamic>? d) {
    double? pos(Object? v) => v is num && v > 0 ? v.toDouble() : null;
    final live = d?['rates'] is Map ? d!['rates'] as Map : const {};
    final over = d?['override'] is Map ? d!['override'] as Map : const {};
    final php = pos(over['PHP']) ?? pos(live['PHP']);
    return FxRates({'USD': 1, 'PHP': ?php});
  }

  static final _doc =
      FirebaseFirestore.instance.collection('general_config').doc('fx_rates');

  static Stream<FxRates> stream() => _doc
      .snapshots()
      .map((s) => FxRates.fromMap(s.data()))
      .handleError((Object e) => debugPrint('[FxRates] $e'));

  static Future<FxRates> fetch() async {
    try {
      return FxRates.fromMap((await _doc.get()).data());
    } catch (e) {
      debugPrint('[FxRates] read failed: $e');
      return usdOnly;
    }
  }
}
