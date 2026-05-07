import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  WorkerPaymentConfirmSheet — shown to worker when gig enters 'payment' status.
//  Worker enters the 6-digit code shown by the host to confirm payment received.
//  QR scanning is temporarily disabled until mobile_scanner supports
//  arm64 iOS simulators (MLKit upstream limitation).
// ─────────────────────────────────────────────────────────────────────────────
class WorkerPaymentConfirmSheet extends StatefulWidget {
  final String gigId;
  final String gigCollection;
  final double budget;
  final String hostName;
  // Called after Firestore update succeeds — parent owns the pop + rating flow.
  final VoidCallback? onConfirmed;

  const WorkerPaymentConfirmSheet({
    super.key,
    required this.gigId,
    required this.gigCollection,
    required this.budget,
    required this.hostName,
    this.onConfirmed,
  });

  static Future<void> show({
    required BuildContext context,
    required String gigId,
    required String gigCollection,
    required double budget,
    required String hostName,
    VoidCallback? onConfirmed,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => WorkerPaymentConfirmSheet(
        gigId: gigId,
        gigCollection: gigCollection,
        budget: budget,
        hostName: hostName,
        onConfirmed: onConfirmed,
      ),
    );
  }

  @override
  State<WorkerPaymentConfirmSheet> createState() =>
      _WorkerPaymentConfirmSheetState();
}

class _WorkerPaymentConfirmSheetState
    extends State<WorkerPaymentConfirmSheet> {
  final _codeController = TextEditingController();
  bool _processing = false;
  String? _errorMsg;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _confirm(String code) async {
    if (_processing) return;
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      setState(() => _errorMsg = 'Please enter the payment code.');
      return;
    }
    setState(() {
      _processing = true;
      _errorMsg = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection(widget.gigCollection)
          .doc(widget.gigId)
          .get();
      final storedCode = snap.data()?['paymentCode'] as String?;
      if (storedCode == null || storedCode != trimmed) {
        setState(() {
          _processing = false;
          _errorMsg =
              'Incorrect code. Check the code with the host and try again.';
        });
        return;
      }
      await FirebaseFirestore.instance
          .collection(widget.gigCollection)
          .doc(widget.gigId)
          .update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'paymentConfirmedAt': FieldValue.serverTimestamp(),
        'paymentConfirmedBy': 'worker',
      });
      // Let the parent (WorkingUI) own the pop + rating dialog flow so there
      // is no race between this Navigator.pop and the Firestore stream firing.
      if (widget.onConfirmed != null) {
        widget.onConfirmed!();
      } else if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      setState(() {
        _processing = false;
        _errorMsg = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF22C55E);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A2236) : Colors.white;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final dividerColor = Theme.of(context).dividerColor;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: dividerColor),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Drag handle ───────────────────────────────────────────────
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 22),

            // ── Header ────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: green.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.verified_rounded,
                      color: green, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Confirm Payment',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Verify payment from ${widget.hostName}',
                        style: const TextStyle(color: kSub, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // ── Amount banner ─────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: green.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_rounded, color: green, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    '₱${widget.budget.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: green,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Cash Payment',
                    style: TextStyle(color: kSub, fontSize: 12),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── 6-digit code input ────────────────────────────────────────
            Text(
              'Enter Payment Code',
              style: TextStyle(
                color: onSurface,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ask the host for the 6-digit code displayed on their screen.',
              style: TextStyle(
                color: kSub.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: onSurface,
                fontSize: 30,
                fontWeight: FontWeight.bold,
                letterSpacing: 12,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: '• • • • • •',
                hintStyle: TextStyle(
                  color: kSub.withValues(alpha: 0.35),
                  fontSize: 24,
                  letterSpacing: 10,
                ),
                counterText: '',
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: green.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: green, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 18),
              ),
              onChanged: (_) {
                if (_errorMsg != null) setState(() => _errorMsg = null);
              },
            ),

            // ── Error message ─────────────────────────────────────────────
            if (_errorMsg != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Colors.redAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMsg!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 22),

            // ── Confirm button ────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _processing
                    ? null
                    : () => _confirm(_codeController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: green.withValues(alpha: 0.4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _processing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text(
                        'Confirm Payment Received',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}