import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;
import '../../../../core/services/gms_availability.dart';
import 'package:giggre_app/features/call/call_user_action.dart';
import 'package:giggre_app/features/chat/gig_chat_action.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/map_style.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../services/quick_gig_matching_service.dart';
import 'host_payment_code_sheet.dart';
import 'payment_selection_sheet.dart';
import '../../../../core/widgets/gig_completion_celebration.dart';
import '../../../gig_shared/active_gig_theme.dart';
import '../../../gig_shared/active_gig_step.dart';
import '../../../gig_shared/active_gig_widgets.dart';

String _generatePaymentCode() {
  final r = Random();
  return List.generate(6, (_) => r.nextInt(10)).join();
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gig Detail Sheet  –  shown when host taps a gig card
//  Displays live task details + map tracking of the assigned worker (if any)
// ─────────────────────────────────────────────────────────────────────────────
class GigDetailSheet extends StatefulWidget {
  final String gigId;
  final String gigType; // 'quick' | 'open' | 'offered'

  const GigDetailSheet({super.key, required this.gigId, required this.gigType});

  @override
  State<GigDetailSheet> createState() => _GigDetailSheetState();
}

class _GigDetailSheetState extends State<GigDetailSheet> {
  Map<String, dynamic>? _data;
  StreamSubscription? _gigSub;
  bool _cancelledHandled = false;
  // Loaded once for the "favorite this worker" toggle shown on completed
  // gigs — mirrors the same users/{hostId}.favoriteWorkerIds field the
  // Profile > Gig History sheet reads/writes (gig_host_profile_screen.dart).
  Set<String> _favoriteWorkerIds = {};

  String get _collection {
    switch (widget.gigType) {
      case 'open':
        return 'open_gigs';
      case 'offered':
        return 'offered_gigs';
      default:
        return 'quick_gigs';
    }
  }

  static const _activeStatuses = [
    'scanning',
    'in_progress',
    'navigating',
    'arrived',
    'working',
    'task_complete',
    'payment',
    'cancellation_requested',
  ];

  @override
  void initState() {
    super.initState();
    _gigSub = FirebaseFirestore.instance
        .collection(_collection)
        .doc(widget.gigId)
        .snapshots()
        .listen((snap) {
          if (!mounted || !snap.exists) return;
          final data = snap.data()!;
          setState(() => _data = data);

          if (data['status'] == 'cancelled' && !_cancelledHandled) {
            _cancelledHandled = true;
            final reasons = data['cancellation_reason'] as List?;
            final lastReason = reasons != null && reasons.isNotEmpty
                ? reasons.last as Map<String, dynamic>?
                : null;
            final isSystemAutoCancel =
                lastReason?['requestedBy'] == 'system';
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isSystemAutoCancel
                        ? 'This gig was auto-cancelled — no worker was selected before the scheduled time.'
                        : 'Gig cancellation has been approved by admin.',
                  ),
                  backgroundColor: Colors.redAccent,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              Navigator.pop(context);
            });
            return;
          }
        }, onError: (e) => debugPrint('[GigDetailSheet] gig stream error: $e'));
    _loadFavoriteWorkerIds();
  }

  @override
  void dispose() {
    _gigSub?.cancel();
    super.dispose();
  }

  Future<void> _loadFavoriteWorkerIds() async {
    final hostId = FirebaseAuth.instance.currentUser?.uid;
    if (hostId == null) return;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(hostId).get();
    if (!mounted) return;
    final list = (doc.data()?['favoriteWorkerIds'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    setState(() => _favoriteWorkerIds = list.toSet());
  }

  Future<void> _toggleFavoriteWorker(String workerId) async {
    final hostId = FirebaseAuth.instance.currentUser?.uid;
    if (hostId == null || workerId.isEmpty) return;
    final isFav = _favoriteWorkerIds.contains(workerId);
    setState(() {
      if (isFav) {
        _favoriteWorkerIds.remove(workerId);
      } else {
        _favoriteWorkerIds.add(workerId);
      }
    });
    await FirebaseFirestore.instance.collection('users').doc(hostId).set({
      'favoriteWorkerIds': isFav
          ? FieldValue.arrayRemove([workerId])
          : FieldValue.arrayUnion([workerId]),
    }, SetOptions(merge: true));
  }

  void _openFullScreenTrackingMap(
    BuildContext context, {
    required LatLng gigLocation,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              // Own live stream so the map keeps tracking the worker while
              // full screen, instead of a one-time snapshot from the sheet.
              stream: FirebaseFirestore.instance
                  .collection(_collection)
                  .doc(widget.gigId)
                  .snapshots(),
              builder: (context, snap) {
                final liveData = snap.data?.data();
                final workerGeo = liveData?['workerLocation'] as GeoPoint?;
                final liveWorkerLocation = workerGeo != null
                    ? LatLng(workerGeo.latitude, workerGeo.longitude)
                    : null;
                final liveWorkerName =
                    liveData?['assignedWorkerName'] as String? ??
                    liveData?['workerName'] as String? ??
                    'Worker';
                final liveWorkerId =
                    liveData?['assignedWorkerId'] as String? ??
                    liveData?['workerId'] as String?;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: _GigTrackingMap(
                        gigLocation: gigLocation,
                        workerLocation: liveWorkerLocation,
                        workerId: (liveWorkerId?.isNotEmpty ?? false)
                            ? liveWorkerId
                            : null,
                        workerName: liveWorkerName,
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _MapRoundButton(
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.of(ctx).pop(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _dispatchGig() async {
    final data = _data;
    if (data == null || widget.gigType != 'quick') return;
    final location = data['location'] as GeoPoint?;
    if (location == null) return;

    await FirebaseFirestore.instance
        .collection('quick_gigs')
        .doc(widget.gigId)
        .update({
          'status': 'scanning',
          'assignedWorkerId': null,
          'assignedWorkerName': null,
          'searchStartedAt': FieldValue.serverTimestamp(),
        });

    QuickGigMatchingService.startAutoSearch(
      gigId: widget.gigId,
      gigLocation: location,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Searching for available workers...'),
          backgroundColor: kAmber,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<void> _requestCancellation() async {
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
      await FirebaseFirestore.instance
          .collection(_collection)
          .doc(widget.gigId)
          .update({
            'cancellation_reason': FieldValue.arrayUnion([
              {'reason': reason, 'approved': null, 'requestedBy': 'host'},
            ]),
            'lastProgressStatus': _data?['status'] as String? ?? 'working',
            'cancellationRequestedAt': FieldValue.serverTimestamp(),
            'status': 'cancellation_requested',
          });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cancellation request submitted. Pending admin review.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _confirmCompleted() async {
    final data = _data;
    if (data == null) return;
    final db = FirebaseFirestore.instance;
    final workerId =
        data['workerId'] as String? ?? data['assignedWorkerId'] as String?;
    final workerName =
        data['assignedWorkerName'] as String? ??
        data['workerName'] as String? ??
        'Worker';
    final title = data['title'] as String? ?? 'Gig';
    final budget = (data['budget'] as num?)?.toDouble() ?? 0;
    final currencyCode = (data['currencyCode'] as String?) ?? 'PHP';

    String? paymentCode;
    await PaymentSelectionSheet.show(
      context: context,
      gigTitle: title,
      budget: budget,
      currencyCode: currencyCode,
      onConfirm: (paymentMethod) async {
        paymentCode = _generatePaymentCode();
        await Future.wait([
          db.collection(_collection).doc(widget.gigId).update({
            'status': 'payment',
            'paymentMethod': paymentMethod,
            'paymentCode': paymentCode,
            'paymentInitiatedAt': FieldValue.serverTimestamp(),
          }),
          if (workerId != null && workerId.isNotEmpty)
            db.collection('users').doc(workerId).update({'slot': 'AVAILABLE'}),
        ]);
      },
    );
    if (!mounted || paymentCode == null) return;

    final workerConfirmed = await HostPaymentCodeSheet.show(
      context: context,
      gigId: widget.gigId,
      gigCollection: _collection,
      paymentCode: paymentCode!,
      budget: budget,
      currencyCode: currencyCode,
      workerName: workerName,
      workerId: workerId ?? '',
    );
    if (!mounted || !workerConfirmed) return;

    await GigCompletionCelebration.show(
      context: context,
      title: 'Gig Complete!',
      subtitle: 'Payment confirmed — nice work getting this one done!',
      icon: Icons.emoji_events_rounded,
      accentColor: kAmber,
    );
    if (!mounted) return;

    if (workerId != null && workerId.isNotEmpty) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RatingDialog(
          workerId: workerId,
          workerName: workerName,
          gigId: widget.gigId,
          gigCollection: _collection,
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _selectWorker(Map<String, dynamic> applicant) async {
    final workerName = applicant['workerName'] as String? ?? 'Worker';
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
                  color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Color(0xFF22C55E),
                  size: 24,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Assign $workerName?',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This worker will be assigned to the gig and notified to proceed.',
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
                          'Cancel',
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
                          'Assign',
                          style: TextStyle(
                            color: Color(0xFF22C55E),
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
    await FirebaseFirestore.instance
        .collection(_collection)
        .doc(widget.gigId)
        .update({
          'workerId': applicant['workerId'],
          'assignedWorkerId': applicant['workerId'],
          'assignedWorkerName': workerName,
          'status': 'navigating',
          'selectedAt': FieldValue.serverTimestamp(),
        });
  }

  Widget _buildApplicantsSection(List<Map<String, dynamic>> applicants) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = activeGigTextPrimary(isDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Applicants',
              style: TextStyle(
                color: onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: kHostAccent.solid.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${applicants.length}',
                style: TextStyle(
                  color: kHostAccent.onWhiteText,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (applicants.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hostSheetRowSurface(isDark),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: activeGigCardBorder(isDark)),
            ),
            child: Text(
              'No applicants yet',
              style: TextStyle(color: activeGigTextMuted(isDark), fontSize: 13),
            ),
          )
        else
          Column(
            children: applicants.asMap().entries.map((entry) {
              final i = entry.key;
              final applicant = entry.value;
              final workerId = applicant['workerId'] as String? ?? '';
              final name = applicant['workerName'] as String? ?? 'Worker';
              final isLast = i == applicants.length - 1;
              return Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                child: _ApplicantTile(
                  key: ValueKey('applicant_$workerId'),
                  workerId: workerId,
                  workerName: name,
                  accentColor: kActiveGigSuccessGreen,
                  onSelect: () => _selectWorker(applicant),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final data = _data;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) {
        if (data == null) {
          return Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: kAmber, strokeWidth: 2),
            ),
          );
        }

        final status = data['status'] as String? ?? '';
        final title = data['title'] as String? ?? 'Gig';
        final budget = (data['budget'] as num?)?.toDouble() ?? 0;
        final currencyCode = (data['currencyCode'] as String?) ?? 'PHP';
        final address = data['address'] as String? ?? '';
        final scheduledDate = data['scheduledDate'] as Timestamp?;
        final geo = data['location'] as GeoPoint?;
        final gigLocation = geo != null
            ? LatLng(geo.latitude, geo.longitude)
            : null;
        final workerGeo = data['workerLocation'] as GeoPoint?;
        final workerLocation = workerGeo != null
            ? LatLng(workerGeo.latitude, workerGeo.longitude)
            : null;
        final workerName =
            data['assignedWorkerName'] as String? ??
            data['workerName'] as String? ??
            '';
        final workerId =
            data['assignedWorkerId'] as String? ??
            data['workerId'] as String? ??
            '';
        final isActive = _activeStatuses.contains(status);
        final isTaskComplete = status == 'task_complete';
        // scanning = no worker dispatched yet; in_progress = dispatched, awaiting response
        final isSearching = status == 'scanning' || status == 'in_progress';
        final progressStatus = status == 'cancellation_requested'
            ? (data['lastProgressStatus'] as String? ?? 'working')
            : status;
        final resolvedWorkerName = isSearching
            ? 'Searching for worker…'
            : (workerName.isNotEmpty ? workerName : 'Worker');
        final hostStep = gigStepFromStatus(progressStatus);
        final hostStepIndex = GigStep.values.indexOf(hostStep);
        final hostCopy = isSearching
            ? const GigStepCopy(
                'Finding the best nearby worker',
                "Hold tight — you’ll be notified the moment someone accepts.",
              )
            : hostInstructionFor(
                hostStep,
                workerName: resolvedWorkerName,
                amount: budget,
                currencyCode: currencyCode,
              );
        final showCancelGig = ![
          'completed',
          'cancelled',
          'no_worker',
          'task_complete',
          'payment',
          'cancellation_requested',
        ].contains(status);
        final createdAt = data['createdAt'] as Timestamp?;
        final applicantsList = List<Map<String, dynamic>>.from(
          (data['applicants'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>(),
        );
        final hostMapDistanceText = (gigLocation != null && workerLocation != null)
            ? ' · ${fmtDist(const ll.Distance().as(
                  ll.LengthUnit.Meter,
                  ll.LatLng(gigLocation.latitude, gigLocation.longitude),
                  ll.LatLng(workerLocation.latitude, workerLocation.longitude),
                ))} away'
            : '';

        return Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              // ── Drag handle ────────────────────────────────────────
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              if (isActive) ...[
                // ── Gold "Gig in Progress" header (mirrors worker's Figure 9) ──
                ActiveGigHeader(
                  title: isSearching ? 'Finding a Worker' : 'Gig in Progress',
                  statusLabel: isSearching
                      ? 'Searching for worker…'
                      : _hostStatusChipLabel(hostStep, resolvedWorkerName),
                  onBack: () => Navigator.pop(context),
                  accent: kHostAccent,
                ),
                const SizedBox(height: 16),

                // ── Live map card ────────────────────────────────────
                if (gigLocation != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(kActiveGigCardRadius),
                    child: Container(
                      height: 176,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(kActiveGigCardRadius),
                        border: Border.all(color: activeGigCardBorder(isDark)),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: _GigTrackingMap(
                              gigLocation: gigLocation,
                              workerLocation: workerLocation,
                              workerId: workerId.isNotEmpty ? workerId : null,
                              workerName: resolvedWorkerName,
                            ),
                          ),
                          Positioned(
                            left: 8,
                            top: 8,
                            child: MapInfoChip(
                              primaryLabel: resolvedWorkerName,
                              primaryDotColor: kActiveGigSuccessGreen,
                              secondaryLabel: 'Your gig$hostMapDistanceText',
                              secondaryDotColor: kHostAccent.solid,
                            ),
                          ),
                          if (workerLocation != null)
                            const Positioned(right: 8, top: 8, child: LiveBadge()),
                          Positioned(
                            left: 10,
                            bottom: 10,
                            child: MapRoundButton(
                              icon: Icons.fullscreen_rounded,
                              onTap: () => _openFullScreenTrackingMap(
                                ctx,
                                gigLocation: gigLocation,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Progress card: stepper + host-perspective instructions ──
                // Hidden while searching — shown only after a worker accepts.
                if (!isSearching) ...[
                  ActiveGigProgressCard(
                    stepIndex: hostStepIndex,
                    title: hostCopy.title,
                    body: hostCopy.body,
                    arrivedPromptVisible: false,
                    onConfirmArrival: () {},
                    isCancelPending: status == 'cancellation_requested',
                    showStartGig: false,
                    onStartGig: () {},
                    showGigComplete: isTaskComplete,
                    onGigComplete: _confirmCompleted,
                    accent: kHostAccent,
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Gig + worker card ────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: activeGigCardBg(isDark),
                    borderRadius: BorderRadius.circular(kActiveGigCardRadius),
                    border: Border.all(color: activeGigCardBorder(isDark)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                color: activeGigTextPrimary(isDark),
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          RichText(
                            textAlign: TextAlign.right,
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: CurrencyFormatter.format(budget, currencyCode),
                                  style: TextStyle(
                                    color: kHostAccent.onWhiteText,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                TextSpan(
                                  text: ' / gig',
                                  style: TextStyle(
                                    color: activeGigTextMuted(isDark),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (address.isNotEmpty || scheduledDate != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.location_on_outlined,
                                color: activeGigTextMuted(isDark), size: 14),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                [
                                  if (address.isNotEmpty) dedupedAddress(address),
                                  if (scheduledDate != null)
                                    _fmtScheduledShort(scheduledDate),
                                ].join(' · '),
                                style: TextStyle(
                                    color: activeGigTextMuted(isDark), fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ],
                      // Worker profile only shown after acceptance — not during dispatch.
                      if (workerId.isNotEmpty && !isSearching) ...[
                        const SizedBox(height: 14),
                        Divider(height: 0, thickness: 1, color: activeGigDividerColor(isDark)),
                        const SizedBox(height: 14),
                        _WorkerProfileCard(
                          key: ValueKey('worker_$workerId'),
                          gigId: widget.gigId,
                          workerId: workerId,
                          workerName: resolvedWorkerName,
                        ),
                      ],
                    ],
                  ),
                ),

                // ── Cancel gig ────────────────────────────────────────
                if (showCancelGig) ...[
                  const SizedBox(height: 20),
                  CancelGigSection(
                    onPressed: _requestCancellation,
                    caption:
                        'Cancelling now notifies $resolvedWorkerName · frequent cancellations affect your host rating',
                  ),
                ],
              ] else ...[
                // ── Title + status dot ──────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: activeGigTextPrimary(isDark),
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: _gigTypeAccent(widget.gigType),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _hostSheetStatusLabel(status),
                          style: TextStyle(
                            color: _gigTypeAccent(widget.gigType),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    _gigTypeLabel(widget.gigType),
                    if (createdAt != null) 'posted ${_timeAgo(createdAt.toDate())}',
                    if (widget.gigType == 'open')
                      '${applicantsList.length} applicant${applicantsList.length == 1 ? '' : 's'}',
                  ].join(' · '),
                  style: TextStyle(color: activeGigTextMuted(isDark), fontSize: 11),
                ),
                const SizedBox(height: 16),

                // ── Map: gig location (no worker yet) ─────────────────
                if (gigLocation != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 140,
                      decoration: BoxDecoration(
                        border: Border.all(color: activeGigCardBorder(isDark)),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: _GigTrackingMap(
                              gigLocation: gigLocation,
                              workerLocation: null,
                              workerId: workerId.isNotEmpty ? workerId : null,
                              workerName: workerName.isNotEmpty
                                  ? workerName
                                  : 'Worker',
                            ),
                          ),
                          Positioned(
                            left: 10,
                            bottom: 10,
                            child: _MapRoundButton(
                              icon: Icons.fullscreen_rounded,
                              onTap: () => _openFullScreenTrackingMap(
                                ctx,
                                gigLocation: gigLocation,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Applicants (open gig waiting for host to pick a worker) ──────
                if (widget.gigType == 'open' && status == 'open') ...[
                  _buildApplicantsSection(applicantsList),
                  const SizedBox(height: 16),
                ],

                // ── Info grid: pay / schedule / location ───────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _InfoGridCell(
                        icon: Icons.payments_rounded,
                        label: 'PAY',
                        isDark: isDark,
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: CurrencyFormatter.format(budget, currencyCode),
                                style: TextStyle(
                                  color: kHostAccent.onWhiteText,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              TextSpan(
                                text: ' / gig',
                                style: TextStyle(
                                  color: activeGigTextMuted(isDark),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _InfoGridCell(
                        icon: Icons.event_rounded,
                        label: 'SCHEDULE',
                        isDark: isDark,
                        value: scheduledDate != null
                            ? _fmtScheduleGrid(scheduledDate)
                            : '—',
                      ),
                    ),
                  ],
                ),
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _InfoGridCell(
                    icon: Icons.location_on_outlined,
                    label: 'LOCATION',
                    isDark: isDark,
                    value: dedupedAddress(address),
                  ),
                ],
                const SizedBox(height: 16),

                // ── Worker (offered/completed/etc. — the active branch above
                // shows this same card for in-progress gigs; this branch
                // covers every other status, so an offered gig still shows
                // who it was offered to) ────────────────────────────────
                if (workerId.isNotEmpty) ...[
                  _WorkerProfileCard(
                    key: ValueKey('worker_$workerId'),
                    gigId: widget.gigId,
                    workerId: workerId,
                    workerName: resolvedWorkerName,
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Favorite worker (completed gigs) ────────────────────
                if (status == 'completed' && workerId.isNotEmpty) ...[
                  Builder(builder: (_) {
                    final isFavorite = _favoriteWorkerIds.contains(workerId);
                    return GestureDetector(
                      onTap: () => _toggleFavoriteWorker(workerId),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: isFavorite
                              ? Colors.redAccent.withValues(alpha: 0.08)
                              : isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.grey.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isFavorite
                                ? Colors.redAccent.withValues(alpha: 0.4)
                                : activeGigCardBorder(isDark),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: isFavorite ? Colors.redAccent : kSub,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              isFavorite
                                  ? 'In Favorites'
                                  : 'Add $resolvedWorkerName to Favorites',
                              style: TextStyle(
                                color: isFavorite
                                    ? Colors.redAccent
                                    : activeGigTextPrimary(isDark),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                ],

                // ── Cancel gig ──────────────────────────────────────────
                if (showCancelGig) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _requestCancellation,
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: kActiveGigDestructiveRed,
                      ),
                      label: const Text(
                        'Cancel gig',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: kActiveGigDestructiveRed,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: activeGigCardBg(isDark),
                        side: BorderSide(color: activeGigDestructiveBorder(isDark)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ],

              // ── Dispatch button (quick gigs not yet accepted) ──────
              if (widget.gigType == 'quick' &&
                  (status == 'scanning' ||
                      status == 'no_worker' ||
                      status == 'in_progress')) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _dispatchGig,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text(
                      'Dispatch',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAmber,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Map showing gig location pin + live worker pin
// ─────────────────────────────────────────────────────────────────────────────
class _GigTrackingMap extends StatefulWidget {
  final LatLng gigLocation;
  final LatLng? workerLocation;
  final String? workerId;
  final String workerName;

  const _GigTrackingMap({
    required this.gigLocation,
    this.workerLocation,
    this.workerId,
    this.workerName = 'Worker',
  });

  @override
  State<_GigTrackingMap> createState() => _GigTrackingMapState();
}

class _GigTrackingMapState extends State<_GigTrackingMap> {
  GoogleMapController? _googleMapController;
  bool _useGoogleMaps = true;
  final _osmController = fm.MapController();
  bool _osmMapReady = false;
  List<LatLng> _routePoints = [];
  List<ll.LatLng> _routePointsOsm = [];
  BitmapDescriptor? _workerIcon;
  String? _workerPhotoUrl;
  String? _iconBuiltForWorkerId;

  @override
  void initState() {
    super.initState();
    GmsAvailability.isAvailable.then((v) {
      if (mounted) setState(() => _useGoogleMaps = v);
    });
    if (widget.workerLocation != null) {
      _fetchRoute();
    }
    _loadWorkerIcon();
  }

  @override
  void didUpdateWidget(_GigTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-center when worker location first appears or gig location changes
    if (oldWidget.workerLocation != widget.workerLocation ||
        oldWidget.gigLocation != widget.gigLocation) {
      _animateToCenter();
    }
    if (widget.workerLocation != null &&
        widget.workerLocation != oldWidget.workerLocation) {
      _fetchRoute();
    }
    if (widget.workerId != oldWidget.workerId) {
      _loadWorkerIcon();
    }
  }

  Future<void> _loadWorkerIcon() async {
    final wid = widget.workerId;
    if (wid == null || wid.isEmpty) return;
    if (_iconBuiltForWorkerId == wid) return;
    _iconBuiltForWorkerId = wid;
    String? photoUrl;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(wid)
          .get();
      photoUrl = snap.data()?['photoUrl'] as String?;
    } catch (_) {}
    final icon = await _buildAvatarMarker(photoUrl, widget.workerName);
    if (mounted && widget.workerId == wid) {
      setState(() {
        _workerPhotoUrl = photoUrl;
        _workerIcon = icon;
      });
    }
  }

  Future<BitmapDescriptor> _buildAvatarMarker(
    String? photoUrl,
    String name,
  ) async {
    const size = 40.0;
    const border = 5.0;
    const radius = size / 2 - border;
    const center = Offset(size / 2, size / 2);

    ui.Image? photo;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      try {
        final res = await http.get(Uri.parse(photoUrl));
        if (res.statusCode == 200) {
          final codec = await ui.instantiateImageCodec(
            res.bodyBytes,
            targetWidth: size.toInt(),
          );
          final frame = await codec.getNextFrame();
          photo = frame.image;
        }
      } catch (_) {}
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // White ring backdrop
    canvas.drawCircle(center, size / 2, Paint()..color = Colors.white);

    if (photo != null) {
      canvas.save();
      canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
      );
      paintImage(
        canvas: canvas,
        rect: Rect.fromCircle(center: center, radius: radius),
        image: photo,
        fit: BoxFit.cover,
      );
      canvas.restore();
    } else {
      canvas.drawCircle(center, radius, Paint()..color = kBlue);
      final initial = name.trim().isNotEmpty
          ? name.trim()[0].toUpperCase()
          : '?';
      final pb =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(
                textAlign: TextAlign.center,
                fontWeight: FontWeight.bold,
                fontSize: radius,
              ),
            )
            ..pushStyle(
              ui.TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: radius,
              ),
            )
            ..addText(initial);
      final paragraph = pb.build()
        ..layout(const ui.ParagraphConstraints(width: size));
      canvas.drawParagraph(
        paragraph,
        Offset(0, center.dy - paragraph.height / 2),
      );
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  Future<void> _fetchRoute({int attempt = 0}) async {
    final worker = widget.workerLocation;
    if (worker == null) return;
    final gig = widget.gigLocation;
    try {
      final url = Uri.parse(
        'http://router.project-osrm.org/route/v1/driving/'
        '${worker.longitude},${worker.latitude};${gig.longitude},${gig.latitude}'
        '?overview=full&geometries=polyline',
      );
      final res = await http.get(url);
      if (!mounted || res.statusCode != 200) {
        if (attempt < 3) {
          await Future.delayed(const Duration(seconds: 5));
          if (mounted) _fetchRoute(attempt: attempt + 1);
        }
        return;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = body['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return;
      final geometry =
          (routes[0] as Map<String, dynamic>)['geometry'] as String;
      final decoded = PolylinePoints()
          .decodePolyline(geometry)
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList();
      if (!mounted) return;
      setState(() {
        _routePoints = decoded;
        _routePointsOsm = decoded
            .map((p) => ll.LatLng(p.latitude, p.longitude))
            .toList();
      });
    } catch (_) {
      if (attempt < 3) {
        await Future.delayed(const Duration(seconds: 5));
        if (mounted) _fetchRoute(attempt: attempt + 1);
      }
    }
  }

  void _animateToCenter() {
    final worker = widget.workerLocation;
    if (worker == null) {
      // Only the destination is known so far — just center on it.
      if (_useGoogleMaps) {
        _googleMapController?.animateCamera(
          CameraUpdate.newLatLngZoom(widget.gigLocation, 15.0),
        );
      } else if (_osmMapReady) {
        _osmController.move(
          ll.LatLng(widget.gigLocation.latitude, widget.gigLocation.longitude),
          15.0,
        );
      }
      return;
    }

    // Both the worker and destination are known — fit the camera so both
    // stay in view instead of a fixed zoom that may crop one of them out.
    final swLat = min(widget.gigLocation.latitude, worker.latitude);
    final swLng = min(widget.gigLocation.longitude, worker.longitude);
    final neLat = max(widget.gigLocation.latitude, worker.latitude);
    final neLng = max(widget.gigLocation.longitude, worker.longitude);

    if (_useGoogleMaps) {
      _googleMapController?.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(swLat, swLng),
            northeast: LatLng(neLat, neLng),
          ),
          60,
        ),
      );
    } else if (_osmMapReady) {
      _osmController.fitCamera(
        fm.CameraFit.bounds(
          bounds: fm.LatLngBounds(
            ll.LatLng(swLat, swLng),
            ll.LatLng(neLat, neLng),
          ),
          padding: const EdgeInsets.all(60),
        ),
      );
    }
  }

  LatLng _computeCenter() {
    if (widget.workerLocation != null) {
      return LatLng(
        (widget.gigLocation.latitude + widget.workerLocation!.latitude) / 2,
        (widget.gigLocation.longitude + widget.workerLocation!.longitude) / 2,
      );
    }
    return widget.gigLocation;
  }

  Set<Marker> _buildGoogleMarkers() {
    return {
      Marker(
        markerId: const MarkerId('gig_location'),
        position: widget.gigLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ),
      if (widget.workerLocation != null)
        Marker(
          markerId: const MarkerId('worker_location'),
          position: widget.workerLocation!,
          icon:
              _workerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
        ),
    };
  }

  Widget _buildOsmMap() {
    final center = _computeCenter();
    final zoom = widget.workerLocation != null ? 14.0 : 15.0;
    final osmMarkers = <fm.Marker>[
      fm.Marker(
        point: ll.LatLng(
          widget.gigLocation.latitude,
          widget.gigLocation.longitude,
        ),
        width: 32,
        height: 32,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.orange,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: const Icon(Icons.work_rounded, color: Colors.white, size: 16),
        ),
      ),
      if (widget.workerLocation != null)
        fm.Marker(
          point: ll.LatLng(
            widget.workerLocation!.latitude,
            widget.workerLocation!.longitude,
          ),
          width: 34,
          height: 34,
          child: _WorkerPinAvatar(
            photoUrl: _workerPhotoUrl,
            name: widget.workerName,
          ),
        ),
    ];
    return fm.FlutterMap(
      mapController: _osmController,
      options: fm.MapOptions(
        initialCenter: ll.LatLng(center.latitude, center.longitude),
        initialZoom: zoom,
        interactionOptions: const fm.InteractionOptions(
          flags:
              fm.InteractiveFlag.pinchZoom |
              fm.InteractiveFlag.doubleTapZoom |
              fm.InteractiveFlag.drag |
              fm.InteractiveFlag.flingAnimation,
        ),
        onMapReady: () {
          if (mounted) setState(() => _osmMapReady = true);
          _animateToCenter();
        },
      ),
      children: [
        fm.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.giggre.mobile',
        ),
        if (_routePointsOsm.isNotEmpty)
          fm.PolylineLayer(
            polylines: [
              fm.Polyline(
                points: _routePointsOsm,
                color: kBlue,
                strokeWidth: 4,
              ),
            ],
          ),
        fm.MarkerLayer(markers: osmMarkers),
      ],
    );
  }

  @override
  void dispose() {
    _googleMapController?.dispose();
    _osmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final center = _computeCenter();
    final initialZoom = widget.workerLocation != null ? 14.0 : 15.0;

    return Stack(
      children: [
        _useGoogleMaps
            ? GoogleMap(
                style: Theme.of(context).brightness == Brightness.dark
                    ? kDarkMapStyle
                    : null,
                onMapCreated: (controller) {
                  _googleMapController = controller;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _animateToCenter();
                  });
                },
                initialCameraPosition: CameraPosition(
                  target: center,
                  zoom: initialZoom,
                ),
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                markers: _buildGoogleMarkers(),
                polylines: _routePoints.isNotEmpty
                    ? {
                        Polyline(
                          polylineId: const PolylineId('route'),
                          points: _routePoints,
                          color: kBlue,
                          width: 4,
                        ),
                      }
                    : {},
                gestureRecognizers: {
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
              )
            : _buildOsmMap(),
        Positioned(
          bottom: 12,
          right: 12,
          child: GestureDetector(
            onTap: () {
              if (_useGoogleMaps) {
                _googleMapController?.animateCamera(
                  CameraUpdate.newLatLngZoom(widget.gigLocation, 15.0),
                );
              } else if (_osmMapReady) {
                _osmController.move(
                  ll.LatLng(
                    widget.gigLocation.latitude,
                    widget.gigLocation.longitude,
                  ),
                  15.0,
                );
              }
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: cardColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.my_location_rounded,
                size: 18,
                color: kAmber,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small round icon button overlaid on the tracking map (expand / close).
// ─────────────────────────────────────────────────────────────────────────────
class _MapRoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapRoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: Colors.black87),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Worker avatar pin (OSM) — profile photo, falls back to name initial
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerPinAvatar extends StatelessWidget {
  final String? photoUrl;
  final String name;

  const _WorkerPinAvatar({this.photoUrl, required this.name});

  Widget _initialsFallback() {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      color: kBlue,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: ClipOval(
        child: (photoUrl != null && photoUrl!.isNotEmpty)
            ? Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _initialsFallback(),
              )
            : _initialsFallback(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small helpers
// ─────────────────────────────────────────────────────────────────────────────
// Gig-type accent used by the pre-selection sheet's status dot/subline —
// distinct from the gold/blue role accents above (those color the *host's*
// side of an active gig; this colors the gig's *type* before anyone's picked).
Color _gigTypeAccent(String gigType) {
  switch (gigType) {
    case 'open':
      return const Color(0xFF2B6FB5);
    case 'offered':
      return const Color(0xFF8B6FD8);
    default:
      return const Color(0xFFF0A830);
  }
}

String _gigTypeLabel(String gigType) {
  switch (gigType) {
    case 'open':
      return 'Open Gig';
    case 'offered':
      return 'Offered Gig';
    default:
      return 'Quick Gig';
  }
}

String _hostSheetStatusLabel(String status) {
  switch (status) {
    case 'scanning':
      return 'Scanning';
    case 'in_progress':
      return 'Searching';
    case 'open':
      return 'Open';
    case 'offered':
      return 'Offered';
    case 'no_worker':
      return 'No worker';
    case 'cancelled':
      return 'Cancelled';
    case 'cancellation_requested':
      return 'Cancel pending';
    default:
      return status.isEmpty
          ? ''
          : status[0].toUpperCase() + status.substring(1).replaceAll('_', ' ');
  }
}

Color _hostSheetRowSurface(bool isDark) =>
    isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFFAFBFD);
Color _hostSheetNeutralSurface(bool isDark) =>
    isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9);

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

// "Fri, Jul 11 · 4:59 PM" — the SCHEDULE cell's value format.
String _fmtScheduleGrid(Timestamp ts) {
  const weekdays = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final dt = ts.toDate().toLocal();
  final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final m = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  return '${weekdays[dt.weekday]}, ${months[dt.month]} ${dt.day} · $h:$m $period';
}

// Pay/Schedule/Location grid cell used by the pre-selection sheet.
class _InfoGridCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final String? value;
  final Widget? child;
  const _InfoGridCell({
    required this.icon,
    required this.label,
    required this.isDark,
    this.value,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _hostSheetNeutralSurface(isDark),
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 15, color: activeGigTextMuted(isDark)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: activeGigTextMuted(isDark),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              child ??
                  Text(
                    value ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: activeGigTextPrimary(isDark),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

// Short "Fri, 4:59 PM" form used inline on the gold gig+worker card.
String _fmtScheduledShort(Timestamp ts) {
  const weekdays = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final dt = ts.toDate().toLocal();
  final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final m = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  return '${weekdays[dt.weekday]}, $h:$m $period';
}

// Host-perspective status chip label for the gold "Gig in Progress" header —
// same 6-status source of truth as gigStepFromStatus, just worded for the
// host reading about their worker instead of the worker reading about self.
String _hostStatusChipLabel(GigStep step, String workerName) {
  switch (step) {
    case GigStep.navigating:
      return '$workerName on the way';
    case GigStep.arrived:
      return '$workerName arrived';
    case GigStep.working:
      return 'Working';
    case GigStep.taskComplete:
      return 'Work done';
    case GigStep.payment:
      return 'Payment in progress';
    case GigStep.completed:
      return 'Completed';
  }
}

// Counts a worker's completed gigs across all three gig collections.
// quick_gigs/open_gigs store the worker under `assignedWorkerId`; offered_gigs
// stores it under `workerId` — see the field-name note on GigDetailSheet's
// `workerId` lookup above.
Future<int> _fetchWorkerCompletedCount(String workerId) async {
  final db = FirebaseFirestore.instance;
  final snaps = await Future.wait([
    db
        .collection('quick_gigs')
        .where('assignedWorkerId', isEqualTo: workerId)
        .where('status', isEqualTo: 'completed')
        .get(),
    db
        .collection('open_gigs')
        .where('assignedWorkerId', isEqualTo: workerId)
        .where('status', isEqualTo: 'completed')
        .get(),
    db
        .collection('offered_gigs')
        .where('workerId', isEqualTo: workerId)
        .where('status', isEqualTo: 'completed')
        .get(),
  ]);
  return snaps.fold<int>(0, (total, snap) => total + snap.docs.length);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Worker profile card — photo/initials avatar, rating, completed gigs
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerProfileCard extends StatefulWidget {
  final String gigId;
  final String workerId;
  final String workerName;

  const _WorkerProfileCard({
    super.key,
    required this.gigId,
    required this.workerId,
    required this.workerName,
  });

  @override
  State<_WorkerProfileCard> createState() => _WorkerProfileCardState();
}

class _WorkerProfileCardState extends State<_WorkerProfileCard> {
  String? _photoUrl;
  double _rating = 5.0;
  int _ratingCount = 0;
  int _completedGigs = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_WorkerProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workerId != widget.workerId) _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(widget.workerId).get(),
        _fetchWorkerCompletedCount(widget.workerId),
      ]);
      if (!mounted) return;
      final userSnap = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final completed = results[1] as int;
      final data = userSnap.data();
      setState(() {
        _photoUrl = data?['photoUrl'] as String?;
        _rating = (data?['ratingAsWorker'] as num?)?.toDouble() ?? 5.0;
        _ratingCount = (data?['ratingCount'] as num?)?.toInt() ?? 0;
        _completedGigs = completed;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[WorkerProfileCard] load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _ProfileAvatar(photoUrl: _photoUrl, name: widget.workerName, size: 42),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.workerName,
                style: TextStyle(
                  color: activeGigTextPrimary(isDark),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              if (_loading)
                const SizedBox(
                  height: 12,
                  width: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kAmber,
                  ),
                )
              else
                Text(
                  '★ ${_rating.toStringAsFixed(1)} ($_ratingCount) · $_completedGigs gigs done',
                  style: TextStyle(
                      color: activeGigTextMuted(isDark), fontSize: 10.5),
                ),
            ],
          ),
        ),
        PartyActionCircle(
          bg: kHostAccent.solid.withValues(alpha: 0.12),
          child: CallUserAction(
            callType: CallType.voice,
            targetUserId: widget.workerId,
            targetUserName: widget.workerName,
            iconColor: kHostAccent.solid,
          ),
        ),
        const SizedBox(width: 8),
        PartyActionCircle(
          bg: kHostAccent.solid.withValues(alpha: 0.12),
          child: CallUserAction(
            callType: CallType.video,
            targetUserId: widget.workerId,
            targetUserName: widget.workerName,
            iconColor: kHostAccent.solid,
          ),
        ),
        const SizedBox(width: 8),
        PartyActionCircle(
          bg: kHostAccent.solid,
          child: GigChatAction(
            gigId: widget.gigId,
            targetUserId: widget.workerId,
            targetUserName: widget.workerName,
            iconColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Profile avatar — worker's photo, falls back to their name's initial
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileAvatar extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final double size;

  const _ProfileAvatar({
    required this.photoUrl,
    required this.name,
    required this.size,
  });

  Widget _initialsFallback() {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      decoration: const BoxDecoration(color: kBlue, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: (url != null && url.isNotEmpty)
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _initialsFallback(),
              )
            : _initialsFallback(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Applicant tile — shown in the Applicants list before a worker is chosen.
//  Surfaces rating + completed-gigs so the host can compare candidates.
// ─────────────────────────────────────────────────────────────────────────────
class _ApplicantTile extends StatefulWidget {
  final String workerId;
  final String workerName;
  final Color accentColor;
  final VoidCallback onSelect;

  const _ApplicantTile({
    super.key,
    required this.workerId,
    required this.workerName,
    required this.accentColor,
    required this.onSelect,
  });

  @override
  State<_ApplicantTile> createState() => _ApplicantTileState();
}

class _ApplicantTileState extends State<_ApplicantTile> {
  String? _photoUrl;
  double _rating = 5.0;
  int _ratingCount = 0;
  int _completedGigs = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.workerId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(widget.workerId).get(),
        _fetchWorkerCompletedCount(widget.workerId),
      ]);
      if (!mounted) return;
      final userSnap = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final completed = results[1] as int;
      final data = userSnap.data();
      setState(() {
        _photoUrl = data?['photoUrl'] as String?;
        _rating = (data?['ratingAsWorker'] as num?)?.toDouble() ?? 5.0;
        _ratingCount = (data?['ratingCount'] as num?)?.toInt() ?? 0;
        _completedGigs = completed;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[ApplicantTile] load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = activeGigTextPrimary(isDark);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _hostSheetRowSurface(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: activeGigCardBorder(isDark)),
      ),
      child: Row(
        children: [
          _ProfileAvatar(photoUrl: _photoUrl, name: widget.workerName, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.workerName,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                if (_loading)
                  SizedBox(
                    height: 11,
                    width: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kHostAccent.solid,
                    ),
                  )
                else
                  RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: TextStyle(
                        color: activeGigTextMuted(isDark),
                        fontSize: 10.5,
                      ),
                      children: [
                        const TextSpan(text: '★ ', style: TextStyle(color: kGold)),
                        TextSpan(
                          text:
                              '${_rating.toStringAsFixed(1)} ($_ratingCount) · $_completedGigs gigs done',
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: ElevatedButton(
              onPressed: widget.onSelect,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.accentColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Select',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
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

// ─────────────────────────────────────────────────────────────────────────────
//  Rating Dialog — shown after host confirms gig completed
// ─────────────────────────────────────────────────────────────────────────────
class _RatingDialog extends StatefulWidget {
  final String workerId;
  final String workerName;
  final String gigId;
  final String gigCollection;

  const _RatingDialog({
    required this.workerId,
    required this.workerName,
    required this.gigId,
    required this.gigCollection,
  });

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
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
      final currentCount = (data['ratingCount'] as num?)?.toInt() ?? 0;
      final newCount = currentCount + 1;
      final newRating = ((currentRating * currentCount) + _selected) / newCount;
      await Future.wait([
        db.collection('users').doc(widget.workerId).update({
          'ratingAsWorker': double.parse(newRating.toStringAsFixed(2)),
          'ratingCount': newCount,
        }),
        db.collection(widget.gigCollection).doc(widget.gigId).update({
          'hostRating': _selected,
          'hostRatedAt': FieldValue.serverTimestamp(),
        }),
      ]);
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
            'Rate Your Worker',
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
                  child: const Text(
                    'Skip',
                    style: TextStyle(color: kSub, fontSize: 14),
                  ),
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Submit',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
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
