import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/services/fx_rates.dart';
import '../../../core/theme/profile_tab_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../services/wallet_currency.dart';
import '../services/wallet_requests_service.dart';
import 'widgets/wallet_page_header.dart';
import 'withdraw_details_screen.dart';

/// Quick amounts in the user's own currency.
List<int> _quickAmounts(String currencyCode) =>
    currencyCode == 'PHP' ? const [500, 1000, 2000, 5000] : const [10, 20, 50, 100];

/// Amount entry for a withdrawal (step 2 of 3, like the Top Up amount
/// screen). Checked against the admin's min / max (set in USD, converted)
/// and the user's GigCash balance; the server checks both again.
class WithdrawAmountScreen extends StatefulWidget {
  const WithdrawAmountScreen({
    super.key,
    this.role,
    required this.method,
    required this.config,
  });

  final String? role;
  final WithdrawMethod method;
  final WalletRequestConfig config;

  @override
  State<WithdrawAmountScreen> createState() => _WithdrawAmountScreenState();
}

class _WithdrawAmountScreenState extends State<WithdrawAmountScreen> {
  final _controller = TextEditingController();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  double? _balance;
  FxRates? _fx;

  String get _ccy => WalletCurrency.of(context);
  String get _symbol => CurrencyFormatter.symbol(_ccy);
  NumberFormat get _money => NumberFormat.currency(symbol: '$_symbol ', decimalDigits: 2);
  double? _mine(double? usd) => usd == null ? null : (_fx?.fromUsd(usd, _ccy) ?? usd);
  double? get _min => _mine(widget.config.withdraw.min);
  double? get _max => _mine(widget.config.withdraw.max);
  bool get _ready => _fx != null && _fx!.knows(_ccy) && _balance != null;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _sub = FirebaseFirestore.instance.collection('wallets').doc(uid).snapshots().listen(
            (s) => setState(() => _balance = ((s.data()?['balance'] as num?) ?? 0).toDouble()),
            onError: (Object e) => debugPrint('[Withdraw] balance: $e'),
          );
    } else {
      _balance = 0;
    }
    FxRates.fetch().then((fx) {
      if (mounted) setState(() => _fx = fx);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(_controller.text);

  String? get _error {
    final a = _amount;
    if (_controller.text.isEmpty || a == null) return null;
    if (a <= 0) return 'Enter an amount above 0';
    if (_balance != null && a > _balance! + 0.0001) {
      return 'You only have ${_money.format(_balance)} GigCash';
    }
    if (_min != null && a < _min!) return 'Minimum withdrawal is ${_money.format(_min)}';
    if (_max != null && a > _max!) return 'Maximum withdrawal is ${_money.format(_max)}';
    return null;
  }

  bool get _isValid => _amount != null && _amount! > 0 && _error == null && _ready;

  void _set(double value) {
    _controller.text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
  }

  void _continue() {
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WithdrawDetailsScreen(
          role: widget.role,
          method: widget.method,
          config: widget.config,
          amount: (_amount! * 100).round() / 100,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    final accent = walletAccentFor(widget.role);
    final m = widget.method;
    final limits = [
      if (_min != null) 'Min ${_money.format(_min)}',
      if (_max != null) 'Max ${_money.format(_max)}',
    ].join(' · ');
    // "Withdraw all" — the balance, capped by the max per request.
    final all = _balance == null ? null : (_max != null && _max! < _balance! ? _max! : _balance!);
    final allLabel = all == null ? null : (all == _balance ? 'All' : 'Max');

    return Scaffold(
      backgroundColor: tokens.screenBg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WalletPageHeader(
                      title: switch (m.kind) {
                        DepositKind.ewallet => 'Withdraw to ${m.method}',
                        DepositKind.office => 'Pick up cash',
                        DepositKind.remittance => 'Withdraw via remittance',
                      },
                      tokens: tokens,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: tokens.cardSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: tokens.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Amount',
                                style: TextStyle(color: tokens.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              Text(
                                _balance == null ? 'Loading balance…' : 'Available ${_money.format(_balance)}',
                                style: TextStyle(color: tokens.textMuted, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _controller,
                            autofocus: true,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d{0,6}(\.\d{0,2})?')),
                            ],
                            cursorColor: accent,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                            decoration: InputDecoration(
                              prefixText: '$_symbol ',
                              prefixStyle: TextStyle(color: tokens.textPrimary, fontSize: 30, fontWeight: FontWeight.w800),
                              hintText: '0.00',
                              hintStyle: TextStyle(color: tokens.textMuted, fontSize: 30, fontWeight: FontWeight.w800),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _error ?? (_ready ? (limits.isEmpty ? 'No minimum or maximum' : limits) : 'Loading limits…'),
                            style: TextStyle(color: _error != null ? Colors.redAccent : tokens.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    WalletSectionHeader(label: 'Quick amounts', tokens: tokens),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final v in _quickAmounts(_ccy))
                          _Chip(
                            label: '$_symbol${NumberFormat.decimalPattern().format(v)}',
                            selected: _amount == v.toDouble(),
                            accent: accent,
                            tokens: tokens,
                            onTap: () => _set(v.toDouble()),
                          ),
                        if (all != null && all > 0)
                          _Chip(
                            label: '$allLabel · ${_money.format(all)}',
                            selected: _amount == (all * 100).floor() / 100,
                            accent: accent,
                            tokens: tokens,
                            onTap: () => _set((all * 100).floor() / 100),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: accent.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, color: accent, size: 19),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              (switch (m.kind) {
                                DepositKind.ewallet =>
                                  "Next, enter the ${m.method} account Giggre should send it to.",
                                DepositKind.office =>
                                  "Next, you'll see where to pick up your cash. Bring a valid ID.",
                                DepositKind.remittance =>
                                  "Next, enter your full name as on your ID. Giggre sends you a "
                                      'control number to claim it at the center.',
                              }) +
                                  ' The amount is on hold from your Gig Wallet until Giggre pays it out.',
                              style: TextStyle(color: tokens.textSecondary, fontSize: 12.5, height: 1.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isValid ? _continue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: accent.withValues(alpha: 0.35),
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    _isValid ? 'Continue · ${_money.format(_amount)}' : 'Continue',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
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
      color: selected ? accent.withValues(alpha: 0.12) : tokens.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? accent : tokens.cardBorder, width: selected ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? accent : tokens.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
