import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:giggre_app/features/gig_worker/presentation/verification_screen.dart';

// Bypasses Firestore's local cache so a status change made elsewhere (e.g. an
// admin approving/rejecting from the backend) is never missed by a stale read.
Future<String> fetchLatestVerificationStatus() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return 'unverified';
  final doc = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .get(const GetOptions(source: Source.server));
  return doc.data()?['isVerified'] as String? ?? 'unverified';
}

// Shared "Account not Verified" gate used across the worker and host
// surfaces. "Verify Now" sends the user straight to VerificationScreen; the
// moment they leave that screen — back button, swipe-back, or its own back
// arrow, anything that pops the route — [onStatusRechecked] fires with a
// fresh-from-server status so the caller can drop the gate immediately
// instead of waiting for a manual refresh or app restart.
Future<void> showAccountNotVerifiedModal(
  BuildContext context, {
  ValueChanged<String>? onStatusRechecked,
}) {
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
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline, color: Colors.red, size: 40),
          ),
          const SizedBox(height: 16),
          const Text(
            'Account Not Verified',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Your account needs to be verified before you can continue. '
            'Please request verification from the admin.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VerificationScreen()),
                );
                if (!context.mounted) return;
                final status = await fetchLatestVerificationStatus();
                onStatusRechecked?.call(status);
              },
              child: const Text('Verify Now', style: TextStyle(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Not Now', style: TextStyle(color: Colors.grey.shade600)),
            ),
          ),
        ],
      ),
    ),
  );
}
