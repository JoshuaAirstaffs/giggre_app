import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:giggre_app/main.dart' show flavor;

// Lookups made BEFORE the user is signed in. users/{uid} is readable only by
// signed-in users (firestore.rules), so these go through Cloud Functions
// (functions/src/publicLookups.ts), which return only what's needed.

final _functionsRegion = flavor == 'prod' ? 'us-central1' : 'asia-east2';

HttpsCallable _fn(String name) =>
    FirebaseFunctions.instanceFor(region: _functionsRegion).httpsCallable(name);

class PublicLookupService {
  PublicLookupService._();

  /// Whether a Giggre account already uses [email] (Google / Apple sign-in
  /// decides between "log in" and "finish signing up"). Throws if Giggre
  /// can't be reached, so callers don't mistake an error for "no account".
  static Future<bool> accountExists(String email) async {
    final res = await _fn('checkAccountExists').call({'email': email});
    return (res.data as Map)['exists'] == true;
  }

  /// The referrer for a referral code — {'userId', 'name'} — or null when
  /// the code doesn't exist or can't be checked.
  static Future<Map<String, dynamic>?> lookupReferral(String code) async {
    try {
      final res = await _fn('lookupReferralCode').call({'code': code});
      final d = Map<String, dynamic>.from(res.data as Map);
      if (d['found'] != true) return null;
      return {'userId': d['userId'] as String, 'name': d['name'] as String? ?? 'User'};
    } catch (e) {
      debugPrint('[PublicLookup] referral: $e');
      return null;
    }
  }
}
