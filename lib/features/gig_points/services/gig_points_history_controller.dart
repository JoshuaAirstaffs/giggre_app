import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/gig_points_models.dart';
import 'gig_points_service.dart';

/// Paged, live view of a user's Gig Points ledger.
///
/// Pages grow a single live query (limit += pageSize) rather than stitching
/// cursor pages together, so every visible entry stays live — a pending
/// entry flips to Credited/Voided on screen the moment the backend records
/// it, with no duplicates or gaps when new entries arrive at the top.
class GigPointsHistoryController extends ChangeNotifier {
  final String uid;
  final int pageSize;

  GigPointsHistoryController(this.uid, {this.pageSize = 20})
    : _limit = pageSize {
    _listen();
  }

  int _limit;

  /// Ledger types to show; null = everything.
  List<String>? _types;
  List<String>? get types => _types;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  List<GigPointsTransaction> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _fromCache = false;
  Object? _error;

  List<GigPointsTransaction> get items => _items;

  /// First load, nothing to show yet.
  bool get isLoading => _loading;
  bool get isLoadingMore => _loadingMore;
  bool get hasMore => _hasMore;

  /// Showing device-cached entries (offline) rather than server-confirmed.
  bool get isFromCache => _fromCache;
  Object? get error => _error;
  bool get isEmpty => !_loading && _error == null && _items.isEmpty;

  void _listen() {
    _sub?.cancel();
    _sub = GigPointsService.transactionsQuery(uid, limit: _limit, types: _types)
        .snapshots(includeMetadataChanges: true)
        .listen(_onData, onError: _onError);
  }

  void _onData(QuerySnapshot<Map<String, dynamic>> q) {
    final full = q.docs.length >= _limit;
    _items = q.docs.map(GigPointsTransaction.fromSnapshot).toList();
    _fromCache = q.metadata.isFromCache;
    _error = null;
    _loading = false;
    // A cache-only answer to a bigger page can be short just because older
    // entries were never cached — wait for the server before deciding the
    // history has ended.
    if (_fromCache && !full) {
      _hasMore = _hasMore || _loadingMore;
    } else {
      _hasMore = full;
      _loadingMore = false;
    }
    notifyListeners();
  }

  void _onError(Object e) {
    debugPrint('[GigPointsHistory] $e');
    _error = e;
    _loading = false;
    _loadingMore = false;
    notifyListeners();
  }

  void loadMore() {
    if (_loadingMore || !_hasMore || _error != null) return;
    _loadingMore = true;
    _limit += pageSize;
    notifyListeners();
    _listen();
  }

  /// Switches the filter and starts again from the first page.
  void setTypes(List<String>? types) {
    if (listEquals(types, _types)) return;
    _types = types;
    _limit = pageSize;
    _items = const [];
    _loading = true;
    _loadingMore = false;
    _hasMore = false;
    _error = null;
    notifyListeners();
    _listen();
  }

  void retry() {
    _error = null;
    _loading = _items.isEmpty;
    notifyListeners();
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
