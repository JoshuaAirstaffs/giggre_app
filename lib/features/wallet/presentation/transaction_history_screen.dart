import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/current_user_provider.dart';
import '../../../core/theme/profile_tab_theme.dart';
import 'transaction_details_screen.dart';
import 'widgets/wallet_page_header.dart';
import 'widgets/wallet_transaction.dart';

enum _Filter { all, moneyIn, moneyOut }

/// "See all" — every GigCash transaction, newest first, with
/// All / Money in / Money out filters.
///
/// Filtering is done in the app on the latest [_kLimit] entries so no extra
/// Firestore index is needed. Add pagination when users have more than that.
class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key, required this.uid, this.role});

  final String uid;
  final String? role;

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

const int _kLimit = 200;

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  _Filter _filter = _Filter.all;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      FirebaseFirestore.instance
          .collection('wallets')
          .doc(widget.uid)
          .collection('transactions')
          .orderBy('createdAt', descending: true)
          .limit(_kLimit)
          .snapshots();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    final accent = walletAccentFor(widget.role);
    final userCurrency = context.watch<CurrentUserProvider>().currencyCode;

    return Scaffold(
      backgroundColor: tokens.screenBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: WalletPageHeader(
                title: 'All Transactions',
                tokens: tokens,
              ),
            ),
            // ── Filters ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  for (final f in _Filter.values) ...[
                    _FilterChip(
                      label: switch (f) {
                        _Filter.all => 'All',
                        _Filter.moneyIn => 'Money in',
                        _Filter.moneyOut => 'Money out',
                      },
                      selected: _filter == f,
                      accent: accent,
                      tokens: tokens,
                      onTap: () => setState(() => _filter = f),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _stream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    debugPrint('[Wallet] all-history error: ${snap.error}');
                    return WalletHistoryMessage(
                      icon: Icons.error_outline_rounded,
                      text: "Couldn't load transactions.",
                      tokens: tokens,
                    );
                  }
                  if (!snap.hasData) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: accent,
                        strokeWidth: 2,
                      ),
                    );
                  }
                  final txs = snap.data!.docs
                      .map(WalletTx.fromDoc)
                      .where(
                        (t) => switch (_filter) {
                          _Filter.all => true,
                          _Filter.moneyIn => t.isIn,
                          _Filter.moneyOut => !t.isIn,
                        },
                      )
                      .toList();

                  if (txs.isEmpty) {
                    return WalletHistoryMessage(
                      icon: Icons.receipt_long_rounded,
                      text: _filter == _Filter.all
                          ? 'No transactions yet.'
                          : 'Nothing here for this filter.',
                      tokens: tokens,
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    itemCount: txs.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: tokens.divider),
                    itemBuilder: (context, i) => WalletTransactionRow(
                      tx: txs[i],
                      fallbackCurrency: userCurrency,
                      tokens: tokens,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TransactionDetailsScreen(
                            tx: txs[i],
                            fallbackCurrency: userCurrency,
                            role: widget.role,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final ProfileTabTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent : tokens.cardSurface,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? accent : tokens.cardBorder),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : tokens.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
