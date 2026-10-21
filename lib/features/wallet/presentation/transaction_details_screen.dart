import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/profile_tab_theme.dart';
import 'widgets/wallet_page_header.dart';
import 'widgets/wallet_transaction.dart';

/// Full details of one GigCash transaction.
class TransactionDetailsScreen extends StatelessWidget {
  const TransactionDetailsScreen({
    super.key,
    required this.tx,
    required this.fallbackCurrency,
    this.role,
  });

  final WalletTx tx;
  final String fallbackCurrency;
  final String? role;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    final accent = walletAccentFor(role);
    final color = walletTxColor(tx);
    final statusColor = walletTxStatusColor(tx.status);

    return Scaffold(
      backgroundColor: tokens.screenBg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WalletPageHeader(title: 'Transaction Details', tokens: tokens),
              const SizedBox(height: 4),

              // ── Summary card ───────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                decoration: BoxDecoration(
                  color: tokens.cardSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: tokens.cardBorder),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(walletTxIcon(tx.type), color: color, size: 28),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tx.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        tx.formatAmount(fallbackCurrency),
                        style: TextStyle(
                          color: color,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        walletTxStatusLabel(tx.status),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Details ────────────────────────────────────────────────
              WalletSectionHeader(label: 'Details', tokens: tokens),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: tokens.cardSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: tokens.cardBorder),
                ),
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'Type',
                      value: walletTxTypeLabel(tx.type),
                      tokens: tokens,
                    ),
                    _divider(tokens),
                    _DetailRow(
                      label: 'Date & time',
                      value: tx.createdAt == null
                          ? '—'
                          : DateFormat(
                              'MMM d, yyyy · h:mm a',
                            ).format(tx.createdAt!),
                      tokens: tokens,
                    ),
                    _divider(tokens),
                    _DetailRow(
                      label: 'Amount',
                      value: tx.formatAmount(fallbackCurrency, signed: false),
                      tokens: tokens,
                    ),
                    if (tx.balanceAfter != null) ...[
                      _divider(tokens),
                      _DetailRow(
                        label: 'GigCash after',
                        value: formatMoney(
                          tx.balanceAfter!,
                          tx.currencyCode ?? fallbackCurrency,
                        ),
                        tokens: tokens,
                      ),
                    ],
                    _divider(tokens),
                    _DetailRow(
                      label: 'Reference no.',
                      value: tx.id,
                      tokens: tokens,
                      trailing: IconButton(
                        tooltip: 'Copy reference',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.copy_rounded,
                          size: 18,
                          color: accent,
                        ),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: tx.id));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Reference number copied.'),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Help ───────────────────────────────────────────────────
              Text(
                'Something wrong with this transaction? Contact support and '
                'include the reference number.',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _divider(ProfileTabTokens tokens) =>
      Divider(height: 1, thickness: 1, color: tokens.divider);
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.tokens,
    this.trailing,
  });

  final String label;
  final String value;
  final ProfileTabTokens tokens;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: trailing == null ? 14 : 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: tokens.textSecondary, fontSize: 13.5),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
