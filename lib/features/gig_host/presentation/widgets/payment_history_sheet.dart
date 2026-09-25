import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../../core/providers/current_user_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../gig_shared/active_gig_step.dart';
import '../../models/worker_slot_model.dart';

// One worker's contribution to a completed gig's payout — built from either
// the `workers` subcollection (multi-worker gigs) or straight off the parent
// gig doc's own fields (legacy single-worker gigs, which never had a
// subcollection doc of their own).
class _PaidWorker {
  final String name;
  final double amount;
  final String currencyCode;
  final int? durationSeconds;

  const _PaidWorker({
    required this.name,
    required this.amount,
    required this.currencyCode,
    this.durationSeconds,
  });
}

String _collectionFor(String gigType) {
  switch (gigType) {
    case 'open':
      return 'open_gigs';
    case 'offered':
      return 'offered_gigs';
    default:
      return 'quick_gigs';
  }
}

class PaymentHistorySheet extends StatefulWidget {
  final List<Map<String, dynamic>> gigs;

  const PaymentHistorySheet({super.key, required this.gigs});

  static Future<void> show({
    required BuildContext context,
    required List<Map<String, dynamic>> completedGigs,
  }) {
    final sorted = [...completedGigs]
      ..sort((a, b) {
        final aTs = a['completedAt'] as Timestamp?;
        final bTs = b['completedAt'] as Timestamp?;
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return bTs.compareTo(aTs);
      });

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaymentHistorySheet(gigs: sorted),
    );
  }

  static _MethodConfig _methodConfig(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return const _MethodConfig(
          icon: Icons.payments_rounded,
          color: Color(0xFF10B981),
          label: 'Cash',
        );
      case 'stripe':
        return const _MethodConfig(
          icon: Icons.credit_card_rounded,
          color: Color(0xFF6366F1),
          label: 'Stripe',
        );
      case 'gcash':
      case 'maya':
      case 'maya / gcash':
        return const _MethodConfig(
          icon: Icons.account_balance_wallet_rounded,
          color: Color(0xFF0EA5E9),
          label: 'E-Wallet',
        );
      default:
        return const _MethodConfig(
          icon: Icons.payments_outlined,
          color: kSub,
          label: 'Other',
        );
    }
  }

  @override
  State<PaymentHistorySheet> createState() => _PaymentHistorySheetState();
}

