import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:smart_auth/smart_auth.dart';

/// Strips the formatting autofill/paste tends to add — spaces, parentheses,
/// dashes, dots — so "(555) 123-4567" validates as "5551234567".
String normalizePhoneDigits(String raw) =>
    raw.trim().replaceAll(RegExp(r'[\s()\-.]'), '');

/// Splits an international number like "+1 (555) 123-4567" into the longest
/// matching dial code from [dialCodes] and the remaining national digits.
/// Returns null when [raw] has no leading '+' or no dial code matches, so
/// regular typing in the national-number field is left alone.
({String dialCode, String national})? splitInternationalNumber(
  String raw,
  Iterable<String> dialCodes,
) {
  final trimmed = raw.trim();
  if (!trimmed.startsWith('+')) return null;
  final digits = '+${trimmed.replaceAll(RegExp(r'\D'), '')}';
  final codes = dialCodes.toSet().toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final code in codes) {
    if (digits.startsWith(code) && digits.length > code.length) {
      return (dialCode: code, national: digits.substring(code.length));
    }
  }
  return null;
}

/// Android only: shows Google's Phone Number Hint picker listing the SIM's
/// numbers (no permission needed). Returns null on iOS/web, when the user
/// dismisses it, or when Play services / the SIM can't provide a number.
Future<String?> requestSimPhoneNumber() async {
  if (kIsWeb || !Platform.isAndroid) return null;
  final result = await SmartAuth.instance.requestPhoneNumberHint();
  return result.hasData ? result.data : null;
}

/// Builds the E.164 number for [national] under the selected [dialCode], or
/// returns null when the digits don't fit that country's format — e.g. a
/// Philippine "0917…" number entered while +1 (US/Canada) is selected.
/// Known formats are checked strictly; other countries only get a length
/// check after dropping a single leading trunk '0'.
String? buildFullPhone(String dialCode, String national) {
  var digits = normalizePhoneDigits(national);
  if (!RegExp(r'^\d+$').hasMatch(digits)) return null;
  switch (dialCode) {
    case '+1':
      // Tolerate the national "1" prefix (1 555 123 4567).
      if (digits.length == 11 && digits.startsWith('1')) {
        digits = digits.substring(1);
      }
      if (!RegExp(r'^[2-9]\d{2}[2-9]\d{6}$').hasMatch(digits)) return null;
    case '+63':
      // Mobile only: 09XX XXX XXXX locally, 9XX XXX XXXX after +63.
      if (digits.startsWith('0')) digits = digits.substring(1);
      if (!RegExp(r'^9\d{9}$').hasMatch(digits)) return null;
    default:
      if (digits.startsWith('0')) digits = digits.substring(1);
      final codeLength = dialCode.length - 1;
      if (digits.length < 6 || digits.length + codeLength > 15) return null;
  }
  return '$dialCode$digits';
}
