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

  /// The default set: content moderation, for a profile, a chat message or a
  /// gig listing — things someone posted.
  ///
  /// A finished gig needs different ones. What goes wrong there is about what
  /// happened on site, and none of these describe a worker who never turned
  /// up or a host who paid less than agreed. See [gigReasonsAboutWorker] and
  /// [gigReasonsAboutHost], which [show] takes via `reasons`.
  static const _reasons = [
    'Sexual content',
    'Harassment or bullying',
    'Hate speech',
    'Violence or threats',
    'Scam or fraud',
    'Spam',
    'Impersonation',
    otherReason,
  ];

  /// What a host reports about the worker they hired, after the gig closes.
  static const gigReasonsAboutWorker = [
    'Work not done properly',
    'Never showed up',
    'Showed up very late',
    'Someone else came instead',
    'Damaged property or belongings',
    'Asked for payment outside the app',
    'Harassment or threatening behavior',
    otherReason,
  ];

  /// What a worker reports about the host who hired them, after the gig
  /// closes. Payment sits first because it is the one thing the worker
  /// cannot verify until the gig is already over.
  static const gigReasonsAboutHost = [
    'Payment was different from what was agreed',
    'Never paid for the gig',
    'Work was not what the gig described',
    'Asked me to do work outside the gig',
    'Unsafe working conditions',
    'Location was not as described',
    'Asked to be paid outside the app',
    'Harassment or threatening behavior',
    otherReason,
  ];

  static const _maxSnapshotChars = 2000;

  /// The escape hatch every reason list ends with. Picking it swaps the
  /// fixed label for whatever the reporter types, so `reason` records what
  /// actually happened rather than the word "Other" — which told an admin
  /// nothing and pushed the real reason into the optional details field,
  /// where it was easy to leave blank.
  static const otherReason = 'Other';

  /// Kept short on purpose: `reason` is the one line an admin sees in a list
  /// of reports. Elaboration belongs in the details field below it.
  static const _maxCustomReason = 100;

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
    /// Overrides the reason list. Defaults to content moderation; a
    /// completed-gig report passes one of the gigReasons* sets instead.
    List<String>? reasons,
    /// Heading on the form. Defaults to the generic 'Report content'.
    String? title,
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

    final reasonList = reasons ?? _reasons;
    final heading = title ?? 'Report content';

    if (existing.docs.isNotEmpty) {
      await _showSheet(
        context,
        initiallyReported: true,
        onSubmit: null,
        reasons: reasonList,
        title: heading,
      );
      return;
    }

    await _showSheet(
      context,
      initiallyReported: false,
      reasons: reasonList,
      title: heading,
      onSubmit: (reason, details) async {
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
          // Denormalised fields are best-effort — the report still goes
          // through without them rather than blocking submission on this
          // lookup.
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
          'reason': reason,
          'details': details,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
      },
    );
  }

  // Owns the whole sheet lifecycle (form -> submitting -> confirmed) as one
  // continuously-open bottom sheet, so the reporter sees the "Report
  // received" confirmation immediately in place rather than the sheet just
  // closing — a plain SnackBar wasn't noticeable enough on its own.
  static Future<void> _showSheet(
    BuildContext context, {
    required bool initiallyReported,
    required Future<void> Function(String reason, String details)? onSubmit,
    required List<String> reasons,
    required String title,
  }) {
    String? selectedReason;
    final detailsController = TextEditingController();
    final customReasonController = TextEditingController();
    // Mirrors "the custom reason has something in it", so Submit can stay
    // disabled until it does. A flag rather than reading the controller in
    // build, so typing only rebuilds on the empty/non-empty flip.
    bool customReasonFilled = false;
    bool submitted = initiallyReported;
    bool submitting = false;
    String? submitError;

    return showModalBottomSheet<void>(
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
                              title,
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
                      for (final reason in reasons)
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
                      // Sits directly under the Other row, which is always
                      // last in every reason list.
                      if (selectedReason == otherReason) ...[
                        const SizedBox(height: 2),
                        TextField(
                          controller: customReasonController,
                          autofocus: true,
                          maxLength: _maxCustomReason,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(fontSize: 14, color: onSurface),
                          onChanged: (value) {
                            final filled = value.trim().isNotEmpty;
                            if (filled != customReasonFilled) {
                              setSheetState(() => customReasonFilled = filled);
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'What happened?',
                            hintStyle:
                                const TextStyle(color: kSub, fontSize: 13),
                            filled: true,
                            fillColor: kBlue.withValues(alpha: 0.06),
                            // The ceiling is a guard, not a target — no need
                            // to count up to it on a one-line field.
                            counterText: '',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: kBlue.withValues(alpha: 0.4),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: kBlue.withValues(alpha: 0.4),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: kBlue),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
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
                      if (submitError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          submitError!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed:
                              (selectedReason == null ||
                                  submitting ||
                                  // Other with nothing typed would file a
                                  // report whose reason is the word "Other".
                                  (selectedReason == otherReason &&
                                      !customReasonFilled))
                              ? null
                              : () async {
                                  setSheetState(() {
                                    submitting = true;
                                    submitError = null;
                                  });
                                  try {
                                    await onSubmit!(
                                      selectedReason == otherReason
                                          ? customReasonController.text.trim()
                                          : selectedReason!,
                                      detailsController.text.trim(),
                                    );
                                    setSheetState(() {
                                      submitting = false;
                                      submitted = true;
                                    });
                                  } catch (e) {
                                    setSheetState(() {
                                      submitting = false;
                                      submitError =
                                          'Something went wrong. Please try again.';
                                    });
                                  }
                                },
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
                          child: submitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
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
                          onPressed: submitting ? null : () => Navigator.pop(ctx),
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
    ).whenComplete(() {
      detailsController.dispose();
      customReasonController.dispose();
    });
  }
}
