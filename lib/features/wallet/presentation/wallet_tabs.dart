import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../services/wallet_requests_service.dart';
import 'transaction_details_screen.dart';
import 'widgets/wallet_transaction.dart';

/// The wallet ledger entry model (widgets/wallet_transaction.dart).
typedef WalletTxView = WalletTx;

final _money2 = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
final _timeFmt = DateFormat('h:mm a');
const _amber = Color(0xFFF0A830);

const _blueGradient = [Color(0xFF3B9BFF), Color(0xFF046BD2), Color(0xFF03509E)];
const _goldGradient = [Color(0xFFF6B640), Color(0xFFE88A22), Color(0xFFD9671A)];

// ── Balance card ───────────────────────────────────────────────────────────

/// Wallet-style balance card, same shape as the Gig Points one: available
/// GigCash, status chips and the Top Up / Withdraw / Send actions.
class WalletHero extends StatelessWidget {
  const WalletHero({
    super.key,
    required this.isHost,
    required this.loading,
    required this.hasError,
    required this.balance,
    required this.symbol,
    required this.fromCache,
    required this.pending,
    required this.onTopUp,
    required this.onWithdraw,
    required this.onSend,
    required this.onInfo,
  });

  final bool isHost;
  final bool loading;
  final bool hasError;
  final double balance;
  final String symbol;
  final bool fromCache;
  final WalletRequest? pending;
  final VoidCallback onTopUp;
  final VoidCallback onWithdraw;
  final VoidCallback onSend;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final colors = isHost ? _goldGradient : _blueGradient;
    final deep = colors.last;
    final white80 = Colors.white.withValues(alpha: 0.82);
    final number = NumberFormat.currency(symbol: '', decimalDigits: 2);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors[1].withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            const Positioned(right: -40, top: -50, child: _Ring(size: 170, opacity: 0.10)),
            const Positioned(right: 40, top: 60, child: _Ring(size: 90, opacity: 0.08)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Available GigCash',
                          style: TextStyle(color: white80, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        onPressed: onInfo,
                        tooltip: 'How Gig Wallet works',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (hasError)
                    const Text(
                      "Couldn't load your balance. Pull down to retry.",
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    )
                  else if (loading)
                    const SizedBox(
                      height: 48,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                        ),
                      ),
                    )
                  else
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            symbol,
                            style: TextStyle(color: white80, fontSize: 22, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            number.format(balance).trim(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 40,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (pending != null)
                        _HeroChip(
                          icon: Icons.schedule_rounded,
                          text: '${pending!.label} of ${_money2.format(pending!.amount)} in review',
                        ),
                      if (fromCache && !hasError)
                        const _HeroChip(icon: Icons.cloud_off_rounded, text: 'Offline · last synced'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: _HeroAction(
                            icon: Icons.add_card_rounded,
                            label: 'Top Up',
                            color: deep,
                            enabled: pending == null,
                            onTap: onTopUp,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _HeroAction(
                            icon: Icons.account_balance_rounded,
                            label: 'Withdraw',
                            color: deep,
                            enabled: false,
                            onTap: onWithdraw,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _HeroAction(
                            icon: Icons.north_east_rounded,
                            label: 'Send',
                            color: deep,
                            enabled: pending == null,
                            onTap: onSend,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final double size;
  final double opacity;

  const _Ring({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: opacity), width: 18),
      ),
    ),
  );
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HeroChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 13),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _HeroAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _HeroAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label${enabled ? '' : ', unavailable'}',
      child: InkWell(
        // Still tappable when dimmed, so it can explain why.
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: color, size: 23),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Stats strip ────────────────────────────────────────────────────────────

/// Money in / out over the last 30 days and what's pending, from the loaded
/// history (completed entries only for in/out).
class WalletStatsStrip extends StatelessWidget {
  const WalletStatsStrip({super.key, required this.txs, required this.currency, required this.accent});

  final List<WalletTx>? txs;
  final String currency;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final list = txs;
    final since = DateTime.now().subtract(const Duration(days: 30));
    double moneyIn = 0, moneyOut = 0, pending = 0;
    for (final t in list ?? const <WalletTx>[]) {
      if (t.status == 'pending') {
        pending += t.amount.abs();
        continue;
      }
      if (t.status != 'completed') continue;
      if (t.createdAt != null && t.createdAt!.isBefore(since)) continue;
      if (t.amount >= 0) {
        moneyIn += t.amount;
      } else {
        moneyOut += -t.amount;
      }
    }
    String f(double v) => list == null ? '–' : formatMoney(v, currency);
    final divider = Container(width: 1, height: 34, color: Theme.of(context).dividerColor);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Expanded(child: _Stat(value: f(moneyIn), label: 'In · 30 days', color: kWalletIn)),
          divider,
          Expanded(child: _Stat(value: f(moneyOut), label: 'Out · 30 days', color: kWalletOut)),
          divider,
          Expanded(child: _Stat(value: f(pending), label: 'Pending', color: _amber)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _Stat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: TextStyle(color: color, fontSize: 16.5, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kSub, fontSize: 11.5)),
      ],
    ),
  );
}

