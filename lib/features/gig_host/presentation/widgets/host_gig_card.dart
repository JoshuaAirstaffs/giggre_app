import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:giggre_app/features/gig_host/models/gig_template_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../gig_shared/active_gig_step.dart';
import '../../services/quick_gig_matching_service.dart';
import 'gig_detail_sheet.dart';
import 'quick_gig_search_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Host Gig Card — single reusable list-item widget for every place the
//  host's own gigs render as a list (dashboard "Your Gigs" preview + the full
//  "My Gigs" screen). Tapping opens the same GigDetailSheet as before; the
//  dispatch/cancel/delete/save-as-template actions (only relevant on the full
//  list, via showActions) are reached with a long-press instead of a visible
//  overflow icon, so the trailing side of the card stays exactly badge+chevron.
// ─────────────────────────────────────────────────────────────────────────────

const Color _kCardBorder = Color(0xFFE4E9F0);
const Color _kTitleColor = Color(0xFF17263D);
const Color _kBodyColor = Color(0xFF5A6778);
const Color _kMutedColor = Color(0xFF94A0B0);
const Color _kChevronColor = Color(0xFFB7C0CD);
const Color _kOpenColor = Color(0xFF2B6FB5);
const Color _kProgressColor = Color(0xFF2E9E6B);
const Color _kCancelColor = Color(0xFFE5484D);
const Color _kWrapUpColor = Color(0xFFB06E00);
const Color _kOfferedColor = Color(0xFF8B5CF6);

const _kActiveStatuses = {
  'navigating',
  'arrived',
  'working',
  'task_complete',
  'payment',
  'assigned',
};

class _StatusMeta {
  final String label;
  final Color color;
  const _StatusMeta(this.label, this.color);
}

_StatusMeta _statusMeta(String status) {
  switch (status) {
    case 'open':
      return const _StatusMeta('Open', _kOpenColor);
    case 'offered':
      return const _StatusMeta('Offered', _kOfferedColor);
    case 'scanning':
    case 'in_progress':
      return const _StatusMeta('Searching', kGold);
    case 'no_worker':
      return const _StatusMeta('No worker found', _kCancelColor);
    case 'navigating':
    case 'arrived':
    case 'working':
    case 'assigned':
      return const _StatusMeta('In progress', _kProgressColor);
    case 'task_complete':
    case 'payment':
      return const _StatusMeta('Wrapping up', _kWrapUpColor);
    case 'cancellation_requested':
      return const _StatusMeta('Cancellation requested', _kCancelColor);
    case 'completed':
      return const _StatusMeta('Completed', _kMutedColor);
    case 'cancelled':
      return const _StatusMeta('Cancelled', _kMutedColor);
    default:
      return _StatusMeta(_humanizeStatus(status), _kMutedColor);
  }
}

String _humanizeStatus(String raw) {
  final words = raw
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1));
  return words.isEmpty ? raw : words.join(' ');
}

String _categoryText(String gigType, Map<String, dynamic> data) {
  switch (gigType) {
    case 'open':
      final skills = List<String>.from(data['requiredSkills'] ?? const []);
      return skills.join(', ');
    case 'offered':
      return data['skillRequired'] as String? ?? '';
    default:
      return data['category'] as String? ?? '';
  }
}

String _timeLabel(DateTime createdAt) {
  final now = DateTime.now();
  if (createdAt.year == now.year &&
      createdAt.month == now.month &&
      createdAt.day == now.day) {
    return 'today';
  }
  final diff = now.difference(createdAt);
  if (diff.inDays <= 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final weeks = diff.inDays ~/ 7;
  if (weeks < 5) return '${weeks}w ago';
  return '${diff.inDays ~/ 30}mo ago';
}

String? _sublineFor({
  required String status,
  required Map<String, dynamic> data,
  required DateTime createdAt,
  required String pay,
}) {
  if (status == 'cancellation_requested') return null;

  if (status == 'open') {
    final applicants = data['applicants'] as List<dynamic>? ?? const [];
    if (applicants.isNotEmpty) {
      final n = applicants.length;
      return '$n applicant${n == 1 ? '' : 's'} waiting for your review';
    }
    return 'No applicants yet';
  }

  if (_kActiveStatuses.contains(status)) {
    final workerName =
        (data['assignedWorkerName'] as String?) ??
        (data['workerName'] as String?) ??
        'Worker';
    switch (gigStepFromStatus(status)) {
      case GigStep.navigating:
        return '$workerName is on the way';
      case GigStep.arrived:
        return '$workerName has arrived';
      case GigStep.working:
        return '$workerName is working';
      case GigStep.taskComplete:
        return '$workerName is finished';
      case GigStep.payment:
        return '$workerName is in payment';
      case GigStep.completed:
        return '$workerName is finished';
    }
  }

  if (status == 'completed') {
    final completedAt = data['completedAt'] is Timestamp
        ? (data['completedAt'] as Timestamp).toDate()
        : createdAt;
    return 'Completed ${DateFormat('MMM d').format(completedAt)} · $pay paid';
  }

  if (status == 'scanning' || status == 'in_progress') {
    return 'Searching for available workers';
  }
  if (status == 'no_worker') return 'No worker accepted yet';
  if (status == 'offered') {
    final workerName = (data['workerName'] as String?) ?? '';
    return workerName.isNotEmpty
        ? 'Waiting for $workerName to respond'
        : 'Waiting for worker response';
  }
  return null;
}

class HostGigCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool showActions;
  const HostGigCard({super.key, required this.data, this.showActions = true});

  @override
  State<HostGigCard> createState() => _HostGigCardState();
}

