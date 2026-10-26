import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/current_user_provider.dart';
import '../../../core/services/fx_rates.dart';

import '../../../core/theme/app_colors.dart';
import '../models/gig_points_request_models.dart';
import '../services/gig_points_service.dart';
import 'reward_stage_style.dart';

final _numFmt = NumberFormat.decimalPattern();
String _n(int v) => _numFmt.format(v);

/// Colour + icon per conversion direction, shared by the balance card, the
/// sheet and the requests list.
({Color color, IconData icon}) pointsRequestStyle(PointsRequestType? t) =>
    switch (t) {
      PointsRequestType.toCash => (
        color: const Color(0xFFE07B1A),
        icon: Icons.account_balance_wallet_outlined,
      ),
      PointsRequestType.toPoints => (color: kBlue, icon: Icons.stars_rounded),
      null => (color: kSub, icon: Icons.receipt_long_outlined),
    };

/// Bottom sheet for a Points ⇄ GigCash conversion REQUEST.
///
/// Two steps: the form (with a live preview at the admin-set rate), then a
/// confirmation summary — nothing is sent until the user confirms. Every
/// request waits for a Giggre admin; the sheet says what is held meanwhile.
/// The amounts shown are previews — the server decides the real ones.
class PointsRequestSheet extends StatefulWidget {
  final PointsRequestType type;
  final int availablePoints;
  final WalletBalance? wallet;
  final PointsTypeLimits limits;

  const PointsRequestSheet({
    super.key,
    required this.type,
    required this.availablePoints,
    required this.wallet,
    required this.limits,
  });

  /// Returns true when a request was submitted.
  static Future<bool?> show(
    BuildContext context, {
    required PointsRequestType type,
    required int availablePoints,
    required WalletBalance? wallet,
    required PointsTypeLimits limits,
  }) => showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => PointsRequestSheet(
      type: type,
      availablePoints: availablePoints,
      wallet: wallet,
      limits: limits,
    ),
  );

  @override
  State<PointsRequestSheet> createState() => _PointsRequestSheetState();
}

enum _Step { form, confirm, done }