// ── Security banner ────────────────────────────────────────────────────────

class WalletSecurityBanner extends StatelessWidget {
  const WalletSecurityBanner({super.key, required this.accent, required this.onTap});

  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: accent.withValues(alpha: 0.10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: accent.withValues(alpha: 0.25)),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.shield_outlined, color: accent, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Your Gig Wallet is protected. Learn about Security and Privacy.',
                style: TextStyle(color: accent, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: accent, size: 20),
          ],
        ),
      ),
    ),
  );
}

// ── Activity tab ───────────────────────────────────────────────────────────

enum WalletFilter {
  all('All'),
  moneyIn('Money in'),
  moneyOut('Money out'),
  pending('Pending');

  final String label;
  const WalletFilter(this.label);

  bool test(WalletTx t) => switch (this) {
    WalletFilter.all => true,
    WalletFilter.moneyIn => t.isIn && t.status == 'completed',
    WalletFilter.moneyOut => !t.isIn && t.status == 'completed',
    WalletFilter.pending => t.status == 'pending',
  };
}

String _dayLabel(DateTime d, DateTime now) {
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat(d.year == now.year ? 'EEE, MMM d' : 'MMM d, y').format(d);
}

/// Filter chips + date-grouped history + paging footer, as slivers.
List<Widget> walletActivitySlivers(
  BuildContext context, {
  required List<WalletTx>? txs,
  required bool hasError,
  required bool fromCache,
  required WalletFilter filter,
  required ValueChanged<WalletFilter> onFilter,
  required bool hasMore,
  required bool loadingMore,
  required VoidCallback onLoadMore,
  required VoidCallback onRetry,
  required String fallbackCurrency,
  required String? role,
  required Color accent,
}) {
  Widget boxed(Widget child) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
    sliver: SliverToBoxAdapter(child: child),
  );

  final chips = SliverPadding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
    sliver: SliverToBoxAdapter(
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in WalletFilter.values) ...[
                    ChoiceChip(
                      label: Text(f.label),
                      selected: f == filter,
                      onSelected: (_) => onFilter(f),
                      showCheckmark: false,
                      selectedColor: accent.withValues(alpha: 0.16),
                      side: BorderSide(color: f == filter ? accent : Theme.of(context).dividerColor),
                      labelStyle: TextStyle(
                        color: f == filter ? accent : Theme.of(context).colorScheme.onSurface,
                        fontWeight: f == filter ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 12.5,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
          if (fromCache)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Tooltip(
                message: 'Offline — showing saved activity',
                child: Icon(Icons.cloud_off_rounded, size: 16, color: kSub),
              ),
            ),
        ],
      ),
    ),
  );

  if (txs == null && !hasError) {
    return [
      chips,
      boxed(Padding(
        padding: const EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator(color: accent)),
      )),
    ];
  }
  if (hasError && (txs == null || txs.isEmpty)) {
    return [
      chips,
      boxed(WalletEmpty(
        icon: Icons.cloud_off_rounded,
        text: "Couldn't load your activity.",
        actionLabel: 'Retry',
        onAction: onRetry,
        accent: accent,
      )),
    ];
  }
  final items = txs!.where(filter.test).toList();
  if (items.isEmpty) {
    return [
      chips,
      boxed(WalletEmpty(
        icon: Icons.receipt_long_outlined,
        text: filter == WalletFilter.all
            ? 'No transactions yet. Top up to add GigCash, or earn it from gigs.'
            : hasMore
            ? 'Nothing here in your recent activity.'
            : 'Nothing here for this filter.',
        actionLabel: hasMore && filter != WalletFilter.all ? 'Load older' : null,
        onAction: onLoadMore,
        accent: accent,
      )),
    ];
  }

  final now = DateTime.now();
  final rows = <Object>[];
  String? current;
  for (final tx in items) {
    final d = tx.createdAt?.toLocal();
    final label = d == null ? 'Earlier' : _dayLabel(d, now);
    if (label != current) {
      rows.add(label);
      current = label;
    }
    rows.add(tx);
  }

  return [
    chips,
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final row = rows[i];
          if (row is String) {
            return Padding(
              padding: EdgeInsets.fromLTRB(4, i == 0 ? 4 : 16, 4, 8),
              child: Text(
                row.toUpperCase(),
                style: const TextStyle(color: kSub, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6),
              ),
            );
          }
          final tx = row as WalletTx;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: WalletActivityTile(
              tx: tx,
              fallbackCurrency: fallbackCurrency,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TransactionDetailsScreen(tx: tx, fallbackCurrency: fallbackCurrency, role: role),
                ),
              ),
            ),
          );
        },
      ),
    ),
    boxed(Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Center(
        child: loadingMore
            ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: accent))
            : hasMore
            ? TextButton(
                onPressed: onLoadMore,
                child: Text('Load more', style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
              )
            : const Text("You're all caught up.", style: TextStyle(color: kSub, fontSize: 12)),
      ),
    )),
  ];
}

