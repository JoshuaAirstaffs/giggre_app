import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Client-side content gate mirroring the server-side word-filter matcher
/// (functions/src/wordFilter.ts) so disallowed content is rejected before it
/// ever round-trips to Firestore. Reads the admin-managed
/// `app_content/word_filter` doc and keeps a live listener so admin edits to
/// the blocked-term list apply without an app restart — same idea as
/// _MaintenanceGate's general_config/maintenance listener in main.dart,
/// just a plain listener instead of a widget-level StreamBuilder.
class ContentFilterService {
  ContentFilterService._();
  static final ContentFilterService instance = ContentFilterService._();

  static const String rejectionMessage =
      "This content doesn't meet our community guidelines. Please revise and try again.";

  static const _prefsTermsKey = 'content_filter_blocked_terms';
  static const _prefsEnabledKey = 'content_filter_enabled';

  final DocumentReference _docRef = FirebaseFirestore.instance
      .collection('app_content')
      .doc('word_filter');

  Set<String> _terms = <String>{};
  bool _enabled = false;
  StreamSubscription? _subscription;

  // Call once at app startup (see main.dart). Loads the last-known-good list
  // from shared_preferences first so `check()` is usable immediately, then
  // tries a live fetch — if that fails (no network, and no doc has ever been
  // cached), `_terms`/`_enabled` stay at their empty/false defaults, so
  // `check()` fails OPEN rather than blocking every submission.
  Future<void> initialize() async {
    await _loadFromCache();
    try {
      final first = await _docRef.snapshots().first.timeout(
        const Duration(seconds: 5),
      );
      _applySnapshot(first);
    } catch (e) {
      debugPrint('[ContentFilterService] initial load failed: $e');
    }
    _subscription?.cancel();
    _subscription = _docRef.snapshots().listen(
      _applySnapshot,
      onError: (e) => debugPrint('[ContentFilterService] listener error: $e'),
    );
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedTerms = prefs.getStringList(_prefsTermsKey);
      if (cachedTerms != null) _terms = cachedTerms.toSet();
      _enabled = prefs.getBool(_prefsEnabledKey) ?? false;
    } catch (e) {
      debugPrint('[ContentFilterService] cache load failed: $e');
    }
  }

  void _applySnapshot(DocumentSnapshot snapshot) {
    final data = snapshot.data() as Map<String, dynamic>?;
    if (data == null) return;
    _terms = (data['blockedTerms'] as List<dynamic>? ?? const [])
        .map((t) => t.toString().toLowerCase().trim())
        .where((t) => t.isNotEmpty)
        .toSet();
    _enabled = data['enabled'] as bool? ?? false;
    _persistToCache();
  }

  Future<void> _persistToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsTermsKey, _terms.toList());
      await prefs.setBool(_prefsEnabledKey, _enabled);
    } catch (e) {
      debugPrint('[ContentFilterService] cache persist failed: $e');
    }
  }

  /// True if [text] contains a blocked term/phrase as a whole word — mirrors
  /// the server matcher's `(?<![a-z0-9])TERM(?![a-z0-9])` boundary so e.g.
  /// "asshole" never matches inside "assholetown" (Scunthorpe problem), and
  /// a multi-word phrase like "sex for cash" is matched as one literal unit
  /// bounded the same way, not word-by-word.
  bool check(String text) {
    if (!_enabled || _terms.isEmpty) return false;
    final normalized = text.toLowerCase();
    for (final term in _terms) {
      final pattern = RegExp('(?<![a-z0-9])${RegExp.escape(term)}(?![a-z0-9])');
      if (pattern.hasMatch(normalized)) return true;
    }
    return false;
  }
}
