import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/profile_tab_theme.dart';
import '../services/wallet_requests_service.dart';
import 'widgets/wallet_page_header.dart';

/// Amount + confirm for Send. The request goes to a Giggre admin; the
/// amount is taken from the sender's wallet right away (on hold) and is
/// refunded if the admin rejects it or the sender cancels.
class SendAmountScreen extends StatefulWidget {
  const SendAmountScreen({
    super.key,
    this.role,
    required this.recipient,
    required this.config,
  });

  final String? role;
  final WalletRecipient recipient;
  final WalletRequestConfig config;

  @override
  State<SendAmountScreen> createState() => _SendAmountScreenState();
}

class _SendAmountScreenState extends State<SendAmountScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _money = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final _clientRequestId = WalletRequestsService.newClientRequestId();
  late final Stream<double> _balance;
  double? _bal;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _balance = uid == null
        ? Stream.value(0)
        : FirebaseFirestore.instance
              .collection('wallets')
              .doc(uid)
              .snapshots()
              .map((s) => ((s.data()?['balance'] as num?) ?? 0).toDouble());
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  WalletAmountLimits get _lim => widget.config.transfer;
  double? get _value {
    final v = double.tryParse(_amount.text);
    return v == null || v <= 0 ? null : (v * 100).round() / 100;
  }

  String? get _fieldError {
    final v = _value;
    if (_amount.text.isEmpty || v == null) return null;
    if (_lim.min != null && v < _lim.min!) return 'Minimum is ${_money.format(_lim.min)}';
    if (_lim.max != null && v > _lim.max!) return 'Maximum is ${_money.format(_lim.max)}';
    if (_lim.dailyMax != null && v > _lim.dailyMax!) {
      return 'The daily limit is ${_money.format(_lim.dailyMax)}';
    }
    if (_bal != null && v > _bal!) return 'Your GigCash is ${_money.format(_bal)}';
    return null;
  }

  bool get _ready => _value != null && _fieldError == null && !_submitting;

  Future<void> _confirmAndSend() async {
    FocusScope.of(context).unfocus();
    final v = _value!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send ${_money.format(v)}?'),
        content: Text(
          'To ${widget.recipient.name}'
          '${widget.recipient.code == null ? '' : ' (${widget.recipient.code})'}.\n\n'
          'A Giggre admin reviews every send. ${_money.format(v)} is taken '
          'from your wallet now and refunded if it is rejected or you cancel it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await WalletRequestsService.createSend(
        amount: v,
        recipientId: widget.recipient.id,
        clientRequestId: _clientRequestId,
        note: _note.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sending ${_money.format(v)} to ${widget.recipient.name} is '
            "waiting for review. We'll notify you.",
          ),
        ),
      );
      var n = 0;
      Navigator.of(context).popUntil((_) => n++ >= 2);
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
    final r = widget.recipient;

    return Scaffold(
      backgroundColor: tokens.screenBg,
      body: SafeArea(
        child: StreamBuilder<double>(
          stream: _balance,
          builder: (context, snap) {
            _bal = snap.data;
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        WalletPageHeader(title: 'Send GigCash', tokens: tokens),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: tokens.cardSurface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: tokens.cardBorder),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: accent.withValues(alpha: 0.15),
                                backgroundImage:
                                    r.photoUrl == null ? null : NetworkImage(r.photoUrl!),
                                child: r.photoUrl == null
                                    ? Text(
                                        r.name.isEmpty ? '?' : r.name[0],
                                        style: TextStyle(
                                          color: accent,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.name,
                                      style: TextStyle(
                                        color: tokens.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (r.code != null)
                                      Text(
                                        r.code!,
                                        style: TextStyle(
                                          color: tokens.textMuted,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
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
                              TextField(
                                controller: _amount,
                                autofocus: true,
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d{0,6}(\.\d{0,2})?'),
                                  ),
                                ],
                                cursorColor: accent,
                                style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
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
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _fieldError ??
                                    [
                                      'Available ${_bal == null ? '–' : _money.format(_bal)}',
                                      if (_lim.min != null) 'Min ${_money.format(_lim.min)}',
                                      if (_lim.max != null) 'Max ${_money.format(_lim.max)}',
                                    ].join(' · '),
                                style: TextStyle(
                                  color: _fieldError != null
                                      ? Colors.redAccent
                                      : tokens.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _note,
                          maxLength: 200,
                          cursorColor: accent,
                          style: TextStyle(color: tokens.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Message (optional)',
                            hintStyle: TextStyle(color: tokens.textMuted),
                            filled: true,
                            fillColor: tokens.cardSurface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: tokens.cardBorder),
                            ),
                          ),
                        ),
                        if (_error != null)
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
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
                      onPressed: _ready ? _confirmAndSend : null,
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
                          : Text(
                              _value == null || _fieldError != null
                                  ? 'Send'
                                  : 'Send ${_money.format(_value)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
