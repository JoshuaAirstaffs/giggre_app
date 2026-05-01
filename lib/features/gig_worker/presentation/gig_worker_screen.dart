import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/login_screen.dart';
import 'widgets/dispatch_offer_card.dart';
import 'widgets/earnings_card.dart';
import 'widgets/gig_map_section.dart';
import 'widgets/quick_gig_power_button.dart';
import 'widgets/toggles_card.dart';
import 'widgets/worker_header.dart';
import 'widgets/worker_widgets.dart';
import 'widgets/working_ui.dart';
import 'widgets/offered_gig_offer_card.dart';
import 'widgets/toolchest_sheet.dart';
import 'gig_history_screen.dart';
import 'worker_ratings_screen.dart';
import 'widgets/worker_notifications_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Main screen
// ─────────────────────────────────────────────────────────────────────────────
class GigWorkerScreen extends StatefulWidget {
  const GigWorkerScreen({super.key});

  @override
  State<GigWorkerScreen> createState() => _GigWorkerScreenState();
}

class _GigWorkerScreenState extends State<GigWorkerScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  String _isVerified = '';

  // Profile data
  String _userId = '';
  String _name = '';
  String _email = '';
  String _phone = '';
  String _bio = '';
  String _photoUrl = '';
  List<String> _skills = [];
  double _ratingAsWorker = 5.0;
  int _ratingCount = 0;
  String _memberSince = '';

  // Toggles
  bool _availableForGigs = false;
  bool _autoAccept = false;
  bool _seekingQuickGigs = false;

  // Earnings
  double _totalEarnings = 0;
  double _weeklyEarnings = 0;
  int _completedGigs = 0;

  // Active gigs (when working)
  GigMarkerData? _activeQuickGig;
  GigMarkerData? _activeOpenGig;
  GigMarkerData? _activeOfferedGig;

  // Incoming dispatch offer (quick gig)
  GigMarkerData? _dispatchedGig;

  // Incoming offered gig (direct personal offer from host)
  GigMarkerData? _pendingOfferedGig;
  String _pendingOfferedGigDesc = '';
  String _pendingOfferedGigSkill = '';

  StreamSubscription? _dispatchSub;
  StreamSubscription? _offeredGigSub;
  StreamSubscription? _profileSub;

  // Earnings streams
  final List<StreamSubscription> _earningsSubs = [];
  final Map<String, List<Map<String, dynamic>>> _gigsByCollection = {};

  // Decline suspension
  DateTime? _suspendedUntil;
  Timer? _suspensionTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToProfile();
    _setOnlineStatus(true);
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _dispatchSub?.cancel();
    _offeredGigSub?.cancel();
    _suspensionTimer?.cancel();
    for (final sub in _earningsSubs) {
      sub.cancel();
    }
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
      if (uid != null) _checkForActiveGig(uid);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _setOnlineStatus(false);
    }
  }

  Future<void> _setOnlineStatus(bool online) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'isOnline': online});
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
        _bio = data['bio'] as String? ?? '';
        _photoUrl = data['photoUrl'] as String? ?? '';
        _skills = List<String>.from(data['skills'] ?? []);
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
      });

      if (isFirstLoad) {
        _startEarningsSubs(uid);
        _saveLocationToFirestore();
        _startDispatchSub(uid);
        _startOfferedGigSub(uid);
        _checkForActiveGig(uid);
      }

      if (suspendedUntil != null) {
        _startSuspensionTimer();
        if (wasNotSuspended) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _showSuspensionDialog());
        }
      }
    }, onError: (e) => debugPrint('[GigWorker] profile stream error: $e'));
  }

  void _startEarningsSubs(String uid) {
    for (final sub in _earningsSubs) {
      sub.cancel();
    }
    _earningsSubs.clear();
    _gigsByCollection.clear();

    final now = DateTime.now();
    final weekStartMidnight = DateTime(
      now.year,
      now.month,
      now.day - (now.weekday - 1),
    );

    void recalculate() {
      double total = 0, weekly = 0;
      int completed = 0;
      for (final gigs in _gigsByCollection.values) {
        for (final gig in gigs) {
          final budget = (gig['budget'] as num?)?.toDouble() ?? 0;
          total += budget;
          completed++;
          final ts = gig['completedAt'] as Timestamp?;
          if (ts != null && ts.toDate().isAfter(weekStartMidnight)) {
            weekly += budget;
          }
        }
      }
      if (mounted) {
        setState(() {
          _totalEarnings = total;
          _weeklyEarnings = weekly;
          _completedGigs = completed;
        });
      }
    }

    for (final col in ['quick_gigs', 'open_gigs', 'offered_gigs']) {
      final sub = FirebaseFirestore.instance
          .collection(col)
          .where('workerId', isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .snapshots()
          .listen((snap) {
        _gigsByCollection[col] =
            snap.docs.map((d) => d.data()).toList();
        recalculate();
      }, onError: (e) => debugPrint('[GigWorker] earnings stream error: $e'));
      _earningsSubs.add(sub);
    }
  }

  /// On app resume/init, restore WorkingUI if worker has an ongoing gig.
  Future<void> _checkForActiveGig(String uid) async {
    if (_activeQuickGig != null ||
        _activeOpenGig != null ||
        _activeOfferedGig != null) return;
    const activeStatuses = [
      'navigating', 'arrived', 'working', 'task_complete', 'payment', 'cancellation_requested', 
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
          setState(() => _activeQuickGig = GigMarkerData(
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
          ));
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
          setState(() => _activeOpenGig = GigMarkerData(
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
          ));
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
          setState(() => _activeOfferedGig = GigMarkerData(
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
          ));
        }
      }
    } catch (_) {}
  }

  // ── Offered gig stream — listens for pending direct offers ────────────────
  void _startOfferedGigSub(String uid) {
    _offeredGigSub?.cancel();
    _offeredGigSub = FirebaseFirestore.instance
        .collection('offered_gigs')
        .where('workerId', isEqualTo: uid)
        .where('status', isEqualTo: 'offered')
        .snapshots()
        .listen((snap) {
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
        );
        _pendingOfferedGigDesc = data['description'] as String? ?? '';
        _pendingOfferedGigSkill = data['skillRequired'] as String? ?? '';
      });
    }, onError: (e) => debugPrint('[GigWorker] offered gig stream error: $e'));
  }

  Future<void> _acceptOfferedGig(GigMarkerData gig) async {
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
          perm == LocationPermission.deniedForever) { return; }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'location': GeoPoint(pos.latitude, pos.longitude),
      });
    } catch (_) {}
  }

  Future<void> _setToggle(String field, bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({field: value});
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

  void _onQuickGigStarted(GigMarkerData gig) {
    setState(() => _activeQuickGig = gig);
  }

  void _onOpenGigApplied(GigMarkerData gig) {
    setState(() => _activeOpenGig = gig);
  }

  Future<void> _finishOpenGig() async {
    if (mounted) setState(() => _activeOpenGig = null);
  }

  Future<void> _cancelOpenGig() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && _activeOpenGig != null) {
      await FirebaseFirestore.instance
          .collection('open_gigs')
          .doc(_activeOpenGig!.id)
          .update({
        'status': 'open',
        'workerId': FieldValue.delete(),
      });
    }
    if (mounted) setState(() => _activeOpenGig = null);
  }

  Future<void> _acceptDispatch(GigMarkerData gig) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
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
    }
  }

  Future<void> _declineDispatch(GigMarkerData gig) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final currentDeclineCount =
        (userSnap.data()?['decline_count'] as num?)?.toInt() ?? 0;

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
        'decline_count': FieldValue.increment(1),
      }),
    ]);
    if (mounted) setState(() => _dispatchedGig = null);
    await _checkAndApplySuspension(uid, currentDeclineCount + 1);
  }

  // Called by WorkingUI when Firestore status becomes 'completed' (set by host).
  // Host already updated the gig doc; we only reset the worker's slot here.
  Future<void> _finishQuickGig() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'slot': 'AVAILABLE'});
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
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'slot': 'AVAILABLE'});
    }
    if (mounted) setState(() => _activeQuickGig = null);
  }

  Future<void> _checkAndApplySuspension(
      String uid, int newDeclineCount) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('quick_gig_config')
          .doc('decline_suspension')
          .get();
      final data = doc.data() ?? {};
      final freeLimit =
          (data['free_decline_limit'] as num?)?.toInt() ?? 0;

      if (newDeclineCount <= freeLimit) return;

      final tierTable =
          data['suspension_tier_table'] as List<dynamic>? ?? [];
      if (tierTable.isEmpty) return;

      // Find the highest matching tier
      int? suspensionMinutes;
      int highestTrigger = 0;
      for (final tier in tierTable) {
        final trigger =
            (tier['decline_count_trigger'] as num?)?.toInt() ?? 0;
        final mins =
            (tier['suspension_duration_minutes'] as num?)?.toInt() ?? 0;
        if (newDeclineCount >= trigger && trigger >= highestTrigger) {
          highestTrigger = trigger;
          suspensionMinutes = mins;
        }
      }

      if (suspensionMinutes == null || suspensionMinutes <= 0) return;

      final suspendedUntil =
          DateTime.now().add(Duration(minutes: suspensionMinutes));
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'suspended_until': Timestamp.fromDate(suspendedUntil),
        'seekingQuickGigs': false,
        'slot': 'AVAILABLE',
      });

      if (!mounted) return;
      setState(() {
        _suspendedUntil = suspendedUntil;
        _seekingQuickGigs = false;
      });
      _startSuspensionTimer();
    } catch (_) {}
  }

  void _startSuspensionTimer() {
    _suspensionTimer?.cancel();
    _suspensionTimer =
        Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_suspendedUntil == null ||
          DateTime.now().isAfter(_suspendedUntil!)) {
        _suspensionTimer?.cancel();
        if (mounted) setState(() => _suspendedUntil = null);
        return;
      }
      setState(() {});
    });
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            color: Color(0xFFFFEDED),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.block_rounded,
              color: Colors.redAccent, size: 28),
        ),
        title: Text(
          'Account Suspended',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Theme.of(ctx).colorScheme.onSurface,
              fontWeight: FontWeight.bold),
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
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Understood'),
            ),
          ),
        ],
      ),
    );
  }

  void _showComingSoon(String title) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(ctx).dividerColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: kBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.construction_rounded,
                  color: kBlue, size: 24),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('This feature is coming soon!',
                style: TextStyle(color: kSub, fontSize: 14)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditPersonalInfo() {
    final nameCtrl = TextEditingController(text: _name);
    final phoneCtrl = TextEditingController(text: _phone);
    final bioCtrl = TextEditingController(text: _bio);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final cardColor =
              isDark ? const Color(0xFF1E2533) : Colors.white;
          final onSurface = Theme.of(ctx).colorScheme.onSurface;
          bool saving = false;

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Theme.of(ctx).dividerColor),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Edit Profile',
                          style: TextStyle(
                              color: onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.grey.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close_rounded,
                              color: onSurface, size: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _EditField(
                      label: 'Name',
                      controller: nameCtrl,
                      isDark: isDark),
                  const SizedBox(height: 12),
                  _EditField(
                      label: 'Phone',
                      controller: phoneCtrl,
                      isDark: isDark,
                      keyboardType: TextInputType.phone),
                  const SizedBox(height: 12),
                  _EditField(
                      label: 'Bio',
                      controller: bioCtrl,
                      isDark: isDark,
                      maxLines: 3),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: StatefulBuilder(
                      builder: (_, setSave) => ElevatedButton(
                        onPressed: saving
                            ? null
                            : () async {
                                setSave(() => saving = true);
                                final uid = FirebaseAuth
                                    .instance.currentUser?.uid;
                                if (uid != null) {
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(uid)
                                      .update({
                                    'name': nameCtrl.text.trim(),
                                    'phone': phoneCtrl.text.trim(),
                                    'bio': bioCtrl.text.trim(),
                                  });
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Save Changes',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('Log out',
            style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurface)),
        content: const Text('Are you sure you want to log out?',
            style: TextStyle(color: kSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: kSub)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _profileSub?.cancel();
              _dispatchSub?.cancel();
              _offeredGigSub?.cancel();
              for (final sub in _earningsSubs) { sub.cancel(); }
              _earningsSubs.clear();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
              await WidgetsBinding.instance.endOfFrame;
              await FirebaseAuth.instance.signOut();
            },
            child: const Text('Log out',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  String _monthName(int m) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[m];
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: kBlue, strokeWidth: 2))
          : _activeQuickGig != null
          ? WorkingUI(
              gig: _activeQuickGig!,
              gigCollection: 'quick_gigs',
              onComplete: _finishQuickGig,
              onCancel: _cancelQuickGig,
            )
          : _activeOpenGig != null
          ? WorkingUI(
              gig: _activeOpenGig!,
              gigCollection: 'open_gigs',
              onComplete: _finishOpenGig,
              onCancel: _cancelOpenGig,
            )
          : _activeOfferedGig != null
          ? WorkingUI(
              gig: _activeOfferedGig!,
              gigCollection: 'offered_gigs',
              onComplete: _finishOfferedGig,
              onCancel: _cancelOfferedGig,
            )
          : Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: WorkerHeader(
                        userId: _userId,
                        name: _name,
                        email: _email,
                        phone: _phone,
                        photoUrl: _photoUrl,
                        rating: _ratingAsWorker,
                        ratingCount: _ratingCount,
                        memberSince: _memberSince,
                        isDark: isDark,
                        onEdit: _showEditPersonalInfo,
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          const SizedBox(height: 20),

                          // ── Power button ──────────────────────────────
                          QuickGigPowerButton(
                            active: _seekingQuickGigs,
                            onChanged: _toggleQuickGigs,
                            isVerified: _isVerified,
                          ),
                          const SizedBox(height: 16),

                          // ── Earnings ──────────────────────────────────
                          EarningsCard(
                            totalEarnings: _totalEarnings,
                            weeklyEarnings: _weeklyEarnings,
                            completedGigs: _completedGigs,
                          ),
                          const SizedBox(height: 16),

                          // ── Toggles ───────────────────────────────────
                          SectionLabel('Status & Preferences'),
                          const SizedBox(height: 8),
                          TogglesCard(
                            availableForGigs: _availableForGigs,
                            autoAccept: _autoAccept,
                            onAvailableChanged: (v) {
                              setState(() => _availableForGigs = v);
                              _setToggle('availableForGigs', v);
                            },
                            onAutoAcceptChanged: (v) {
                              setState(() => _autoAccept = v);
                              _setToggle('autoAccept', v);
                            },
                            isVerified: _isVerified,
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
                          ),
                          const SizedBox(height: 20),

                          // ── Toolchest ─────────────────────────────────
                          SectionLabel('My Toolchest'),
                          const SizedBox(height: 8),
                          ToolchestCard(
                            skills: _skills,
                            onTap: () => ToolchestSheet.show(context, uid),
                          ),
                          const SizedBox(height: 20),

                          // ── Account ───────────────────────────────────
                          SectionLabel('Account'),
                          const SizedBox(height: 8),
                          MenuCard(children: [
                            MenuRow(
                              icon: Icons.history_rounded,
                              iconColor: kBlue,
                              label: 'Gig History',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const GigHistoryScreen(),
                                ),
                              ),
                            ),
                            const WorkerDivider(),
                            MenuRow(
                              icon: Icons.star_rounded,
                              iconColor: kAmber,
                              label: 'Ratings & Reviews',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const WorkerRatingsScreen(),
                                ),
                              ),
                            ),
                            const WorkerDivider(),
                            MenuRow(
                              icon: Icons.notifications_outlined,
                              iconColor: const Color(0xFF8B5CF6),
                              label: 'Notifications',
                              onTap: () =>
                                  WorkerNotificationsSheet.show(context),
                            ),
                          ]),
                          const SizedBox(height: 12),

                          // ── Settings ──────────────────────────────────
                          SectionLabel('Settings'),
                          const SizedBox(height: 8),
                          MenuCard(children: [
                            MenuRow(
                              icon: Icons.settings_outlined,
                              iconColor: kSub,
                              label: 'Settings',
                              onTap: () => _showComingSoon('Settings'),
                            ),
                            const WorkerDivider(),
                            MenuRow(
                              icon: Icons.help_outline_rounded,
                              iconColor: kBlue,
                              label: 'Help & Support',
                              onTap: () =>
                                  _showComingSoon('Help & Support'),
                            ),
                          ]),
                          const SizedBox(height: 12),

                          // ── Logout ────────────────────────────────────
                          MenuCard(children: [
                            MenuRow(
                              icon: Icons.logout_rounded,
                              iconColor: Colors.redAccent,
                              label: 'Log out',
                              labelColor: Colors.redAccent,
                              onTap: _confirmLogout,
                              showArrow: false,
                            ),
                          ]),
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
                      onAccept: () => _acceptOfferedGig(_pendingOfferedGig!),
                      onDecline: () => _declineOfferedGig(_pendingOfferedGig!),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reusable labeled text field for the edit profile sheet
// ─────────────────────────────────────────────────────────────────────────────
class _EditField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool isDark;
  final TextInputType keyboardType;
  final int maxLines;

  const _EditField({
    required this.label,
    required this.controller,
    required this.isDark,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: kSub,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.grey.withValues(alpha: 0.07),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.grey.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.grey.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kBlue),
            ),
          ),
        ),
      ],
    );
  }
}
