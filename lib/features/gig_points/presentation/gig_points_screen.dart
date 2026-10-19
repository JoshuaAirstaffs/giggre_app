import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/gig_points_models.dart';
import '../models/gig_points_request_models.dart';
import '../services/gig_points_history_controller.dart';
import '../services/gig_points_service.dart';
import 'current_gig_reward_card.dart';
import 'gig_points_activity.dart';
import 'gig_points_earn_tab.dart';
import 'gig_points_hero.dart';
import 'points_requests_section.dart';

enum _Tab { activity, requests, earn }

/// Wallet-style Gig Points screen:
///   balance card (+ Deposit / Withdraw / Transfer) → stats strip →
///   current gig reward → pinned tabs: Activity | Requests | How to earn.
///
/// Purely a viewer of server-written data (functions/src/gigPoints.ts and
/// gigPointsRequests.ts): "Available" only ever reflects credited points.
/// Every other amount — configured, awaiting approval, processing, on hold,
/// not eligible — is labelled with its status and never shown as balance.
class GigPointsScreen extends StatefulWidget {
  const GigPointsScreen({super.key});

  @override
  State<GigPointsScreen> createState() => _GigPointsScreenState();
}

class _GigPointsScreenState extends State<GigPointsScreen> {
  String? _uid;
  Stream<GigPointsBalance>? _balance;
  Stream<PointsRequestLimits> _limits = GigPointsService.limitsStream();
  // One subscription for the user's requests, shared by the balance card,
  // the tab badge and the Requests tab (a broadcast stream wouldn't replay
  // the latest value to a tab opened later).
  StreamSubscription<List<GigPointsRequest>>? _requestsSub;
  List<GigPointsRequest>? _requestList;
  bool _requestsError = false;
  GigPointsHistoryController? _history;
  Future<GigPointsConfig?> _config = GigPointsService.fetchConfig();

  _Tab _tab = _Tab.activity;
  ActivityFilter _filter = ActivityFilter.all;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _uid = uid;
    if (uid != null) {
      _balance = GigPointsService.balanceStream(uid);
      _listenRequests(uid);
      _history = GigPointsHistoryController(uid);
    }
  }

  void _listenRequests(String uid) {
    _requestsSub?.cancel();
    _requestsSub = GigPointsService.requestsStream(uid, limit: 30).listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _requestList = list.where((r) => !r.byAdmin).toList();
          _requestsError = false;
        });
      },
      onError: (Object e) {
        debugPrint('[GigPointsScreen] requests: $e');
        if (mounted) setState(() => _requestsError = true);
      },
    );
  }

  GigPointsRequest? get _pendingRequest {
    for (final r in _requestList ?? const <GigPointsRequest>[]) {
      if (r.isPending) return r;
    }
    return null;
  }

  @override
  void dispose() {
    _requestsSub?.cancel();
    _history?.dispose();
    super.dispose();
  }

  void _retryBalance() {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _balance = GigPointsService.balanceStream(uid));
  }

  // Everything is a live listener already; pull-to-refresh re-reads the
  // reward config and re-opens the listeners (e.g. after a dropped
  // connection).
  Future<void> _refresh() async {
    final config = GigPointsService.fetchConfig();
    setState(() {
      _config = config;
      _limits = GigPointsService.limitsStream();
    });
    final uid = _uid;
    if (uid != null) _listenRequests(uid);
    _retryBalance();
    _history?.retry();
    await config;
  }

  void _setFilter(ActivityFilter f) {
    setState(() => _filter = f);
    _history?.setTypes(f.types);
  }

  // Infinite scroll on the Activity tab only.
  bool _onScroll(ScrollUpdateNotification n) {
    if (_tab == _Tab.activity && n.metrics.extentAfter < 400) {
      _history?.loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final history = _history;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: const Text(
          'Gig Points',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: history == null
          ? const GigPointsEmpty(
              icon: Icons.lock_outline_rounded,
              text: 'Sign in to see your Gig Points.',
            )
          : RefreshIndicator(
              color: kGold,
              onRefresh: _refresh,
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: _onScroll,
                child: ListenableBuilder(
                  listenable: history,
                  builder: (context, _) => CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: StreamBuilder<GigPointsBalance>(
                            stream: _balance,
                            builder: (context, snap) => Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                GigPointsHero(
                                  balance: snap.data,
                                  hasError: snap.hasError && !snap.hasData,
                                  onRetry: _retryBalance,
                                  limits: _limits,
                                  onShowInfo: () =>
                                      showGigPointsInfoSheet(context),
                                  pendingRequest: _pendingRequest,
                                ),
                                const SizedBox(height: 12),
                                GigPointsStatsStrip(balance: snap.data),
                                const SizedBox(height: 16),
                                CurrentGigRewardCard(
                                  uid: history.uid,
                                  config: _config,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _TabsHeader(
                          background: bg,
                          selected: _tab,
                          pendingCount: (_requestList ?? const [])
                              .where((r) => r.isPending)
                              .length,
                          onChanged: (t) => setState(() => _tab = t),
                        ),
                      ),
                      ..._tabSlivers(context, history),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  List<Widget> _tabSlivers(BuildContext context, GigPointsHistoryController h) {
    Widget boxed(Widget child) => SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      sliver: SliverToBoxAdapter(child: child),
    );
    return switch (_tab) {
      _Tab.activity => [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: ActivityFilterBar(
                    selected: _filter,
                    onChanged: _setFilter,
                  ),
                ),
                if (h.isFromCache)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Tooltip(
                      message: 'Offline — showing saved activity',
                      child: Icon(
                        Icons.cloud_off_rounded,
                        size: 16,
                        color: kSub,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        ...activitySlivers(context, h, filter: _filter),
      ],
      _Tab.requests => [
        boxed(
          PointsRequestsList(
            requests: _requestList,
            hasError: _requestsError,
          ),
        ),
      ],
      _Tab.earn => [boxed(GigPointsEarnTab(config: _config))],
    };
  }
}

/// Pinned segmented tabs. The Requests tab shows a live pending count.
class _TabsHeader extends SliverPersistentHeaderDelegate {
  final Color background;
  final _Tab selected;
  final int pendingCount;
  final ValueChanged<_Tab> onChanged;

  _TabsHeader({
    required this.background,
    required this.selected,
    required this.pendingCount,
    required this.onChanged,
  });

  static const double _height = 60;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  bool shouldRebuild(_TabsHeader old) =>
      old.selected != selected ||
      old.background != background ||
      old.pendingCount != pendingCount;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      color: background,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            _seg(context, _Tab.activity, 'Activity'),
            _seg(context, _Tab.requests, 'Requests', badge: pendingCount),
            _seg(context, _Tab.earn, 'How to earn'),
          ],
        ),
      ),
    );
  }

  Widget _seg(BuildContext context, _Tab t, String label, {int badge = 0}) {
    final active = t == selected;
    return Expanded(
      child: Semantics(
        selected: active,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? kGold : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? Colors.white : kGold,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '$badge',
                      style: TextStyle(
                        color: active ? kGold : Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
