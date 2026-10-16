import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../models/gig_points_models.dart';
import '../services/gig_points_history_controller.dart';
import '../services/gig_points_service.dart';
import 'current_gig_reward_card.dart';
import 'reward_stage_style.dart';
final _dateFmt = DateFormat('MMM d, y · h:mm a');
final _numFmt = NumberFormat.decimalPattern();

/// Points summary, current gig reward, and task rewards history for the
/// signed-in user.
///
/// Purely a viewer of server-written data (functions/src/gigPoints.ts):
/// "Available" only ever reflects credited points. Every other amount —
/// a configured reward, one awaiting approval, one approved but still
/// processing, or one that didn't qualify — is labelled with its
/// [RewardStage] and never styled or summed as balance.
class GigPointsScreen extends StatefulWidget {
  const GigPointsScreen({super.key});

  @override
  State<GigPointsScreen> createState() => _GigPointsScreenState();
}

class _GigPointsScreenState extends State<GigPointsScreen> {
  String? _uid;
  Stream<GigPointsBalance>? _balance;
  GigPointsHistoryController? _history;
  Future<GigPointsConfig?> _config = GigPointsService.fetchConfig();

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _uid = uid;
    if (uid != null) {
      _balance = GigPointsService.balanceStream(uid);
      _history = GigPointsHistoryController(uid);
    }
  }

  @override
  void dispose() {
    _history?.dispose();
    super.dispose();
  }

  void _retryBalance() {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _balance = GigPointsService.balanceStream(uid));
  }

  // Everything on screen is a live listener already; pull-to-refresh
  // re-reads the reward config and re-opens the listeners (e.g. after a
  // dropped connection), matching gig_history_screen.dart.
  Future<void> _refresh() async {
    final config = GigPointsService.fetchConfig();
    setState(() => _config = config);
    _retryBalance();
    _history?.retry();
    await config;
  }

  // Infinite scroll: fetch the next page as the user nears the bottom.
  // Only real scroll updates — never during layout/build.
  bool _onScroll(ScrollUpdateNotification n) {
    if (n.metrics.extentAfter < 400) _history?.loadMore();
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
        title: const Text(
          'Gig Points',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: history == null
          ? const _Message(
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
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        sliver: SliverList.list(
                          children: [
                            StreamBuilder<GigPointsBalance>(
                              stream: _balance,
                              builder: (context, snap) => _SummarySection(
                                balance: snap.data,
                                hasError: snap.hasError && !snap.hasData,
                                onRetry: _retryBalance,
                              ),
                            ),
                            const SizedBox(height: 16),
                            CurrentGigRewardCard(
                              uid: history.uid,
                              config: _config,
                            ),
                            FutureBuilder<GigPointsConfig?>(
                              future: _config,
                              builder: (context, snap) => _HowToEarnCard(
                                config: snap.data,
                                loaded:
                                    snap.connectionState ==
                                    ConnectionState.done,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const _StageLegend(),
                            const SizedBox(height: 24),
                            _HistoryHeader(fromCache: history.isFromCache),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                      ..._historySlivers(context, history),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  List<Widget> _historySlivers(
    BuildContext context,
    GigPointsHistoryController h,
  ) {
    Widget boxed(Widget child) => SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      sliver: SliverToBoxAdapter(child: child),
    );

    if (h.isLoading) {
      return [
        boxed(
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: kGold)),
          ),
        ),
      ];
    }
    if (h.error != null && h.items.isEmpty) {
      return [
        boxed(
          _Message(
            icon: Icons.cloud_off_rounded,
            text: "Couldn't load your points history.",
            actionLabel: 'Retry',
            onAction: h.retry,
          ),
        ),
      ];
    }
    if (h.isEmpty) {
      return [
        boxed(
          const _Message(
            icon: Icons.history_rounded,
            text:
                'No points yet. Finish a gig as a worker — once the host '
                'approves your work it shows here as pending, and it is '
                'credited when payment is confirmed.',
          ),
        ),
      ];
    }

    final items = h.items;
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverList.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _TransactionTile(
            tx: items[i],
            onTap: () => _TransactionDetailsSheet.show(context, items[i]),
          ),
        ),
      ),
      boxed(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Center(child: _HistoryFooter(controller: h)),
        ),
      ),
    ];
  }
}

// ── Summary ────────────────────────────────────────────────────────────────

class _SummarySection extends StatelessWidget {
  final GigPointsBalance? balance;
  final bool hasError;
  final VoidCallback onRetry;

