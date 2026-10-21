import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

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
    required this.amount,
    required this.config,
    this.popCount = 3,
  });

  final String? role;
  final String method;
  final double amount;
  final WalletRequestConfig config;

  /// Screens to pop after a successful submit (back to the wallet).
  final int popCount;

  @override
  State<TopUpPaymentScreen> createState() => _TopUpPaymentScreenState();
}

class _TopUpPaymentScreenState extends State<TopUpPaymentScreen> {
  final _ref = TextEditingController();
  final _money = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
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
    final all = widget.config.depositAccounts;
    final same = all
        .where((a) => a.method.toLowerCase() == widget.method.toLowerCase())
        .toList();
    return same.isEmpty ? all : same;
  }

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
                          step(1, 'Send exactly ${_money.format(widget.amount)}'),
                          const SizedBox(height: 4),
                          Text(
                            'Use your ${widget.method} app to pay one of these '
                            'Giggre accounts:',
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_accounts.isEmpty)
                            Text(
                              'No payment accounts are set up yet. Please try '
                              'again later.',
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
                                          '${a.method} · ${a.accountName}',
                                          style: TextStyle(
                                            color: tokens.textSecondary,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          a.accountNumber,
                                          style: TextStyle(
                                            color: tokens.textPrimary,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
                          step(2, 'Enter the reference number'),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _ref,
                            maxLength: 60,
                            textCapitalization: TextCapitalization.characters,
                            cursorColor: accent,
                            style: TextStyle(color: tokens.textPrimary),
                            decoration: InputDecoration(
                              hintText: 'e.g. 1234 567 890123',
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
                            'Find it on the receipt in your ${widget.method} app.',
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Screenshot of the receipt (optional)',
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
                              label: const Text('Add screenshot'),
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
