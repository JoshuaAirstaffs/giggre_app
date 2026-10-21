import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../models/gig_points_models.dart';
import '../models/gig_points_request_models.dart';
import '../services/gig_points_service.dart';
import 'points_request_sheet.dart';
import 'reward_stage_style.dart';

final _numFmt = NumberFormat.decimalPattern();
final _dateFmt = DateFormat('MMM d · h:mm a');

/// Opens the conversion sheet for [type], or explains why it can't be used.
/// Admins open each direction in giggre-admin (Gig Points → Conversion).
Future<void> openPointsRequest(
  BuildContext context, {
  required PointsRequestType type,
  required GigPointsBalance balance,
  required WalletBalance? wallet,
  required PointsRequestLimits limits,
  GigPointsRequest? pending,
}) async {
  // One pending request per user, of any type (enforced on the server too).
  if (pending != null) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('You have a request in review'),
        content: Text(
          'Your ${pending.noun} of ${_numFmt.format(pending.points)} points '
          'is waiting for a Giggre admin. You can make a new request once it '
          'is approved or rejected, or cancel it from the Requests tab.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }
  if (!limits.isOpen(type)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("${type.title} isn't available right now.")),
    );
    return;
  }
  final empty = type == PointsRequestType.toCash
      ? balance.balance <= 0
      : (wallet?.balance ?? 0) <= 0;
  if (empty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          type == PointsRequestType.toCash
              ? 'You need available points to convert to GigCash.'
              : 'You need GigCash in your Gig Wallet to convert to points.',
        ),
      ),
    );
    return;
  }
  await PointsRequestSheet.show(
    context,
    type: type,
    availablePoints: balance.balance,
    wallet: wallet,
    limits: limits.of(type),
  );
}

/// Requests tab: the user's own conversion requests, newest first. Pending
/// ones can be cancelled (held points / GigCash are returned). Admin-made actions only appear
/// in Activity.
class PointsRequestsList extends StatelessWidget {
  /// Null while loading.
  final List<GigPointsRequest>? requests;
  final bool hasError;

  const PointsRequestsList({
    super.key,
    required this.requests,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    final snap = (data: requests, hasError: hasError);
    return Builder(
      builder: (context) {
        if (snap.data == null && !snap.hasError) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(color: kGold)),
          );
        }
        if (snap.hasError && snap.data == null) {
          return const _Empty(
            icon: Icons.cloud_off_rounded,
            text: "Couldn't load your requests. Pull down to retry.",
          );
        }
        final list = (snap.data ?? const <GigPointsRequest>[])
            .where((r) => !r.byAdmin)
            .toList();
        if (list.isEmpty) {
          return const _Empty(
            icon: Icons.receipt_long_outlined,
            text:
                'No conversions yet. Use To GigCash or To Points above — a '
                'Giggre admin reviews each one before it goes through.',
          );
        }
        final pending = list.where((r) => r.isPending).toList();
        final done = list.where((r) => !r.isPending).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (pending.isNotEmpty) ...[
              const _GroupLabel('Waiting for review'),
              for (final r in pending) ...[
                PointsRequestTile(request: r),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
            ],
            if (done.isNotEmpty) ...[
              const _GroupLabel('Completed'),
              for (final r in done) ...[
                PointsRequestTile(request: r),
                const SizedBox(height: 8),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;

  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: kSub,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Empty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kGold.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: kGold, size: 28),
        ),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: kSub, fontSize: 13, height: 1.45),
        ),
      ],
    ),
  );
}

({Color color, IconData icon}) _statusStyle(PointsRequestStatus s) =>
    switch (s) {
      PointsRequestStatus.pending => (
        color: kAmber,
        icon: Icons.hourglass_top_rounded,
      ),
      PointsRequestStatus.approved => (
        color: kGigPointsGreen,
        icon: Icons.check_circle_rounded,
      ),
      PointsRequestStatus.rejected => (
        color: Colors.redAccent,
        icon: Icons.cancel_outlined,
      ),
      PointsRequestStatus.cancelled => (color: kSub, icon: Icons.block_rounded),
    };

class PointsRequestTile extends StatefulWidget {
  final GigPointsRequest request;

  const PointsRequestTile({super.key, required this.request});

  @override
  State<PointsRequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends State<PointsRequestTile> {
  bool _cancelling = false;

  Future<void> _cancel() async {
    final r = widget.request;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancel this ${r.noun}?'),
        content: Text(switch (r.type) {
          PointsRequestType.toCash =>
            'The ${_numFmt.format(r.points)} held points go back to your balance.',
          PointsRequestType.toPoints =>
            '${formatCash(r.cash, r.currencyCode)} is refunded to your Gig Wallet.',
          null => 'Any points on hold go back to your balance.',
        }),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cancel request',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await GigPointsService.cancelRequest(r.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Request cancelled.')),
      );
    } on GigPointsRequestException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final type = pointsRequestStyle(r.type);
    final status = _statusStyle(r.status);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final sign = r.type == PointsRequestType.toPoints ? '+' : '−';
    final date = r.isPending ? r.createdAt : (r.decidedAt ?? r.createdAt);
    final subtitle = [
      if (r.type == PointsRequestType.toCash)
        'Get ${formatCash(r.cash, r.currencyCode)} GigCash',
      if (r.type == PointsRequestType.toPoints)
        'Pay ${formatCash(r.cash, r.currencyCode)} GigCash',
      if (date != null) _dateFmt.format(date),
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: type.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(type.icon, color: type.color, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kSub, fontSize: 12),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$sign${_numFmt.format(r.points)} pts',
                    style: TextStyle(
                      color: r.status == PointsRequestStatus.approved
                          ? type.color
                          : onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      decoration:
                          r.status == PointsRequestStatus.rejected ||
                              r.status == PointsRequestStatus.cancelled
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: status.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      r.status.label,
                      style: TextStyle(
                        color: status.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (r.decisionNote?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              'Reason: ${r.decisionNote}',
              style: const TextStyle(color: kSub, fontSize: 12, height: 1.35),
            ),
          ],
          if (r.isPending) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.type == PointsRequestType.toPoints
                        ? 'GigCash on hold until a Giggre admin reviews it.'
                        : 'Points on hold until a Giggre admin reviews it.',
                    style: const TextStyle(color: kSub, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: _cancelling ? null : _cancel,
                  child: _cancelling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
