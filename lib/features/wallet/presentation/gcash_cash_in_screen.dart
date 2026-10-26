import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/profile_tab_theme.dart';
import '../services/wallet_requests_service.dart';
import 'top_up_payment_screen.dart';
import 'widgets/wallet_page_header.dart';

// Fallbacks only; the real limits come from general_config/wallet_requests
// (giggre-admin → Gig Wallet → Settings) and are enforced on the server.
const double _kMinCashIn = 100;
const double _kMaxCashIn = 10000;
const List<int> _kQuickAmounts = [100, 500, 1000, 5000];

/// Amount entry for a GCash cash-in.
///
/// While online payment (PayMongo) is postponed, Continue opens the manual
/// top up: the user pays Giggre's GCash account and submits the reference
/// number for an admin to confirm (TopUpPaymentScreen). The balance is only
/// ever credited server-side.
class GcashCashInScreen extends StatefulWidget {
  const GcashCashInScreen({
    super.key,
    this.role,
    this.method = 'GCash',
    this.kind = DepositKind.ewallet,
    this.config,
  });

  final String? role;

  /// The admin's label for the method, e.g. "GCash" or "Cash at office".
  final String method;
  final DepositKind kind;
  final WalletRequestConfig? config;

  @override
  State<GcashCashInScreen> createState() => _GcashCashInScreenState();
}

class _GcashCashInScreenState extends State<GcashCashInScreen> {
  final _controller = TextEditingController();
  final _money = NumberFormat.currency(symbol: '₱ ', decimalDigits: 2);
  WalletRequestConfig? _config;

  double get _min => _config?.deposit.min ?? _kMinCashIn;
  double get _max => _config?.deposit.max ?? _kMaxCashIn;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _config = widget.config;
    if (_config == null) {
      WalletRequestsService.fetchConfig().then((c) {
        if (mounted) setState(() => _config = c);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(_controller.text);

  String? get _error {
    final a = _amount;
    if (_controller.text.isEmpty || a == null) return null;
    if (a < _min) {
      return 'Minimum cash-in is ${_money.format(_min)}';
    }
    if (a > _max) {
      return 'Maximum cash-in is ${_money.format(_max)}';
    }
    return null;
  }

  bool get _isValid => _amount != null && _error == null;

  void _setQuick(int value) {
    _controller.text = value.toString();
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  void _continue() {
    FocusScope.of(context).unfocus();
    final config = _config;
    if (config == null || !config.canTopUp) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Top up isn't available right now.")),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TopUpPaymentScreen(
          role: widget.role,
          method: widget.method,
          kind: widget.kind,
          amount: (_amount! * 100).round() / 100,
          config: config,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    final accent = walletAccentFor(widget.role);

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
                      title: switch (widget.kind) {
                        DepositKind.ewallet => 'Cash in via ${widget.method}',
                        DepositKind.office => 'Pay cash at the office',
                        DepositKind.remittance => 'Send via remittance',
                      },
                      tokens: tokens,
                    ),
                    const SizedBox(height: 4),

                    // ── Amount card ──────────────────────────────────────
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
                          Text(
                            'Amount',
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _controller,
                            autofocus: true,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              // digits with up to 2 decimal places
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d{0,6}(\.\d{0,2})?'),
                              ),
                            ],
                            cursorColor: accent,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                            decoration: InputDecoration(
                              prefixText: '₱ ',
                              prefixStyle: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                              ),
                              hintText: '0.00',
                              hintStyle: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _error ??
                                'Min ${_money.format(_min)} · '
                                    'Max ${_money.format(_max)}',
                            style: TextStyle(
                              color: _error != null
                                  ? Colors.redAccent
                                  : tokens.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Quick amounts ────────────────────────────────────
                    WalletSectionHeader(label: 'Quick amounts', tokens: tokens),
                    const SizedBox(height: 10),
                    GridView.count(
                      crossAxisCount: _kQuickAmounts.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.9,
                      children: [
                        for (final v in _kQuickAmounts)
                          _QuickAmountChip(
                            label: NumberFormat.decimalPattern().format(v),
                            selected: _amount == v.toDouble(),
                            accent: accent,
                            tokens: tokens,
                            onTap: () => _setQuick(v),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── How it works ─────────────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: accent,
                            size: 19,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              (switch (widget.kind) {
                                DepositKind.ewallet =>
                                  "Next, you'll see Giggre's ${widget.method} "
                                      'account. Send the amount from your '
                                      '${widget.method} app, then enter the '
                                      'reference number.',
                                DepositKind.office =>
                                  "Next, you'll see the office address and "
                                      'hours. Pay the amount in cash there and '
                                      'enter the official receipt number.',
                                DepositKind.remittance =>
                                  "Next, you'll see who to send it to. Send "
                                      'the amount at any remittance center, '
                                      'then enter the control number. You pay '
                                      "the center's fee.",
                              }) +
                                  ' Your Gig Wallet is updated once Giggre '
                                      'confirms it.',
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontSize: 12.5,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Continue button (pinned to bottom) ───────────────────────
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _isValid
                        ? 'Continue · ${_money.format(_amount)}'
                        : 'Continue',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
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

class _QuickAmountChip extends StatelessWidget {
  const _QuickAmountChip({
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
        side: BorderSide(
          color: selected ? accent : tokens.cardBorder,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Text(
            '₱$label',
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
