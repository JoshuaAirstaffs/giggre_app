import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  WorkerPaymentConfirmSheet — shown to worker when gig enters 'payment' status.
//  Worker enters or scans the 6-digit code shown by the host.
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

  Future<void> _scanQrCode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScannerScreen()),
    );
    if (code != null && mounted) {
      setState(() {
        _codeController.text = code;
        _errorMsg = null;
      });
      _confirm(code);
    }
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
            Row(
              children: [
                Text(
                  'Enter Payment Code',
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _scanQrCode,
                  icon: const Icon(Icons.qr_code_scanner_rounded,
                      size: 18, color: green),
                  label: const Text('Scan QR',
                      style: TextStyle(color: green, fontSize: 13)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Scan the QR code or manually enter the 6-digit code from the host.',
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

// ─────────────────────────────────────────────────────────────────────────────
//  QR Scanner Screen
// ─────────────────────────────────────────────────────────────────────────────
class _QrScannerScreen extends StatefulWidget {
  const _QrScannerScreen();

  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  final _controller = MobileScannerController();
  bool _detected = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_detected) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue ?? '';
      if (RegExp(r'^\d{6}$').hasMatch(value)) {
        _detected = true;
        Navigator.pop(context, value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan Payment QR Code',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Scan frame overlay
          Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF22C55E), width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // Hint text
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Point camera at the host\'s QR code',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}