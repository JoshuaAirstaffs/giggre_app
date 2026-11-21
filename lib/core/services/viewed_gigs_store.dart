import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gigs the signed-in worker has opened (the detail sheet), so the gig list
/// can show unseen gigs with a bolder title.
///
/// Kept on the device only, per account: it's a reading aid, not data
/// anyone else needs, so it costs no Firestore reads or writes. Clearing
/// app data or switching phones just shows everything as new again.
class ViewedGigsStore {
  ViewedGigsStore._();
  static final instance = ViewedGigsStore._();

  /// Most recent last. Capped so it never grows without bound; gigs this
  /// old have long expired or been filled.
  static const _maxIds = 1000;

  /// Ids of viewed gigs for the current account. Listen to rebuild cards.
  final ValueNotifier<Set<String>> viewed = ValueNotifier(<String>{});

  String? _uid;
  List<String> _order = [];

  static String _key(String uid) => 'viewed_gigs_$uid';

  /// Loads [uid]'s viewed gigs. Safe to call repeatedly; only reloads when
  /// the account changes.
  Future<void> load(String uid) async {
    if (uid.isEmpty || uid == _uid) return;
    _uid = uid;
    _order = [];
    viewed.value = <String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_uid != uid) return; // account changed while loading
      _order = prefs.getStringList(_key(uid)) ?? [];
      viewed.value = _order.toSet();
    } catch (e) {
      debugPrint('[ViewedGigs] load: $e');
    }
  }

  bool isViewed(String gigId) => viewed.value.contains(gigId);

  Future<void> markViewed(String uid, String gigId) async {
    if (uid.isEmpty || gigId.isEmpty) return;
    if (uid != _uid) await load(uid);
    if (viewed.value.contains(gigId)) return;
    _order = [..._order, gigId];
    if (_order.length > _maxIds) {
      _order = _order.sublist(_order.length - _maxIds);
    }
    viewed.value = _order.toSet();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key(uid), _order);
    } catch (e) {
      debugPrint('[ViewedGigs] save: $e');
    }
  }
}
