import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/current_user_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../services/wallet_requests_service.dart';
import 'cash_in_methods_screen.dart';
import 'choose_recipient_screen.dart';
import 'security_privacy_centre_screen.dart';
import 'wallet_tabs.dart';

enum _Tab { activity, requests, info }

/// Gig Wallet, laid out like the Gig Points screen:
///   balance card (+ Top Up / Withdraw / Send) → stats strip →
///   security banner → pinned tabs: Activity | Requests | How it works.
///
/// Read-only over server-written data: wallets/{uid} and its transactions
/// (functions/src/wallet.ts) and wallet_requests (walletRequests.ts).
/// Top Up and Send are requests a Giggre admin approves; Withdraw is not
/// available yet. Blue in Worker mode, gold in Host mode.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, this.role});

  /// The mode picked on Home: 'host' → gold, anything else → blue.
  final String? role;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  static const _pageSize = 30;

  String? _uid;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _wallet;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _txSub;
  StreamSubscription<List<WalletRequest>>? _reqSub;

  List<WalletTxView>? _txs;
  bool _txError = false;
  bool _txFromCache = false;
  int _txLimit = _pageSize;
  bool _loadingMore = false;

  List<WalletRequest>? _requests;
  bool _reqError = false;

  _Tab _tab = _Tab.activity;
  WalletFilter _filter = WalletFilter.all;

  bool get _isHost => widget.role == 'host';
  Color get _accent => _isHost ? kGold : kBlue;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _listenAll();
  }

  void _listenAll() {
    final uid = _uid;
    if (uid == null) return;
    _wallet = FirebaseFirestore.instance.collection('wallets').doc(uid).snapshots(
      includeMetadataChanges: true,
    );
    _listenTxs();
    _reqSub?.cancel();
    _reqSub = WalletRequestsService.requestsStream(uid).listen(
      (list) {
        if (mounted) setState(() {
          _requests = list;
          _reqError = false;
        });
      },
      onError: (Object e) {
        debugPrint('[Wallet] requests: $e');
        if (mounted) setState(() => _reqError = true);
      },
    );
  }

  // One growing live query (like the Gig Points history), so pending
  // entries flip to completed on screen.
  void _listenTxs() {
    final uid = _uid;
    if (uid == null) return;
    _txSub?.cancel();
    _txSub = FirebaseFirestore.instance
        .collection('wallets')
        .doc(uid)
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .limit(_txLimit)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (q) {
            if (!mounted) return;
            setState(() {
              _txs = q.docs.map(WalletTxView.fromDoc).toList();
              _txFromCache = q.metadata.isFromCache;
              _txError = false;
              _loadingMore = false;
            });
          },
          onError: (Object e) {
            debugPrint('[Wallet] history: $e');
            if (mounted) setState(() {
              _txError = true;
              _loadingMore = false;
            });
          },
        );
  }

  bool get _hasMore => (_txs?.length ?? 0) >= _txLimit;

  void _loadMore() {
    if (_loadingMore || !_hasMore || _txError) return;
    setState(() {
      _loadingMore = true;
      _txLimit += _pageSize;
    });
    _listenTxs();
  }

  bool _onScroll(ScrollUpdateNotification n) {
    if (_tab == _Tab.activity && n.metrics.extentAfter < 400) _loadMore();
    return false;
  }

  Future<void> _refresh() async {
    setState(() {
      _txLimit = _pageSize;
    });
    _listenAll();
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  @override
  void dispose() {
    _txSub?.cancel();
    _reqSub?.cancel();
    super.dispose();
  }

  WalletRequest? get _pending {
    for (final r in _requests ?? const <WalletRequest>[]) {
      if (r.isPending) return r;
    }
    return null;
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// One request at a time (enforced on the server too).
  bool _blockedByPending() {
    final p = _pending;
    if (p == null) return false;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('You have a request in review'),
        content: Text(
          'Your ${p.label.toLowerCase()} of '
          '${walletCash(p.amount, p.currencyCode ?? context.read<CurrentUserProvider>().currencyCode)} '
          'is waiting for a Giggre admin. You can make a new request once it '
          'is approved or rejected, or cancel it from the Requests tab.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
    return true;
  }

  void _topUp() {
    if (_blockedByPending()) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CashInMethodsScreen(role: widget.role)),
    );
  }

  void _send() {
    if (_blockedByPending()) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChooseRecipientScreen(role: widget.role)),
    );
  }

  void _withdraw() => _snack('Withdraw is coming soon.');

  void _openSecurity() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => SecurityPrivacyCentreScreen(role: widget.role)),
  );

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final userCurrency = context.watch<CurrentUserProvider>().currencyCode;
    final uid = _uid;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: const Text('Gig Wallet', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: uid == null
          ? const WalletEmpty(
              icon: Icons.lock_outline_rounded,
              text: 'Sign in to see your Gig Wallet.',
            )
          : RefreshIndicator(
              color: _accent,
              onRefresh: _refresh,
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: _onScroll,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                              stream: _wallet,
                              builder: (context, snap) {
                                final d = snap.data?.data();
                                return WalletHero(
                                  isHost: _isHost,
                                  loading: !snap.hasData && !snap.hasError,
                                  hasError: snap.hasError && !snap.hasData,
                                  balance: (d?['balance'] as num?)?.toDouble() ?? 0,
                                  symbol: CurrencyFormatter.symbol(
                                    d?['currencyCode'] as String? ?? userCurrency,
                                  ),
                                  fromCache: snap.data?.metadata.isFromCache ?? false,
                                  pending: _pending,
                                  onTopUp: _topUp,
                                  onWithdraw: _withdraw,
                                  onSend: _send,
                                  onInfo: () => showWalletInfoSheet(context),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            WalletStatsStrip(
                              txs: _txs,
                              currency: userCurrency,
                              accent: _accent,
                            ),
                            const SizedBox(height: 12),
                            WalletSecurityBanner(accent: _accent, onTap: _openSecurity),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _TabsHeader(
                        background: bg,
                        accent: _accent,
                        selected: _tab,
                        pendingCount: _pending == null ? 0 : 1,
                        onChanged: (t) => setState(() => _tab = t),
                      ),
                    ),
                    ...switch (_tab) {
                      _Tab.activity => walletActivitySlivers(
                        context,
                        txs: _txs,
                        hasError: _txError,
                        fromCache: _txFromCache,
                        filter: _filter,
                        onFilter: (f) => setState(() => _filter = f),
                        hasMore: _hasMore,
                        loadingMore: _loadingMore,
                        onLoadMore: _loadMore,
                        onRetry: _listenTxs,
                        fallbackCurrency: userCurrency,
                        role: widget.role,
                        accent: _accent,
                      ),
                      _Tab.requests => [
                        _boxed(
                          WalletRequestsList(
                            requests: _requests,
                            fallbackCurrency: userCurrency,
                            hasError: _reqError,
                            accent: _accent,
                          ),
                        ),
                      ],
                      _Tab.info => [
                        _boxed(WalletInfoTab(accent: _accent, onSecurity: _openSecurity)),
                      ],
                    },
                  ],
                ),
              ),
            ),
    );
  }

  Widget _boxed(Widget child) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
    sliver: SliverToBoxAdapter(child: child),
  );
}

/// Pinned segmented tabs (same look as Gig Points, in the wallet accent).
class _TabsHeader extends SliverPersistentHeaderDelegate {
  final Color background;
  final Color accent;
  final _Tab selected;
  final int pendingCount;
  final ValueChanged<_Tab> onChanged;

  _TabsHeader({
    required this.background,
    required this.accent,
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
      old.accent != accent ||
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
            _seg(context, _Tab.info, 'How it works'),
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
              color: active ? accent : Colors.transparent,
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
                      color: active ? Colors.white : Theme.of(context).colorScheme.onSurface,
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
                      color: active ? Colors.white : accent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '$badge',
                      style: TextStyle(
                        color: active ? accent : Colors.white,
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
