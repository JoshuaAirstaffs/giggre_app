import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../models/gig_points_request_models.dart';
import '../services/gig_points_service.dart';
import 'reward_stage_style.dart';

final _numFmt = NumberFormat.decimalPattern();
String _n(int v) => _numFmt.format(v);

/// Colour + icon per request type, shared by the action buttons, the sheet
/// and the requests list.
({Color color, IconData icon}) pointsRequestStyle(PointsRequestType t) =>
    switch (t) {
      PointsRequestType.deposit => (
        color: kGigPointsGreen,
        icon: Icons.add_circle_outline_rounded,
      ),
      PointsRequestType.withdraw => (
        color: const Color(0xFFE07B1A),
        icon: Icons.account_balance_wallet_outlined,
      ),
      PointsRequestType.transfer => (
        color: kBlue,
        icon: Icons.swap_horiz_rounded,
      ),
    };

/// Bottom sheet for a deposit / withdraw / transfer REQUEST.
///
/// Two steps: the form, then a confirmation summary — nothing is sent until
/// the user confirms there. Every request then waits for a Giggre admin; the
/// sheet says so, and that withdrawals/transfers put the points on hold.
/// Limits shown here are for guidance — the server enforces them.
class PointsRequestSheet extends StatefulWidget {
  final PointsRequestType type;
  final int availableBalance;
  final PointsTypeLimits limits;

  const PointsRequestSheet({
    super.key,
    required this.type,
    required this.availableBalance,
    required this.limits,
  });

