import 'dart:async';

import 'package:flutter/foundation.dart';

import 'fx_rates.dart';

/// The currency amounts are SHOWN in, and live rates to convert into it.
///
/// [code] is the user's currency from their location (CurrentUserProvider:
/// Philippines → PHP, US and elsewhere → USD, USD by default — re-detected on
/// every app resume). Gig pay in another currency is shown converted
/// ("≈ ₱570", with "orig. $10" where there's room) — display only: gigs are
/// still stored, filtered for payment and paid in their own currency.
class DisplayCurrency {
  DisplayCurrency._();

  static final ValueNotifier<String> code = ValueNotifier('USD');
  static final ValueNotifier<FxRates> rates = ValueNotifier(FxRates.usdOnly);
  static StreamSubscription<FxRates>? _sub;

  /// Rebuild on this to pick up a new currency or fresh rates.
  static final Listenable changes = Listenable.merge([code, rates]);

  /// Starts listening to general_config/fx_rates (needs a signed-in user).
  static void start() {
    _sub ??= FxRates.stream().listen(
      (r) => rates.value = r,
      onError: (Object _) => _sub = null, // retried on the next start()
    );
  }

  static void setCode(String c) {
    if (c.isNotEmpty && code.value != c) code.value = c;
  }

  /// [amount] in [from] → [to] (default: the display currency), mid rate,
  /// rounded to the cent. null when a rate isn't known yet.
  static double? convert(double amount, String from, [String? to]) {
    final target = to ?? code.value;
    if (from == target) return amount;
    final a = rates.value.perUsd(from), b = rates.value.perUsd(target);
    if (a == null || b == null) return null;
    return ((amount / a) * b * 100).round() / 100;
  }
}
