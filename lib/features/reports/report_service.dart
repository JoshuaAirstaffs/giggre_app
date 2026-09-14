import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'models/report_content_type.dart';

/// Single reusable report flow, callable from any surface (gig listing,
/// chat message, user, review) — writes one `reports/{autoId}` doc with
/// enough context that an admin can act without opening the app.
///
/// Reporting never blocks the reported user as a side effect — blocking is
/// a fully separate action via the existing block feature.
class ReportService {
  ReportService._();

  static const _reasons = [
    'Sexual content',
    'Harassment or bullying',
    'Hate speech',
    'Violence or threats',
    'Scam or fraud',
    'Spam',
    'Impersonation',
    'Other',
  ];

  static const _maxSnapshotChars = 2000;

  /// Opens the report bottom sheet. [contentAuthorId] is the uid of whoever
  /// authored the reported content (the reported user themself, when
  /// [contentType] is [ReportContentType.user]) — callers must already hide
  /// the report option when this is the current user's own content; this is
  /// just a defensive double-check.
  static Future<void> show(
    BuildContext context, {
    required ReportContentType contentType,
    required String contentId,
    required String contentSnapshot,
    required String contentAuthorId,
    required String surface,
    String? roomId,
    String? gigId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid == contentAuthorId) return;

    final existing = await FirebaseFirestore.instance
        .collection('reports')
        .where('reporterId', isEqualTo: uid)
        .where('contentId', isEqualTo: contentId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (!context.mounted) return;

    if (existing.docs.isNotEmpty) {
      await _showSheet(context, alreadyReported: true);
      return;
    }

    final submission = await _showSheet(context, alreadyReported: false);
    if (submission == null || !context.mounted) return;

    String reportedUserName = '';
    String reportedUserEmail = '';
    String snapshot = contentSnapshot.trim();
    try {
      final authorDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(contentAuthorId)
          .get();
      final authorData = authorDoc.data();
      reportedUserName = authorData?['name'] as String? ?? '';
      reportedUserEmail = authorData?['email'] as String? ?? '';
      if (snapshot.isEmpty && contentType == ReportContentType.user) {
        snapshot = (authorData?['bio'] as String? ?? '').trim();
      }
    } catch (_) {
      // Denormalised fields are best-effort — the report still goes through
      // without them rather than blocking submission on this lookup.
    }
    if (snapshot.length > _maxSnapshotChars) {
      snapshot = snapshot.substring(0, _maxSnapshotChars);
    }

    await FirebaseFirestore.instance.collection('reports').add({
      'contentType': contentType.value,
      'contentId': contentId,
      'contentSnapshot': snapshot,
      'surface': surface,
      if (roomId != null) 'roomId': roomId,
      if (gigId != null) 'gigId': gigId,
      'reporterId': uid,
      'reportedUserId': contentAuthorId,
      'reportedUserName': reportedUserName,
      'reportedUserEmail': reportedUserEmail,
      'reason': submission.reason,
      'details': submission.details,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<_ReportSubmission?> _showSheet(
    BuildContext context, {
    required bool alreadyReported,
  }) {
    String? selectedReason;
    final detailsController = TextEditingController();

    return showModalBottomSheet<_ReportSubmission>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Dragging this sheet closed while the details TextField still has
      // focus races the framework's focus teardown against the route pop
      // and throws an InheritedElement `_dependents.isEmpty` assertion.
      // Disabling drag removes that path — Cancel/submit and tapping
      // outside the sheet still dismiss it safely.
      enableDrag: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final cardColor = Theme.of(ctx).cardColor;
          final onSurface = Theme.of(ctx).colorScheme.onSurface;
          final submitted = alreadyReported;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                24,
                12,
                24,
                MediaQuery.of(ctx).viewPadding.bottom + 24,
              ),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    if (submitted) ...[
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.green,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Report received',
                              style: TextStyle(
                                color: onSurface,
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Report submitted. We review all reports within 24 hours.',
                        style: TextStyle(color: kSub, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.flag_rounded,
                              color: Colors.orange,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Report content',
                              style: TextStyle(
                                color: onSurface,
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Tell us what's wrong. Our team reviews reports separately from any blocking you do yourself.",
                        style: TextStyle(color: kSub, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      for (final reason in _reasons)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () =>
                                setSheetState(() => selectedReason = reason),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: selectedReason == reason
                                    ? kBlue.withValues(alpha: 0.1)
                                    : Colors.grey.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selectedReason == reason
                                      ? kBlue
                                      : Colors.transparent,
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selectedReason == reason
                                        ? Icons.check_circle_rounded
                                        : Icons.circle_outlined,
                                    size: 18,
                                    color: selectedReason == reason
                                        ? kBlue
                                        : kSub,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    reason,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: detailsController,
                        maxLines: 3,
                        style: TextStyle(fontSize: 14, color: onSurface),
                        decoration: InputDecoration(
                          hintText: 'Additional details (optional)',
                          hintStyle: const TextStyle(color: kSub, fontSize: 13),
                          filled: true,
                          fillColor: Colors.grey.withValues(alpha: 0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: selectedReason == null
                              ? null
                              : () => Navigator.pop(
                                  ctx,
                                  _ReportSubmission(
                                    reason: selectedReason!,
                                    details: detailsController.text.trim(),
                                  ),
                                ),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange.shade700,
                            disabledBackgroundColor: Colors.grey.withValues(
                              alpha: 0.3,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Submit report',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: kSub, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() => detailsController.dispose());
  }
}

class _ReportSubmission {
  final String reason;
  final String details;
  const _ReportSubmission({required this.reason, required this.details});
}
