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

  // Profile data
  String _name = '';
  String _email = '';
  String _bio = '';
  String _photoUrl = '';
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

  // Active quick gig (when working)
  GigMarkerData? _activeQuickGig;

  // Incoming dispatch offer
  GigMarkerData? _dispatchedGig;
  StreamSubscription? _dispatchSub;

  // Decline suspension
  DateTime? _suspendedUntil;
  Timer? _suspensionTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfile();
    _setOnlineStatus(true);
  }

  @override
  void dispose() {
    _dispatchSub?.cancel();
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

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = doc.data() ?? {};

    double total = 0, weekly = 0;
    int completed = 0;
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartMidnight =
        DateTime(weekStart.year, weekStart.month, weekStart.day);

    try {
      for (final col in ['quick_gigs', 'open_gigs', 'offered_gigs']) {
        final snap = await FirebaseFirestore.instance
            .collection(col)
            .where('workerId', isEqualTo: uid)
            .where('status', isEqualTo: 'completed')
            .get();
        for (final d in snap.docs) {
          final gig = d.data();
          final budget = (gig['budget'] as num?)?.toDouble() ?? 0;
          total += budget;
          completed++;
          final ts = gig['completedAt'] as Timestamp?;
          if (ts != null && ts.toDate().isAfter(weekStartMidnight)) {
            weekly += budget;
          }
        }
      }
    } catch (_) {}

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
    setState(() {
      _name = data['name'] as String? ?? '';
      _email = data['email'] as String? ?? '';
      _bio = data['bio'] as String? ?? '';
      _photoUrl = data['photoUrl'] as String? ?? '';
      _ratingAsWorker =
          (data['ratingAsWorker'] as num?)?.toDouble() ?? 5.0;
      _ratingCount = (data['ratingCount'] as num?)?.toInt() ?? 0;
      _availableForGigs = data['availableForGigs'] as bool? ?? false;
      _autoAccept = data['autoAccept'] as bool? ?? false;
      _seekingQuickGigs = data['seekingQuickGigs'] as bool? ?? false;
      _memberSince = memberSince;
      _totalEarnings = total;
      _weeklyEarnings = weekly;
      _completedGigs = completed;
      _suspendedUntil = suspendedUntil;
      _loading = false;
    });
    _saveLocationToFirestore();
    _startDispatchSub(uid);
    if (_suspendedUntil != null) {
      _startSuspensionTimer();
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showSuspensionDialog());
    }
    await _checkForActiveGig(uid);
  }

  /// On app resume/init, restore WorkingUI if worker has an ongoing gig.
  Future<void> _checkForActiveGig(String uid) async {
    // Skip if already showing an active gig
    if (_activeQuickGig != null) return;
    const activeStatuses = [
      'navigating', 'arrived', 'working', 'task_complete', 'payment'
    ];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('quick_gigs')
          .where('workerId', isEqualTo: uid)
          .where('status', whereIn: activeStatuses)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return;
      final doc = snap.docs.first;
      final data = doc.data();
      final geo = data['location'] as GeoPoint?;
      if (geo == null) return;
      final gig = GigMarkerData(
        id: doc.id,
        title: data['title'] as String? ?? 'Quick Gig',
        gigType: 'quick',
        budget: (data['budget'] as num?)?.toDouble() ?? 0,
        status: data['status'] as String? ?? 'navigating',
        hostName: data['hostName'] as String? ?? '',
        address: data['address'] as String? ?? '',
        position: LatLng(geo.latitude, geo.longitude),
        assignedWorkerId: uid,
      );
      if (mounted) setState(() => _activeQuickGig = gig);
    } catch (_) {}
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
      );
      // Auto-accept: skip review window and accept immediately
      if (_autoAccept) {
        _acceptDispatch(gig);
        return;
      }
      setState(() => _dispatchedGig = gig);
    });
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
              await FirebaseAuth.instance.signOut();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
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
              onComplete: _finishQuickGig,
              onCancel: _cancelQuickGig,
            )
          : Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: WorkerHeader(
                        name: _name,
                        email: _email,
                        photoUrl: _photoUrl,
                        rating: _ratingAsWorker,
                        ratingCount: _ratingCount,
                        memberSince: _memberSince,
                        isDark: isDark,
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
                          ),
                          const SizedBox(height: 20),

                          // ── Gig Map ───────────────────────────────────
                          GigMapSection(
                            uid: uid,
                            seekingQuickGigs: _seekingQuickGigs,
                            onQuickGigStarted: _onQuickGigStarted,
                          ),
                          const SizedBox(height: 20),

                          // ── Toolchest ─────────────────────────────────
                          SectionLabel('My Toolchest'),
                          const SizedBox(height: 8),
                          ToolchestCard(
                            bio: _bio,
                            onTap: () => _showComingSoon('Toolchest'),
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
                              onTap: () => _showComingSoon('Gig History'),
                            ),
                            const WorkerDivider(),
                            MenuRow(
                              icon: Icons.star_rounded,
                              iconColor: kAmber,
                              label: 'Ratings & Reviews',
                              onTap: () =>
                                  _showComingSoon('Ratings & Reviews'),
                            ),
                            const WorkerDivider(),
                            MenuRow(
                              icon: Icons.notifications_outlined,
                              iconColor: const Color(0xFF8B5CF6),
                              label: 'Notifications',
                              onTap: () =>
                                  _showComingSoon('Notifications'),
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
              ],
            ),
    );
  }
}