  /// Returns true when a request was submitted.
  static Future<bool?> show(
    BuildContext context, {
    required PointsRequestType type,
    required int availableBalance,
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
      availableBalance: availableBalance,
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
  final _recipientQuery = TextEditingController();

  _Step _step = _Step.form;
  PointsRecipient? _recipient;
  bool _lookingUp = false;
  bool _submitting = false;
  String? _lookupError;
  String? _submitError;

  /// One id per sheet: re-submitting after a network error can't duplicate.
  final String _clientRequestId = GigPointsService.newClientRequestId();

  PointsRequestType get _type => widget.type;
  PointsTypeLimits get _lim => widget.limits;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _recipientQuery.dispose();
    super.dispose();
  }

  int? get _points {
    final v = int.tryParse(_amount.text.trim());
    return v == null || v <= 0 ? null : v;
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
    if (_type.holdsPoints && p > widget.availableBalance) {
      return 'You only have ${_n(widget.availableBalance)} available points.';
    }
    return null;
  }

  bool get _formReady =>
      _points != null &&
      _amountError == null &&
      (_type != PointsRequestType.transfer || _recipient != null);

  Future<void> _lookup() async {
    final q = _recipientQuery.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _lookingUp = true;
      _lookupError = null;
      _recipient = null;
    });
    try {
      final r = await GigPointsService.lookupRecipient(q);
      if (mounted) setState(() => _recipient = r);
    } on GigPointsRequestException catch (e) {
      if (mounted) setState(() => _lookupError = e.message);
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
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
        recipientId: _recipient?.id,
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
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
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
                      _Step.form => '${_type.label} points',
                      _Step.confirm => 'Confirm your ${_type.noun}',
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
      if (_lim.max != null) 'Max ${_n(_lim.max!)} per request',
      if (_lim.dailyMax != null) 'Up to ${_n(_lim.dailyMax!)} a day',
    ];
    return [
      Text(
        switch (_type) {
          PointsRequestType.deposit =>
            'Pay Giggre first, then request the points here. They are added '
                'once an admin confirms your payment.',
          PointsRequestType.withdraw =>
            'Cash out your points. Giggre pays you outside the app once an '
                'admin approves the request.',
          PointsRequestType.transfer =>
            'Send points to another Giggre user. They arrive once an admin '
                'approves the transfer.',
        },
        style: const TextStyle(color: kSub, fontSize: 13, height: 1.4),
      ),
      if (_type.holdsPoints) ...[
        const SizedBox(height: 10),
        Text(
          'Available: ${_n(widget.availableBalance)} points',
          style: TextStyle(
            color: onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
      if (_type == PointsRequestType.transfer) ...[
        const SizedBox(height: 16),
        _label(context, 'Send to'),
        if (_recipient == null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _recipientQuery,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _lookup(),
                  enabled: !_lookingUp,
                  decoration: _decoration(
                    context,
                    hint: 'Giggre ID or phone number',
                    error: _lookupError,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _lookingUp ? null : _lookup,
                  style: FilledButton.styleFrom(backgroundColor: kBlue),
                  child: _lookingUp
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Find'),
                ),
              ),
            ],
          )
        else
          _RecipientTile(
            recipient: _recipient!,
            onChange: () => setState(() => _recipient = null),
          ),
      ],
      const SizedBox(height: 16),
      _label(context, 'Points'),
      TextField(
        controller: _amount,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(7),
        ],
        onChanged: (_) => setState(() {}),
        decoration: _decoration(
          context,
          hint: '0',
          error: _amountError,
          helper: limitParts.isEmpty ? null : limitParts.join(' · '),
        ),
      ),
      if (_type.holdsPoints && widget.availableBalance > 0) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () {
              var all = widget.availableBalance;
              if (_lim.max != null && all > _lim.max!) all = _lim.max!;
              if (_lim.dailyMax != null && all > _lim.dailyMax!) {
                all = _lim.dailyMax!;
              }
              setState(() => _amount.text = '$all');
            },
            child: const Text('Use maximum'),
          ),
        ),
      ],
      const SizedBox(height: 12),
      _label(context, 'Note (optional)'),
      TextField(
        controller: _note,
        maxLength: 200,
        maxLines: 2,
        minLines: 1,
        decoration: _decoration(
          context,
          hint: switch (_type) {
            PointsRequestType.deposit => 'How you paid, e.g. GCash ref. no.',
            PointsRequestType.withdraw => 'Where to pay you, e.g. GCash number',
            PointsRequestType.transfer => 'What it is for',
          },
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _formReady ? () => setState(() => _step = _Step.confirm) : null,
        style: FilledButton.styleFrom(
          backgroundColor: kGold,
          minimumSize: const Size.fromHeight(48),
        ),
        child: const Text(
          'Review request',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ];
  }

  // ── Step 2: confirm ──────────────────────────────────────────────────────

  List<Widget> _confirm(BuildContext context) {
    final p = _points!;
    final note = _note.text.trim();
    final rows = <(String, String)>[
      ('Type', _type.label),
      ('Points', _n(p)),
      if (_recipient != null)
        (
          'To',
          '${_recipient!.name}${_recipient!.code == null ? '' : ' (${_recipient!.code})'}',
        ),
      if (_type.holdsPoints)
        ('Balance after hold', _n(widget.availableBalance - p)),
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
        text: _type.holdsPoints
            ? 'A Giggre admin reviews every request before it goes through. '
                  '${_n(p)} points go on hold now and come back to you if '
                  'the request is rejected or you cancel it.'
            : 'A Giggre admin reviews every request before it goes through. '
                  'The points are added once your payment is confirmed.',
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
                  : Text(
                      'Send ${_type.noun} request',
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
      const Icon(
        Icons.check_circle_rounded,
        color: kGigPointsGreen,
        size: 56,
      ),
      const SizedBox(height: 12),
      Text(
        'Your ${_type.noun} of ${_n(_points!)} points is waiting for review. '
        "We'll notify you when it's approved or rejected."
        '${_type.holdsPoints ? ' You can cancel it from the Requests tab until then.' : ''}',
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
  }) => InputDecoration(
    hintText: hint,
    errorText: error,
    helperText: helper,
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

class _RecipientTile extends StatelessWidget {
  final PointsRecipient recipient;
  final VoidCallback onChange;

  const _RecipientTile({required this.recipient, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final photo = recipient.photoUrl;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: kBlue.withValues(alpha: 0.15),
            backgroundImage: photo == null ? null : NetworkImage(photo),
            child: photo == null
                ? Text(
                    recipient.name.isEmpty ? '?' : recipient.name[0],
                    style: const TextStyle(
                      color: kBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipient.name,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (recipient.code != null)
                  Text(
                    recipient.code!,
                    style: const TextStyle(color: kSub, fontSize: 12),
                  ),
              ],
            ),
          ),
          TextButton(onPressed: onChange, child: const Text('Change')),
        ],
      ),
    );
  }
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
