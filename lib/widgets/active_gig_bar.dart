import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_colors.dart';
import '../features/gig_worker/presentation/gig_worker_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Styling constants — kept together so a gold "host" variant can reuse/retheme
//  this bar later without touching layout code. Colors that need to flip with
//  the app theme are functions of `isDark` instead of consts.
// ─────────────────────────────────────────────────────────────────────────────
Color _barBg(bool isDark) => isDark ? kCard : Colors.white;
const double _kBarRadius = 22.0;
const Color _kShadowColor = Color(0x73000000); // black @ ~45%
const Color _kIconBg = Color(0x242563EB); // #2563EB @ ~14%
const Color _kIconColor = Color(0xFF2563EB);
const Color _kPresenceDot = Color(0xFF2E9E6B);
Color _titleColor(bool isDark) => isDark ? Colors.white : const Color(0xFF17263D);
const Color _kStatusBlue = Color(0xFF2563EB);
Color _subGray(bool isDark) => isDark ? kSub : const Color(0xFF94A0B0);
Color _trackBg(bool isDark) => isDark ? const Color(0xFF334155) : const Color(0xFFEDF1F6);
Color _stepCaption(bool isDark) => isDark ? const Color(0xFF64748B) : const Color(0xFFB7C0CD);
const double _kLeadingSize = 42.0;
const double _kPresenceDotSize = 10.0;
const double _kPillRadius = 17.0;
const double _kTrackHeight = 4.0;
const Color _kWaveHighlight = Color(0xFF8FB4FA); // lighter blue crest of the sweep
const Duration _kWaveDuration = Duration(milliseconds: 1600);

// ─────────────────────────────────────────────────────────────────────────────
//  Status source of truth — same collection/field names and same status
//  string values already used by _checkForActiveGig (gig_worker_screen.dart)
//  and by _stepFromStatus (working_ui.dart), minus 'cancellation_requested':
//  once the worker requests cancellation this bar should hide right away
//  rather than wait for host/admin approval, unlike WorkingUI's own frozen
//  step display. Do not invent new values here.
// ─────────────────────────────────────────────────────────────────────────────
const List<String> _activeGigStatuses = [
  'navigating',
  'arrived',
  'working',
  'task_complete',
  'payment',
];

// Same 6-step sequence as working_ui.dart's _GigStep / _stepLabels.
const List<String> _stepOrder = [
  'navigating',
  'arrived',
  'working',
  'task_complete',
  'payment',
  'completed',
];
const List<String> _stepDisplayLabels = [
  'On the way',
  'Arrived',
  'Working',
  'Done',
  'Payment',
  'Completed',
];

/// Minimal data needed to render the bar — deliberately not GigMarkerData
/// (that's the progress screen's model); this only holds what's displayed.
class ActiveGigInfo {
  final String id;
  final String gigCollection; // 'quick_gigs' | 'open_gigs' | 'offered_gigs'
  final String title;
  final String status;
  final DateTime? scheduledDate;

  const ActiveGigInfo({
    required this.id,
    required this.gigCollection,
    required this.title,
    required this.status,
    this.scheduledDate,
  });

  int get stepIndex {
    final idx = _stepOrder.indexOf(status);
    return idx == -1 ? 0 : idx;
  }

  String get stepLabel => _stepDisplayLabels[stepIndex];
}