class _HostGigCardState extends State<HostGigCard> {
  static String _collectionFor(String gigType) {
    switch (gigType) {
      case 'open':
        return 'open_gigs';
      case 'offered':
        return 'offered_gigs';
      default:
        return 'quick_gigs';
    }
  }

  void _showDetail() {
    final gigType = widget.data['gigType'] as String? ?? 'quick';
    final docId = widget.data['docId'] as String? ?? '';
    if (docId.isEmpty) return;

    final status = widget.data['status'] as String? ?? 'scanning';
    final location = widget.data['location'] as GeoPoint?;
    if (gigType == 'quick' &&
        (status == 'scanning' || status == 'in_progress') &&
        location != null) {
      QuickGigSearchSheet.show(
        context: context,
        gigId: docId,
        gigLocation: location,
        onDone: () => Navigator.pop(context),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GigDetailSheet(gigId: docId, gigType: gigType),
    );
  }

  Future<void> _confirmCancel() async {
    final gigType = widget.data['gigType'] as String? ?? 'quick';
    final docId = widget.data['docId'] as String? ?? '';
    if (docId.isEmpty) return;

    final controller = TextEditingController();
    bool submitted = false;
    try {
      submitted =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _CancelReasonDialog(controller: controller),
          ) ??
          false;
      if (!submitted || !mounted) return;
      final reason = controller.text.trim();
      if (reason.isEmpty) return;

      final messenger = ScaffoldMessenger.of(context);
      await FirebaseFirestore.instance
          .collection(_collectionFor(gigType))
          .doc(docId)
          .update({
            'cancellation_reason': FieldValue.arrayUnion([
              {'reason': reason, 'approved': null, 'requestedBy': 'host'},
            ]),
            'status': 'cancellation_requested',
          });
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Cancellation request submitted. Pending admin review.',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _confirmDelete() async {
    final gigType = widget.data['gigType'] as String? ?? 'quick';
    final docId = widget.data['docId'] as String? ?? '';
    if (docId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                  size: 22,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Delete Gig?',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This will permanently remove the gig. This cannot be undone.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: kSub, height: 1.55),
              ),
              const SizedBox(height: 22),
              const Divider(height: 0.5, thickness: 0.5),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(20),
                            ),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text(
                          'Keep',
                          style: TextStyle(color: kSub, fontSize: 15),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 0.5, thickness: 0.5),
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(
                              bottomRight: Radius.circular(20),
                            ),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text(
                          'Delete',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance
        .collection(_collectionFor(gigType))
        .doc(docId)
        .delete();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Gig deleted'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSnack(String msg, String status) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: status == 'success' ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _saveAsTemplate() async {
    final gigType = widget.data['gigType'] as String? ?? 'quick';
    final gigInfo = widget.data;

    final raw = gigInfo['budget'];
    final budgetVal = raw is double
        ? raw
        : raw is int
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '0') ?? 0.0;

    final rawSkills = gigInfo['requiredSkills'];
    final skillRequired = rawSkills is List
        ? (rawSkills).join(', ')
        : rawSkills?.toString() ?? '';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('gig_templates')
          .add(
            GigTemplateModel(
              hostId: uid,
              gigType: gigType,
              name: gigInfo['title'] as String? ?? '',
              title: gigInfo['title'] as String? ?? '',
              description: gigInfo['description'] as String? ?? '',
              budget: budgetVal,
              skillRequired: skillRequired,
              experienceLevel: gigInfo['experienceLevel'] as String? ?? '',
              createdAt: DateTime.now(),
            ).toMap(),
          );
      if (mounted) _showSnack('Template saved!', 'success');
    } catch (err) {
      debugPrint('Error saving template: $err');
      if (mounted) _showSnack('Failed to save template.', 'error');
    }
  }

  Future<void> _dispatchGig() async {
    final gigType = widget.data['gigType'] as String? ?? 'quick';
    if (gigType != 'quick') return;
    final docId = widget.data['docId'] as String? ?? '';
    if (docId.isEmpty) return;
    final location = widget.data['location'] as GeoPoint?;
    if (location == null) return;

    await FirebaseFirestore.instance
        .collection('quick_gigs')
        .doc(docId)
        .update({
          'status': 'scanning',
          'assignedWorkerId': null,
          'assignedWorkerName': null,
          'searchStartedAt': FieldValue.serverTimestamp(),
          'exclusionList': [],
        });

    QuickGigMatchingService.startAutoSearch(
      gigId: docId,
      gigLocation: location,
    );

    if (mounted) {
      QuickGigSearchSheet.show(
        context: context,
        gigId: docId,
        gigLocation: location,
        onDone: () => Navigator.pop(context),
      );
    }
  }

  // Long-press reveals the same dispatch/cancel/delete/save-as-template
  // actions the old overflow menu had — the redesigned card has no room for
  // a visible menu icon, so the trigger moves here instead of disappearing.
  void _showActionsSheet() {
    final gigType = widget.data['gigType'] as String? ?? 'quick';
    final status = widget.data['status'] as String? ?? 'scanning';
    final isClosed = status == 'cancelled' || status == 'completed';
    const activeGigStatusesForMenu = {
      'in_progress',
      'navigating',
      'arrived',
      'working',
      'task_complete',
      'payment',
      'cancellation_requested',
    };
    final isActiveGig = activeGigStatusesForMenu.contains(status);
    final canDispatch =
        !isClosed && gigType == 'quick' && status == 'no_worker';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canDispatch)
              ListTile(
                leading: const Icon(Icons.send_rounded, color: kAmber),
                title: const Text('Start New Search'),
                onTap: () {
                  Navigator.pop(ctx);
                  _dispatchGig();
                },
              ),
            if (!isClosed)
              ListTile(
                leading: const Icon(
                  Icons.cancel_outlined,
                  color: Colors.orange,
                ),
                title: const Text('Cancel Gig'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmCancel();
                },
              ),
            if (!isActiveGig)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text('Delete'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete();
                },
              ),
            ListTile(
              leading: const Icon(Icons.save_outlined, color: Colors.blue),
              title: const Text('Save as template'),
              onTap: () {
                Navigator.pop(ctx);
                _saveAsTemplate();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final gigType = data['gigType'] as String? ?? 'quick';
    final status = data['status'] as String? ?? 'scanning';
    final meta = _statusMeta(status);

    final title = data['title'] as String? ?? 'Untitled Gig';
    final pay = CurrencyFormatter.format(
      (data['budget'] as num?)?.toDouble() ?? 0,
      (data['currencyCode'] as String?) ?? 'PHP',
    );
    final category = _categoryText(gigType, data);
    final createdAt = data['createdAt'] != null
        ? (data['createdAt'] as Timestamp).toDate()
        : DateTime.now();
    final line2 = [
      if (category.isNotEmpty) category,
      pay,
      _timeLabel(createdAt),
    ].join(' · ');

    final subline = _sublineFor(
      status: status,
      data: data,
      createdAt: createdAt,
      pay: pay,
    );
    final hasSubline = subline != null && subline.isNotEmpty;

    final applicants = status == 'open'
        ? (data['applicants'] as List<dynamic>? ?? const [])
        : const [];
    final showApplicantBadge = status == 'open' && applicants.isNotEmpty;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? kCard : Colors.white;
    final borderColor = isDark ? kBorder : _kCardBorder;
    final titleColor = isDark ? const Color(0xFFEAF0F8) : _kTitleColor;
    final bodyColor = isDark ? const Color(0xFFCBD5E1) : _kBodyColor;
    final mutedColor = isDark ? kSub : _kMutedColor;
    final chevronColor = isDark ? kSub : _kChevronColor;

    return GestureDetector(
      onTap: _showDetail,
      onLongPress: widget.showActions ? _showActionsSheet : null,
      child: Container(
        height: 86,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '● ${meta.label}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: meta.color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    line2,
                    style: TextStyle(fontSize: 11, color: bodyColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasSubline) ...[
                    const SizedBox(height: 4),
                    Text(
                      subline,
                      style: TextStyle(fontSize: 10.5, color: mutedColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (showApplicantBadge) ...[
              Container(
                height: 20,
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kGold,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${applicants.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(Icons.chevron_right_rounded, size: 15, color: chevronColor),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Cancel Reason Dialog — host states reason; admin decides approval
// ─────────────────────────────────────────────────────────────────────────────
class _CancelReasonDialog extends StatefulWidget {
  final TextEditingController controller;
  const _CancelReasonDialog({required this.controller});

  @override
  State<_CancelReasonDialog> createState() => _CancelReasonDialogState();
}

class _CancelReasonDialogState extends State<_CancelReasonDialog> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  void _onChanged() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.cancel_outlined,
              color: Colors.redAccent,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Request Cancellation',
            style: TextStyle(
              color: onSurface,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Your request will be reviewed by an admin before the gig is cancelled.',
            style: TextStyle(color: kSub, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: widget.controller,
            maxLines: 4,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: onSurface, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Describe your reason for cancelling...',
              hintStyle: TextStyle(
                color: kSub.withValues(alpha: 0.6),
                fontSize: 13,
              ),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.redAccent.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.redAccent.withValues(alpha: 0.25),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Colors.redAccent,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Go Back', style: TextStyle(color: kSub)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _hasText
                      ? () => Navigator.pop(context, true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.redAccent.withValues(
                      alpha: 0.35,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text(
                    'Submit Request',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