class _PaymentHistorySheetState extends State<PaymentHistorySheet> {
  final Map<String, List<_PaidWorker>> _workersByGig = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWorkers();
  }

  Future<void> _loadWorkers() async {
    final db = FirebaseFirestore.instance;

    await Future.wait(
      widget.gigs.map((g) async {
        final gigId = g['docId'] as String?;
        if (gigId == null) return;
        final workerSlots = (g['workerSlots'] as num?)?.toInt() ?? 1;
        final currencyCode = (g['currencyCode'] as String?) ?? 'USD';

        if (workerSlots > 1) {
          final gigType = g['gigType'] as String? ?? 'quick';
          try {
            final snap = await db
                .collection(_collectionFor(gigType))
                .doc(gigId)
                .collection('workers')
                .where('status', isEqualTo: 'completed')
                .get();
            _workersByGig[gigId] = snap.docs.map((d) {
              final w = WorkerSlotModel.fromDoc(d);
              return _PaidWorker(
                name: w.workerName.isNotEmpty ? w.workerName : 'Worker',
                amount: w.finalAmount ?? w.adjustedAmount ?? w.rate,
                currencyCode: w.currencyCode,
                durationSeconds: w.durationSeconds,
              );
            }).toList();
          } catch (_) {
            _workersByGig[gigId] = [];
          }
        } else {
          final budget = (g['budget'] as num?)?.toDouble() ?? 0;
          final name =
              (g['assignedWorkerName'] as String?) ??
              (g['workerName'] as String?) ??
              'Worker';
          _workersByGig[gigId] = [
            _PaidWorker(
              name: name,
              amount:
                  (g['finalAmount'] as num?)?.toDouble() ??
                  (g['adjustedAmount'] as num?)?.toDouble() ??
                  budget,
              currencyCode: currencyCode,
              durationSeconds: (g['durationSeconds'] as num?)?.toInt(),
            ),
          ];
        }
      }),
    );

    if (mounted) setState(() => _loading = false);
  }

  // Actual amount paid out for a gig — sum of every worker's final payment,
  // not the posted rate (which for hourly gigs is per-hour, not the total,
  // and for multi-worker gigs is per-slot, not the aggregate).
  double _totalPaidFor(Map<String, dynamic> g) {
    final gigId = g['docId'] as String?;
    final workers = gigId != null ? _workersByGig[gigId] : null;
    if (workers != null) {
      return workers.fold(0.0, (total, w) => total + w.amount);
    }
    // Fallback while still loading.
    final rate = (g['budget'] as num?)?.toDouble() ?? 0;
    final slots = (g['workerSlots'] as num?)?.toInt() ?? 1;
    return rate * slots;
  }

  Map<String, double> get _totalByCurrency {
    final map = <String, double>{};
    for (final g in widget.gigs) {
      final code = (g['currencyCode'] as String?) ?? 'USD';
      map[code] = (map[code] ?? 0) + _totalPaidFor(g);
    }
    return map;
  }

  // Spending per payment method (keyed by method label), tracks first-seen currency per method.
  Map<String, ({double amount, String currencyCode})> get _byMethod {
    final map = <String, ({double amount, String currencyCode})>{};
    for (final g in widget.gigs) {
      final method = (g['paymentMethod'] as String? ?? 'cash');
      final amount = _totalPaidFor(g);
      final code = (g['currencyCode'] as String?) ?? 'USD';
      final existing = map[method];
      map[method] = (
        amount: (existing?.amount ?? 0) + amount,
        currencyCode: existing?.currencyCode ?? code,
      );
    }
    return map;
  }

  String _totalSpentLabel(BuildContext context) {
    final entries = _totalByCurrency.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) {
      return CurrencyFormatter.format(
        0,
        context.watch<CurrentUserProvider>().currencyCode,
      );
    }
    return entries
        .map((e) => CurrencyFormatter.format(e.value, e.key))
        .join('  ');
  }

  void _showWorkers(Map<String, dynamic> gig) {
    final gigId = gig['docId'] as String?;
    final workers = gigId != null
        ? _workersByGig[gigId] ?? const <_PaidWorker>[]
        : const <_PaidWorker>[];
    final title = gig['title'] as String? ?? 'Gig';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WorkersSheet(title: title, workers: workers),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    const green = Color(0xFF10B981);
    final gigs = widget.gigs;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Handle ──────────────────────────────────────────────────
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.receipt_long_outlined,
                      color: green,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment History',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${gigs.length} transaction${gigs.length == 1 ? '' : 's'}',
                        style: const TextStyle(color: kSub, fontSize: 12),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (gigs.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _totalSpentLabel(context),
                          style: TextStyle(
                            color: onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'total spent',
                          style: TextStyle(color: kSub, fontSize: 10),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // ── Method summary chips ─────────────────────────────────────
            if (gigs.isNotEmpty && _byMethod.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: _byMethod.entries.map((e) {
                    final cfg = PaymentHistorySheet._methodConfig(e.key);
                    final label = CurrencyFormatter.format(
                      e.value.amount,
                      e.value.currencyCode,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: cfg.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: cfg.color.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(cfg.icon, color: cfg.color, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              cfg.label,
                              style: TextStyle(
                                color: cfg.color,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              label,
                              style: TextStyle(
                                color: cfg.color,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            const Divider(height: 1, color: kBorder),

            // ── List ────────────────────────────────────────────────────
            if (gigs.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        color: kSub.withValues(alpha: 0.35),
                        size: 52,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No payments yet',
                        style: TextStyle(color: kSub, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Completed gigs will appear here',
                        style: TextStyle(color: kSub, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else if (_loading)
              Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                    color: green,
                    strokeWidth: 2,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: gigs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) => _PaymentCard(
                    gig: gigs[i],
                    isDark: isDark,
                    totalSpent: _totalPaidFor(gigs[i]),
                    onTap: () => _showWorkers(gigs[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MethodConfig {
  final IconData icon;
  final Color color;
  final String label;
  const _MethodConfig({
    required this.icon,
    required this.color,
    required this.label,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Individual payment entry card
// ─────────────────────────────────────────────────────────────────────────────
class _PaymentCard extends StatelessWidget {
  final Map<String, dynamic> gig;
  final bool isDark;
  final double totalSpent;
  final VoidCallback onTap;

  const _PaymentCard({
    required this.gig,
    required this.isDark,
    required this.totalSpent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final title = gig['title'] as String? ?? 'Gig';
    final currencyCode = (gig['currencyCode'] as String?) ?? 'USD';
    final paymentMethod = gig['paymentMethod'] as String? ?? 'cash';
    final workerName =
        gig['assignedWorkerName'] as String? ??
        gig['workerName'] as String? ??
        '';
    final completedAt = gig['completedAt'] as Timestamp?;
    final gigType = gig['gigType'] as String? ?? 'quick';
    final workerSlots = (gig['workerSlots'] as num?)?.toInt() ?? 1;
    final isMultiWorker = workerSlots > 1;

    final cfg = PaymentHistorySheet._methodConfig(paymentMethod);

    final typeColor = gigType == 'quick'
        ? kAmber
        : gigType == 'open'
        ? kBlue
        : const Color(0xFF8B5CF6);
    final typeIcon = gigType == 'quick'
        ? Icons.bolt_rounded
        : gigType == 'open'
        ? Icons.work_outline_rounded
        : Icons.handshake_outlined;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.grey.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? kBorder : Colors.grey.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            // ── Payment method icon ────────────────────────────────────
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cfg.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(cfg.icon, color: cfg.color, size: 20),
            ),
            const SizedBox(width: 12),

            // ── Info ───────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(typeIcon, color: typeColor, size: 13),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cfg.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          cfg.label,
                          style: TextStyle(
                            color: cfg.color,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!isMultiWorker && workerName.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.person_outline_rounded,
                          size: 11,
                          color: kSub,
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            workerName,
                            style: const TextStyle(color: kSub, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      if (isMultiWorker) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.groups_rounded, size: 11, color: kSub),
                        const SizedBox(width: 2),
                        Text(
                          '× $workerSlots workers',
                          style: const TextStyle(color: kSub, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                  if (completedAt != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 11,
                          color: kSub,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _fmtDate(completedAt),
                          style: const TextStyle(color: kSub, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // ── Amount ────────────────────────────────────────────────
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.format(totalSpent, currencyCode),
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'total spent',
                  style: TextStyle(color: kSub, fontSize: 9.5),
                ),
                const SizedBox(height: 2),
                const Icon(Icons.chevron_right_rounded, size: 14, color: kSub),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(Timestamp ts) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dt = ts.toDate().toLocal();
    return '${months[dt.month]} ${dt.day}, ${dt.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Workers drawer — who was assigned to this gig, their worked hours, and
//  what they were each actually paid.
// ─────────────────────────────────────────────────────────────────────────────
class _WorkersSheet extends StatelessWidget {
  final String title;
  final List<_PaidWorker> workers;

  const _WorkersSheet({required this.title, required this.workers});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${workers.length} worker${workers.length == 1 ? '' : 's'} assigned',
                    style: const TextStyle(color: kSub, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: kBorder),
            Expanded(
              child: workers.isEmpty
                  ? const Center(
                      child: Text(
                        'No worker payout details found',
                        style: TextStyle(color: kSub, fontSize: 13),
                      ),
                    )
                  : ListView.separated(
                      controller: scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: workers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) =>
                          _WorkerPayoutCard(worker: workers[i], isDark: isDark),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkerPayoutCard extends StatelessWidget {
  final _PaidWorker worker;
  final bool isDark;
  const _WorkerPayoutCard({required this.worker, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final duration =
        worker.durationSeconds != null && worker.durationSeconds! > 0
        ? fmtWorkDuration(worker.durationSeconds!)
        : '—';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.grey.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? kBorder : Colors.grey.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: kAmber.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded, color: kAmber, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  worker.name,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(
                      Icons.hourglass_bottom_rounded,
                      size: 12,
                      color: kSub,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Worked $duration',
                      style: const TextStyle(color: kSub, fontSize: 11.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            CurrencyFormatter.format(worker.amount, worker.currencyCode),
            style: TextStyle(
              color: onSurface,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
