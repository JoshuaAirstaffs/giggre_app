import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/profile_tab_theme.dart';
import '../../../../core/utils/currency_formatter.dart';

/// One entry from wallets/{uid}/transactions (written only by
/// postLedgerEntry in functions/src/wallet.ts).
class WalletTx {
  const WalletTx({
    required this.id,
    required this.amount,
    required this.type,
    required this.title,
    required this.status,
    required this.currencyCode,
    required this.createdAt,
    required this.balanceAfter,
  });

  final String id;

  /// Signed: + money in, − money out.
  final double amount;
  final String type;
  final String title;
  final String status;
  final String? currencyCode;
  final DateTime? createdAt;
  final double? balanceAfter;

  bool get isIn => amount >= 0;

  factory WalletTx.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return WalletTx(
      id: doc.id,
      amount: (d['amount'] as num?)?.toDouble() ?? 0,
      type: d['type'] as String? ?? '',
      title: d['title'] as String? ?? 'Transaction',
      status: d['status'] as String? ?? 'completed',
      currencyCode: d['currencyCode'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      balanceAfter: (d['balanceAfter'] as num?)?.toDouble(),
    );
  }

  String formatAmount(String fallbackCurrency, {bool signed = true}) {
    final money = formatMoney(amount.abs(), currencyCode ?? fallbackCurrency);
    return signed ? '${isIn ? '+' : '−'} $money' : money;
  }
}

String formatMoney(double value, String currencyCode) => NumberFormat.currency(
  symbol: '${CurrencyFormatter.symbol(currencyCode)} ',
  decimalDigits: 2,
).format(value);

const kWalletIn = Color(0xFF2BB673);
const kWalletOut = Colors.redAccent;

Color walletTxColor(WalletTx tx) => tx.isIn ? kWalletIn : kWalletOut;

IconData walletTxIcon(String type) => switch (type) {
  'top_up' => Icons.add_card_rounded,
  'transfer' => Icons.swap_horiz_rounded,
  'send' => Icons.north_east_rounded,
  'receive' => Icons.south_west_rounded,
  'withdraw' => Icons.account_balance_rounded,
  'earning' => Icons.work_outline_rounded,
  'gig_payment' => Icons.handshake_outlined,
  'refund' => Icons.replay_rounded,
  'fee' => Icons.percent_rounded,
  'adjustment' => Icons.tune_rounded,
  _ => Icons.receipt_long_rounded,
};

String walletTxTypeLabel(String type) => switch (type) {
  'top_up' => 'Top Up',
  'transfer' => 'Transfer',
  'send' => 'Sent',
  'receive' => 'Received',
  'withdraw' => 'Withdrawal',
  'earning' => 'Gig Earning',
  'gig_payment' => 'Gig Payment',
  'refund' => 'Refund',
  'fee' => 'Fee',
  'adjustment' => 'Adjustment',
  _ => 'Transaction',
};

String walletTxStatusLabel(String status) =>
    status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1);

Color walletTxStatusColor(String status) => switch (status) {
  'completed' => kWalletIn,
  'pending' => const Color(0xFFF0A830),
  'failed' => kWalletOut,
  _ => Colors.grey,
};

/// A tappable history row: type icon, title, date (+ status if not
/// completed), and the signed amount in green/red.
class WalletTransactionRow extends StatelessWidget {
  const WalletTransactionRow({
    super.key,
    required this.tx,
    required this.fallbackCurrency,
    required this.tokens,
    this.onTap,
  });

  final WalletTx tx;
  final String fallbackCurrency;
  final ProfileTabTokens tokens;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = walletTxColor(tx);
    final subtitle = [
      if (tx.createdAt != null)
        DateFormat('MMM d, yyyy · h:mm a').format(tx.createdAt!),
      if (tx.status != 'completed') walletTxStatusLabel(tx.status),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(walletTxIcon(tx.type), size: 19, color: color),
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
                      color: tokens.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: tokens.textMuted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              tx.formatAmount(fallbackCurrency),
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered icon + message for empty / error states.
class WalletHistoryMessage extends StatelessWidget {
  const WalletHistoryMessage({
    super.key,
    required this.icon,
    required this.text,
    required this.tokens,
  });

  final IconData icon;
  final String text;
  final ProfileTabTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 36, color: tokens.textMuted),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
