import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../models/gig_points_models.dart';
import '../services/gig_points_history_controller.dart';
import 'reward_stage_style.dart';

final _numFmt = NumberFormat.decimalPattern();
final _timeFmt = DateFormat('h:mm a');
final _dateFmt = DateFormat('MMM d, y · h:mm a');

/// History filters. Each maps to ledger `type` values queried server-side.
enum ActivityFilter {
  all('All', null),
  earned('Earned', ['earn', 'adjustment']),
  deposits('Deposits', ['deposit']),
  withdrawals('Withdrawals', ['withdraw']),
  transfers('Transfers', ['transfer_out', 'transfer_in']);

  final String label;
  final List<String>? types;
  const ActivityFilter(this.label, this.types);
}

class ActivityFilterBar extends StatelessWidget {
  final ActivityFilter selected;
  final ValueChanged<ActivityFilter> onChanged;

  const ActivityFilterBar({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in ActivityFilter.values) ...[
            ChoiceChip(
              label: Text(f.label),
              selected: f == selected,
              onSelected: (_) => onChanged(f),
              showCheckmark: false,
              selectedColor: kGold.withValues(alpha: 0.18),
              side: BorderSide(
                color: f == selected ? kGold : Theme.of(context).dividerColor,
              ),
              labelStyle: TextStyle(
                color: f == selected
                    ? const Color(0xFFD9671A)
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: f == selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// "Today", "Yesterday", or a date — the group an entry falls in.
String dayLabel(DateTime d, DateTime now) {
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat(d.year == now.year ? 'EEE, MMM d' : 'MMM d, y').format(d);
}

/// Activity tab body as slivers: date-grouped entries plus paging footer.
List<Widget> activitySlivers(
  BuildContext context,
  GigPointsHistoryController h, {
  required ActivityFilter filter,
}) {
  Widget boxed(Widget child) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
    sliver: SliverToBoxAdapter(child: child),
  );

  if (h.isLoading) {
    return [
      boxed(
        const Padding(
          padding: EdgeInsets.all(28),
          child: Center(child: CircularProgressIndicator(color: kGold)),
        ),
      ),
    ];
  }
  if (h.error != null && h.items.isEmpty) {
    return [
      boxed(
        GigPointsEmpty(
          icon: Icons.cloud_off_rounded,
          text: "Couldn't load your activity.",
          actionLabel: 'Retry',
          onAction: h.retry,
        ),
      ),
    ];
  }
  if (h.isEmpty) {
    return [
      boxed(
        GigPointsEmpty(
          icon: Icons.history_rounded,
          text: filter == ActivityFilter.all
              ? 'No activity yet. Finish a gig as a worker to earn points — '
                    'they show here as processing once the host approves, and '
                    'are credited when payment is confirmed.'
              : 'No ${filter.label.toLowerCase()} yet.',
        ),
      ),
    ];
  }

  // Flatten into headers + entries, grouped by local calendar day.
  final now = DateTime.now();
  final rows = <Object>[];
  String? current;
  for (final tx in h.items) {
    final d = (tx.statusDate ?? tx.createdAt)?.toLocal();
    final label = d == null ? 'Earlier' : dayLabel(d, now);
    if (label != current) {
      rows.add(label);
      current = label;
    }
    rows.add(tx);
  }

  return [
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
                style: const TextStyle(
                  color: kSub,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            );
          }
          final tx = row as GigPointsTransaction;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ActivityTile(
              tx: tx,
              onTap: () => TransactionDetailsSheet.show(context, tx),
            ),
          );
        },
      ),
    ),
    boxed(
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Center(child: _Footer(controller: h)),
      ),
    ),
  ];
}

/// Icon + colour for an entry: its type for movements, else its stage.
({Color color, IconData icon}) entryStyle(GigPointsTransaction tx) {
  if (tx.status == GigPointsStatus.voided) {
    return (color: kSub, icon: Icons.block_rounded);
  }
  return switch (tx.type) {
    'deposit' => (color: kGigPointsGreen, icon: Icons.add_circle_outline_rounded),
    'withdraw' => (
      color: const Color(0xFFE07B1A),
      icon: Icons.account_balance_wallet_outlined,
    ),
    'transfer_out' => (color: kBlue, icon: Icons.north_east_rounded),
    'transfer_in' => (color: kGigPointsGreen, icon: Icons.south_west_rounded),
    'adjustment' => tx.points < 0
        ? (color: Colors.redAccent, icon: Icons.remove_circle_outline_rounded)
        : (color: kGigPointsGreen, icon: Icons.card_giftcard_rounded),
    _ => switch (tx.gigType) {
      'quick' => (color: rewardStageStyle(tx.stage).color, icon: Icons.bolt_rounded),
      'open' => (color: rewardStageStyle(tx.stage).color, icon: Icons.campaign_rounded),
      'offered' => (
        color: rewardStageStyle(tx.stage).color,
        icon: Icons.handshake_rounded,
      ),
      _ => rewardStageStyle(tx.stage),
    },
  };
}

String pointsText(GigPointsTransaction tx) {
  final abs = _numFmt.format(tx.points.abs());
  if (tx.status == GigPointsStatus.voided) return abs;
  return tx.points < 0 ? '−$abs' : '+$abs';
}

