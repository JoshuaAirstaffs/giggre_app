import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/app_colors.dart';

class PaymentHistorySheet extends StatelessWidget {
  final List<Map<String, dynamic>> gigs;

  const PaymentHistorySheet({super.key, required this.gigs});

  static Future<void> show({
    required BuildContext context,
    required List<Map<String, dynamic>> completedGigs,
  }) {
    final sorted = [...completedGigs]..sort((a, b) {
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

  double get _totalSpent =>
      gigs.fold(0.0, (acc, g) => acc + ((g['budget'] as num?)?.toDouble() ?? 0));

  Map<String, double> get _byMethod {
    final map = <String, double>{};
    for (final g in gigs) {
      final method = (g['paymentMethod'] as String? ?? 'cash');
      map[method] = (map[method] ?? 0) + ((g['budget'] as num?)?.toDouble() ?? 0);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    const green = Color(0xFF10B981);

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
                    child: const Icon(Icons.receipt_long_outlined,
                        color: green, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Payment History',
                          style: TextStyle(
                              color: onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Text('${gigs.length} transaction${gigs.length == 1 ? '' : 's'}',
                          style: const TextStyle(color: kSub, fontSize: 12)),
                    ],
                  ),
                  const Spacer(),
                  if (gigs.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('₱${_totalSpent.toStringAsFixed(0)}',
                            style: TextStyle(
                                color: onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        const Text('total spent',
                            style: TextStyle(color: kSub, fontSize: 10)),
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
                    final cfg = _methodConfig(e.key);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: cfg.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: cfg.color.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(cfg.icon, color: cfg.color, size: 12),
                            const SizedBox(width: 4),
                            Text(cfg.label,
                                style: TextStyle(
                                    color: cfg.color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 4),
                            Text('₱${e.value.toStringAsFixed(0)}',
                                style: TextStyle(
                                    color: cfg.color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
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
                      Icon(Icons.receipt_long_outlined,
                          color: kSub.withValues(alpha: 0.35), size: 52),
                      const SizedBox(height: 12),
                      const Text('No payments yet',
                          style: TextStyle(color: kSub, fontSize: 14)),
                      const SizedBox(height: 4),
                      const Text('Completed gigs will appear here',
                          style: TextStyle(color: kSub, fontSize: 12)),
                    ],
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
                  itemBuilder: (ctx, i) =>
                      _PaymentCard(gig: gigs[i], isDark: isDark),
                ),
              ),
          ],
        ),
      ),
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
}

class _MethodConfig {
  final IconData icon;
  final Color color;
  final String label;
  const _MethodConfig(
      {required this.icon, required this.color, required this.label});
}

// ─────────────────────────────────────────────────────────────────────────────
//  Individual payment entry card
// ─────────────────────────────────────────────────────────────────────────────
class _PaymentCard extends StatelessWidget {
  final Map<String, dynamic> gig;
  final bool isDark;

  const _PaymentCard({required this.gig, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final title = gig['title'] as String? ?? 'Gig';
    final budget = (gig['budget'] as num?)?.toDouble() ?? 0;
    final paymentMethod = gig['paymentMethod'] as String? ?? 'cash';
    final workerName = gig['assignedWorkerName'] as String? ??
        gig['workerName'] as String? ?? '';
    final completedAt = gig['completedAt'] as Timestamp?;
    final gigType = gig['gigType'] as String? ?? 'quick';

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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.grey.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color:
                isDark ? kBorder : Colors.grey.withValues(alpha: 0.18)),
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
                      child: Text(title,
                          style: TextStyle(
                              color: onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
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
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: cfg.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(cfg.label,
                          style: TextStyle(
                              color: cfg.color,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (workerName.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.person_outline_rounded,
                          size: 11, color: kSub),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(workerName,
                            style: const TextStyle(
                                color: kSub, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ],
                ),
                if (completedAt != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 11, color: kSub),
                      const SizedBox(width: 3),
                      Text(_fmtDate(completedAt),
                          style: const TextStyle(
                              color: kSub, fontSize: 11)),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // ── Amount ────────────────────────────────────────────────
          const SizedBox(width: 12),
          Text('₱${budget.toStringAsFixed(0)}',
              style: TextStyle(
                  color: onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  static String _fmtDate(Timestamp ts) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dt = ts.toDate().toLocal();
    return '${months[dt.month]} ${dt.day}, ${dt.year}';
  }
}