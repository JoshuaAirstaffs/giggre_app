import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/login_screen.dart';

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
  _GigMarkerData? _activeQuickGig;

  // Incoming dispatch offer
  _GigMarkerData? _dispatchedGig;
  StreamSubscription? _dispatchSub;

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
    _setOnlineStatus(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setOnlineStatus(true);
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
      _loading = false;
    });
    _saveLocationToFirestore();
    _startDispatchSub(uid);
  }

  void _startDispatchSub(String uid) {
    _dispatchSub?.cancel();
    _dispatchSub = FirebaseFirestore.instance
        .collection('quick_gigs')
        .where('assignedWorkerId', isEqualTo: uid)
        .where('status', isEqualTo: 'dispatched')
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
      setState(() {
        _dispatchedGig = _GigMarkerData(
          id: doc.id,
          title: data['title'] as String? ?? 'Quick Gig',
          gigType: 'quick',
          budget: (data['budget'] as num?)?.toDouble() ?? 0,
          status: 'dispatched',
          hostName: data['hostName'] as String? ?? '',
          address: data['address'] as String? ?? '',
          position: LatLng(geo.latitude, geo.longitude),
          assignedWorkerId: uid,
        );
      });
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
          perm == LocationPermission.deniedForever) return;
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

  void _onQuickGigStarted(_GigMarkerData gig) {
    setState(() => _activeQuickGig = gig);
  }

  Future<void> _acceptDispatch(_GigMarkerData gig) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('quick_gigs')
        .doc(gig.id)
        .update({
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
      'workerId': uid,
    });
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'slot': 'BUSY',
      'acceptanceRate': FieldValue.increment(0.02),
    });
    if (mounted) {
      setState(() {
        _dispatchedGig = null;
        _activeQuickGig = gig;
      });
    }
  }

  Future<void> _declineDispatch(_GigMarkerData gig) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('quick_gigs')
        .doc(gig.id)
        .update({
      'status': 'scanning',
      'assignedWorkerId': FieldValue.delete(),
      'assignedWorkerName': FieldValue.delete(),
      'exclusionList': FieldValue.arrayUnion([uid]),
    });
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'acceptanceRate': FieldValue.increment(-0.10),
    });
    if (mounted) setState(() => _dispatchedGig = null);
  }

  Future<void> _finishQuickGig() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && _activeQuickGig != null) {
      await FirebaseFirestore.instance
          .collection('quick_gigs')
          .doc(_activeQuickGig!.id)
          .update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'workerId': uid,
      });
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
          ? _WorkingUI(
              gig: _activeQuickGig!,
              onComplete: _finishQuickGig,
              onCancel: _cancelQuickGig,
            )
          : Stack(
              children: [
                CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(
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
                      _QuickGigPowerButton(
                        active: _seekingQuickGigs,
                        onChanged: _toggleQuickGigs,
                      ),
                      const SizedBox(height: 16),

                      // ── Earnings ──────────────────────────────────
                      _EarningsCard(
                        totalEarnings: _totalEarnings,
                        weeklyEarnings: _weeklyEarnings,
                        completedGigs: _completedGigs,
                      ),
                      const SizedBox(height: 16),

                      // ── Toggles ───────────────────────────────────
                      _SectionLabel('Status & Preferences'),
                      const SizedBox(height: 8),
                      _TogglesCard(
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
                      _GigMapSection(
                        uid: uid,
                        seekingQuickGigs: _seekingQuickGigs,
                        onQuickGigStarted: _onQuickGigStarted,
                      ),
                      const SizedBox(height: 20),

                      // ── Toolchest ─────────────────────────────────
                      _SectionLabel('My Toolchest'),
                      const SizedBox(height: 8),
                      _ToolchestCard(
                        bio: _bio,
                        onTap: () => _showComingSoon('Toolchest'),
                      ),
                      const SizedBox(height: 20),

                      // ── Account ───────────────────────────────────
                      _SectionLabel('Account'),
                      const SizedBox(height: 8),
                      _MenuCard(children: [
                        _MenuRow(
                          icon: Icons.history_rounded,
                          iconColor: kBlue,
                          label: 'Gig History',
                          onTap: () => _showComingSoon('Gig History'),
                        ),
                        _Divider(),
                        _MenuRow(
                          icon: Icons.star_rounded,
                          iconColor: kAmber,
                          label: 'Ratings & Reviews',
                          onTap: () =>
                              _showComingSoon('Ratings & Reviews'),
                        ),
                        _Divider(),
                        _MenuRow(
                          icon: Icons.notifications_outlined,
                          iconColor: const Color(0xFF8B5CF6),
                          label: 'Notifications',
                          onTap: () => _showComingSoon('Notifications'),
                        ),
                      ]),
                      const SizedBox(height: 12),

                      // ── Settings ──────────────────────────────────
                      _SectionLabel('Settings'),
                      const SizedBox(height: 8),
                      _MenuCard(children: [
                        _MenuRow(
                          icon: Icons.settings_outlined,
                          iconColor: kSub,
                          label: 'Settings',
                          onTap: () => _showComingSoon('Settings'),
                        ),
                        _Divider(),
                        _MenuRow(
                          icon: Icons.help_outline_rounded,
                          iconColor: kBlue,
                          label: 'Help & Support',
                          onTap: () => _showComingSoon('Help & Support'),
                        ),
                      ]),
                      const SizedBox(height: 12),

                      // ── Logout ────────────────────────────────────
                      _MenuCard(children: [
                        _MenuRow(
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
                    child: _DispatchOfferCard(
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

// ─────────────────────────────────────────────────────────────────────────────
//  Dispatch Offer Card
// ─────────────────────────────────────────────────────────────────────────────
class _DispatchOfferCard extends StatefulWidget {
  final _GigMarkerData gig;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _DispatchOfferCard({
    required this.gig,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<_DispatchOfferCard> createState() => _DispatchOfferCardState();
}

class _DispatchOfferCardState extends State<_DispatchOfferCard> {
  late Timer _timer;
  int _seconds = 30;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds--);
      if (_seconds <= 0) {
        _timer.cancel();
        widget.onDecline();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final divider = Theme.of(context).dividerColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const green = Color(0xFF22C55E);

    final timerColor = _seconds > 20
        ? green
        : _seconds > 10
            ? kAmber
            : Colors.redAccent;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kAmber.withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: kAmber.withValues(alpha: isDark ? 0.2 : 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kAmber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.flash_on_rounded,
                    color: kAmber, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick Gig Offer!',
                      style: TextStyle(
                          color: kAmber,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5),
                    ),
                    Text(
                      widget.gig.title,
                      style: TextStyle(
                          color: onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: timerColor, width: 2),
                  color: timerColor.withValues(alpha: 0.1),
                ),
                child: Center(
                  child: Text(
                    '$_seconds',
                    style: TextStyle(
                        color: timerColor,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: divider),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, color: kSub, size: 14),
              const SizedBox(width: 6),
              Text(
                widget.gig.hostName.isNotEmpty ? widget.gig.hostName : 'Host',
                style: const TextStyle(color: kSub, fontSize: 12),
              ),
              const SizedBox(width: 16),
              const Icon(Icons.attach_money_rounded, color: kAmber, size: 14),
              Text(
                '₱${widget.gig.budget.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: kAmber,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (widget.gig.address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: kSub, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.gig.address,
                    style: const TextStyle(color: kSub, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kSub,
                    side: BorderSide(color: divider),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Decline',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: widget.onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Accept Gig',
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

// ─────────────────────────────────────────────────────────────────────────────
//  Power button — Start Quick Gigs
// ─────────────────────────────────────────────────────────────────────────────
class _QuickGigPowerButton extends StatelessWidget {
  final bool active;
  final ValueChanged<bool> onChanged;
  const _QuickGigPowerButton(
      {required this.active, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final cardColor = Theme.of(context).cardColor;
    final divider = Theme.of(context).dividerColor;
    const green = Color(0xFF22C55E);
    final activeColor = active ? green : kSub;

    return GestureDetector(
      onTap: () => onChanged(!active),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: active
              ? green.withValues(alpha: 0.07)
              : cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active
                ? green.withValues(alpha: 0.5)
                : divider,
            width: active ? 1.5 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: green.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            // Power icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: activeColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: green.withValues(alpha: 0.3),
                          blurRadius: 14,
                          spreadRadius: 2,
                        )
                      ]
                    : [],
              ),
              child: Icon(
                Icons.power_settings_new_rounded,
                color: activeColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Start Quick Gigs',
                    style: TextStyle(
                        color: onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    active
                        ? 'Quick Gig: On — waiting for nearby gigs...'
                        : 'Tap to go online and receive quick gig offers',
                    style: const TextStyle(color: kSub, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: activeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: activeColor.withValues(alpha: 0.5)),
              ),
              child: Text(
                active ? 'ON' : 'OFF',
                style: TextStyle(
                    color: activeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gig Map Section
// ─────────────────────────────────────────────────────────────────────────────
class _GigMarkerData {
  final String id;
  final String title;
  final String gigType; // 'quick' | 'open' | 'offered'
  final double budget;
  final String status;
  final String hostName;
  final String address;
  final LatLng position;
  final String? assignedWorkerId;

  const _GigMarkerData({
    required this.id,
    required this.title,
    required this.gigType,
    required this.budget,
    required this.status,
    required this.hostName,
    required this.address,
    required this.position,
    this.assignedWorkerId,
  });
}

class _GigCluster {
  final LatLng center;
  final int count;
  final _GigMarkerData? singleGig;
  final List<_GigMarkerData> gigs;

  const _GigCluster({
    required this.center,
    required this.count,
    required this.gigs,
    this.singleGig,
  });
}

class _GigMapSection extends StatefulWidget {
  final String uid;
  final bool seekingQuickGigs;
  final ValueChanged<_GigMarkerData>? onQuickGigStarted;

  const _GigMapSection({
    required this.uid,
    required this.seekingQuickGigs,
    this.onQuickGigStarted,
  });

  @override
  State<_GigMapSection> createState() => _GigMapSectionState();
}

class _GigMapSectionState extends State<_GigMapSection> {
  final _mapController = MapController();
  double _zoom = 12.0;
  LatLng? _myLocation;

  List<_GigMarkerData> _quickGigs = [];
  List<_GigMarkerData> _openGigs = [];
  List<_GigMarkerData> _offeredGigs = [];

  StreamSubscription? _quickSub;
  late StreamSubscription _openSub, _offeredSub;

  @override
  void initState() {
    super.initState();
    final db = FirebaseFirestore.instance;
    _startOpenSub(db);
    _startOfferedSub(db);
    if (widget.seekingQuickGigs) _startQuickSub(db);
    _fetchAndCenterMap();
  }

  Future<void> _fetchAndCenterMap() async {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      _mapController.move(_myLocation!, 14.0);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(_GigMapSection old) {
    super.didUpdateWidget(old);
    if (old.seekingQuickGigs != widget.seekingQuickGigs) {
      if (widget.seekingQuickGigs) {
        _startQuickSub(FirebaseFirestore.instance);
      } else {
        _quickSub?.cancel();
        _quickSub = null;
        setState(() => _quickGigs = []);
      }
    }
  }

  void _startQuickSub(FirebaseFirestore db) {
    _quickSub = db
        .collection('quick_gigs')
        .where('status', whereIn: ['scanning', 'dispatched'])
        .snapshots()
        .listen((s) {
      final all = s.docs.map((d) {
        final data = d.data();
        final status = data['status'] as String? ?? '';
        // Only show dispatched gigs assigned to this worker
        if (status == 'dispatched' &&
            data['assignedWorkerId'] != widget.uid) {
          return null;
        }
        return _toMarker(d.id, data, 'quick');
      }).whereType<_GigMarkerData>().toList();
      setState(() => _quickGigs = all);
    });
  }

  void _startOpenSub(FirebaseFirestore db) {
    _openSub = db
        .collection('open_gigs')
        .where('status', isEqualTo: 'open')
        .snapshots()
        .listen((s) {
      setState(() {
        _openGigs = s.docs
            .map((d) => _toMarker(d.id, d.data(), 'open'))
            .whereType<_GigMarkerData>()
            .toList();
      });
    });
  }

  void _startOfferedSub(FirebaseFirestore db) {
    _offeredSub = db
        .collection('offered_gigs')
        .where('workerId', isEqualTo: widget.uid)
        .where('status', isEqualTo: 'offered')
        .snapshots()
        .listen((s) {
      setState(() {
        _offeredGigs = s.docs
            .map((d) => _toMarker(d.id, d.data(), 'offered'))
            .whereType<_GigMarkerData>()
            .toList();
      });
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    _quickSub?.cancel();
    _openSub.cancel();
    _offeredSub.cancel();
    super.dispose();
  }

  _GigMarkerData? _toMarker(
      String id, Map<String, dynamic> data, String type) {
    final geo = data['location'] as GeoPoint?;
    if (geo == null) return null;
    return _GigMarkerData(
      id: id,
      title: data['title'] as String? ?? 'Untitled Gig',
      gigType: type,
      budget: (data['budget'] as num?)?.toDouble() ?? 0,
      status: data['status'] as String? ?? '',
      hostName: data['hostName'] as String? ?? '',
      address: data['address'] as String? ?? '',
      position: LatLng(geo.latitude, geo.longitude),
      assignedWorkerId: data['assignedWorkerId'] as String?,
    );
  }

  List<_GigMarkerData> get _allGigs =>
      [..._quickGigs, ..._openGigs, ..._offeredGigs];

  static double _gridSize(double zoom) {
    if (zoom < 10) return 0.15;
    if (zoom < 11) return 0.08;
    if (zoom < 12) return 0.04;
    if (zoom < 13) return 0.02;
    if (zoom < 14) return 0.008;
    return 0.0;
  }

  List<_GigCluster> _buildClusters() {
    final all = _allGigs;
    final gridSize = _gridSize(_zoom);

    if (gridSize == 0.0) {
      return all
          .map((g) => _GigCluster(
                center: g.position,
                count: 1,
                gigs: [g],
                singleGig: g,
              ))
          .toList();
    }

    final Map<String, List<_GigMarkerData>> grid = {};
    for (final g in all) {
      final latKey = (g.position.latitude / gridSize).floor();
      final lngKey = (g.position.longitude / gridSize).floor();
      grid.putIfAbsent('$latKey:$lngKey', () => []).add(g);
    }

    return grid.values.map((group) {
      final avgLat =
          group.fold(0.0, (s, g) => s + g.position.latitude) /
              group.length;
      final avgLng =
          group.fold(0.0, (s, g) => s + g.position.longitude) /
              group.length;
      return _GigCluster(
        center: LatLng(avgLat, avgLng),
        count: group.length,
        gigs: group,
        singleGig: group.length == 1 ? group.first : null,
      );
    }).toList();
  }

  List<Marker> _buildMarkers() {
    return _buildClusters().map((cluster) {
      if (cluster.count == 1 && cluster.singleGig != null) {
        final singleGig = cluster.singleGig!;
        return Marker(
          point: cluster.center,
          width: 40,
          height: 48,
          child: _GigPin(
            gig: singleGig,
            onStart: singleGig.gigType == 'quick' &&
                    singleGig.assignedWorkerId == widget.uid
                ? () => widget.onQuickGigStarted?.call(singleGig)
                : null,
          ),
        );
      }
      return Marker(
        point: cluster.center,
        width: 60,
        height: 60,
        child: _GigClusterBadge(
          count: cluster.count,
          gigs: cluster.gigs,
          onQuickGigStarted: widget.onQuickGigStarted,
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final borderColor = Theme.of(context).dividerColor;
    final total = _allGigs.length;
    final offeredCount = _offeredGigs.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            Expanded(
              child: Text('Gigs Near You',
                  style: TextStyle(
                      color: onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
            ),
            if (offeredCount > 0)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color:
                          const Color(0xFF8B5CF6).withValues(alpha: 0.4)),
                ),
                child: Text(
                  '$offeredCount Offered',
                  style: const TextStyle(
                      color: Color(0xFF8B5CF6),
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: kAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: kAmber.withValues(alpha: 0.4)),
              ),
              child: Text(
                '$total ${total == 1 ? 'Gig' : 'Gigs'}',
                style: const TextStyle(
                    color: kAmber,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Legend
        Row(
          children: [
            if (widget.seekingQuickGigs) ...[
              _LegendDot(color: kAmber, label: 'Quick'),
              const SizedBox(width: 14),
            ],
            _LegendDot(color: kBlue, label: 'Open'),
            const SizedBox(width: 14),
            _LegendDot(
                color: const Color(0xFF8B5CF6), label: 'Offered to me'),
          ],
        ),
        const SizedBox(height: 10),

        // Map
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 300,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(14.5995, 120.9842),
                initialZoom: 12.0,
                minZoom: 9.0,
                maxZoom: 18.0,
                onMapEvent: (event) {
                  final newZoom = _mapController.camera.zoom;
                  if ((newZoom - _zoom).abs() >= 0.3) {
                    setState(() => _zoom = newZoom);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.giggre.app',
                ),
                MarkerLayer(markers: _buildMarkers()),
                if (_myLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _myLocation!,
                        width: 22,
                        height: 22,
                        child: Container(
                          decoration: BoxDecoration(
                            color: kBlue,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: kBlue.withValues(alpha: 0.45),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Zoom in to see individual gigs · Tap a pin for details',
            style: TextStyle(
                color: kSub.withValues(alpha: 0.7), fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(color: kSub, fontSize: 11)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gig Pin (single gig marker)
// ─────────────────────────────────────────────────────────────────────────────
class _GigPin extends StatelessWidget {
  final _GigMarkerData gig;
  final VoidCallback? onStart;
  const _GigPin({required this.gig, this.onStart});

  Color get _pinColor {
    switch (gig.gigType) {
      case 'open':    return kBlue;
      case 'offered': return const Color(0xFF8B5CF6);
      default:        return kAmber;
    }
  }

  IconData get _pinIcon {
    switch (gig.gigType) {
      case 'open':    return Icons.workspace_premium_outlined;
      case 'offered': return Icons.send_rounded;
      default:        return Icons.flash_on_rounded;
    }
  }

  void _showGigSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cardColor = Theme.of(ctx).cardColor;
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        final color = _pinColor;
        final typeLabel = gig.gigType == 'open'
            ? 'Open Gig'
            : gig.gigType == 'offered'
                ? 'Offered to You'
                : 'Quick Gig';
        final btnLabel = gig.gigType == 'open'
            ? 'Apply Now'
            : gig.gigType == 'offered'
                ? 'Accept Offer'
                : 'Start Gig';
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_pinIcon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(gig.title,
                            style: TextStyle(
                                color: onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(typeLabel,
                              style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _GigSheetRow(
                icon: Icons.person_outline_rounded,
                label: 'Host',
                value: gig.hostName.isNotEmpty ? gig.hostName : '—',
              ),
              _GigSheetRow(
                icon: Icons.attach_money_rounded,
                label: 'Budget',
                value: '₱${gig.budget.toStringAsFixed(0)}',
                valueColor: kAmber,
              ),
              if (gig.address.isNotEmpty)
                _GigSheetRow(
                  icon: Icons.location_on_outlined,
                  label: 'Location',
                  value: gig.address,
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (gig.gigType == 'quick') onStart?.call();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(btnLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _pinColor;
    return GestureDetector(
      onTap: () => _showGigSheet(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(_pinIcon, color: Colors.white, size: 18),
          ),
          CustomPaint(
            painter: _TrianglePainter(color: color),
            size: const Size(10, 6),
          ),
        ],
      ),
    );
  }
}

class _GigSheetRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _GigSheetRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, color: kSub, size: 16),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(color: kSub, fontSize: 13)),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: valueColor ??
                        Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gig Cluster Badge
// ─────────────────────────────────────────────────────────────────────────────
class _GigClusterBadge extends StatelessWidget {
  final int count;
  final List<_GigMarkerData> gigs;
  final ValueChanged<_GigMarkerData>? onQuickGigStarted;
  const _GigClusterBadge({
    required this.count,
    required this.gigs,
    this.onQuickGigStarted,
  });

  void _showGigList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final cardColor = Theme.of(ctx).cardColor;
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: kAmber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.work_outline_rounded,
                          color: kAmber, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$count Gigs in this area',
                            style: TextStyle(
                                color: onSurface,
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                        const Text('Tap a gig to see details',
                            style:
                                TextStyle(color: kSub, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Divider(
                  color: isDark
                      ? kBorder.withValues(alpha: 0.5)
                      : Colors.grey.withValues(alpha: 0.15)),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight:
                      MediaQuery.of(ctx).size.height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  itemCount: gigs.length,
                  separatorBuilder: (_, i) => Divider(
                    height: 1,
                    color: isDark
                        ? kBorder.withValues(alpha: 0.4)
                        : Colors.grey.withValues(alpha: 0.1),
                  ),
                  itemBuilder: (_, i) {
                    final g = gigs[i];
                    final typeColor = g.gigType == 'open'
                        ? kBlue
                        : g.gigType == 'offered'
                            ? const Color(0xFF8B5CF6)
                            : kAmber;
                    final typeIcon = g.gigType == 'open'
                        ? Icons.workspace_premium_outlined
                        : g.gigType == 'offered'
                            ? Icons.send_rounded
                            : Icons.flash_on_rounded;
                    final typeLabel = g.gigType == 'open'
                        ? 'Open'
                        : g.gigType == 'offered'
                            ? 'Offered'
                            : 'Quick';
                    final btnLabel = g.gigType == 'open'
                        ? 'Apply'
                        : g.gigType == 'offered'
                            ? 'Accept'
                            : 'Start';
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(typeIcon,
                            color: typeColor, size: 20),
                      ),
                      title: Text(g.title,
                          style: TextStyle(
                              color: onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(typeLabel,
                                style: TextStyle(
                                    color: typeColor, fontSize: 10)),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '₱${g.budget.toStringAsFixed(0)}',
                            style: const TextStyle(
                                color: kAmber,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      trailing: TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          if (g.gigType == 'quick') onQuickGigStarted?.call(g);
                        },
                        style: TextButton.styleFrom(
                          backgroundColor:
                              typeColor.withValues(alpha: 0.1),
                          foregroundColor: typeColor,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          minimumSize: Size.zero,
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(btnLabel,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showGigList(context),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: kAmber,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: kAmber.withValues(alpha: 0.45),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$count',
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  height: 1),
            ),
            const Text(
              'gigs',
              style: TextStyle(
                  color: Colors.black87,
                  fontSize: 8,
                  letterSpacing: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Triangle pointer painter
// ─────────────────────────────────────────────────────────────────────────────
class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Working UI — shown when a quick gig is active
// ─────────────────────────────────────────────────────────────────────────────
class _WorkingUI extends StatefulWidget {
  final _GigMarkerData gig;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  const _WorkingUI({
    required this.gig,
    required this.onComplete,
    required this.onCancel,
  });

  @override
  State<_WorkingUI> createState() => _WorkingUIState();
}

class _WorkingUIState extends State<_WorkingUI> {
  late final Stopwatch _stopwatch;
  late final Timer _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed = _stopwatch.elapsed);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final gig = widget.gig;
    const green = Color(0xFF22C55E);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final cardColor = Theme.of(context).cardColor;
    final divider = Theme.of(context).dividerColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── Working header ────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              decoration: BoxDecoration(
                color: green.withValues(alpha: 0.07),
                border: Border(bottom: BorderSide(color: divider)),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: green.withValues(alpha: 0.35),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.work_rounded, color: green, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Currently Working',
                            style: TextStyle(
                                color: onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        const Text('Quick Gig — Active',
                            style: TextStyle(color: green, fontSize: 12)),
                      ],
                    ),
                  ),
                  // Live timer
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black26 : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: green.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      _fmt(_elapsed),
                      style: const TextStyle(
                        color: green,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Gig details + actions ────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    // Gig card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: divider),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: isDark ? 0.2 : 0.05),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: kAmber.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.flash_on_rounded,
                                    color: kAmber, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      gig.title,
                                      style: TextStyle(
                                          color: onSurface,
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 3),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: kAmber.withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: const Text('Quick Gig',
                                          style: TextStyle(
                                              color: kAmber,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Divider(color: divider),
                          const SizedBox(height: 6),
                          _WorkingDetail(
                            icon: Icons.person_outline_rounded,
                            label: 'Host',
                            value: gig.hostName.isNotEmpty ? gig.hostName : '—',
                          ),
                          _WorkingDetail(
                            icon: Icons.attach_money_rounded,
                            label: 'Budget',
                            value: '₱${gig.budget.toStringAsFixed(0)}',
                            valueColor: kAmber,
                          ),
                          if (gig.address.isNotEmpty)
                            _WorkingDetail(
                              icon: Icons.location_on_outlined,
                              label: 'Location',
                              value: gig.address,
                            ),
                          _WorkingDetail(
                            icon: Icons.circle,
                            label: 'Status',
                            value: 'In Progress',
                            valueColor: green,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Mark as Complete
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: widget.onComplete,
                        icon: const Icon(Icons.check_circle_outline_rounded,
                            size: 22),
                        label: const Text('Mark as Complete',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Cancel
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: widget.onCancel,
                        icon: const Icon(Icons.cancel_outlined,
                            size: 20, color: Colors.redAccent),
                        label: const Text('Cancel Gig',
                            style: TextStyle(
                                fontSize: 15, color: Colors.redAccent)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: Colors.redAccent.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkingDetail extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _WorkingDetail({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: kSub, size: 17),
            const SizedBox(width: 10),
            Text('$label  ',
                style: const TextStyle(color: kSub, fontSize: 13)),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: valueColor ??
                      Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Header
// ─────────────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String name;
  final String email;
  final String photoUrl;
  final double rating;
  final int ratingCount;
  final String memberSince;
  final bool isDark;

  const _Header({
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.rating,
    required this.ratingCount,
    required this.memberSince,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF0A1628), const Color(0xFF0F2040)]
              : [const Color(0xFF046BD2), const Color(0xFF1E88E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Gig Worker',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _Avatar(photoUrl: photoUrl, size: 72),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isNotEmpty ? name : 'Worker',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(email,
                            style: TextStyle(
                                color: Colors.white
                                    .withValues(alpha: 0.75),
                                fontSize: 13)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ...List.generate(5, (i) {
                              final full = i < rating.floor();
                              final half = !full &&
                                  i < rating &&
                                  rating - i >= 0.5;
                              return Icon(
                                full
                                    ? Icons.star_rounded
                                    : half
                                        ? Icons.star_half_rounded
                                        : Icons.star_outline_rounded,
                                color: kAmber,
                                size: 15,
                              );
                            }),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '${rating.toStringAsFixed(1)}  ($ratingCount reviews)',
                                style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.8),
                                    fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (memberSince.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Member since $memberSince',
                              style: TextStyle(
                                  color: Colors.white
                                      .withValues(alpha: 0.55),
                                  fontSize: 11)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Earnings card
// ─────────────────────────────────────────────────────────────────────────────
class _EarningsCard extends StatelessWidget {
  final double totalEarnings;
  final double weeklyEarnings;
  final int completedGigs;

  const _EarningsCard({
    required this.totalEarnings,
    required this.weeklyEarnings,
    required this.completedGigs,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final divider = Theme.of(context).dividerColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    const green = Color(0xFF22C55E);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: green,
                    size: 20),
              ),
              const SizedBox(width: 10),
              Text('Earnings',
                  style: TextStyle(
                      color: onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _EarningsStat(
                  label: 'This Week',
                  value: '₱${weeklyEarnings.toStringAsFixed(0)}',
                  color: green,
                ),
              ),
              Container(width: 1, height: 40, color: divider),
              Expanded(
                child: _EarningsStat(
                  label: 'Total Earned',
                  value: '₱${totalEarnings.toStringAsFixed(0)}',
                  color: kAmber,
                ),
              ),
              Container(width: 1, height: 40, color: divider),
              Expanded(
                child: _EarningsStat(
                  label: 'Completed',
                  value: '$completedGigs gigs',
                  color: kBlue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EarningsStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _EarningsStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(color: kSub, fontSize: 11)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Toggles card
// ─────────────────────────────────────────────────────────────────────────────
class _TogglesCard extends StatelessWidget {
  final bool availableForGigs;
  final bool autoAccept;
  final ValueChanged<bool> onAvailableChanged;
  final ValueChanged<bool> onAutoAcceptChanged;

  const _TogglesCard({
    required this.availableForGigs,
    required this.autoAccept,
    required this.onAvailableChanged,
    required this.onAutoAcceptChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final divider = Theme.of(context).dividerColor;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider),
      ),
      child: Column(
        children: [
          _ToggleRow(
            icon: Icons.circle_rounded,
            iconColor:
                availableForGigs ? const Color(0xFF22C55E) : kSub,
            label: 'Available for Gigs',
            subtitle: availableForGigs
                ? 'You appear online to hosts'
                : 'You are hidden from hosts',
            value: availableForGigs,
            activeColor: const Color(0xFF22C55E),
            onChanged: onAvailableChanged,
          ),
          Divider(height: 1, color: divider, indent: 56),
          _ToggleRow(
            icon: Icons.bolt_rounded,
            iconColor: autoAccept ? kAmber : kSub,
            label: 'Auto Accept',
            subtitle: autoAccept
                ? 'Gigs matching your skills are auto-accepted'
                : 'You manually review each gig offer',
            value: autoAccept,
            activeColor: kAmber,
            onChanged: onAutoAcceptChanged,
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(color: kSub, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: activeColor,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Toolchest card
// ─────────────────────────────────────────────────────────────────────────────
class _ToolchestCard extends StatelessWidget {
  final String bio;
  final VoidCallback onTap;
  const _ToolchestCard({required this.bio, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final divider = Theme.of(context).dividerColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: divider),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kAmber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.construction_rounded,
                  color: kAmber, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My Toolchest',
                      style: TextStyle(
                          color: onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    bio.isNotEmpty
                        ? bio
                        : 'Add your skills, tools, and certifications',
                    style: const TextStyle(color: kSub, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: kSub, size: 14),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reusable small widgets
// ─────────────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            color: kSub,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5),
      );
}

class _MenuCard extends StatelessWidget {
  final List<Widget> children;
  const _MenuCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(children: children),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;
  final VoidCallback onTap;
  final bool showArrow;

  const _MenuRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.labelColor,
    this.showArrow = true,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    color: labelColor ?? onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
              ),
            ),
            if (showArrow)
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: kSub, size: 14),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Divider(
      height: 1,
      color: Theme.of(context).dividerColor,
      indent: 64);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Avatar
// ─────────────────────────────────────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  final String photoUrl;
  final double size;
  const _Avatar({required this.photoUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    if (photoUrl.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (ctx, url) => _DefaultAvatar(size: size),
          errorWidget: (ctx, url, err) => _DefaultAvatar(size: size),
        ),
      );
    }
    return _DefaultAvatar(size: size);
  }
}

class _DefaultAvatar extends StatelessWidget {
  final double size;
  const _DefaultAvatar({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: kAmber.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.3), width: 2),
      ),
      child: Icon(Icons.person_rounded,
          color: kAmber, size: size * 0.5),
    );
  }
}