({Color color, String label}) _statusStyle(String status) => switch (status) {
  'pending' => (color: _amber, label: 'Pending'),
  'failed' => (color: kSub, label: 'Not approved'),
  'reversed' => (color: kSub, label: 'Reversed'),
  _ => (color: kWalletIn, label: 'Completed'),
};

class WalletActivityTile extends StatelessWidget {
  const WalletActivityTile({super.key, required this.tx, required this.fallbackCurrency, required this.onTap});

  final WalletTx tx;
  final String fallbackCurrency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final done = tx.status == 'completed';
    final dead = tx.status == 'failed' || tx.status == 'reversed';
    final color = dead ? kSub : (tx.status == 'pending' ? _amber : walletTxColor(tx));
    final status = _statusStyle(tx.status);
    final date = tx.createdAt?.toLocal();
    final subtitle = [walletTxTypeLabel(tx.type), if (date != null) _timeFmt.format(date)].join(' · ');

    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.13), shape: BoxShape.circle),
                child: Icon(walletTxIcon(tx.type), color: color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: onSurface, fontSize: 14.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kSub, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    tx.formatAmount(fallbackCurrency),
                    style: TextStyle(
                      color: done ? walletTxColor(tx) : (dead ? kSub : onSurface.withValues(alpha: 0.7)),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      decoration: dead ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _Pill(text: status.label, color: status.color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;

  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
    child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

// ── Requests tab ───────────────────────────────────────────────────────────

class WalletRequestsList extends StatelessWidget {
  const WalletRequestsList({super.key, required this.requests, required this.hasError, required this.accent});

  final List<WalletRequest>? requests;
  final bool hasError;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final list = requests;
    if (list == null && !hasError) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(color: accent)),
      );
    }
    if (hasError && (list == null || list.isEmpty)) {
      return WalletEmpty(
        icon: Icons.cloud_off_rounded,
        text: "Couldn't load your requests. Pull down to retry.",
        accent: accent,
      );
    }
    if (list!.isEmpty) {
      return WalletEmpty(
        icon: Icons.receipt_long_outlined,
        text: 'No requests yet. Use Top Up or Send above — a Giggre admin reviews each one before it goes through.',
        accent: accent,
      );
    }
    final pending = list.where((r) => r.isPending).toList();
    final done = list.where((r) => !r.isPending).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending.isNotEmpty) ...[
          const _GroupLabel('Waiting for review'),
          for (final r in pending) ...[WalletRequestTile(request: r), const SizedBox(height: 8)],
          const SizedBox(height: 8),
        ],
        if (done.isNotEmpty) ...[
          const _GroupLabel('Completed'),
          for (final r in done) ...[WalletRequestTile(request: r), const SizedBox(height: 8)],
        ],
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;

  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(color: kSub, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6),
    ),
  );
}

