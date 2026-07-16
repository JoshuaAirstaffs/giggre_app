import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:provider/provider.dart';
import '../../../core/providers/current_user_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/earnings_service.dart';
import '../../../core/utils/worker_active_gig.dart';
import '../../auth/presentation/login_screen.dart';
import '../../../screens/host/host_shell.dart';
import '../../home/presentation/profile_tab.dart';
import 'widgets/dashboard_summary_card.dart';
import 'widgets/dispatch_offer_card.dart';
import 'widgets/gig_map_section.dart';
import 'widgets/worker_header.dart';
import 'widgets/worker_notifications_sheet.dart';
import 'widgets/working_ui.dart';
import 'widgets/offered_gig_offer_card.dart';
import 'widgets/gig_assigned_popup.dart'; // exports GigAssignedDialog
import '../../../widgets/active_gig_bar.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Main screen
// ─────────────────────────────────────────────────────────────────────────────
class GigWorkerScreen extends StatefulWidget {
  // When true, an already-in-progress gig is restored straight into WorkingUI
  // on entry (used by ActiveGigBar's "View" button). Defaults to false so
  // normal entry (e.g. Home's "Continue as Gig Worker") always lands on the
  // regular dashboard — the bar is the only entry point into the restore.
  final bool restoreActiveGigOnEntry;

  // True when hosted as the Home tab root inside WorkerShell — suppresses the
  // header's back arrow since there's no dashboard-level route to pop to.
  final bool isTabRoot;

  const GigWorkerScreen({
    super.key,
    this.restoreActiveGigOnEntry = false,
    this.isTabRoot = false,
  });

  @override
  State<GigWorkerScreen> createState() => _GigWorkerScreenState();
}

