import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/current_user_provider.dart';
import '../../../core/utils/currency_formatter.dart';

import '../../../core/theme/profile_tab_theme.dart';
import '../services/wallet_requests_service.dart';
import 'widgets/wallet_page_header.dart';

/// Manual top up while online payment is postponed: the user pays one of
/// Giggre's accounts outside the app, then submits the reference number
/// (and optionally a screenshot). A Giggre admin confirms it in
/// giggre-admin → Gig Wallet → Requests before the GigCash is added.
class TopUpPaymentScreen extends StatefulWidget {
  const TopUpPaymentScreen({
    super.key,
    this.role,
    required this.method,
    this.kind = DepositKind.ewallet,
    required this.amount,
    required this.config,
    this.popCount = 3,
  });

  final String? role;
  final String method;
  final DepositKind kind;
  final double amount;
  final WalletRequestConfig config;

  /// Screens to pop after a successful submit (back to the wallet).
  final int popCount;

  @override
  State<TopUpPaymentScreen> createState() => _TopUpPaymentScreenState();
}

class _TopUpPaymentScreenState extends State<TopUpPaymentScreen> {
  final _ref = TextEditingController();
  /// The user's currency symbol: $ by default, ₱ for users located in the
  /// Philippines (CurrentUserProvider / CurrencyFormatter).
  String get _symbol => CurrencyFormatter.symbol(
    context.read<CurrentUserProvider>().currencyCode,
  );
  NumberFormat get _money =>
      NumberFormat.currency(symbol: _symbol, decimalDigits: 2);
  final _clientRequestId = WalletRequestsService.newClientRequestId();
  File? _proof;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ref.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  List<DepositAccount> get _accounts {
    final ofKind = widget.config.accountsOf(widget.kind);
    if (widget.kind != DepositKind.ewallet) return ofKind;
    final same = widget.config.accountsOf(widget.kind, method: widget.method);
    return same.isEmpty ? ofKind : same;
  }

  bool get _isEwallet => widget.kind == DepositKind.ewallet;

  bool get _ready => _ref.text.trim().length >= 4 && !_submitting;

