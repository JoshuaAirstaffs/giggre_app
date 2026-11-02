import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/current_user_provider.dart';
import '../../../core/theme/profile_tab_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../services/wallet_currency.dart';
import '../services/wallet_requests_service.dart';
import 'widgets/wallet_page_header.dart';

/// Payout details + confirm for a withdrawal (step 3 of 3, like the Top Up
/// payment screen). Submitting puts the amount on hold; a Giggre admin pays
/// it out in giggre-admin → Gig Wallet → Requests and approves it with the
/// payout reference / control number, which the user is notified of.
class WithdrawDetailsScreen extends StatefulWidget {
  const WithdrawDetailsScreen({
    super.key,
    this.role,
    required this.method,
    required this.config,
    required this.amount,
    this.popCount = 3,
  });

  final String? role;
  final WithdrawMethod method;
  final WalletRequestConfig config;
  final double amount;

  /// Screens to pop after a successful submit (back to the wallet).
  final int popCount;

  @override
  State<WithdrawDetailsScreen> createState() => _WithdrawDetailsScreenState();
}

class _WithdrawDetailsScreenState extends State<WithdrawDetailsScreen> {
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _note = TextEditingController();
  final _clientRequestId = WalletRequestsService.newClientRequestId();
  bool _submitting = false;
  String? _error;

  DepositKind get _kind => widget.method.kind;
  bool get _needsDetails => _kind != DepositKind.office;

  NumberFormat get _money => NumberFormat.currency(
        symbol: CurrencyFormatter.symbol(WalletCurrency.of(context)),
        decimalDigits: 2,
      );

  @override
  void initState() {
    super.initState();
    _name.text = context.read<CurrentUserProvider>().currentName ?? '';
    _name.addListener(() => setState(() {}));
    _number.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _ready =>
      !_submitting &&
      (!_needsDetails ||
          (_name.text.trim().length >= 2 &&
              _number.text.replaceAll(RegExp(r'\D'), '').length >= 7));

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await WalletRequestsService.createWithdraw(
        amount: widget.amount,
        method: widget.method,
        clientRequestId: _clientRequestId,
        payoutName: _needsDetails ? _name.text : null,
        payoutNumber: _needsDetails ? _number.text : null,
        note: _note.text,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Withdrawal requested'),
          content: Text(switch (_kind) {
            DepositKind.ewallet =>
              '${_money.format(widget.amount)} is on hold. Giggre will send it to your '
                  "${widget.method.method} account and notify you with the reference number.",
            DepositKind.office =>
              '${_money.format(widget.amount)} is on hold for pickup at ${widget.method.method}. '
                  'Bring a valid ID when you collect it.',
            DepositKind.remittance =>
              '${_money.format(widget.amount)} is on hold. Giggre will send it by remittance and '
                  'notify you with the control number to claim it.',
          }),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      if (!mounted) return;
      var n = 0;
      Navigator.of(context).popUntil((_) => n++ >= widget.popCount);
    } on WalletRequestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    final accent = walletAccentFor(widget.role);
    final m = widget.method;
    final note = widget.config.withdrawNote.trim();

    Widget card({required Widget child}) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tokens.cardBorder),
          ),
          child: child,
        );
    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: tokens.textMuted),
          filled: true,
          fillColor: tokens.insetBg,
          counterText: '',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        );
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 2),
          child: Text(text, style: TextStyle(color: tokens.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        );
    Widget row(String k, String v, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Text(k, style: TextStyle(color: tokens.textSecondary, fontSize: 13)),
              const Spacer(),
              Flexible(
                child: Text(
                  v,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: strong ? 16 : 13.5,
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );

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
                    WalletPageHeader(title: 'Withdraw ${_money.format(widget.amount)}', tokens: tokens),
                    const SizedBox(height: 8),

                    // ── Where to receive it ──────────────────────────────
                    card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            switch (_kind) {
                              DepositKind.ewallet => 'Your ${m.method} account',
                              DepositKind.office => 'Pick up at ${m.method}',
                              DepositKind.remittance => 'Receiver details',
                            },
                            style: TextStyle(color: tokens.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          if (_kind == DepositKind.office) ...[
                            if (m.details.isNotEmpty)
                              Text(m.details, style: TextStyle(color: tokens.textSecondary, fontSize: 13, height: 1.4)),
                            const SizedBox(height: 6),
                            Text(
                              'Bring a valid ID. Giggre completes the withdrawal when you receive the cash.',
                              style: TextStyle(color: tokens.textMuted, fontSize: 12.5, height: 1.4),
                            ),
                          ] else ...[
                            label(_kind == DepositKind.remittance ? 'Full name (as on your valid ID)' : 'Account name'),
                            TextField(
                              controller: _name,
                              maxLength: 80,
                              textCapitalization: TextCapitalization.words,
                              cursorColor: accent,
                              style: TextStyle(color: tokens.textPrimary),
                              decoration: deco('Juan Dela Cruz'),
                            ),
                            const SizedBox(height: 10),
                            label(_kind == DepositKind.remittance ? 'Mobile number' : '${m.method} number'),
                            TextField(
                              controller: _number,
                              maxLength: 40,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]'))],
                              cursorColor: accent,
                              style: TextStyle(color: tokens.textPrimary, letterSpacing: 0.5),
                              decoration: deco('0917 123 4567'),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _kind == DepositKind.remittance
                                  ? 'The name must match your ID exactly, or the center can\'t release it.'
                                  : 'Double-check the number. Money sent to a wrong account may not be recoverable.',
                              style: TextStyle(color: tokens.textMuted, fontSize: 12, height: 1.35),
                            ),
                            if (m.details.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(m.details, style: TextStyle(color: tokens.textSecondary, fontSize: 12.5, height: 1.35)),
                            ],
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Summary ──────────────────────────────────────────
                    card(
                      child: Column(
                        children: [
                          row('Method', m.method),
                          row('Amount', _money.format(widget.amount), strong: true),
                          const SizedBox(height: 4),
                          Text(
                            'This amount is taken from your Gig Wallet now and held until Giggre pays '
                            'it out. If the request is rejected or you cancel it, it comes back.',
                            style: TextStyle(color: tokens.textMuted, fontSize: 12, height: 1.4),
                          ),
                          if (note.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(note, style: TextStyle(color: tokens.textSecondary, fontSize: 12.5, height: 1.4)),
                          ],
                          const SizedBox(height: 10),
                          TextField(
                            controller: _note,
                            maxLength: 200,
                            cursorColor: accent,
                            style: TextStyle(color: tokens.textPrimary, fontSize: 13.5),
                            decoration: deco('Note for Giggre (optional)'),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                    ],
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
                  onPressed: _ready ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: accent.withValues(alpha: 0.35),
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : const Text('Request withdrawal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