({Color color, IconData icon, String label}) _requestStatus(String s) => switch (s) {
  'approved' => (color: kWalletIn, icon: Icons.check_circle_rounded, label: 'Approved'),
  'rejected' => (color: Colors.redAccent, icon: Icons.cancel_outlined, label: 'Rejected'),
  'cancelled' => (color: kSub, icon: Icons.block_rounded, label: 'Cancelled'),
  _ => (color: _amber, icon: Icons.hourglass_top_rounded, label: 'Pending review'),
};

class WalletRequestTile extends StatefulWidget {
  const WalletRequestTile({super.key, required this.request});

  final WalletRequest request;

  @override
  State<WalletRequestTile> createState() => _WalletRequestTileState();
}

class _WalletRequestTileState extends State<WalletRequestTile> {
  bool _cancelling = false;

  Future<void> _cancel() async {
    final r = widget.request;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancel this ${r.label.toLowerCase()}?'),
        content: Text(
          r.type == 'transfer'
              ? '${_money2.format(r.amount)} goes back to your Gig Wallet.'
              : 'Giggre will no longer review this top up. If you already paid, contact support instead.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel request', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await WalletRequestsService.cancel(r.id);
      messenger.showSnackBar(const SnackBar(content: Text('Request cancelled.')));
    } on WalletRequestException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final st = _requestStatus(r.status);
    final isSend = r.type == 'transfer';
    final typeColor = isSend ? kWalletOut : kWalletIn;
    final date = r.isPending ? r.createdAt : (r.decidedAt ?? r.createdAt);
    final subtitle = [
      if (isSend && r.recipientName != null) 'To ${r.recipientName}',
      if (!isSend && r.reference != null) 'Ref ${r.reference}',
      if (date != null) DateFormat('MMM d · h:mm a').format(date.toLocal()),
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.13), shape: BoxShape.circle),
                child: Icon(isSend ? Icons.north_east_rounded : Icons.add_card_rounded, color: typeColor, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSend ? 'Send' : 'Top up${r.method == null ? '' : ' via ${r.method}'}',
                      style: TextStyle(color: onSurface, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kSub, fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isSend ? '−' : '+'}${_money2.format(r.amount)}',
                    style: TextStyle(
                      color: r.status == 'approved' ? typeColor : onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      decoration: r.status == 'rejected' || r.status == 'cancelled' ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _Pill(text: st.label, color: st.color),
                ],
              ),
            ],
          ),
          if (r.decisionNote?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text('Reason: ${r.decisionNote}', style: const TextStyle(color: kSub, fontSize: 12, height: 1.35)),
          ],
          if (r.isPending)
            Row(
              children: [
                Expanded(
                  child: Text(
                    isSend ? 'Amount on hold until a Giggre admin reviews it.' : 'Giggre is confirming your payment.',
                    style: const TextStyle(color: kSub, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: _cancelling ? null : _cancel,
                  child: _cancelling
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── How it works ───────────────────────────────────────────────────────────

class WalletInfoTab extends StatelessWidget {
  const WalletInfoTab({super.key, required this.accent, required this.onSecurity});

  final Color accent;
  final VoidCallback onSecurity;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoCard(
          title: 'Top Up',
          icon: Icons.add_card_rounded,
          accent: accent,
          steps: const [
            'Choose how to pay: cash at a Giggre office, a remittance center, or GCash.',
            'Enter the amount, then pay it using the details shown.',
            'Enter the receipt, control or reference number (and a photo if you have one).',
            'Giggre confirms the payment and adds the GigCash.',
          ],
        ),
        const SizedBox(height: 12),
        _InfoCard(
          title: 'Send',
          icon: Icons.north_east_rounded,
          accent: accent,
          steps: const [
            "Enter the person's mobile number.",
            'Enter the amount. It goes on hold in your wallet right away.',
            'Giggre reviews it, then the money arrives. If it is rejected or you cancel, it comes back.',
          ],
          footnote: 'Only verified accounts can send.',
        ),
        const SizedBox(height: 12),
        _InfoCard(
          title: 'Withdraw',
          icon: Icons.account_balance_rounded,
          accent: accent,
          steps: const ['Cashing out to GCash or a bank is coming soon.'],
        ),
        const SizedBox(height: 12),
        _InfoCard(
          title: 'Good to know',
          icon: Icons.info_outline_rounded,
          accent: accent,
          steps: const [
            'You can have one request waiting for review at a time.',
            'Each request has a minimum, a maximum and a daily limit.',
            "You're notified when a request is approved or rejected.",
          ],
        ),
        const SizedBox(height: 12),
        WalletSecurityBanner(accent: accent, onTap: onSecurity),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.icon, required this.accent, required this.steps, this.footnote});

  final String title;
  final IconData icon;
  final Color accent;
  final List<String> steps;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.13), shape: BoxShape.circle),
                child: Icon(icon, color: accent, size: 17),
              ),
              const SizedBox(width: 10),
              Text(title, style: TextStyle(color: onSurface, fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          for (final (i, s) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      steps.length > 1 ? '${i + 1}.' : '•',
                      style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(child: Text(s, style: const TextStyle(color: kSub, fontSize: 13, height: 1.4))),
                ],
              ),
            ),
          if (footnote != null)
            Text(footnote!, style: TextStyle(color: onSurface, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Opened from the balance card's (i) button.
Future<void> showWalletInfoSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      final onSurface = Theme.of(ctx).colorScheme.onSurface;
      Widget para(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: onSurface, fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(body, style: const TextStyle(color: kSub, fontSize: 13, height: 1.4)),
          ],
        ),
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Theme.of(ctx).dividerColor, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('How Gig Wallet works', style: TextStyle(color: onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            para('Available GigCash', 'Money you can send or use. Amounts on hold for a pending Send are already taken out.'),
            para('Pending', 'Top ups waiting for Giggre to confirm your payment, and sends waiting for review.'),
            para('Requests', 'Every top up and send is reviewed by a Giggre admin before it goes through. You can have one waiting at a time.'),
            para('Gig Points', 'You can also convert Gig Points to GigCash from the Gig Points screen.'),
          ],
        ),
      );
    },
  );
}

/// Shared empty / error state.
class WalletEmpty extends StatelessWidget {
  const WalletEmpty({
    super.key,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.accent = kBlue,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, color: accent, size: 28),
        ),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(color: kSub, fontSize: 13, height: 1.45)),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!, style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
          ),
      ],
    ),
  );
}