  Future<void> _pickProof() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1600,
    );
    if (x != null && mounted) setState(() => _proof = File(x.path));
  }

  Future<void> _submit() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      String? path, url;
      if (_proof != null) {
        (path, url) = await WalletRequestsService.uploadProof(
          uid: uid,
          clientRequestId: _clientRequestId,
          file: _proof!,
        );
      }
      await WalletRequestsService.createTopUp(
        amount: widget.amount,
        method: widget.method,
        kind: widget.kind,
        reference: _ref.text.trim(),
        clientRequestId: _clientRequestId,
        proofPath: path,
        proofUrl: url,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Top up submitted'),
          content: Text(
            'Giggre will check your payment of ${_money.format(widget.amount)} '
            "and add it to your Gig Wallet. We'll notify you once it's done.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      var n = 0;
      Navigator.of(context).popUntil((_) => n++ >= widget.popCount);
    } on WalletRequestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('[TopUp] $e');
      if (mounted) {
        setState(() => _error = "Couldn't upload the screenshot. Try again.");
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    final accent = walletAccentFor(widget.role);
    final note = widget.config.depositNote.trim();

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
    Widget step(int n, String text) => Row(
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: accent,
          child: Text(
            '$n',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
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
                    WalletPageHeader(
                      title: 'Pay ${_money.format(widget.amount)}',
                      tokens: tokens,
                    ),
                    const SizedBox(height: 8),
                    card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          step(1, switch (widget.kind) {
                            DepositKind.ewallet => 'Send exactly ${_money.format(widget.amount)}',
                            DepositKind.office => 'Pay ${_money.format(widget.amount)} in cash',
                            DepositKind.remittance => 'Send ${_money.format(widget.amount)} by remittance',
                          }),
                          const SizedBox(height: 4),
                          Text(
                            switch (widget.kind) {
                              DepositKind.ewallet =>
                                'Use your ${widget.method} app to pay one of '
                                    'these Giggre accounts:',
                              DepositKind.office =>
                                'Go to one of these offices and pay the cashier. '
                                    'Ask for an official receipt.',
                              DepositKind.remittance =>
                                'At any remittance center, send the amount to '
                                    'this receiver. The center charges you its '
                                    'own fee on top.',
                            },
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_accounts.isEmpty)
                            Text(
                              'This top-up method is not set up yet. Please '
                              'try another one.',
                              style: TextStyle(color: tokens.textMuted),
                            ),
                          for (final a in _accounts)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          switch (widget.kind) {
                                            DepositKind.ewallet => '${a.method} · ${a.accountName}',
                                            DepositKind.office => a.accountName,
                                            DepositKind.remittance => 'Receiver: ${a.accountName}',
                                          },
                                          style: TextStyle(
                                            color: _isEwallet
                                                ? tokens.textSecondary
                                                : tokens.textPrimary,
                                            fontSize: _isEwallet ? 12.5 : 14.5,
                                            fontWeight: _isEwallet
                                                ? FontWeight.w400
                                                : FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          widget.kind == DepositKind.remittance
                                              ? 'Mobile: ${a.accountNumber}'
                                              : a.accountNumber,
                                          style: TextStyle(
                                            color: tokens.textPrimary,
                                            fontSize: _isEwallet ? 17 : 13.5,
                                            fontWeight: _isEwallet
                                                ? FontWeight.w800
                                                : FontWeight.w500,
                                            letterSpacing: _isEwallet ? 0.5 : 0,
                                          ),
                                        ),
                                        if (a.details.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            a.details,
                                            style: TextStyle(
                                              color: tokens.textSecondary,
                                              fontSize: 12.5,
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (widget.kind != DepositKind.office)
                                  IconButton(
                                    tooltip: 'Copy number',
                                    icon: Icon(Icons.copy_rounded,
                                        color: accent, size: 20),
                                    onPressed: () {
                                      Clipboard.setData(
                                        ClipboardData(text: a.accountNumber),
                                      );
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Account number copied'),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          if (note.isNotEmpty)
                            Text(
                              note,
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          step(2, 'Enter the ${widget.kind.referenceLabel}'),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _ref,
                            maxLength: 60,
                            textCapitalization: TextCapitalization.characters,
                            cursorColor: accent,
                            style: TextStyle(color: tokens.textPrimary),
                            decoration: InputDecoration(
                              hintText: switch (widget.kind) {
                                DepositKind.ewallet => 'e.g. 1234 567 890123',
                                DepositKind.office => 'e.g. OR 004512',
                                DepositKind.remittance => 'e.g. 1234-5678-9012',
                              },
                              hintStyle: TextStyle(color: tokens.textMuted),
                              filled: true,
                              fillColor: tokens.insetBg,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            switch (widget.kind) {
                              DepositKind.ewallet =>
                                'Find it on the receipt in your ${widget.method} app.',
                              DepositKind.office =>
                                "It's printed on the official receipt the cashier gives you.",
                              DepositKind.remittance =>
                                "It's on the remittance slip (also called KPTN, "
                                    'reference or tracking number).',
                            },
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _isEwallet
                                ? 'Screenshot of the receipt (optional)'
                                : 'Photo of the receipt / slip (optional)',
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_proof == null)
                            OutlinedButton.icon(
                              onPressed: _submitting ? null : _pickProof,
                              icon: const Icon(Icons.add_photo_alternate_outlined),
                              label: Text(_isEwallet ? 'Add screenshot' : 'Add photo'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: accent,
                                side: BorderSide(color: accent),
                              ),
                            )
                          else
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    _proof!,
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                TextButton(
                                  onPressed: _submitting
                                      ? null
                                      : () => setState(() => _proof = null),
                                  child: const Text('Remove'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                        ),
                      ),
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
                  onPressed: _ready && _accounts.isNotEmpty ? _submit : null,
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
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          "I've paid — submit for review",
                          style: TextStyle(
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
