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
