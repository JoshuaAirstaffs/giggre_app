import 'package:flutter/material.dart';

// Confirms withdrawing a pending gig application. Same shape as the app's
// other single-message modals (application_sent_modal.dart,
// account_not_verified_modal.dart). Resolves true only on "Withdraw".
Future<bool> showWithdrawApplicationModal(
  BuildContext context, {
  required String gigTitle,
}) async {
  final red = Colors.red.shade600;
  final title = gigTitle.trim();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: red.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.undo_rounded, color: red, size: 40),
          ),
          const SizedBox(height: 16),
          const Text(
            'Withdraw your application?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            title.isEmpty
                ? "The host won't see you as an applicant for this gig anymore. You can apply again while it's still open."
                : "The host won't see you as an applicant for \"$title\" anymore. You can apply again while it's still open.",
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Withdraw',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Keep my application',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  return confirmed == true;
}
