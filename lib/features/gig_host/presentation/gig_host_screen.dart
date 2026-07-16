import 'dart:async';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import '../../../core/services/gms_availability.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/map_style.dart';
import 'post_quick_gig_screen.dart';
import 'post_open_gig_screen.dart';
import 'post_offered_gig_screen.dart';
import '../models/gig_template_model.dart';
import '../../../core/utils/currency_formatter.dart';
import 'widgets/admin_gig_config_sheet.dart';
import 'widgets/notifications_sheet.dart';
import 'widgets/gig_detail_sheet.dart';
import 'widgets/host_gig_card.dart';
import 'host_gigs_screen.dart';

class GigHostScreen extends StatefulWidget {
  // True when hosted as the Home tab root inside HostShell — suppresses the
  // header's back arrow since there's no dashboard-level route to pop to.
  final bool isTabRoot;

  const GigHostScreen({super.key, this.isTabRoot = false});

  @override
  State<GigHostScreen> createState() => _GigHostScreenState();
}

class _GigHostScreenState extends State<GigHostScreen> {
  String _userName = '';
  String _photoUrl = '';
  final GlobalKey _workerMapKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!mounted) return;
    setState(() {
      _userName = doc.data()?['name'] ?? '';
      _photoUrl = doc.data()?['photoUrl'] ?? '';
    });
  }

  void _scrollToWorkerMap() {
    final ctx = _workerMapKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.05,
      );
    }
  }

  void _showTemplates() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TemplatesSheet(hostId: uid, hostName: _userName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstName = _userName.split(' ').first;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // ── Gold header band + overlapping stat cards ──────────
          SliverToBoxAdapter(
            child: _HostHeader(
              firstName: firstName,
              photoUrl: _photoUrl,
              uid: uid,
              showBackButton: !widget.isTabRoot,
              onTemplates: _showTemplates,
              onViewWorkers: _scrollToWorkerMap,
            ),
          ),

          // ── Body content ──────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Workers Near You ───────────────────────────
                _WorkerMapSection(key: _workerMapKey, hostName: _userName),
                const SizedBox(height: 24),

                // ── Your Gigs ──────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Your Gigs',
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => HostGigsScreen(uid: uid)),
                      ),
                      child: const Text(
                        'See all',
                        style: TextStyle(
                          color: kGold,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _GigPreviewList(uid: uid),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gold header band
// ─────────────────────────────────────────────────────────────────────────────
class _HostHeader extends StatelessWidget {
  final String firstName;
  final String photoUrl;
  final String uid;
  final bool showBackButton;
  final VoidCallback onTemplates;
  final VoidCallback onViewWorkers;

  const _HostHeader({
    required this.firstName,
    required this.photoUrl,
    required this.uid,
    required this.showBackButton,
    required this.onTemplates,
    required this.onViewWorkers,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Gold gradient band — bottom corners curve, matching the worker
        // dashboard's header, so the banner below can overlap the curve.
        ClipRRect(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(26),
            bottomRight: Radius.circular(26),
          ),
          child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kGold, Color(0xFFD88810)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Action row ──────────────────────────────
                  Row(
                    children: [
                      // Left: back (when pushed) + "Gig Host / Dashboard" label
                      GestureDetector(
                        onTap: showBackButton
                            ? () => Navigator.pop(context)
                            : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showBackButton) ...[
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white,
                                  size: 15,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            const Text(
                              'Host Dashboard',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Right: action icons (white)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Bell with unread dot
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('open_gigs')
                                .where('hostId', isEqualTo: uid)
                                .where('status', isEqualTo: 'open')
                                .snapshots(),
                            builder: (context, snap) {
                              final hasApplicants =
                                  snap.data?.docs.any((d) {
                                        final applicants = (d.data()
                                                as Map<String, dynamic>)[
                                            'applicants'] as List?;
                                        return applicants != null &&
                                            applicants.isNotEmpty;
                                      }) ??
                                      false;
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  IconButton(
                                    tooltip: 'Notifications',
                                    icon: const Icon(
                                      Icons.notifications_outlined,
                                      size: 19,
                                    ),
                                    onPressed: () =>
                                        NotificationsSheet.show(context),
                                    style: IconButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.18),
                                      shape: const CircleBorder(),
                                      fixedSize: const Size(38, 38),
                                    ),
                                  ),
                                  if (hasApplicants)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                          // More menu (templates + gig config)
                          PopupMenuButton<String>(
                            tooltip: 'More',
                            icon: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.more_vert_rounded,
                                color: Colors.white,
                                size: 19,
                              ),
                            ),
                            color: Theme.of(context).cardColor,
                            onSelected: (val) {
                              if (val == 'templates') onTemplates();
                              if (val == 'config') {
                                AdminGigConfigSheet.show(context);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'templates',
                                child: Row(
                                  children: [
                                    Icon(Icons.bookmark_add_outlined,
                                        size: 16, color: kSub),
                                    SizedBox(width: 10),
                                    Text('Saved Templates',
                                        style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'config',
                                child: Row(
                                  children: [
                                    Icon(Icons.tune_rounded,
                                        size: 16, color: kSub),
                                    SizedBox(width: 10),
                                    Text('Gig Config',
                                        style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // ── Profile strip ────────────────────────────
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.white.withValues(alpha: 0.22),
                        backgroundImage: photoUrl.isNotEmpty
                            ? CachedNetworkImageProvider(photoUrl)
                            : null,
                        child: photoUrl.isEmpty
                            ? const Icon(
                                Icons.account_circle_rounded,
                                color: Colors.white,
                                size: 26,
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              firstName.isNotEmpty ? firstName : 'Welcome, Host!',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              'Manage your gigs and find workers',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ),
        ),
        // Workers-online card — always shown, overlapping the header's
        // curved bottom edge, translated up by exactly half its own height
        // (52/2) so the curve crosses its vertical center, matching the
        // worker dashboard's header/AvailabilityCard overlap.
        Transform.translate(
          offset: const Offset(0, -26),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _WorkersOnlineCard(uid: uid, onViewWorkers: onViewWorkers),
          ),
        ),
        // Applicant-waiting card — sits directly under the workers-online
        // card in normal flow. No extra top padding: the translate above
        // already leaves its own ~26px reserved (unpainted) gap before this.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ApplicantWaitingCard(uid: uid),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Applicant-priority banner — summarizes open gigs that currently have at least
//  one applicant still waiting to be selected (status still 'open', so the
//  count/visibility comes straight from the same `open_gigs` +
//  `applicants` array already streamed for the dashboard's notification
//  bell — nothing gets counted here that isn't actually pending). The
//  `notifications` collection (category: 'new_applicant', fired on every
//  apply — see gig_map_section.dart _applyToOpenGig) is only used as a
//  best-effort source for "earliest application" display time; it never
//  affects the count or whether the card shows at all.
// ─────────────────────────────────────────────────────────────────────────────
const _kBannerBg = Color(0xFFFFF7E8);
const _kBannerBorder = Color(0xFFF2DFB8);
const _kBannerTitle = Color(0xFF17263D);
const _kBannerSub = Color(0xFF8A7A55);
const _kGoldDark = Color(0xFFD88810);
const _kGoldText = Color(0xFFB06E00);
const _kGreenDot = Color(0xFF2E9E6B);
const _kAvatarBlue = Color(0xFF2B6FB5);

// ─────────────────────────────────────────────────────────────────────────────
//  Workers-online card — always shown, overlapping the header's curved
//  bottom edge (positioned by the parent _HostHeader via Transform.translate).
//  "Online" here specifically means ready for quick gigs (isOnline AND
//  seekingQuickGigs), matching this card's own "quick gig offers" subtitle —
//  reuses the same users/isOnline stream shape as _WorkerMapSection, just
//  filtered client-side by a different flag.
// ─────────────────────────────────────────────────────────────────────────────
class _WorkersOnlineCard extends StatefulWidget {
  final String uid;
  final VoidCallback onViewWorkers;
  const _WorkersOnlineCard({required this.uid, required this.onViewWorkers});

  @override
  State<_WorkersOnlineCard> createState() => _WorkersOnlineCardState();
}

class _WorkersOnlineCardState extends State<_WorkersOnlineCard> {
  StreamSubscription? _onlineSub;
  int _onlineWorkers = 0;

  @override
  void initState() {
    super.initState();
    if (widget.uid.isEmpty) return;
    _onlineSub = FirebaseFirestore.instance
        .collection('users')
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      final count =
          snap.docs.where((d) => d.data()['seekingQuickGigs'] == true).length;
      if (mounted) setState(() => _onlineWorkers = count);
    }, onError: (e) {
      if (FirebaseAuth.instance.currentUser == null) return;
      debugPrint('[_WorkersOnlineCard] stream error: $e');
    });
  }

  @override
  void dispose() {
    _onlineSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: _kGreenDot,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_onlineWorkers ${_onlineWorkers == 1 ? 'worker' : 'workers'} online near you',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Ready to receive quick gig offers',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: kSub, fontSize: 10.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 30,
            child: OutlinedButton(
              onPressed: widget.onViewWorkers,
              style: OutlinedButton.styleFrom(
                foregroundColor: _kGoldText,
                side: const BorderSide(color: _kGoldDark),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text(
                'View',
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
//  Applicant-waiting card — sits in normal flow directly under the
//  workers-online card, only rendered when at least one open gig (status
//  still 'open') has an applicant waiting (count/visibility comes straight
//  from the same `open_gigs` + `applicants` array already streamed for the
//  dashboard's notification bell). The `notifications` collection (category:
//  'new_applicant', fired on every apply — see gig_map_section.dart
//  _applyToOpenGig) is only used as a best-effort source for "most recent
//  applicant" display; it never affects the count or whether the card shows.
// ─────────────────────────────────────────────────────────────────────────────
class _ApplicantWaitingCard extends StatefulWidget {
  final String uid;
  const _ApplicantWaitingCard({required this.uid});

  @override
  State<_ApplicantWaitingCard> createState() => _ApplicantWaitingCardState();
}

class _ApplicantWaitingCardState extends State<_ApplicantWaitingCard> {
  StreamSubscription? _gigsSub;
  StreamSubscription? _notifSub;
  // Open gigs (status still 'open') that have >=1 applicant waiting.
  List<Map<String, dynamic>> _pendingGigs = [];
  List<Map<String, dynamic>> _applicantNotifs = [];

  @override
  void initState() {
    super.initState();
    if (widget.uid.isEmpty) return;
    final db = FirebaseFirestore.instance;
    void onErr(Object e) {
      if (FirebaseAuth.instance.currentUser == null) return;
      debugPrint('[_ApplicantWaitingCard] stream error: $e');
    }

    _gigsSub = db
        .collection('open_gigs')
        .where('hostId', isEqualTo: widget.uid)
        .where('status', isEqualTo: 'open')
        .snapshots()
        .listen((snap) {
      final pending = snap.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        data['id'] = d.id;
        return data;
      }).where((d) {
        final applicants = d['applicants'] as List?;
        return applicants != null && applicants.isNotEmpty;
      }).toList();
      if (mounted) setState(() => _pendingGigs = pending);
    }, onError: onErr);

    // Same query shape as NotificationsSheet (userId + createdAt ordering,
    // category filtered client-side) — no new Firestore index needed.
    _notifSub = db
        .collection('notifications')
        .where('userId', isEqualTo: widget.uid)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .listen((snap) {
      final notifs = snap.docs
          .map((d) => d.data())
          .where((d) => d['category'] == 'new_applicant')
          .toList();
      if (mounted) setState(() => _applicantNotifs = notifs);
    }, onError: onErr);
  }

  @override
  void dispose() {
    _gigsSub?.cancel();
    _notifSub?.cancel();
    super.dispose();
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // Newest new_applicant notification for one specific gig, if any.
  Map<String, dynamic>? _mostRecentNotifFor(String gigId) {
    final matches = _applicantNotifs
        .where((n) => (n['gigId'] as String?) == gigId)
        .toList()
      ..sort((a, b) {
        final aTs = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
        final bTs = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
        return bTs.compareTo(aTs);
      });
    return matches.isNotEmpty ? matches.first : null;
  }

  @override
  Widget build(BuildContext context) {
    if (_pendingGigs.isEmpty) return const SizedBox.shrink();

    // One banner per pending gig — a worker who applied to 2 different gigs
    // must surface 2 banners, not collapse into a single aggregate one.
    // Freshest activity (by that gig's own most recent applicant notif) first.
    final gigs = [..._pendingGigs]..sort((a, b) {
        final aTs =
            (_mostRecentNotifFor(a['id'] as String)?['createdAt'] as Timestamp?)
                ?.toDate() ??
            DateTime(0);
        final bTs =
            (_mostRecentNotifFor(b['id'] as String)?['createdAt'] as Timestamp?)
                ?.toDate() ??
            DateTime(0);
        return bTs.compareTo(aTs);
      });

    return Column(
      children: [
        for (var i = 0; i < gigs.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _buildBanner(gigs[i]),
        ],
      ],
    );
  }

  Widget _buildBanner(Map<String, dynamic> gig) {
    final gigId = gig['id'] as String;
    final applicants = gig['applicants'] as List;
    final applicantCount = applicants.length;
    final notif = _mostRecentNotifFor(gigId);
    final mostRecentTs = (notif?['createdAt'] as Timestamp?)?.toDate();
    final applicantName = notif?['workerName'] as String? ??
        (applicants.isNotEmpty
            ? (applicants.last as Map<String, dynamic>)['workerName']
                    as String? ??
                'A worker'
            : 'A worker');
    final gigTitle = gig['title'] as String? ?? 'your gig';

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _kBannerBg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _kBannerBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: _kAvatarBlue,
            child: Text(
              applicantName.isNotEmpty ? applicantName[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$applicantCount ${applicantCount == 1 ? 'applicant' : 'applicants'} '
                  'waiting to be selected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kBannerTitle,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  mostRecentTs != null
                      ? '$gigTitle · ${_timeAgo(mostRecentTs)}'
                      : gigTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _kBannerSub, fontSize: 10.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 30,
            child: ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => GigDetailSheet(gigId: gigId, gigType: 'open'),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGoldDark,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text(
                'Review',
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
//  Gig Type Card
// ─────────────────────────────────────────────────────────────────────────────
class _GigTypeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String example;
  final IconData icon;
  final Color accentColor;
  final String badge;
  final Color badgeColor;
  final VoidCallback? onTap;

  const _GigTypeCard({
    required this.title,
    required this.subtitle,
    required this.example,
    required this.icon,
    required this.accentColor,
    required this.badge,
    required this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final cardColor = Theme.of(context).cardColor;
    final borderColor = Theme.of(context).dividerColor;
    final titleColor = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: enabled ? accentColor.withValues(alpha: 0.08) : cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled
                ? accentColor.withValues(alpha: 0.5)
                : borderColor,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: enabled ? 0.18 : 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon,
                  color: enabled
                      ? accentColor
                      : accentColor.withValues(alpha: 0.4),
                  size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                            color: enabled
                                ? titleColor
                                : titleColor.withValues(alpha: 0.4),
                            fontSize: 15,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: badgeColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                              color: badgeColor,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: enabled
                              ? kSub
                              : kSub.withValues(alpha: 0.5),
                          fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(example,
                      style: TextStyle(
                          color: enabled
                              ? accentColor.withValues(alpha: 0.7)
                              : kSub.withValues(alpha: 0.3),
                          fontSize: 11)),
                ],
              ),
            ),
            if (enabled)
              Icon(Icons.arrow_forward_ios_rounded,
                  color: accentColor.withValues(alpha: 0.6), size: 16),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gig Area Preview — 5 most recent across all types
// ─────────────────────────────────────────────────────────────────────────────
class _GigPreviewList extends StatefulWidget {
  final String uid;
  const _GigPreviewList({required this.uid});

  @override
  State<_GigPreviewList> createState() => _GigPreviewListState();
}

class _GigPreviewListState extends State<_GigPreviewList> {
  List<Map<String, dynamic>> _quick = [], _open = [], _offered = [];
  bool _loading = true;
  StreamSubscription? _quickSub, _openSub, _offeredSub;

  @override
  void initState() {
    super.initState();
    if (widget.uid.isEmpty) return;
    final db = FirebaseFirestore.instance;
    void onErr(Object e) {
      if (FirebaseAuth.instance.currentUser == null) return;
      debugPrint('[_GigPreviewList] stream error: $e');
    }

    _quickSub = db
        .collection('quick_gigs')
        .where('hostId', isEqualTo: widget.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((s) => setState(() {
              _quick = s.docs.map((d) {
                final m = Map<String, dynamic>.from(d.data());
                m['gigType'] = m['gigType'] ?? 'quick';
                m['docId'] = d.id;
                return m;
              }).toList();
              _loading = false;
            }), onError: onErr);

    _openSub = db
        .collection('open_gigs')
        .where('hostId', isEqualTo: widget.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((s) => setState(() {
              _open = s.docs.map((d) {
                final m = Map<String, dynamic>.from(d.data());
                m['gigType'] = m['gigType'] ?? 'open';
                m['docId'] = d.id;
                return m;
              }).toList();
              _loading = false;
            }), onError: onErr);

    _offeredSub = db
        .collection('offered_gigs')
        .where('hostId', isEqualTo: widget.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((s) => setState(() {
              _offered = s.docs.map((d) {
                final m = Map<String, dynamic>.from(d.data());
                m['gigType'] = m['gigType'] ?? 'offered';
                m['docId'] = d.id;
                return m;
              }).toList();
              _loading = false;
            }), onError: onErr);
  }

  @override
  void dispose() {
    _quickSub?.cancel();
    _openSub?.cancel();
    _offeredSub?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> get _latest {
    final all = [..._quick, ..._open, ..._offered]
        .where((d) {
          final s = d['status'] as String? ?? '';
          return s != 'cancelled' && s != 'completed';
        })
        .toList();
    all.sort((a, b) {
      final aTs = a['createdAt'] as Timestamp?;
      final bTs = b['createdAt'] as Timestamp?;
      if (aTs == null || bTs == null) return 0;
      return bTs.toDate().compareTo(aTs.toDate());
    });
    return all.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: kAmber, strokeWidth: 2),
        ),
      );
    }

    final preview = _latest;

    if (preview.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: kAmber.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.inbox_outlined, color: kAmber, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              'No gigs posted yet',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Use the post options above to create a gig.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kSub, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      children: preview.map((d) => HostGigCard(data: d, showActions: false)).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Worker Data
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerData {
  final String id;
  final String name;
  final String skill;
  final LatLng position;
  final String photoUrl;
  final double rating;
  final int ratingCount;

  _WorkerData({
    required this.id,
    required this.name,
    required this.skill,
    required this.position,
    this.photoUrl = '',
    this.rating = 5.0,
    this.ratingCount = 0,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Worker Map Section
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerCluster {
  final LatLng center;
  final int count;
  final _WorkerData? singleWorker;
  final List<_WorkerData> workers;

  const _WorkerCluster({
    required this.center,
    required this.count,
    required this.workers,
    this.singleWorker,
  });
}

class _WorkerMapSection extends StatefulWidget {
  final String hostName;
  const _WorkerMapSection({super.key, required this.hostName});

  @override
  State<_WorkerMapSection> createState() => _WorkerMapSectionState();
}

class _WorkerMapSectionState extends State<_WorkerMapSection> {
  GoogleMapController? _googleMapController;
  bool _useGoogleMaps = true;
  final _osmController = fm.MapController();
  bool _osmMapReady = false;
  double _zoom = 12.0;
  LatLng? _myLocation;
  bool _mapInteractive = false;
  // All online + available workers with a location, unfiltered by distance.
  List<_WorkerData> _allWorkers = [];
  // Cached result of filtering _allWorkers to within 20km of _myLocation —
  // recomputed only when either input changes (see _recomputeVisibleWorkers),
  // NOT on every read. _buildClusters()'s nested loop indexes into this list
  // many times per build; if this were a getter re-filtering from scratch on
  // every access (as it briefly was), that nested-loop access pattern turns
  // an O(n) filter into effectively O(n^3) and stalls the main thread badly
  // enough to crash the app on a device with more than a handful of workers.
  List<_WorkerData> _workers = [];
  StreamSubscription? _workerSub;
  BuildContext? _context;
  // Generic "W" fallback shown before a worker's own photo icon has loaded,
  // and for workers without a photoUrl at all.
  BitmapDescriptor? _blueCircleIcon;
  // Per-worker profile-photo marker icons, keyed by worker id — built lazily
  // (see _ensureWorkerAvatarIcons/_loadWorkerPhotoIcon) so the map doesn't
  // block on fetching every online worker's photo up front.
  final Map<String, BitmapDescriptor> _workerAvatarIcons = {};
  final Set<String> _fetchingAvatarFor = {};
  // Separate controller for the full-screen map route (a distinct GoogleMap
  // widget instance from the inline preview's, so each needs its own).
  GoogleMapController? _fullScreenGoogleMapController;
  // Bumped whenever live map data changes so the full-screen route (pushed
  // via Navigator, so outside this State's own rebuild scope) can rebuild
  // via ValueListenableBuilder without duplicating the worker/location
  // subscriptions that already live in this State.
  final ValueNotifier<int> _fullScreenTick = ValueNotifier(0);

  static const double _kMaxWorkerDistanceMeters = 20000;

  // Falls back to the unfiltered list while the host's own location hasn't
  // resolved yet, so the map isn't empty just because location
  // permission/fix is still pending.
  void _recomputeVisibleWorkers() {
    final loc = _myLocation;
    _workers = loc == null
        ? _allWorkers
        : _allWorkers.where((w) {
            final distance = Geolocator.distanceBetween(
              loc.latitude,
              loc.longitude,
              w.position.latitude,
              w.position.longitude,
            );
            return distance <= _kMaxWorkerDistanceMeters;
          }).toList();
  }

  @override
  void initState() {
    super.initState();
    _initMap();
    _startWorkersSub();
    _loadBlueCircleIcon();
  }

  // Draws a fixed-size blue circle with a "W" letter (blue fill, white
  // ring) at runtime — the fallback shown for a worker pin until that
  // worker's own profile-photo icon has loaded (or permanently, if they have
  // no photo). There's no built-in circular hue for the default teardrop
  // marker, and a `Circle` overlay is sized in real-world meters so it'd
  // shrink/grow with zoom instead of staying a consistent marker size.
  Future<void> _loadBlueCircleIcon() async {
    const double size = 88;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(size / 2, size / 2);
    const radius = size / 2 - 6;
    canvas.drawCircle(center, radius, Paint()..color = _kAvatarBlue);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
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
          ..addText('W');
    final paragraph = pb.build()
      ..layout(const ui.ParagraphConstraints(width: size));
    canvas.drawParagraph(
      paragraph,
      Offset(0, center.dy - paragraph.height / 2),
    );
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null || !mounted) return;
    setState(() {
      _blueCircleIcon = BitmapDescriptor.bytes(
        bytes.buffer.asUint8List(),
        width: 20,
        height: 20,
      );
    });
  }

  // Kicks off a photo fetch for every worker with a photoUrl that doesn't
  // have a cached (or in-flight) marker icon yet. Fire-and-forget by design —
  // each call independently updates _workerAvatarIcons and setState()s once
  // it resolves, so markers upgrade from the "W" fallback to the real photo
  // as fetches complete rather than blocking the map on all of them at once.
  void _ensureWorkerAvatarIcons(List<_WorkerData> workers) {
    for (final w in workers) {
      if (w.photoUrl.isEmpty) continue;
      if (_workerAvatarIcons.containsKey(w.id)) continue;
      if (_fetchingAvatarFor.contains(w.id)) continue;
      _fetchingAvatarFor.add(w.id);
      _loadWorkerPhotoIcon(w);
    }
  }

  Future<void> _loadWorkerPhotoIcon(_WorkerData worker) async {
    const double size = 64;
    const double border = 4;
    const double radius = size / 2 - border;
    const center = Offset(size / 2, size / 2);

    ui.Image? photo;
    try {
      final res = await http.get(Uri.parse(worker.photoUrl));
      if (res.statusCode == 200) {
        final codec = await ui.instantiateImageCodec(
          res.bodyBytes,
          targetWidth: size.toInt(),
        );
        final frame = await codec.getNextFrame();
        photo = frame.image;
      }
    } catch (_) {}

    _fetchingAvatarFor.remove(worker.id);
    if (photo == null || !mounted) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(center, size / 2, Paint()..color = Colors.white);
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

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null || !mounted) return;
    setState(() {
      _workerAvatarIcons[worker.id] = BitmapDescriptor.bytes(
        bytes.buffer.asUint8List(),
        width: 20,
        height: 20,
      );
    });
    _fullScreenTick.value++;
  }

  Future<void> _initMap() async {
    final hasGms = await GmsAvailability.isAvailable;
    if (mounted) setState(() => _useGoogleMaps = hasGms);
    _fetchAndCenterMap();
  }

  // OSM-path equivalent of the "W" fallback baked into _blueCircleIcon for
  // Google Maps — shown while a worker's photo loads, or if they have none.
  static Widget _workerFallbackAvatar() => Container(
        color: _kAvatarBlue,
        alignment: Alignment.center,
        child: const Text(
          'W',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  @override
  void dispose() {
    _workerSub?.cancel();
    _googleMapController?.dispose();
    _fullScreenGoogleMapController?.dispose();
    _osmController.dispose();
    _fullScreenTick.dispose();
    super.dispose();
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
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _myLocation = loc;
        _recomputeVisibleWorkers();
      });
      _fullScreenTick.value++;
      _ensureWorkerAvatarIcons(_workers);
      if (_useGoogleMaps) {
        _googleMapController?.animateCamera(
          CameraUpdate.newLatLngZoom(loc, 14.0),
        );
        _fullScreenGoogleMapController?.animateCamera(
          CameraUpdate.newLatLngZoom(loc, 14.0),
        );
      } else if (_osmMapReady) {
        _osmController.move(ll.LatLng(loc.latitude, loc.longitude), 14.0);
      }
    } catch (_) {}
  }

  void _startWorkersSub() {
    if (FirebaseAuth.instance.currentUser == null) return;
    _workerSub = FirebaseFirestore.instance
        .collection('users')
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      final workers = snap.docs.where((d) => d.data()['availableForGigs'] == true).map((d) {
        final data = d.data();
        final geo = data['location'] as GeoPoint?;
        if (geo == null) return null;
        final skills = (data['skills'] as List?)?.cast<String>() ?? [];
        return _WorkerData(
          id: d.id,
          name: data['name'] as String? ?? 'Worker',
          skill: skills.isNotEmpty ? skills.first : 'General',
          position: LatLng(geo.latitude, geo.longitude),
          photoUrl: data['photoUrl'] as String? ?? '',
          rating: (data['ratingAsWorker'] as num?)?.toDouble() ?? 5.0,
          ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
        );
      }).whereType<_WorkerData>().toList();
      if (mounted) {
        setState(() {
          _allWorkers = workers;
          _recomputeVisibleWorkers();
        });
        _fullScreenTick.value++;
        _ensureWorkerAvatarIcons(_workers);
      }
    }, onError: (e) {
      if (FirebaseAuth.instance.currentUser == null) return;
      debugPrint('[_WorkerMapSection] stream error: $e');
    });
  }

  // Cluster radius in metres shrinks as zoom increases
  static double _clusterRadius(double zoom) {
    if (zoom >= 15) return 20.0;
    if (zoom >= 14) return 60.0;
    if (zoom >= 13) return 200.0;
    if (zoom >= 12) return 600.0;
    if (zoom >= 11) return 1800.0;
    if (zoom >= 10) return 5000.0;
    return 15000.0;
  }

  List<_WorkerCluster> _buildClusters() {
    final radiusM = _clusterRadius(_zoom);
    final assigned = List.filled(_workers.length, false);
    final clusters = <_WorkerCluster>[];

    for (int i = 0; i < _workers.length; i++) {
      if (assigned[i]) continue;
      assigned[i] = true;
      final group = [_workers[i]];

      for (int j = i + 1; j < _workers.length; j++) {
        if (assigned[j]) continue;
        final dist = Geolocator.distanceBetween(
          _workers[i].position.latitude,
          _workers[i].position.longitude,
          _workers[j].position.latitude,
          _workers[j].position.longitude,
        );
        if (dist <= radiusM) {
          assigned[j] = true;
          group.add(_workers[j]);
        }
      }

      final avgLat =
          group.fold(0.0, (s, w) => s + w.position.latitude) / group.length;
      final avgLng =
          group.fold(0.0, (s, w) => s + w.position.longitude) / group.length;
      clusters.add(_WorkerCluster(
        center: LatLng(avgLat, avgLng),
        count: group.length,
        workers: group,
        singleWorker: group.length == 1 ? group.first : null,
      ));
    }
    return clusters;
  }

  Set<Marker> _buildMarkers() {
    final ctx = _context;
    final clusters = _buildClusters();
    return clusters.map((cluster) {
      if (cluster.count == 1 && cluster.singleWorker != null) {
        final worker = cluster.singleWorker!;
        return Marker(
          markerId: MarkerId('worker_${worker.id}'),
          position: cluster.center,
          icon: _workerAvatarIcons[worker.id] ??
              _blueCircleIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          onTap: ctx != null ? () => _showWorkerSheet(ctx, worker) : null,
        );
      }
      // Cluster marker — use yellow/amber hue
      return Marker(
        markerId: MarkerId('cluster_${cluster.center.latitude}_${cluster.center.longitude}'),
        position: cluster.center,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        onTap: ctx != null ? () => _showWorkerList(ctx, cluster.workers) : null,
      );
    }).toSet();
  }

  Widget _buildOsmMap() {
    final ctx = _context;
    final clusters = _buildClusters();
    final osmMarkers = <fm.Marker>[];
    for (final cluster in clusters) {
      if (cluster.count == 1 && cluster.singleWorker != null) {
        final worker = cluster.singleWorker!;
        osmMarkers.add(fm.Marker(
          point: ll.LatLng(cluster.center.latitude, cluster.center.longitude),
          width: 20,
          height: 20,
          child: GestureDetector(
            onTap: ctx != null ? () => _showWorkerSheet(ctx, worker) : null,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: ClipOval(
                child: worker.photoUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: worker.photoUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => _workerFallbackAvatar(),
                        errorWidget: (_, _, _) => _workerFallbackAvatar(),
                      )
                    : _workerFallbackAvatar(),
              ),
            ),
          ),
        ));
      } else {
        osmMarkers.add(fm.Marker(
          point: ll.LatLng(cluster.center.latitude, cluster.center.longitude),
          width: 36,
          height: 36,
          child: GestureDetector(
            onTap: ctx != null ? () => _showWorkerList(ctx, cluster.workers) : null,
            child: Container(
              decoration: BoxDecoration(
                color: kAmber,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: Center(
                child: Text(
                  '${cluster.count}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ));
      }
    }
    if (_myLocation != null) {
      osmMarkers.add(fm.Marker(
        point: ll.LatLng(_myLocation!.latitude, _myLocation!.longitude),
        width: 28,
        height: 28,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.cyan,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 14),
        ),
      ));
    }
    return fm.FlutterMap(
      mapController: _osmController,
      options: fm.MapOptions(
        initialCenter: _myLocation != null
            ? ll.LatLng(_myLocation!.latitude, _myLocation!.longitude)
            : const ll.LatLng(14.5995, 120.9842),
        initialZoom: _zoom,
        onMapReady: () {
          if (mounted) setState(() => _osmMapReady = true);
        },
        onPositionChanged: (camera, _) {
          final newZoom = camera.zoom;
          if ((newZoom - _zoom).abs() >= 0.3) setState(() => _zoom = newZoom);
        },
      ),
      children: [
        fm.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.giggre.mobile',
        ),
        fm.MarkerLayer(markers: osmMarkers),
      ],
    );
  }

  Future<({int completedGigs, bool isFavorite})> _fetchWorkerSheetData(
      String workerId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    int count = 0;
    for (final col in ['quick_gigs', 'open_gigs', 'offered_gigs']) {
      final snap = await FirebaseFirestore.instance
          .collection(col)
          .where('workerId', isEqualTo: workerId)
          .where('status', isEqualTo: 'completed')
          .get();
      count += snap.docs.length;
    }
    final hostDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final favIds =
        (hostDoc.data()?['favoriteWorkerIds'] as List?)?.cast<String>() ?? [];
    return (completedGigs: count, isFavorite: favIds.contains(workerId));
  }

  void _showWorkerSheet(BuildContext context, _WorkerData worker) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cardColor = Theme.of(ctx).cardColor;
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        final borderColor = Theme.of(ctx).dividerColor;
        return FutureBuilder<({int completedGigs, bool isFavorite})>(
          future: _fetchWorkerSheetData(worker.id),
          builder: (_, snap) {
            final completed = snap.data?.completedGigs ?? 0;
            final isFavorite = snap.data?.isFavorite ?? false;
            final loaded = snap.connectionState == ConnectionState.done;
            return Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: kBlue.withValues(alpha: 0.15),
                    backgroundImage: worker.photoUrl.isNotEmpty
                        ? CachedNetworkImageProvider(worker.photoUrl)
                        : null,
                    child: worker.photoUrl.isEmpty
                        ? const Icon(Icons.person, color: kBlue, size: 30)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(worker.name,
                      style: TextStyle(
                          color: onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(worker.skill,
                      style: const TextStyle(color: kSub, fontSize: 13)),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF22C55E),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('Online now',
                          style: TextStyle(
                              color: Color(0xFF22C55E), fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _StatCell(
                          icon: Icons.star_rounded,
                          iconColor: Colors.amber,
                          value: worker.rating.toStringAsFixed(1),
                          label: 'Rating (${worker.ratingCount})',
                        ),
                        Container(width: 1, height: 36, color: borderColor),
                        _StatCell(
                          icon: Icons.check_circle_rounded,
                          iconColor: const Color(0xFF10B981),
                          value: loaded ? '$completed' : '—',
                          label: 'Gigs Done',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (loaded && isFavorite)
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => PostOfferedGigScreen(
                              hostName: widget.hostName,
                              preselectedWorkerId: worker.id,
                              preselectedWorkerName: worker.name,
                            ),
                          ));
                        },
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: const Text('Offer a Gig',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  if (loaded && !isFavorite)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Add this worker to your Favorites to offer a gig',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: kSub.withValues(alpha: 0.8),
                            fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showWorkerList(BuildContext context, List<_WorkerData> workers) {
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
                      child: const Icon(Icons.people_alt_outlined,
                          color: kAmber, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${workers.length} Workers in this area',
                            style: TextStyle(
                                color: onSurface,
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                        const Text('Tap a worker to offer a gig',
                            style: TextStyle(color: kSub, fontSize: 11)),
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
                  maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  itemCount: workers.length,
                  separatorBuilder: (_, i) => Divider(
                    height: 1,
                    color: isDark
                        ? kBorder.withValues(alpha: 0.4)
                        : Colors.grey.withValues(alpha: 0.1),
                  ),
                  itemBuilder: (_, i) {
                    final w = workers[i];
                    return _ClusterWorkerTile(
                      w: w,
                      onOffer: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PostOfferedGigScreen(
                            hostName: widget.hostName,
                            preselectedWorkerId: w.id,
                            preselectedWorkerName: w.name,
                          ),
                        ));
                      },
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

  // Pushes a full-screen route showing the same live map — back button/
  // gesture pops it naturally since it's a real route, and _fullScreenTick
  // (bumped alongside every existing worker/location setState in this
  // State) keeps it in sync without a second Firestore subscription.
  void _openFullScreen() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ValueListenableBuilder<int>(
          valueListenable: _fullScreenTick,
          builder: (_, _, _) => Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(child: _buildMapStack(isFullScreen: true)),
          ),
        ),
      ),
    );
  }

  void _closeFullScreen() {
    Navigator.of(context, rootNavigator: true).pop();
    _fullScreenGoogleMapController?.dispose();
    _fullScreenGoogleMapController = null;
  }

  Widget _buildMapStack({required bool isFullScreen}) {
    final borderColor = Theme.of(context).dividerColor;
    final height = isFullScreen ? MediaQuery.of(context).size.height : 280.0;
    final radius = isFullScreen ? 0.0 : 16.0;
    final interactive = isFullScreen || _mapInteractive;

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: isFullScreen ? null : Border.all(color: borderColor),
            ),
            child: _useGoogleMaps
                ? GoogleMap(
                    style: Theme.of(context).brightness == Brightness.dark
                        ? kDarkMapStyle
                        : null,
                    gestureRecognizers: interactive
                        ? <Factory<OneSequenceGestureRecognizer>>{
                            Factory<OneSequenceGestureRecognizer>(
                              () => EagerGestureRecognizer(),
                            ),
                          }
                        : const <Factory<OneSequenceGestureRecognizer>>{},
                    onMapCreated: (controller) {
                      if (isFullScreen) {
                        _fullScreenGoogleMapController = controller;
                      } else {
                        _googleMapController = controller;
                      }
                      if (_myLocation != null) {
                        controller.animateCamera(
                          CameraUpdate.newLatLngZoom(_myLocation!, 14.0),
                        );
                      }
                    },
                    initialCameraPosition: const CameraPosition(
                      target: LatLng(14.5995, 120.9842),
                      zoom: 12.0,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    markers: _buildMarkers(),
                    onCameraMove: (position) {
                      final newZoom = position.zoom;
                      if ((newZoom - _zoom).abs() >= 0.3) {
                        setState(() => _zoom = newZoom);
                        _fullScreenTick.value++;
                      }
                    },
                  )
                : _buildOsmMap(),
          ),
        ),
        // Tap-to-interact overlay — inline map only; full screen is always
        // interactive since that's the entire point of switching to it.
        if (!isFullScreen && !_mapInteractive)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _mapInteractive = true),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.touch_app_rounded,
                          color: Colors.white,
                          size: 13,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Tap to interact with map',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        // Lock-map button shown while the inline map is interactive
        if (!isFullScreen && _mapInteractive)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () => setState(() => _mapInteractive = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_open_rounded,
                        color: Colors.white,
                        size: 13,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Tap to lock map',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Recenter button
        Positioned(
          bottom: 12,
          right: 12,
          child: GestureDetector(
            onTap: _fetchAndCenterMap,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.my_location_rounded,
                size: 18,
                color: _myLocation != null ? const Color(0xFF22C55E) : kSub,
              ),
            ),
          ),
        ),
        // Full-screen toggle button
        Positioned(
          bottom: 12,
          left: 12,
          child: GestureDetector(
            onTap: isFullScreen ? _closeFullScreen : _openFullScreen,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                isFullScreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                size: 18,
                color: kSub,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _context = context;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Expanded(
              child: Text(
                'Workers Near You',
                style: TextStyle(
                  color: onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF22C55E),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_workers.length} Online',
                    style: const TextStyle(
                      color: Color(0xFF22C55E),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Map
        _buildMapStack(isFullScreen: false),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Zoom in to see individual workers · Tap a pin for details',
            style: TextStyle(color: kSub.withValues(alpha: 0.7), fontSize: 11),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Stat Cell (used in worker bottom sheet)
// ─────────────────────────────────────────────────────────────────────────────
class _StatCell extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatCell({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: onSurface, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: kSub, fontSize: 11)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Cluster Worker Tile (used inside cluster bottom sheet)
// ─────────────────────────────────────────────────────────────────────────────
class _ClusterWorkerTile extends StatefulWidget {
  final _WorkerData w;
  final VoidCallback onOffer;
  const _ClusterWorkerTile({required this.w, required this.onOffer});

  @override
  State<_ClusterWorkerTile> createState() => _ClusterWorkerTileState();
}

class _ClusterWorkerTileState extends State<_ClusterWorkerTile> {
  int _completedGigs = 0;
  bool _isFavorite = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    int count = 0;
    for (final col in ['quick_gigs', 'open_gigs', 'offered_gigs']) {
      final snap = await FirebaseFirestore.instance
          .collection(col)
          .where('workerId', isEqualTo: widget.w.id)
          .where('status', isEqualTo: 'completed')
          .get();
      count += snap.docs.length;
    }
    final hostDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final favIds =
        (hostDoc.data()?['favoriteWorkerIds'] as List?)?.cast<String>() ?? [];
    if (!mounted) return;
    setState(() {
      _completedGigs = count;
      _isFavorite = favIds.contains(widget.w.id);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final w = widget.w;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: kBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: w.photoUrl.isNotEmpty
                ? ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: w.photoUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorWidget: (context, error, _) =>
                          const Icon(Icons.person, color: kBlue, size: 22),
                    ),
                  )
                : const Icon(Icons.person, color: kBlue, size: 22),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.name,
                    style: TextStyle(
                        color: onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.work_outline_rounded,
                        color: kSub, size: 12),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(w.skill,
                          style: const TextStyle(color: kSub, fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('Online',
                        style: TextStyle(
                            color: Color(0xFF22C55E), fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        color: Colors.amber, size: 13),
                    const SizedBox(width: 3),
                    Text(w.rating.toStringAsFixed(1),
                        style: TextStyle(
                            color: onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 10),
                    const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF10B981), size: 13),
                    const SizedBox(width: 3),
                    Text(_loading ? '—' : '$_completedGigs done',
                        style: const TextStyle(color: kSub, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Offer button or lock indicator
          if (_loading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: kBlue),
            )
          else if (_isFavorite)
            TextButton(
              onPressed: widget.onOffer,
              style: TextButton.styleFrom(
                backgroundColor: kBlue.withValues(alpha: 0.1),
                foregroundColor: kBlue,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Offer',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            )
          else
            Tooltip(
              message: 'Add to favorites to offer',
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: kSub.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.lock_outline_rounded,
                    color: kSub, size: 14),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Saved Templates Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _TemplatesSheet extends StatelessWidget {
  final String hostId;
  final String hostName;
  const _TemplatesSheet({required this.hostId, required this.hostName});

  static const _purple = Color(0xFF8B5CF6);

  Future<void> _deleteTemplate(BuildContext context, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Template',
            style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurface,
                fontWeight: FontWeight.bold)),
        content: const Text('Remove this template?',
            style: TextStyle(color: kSub, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep', style: TextStyle(color: kSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseFirestore.instance
        .collection('gig_templates')
        .doc(id)
        .delete();
  }

  void _useTemplate(BuildContext context, GigTemplateModel t) {
    Navigator.pop(context);
    switch (t.gigType) {
      case 'open':
        Navigator.push(context, MaterialPageRoute(
          builder: (_) =>
              PostOpenGigScreen(hostName: hostName, template: t),
        ));
        break;
      case 'offered':
        Navigator.push(context, MaterialPageRoute(
          builder: (_) =>
              PostOfferedGigScreen(hostName: hostName, template: t),
        ));
        break;
      default:
        Navigator.push(context, MaterialPageRoute(
          builder: (_) =>
              PostQuickGigScreen(hostName: hostName, template: t),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('gig_templates')
              .where('hostId', isEqualTo: hostId)
              .snapshots(),
          builder: (ctx, snapshot) {
            final docs = snapshot.data?.docs ?? [];
            final templates = docs
                .map((d) => GigTemplateModel.fromDoc(d))
                .toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              children: [
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
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: kAmber.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.bookmark_rounded,
                          color: kAmber, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Saved Templates',
                              style: TextStyle(
                                  color: onSurface,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold)),
                          Text(
                            '${templates.length} template${templates.length != 1 ? 's' : ''}',
                            style:
                                const TextStyle(color: kSub, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(
                          color: kAmber, strokeWidth: 2),
                    ),
                  )
                else if (templates.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: kAmber.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.bookmark_add_outlined,
                              color: kAmber, size: 34),
                        ),
                        const SizedBox(height: 16),
                        Text('No templates yet',
                            style: TextStyle(
                                color: onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        const Text(
                          'Fill in a gig form and tap\n"Save as Template" to reuse it later.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: kSub, fontSize: 13, height: 1.5),
                        ),
                      ],
                    ),
                  )
                else
                  ...templates.map((t) => _buildCard(context, t, isDark)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCard(
      BuildContext context, GigTemplateModel t, bool isDark) {
    final Color accent;
    final IconData typeIcon;
    final String typeLabel;
    switch (t.gigType) {
      case 'open':
        accent = kBlue;
        typeIcon = Icons.workspace_premium_outlined;
        typeLabel = 'Open Gig';
        break;
      case 'offered':
        accent = _purple;
        typeIcon = Icons.send_rounded;
        typeLabel = 'Offered Gig';
        break;
      default:
        accent = kAmber;
        typeIcon = Icons.flash_on_rounded;
        typeLabel = 'Quick Gig';
    }
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        onTap: () => _useTemplate(context, t),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(typeIcon, color: accent, size: 20),
        ),
        title: Text(t.name,
            style: TextStyle(
                color: onSurface,
                fontSize: 14,
                fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(typeLabel,
                      style: TextStyle(
                          color: accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 6),
                Text(CurrencyFormatter.format(t.budget, t.currencyCode),
                    style: const TextStyle(
                        color: kAmber,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                if (t.skillRequired.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('• ${t.skillRequired}',
                        style:
                            const TextStyle(color: kSub, fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ],
            ),
            if (t.title.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(t.title,
                  style: const TextStyle(color: kSub, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline_rounded,
              color: Colors.redAccent, size: 20),
          onPressed: () => _deleteTemplate(context, t.id!),
        ),
      ),
    );
  }
}

// Public so HostShell's speed dial can show the same "not verified" prompt
// as the (now-removed) dashboard post-gig cards used to.
void showUnverifiedHostModal(
  BuildContext context,
) {
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
              color: ( Colors.red).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Account not Verified',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Your account needs to be verified before you can continue. Please request verification from the admin.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:  Colors.red,
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
