class CurrencyFormatter {
  static String symbol(String currencyCode) => switch (currencyCode) {
        'PHP' => '₱',
        'USD' => '\$',
        _ => '\$',
      };

  // Format amount with its stored currency symbol, no decimals.
  static String format(double amount, String currencyCode) =>
      '${symbol(currencyCode)}${amount.toStringAsFixed(0)}';

  // Map a 2-letter ISO country code to a currency code.
  // PH → PHP, everything else → USD.
  static String countryToCurrency(String? countryCode) =>
      countryCode == 'PH' ? 'PHP' : 'USD';
}
