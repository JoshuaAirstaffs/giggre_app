import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/app_colors.dart';

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

  const _GigProgressCard({
    required this.doc,
    required this.gigCollection,
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

  Future<void> _confirmCompleted(BuildContext context, String gigId,
      String? workerId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Confirm Gig Completed',
            style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        content: const Text(
          'Confirm that the gig worker has completed the task?\nThis will release their payment.',
          style: TextStyle(color: kSub, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: kSub)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final db = FirebaseFirestore.instance;
    final updates = <Future>[
      db.collection(gigCollection).doc(gigId).update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      }),
    ];
    if (workerId != null && workerId.isNotEmpty) {
      updates.add(
        db.collection('users').doc(workerId).update({'slot': 'AVAILABLE'}),
      );
    }
    await Future.wait(updates);
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

    final steps = _steps;
    final stepLabels = _stepLabels;
    final stepIndex = steps.indexOf(status).clamp(0, steps.length - 1);
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

          // ── Gig Completed button (host confirms) ─────────────
          if (isTaskComplete) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: () =>
                    _confirmCompleted(context, gigId, workerId),
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