class _PointsRequestSheetState extends State<PointsRequestSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();

  _Step _step = _Step.form;
  bool _submitting = false;
  String? _submitError;

  /// One id per sheet: re-submitting after a network error can't duplicate.
  final String _clientRequestId = GigPointsService.newClientRequestId();

  PointsRequestType get _type => widget.type;
  PointsTypeLimits get _lim => widget.limits;
  int get _rate => _lim.rate ?? 1;

  /// Live exchange rate (rates are set per US$1). Null while loading.
  FxRates? _fx;

  @override
  void initState() {
    super.initState();
    FxRates.fetch().then((fx) {
      if (mounted) setState(() => _fx = fx);
    });
  }

  /// Wallet units per US$1, or null if the rate isn't known yet.
  double? get _fxRate => _fx?.perUsd(_ccy);
  String get _ccy =>
      widget.wallet?.currencyCode ??
      context.read<CurrentUserProvider>().currencyCode;
  double get _walletBal => widget.wallet?.balance ?? 0;
  bool get _toCash => _type == PointsRequestType.toCash;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _points {
    final v = int.tryParse(_amount.text.trim());
    return v == null || v <= 0 ? null : v;
  }

  double? get _cash {
    final p = _points;
    final fx = _fxRate;
    return p == null || fx == null ? null : _type.cashFor(p, _rate, fx);
  }

  /// Most points the user can convert right now.
  int get _maxPoints {
    var m = _toCash
        ? widget.availablePoints
        // Largest whole number of points the wallet can pay for.
        : (_walletBal / (_fxRate ?? 1) * _rate + 1e-6).floor();
    if (_lim.max != null && m > _lim.max!) m = _lim.max!;
    if (_lim.dailyMax != null && m > _lim.dailyMax!) m = _lim.dailyMax!;
    return m < 0 ? 0 : m;
  }

  /// Client-side mirror of the server checks, for instant feedback.
  String? get _amountError {
    if (_amount.text.trim().isEmpty) return null;
    final p = _points;
    if (p == null) return 'Enter a whole number of points.';
    if (_lim.min != null && p < _lim.min!) {
      return 'Minimum is ${_n(_lim.min!)} points.';
    }
    if (_lim.max != null && p > _lim.max!) {
      return 'Maximum is ${_n(_lim.max!)} points per request.';
    }
    if (_lim.dailyMax != null && p > _lim.dailyMax!) {
      return 'The daily limit is ${_n(_lim.dailyMax!)} points.';
    }
    if (_fxRate == null) return null; // rate still loading
    final c = _cash ?? 0;
    if (c <= 0) {
      return 'That is worth less than ${formatCash(0.01, _ccy)}. Enter more points.';
    }
    if (_toCash && p > widget.availablePoints) {
      return 'You only have ${_n(widget.availablePoints)} available points.';
    }
    if (!_toCash && c > _walletBal) {
      return 'This costs ${formatCash(c, _ccy)} but your GigCash is '
          '${formatCash(_walletBal, _ccy)}.';
    }
    return null;
  }

  bool get _formReady =>
      _points != null && _amountError == null && _fxRate != null;

  /// "$1" for dollar wallets, "$1 (₱56.12)" for peso wallets.
  String _perDollar() {
    if (_ccy == 'USD') return formatCash(1, 'USD');
    final fx = _fxRate;
    return fx == null
        ? '${formatCash(1, 'USD')} (rate loading…)'
        : '${formatCash(1, 'USD')} (${formatCash(fx, _ccy)})';
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await GigPointsService.createRequest(
        type: _type,
        points: _points!,
        clientRequestId: _clientRequestId,
        note: _note.text,
      );
      if (mounted) setState(() => _step = _Step.done);
    } on GigPointsRequestException catch (e) {
      if (mounted) setState(() => _submitError = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = pointsRequestStyle(_type);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(style.icon, color: style.color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    switch (_step) {
                      _Step.form =>
                        _toCash ? 'Convert to GigCash' : 'Convert to Points',
                      _Step.confirm => 'Confirm conversion',
                      _Step.done => 'Request sent',
                    },
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...switch (_step) {
              _Step.form => _form(context),
              _Step.confirm => _confirm(context),
              _Step.done => _done(context),
            },
          ],
        ),
      ),
    );
  }

  // ── Step 1: form ─────────────────────────────────────────────────────────

  List<Widget> _form(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final limitParts = [
      if (_lim.min != null) 'Min ${_n(_lim.min!)}',
      if (_lim.max != null) 'Max ${_n(_lim.max!)}',
      if (_lim.dailyMax != null) 'Up to ${_n(_lim.dailyMax!)} a day',
    ];
    final cash = _amountError == null ? _cash : null;
    return [
      // Rate + what you have on each side.
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kGold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kGold.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _toCash
                  ? 'Rate: ${_n(_rate)} points = ${_perDollar()}'
                  : 'Rate: ${_perDollar()} = ${_n(_rate)} points',
              style: TextStyle(
                color: onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Available points: ${_n(widget.availablePoints)}  ·  '
              'GigCash: ${widget.wallet == null ? '–' : formatCash(_walletBal, _ccy)}',
              style: const TextStyle(color: kSub, fontSize: 12.5),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _label(context, _toCash ? 'Points to convert' : 'Points to get'),
      TextField(
        controller: _amount,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(8),
        ],
        onChanged: (_) => setState(() {}),
        decoration: _decoration(
          context,
          hint: '0',
          suffix: 'pts',
          error: _amountError,
          helper: limitParts.isEmpty ? null : limitParts.join(' · '),
        ),
      ),
      if (_maxPoints > 0)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _amount.text = '$_maxPoints'),
            child: Text('Use maximum (${_n(_maxPoints)})'),
          ),
        ),
      const SizedBox(height: 4),
      // Live preview.
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.swap_vert_rounded,
              color: pointsRequestStyle(_type).color,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _toCash ? 'You receive' : 'It costs',
                style: const TextStyle(color: kSub, fontSize: 13),
              ),
            ),
            Text(
              cash == null ? '–' : '${formatCash(cash, _ccy)} GigCash',
              style: TextStyle(
                color: onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _label(context, 'Note (optional)'),
      TextField(
        controller: _note,
        maxLength: 200,
        maxLines: 2,
        minLines: 1,
        decoration: _decoration(context, hint: 'Anything the admin should know'),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: _formReady
            ? () => setState(() => _step = _Step.confirm)
            : null,
        style: FilledButton.styleFrom(
          backgroundColor: kGold,
          minimumSize: const Size.fromHeight(48),
        ),
        child: const Text(
          'Review conversion',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ];
  }

  // ── Step 2: confirm ──────────────────────────────────────────────────────

  List<Widget> _confirm(BuildContext context) {
    final p = _points!;
    final c = _cash!;
    final note = _note.text.trim();
    final rows = <(String, String)>[
      ('Conversion', _type.title),
      (_toCash ? 'You give' : 'You get', '${_n(p)} points'),
      (_toCash ? 'You get' : 'You pay', '${formatCash(c, _ccy)} GigCash'),
      ('Rate', '${_n(_rate)} points per ${_perDollar()}'),
      if (_toCash)
        ('Points after hold', _n(widget.availablePoints - p))
      else
        ('GigCash after', formatCash(_walletBal - c, _ccy)),
      if (note.isNotEmpty) ('Note', note),
    ];
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          children: [
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 128,
                      child: Text(
                        k,
                        style: const TextStyle(color: kSub, fontSize: 13),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        v,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _Notice(
        icon: Icons.verified_user_outlined,
        text: _toCash
            ? 'A Giggre admin reviews every conversion. ${_n(p)} points go on '
                  'hold now and come back to you if it is rejected or you '
                  'cancel it.'
            : 'A Giggre admin reviews every conversion. ${formatCash(c, _ccy)} '
                  'is taken from your Gig Wallet now and refunded if it is '
                  'rejected or you cancel it.',
      ),
      if (_submitError != null) ...[
        const SizedBox(height: 12),
        Text(
          _submitError!,
          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
        ),
      ],
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                      _step = _Step.form;
                      _submitError = null;
                    }),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Back'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: kGold,
                minimumSize: const Size.fromHeight(48),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Send request',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    ];
  }

  // ── Step 3: done ─────────────────────────────────────────────────────────

  List<Widget> _done(BuildContext context) {
    return [
      const Icon(Icons.check_circle_rounded, color: kGigPointsGreen, size: 56),
      const SizedBox(height: 12),
      Text(
        'Your ${_type.noun} is waiting for review. We\'ll notify you when '
        "it's approved or rejected. You can cancel it from the Requests tab "
        'until then.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 14,
          height: 1.45,
        ),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        style: FilledButton.styleFrom(
          backgroundColor: kGold,
          minimumSize: const Size.fromHeight(48),
        ),
        child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    ];
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  InputDecoration _decoration(
    BuildContext context, {
    String? hint,
    String? error,
    String? helper,
    String? suffix,
  }) => InputDecoration(
    hintText: hint,
    errorText: error,
    helperText: helper,
    suffixText: suffix,
    helperMaxLines: 2,
    errorMaxLines: 3,
    isDense: true,
    filled: true,
    fillColor: Theme.of(context).scaffoldBackgroundColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Theme.of(context).dividerColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Theme.of(context).dividerColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kGold, width: 1.5),
    ),
  );
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Notice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: kGold.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: kGold, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}