Color _amountColor(BuildContext context, GigPointsTransaction tx) {
  if (tx.status == GigPointsStatus.voided) return kSub;
  if (tx.status == GigPointsStatus.pending) {
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
  }
  return tx.points < 0
      ? Theme.of(context).colorScheme.onSurface
      : kGigPointsGreen;
}

class ActivityTile extends StatelessWidget {
  final GigPointsTransaction tx;
  final VoidCallback onTap;

  const ActivityTile({super.key, required this.tx, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = entryStyle(tx);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final date = (tx.statusDate ?? tx.createdAt)?.toLocal();
    final note = tx.isMovement ? tx.note : null;
    final subtitle = [
      tx.typeLabel,
      if (date != null) _timeFmt.format(date),
    ].join(' · ');
    final voided = tx.status == GigPointsStatus.voided;

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
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: Icon(style.icon, color: style.color, size: 21),
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
                        color: onSurface,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kSub, fontSize: 12),
                    ),
                    if (note?.isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(
                        note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kSub,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    pointsText(tx),
                    style: TextStyle(
                      color: _amountColor(context, tx),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      decoration: voided ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 5),
                  EntryStatusPill(tx: tx),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Status in the entry's stage colour. Task rewards read as their reward
/// stage; deposits/withdrawals/transfers as a request status.
class EntryStatusPill extends StatelessWidget {
  final GigPointsTransaction tx;

  const EntryStatusPill({super.key, required this.tx});

  @override
  Widget build(BuildContext context) {
    if (!tx.isMovement) return RewardStagePill(stage: tx.stage);
    final color = tx.status == GigPointsStatus.voided
        ? kSub
        : rewardStageStyle(tx.stage).color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        tx.statusLabel,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final GigPointsHistoryController controller;

  const _Footer({required this.controller});

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
      "You're all caught up.",
      style: TextStyle(color: kSub, fontSize: 12),
    );
  }
}

/// Shared empty / error state for the tabs.
class GigPointsEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const GigPointsEmpty({
    super.key,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kGold.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: kGold, size: 28),
        ),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: kSub, fontSize: 13, height: 1.45),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(
              actionLabel!,
              style: const TextStyle(color: kBlue, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    ),
  );
}

// ── Details sheet ──────────────────────────────────────────────────────────

class TransactionDetailsSheet extends StatelessWidget {
  final GigPointsTransaction tx;

  const TransactionDetailsSheet({super.key, required this.tx});

  static Future<void> show(BuildContext context, GigPointsTransaction tx) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TransactionDetailsSheet(tx: tx),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = entryStyle(tx);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    String? d(DateTime? v) => v == null ? null : _dateFmt.format(v.toLocal());

    final rows = <(String, String?)>[
      ('Type', tx.typeLabel),
      if (tx.isMovement && tx.counterpartyName != null)
        (
          tx.type == 'transfer_in' ? 'From' : 'To',
          '${tx.counterpartyName}'
              '${tx.counterpartyCode == null ? '' : ' (${tx.counterpartyCode})'}',
        ),
      if (tx.isMovement) ('Requested', d(tx.createdAt)),
      ('Approved', d(tx.approvedAt)),
      ('Completed', d(tx.isMovement ? tx.creditedAt : tx.completedAt)),
      if (!tx.isMovement)
        (tx.isAdjustment ? 'Adjusted' : 'Credited', d(tx.creditedAt)),
      (tx.isMovement ? tx.statusLabel : 'Voided', d(tx.voidedAt)),
      if (tx.reference?.isNotEmpty == true) ('Payment ref.', tx.reference),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          const SizedBox(height: 20),
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: style.color.withValues(alpha: 0.13),
                shape: BoxShape.circle,
              ),
              child: Icon(style.icon, color: style.color, size: 28),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${pointsText(tx)} pts',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _amountColor(context, tx),
              fontSize: 30,
              fontWeight: FontWeight.w800,
              decoration: tx.status == GigPointsStatus.voided
                  ? TextDecoration.lineThrough
                  : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tx.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Center(child: EntryStatusPill(tx: tx)),
          const SizedBox(height: 16),
          _InfoBox(
            title: tx.isMovement ? 'Status' : 'Where it is',
            body: tx.statusExplanation,
          ),
          const SizedBox(height: 8),
          _InfoBox(
            title: tx.isMovement ? 'Details' : 'Why this amount',
            body: tx.amountExplanation,
          ),
          const SizedBox(height: 12),
          for (final (label, value) in rows)
            if (value != null) _DetailRow(label: label, value: value),
          if (tx.gigId != null)
            _DetailRow(label: 'Task ID', value: tx.gigId!, copyable: true),
          _DetailRow(label: 'Reference', value: tx.id, copyable: true),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String title;
  final String body;

  const _InfoBox({required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          style: const TextStyle(color: kSub, fontSize: 13, height: 1.4),
        ),
      ],
    ),
  );
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: kSub, fontSize: 13),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
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
                padding: EdgeInsets.only(left: 6, top: 1),
                child: Icon(Icons.copy_rounded, size: 16, color: kSub),
              ),
            ),
        ],
      ),
    );
  }
}
