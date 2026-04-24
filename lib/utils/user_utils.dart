import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

// Matches Philippine (+63 / 09xx) and U.S. (+1 / 10-digit) numbers.
final phoneRegex = RegExp(
  r'^(\+?63|0)9\d{9}$|^(\+?1)?[2-9]\d{2}[2-9]\d{6}$',
);

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

/// Generates a unique user ID: 3 random uppercase letters + 6 random digits
/// (e.g. "XKP482931"). Retries automatically on the rare collision.
Future<String> generateUserId() async {
  const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const digits  = '0123456789';
  final rng = Random.secure();
  final db  = FirebaseFirestore.instance;

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
