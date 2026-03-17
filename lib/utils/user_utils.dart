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

/// Generates a short unique user ID using Firestore (collision-resistant).
Future<String> generateUserId() async {
  final ref = FirebaseFirestore.instance.collection('_counters').doc('userId');
  // Use a transaction to get an auto-incrementing integer.
  final result = await FirebaseFirestore.instance.runTransaction((tx) async {
    final snap = await tx.get(ref);
    final next = (snap.exists ? (snap.data()?['value'] as int? ?? 0) : 0) + 1;
    tx.set(ref, {'value': next});
    return next;
  });
  return 'GIG${result.toString().padLeft(6, '0')}';
}
