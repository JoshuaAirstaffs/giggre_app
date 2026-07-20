import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/services/earnings_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  HostPaymentCodeSheet — shown to host after selecting payment method.
//  Displays a generated 6-digit code + QR code for the worker to confirm.
//  Auto-closes when Firestore status changes to 'completed'.
// ─────────────────────────────────────────────────────────────────────────────
class HostPaymentCodeSheet extends StatefulWidget {
  final String gigId;
  final String gigCollection;
  final String paymentCode;
  final double budget;
  final String currencyCode;
  final String workerName;
  final String workerId;
  // When set, this gig uses the multi-worker `workers` subcollection and all
  // reads/writes target `{gigCollection}/{gigId}/workers/{slotWorkerId}`
  // instead of the gig doc directly — each worker settles independently.
  // Null == legacy single-worker gig, unchanged behavior.
  final String? slotWorkerId;

  const HostPaymentCodeSheet({
    super.key,
    required this.gigId,
    required this.gigCollection,
    required this.paymentCode,
    required this.budget,
    this.currencyCode = 'PHP',
    required this.workerName,
    required this.workerId,
    this.slotWorkerId,
  });

  static Future<bool> show({
    required BuildContext context,
    required String gigId,
    required String gigCollection,
    required String paymentCode,
    required double budget,
    String currencyCode = 'PHP',
    required String workerName,
    required String workerId,
    String? slotWorkerId,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => HostPaymentCodeSheet(
        gigId: gigId,
        gigCollection: gigCollection,
        paymentCode: paymentCode,
        budget: budget,
        currencyCode: currencyCode,
        workerName: workerName,
        workerId: workerId,
        slotWorkerId: slotWorkerId,
      ),
    );
    return result ?? false;
  }

  @override
  State<HostPaymentCodeSheet> createState() => _HostPaymentCodeSheetState();
}

class _HostPaymentCodeSheetState extends State<HostPaymentCodeSheet> {
  StreamSubscription? _sub;
  bool _confirmed = false;
  bool _manualProcessing = false;

  DocumentReference<Map<String, dynamic>> get _targetRef {
    final gigRef = FirebaseFirestore.instance
        .collection(widget.gigCollection)
        .doc(widget.gigId);
    final slotId = widget.slotWorkerId;
    return slotId == null ? gigRef : gigRef.collection('workers').doc(slotId);
  }

  @override
  void initState() {
    super.initState();
    _sub = _targetRef.snapshots().listen((snap) {
      final status = snap.data()?['status'] as String?;
      if (status == 'completed' && !_confirmed && mounted) {
        _confirmed = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context, true);
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _manualConfirm() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        const green = Color(0xFF22C55E);
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        final cardColor = Theme.of(ctx).cardColor;
        return AlertDialog(
          backgroundColor: cardColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          contentPadding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kAmber.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: kAmber, size: 26),
              ),
              const SizedBox(height: 14),
              Text(
                'Confirm Manually?',
                style: TextStyle(
                    color: onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Use this only if the worker verbally confirmed and code verification cannot be completed.',
                style: TextStyle(color: kSub, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: kSub.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child:
                          const Text('Cancel', style: TextStyle(color: kSub)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('Confirm',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (confirm != true || !mounted) return;
    setState(() => _manualProcessing = true);
    try {
      final db = FirebaseFirestore.instance;
      final targetRef = _targetRef;
      final workerRef = db.collection('users').doc(widget.workerId);
      final currentWeek = EarningsService.currentWeekLabel();
      final slotId = widget.slotWorkerId;
      final gigRef = slotId == null
          ? null
          : db.collection(widget.gigCollection).doc(widget.gigId);

      await db.runTransaction((tx) async {
        final targetSnap = await tx.get(targetRef);
        if (targetSnap.data()?['status'] == 'completed') return;

        await EarningsService.incrementInTransaction(
          tx: tx,
          workerRef: workerRef,
          budget: widget.budget,
          currencyCode: widget.currencyCode,
          currentWeek: currentWeek,
        );

        tx.update(targetRef, {
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
          'paymentConfirmedManually': true,
        });

        if (gigRef != null) {
          final gigSnap = await tx.get(gigRef);
          final gigData = gigSnap.data() ?? {};
          final slots = (gigData['workerSlots'] as num?)?.toInt() ?? 1;
          final completed = ((gigData['slotsCompleted'] as num?)?.toInt() ?? 0) + 1;
          tx.update(gigRef, {
            'slotsCompleted': completed,
            if (completed >= slots) 'status': 'completed',
          });
        }
      });
    } finally {
      if (mounted) setState(() => _manualProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF22C55E);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A2236) : Colors.white;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final divider = Theme.of(context).dividerColor;

    // Format code as "482 910" for readability
    final codeFormatted = widget.paymentCode.length == 6
        ? '${widget.paymentCode.substring(0, 3)}  ${widget.paymentCode.substring(3)}'
        : widget.paymentCode;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: divider),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Drag handle ───────────────────────────────────────────────
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 22),

            // ── Header icon ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.payments_rounded, color: green, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              'Payment Code',
              style: TextStyle(
                color: onSurface,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Show this code or QR to ${widget.workerName}',
              style: const TextStyle(color: kSub, fontSize: 13),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // ── QR code ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: green.withValues(alpha: 0.35),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: green.withValues(alpha: 0.12),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: QrImageView(
                data: widget.paymentCode,
                version: QrVersions.auto,
                size: 180,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF0F172A),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),

            const SizedBox(height: 22),

            // ── Code display with copy button ─────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: divider),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    codeFormatted,
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 14),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(
                          ClipboardData(text: widget.paymentCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Code copied to clipboard'),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.copy_rounded,
                          color: green, size: 18),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Amount pill ───────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: green.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.payments_rounded, color: green, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '${CurrencyFormatter.format(widget.budget, widget.currencyCode)} Cash',
                    style: const TextStyle(
                      color: green,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Waiting indicator ─────────────────────────────────────────
            if (!_confirmed)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: kAmber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kAmber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: kAmber,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Waiting for ${widget.workerName} to confirm…',
                      style:
                          const TextStyle(color: kAmber, fontSize: 12),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            Divider(height: 0, color: divider),
            const SizedBox(height: 14),

            // ── Manual confirm fallback ───────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed:
                    (_confirmed || _manualProcessing) ? null : _manualConfirm,
                icon: _manualProcessing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: kSub, strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline_rounded,
                        size: 16, color: kSub),
                label: const Text(
                  'Confirm Manually',
                  style: TextStyle(color: kSub, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}