  const _SummarySection({
    required this.balance,
    required this.hasError,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final b = balance;
    String n(int Function(GigPointsBalance) f) =>
        b == null ? '–' : _numFmt.format(f(b));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFFF0A830), Color(0xFFE07B1A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: kGold.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.stars_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 6),
                  Text(
                    'Available Gig Points',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (hasError)
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Couldn't load your balance.",
                        style: TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    ),
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: const Text(
                        'Retry',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                )
              else
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    n((b) => b.balance),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ),
              if (!hasError) ...[
                const SizedBox(height: 4),
                Text(
                  'Only credited points count toward your balance.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ],
              if (b?.fromCache == true && !hasError) ...[
                const SizedBox(height: 6),
                Text(
                  'Offline — showing your last synced balance',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: rewardStageStyle(RewardStage.approvedProcessing).icon,
                color: rewardStageStyle(RewardStage.approvedProcessing).color,
                value: n((b) => b.pendingPoints),
                label: 'Processing',
                hint: RewardStage.approvedProcessing.explanation,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                icon: Icons.trending_up_rounded,
                color: kGigPointsGreen,
                value: n((b) => b.lifetimeEarned),
                label: 'Lifetime earned',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                icon: Icons.task_alt_rounded,
                color: kBlue,
                value: n((b) => b.gigsRewarded),
                label: 'Tasks rewarded',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String? hint;

  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final tile = _Card(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: kSub, fontSize: 11.5),
          ),
        ],
      ),
    );
    return hint == null ? tile : Tooltip(message: hint!, child: tile);
  }
}

class _HowToEarnCard extends StatelessWidget {
  final GigPointsConfig? config;
  final bool loaded;