class _GigWorkerScreenState extends State<GigWorkerScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  // Only true when entered via ActiveGigBar's "View" — keeps the loading
  // spinner up (instead of flashing the dashboard) until _checkForActiveGig's
  // async lookup resolves and WorkingUI is ready to show.
  bool _awaitingActiveGigRestore = false;
  String _isVerified = '';

  // Profile data
  String _userId = '';
  String _name = '';
  String _email = '';
  String _phone = '';
  String _photoUrl = '';
  List<String> _skills = [];
  double _ratingAsWorker = 5.0;
  int _ratingCount = 0;
  String _memberSince = '';

  // Toggles
  bool _availableForGigs = false;
  bool _autoAccept = false;
  bool _seekingQuickGigs = false;

  // Earnings grouped by currency code
  Map<String, double> _earningsByCode = {};
  Map<String, double> _weeklyByCode = {};
  int _completedGigs = 0;

  // Active gigs (when working)
  GigMarkerData? _activeQuickGig;
  GigMarkerData? _activeOpenGig;
  GigMarkerData? _activeOfferedGig;

  // Bottom-docked bar shown on the dashboard when a gig is in progress but
  // not yet restored into WorkingUI (see GigWorkerScreen.restoreActiveGigOnEntry).
  Stream<ActiveGigInfo?>? _activeGigBarStream;

  // Incoming dispatch offer (quick gig)
  GigMarkerData? _dispatchedGig;

  // Incoming offered gig (direct personal offer from host)
  GigMarkerData? _pendingOfferedGig;
  String _pendingOfferedGigDesc = '';
  String _pendingOfferedGigSkill = '';

  StreamSubscription? _dispatchSub;
  StreamSubscription? _offeredGigSub;
  StreamSubscription? _openGigAssignSub;
  StreamSubscription? _profileSub;

  // Decline suspension
  DateTime? _suspendedUntil;
  Timer? _suspensionTimer;

  // True while WorkingUI is pushed as a route so the body doesn't render a duplicate.
  bool _workingUIRouteActive = false;

  @override
  void initState() {
    super.initState();
    _awaitingActiveGigRestore = widget.restoreActiveGigOnEntry;
    WidgetsBinding.instance.addObserver(this);
    _listenToProfile();
    _setOnlineStatus(true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _activeGigBarStream = watchActiveWorkerGig(uid);
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _dispatchSub?.cancel();
    _offeredGigSub?.cancel();
    _openGigAssignSub?.cancel();
    _suspensionTimer?.cancel();
    _setOnlineStatus(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setOnlineStatus(true);
      // Restore WorkingUI if worker has an ongoing gig they came back to
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && widget.restoreActiveGigOnEntry)
        _checkForActiveGig(uid);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _setOnlineStatus(false);
    }
  }

  Future<void> _setOnlineStatus(bool online) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isOnline': online,
      });
    } catch (_) {}
  }

  void _listenToProfile() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _profileSub?.cancel();
    _profileSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
          final data = doc.data() ?? {};

          final createdAt = data['createdAt'];
          String memberSince = '';
          if (createdAt is Timestamp) {
            final d = createdAt.toDate();
            memberSince = '${_monthName(d.month)} ${d.year}';
          }

          final suspendedUntilTs = data['suspended_until'] as Timestamp?;
          DateTime? suspendedUntil;
          if (suspendedUntilTs != null) {
            final dt = suspendedUntilTs.toDate();
            if (dt.isAfter(DateTime.now())) suspendedUntil = dt;
          }

          if (!mounted) return;

          final isFirstLoad = _loading;
          final wasNotSuspended = _suspendedUntil == null;

          setState(() {
            _userId = data['userId'] as String? ?? '';
            _name = data['name'] as String? ?? '';
            _email = data['email'] as String? ?? '';
            _phone = data['phone'] as String? ?? '';
            _photoUrl = data['photoUrl'] as String? ?? '';
            final skillsXP = data['skillsXP'] as Map<String, dynamic>? ?? {};
            _skills = skillsXP.keys.toList();
            _ratingAsWorker =
                (data['ratingAsWorker'] as num?)?.toDouble() ?? 5.0;
            _ratingCount = (data['ratingCount'] as num?)?.toInt() ?? 0;
            _availableForGigs = data['availableForGigs'] as bool? ?? false;
            _autoAccept = data['autoAccept'] as bool? ?? false;
            _seekingQuickGigs = data['seekingQuickGigs'] as bool? ?? false;
            _memberSince = memberSince;
            _suspendedUntil = suspendedUntil;
            _loading = false;
            _isVerified = data['isVerified'] as String? ?? '';

            // Earnings — read directly from the aggregated field on the user doc.
            final earningsData =
                (data['earnings'] as Map<String, dynamic>?) ?? {};
            final storedWeek = earningsData['currentWeek'] as String? ?? '';
            final currentWeek = EarningsService.currentWeekLabel();
            final rawTotal =
                (earningsData['total'] as Map<String, dynamic>?) ?? {};
            final rawWeekly = storedWeek == currentWeek
                ? (earningsData['weekly'] as Map<String, dynamic>?) ?? {}
                : <String, dynamic>{};
            _earningsByCode = rawTotal.map(
              (k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 0),
            );
            _weeklyByCode = rawWeekly.map(
              (k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 0),
            );
            _completedGigs =
                (earningsData['completedGigs'] as num?)?.toInt() ?? 0;
          });

          if (isFirstLoad) {
            _saveLocationToFirestore();
            _startDispatchSub(uid);
            _startOfferedGigSub(uid);
            _startOpenGigAssignSub(uid);
            if (widget.restoreActiveGigOnEntry) _checkForActiveGig(uid);
          }

          if (suspendedUntil != null) {
            _startSuspensionTimer();
            if (wasNotSuspended) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _showSuspensionDialog(),
              );
            }
          }
        }, onError: (e) => debugPrint('[GigWorker] profile stream error: $e'));
  }

  /// On app resume/init, restore WorkingUI if worker has an ongoing gig.
  Future<void> _checkForActiveGig(String uid) async {
    if (_activeQuickGig != null ||
        _activeOpenGig != null ||
        _activeOfferedGig != null)
      return;
    const activeStatuses = [
      'navigating',
      'arrived',
      'working',
      'task_complete',
      'payment',
      'cancellation_requested',
    ];
    try {
      // Check quick gigs first
      final quickSnap = await FirebaseFirestore.instance
          .collection('quick_gigs')
          .where('workerId', isEqualTo: uid)
          .where('status', whereIn: activeStatuses)
          .limit(1)
          .get();
      if (quickSnap.docs.isNotEmpty) {
        final doc = quickSnap.docs.first;
        final data = doc.data();
        final geo = data['location'] as GeoPoint?;
        if (geo != null && mounted) {
          setState(
            () => _activeQuickGig = GigMarkerData(
              id: doc.id,
              title: data['title'] as String? ?? 'Quick Gig',
              gigType: 'quick',
              budget: (data['budget'] as num?)?.toDouble() ?? 0,
              status: data['status'] as String? ?? 'navigating',
              hostName: data['hostName'] as String? ?? '',
              address: data['address'] as String? ?? '',
              position: LatLng(geo.latitude, geo.longitude),
              assignedWorkerId: uid,
              hostId: data['hostId'] as String? ?? '',
            ),
          );
        }
        return;
      }
      // Check open gigs
      final openSnap = await FirebaseFirestore.instance
          .collection('open_gigs')
          .where('workerId', isEqualTo: uid)
          .where('status', whereIn: activeStatuses)
          .limit(1)
          .get();
      if (openSnap.docs.isNotEmpty) {
        final doc = openSnap.docs.first;
        final data = doc.data();
        debugPrint('Open Data $data');
        final geo = data['location'] as GeoPoint?;
        if (geo != null && mounted) {
          setState(
            () => _activeOpenGig = GigMarkerData(
              id: doc.id,
              title: data['title'] as String? ?? 'Open Gig',
              gigType: 'open',
              budget: (data['budget'] as num?)?.toDouble() ?? 0,
              status: data['status'] as String? ?? 'navigating',
              hostName: data['hostName'] as String? ?? '',
              address: data['address'] as String? ?? '',
              position: LatLng(geo.latitude, geo.longitude),
              assignedWorkerId: uid,
              hostId: data['hostId'] as String? ?? '',
            ),
          );
        }
        return;
      }
      // Check offered gigs
      final offeredSnap = await FirebaseFirestore.instance
          .collection('offered_gigs')
          .where('workerId', isEqualTo: uid)
          .where('status', whereIn: activeStatuses)
          .limit(1)
          .get();
      if (offeredSnap.docs.isNotEmpty) {
        final doc = offeredSnap.docs.first;
        final data = doc.data();
        final geo = data['location'] as GeoPoint?;
        if (geo != null && mounted) {
          setState(
            () => _activeOfferedGig = GigMarkerData(
              id: doc.id,
              title: data['title'] as String? ?? 'Offered Gig',
              gigType: 'offered',
              budget: (data['budget'] as num?)?.toDouble() ?? 0,
              status: data['status'] as String? ?? 'navigating',
              hostName: data['hostName'] as String? ?? '',
              address: data['address'] as String? ?? '',
              position: LatLng(geo.latitude, geo.longitude),
              assignedWorkerId: uid,
              experienceLevel: data['experienceLevel'] as String? ?? '',
              requiredSkills: data['skillRequired'] != null
                  ? [data['skillRequired'] as String]
                  : [],
              hostId: data['hostId'] as String? ?? '',
            ),
          );
        }
      }
    } catch (_) {
    } finally {
      if (mounted && _awaitingActiveGigRestore) {
        setState(() => _awaitingActiveGigRestore = false);
      }
    }
  }

  // ── Offered gig stream — listens for pending direct offers ────────────────
  void _startOfferedGigSub(String uid) {
    _offeredGigSub?.cancel();
    _offeredGigSub = FirebaseFirestore.instance
        .collection('offered_gigs')
        .where('workerId', isEqualTo: uid)
        .where('status', isEqualTo: 'offered')
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            if (snap.docs.isEmpty) {
              setState(() => _pendingOfferedGig = null);
              return;
            }
            final doc = snap.docs.first;
            final data = doc.data();
            final geo = data['location'] as GeoPoint?;
            if (geo == null) return;
            setState(() {
              _pendingOfferedGig = GigMarkerData(
                id: doc.id,
                title: data['title'] as String? ?? 'Offered Gig',
                gigType: 'offered',
                budget: (data['budget'] as num?)?.toDouble() ?? 0,
                status: 'offered',
                hostName: data['hostName'] as String? ?? '',
                address: data['address'] as String? ?? '',
                position: LatLng(geo.latitude, geo.longitude),
                assignedWorkerId: uid,
                experienceLevel: data['experienceLevel'] as String? ?? '',
                requiredSkills: data['skillRequired'] != null
                    ? [data['skillRequired'] as String]
                    : [],
                hostId: data['hostId'] as String? ?? '',
                scheduledDate: (data['scheduledDate'] as Timestamp?)?.toDate(),
              );
              _pendingOfferedGigDesc = data['description'] as String? ?? '';
              _pendingOfferedGigSkill = data['skillRequired'] as String? ?? '';
            });
          },
          onError: (e) =>
              debugPrint('[GigWorker] offered gig stream error: $e'),
        );
  }

  // Watches for open gig assignments initiated by the host (worker doesn't tap accept).
  void _startOpenGigAssignSub(String uid) {
    _openGigAssignSub?.cancel();
    bool firstLoad = true;
    _openGigAssignSub = FirebaseFirestore.instance
        .collection('open_gigs')
        .where('workerId', isEqualTo: uid)
        .where('status', isEqualTo: 'navigating')
        .snapshots()
        .listen(
          (snap) {
            if (firstLoad) {
              firstLoad = false;
              return;
            }
            if (!mounted) return;
            for (final change in snap.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final data = change.doc.data()!;
                final geo = data['location'] as GeoPoint?;
                if (geo == null) continue;
                final gig = GigMarkerData(
                  id: change.doc.id,
                  title: data['title'] as String? ?? 'Open Gig',
                  gigType: 'open',
                  budget: (data['budget'] as num?)?.toDouble() ?? 0,
                  status: 'navigating',
                  hostName: data['hostName'] as String? ?? '',
                  address: data['address'] as String? ?? '',
                  position: LatLng(geo.latitude, geo.longitude),
                  assignedWorkerId: uid,
                  hostId: data['hostId'] as String? ?? '',
                  scheduledDate: (data['scheduledDate'] as Timestamp?)
                      ?.toDate(),
                );
                _showAssignedPopup(gig);
                break;
              }
            }
          },
          onError: (e) =>
              debugPrint('[GigWorker] open gig assign stream error: $e'),
        );
  }

  void _showAssignedPopup(GigMarkerData gig) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => GigAssignedDialog(
          gig: gig,
          onGoToLocation: () {
            Navigator.of(ctx).pop(); // close the dialog
            _openWorkingUIRoute(gig);
          },
        ),
      );
    });
  }

  void _openWorkingUIRoute(GigMarkerData gig) {
    if (!mounted) return;

    final String collection;
    final Future<void> Function() onComplete;
    final Future<void> Function() onCancel;

    if (gig.gigType == 'quick') {
      collection = 'quick_gigs';
      onComplete = _finishQuickGig;
      onCancel = _cancelQuickGig;
    } else if (gig.gigType == 'open') {
      collection = 'open_gigs';
      onComplete = _finishOpenGig;
      onCancel = _cancelOpenGig;
    } else {
      collection = 'offered_gigs';
      onComplete = _finishOfferedGig;
      onCancel = _cancelOfferedGig;
    }

    setState(() => _workingUIRouteActive = true);

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => WorkingUI(
              gig: gig,
              gigCollection: collection,
              onComplete: () async {
                await onComplete();
                if (mounted) {
                  setState(() => _workingUIRouteActive = false);
                  Navigator.of(context).maybePop();
                }
              },
              onCancel: () async {
                await onCancel();
                if (mounted) {
                  setState(() => _workingUIRouteActive = false);
                  Navigator.of(context).maybePop();
                }
              },
            ),
          ),
        )
        .then((_) {
          // Reset if the route was dismissed via back gesture / hardware back button.
          if (mounted) setState(() => _workingUIRouteActive = false);
        });
  }

  Future<void> _acceptOfferedGig(GigMarkerData gig) async {
    if (_suspendedUntil != null && DateTime.now().isBefore(_suspendedUntil!)) {
      _showSuspensionDialog();
      return;
    }
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null && await workerHasActiveGig(currentUid)) {
      if (mounted) _showAlreadyActiveGigDialog();
      return;
    }
    await FirebaseFirestore.instance
        .collection('offered_gigs')
        .doc(gig.id)
        .update({
          'status': 'navigating',
          'acceptedAt': FieldValue.serverTimestamp(),
        });
    if (mounted) {
      setState(() {
        _pendingOfferedGig = null;
        _activeOfferedGig = gig;
      });
      _showAssignedPopup(gig);
    }
  }

  Future<void> _declineOfferedGig(GigMarkerData gig) async {
    await FirebaseFirestore.instance
        .collection('offered_gigs')
        .doc(gig.id)
        .update({'status': 'declined'});
    if (mounted) setState(() => _pendingOfferedGig = null);
  }

  Future<void> _finishOfferedGig() async {
    if (mounted) setState(() => _activeOfferedGig = null);
  }

  Future<void> _cancelOfferedGig() async {
    if (mounted) setState(() => _activeOfferedGig = null);
  }

  void _startDispatchSub(String uid) {
    _dispatchSub?.cancel();
    _dispatchSub = FirebaseFirestore.instance
        .collection('quick_gigs')
        .where('assignedWorkerId', isEqualTo: uid)
        .where('status', isEqualTo: 'in_progress')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          if (snap.docs.isEmpty) {
            setState(() => _dispatchedGig = null);
            return;
          }
          final doc = snap.docs.first;
          final data = doc.data();
          final geo = data['location'] as GeoPoint?;
          if (geo == null) return;
          final gig = GigMarkerData(
            id: doc.id,
            title: data['title'] as String? ?? 'Quick Gig',
            gigType: 'quick',
            budget: (data['budget'] as num?)?.toDouble() ?? 0,
            status: 'in_progress',
            hostName: data['hostName'] as String? ?? '',
            address: data['address'] as String? ?? '',
            position: LatLng(geo.latitude, geo.longitude),
            assignedWorkerId: uid,
            hostId: data['hostId'] as String? ?? '',
            scheduledDate: (data['scheduledDate'] as Timestamp?)?.toDate(),
          );
          // Auto-accept: skip review window and accept immediately
          if (_autoAccept) {
            _acceptDispatch(gig);
            return;
          }
          setState(() => _dispatchedGig = gig);
        }, onError: (e) => debugPrint('[GigWorker] dispatch stream error: $e'));
  }

  Future<void> _saveLocationToFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'location': GeoPoint(pos.latitude, pos.longitude),
      });
    } catch (_) {}
  }

  Future<void> _setToggle(String field, bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      field: value,
    });
  }

  Future<void> _toggleQuickGigs(bool value) async {
    if (value &&
        _suspendedUntil != null &&
        DateTime.now().isBefore(_suspendedUntil!)) {
      return; // blocked — suspension banner is already visible
    }
    setState(() => _seekingQuickGigs = value);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final updates = <String, dynamic>{'seekingQuickGigs': value};
    if (value) {
      updates['availableForGigs'] = true;
      updates['slot'] = 'AVAILABLE';
    }
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update(updates);
    if (value && mounted) setState(() => _availableForGigs = true);
  }

  Future<void> _onQuickGigStarted(GigMarkerData gig) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null && await workerHasActiveGig(currentUid)) {
      if (mounted) _showAlreadyActiveGigDialog();
      return;
    }
    if (mounted) setState(() => _activeQuickGig = gig);
  }

  void _onOpenGigApplied(GigMarkerData gig) {
    setState(() => _activeOpenGig = gig);
  }

  Future<void> _finishOpenGig() async {
    if (mounted) setState(() => _activeOpenGig = null);
  }

  Future<void> _cancelOpenGig() async {
    // onCancel is only reached via admin-approved cancellation (_onAdminCancelled
    // in WorkingUI), so the status is already 'cancelled' in Firestore — do not
    // overwrite it. Just clear the worker assignment and local state.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && _activeOpenGig != null) {
      await FirebaseFirestore.instance
          .collection('open_gigs')
          .doc(_activeOpenGig!.id)
          .update({'workerId': FieldValue.delete()});
    }
    if (mounted) setState(() => _activeOpenGig = null);
  }

  Future<void> _acceptDispatch(GigMarkerData gig) async {
    if (_suspendedUntil != null && DateTime.now().isBefore(_suspendedUntil!)) {
      _showSuspensionDialog();
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (await workerHasActiveGig(uid)) {
      if (mounted) _showAlreadyActiveGigDialog();
      return;
    }
    await Future.wait([
      FirebaseFirestore.instance.collection('quick_gigs').doc(gig.id).update({
        'status': 'navigating',
        'acceptedAt': FieldValue.serverTimestamp(),
        'workerId': uid,
      }),
      FirebaseFirestore.instance.collection('users').doc(uid).update({
        'slot': 'LOCKED',
        'acceptanceRate': FieldValue.increment(0.02),
      }),
    ]);
    if (mounted) {
      setState(() {
        _dispatchedGig = null;
        _activeQuickGig = gig;
      });
      _showAssignedPopup(gig);
    }
  }

  Future<void> _declineDispatch(GigMarkerData gig) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = userSnap.data() ?? {};

    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final storedDate = data['decline_count_date'] as String? ?? '';
    final isNewDay = storedDate != todayStr;

    final currentDeclineCount = isNewDay
        ? 0
        : (data['decline_count'] as num?)?.toInt() ?? 0;
    final newDeclineCount = currentDeclineCount + 1;

    await Future.wait([
      FirebaseFirestore.instance.collection('quick_gigs').doc(gig.id).update({
        'status': 'scanning',
        'assignedWorkerId': FieldValue.delete(),
        'assignedWorkerName': FieldValue.delete(),
        'exclusionList': FieldValue.arrayUnion([uid]),
      }),
      FirebaseFirestore.instance.collection('users').doc(uid).update({
        'slot': 'AVAILABLE',
        'acceptanceRate': FieldValue.increment(-0.10),
        'decline_count': newDeclineCount,
        'decline_count_date': todayStr,
      }),
    ]);
    if (mounted) setState(() => _dispatchedGig = null);
    await _checkAndApplySuspension(uid, newDeclineCount);
  }

  // Called by WorkingUI when Firestore status becomes 'completed' (set by host).
  // Host already updated the gig doc; we only reset the worker's slot here.
  Future<void> _finishQuickGig() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'slot': 'AVAILABLE',
      });
    }
    if (mounted) setState(() => _activeQuickGig = null);
    _toggleQuickGigs(false);
  }

  Future<void> _cancelQuickGig() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && _activeQuickGig != null) {
      await FirebaseFirestore.instance
          .collection('quick_gigs')
          .doc(_activeQuickGig!.id)
          .update({'status': 'cancelled'});
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'slot': 'AVAILABLE',
      });
    }
    if (mounted) setState(() => _activeQuickGig = null);
  }

  Future<void> _checkAndApplySuspension(String uid, int newDeclineCount) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('quick_gig_config')
          .doc('decline_suspension')
          .get();
      final data = doc.data() ?? {};
      final freeLimit = (data['free_decline_limit'] as num?)?.toInt() ?? 0;

      if (newDeclineCount <= freeLimit) return;

      final tierTable = data['suspension_tier_table'] as List<dynamic>? ?? [];
      if (tierTable.isEmpty) return;

      // Triggers are relative to the free limit.
      // e.g. freeLimit=5, trigger=2 → fires at decline #7.
      final declinesOverLimit = newDeclineCount - freeLimit;

      int? suspensionMinutes;
      int highestTrigger = 0;
      for (final tier in tierTable) {
        final trigger = (tier['decline_count_trigger'] as num?)?.toInt() ?? 0;
        final mins =
            (tier['suspension_duration_minutes'] as num?)?.toInt() ?? 0;
        if (declinesOverLimit >= trigger && trigger >= highestTrigger) {
          highestTrigger = trigger;
          suspensionMinutes = mins;
        }
      }

      if (suspensionMinutes == null || suspensionMinutes <= 0) return;

      final suspendedUntil = DateTime.now().add(
        Duration(minutes: suspensionMinutes),
      );
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'suspended_until': Timestamp.fromDate(suspendedUntil),
        'seekingQuickGigs': false,
        'slot': 'AVAILABLE',
      });

      if (!mounted) return;
      // Only update seekingQuickGigs locally; let the profile listener manage
      // _suspendedUntil and the suspension timer so wasNotSuspended fires once
      // and the suspension dialog is shown exactly once.
      setState(() => _seekingQuickGigs = false);
    } catch (_) {}
  }

  void _startSuspensionTimer() {
    _suspensionTimer?.cancel();
    _suspensionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_suspendedUntil == null || DateTime.now().isAfter(_suspendedUntil!)) {
        _suspensionTimer?.cancel();
        if (mounted) setState(() => _suspendedUntil = null);
        return;
      }
      setState(() {});
    });
  }

  void _showAlreadyActiveGigDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            color: Color(0xFFFFF3CD),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.info_outline_rounded,
            color: Colors.orange,
            size: 28,
          ),
        ),
        title: Text(
          'Finish Your Current Gig First',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(ctx).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          "You need to finish your current gig before applying to or accepting another one.",
          textAlign: TextAlign.center,
          style: TextStyle(color: kSub, fontSize: 14, height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Got it'),
            ),
          ),
        ],
      ),
    );
  }

  void _showSuspensionDialog() {
    if (!mounted || _suspendedUntil == null) return;
    final until = _suspendedUntil!;
    final dateStr =
        '${until.day} ${_monthName(until.month)} ${until.year}'
        ' at ${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            color: Color(0xFFFFEDED),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.block_rounded,
            color: Colors.redAccent,
            size: 28,
          ),
        ),
        title: Text(
          'Account Suspended',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(ctx).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Your account has been temporarily suspended due to excessive gig declines.\n\n'
          'You can resume accepting gigs after:\n$dateStr',
          textAlign: TextAlign.center,
          style: const TextStyle(color: kSub, fontSize: 14, height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                if (mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Understood'),
            ),
          ),
        ],
      ),
    );
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Profile'), elevation: 0),
          body: ProfileTab(
            initialRole: 'worker',
            onSwitchRole: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const HostShell()),
            ),
            onLogout: _performLogout,
          ),
        ),
      ),
    );
  }

  Future<void> _performLogout() async {
    _profileSub?.cancel();
    _dispatchSub?.cancel();
    _offeredGigSub?.cancel();
    if (!mounted) return;
    final clearing = context.read<CurrentUserProvider>().clearUser();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
    await WidgetsBinding.instance.endOfFrame;
    await clearing;
    await GoogleSignIn().disconnect();
    await FirebaseAuth.instance.signOut();
  }

  String _monthName(int m) {
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
    return months[m];
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: (_loading || _awaitingActiveGigRestore)
          ? const Center(
              child: CircularProgressIndicator(color: kBlue, strokeWidth: 2),
            )
          : !_workingUIRouteActive && _activeQuickGig != null
          ? WorkingUI(
              gig: _activeQuickGig!,
              gigCollection: 'quick_gigs',
              onComplete: _finishQuickGig,
              onCancel: _cancelQuickGig,
            )
          : !_workingUIRouteActive && _activeOpenGig != null
          ? WorkingUI(
              gig: _activeOpenGig!,
              gigCollection: 'open_gigs',
              onComplete: _finishOpenGig,
              onCancel: _cancelOpenGig,
            )
          : !_workingUIRouteActive && _activeOfferedGig != null
          ? WorkingUI(
              gig: _activeOfferedGig!,
              gigCollection: 'offered_gigs',
              onComplete: _finishOfferedGig,
              onCancel: _cancelOfferedGig,
            )
          : StreamBuilder<ActiveGigInfo?>(
              stream: _activeGigBarStream,
              builder: (context, activeGigBarSnap) {
                final activeGigForBar = activeGigBarSnap.data;
                final showActiveGigBar =
                    activeGigForBar != null &&
                    _dispatchedGig == null &&
                    _pendingOfferedGig == null;
                return Stack(
                  children: [
                    CustomScrollView(
                      slivers: [
                        // Header + Availability card share one sliver so the
                        // card's Transform.translate can visually overlap the
                        // header's bottom edge — a Transform can't bleed
                        // across a sliver boundary into a neighboring sliver.
                        SliverToBoxAdapter(
                          child: Column(
                            children: [
                              WorkerHeader(
                                userId: _userId,
                                name: _name,
                                email: _email,
                                phone: _phone,
                                photoUrl: _photoUrl,
                                rating: _ratingAsWorker,
                                ratingCount: _ratingCount,
                                memberSince: _memberSince,
                                isDark: isDark,
                                onEdit: _openProfile,
                                isVerified: _isVerified,
                                showBackButton: !widget.isTabRoot,
                                onNotifications: () =>
                                    WorkerNotificationsSheet.show(context),
                              ),
                              Transform.translate(
                                offset: const Offset(0, -24),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: AvailabilityCard(
                                    isOnline: _availableForGigs,
                                    onChanged: (v) {
                                      setState(() => _availableForGigs = v);
                                      _setToggle('availableForGigs', v);
                                    },
                                    isVerified: _isVerified,
                                    onVerificationRequired: () =>
                                        _showWorkerVerificationModal(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            showActiveGigBar ? 32 + 86 : 32,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              // No leading spacer — the availability card's
                              // Transform.translate above already leaves its
                              // own ~24px reserved (unpainted) gap before this.

                              // ── Earnings ───────────────────────────────────
                              EarningsSummaryCard(
                                totalByCurrency: _earningsByCode,
                                weeklyByCurrency: _weeklyByCode,
                                completedGigs: _completedGigs,
                              ),
                              const SizedBox(height: 16),

                              // ── Work preferences ──────────────────────────
                              WorkPreferencesCard(
                                seekingQuickGigs: _seekingQuickGigs,
                                onQuickGigsChanged: _toggleQuickGigs,
                                autoAccept: _autoAccept,
                                onAutoAcceptChanged: (v) {
                                  setState(() => _autoAccept = v);
                                  _setToggle('autoAccept', v);
                                },
                                isVerified: _isVerified,
                                onVerificationRequired: () =>
                                    _showWorkerVerificationModal(context),
                              ),
                              const SizedBox(height: 20),

                              // ── Gig Map ───────────────────────────────────
                              GigMapSection(
                                uid: uid,
                                workerName: _name,
                                seekingQuickGigs: _seekingQuickGigs,
                                onQuickGigStarted: _onQuickGigStarted,
                                onOpenGigApplied: _onOpenGigApplied,
                                isVerified: _isVerified,
                                workerSkills: _skills,
                              ),
                              const SizedBox(height: 16),
                            ]),
                          ),
                        ),
                      ],
                    ),
                    if (_dispatchedGig != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: DispatchOfferCard(
                          gig: _dispatchedGig!,
                          onAccept: () => _acceptDispatch(_dispatchedGig!),
                          onDecline: () => _declineDispatch(_dispatchedGig!),
                        ),
                      ),
                    if (_pendingOfferedGig != null && _dispatchedGig == null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: OfferedGigOfferCard(
                          gig: _pendingOfferedGig!,
                          description: _pendingOfferedGigDesc,
                          skillRequired: _pendingOfferedGigSkill,
                          onAccept: () =>
                              _acceptOfferedGig(_pendingOfferedGig!),
                          onDecline: () =>
                              _declineOfferedGig(_pendingOfferedGig!),
                        ),
                      ),
                    if (showActiveGigBar)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ActiveGigBar(gig: activeGigForBar),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

void _showWorkerVerificationModal(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
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
            'Account not Verified',
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
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    ),
  );
}
