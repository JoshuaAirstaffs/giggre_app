import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

// Matches Philippine (+63 / 09xx) and U.S. (+1 / 10-digit) numbers.
final phoneRegex = RegExp(r'^(\+?63|0)9\d{9}$|^(\+?1)?[2-9]\d{2}[2-9]\d{6}$');

/// Normalises a raw phone input to a standard format.
String formatPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  // Philippine: starts with 09 → +639...
  if (digits.startsWith('09') && digits.length == 11) {
    return '+63${digits.substring(1)}';
  }
  // Philippine: starts with 639
  if (digits.startsWith('639') && digits.length == 12) {
    return '+$digits';
  }
  // U.S.: 10 digits
  if (digits.length == 10) {
    return '+1$digits';
  }
  // U.S.: 11 digits starting with 1
  if (digits.length == 11 && digits.startsWith('1')) {
    return '+$digits';
  }
  return raw.trim();
}

/// Returns true when a userId is missing or uses the old GIGxxxxxx format.
/// Used to trigger regeneration for existing accounts on next login.
bool needsNewUserId(String? userId) {
  if (userId == null || userId.isEmpty) return true;
  return RegExp(r'^GIG\d{6}$').hasMatch(userId);
}

/// One signup password rule (e.g. "at least 8 characters") plus the check
/// for whether a given password satisfies it. Shared by every signup form
/// so the rules and their wording can't drift between screens.
class PasswordRequirement {
  final String label;
  final bool Function(String) isMet;
  const PasswordRequirement(this.label, this.isMet);
}

final List<PasswordRequirement> passwordRequirements = [
  PasswordRequirement('At least 8 characters', (p) => p.length >= 8),
  PasswordRequirement(
    '1 uppercase letter',
    (p) => RegExp(r'[A-Z]').hasMatch(p),
  ),
  PasswordRequirement(
    '1 lowercase letter',
    (p) => RegExp(r'[a-z]').hasMatch(p),
  ),
  PasswordRequirement('1 number', (p) => RegExp(r'[0-9]').hasMatch(p)),
  PasswordRequirement(
    '1 special character',
    (p) => RegExp(r'''[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\/~`]''').hasMatch(p),
  ),
];

bool isPasswordStrong(String password) =>
    passwordRequirements.every((r) => r.isMet(password));

/// Generates a unique user ID: 3 random uppercase letters + 6 random digits
/// (e.g. "XKP482931"). Retries automatically on the rare collision.
Future<String> generateUserId() async {
  const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const digits = '0123456789';
  final rng = Random.secure();
  final db = FirebaseFirestore.instance;

  while (true) {
    final part1 = List.generate(3, (_) => letters[rng.nextInt(26)]).join();
    final part2 = List.generate(6, (_) => digits[rng.nextInt(10)]).join();
    final candidate = '$part1$part2';

    final existing = await db
        .collection('users')
        .where('userId', isEqualTo: candidate)
        .limit(1)
        .get();

    if (existing.docs.isEmpty) return candidate;
    // Collision — retry (probability ≈ 1 in 17 million per attempt)
  }
}

/// SHA-256 hash of the raw Apple Sign-In nonce (see sign_in_with_apple's own
/// generateNonce()) — the hash goes to Apple/Firebase as replay protection,
/// while the raw value is kept to prove we generated it (see signInWithApple
/// in the login/register screens).
String sha256ofString(String input) =>
    sha256.convert(utf8.encode(input)).toString();

/// Best-effort read of the `email` claim from an Apple identityToken JWT,
/// without verifying its signature (Firebase re-verifies it server-side
/// during signInWithCredential). AppleIDCredential.email is only populated
/// on the very first authorization for an account, but the JWT carries the
/// email claim on every sign-in — this is what makes it possible to check
/// for an existing account on repeat Apple sign-ins.
String? emailFromAppleIdToken(String idToken) {
  try {
    final parts = idToken.split('.');
    if (parts.length != 3) return null;
    final payload =
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    return (jsonDecode(payload) as Map<String, dynamic>)['email'] as String?;
  } catch (_) {
    return null;
  }
}
