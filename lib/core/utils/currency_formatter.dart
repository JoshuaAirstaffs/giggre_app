import 'package:intl/intl.dart';

import '../services/display_currency.dart';

class CurrencyFormatter {
  static final _thousands = NumberFormat('#,##0');

  static String symbol(String currencyCode) => switch (currencyCode) {
    'PHP' => '₱',
    'USD' => '\$',
    _ => '\$',
  };

  // Format amount with its stored currency symbol, no decimals, comma
  // thousands separators (e.g. ₱12,345).
  static String format(double amount, String currencyCode) =>
      '${symbol(currencyCode)}${_thousands.format(amount)}';

  /// Gig pay for the viewer: in the display currency (the user's location —
  /// see [DisplayCurrency]). Another currency is converted and marked "≈"
  /// (e.g. "≈ ₱570" for a $10 gig seen from the Philippines); the same
  /// currency, or an unknown rate, shows the amount as it is.
  static String pay(double amount, String currencyCode, {bool withOriginal = false}) {
    final target = DisplayCurrency.code.value;
    if (currencyCode == target) return format(amount, currencyCode);
    final converted = DisplayCurrency.convert(amount, currencyCode, target);
    if (converted == null) return format(amount, currencyCode);
    final shown = '≈ ${format(converted, target)}';
    return withOriginal ? '$shown (orig. ${format(amount, currencyCode)})' : shown;
  }

  /// " (orig. $10)" when [pay] converts this amount, else "". For layouts
  /// that put a unit ("/day") between the price and the original.
  static String origSuffix(double amount, String currencyCode) {
    final target = DisplayCurrency.code.value;
    if (currencyCode == target) return '';
    if (DisplayCurrency.convert(amount, currencyCode, target) == null) return '';
    return ' (orig. ${format(amount, currencyCode)})';
  }

  // Map a 2-letter ISO country code to a currency code.
  // PH → PHP, everything else → USD.
  static String countryToCurrency(String? countryCode) =>
      countryCode == 'PH' ? 'PHP' : 'USD';
}
