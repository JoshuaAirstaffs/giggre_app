import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/app_colors.dart';
import 'payment_selection_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Gig Progress Tracker — shown on the host dashboard
//  Displays all active quick gigs AND open gigs with their live progress step.
//  When status == 'task_complete', the host gets a "Gig Completed" button.
// ─────────────────────────────────────────────────────────────────────────────
class GigProgressTracker extends StatefulWidget {
  final String hostId;
  const GigProgressTracker({super.key, required this.hostId});

  @override
  State<GigProgressTracker> createState() => _GigProgressTrackerState();
}

class _GigProgressTrackerState extends State<GigProgressTracker> {
  static const _activeStatuses = [
    'in_progress',
    'navigating',
    'arrived',
    'working',
    'task_complete',
    'payment',
    'cancellation_requested',
  ];

  List<({QueryDocumentSnapshot doc, String collection})> _quickDocs = [];
  List<({QueryDocumentSnapshot doc, String collection})> _openDocs = [];
  List<({QueryDocumentSnapshot doc, String collection})> _offeredDocs = [];
  StreamSubscription? _quickSub;
  StreamSubscription? _openSub;
  StreamSubscription? _offeredSub;

  @override
  void initState() {
    super.initState();
    _quickSub = FirebaseFirestore.instance
        .collection('quick_gigs')
        .where('hostId', isEqualTo: widget.hostId)
        .where('status', whereIn: _activeStatuses)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() => _quickDocs =
          snap.docs.map((d) => (doc: d, collection: 'quick_gigs')).toList());
    }, onError: (e) => debugPrint('[GigProgressTracker] quick stream: $e'));

    _openSub = FirebaseFirestore.instance
        .collection('open_gigs')
        .where('hostId', isEqualTo: widget.hostId)
        .where('status', whereIn: _activeStatuses)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() => _openDocs =
          snap.docs.map((d) => (doc: d, collection: 'open_gigs')).toList());
    }, onError: (e) => debugPrint('[GigProgressTracker] open stream: $e'));

    _offeredSub = FirebaseFirestore.instance
        .collection('offered_gigs')
        .where('hostId', isEqualTo: widget.hostId)
        .where('status', whereIn: _activeStatuses)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() => _offeredDocs =
          snap.docs.map((d) => (doc: d, collection: 'offered_gigs')).toList());
    }, onError: (e) => debugPrint('[GigProgressTracker] offered stream: $e'));
  }

  Future<void> _showWorkerRating(String workerId, String workerName) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WorkerRatingDialog(
        workerId: workerId,
        workerName: workerName,
      ),
    );
  }

  @override
  void dispose() {
    _quickSub?.cancel();
    _openSub?.cancel();
    _offeredSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allDocs = [..._quickDocs, ..._openDocs, ..._offeredDocs];
    if (allDocs.isEmpty) return const SizedBox.shrink();

    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.track_changes_rounded, color: kAmber, size: 18),
            const SizedBox(width: 8),
            Text(
              'Active Gig Progress',
              style: TextStyle(
                color: onSurface,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: kAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kAmber.withValues(alpha: 0.4)),
              ),
              child: Text(
                '${allDocs.length} Active',
                style: const TextStyle(
                  color: kAmber,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...allDocs.map((item) => _GigProgressCard(
              doc: item.doc,
              gigCollection: item.collection,
              onPaymentConfirmed: _showWorkerRating,
            )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Single gig progress card
// ─────────────────────────────────────────────────────────────────────────────
class _GigProgressCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final String gigCollection; // 'quick_gigs' | 'open_gigs' | 'offered_gigs'
  final Future<void> Function(String workerId, String workerName)? onPaymentConfirmed;

  const _GigProgressCard({
    required this.doc,
    required this.gigCollection,
    this.onPaymentConfirmed,
  });

  // Steps differ only in the first entry: quick gigs start at 'in_progress',
  // open/offered gigs start at 'navigating'.
  List<String> get _steps => gigCollection == 'quick_gigs'
      ? const [
          'in_progress',
          'arrived',
          'working',
          'task_complete',
          'payment',
          'completed',
        ]
      : const [
          'navigating',
          'arrived',
          'working',
          'task_complete',
          'payment',
          'completed',
        ];

  List<String> get _stepLabels => gigCollection == 'quick_gigs'
      ? const ['In Progress', 'Arrived', 'Working', 'Done', 'Payment', 'Completed']
      : const ['On the way', 'Arrived', 'Working', 'Done', 'Payment', 'Completed'];

  static const _stepIcons = [
    Icons.directions_rounded,
    Icons.location_on_rounded,
    Icons.work_rounded,
    Icons.check_circle_outline_rounded,
    Icons.payment_rounded,
    Icons.verified_rounded,
  ];

  Future<void> _showPaymentAndComplete(
    BuildContext context,
    String gigId,
    String? workerId,
    String workerName,
    String title,
    double budget,
  ) async {
    bool confirmed = false;
    await PaymentSelectionSheet.show(
      context: context,
      gigTitle: title,
      budget: budget,
      onConfirm: (paymentMethod) async {
        final db = FirebaseFirestore.instance;
        final updates = <Future>[
          db.collection(gigCollection).doc(gigId).update({
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
            'paymentMethod': paymentMethod,
          }),
        ];
        if (workerId != null && workerId.isNotEmpty) {
          updates.add(
            db.collection('users').doc(workerId).update({'slot': 'AVAILABLE'}),
          );
        }
        await Future.wait(updates);
        confirmed = true;
      },
    );
    if (confirmed && workerId != null && workerId.isNotEmpty) {
      await onPaymentConfirmed?.call(workerId, workerName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final gigId = doc.id;
    final title = data['title'] as String? ?? 'Gig';
    final status = data['status'] as String? ?? 'navigating';
    // offered_gigs use 'workerName'/'workerId'; quick/open use 'assignedWorkerName'/'assignedWorkerId'
    final workerName = data['assignedWorkerName'] as String? ??
                       data['workerName'] as String? ?? 'Worker';
    final workerId = data['assignedWorkerId'] as String? ??
                     data['workerId'] as String?;
    final budget = (data['budget'] as num?)?.toDouble() ?? 0;
    final isOfferedGig = gigCollection == 'offered_gigs';
    final isOpenGig = gigCollection == 'open_gigs';
    final isCancelPending = status == 'cancellation_requested';

    final steps = _steps;
    final stepLabels = _stepLabels;
    final progressStatus = isCancelPending
        ? (data['lastProgressStatus'] as String? ?? 'working')
        : status;
    final stepIndex = steps.indexOf(progressStatus).clamp(0, steps.length - 1);
    final isTaskComplete = status == 'task_complete';

    final cardColor = Theme.of(context).cardColor;
    final divider = Theme.of(context).dividerColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const green = Color(0xFF22C55E);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isTaskComplete ? green.withValues(alpha: 0.5) : divider,
          width: isTaskComplete ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: (isOfferedGig
                          ? const Color(0xFF8B5CF6)
                          : isOpenGig
                              ? kBlue
                              : kAmber)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isOfferedGig
                      ? Icons.send_rounded
                      : isOpenGig
                          ? Icons.workspace_premium_outlined
                          : Icons.flash_on_rounded,
                  color: isOfferedGig
                      ? const Color(0xFF8B5CF6)
                      : isOpenGig
                          ? kBlue
                          : kAmber,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.person_outline_rounded,
                            color: kSub, size: 12),
                        const SizedBox(width: 4),
                        Text(workerName,
                            style:
                                const TextStyle(color: kSub, fontSize: 11)),
                        const SizedBox(width: 10),
                        const Icon(Icons.attach_money_rounded,
                            color: kAmber, size: 12),
                        Text('₱${budget.toStringAsFixed(0)}',
                            style: const TextStyle(
                                color: kAmber,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
              if (isTaskComplete)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: green.withValues(alpha: 0.4)),
                  ),
                  child: const Text('Action Required',
                      style: TextStyle(
                          color: green,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Mini stepper ─────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(steps.length, (i) {
                final isActive = i == stepIndex;
                final isDone = i < stepIndex;
                final dotColor = (isActive || isDone) ? green : kSub;
                final dotBg = isDone
                    ? green
                    : isActive
                        ? green.withValues(alpha: 0.12)
                        : (isDark
                            ? kBorder.withValues(alpha: 0.5)
                            : Colors.grey.withValues(alpha: 0.12));

                return Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: dotBg,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: (isActive || isDone)
                                  ? green
                                  : kSub.withValues(alpha: 0.3),
                              width: isActive ? 2 : 1,
                            ),
                          ),
                          child: Icon(
                            isDone
                                ? Icons.check_rounded
                                : _stepIcons[i],
                            size: 13,
                            color: isDone ? Colors.white : dotColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stepLabels[i],
                          style: TextStyle(
                            fontSize: 8,
                            color: (isActive || isDone) ? green : kSub,
                            fontWeight: isActive
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    if (i < steps.length - 1)
                      Container(
                        width: 18,
                        height: 1.5,
                        margin: const EdgeInsets.only(bottom: 14),
                        color: i < stepIndex
                            ? green
                            : kSub.withValues(alpha: 0.25),
                      ),
                  ],
                );
              }),
            ),
          ),

          // ── Arrived notification ──────────────────────────────
          if (status == 'arrived') ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.location_on_rounded,
                      color: Color(0xFF22C55E), size: 14),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Worker has arrived at the gig location!',
                      style: TextStyle(
                          color: Color(0xFF22C55E),
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Cancellation pending notice ───────────────────────
          if (isCancelPending) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top_rounded,
                      color: Colors.orange, size: 14),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Cancellation request pending admin review',
                      style: TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Gig Completed button (host confirms) ─────────────
          if (isTaskComplete) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: () => _showPaymentAndComplete(
                    context, gigId, workerId, workerName, title, budget),
                icon: const Icon(Icons.verified_rounded, size: 20),
                label: const Text('Gig Completed',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Worker Rating Dialog — host rates the worker after gig completion
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerRatingDialog extends StatefulWidget {
  final String workerId;
  final String workerName;

  const _WorkerRatingDialog({
    required this.workerId,
    required this.workerName,
  });

  @override
  State<_WorkerRatingDialog> createState() => _WorkerRatingDialogState();
}

class _WorkerRatingDialogState extends State<_WorkerRatingDialog> {
  int _selected = 0;
  bool _submitting = false;

  static const _labels = ['', 'Poor', 'Fair', 'Good', 'Great', 'Excellent'];
  static const _green = Color(0xFF22C55E);
  static const _starActive = Color(0xFFFACC15);

  Future<void> _submit() async {
    if (_selected == 0) return;
    setState(() => _submitting = true);
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db.collection('users').doc(widget.workerId).get();
      final data = snap.data() ?? {};
      final currentRating = (data['ratingAsWorker'] as num?)?.toDouble() ?? 5.0;
      final currentCount = (data['ratingAsWorkerCount'] as num?)?.toInt() ?? 0;
      final newCount = currentCount + 1;
      final newRating = ((currentRating * currentCount) + _selected) / newCount;
      await db.collection('users').doc(widget.workerId).update({
        'ratingAsWorker': double.parse(newRating.toStringAsFixed(2)),
        'ratingAsWorkerCount': newCount,
      });
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final label = _selected > 0 ? _labels[_selected] : 'Tap a star to rate';

    return AlertDialog(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_rounded, color: _green, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            'Rate the Worker',
            style: TextStyle(
              color: onSurface,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'How was ${widget.workerName}?',
            style: const TextStyle(color: kSub, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starNum = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _selected = starNum),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    starNum <= _selected
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: starNum <= _selected ? _starActive : kSub,
                    size: 40,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Text(
              label,
              key: ValueKey(label),
              style: TextStyle(
                color: _selected > 0 ? _starActive : kSub,
                fontSize: 13,
                fontWeight: _selected > 0 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                  child: const Text('Skip',
                      style: TextStyle(color: kSub, fontSize: 14)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: (_selected == 0 || _submitting) ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _green.withValues(alpha: 0.4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Submit',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