/// Live stream of the current user's active gig as a worker, across the three
/// gig collections. Mirrors _checkForActiveGig's/workerHasActiveGig's query
/// (same where clauses) but as a live listener instead of a one-shot get(),
/// since no reusable stream for this existed before.
///
/// Multi-worker gigs record this worker's own status on their
/// `{gigCollection}/{gigId}/workers/{uid}` subcollection doc instead of the
/// top-level gig doc's `workerId`/`status` fields, so that subcollection doc
/// (via a collection-group query) is the primary source and takes priority;
/// the per-collection top-level queries remain as a legacy fallback for
/// gigs posted before the `workers` subcollection existed. Multi-worker
/// support here is scoped to quick_gigs/open_gigs only for now — see the
/// slotSub listener below.
Stream<ActiveGigInfo?> watchActiveWorkerGig(String uid) {
  late final StreamController<ActiveGigInfo?> controller;
  StreamSubscription? quickSub, openSub, offeredSub, slotSub;
  QueryDocumentSnapshot<Map<String, dynamic>>? quickDoc;
  QueryDocumentSnapshot<Map<String, dynamic>>? openDoc;
  QueryDocumentSnapshot<Map<String, dynamic>>? offeredDoc;
  QueryDocumentSnapshot<Map<String, dynamic>>? slotDoc;

  void emit() {
    if (controller.isClosed) return;
    final QueryDocumentSnapshot<Map<String, dynamic>>? doc =
        slotDoc ?? quickDoc ?? openDoc ?? offeredDoc;
    if (doc == null) {
      controller.add(null);
      return;
    }
    final data = doc.data();
    final isSlotDoc = doc == slotDoc;
    controller.add(ActiveGigInfo(
      id: isSlotDoc ? (data['gigId'] as String? ?? doc.id) : doc.id,
      gigCollection: isSlotDoc
          ? (data['gigCollection'] as String? ?? 'quick_gigs')
          : (quickDoc != null
              ? 'quick_gigs'
              : openDoc != null
                  ? 'open_gigs'
                  : 'offered_gigs'),
      title: data['title'] as String? ?? 'Gig',
      status: data['status'] as String? ?? 'navigating',
      scheduledDate: (data['scheduledDate'] as Timestamp?)?.toDate(),
    ));
  }

  controller = StreamController<ActiveGigInfo?>.broadcast(
    onListen: () {
      quickSub = FirebaseFirestore.instance
          .collection('quick_gigs')
          .where('workerId', isEqualTo: uid)
          .where('status', whereIn: _activeGigStatuses)
          .limit(1)
          .snapshots()
          .listen((snap) {
        quickDoc = snap.docs.isNotEmpty ? snap.docs.first : null;
        emit();
      }, onError: (_) {});
      openSub = FirebaseFirestore.instance
          .collection('open_gigs')
          .where('workerId', isEqualTo: uid)
          .where('status', whereIn: _activeGigStatuses)
          .limit(1)
          .snapshots()
          .listen((snap) {
        openDoc = snap.docs.isNotEmpty ? snap.docs.first : null;
        emit();
      }, onError: (_) {});
      offeredSub = FirebaseFirestore.instance
          .collection('offered_gigs')
          .where('workerId', isEqualTo: uid)
          .where('status', whereIn: _activeGigStatuses)
          .limit(1)
          .snapshots()
          .listen((snap) {
        offeredDoc = snap.docs.isNotEmpty ? snap.docs.first : null;
        emit();
      }, onError: (_) {});
      slotSub = FirebaseFirestore.instance
          .collectionGroup('workers')
          .where('workerId', isEqualTo: uid)
          .where('status', whereIn: _activeGigStatuses)
          .snapshots()
          .listen((snap) {
        // `workers` is a collection-group query, so it spans every gig
        // type's subcollection (offered_gigs included) — Firestore can't
        // combine a second whereIn on gigCollection into this query, so
        // scope it to quick/open gigs client-side instead. Multi-worker
        // support elsewhere (offered_gigs) isn't surfaced by this bar yet.
        slotDoc = null;
        for (final d in snap.docs) {
          final collection = d.data()['gigCollection'] as String?;
          if (collection == 'quick_gigs' || collection == 'open_gigs') {
            slotDoc = d;
            break;
          }
        }
        emit();
      }, onError: (_) {});
    },
    onCancel: () {
      quickSub?.cancel();
      openSub?.cancel();
      offeredSub?.cancel();
      slotSub?.cancel();
    },
  );
  return controller.stream;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Active Gig bar — floating, bottom-docked mini player for an in-progress
//  worker gig. Purely presentational; visibility is decided by the caller
//  (render only when watchActiveWorkerGig emits non-null).
// ─────────────────────────────────────────────────────────────────────────────
class ActiveGigBar extends StatelessWidget {
  final ActiveGigInfo gig;

  const ActiveGigBar({super.key, required this.gig});

  void _openProgressScreen(BuildContext context) {
    // Same navigation the "Continue as Gig Worker" button already uses, but
    // opted in to restoring the in-progress gig straight into WorkingUI —
    // that auto-restore is otherwise off so this bar is the only entry point
    // into it (tapping "Continue as Gig Worker" always lands on the dashboard).
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const GigWorkerScreen(restoreActiveGigOnEntry: true),
      ),
    );
  }

  String get _subtitle {
    final date = gig.scheduledDate;
    if (date == null) return gig.title;
    return '${gig.title} · ${DateFormat('MMM d, h:mm a').format(date)}';
  }

  @override
  Widget build(BuildContext context) {
    final fillFraction = (gig.stepIndex + 1) / _stepOrder.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: _barBg(isDark),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(_kBarRadius),
          topRight: Radius.circular(_kBarRadius),
        ),
        boxShadow: const [
          BoxShadow(color: _kShadowColor, offset: Offset(0, -8), blurRadius: 24),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _LeadingIcon(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'Gig in progress · ',
                                style: TextStyle(
                                  color: _titleColor(isDark),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: gig.stepLabel,
                                style: const TextStyle(
                                  color: _kStatusBlue,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _subGray(isDark), fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ViewPillButton(onTap: () => _openProgressScreen(context)),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Step ${gig.stepIndex + 1} of ${_stepOrder.length}',
                  style: TextStyle(color: _stepCaption(isDark), fontSize: 8),
                ),
              ),
              const SizedBox(height: 4),
              _AnimatedProgressTrack(fillFraction: fillFraction),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadingIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: _kLeadingSize,
      height: _kLeadingSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: _kLeadingSize,
            height: _kLeadingSize,
            decoration: const BoxDecoration(
              color: _kIconBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.work_rounded, color: _kIconColor, size: 20),
          ),
          Positioned(
            top: -1,
            right: -1,
            child: Container(
              width: _kPresenceDotSize,
              height: _kPresenceDotSize,
              decoration: BoxDecoration(
                color: _kPresenceDot,
                shape: BoxShape.circle,
                border: Border.all(color: _barBg(isDark), width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Thin progress track with a soft light band that sweeps left-to-right on
// loop across the filled portion, reading as a "live" wave rather than a
// static bar.
class _AnimatedProgressTrack extends StatefulWidget {
  final double fillFraction;
  const _AnimatedProgressTrack({required this.fillFraction});

  @override
  State<_AnimatedProgressTrack> createState() => _AnimatedProgressTrackState();
}

class _AnimatedProgressTrackState extends State<_AnimatedProgressTrack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(vsync: this, duration: _kWaveDuration)
      ..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(_kTrackHeight / 2),
      child: SizedBox(
        height: _kTrackHeight,
        child: Stack(
          children: [
            Container(color: _trackBg(isDark)),
            FractionallySizedBox(
              widthFactor: widget.fillFraction.clamp(0.0, 1.0),
              child: AnimatedBuilder(
                animation: _waveController,
                builder: (context, _) {
                  // Sweeps the highlight band from off the left edge to off
                  // the right edge on loop, so it reads as a continuous wave
                  // rather than a fixed gradient.
                  final dx = _waveController.value * 4 - 1.5;
                  return ShaderMask(
                    blendMode: BlendMode.srcATop,
                    shaderCallback: (rect) => LinearGradient(
                      colors: const [_kStatusBlue, _kWaveHighlight, _kStatusBlue],
                      stops: const [0.35, 0.5, 0.65],
                      begin: Alignment(-1 + dx, 0),
                      end: Alignment(1 + dx, 0),
                    ).createShader(rect),
                    child: Container(color: _kStatusBlue),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewPillButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ViewPillButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kStatusBlue,
      borderRadius: BorderRadius.circular(_kPillRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(_kPillRadius),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'View',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, color: Colors.white, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
