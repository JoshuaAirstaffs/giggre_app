import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  PaymentSelectionSheet — host selects how the worker will be paid
//  before marking the gig completed.
//
//  Options:
//    • Stripe            → Coming soon (disabled)
//    • Maya / GCash      → Coming soon (disabled)
//    • Cash              → Active; shows a confirm dialog then calls onConfirm
// ─────────────────────────────────────────────────────────────────────────────
class PaymentSelectionSheet extends StatefulWidget {
  final String gigTitle;
  final double budget;
  final Future<void> Function(String paymentMethod) onConfirm;

  const PaymentSelectionSheet({
    super.key,
    required this.gigTitle,
    required this.budget,
    required this.onConfirm,
  });

  static Future<void> show({
    required BuildContext context,
    required String gigTitle,
    required double budget,
    required Future<void> Function(String paymentMethod) onConfirm,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaymentSelectionSheet(
        gigTitle: gigTitle,
        budget: budget,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<PaymentSelectionSheet> createState() => _PaymentSelectionSheetState();
}

class _PaymentSelectionSheetState extends State<PaymentSelectionSheet> {
  bool _processing = false;

  Future<void> _confirmCash() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        const green = Color(0xFF22C55E);
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        final cardColor = Theme.of(ctx).cardColor;
        return AlertDialog(
          backgroundColor: cardColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          contentPadding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.payments_rounded, color: green, size: 26),
              ),
              const SizedBox(height: 14),
              Text('Confirm Cash Payment',
                  style: TextStyle(
                      color: onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text(
                'Please confirm you have received the cash payment from the gig worker and the gig is complete.',
                style: TextStyle(color: kSub, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: green.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.payments_rounded,
                        color: green, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '₱${widget.budget.toStringAsFixed(0)}',
                      style: const TextStyle(
                          color: green,
                          fontSize: 17,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    const Text('Cash',
                        style: TextStyle(color: kSub, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: kSub.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(color: kSub)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('Confirm',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;
    setState(() => _processing = true);
    try {
      await widget.onConfirm('cash');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF22C55E);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A2236) : Colors.white;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final divider = Theme.of(context).dividerColor;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ─────────────────────────────────────────────────
          const SizedBox(height: 14),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 20),

          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kAmber.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.payment_rounded,
                      color: kAmber, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Select Payment Method',
                          style: TextStyle(
                              color: onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(widget.gigTitle,
                          style:
                              const TextStyle(color: kSub, fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: kAmber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: kAmber.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '₱${widget.budget.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: kAmber,
                        fontSize: 14,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),
          Divider(height: 0, color: divider),
          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PAYMENT OPTIONS',
                    style: TextStyle(
                        color: onSurface.withValues(alpha: 0.4),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
                const SizedBox(height: 12),

                // ── Stripe — coming soon ─────────────────────────────────
                _PaymentTile(
                  icon: Icons.credit_card_rounded,
                  iconColor: const Color(0xFF6366F1),
                  title: 'Stripe',
                  subtitle: 'Credit / Debit Card',
                  comingSoon: true,
                  isDark: isDark,
                ),
                const SizedBox(height: 10),

                // ── Maya / GCash — coming soon ───────────────────────────
                _PaymentTile(
                  icon: Icons.account_balance_wallet_rounded,
                  iconColor: const Color(0xFF0EA5E9),
                  title: 'Maya / GCash',
                  subtitle: 'Mobile Wallet',
                  comingSoon: true,
                  isDark: isDark,
                ),
                const SizedBox(height: 10),

                // ── Cash — active ────────────────────────────────────────
                _PaymentTile(
                  icon: Icons.payments_rounded,
                  iconColor: green,
                  title: 'Cash',
                  subtitle: 'Pay in person',
                  comingSoon: false,
                  processing: _processing,
                  isDark: isDark,
                  onTap: _processing ? null : _confirmCash,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed:
                    _processing ? null : () => Navigator.pop(context),
                child: const Text('Cancel',
                    style: TextStyle(color: kSub, fontSize: 14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Single payment option tile
// ─────────────────────────────────────────────────────────────────────────────
class _PaymentTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool comingSoon;
  final bool isDark;
  final bool processing;
  final VoidCallback? onTap;

  const _PaymentTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.comingSoon,
    required this.isDark,
    this.processing = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = comingSoon || onTap == null;
    final bg = isDark
        ? Colors.white.withValues(alpha: disabled ? 0.04 : 0.07)
        : Colors.grey.withValues(alpha: disabled ? 0.05 : 0.09);
    final border = disabled
        ? (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.grey.withValues(alpha: 0.15))
        : iconColor.withValues(alpha: 0.45);
    final iconAlpha = disabled ? 0.35 : 1.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: border, width: disabled ? 1.0 : 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: disabled ? 0.07 : 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: iconColor.withValues(alpha: iconAlpha),
                  size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: disabled
                              ? kSub
                              : Theme.of(context).colorScheme.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          const TextStyle(color: kSub, fontSize: 11)),
                ],
              ),
            ),
            if (processing)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: iconColor, strokeWidth: 2.5),
              )
            else if (comingSoon)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kSub.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Coming Soon',
                    style: TextStyle(
                        color: kSub,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3)),
              )
            else
              Icon(Icons.chevron_right_rounded,
                  color: iconColor.withValues(alpha: 0.7), size: 20),
          ],
        ),
      ),
    );
  }
}