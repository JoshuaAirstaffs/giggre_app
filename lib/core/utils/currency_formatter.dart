import 'package:intl/intl.dart';

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

  // Map a 2-letter ISO country code to a currency code.
  // PH → PHP, everything else → USD.
  static String countryToCurrency(String? countryCode) =>
      countryCode == 'PH' ? 'PHP' : 'USD';
}
