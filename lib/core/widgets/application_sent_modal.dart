import 'package:flutter/material.dart';

// Shown after a worker applies to an open gig, in place of the old
// "Application submitted!" snackbar. Same shape as the app's other
// single-message modals (see account_not_verified_modal.dart).
Future<void> showApplicationSentModal(
  BuildContext context, {
  required String gigTitle,
}) {
  const green = Color(0xFF22C55E);
  final title = gigTitle.trim();
  return showDialog(
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
              color: green.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: green,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Application sent! 🎉',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            title.isEmpty
                ? "You applied for this gig! We'll let you know as soon as the host picks someone."
                : "You applied for \"$title\"! We'll let you know as soon as the host picks someone.",
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Sounds good',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