  const _HowToEarnCard({required this.config, required this.loaded});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final c = config;
    final String intro;
    if (!loaded) {
      intro = 'Loading reward values…';
    } else if (c == null) {
      intro = "Couldn't load the current reward values. Pull down to retry.";
    } else if (!c.enabled) {
      intro =
          'Gig Points are paused right now. Points you already have are '
          'safe.';
    } else {
      intro =
          'Finish a gig as a worker. A gig pays its own reward if one is set '
          'for it; otherwise it pays the standard reward for its type. Points '
          'are credited after the host approves your work and payment is '
          'confirmed.';
    }
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to earn',
            style: TextStyle(
              color: onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            intro,
            style: const TextStyle(color: kSub, fontSize: 13, height: 1.35),
          ),
          if (c != null && c.enabled) ...[
            const SizedBox(height: 12),
            Text(
              'Standard rewards',
              style: TextStyle(
                color: onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            _RewardRow(
              icon: Icons.bolt_rounded,
              label: 'Quick Gig',
              points: c.pointsFor('quick'),
            ),
            _RewardRow(
              icon: Icons.campaign_rounded,
              label: 'Open Gig',
              points: c.pointsFor('open'),
            ),
            _RewardRow(
              icon: Icons.handshake_rounded,
              label: 'Offered Gig',
              points: c.pointsFor('offered'),
            ),
            if (c.maxPointsPerGig != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Maximum per gig: ${c.maxPointsPerGig} pts.',
                  style: const TextStyle(color: kSub, fontSize: 12),
                ),
              ),
            if (!c.hasAnyTypeReward)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Standard rewards haven\'t been set up yet. Only gigs '
                  'with their own reward pay points for now.',
                  style: TextStyle(color: kSub, fontSize: 12, height: 1.35),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Null when no reward is configured for this type.
  final int? points;

  const _RewardRow({
    required this.icon,
    required this.label,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final p = points;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: kBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            p == null ? 'Not set' : '$p pts',
            style: TextStyle(
              color: p == null ? kSub : kBlue,
              fontSize: 14,
              fontWeight: p == null ? FontWeight.w500 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── History ────────────────────────────────────────────────────────────────

class _HistoryHeader extends StatelessWidget {
  final bool fromCache;

  const _HistoryHeader({required this.fromCache});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Task rewards',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (fromCache)
          const Row(
            children: [
              Icon(Icons.cloud_off_rounded, size: 14, color: kSub),
              SizedBox(width: 4),
              Text('Offline', style: TextStyle(color: kSub, fontSize: 12)),
            ],
          ),
      ],
    );
  }
}

class _HistoryFooter extends StatelessWidget {
  final GigPointsHistoryController controller;

  const _HistoryFooter({required this.controller});

  @override
  Widget build(BuildContext context) {
    final h = controller;
    if (h.error != null) {
      return Column(
        children: [
          const Text(
            "Couldn't load more entries.",
            style: TextStyle(color: kSub, fontSize: 13),
          ),
          TextButton(
            onPressed: h.retry,
            child: const Text(
              'Retry',
              style: TextStyle(color: kBlue, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }
    if (h.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: kGold),
        ),
      );
    }
    if (h.hasMore) {
      return TextButton(
        onPressed: h.loadMore,
        child: const Text(
          'Load more',
          style: TextStyle(color: kBlue, fontWeight: FontWeight.w600),
        ),
      );
    }
    return const Text(
      "That's all your Gig Points history.",
      style: TextStyle(color: kSub, fontSize: 12),
    );
  }
}

/// Colour/icon for an entry: its reward stage, except credited deductions,
/// which read as red.
({Color color, IconData icon}) _entryStyle(GigPointsTransaction tx) =>
    tx.isCredited && tx.points < 0
    ? (color: Colors.redAccent, icon: Icons.remove_circle_outline_rounded)
    : rewardStageStyle(tx.stage);

String _pointsText(GigPointsTransaction tx) {
  final abs = _numFmt.format(tx.points.abs());
  if (tx.status == GigPointsStatus.voided) return abs;
  return tx.points < 0 ? '−$abs' : '+$abs';
}

String _shortId(String id) =>
    id.length <= 8 ? id : '${id.substring(0, 8).toUpperCase()}…';

class _TransactionTile extends StatelessWidget {
  final GigPointsTransaction tx;
  final VoidCallback onTap;

  const _TransactionTile({required this.tx, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = _entryStyle(tx);
    final date = tx.statusDate;
    final voided = tx.status == GigPointsStatus.voided;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: _Card(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(style.icon, color: style.color, size: 20),
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Pill(text: tx.typeLabel, color: kBlue),
                        if (tx.gigId != null)
                          Text(
                            'Task ${_shortId(tx.gigId!)}',
                            style: const TextStyle(color: kSub, fontSize: 11.5),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      date == null
                          ? tx.statusDateLabel
                          : '${tx.statusDateLabel} ${_dateFmt.format(date)}',
                      style: const TextStyle(color: kSub, fontSize: 12),
                    ),
                    if (tx.description?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        tx.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kSub,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _pointsText(tx),
                    style: TextStyle(
                      color: style.color,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      decoration: voided ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  RewardStagePill(stage: tx.stage),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionDetailsSheet extends StatelessWidget {
  final GigPointsTransaction tx;

  const _TransactionDetailsSheet({required this.tx});

  static Future<void> show(BuildContext context, GigPointsTransaction tx) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TransactionDetailsSheet(tx: tx),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = _entryStyle(tx);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    String? d(DateTime? v) => v == null ? null : _dateFmt.format(v);

    final rows = <(String, String?)>[
      ('Type', tx.typeLabel),
      ('Status', tx.stage.label),
      ('Approved', d(tx.approvedAt)),
      ('Completed', d(tx.completedAt)),
      (tx.isAdjustment ? 'Adjusted' : 'Credited', d(tx.creditedAt)),
      ('Voided', d(tx.voidedAt)),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    tx.title,
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${_pointsText(tx)} pts',
                  style: TextStyle(
                    color: style.color,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    decoration: tx.status == GigPointsStatus.voided
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            RewardStagePill(stage: tx.stage),
            const SizedBox(height: 8),
            Text(
              tx.isAdjustment ? 'Adjusted by Giggre support.' : tx.stage.explanation,
              style: TextStyle(color: onSurface, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            Text(
              'Why this amount',
              style: TextStyle(
                color: onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tx.amountExplanation,
              style: const TextStyle(color: kSub, fontSize: 13, height: 1.4),
            ),
            if (tx.description?.isNotEmpty == true && !tx.isAdjustment) ...[
              const SizedBox(height: 6),
              Text(
                tx.description!,
                style: const TextStyle(color: kSub, fontSize: 12, height: 1.4),
              ),
            ],
            const SizedBox(height: 16),
            for (final (label, value) in rows)
              if (value != null) _DetailRow(label: label, value: value),
            if (tx.gigId != null)
              _DetailRow(label: 'Task ID', value: tx.gigId!, copyable: true),
            _DetailRow(label: 'Reference', value: tx.id, copyable: true),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;

  const _DetailRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(color: kSub, fontSize: 13),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
              ),
            ),
          ),
          if (copyable)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$label copied')),
                );
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy_rounded, size: 16, color: kSub),
              ),
            ),
        ],
      ),
    );
  }
}

/// Collapsible key to the five reward stages.
class _StageLegend extends StatefulWidget {
  const _StageLegend();

  @override
  State<_StageLegend> createState() => _StageLegendState();
}

class _StageLegendState extends State<_StageLegend> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'What the reward labels mean',
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: kSub,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  for (final stage in RewardStage.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            rewardStageStyle(stage).icon,
                            size: 18,
                            color: rewardStageStyle(stage).color,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stage.label,
                                  style: TextStyle(
                                    color: rewardStageStyle(stage).color,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  stage.countsTowardBalance
                                      ? '${stage.explanation} Counts toward '
                                            'your available balance.'
                                      : '${stage.explanation} Not part of '
                                            'your available balance.',
                                  style: const TextStyle(
                                    color: kSub,
                                    fontSize: 12.5,
                                    height: 1.35,
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
        ],
      ),
    );
  }
}

// ── Shared bits ────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String text;
  final Color color;

  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: child,
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Message({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Column(
        children: [
          Icon(icon, color: kSub, size: 32),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kSub, fontSize: 13, height: 1.4),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  color: kBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
