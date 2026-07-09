import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/current_user_provider.dart';
import '../../../core/services/gms_availability.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_provider.dart';
import '../../auth/presentation/login_screen.dart';
import 'post_quick_gig_screen.dart';
import 'post_open_gig_screen.dart';
import 'post_offered_gig_screen.dart';
import 'gig_host_profile_screen.dart';
import '../models/gig_template_model.dart';
import '../../../core/utils/currency_formatter.dart';
import 'widgets/admin_gig_config_sheet.dart';
import 'widgets/notifications_sheet.dart';
import 'host_gigs_screen.dart';

class GigHostScreen extends StatefulWidget {
  const GigHostScreen({super.key});

  @override
  State<GigHostScreen> createState() => _GigHostScreenState();
}

class _GigHostScreenState extends State<GigHostScreen> {
  String _userName = '';
  String? _isVerified;
  String _photoUrl = '';
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
      _isVerified = doc.data()?['isVerified'] ?? '';
      _photoUrl = doc.data()?['photoUrl'] ?? '';
    });
  }

  void _showProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GigHostProfileScreen()),
    );
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
Future<void> _logout() async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54, height: 54,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 22),
            ),
            const SizedBox(height: 14),
            Text(
              'Log out?',
              style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "You'll need to sign back in to access your account.",
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
                          borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20)),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel', style: TextStyle(color: kSub, fontSize: 15)),
                    ),
                  ),
                  const VerticalDivider(width: 0.5, thickness: 0.5),
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(bottomRight: Radius.circular(20)),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Log out',
                          style: TextStyle(color: Colors.redAccent, fontSize: 15, fontWeight: FontWeight.w600)),
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

  if (confirm == true) {
    if (mounted) {
      context.read<CurrentUserProvider>().clearUser();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
    await WidgetsBinding.instance.endOfFrame;
    await GoogleSignIn().disconnect();
    await FirebaseAuth.instance.signOut();
  }
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
              onProfile: _showProfile,
              onTemplates: _showTemplates,
              onLogout: _logout,
            ),
          ),

          // ── Body content ──────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Post a Gig ─────────────────────────────────
                const _HostSectionLabel('Post a gig'),
                const SizedBox(height: 10),
                _FullWidthGigCard(
                  title: 'Quick Gig',
                  subtitle: 'Simple tasks, no skills required',
                  icon: Icons.bolt_rounded,
                  accentColor: kGold,
                  onTap: () {
                    if (_isVerified == 'verified') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PostQuickGigScreen(hostName: _userName),
                        ),
                      );
                    } else {
                      _showModal(context);
                    }
                  },
                ),
                const SizedBox(height: 10),
                _FullWidthGigCard(
                  title: 'Open Gig',
                  subtitle: 'Skilled tasks for qualified workers',
                  icon: Icons.workspace_premium_outlined,
                  accentColor: kBlue,
                  onTap: () {
                    if (_isVerified == 'verified') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PostOpenGigScreen(hostName: _userName),
                        ),
                      );
                    } else {
                      _showModal(context);
                    }
                  },
                ),
                const SizedBox(height: 10),
                _FullWidthGigCard(
                  title: 'Offered Gig',
                  subtitle: 'Direct offers to specific workers you trust',
                  icon: Icons.send_rounded,
                  accentColor: const Color(0xFF8B5CF6),
                  onTap: () {
                    if (_isVerified == 'verified') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PostOfferedGigScreen(hostName: _userName),
                        ),
                      );
                    } else {
                      _showModal(context);
                    }
                  },
                ),
                const SizedBox(height: 24),

                // ── Workers Near You ───────────────────────────
                _WorkerMapSection(hostName: _userName),
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
  final VoidCallback onProfile;
  final VoidCallback onTemplates;
  final VoidCallback onLogout;

  const _HostHeader({
    required this.firstName,
    required this.photoUrl,
    required this.uid,
    required this.onProfile,
    required this.onTemplates,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Gold gradient band
        Container(
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
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Action row ──────────────────────────────
                  Row(
                    children: [
                      // Left: back + "Gig Host / Dashboard" label
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Gig Host',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Dashboard',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
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
                                      color: Colors.white,
                                    ),
                                    onPressed: () =>
                                        NotificationsSheet.show(context),
                                    style: IconButton.styleFrom(
                                      foregroundColor: Colors.white,
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
                          // Profile
                          IconButton(
                            tooltip: 'Profile',
                            icon: const Icon(
                              Icons.account_circle_outlined,
                              color: Colors.white,
                            ),
                            onPressed: onProfile,
                            style: IconButton.styleFrom(
                                foregroundColor: Colors.white),
                          ),
                          // More menu (templates + gig config)
                          PopupMenuButton<String>(
                            tooltip: 'More',
                            icon: const Icon(
                              Icons.more_vert_rounded,
                              color: Colors.white,
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
                          // Theme toggle (white-tinted)
                          ColorFiltered(
                            colorFilter: const ColorFilter.mode(
                              Colors.white,
                              BlendMode.srcIn,
                            ),
                            child: const ThemeToggleButton(),
                          ),
                          // Logout
                          IconButton(
                            tooltip: 'Log Out',
                            icon: const Icon(
                              Icons.logout_rounded,
                              color: Colors.white,
                            ),
                            onPressed: onLogout,
                            style: IconButton.styleFrom(
                                foregroundColor: Colors.white),
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
                              firstName.isNotEmpty
                                  ? 'Hey, $firstName 👋'
                                  : 'Welcome, Host!',
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
        // Stat cards directly below the gold band — full width, equal sizing
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: _StatsRow(uid: uid),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Full-Width Gig Card — horizontal icon + text + chevron
// ─────────────────────────────────────────────────────────────────────────────
class _FullWidthGigCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback? onTap;

  const _FullWidthGigCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(color: kSub, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: accentColor.withValues(alpha: 0.6),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Muted uppercase section label
// ─────────────────────────────────────────────────────────────────────────────
class _HostSectionLabel extends StatelessWidget {
  final String text;
  const _HostSectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: kSub,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Stats Row
// ─────────────────────────────────────────────────────────────────────────────
class _StatsRow extends StatefulWidget {
  final String uid;
  const _StatsRow({required this.uid});

  @override
  State<_StatsRow> createState() => _StatsRowState();
}

class _StatsRowState extends State<_StatsRow> {
  int _total = 0, _active = 0, _done = 0;
  List<Map> _quick = [], _open = [], _offered = [];
  StreamSubscription? _quickSub, _openSub, _offeredSub;

  static bool _isActive(Map d) {
    final s = d['status'] as String? ?? '';
    if (s == 'completed' || s == 'cancelled' || s.isEmpty) return false;
    final assignedWorker = d['assignedWorkerId'] as String?;
    return assignedWorker != null && assignedWorker.isNotEmpty;
  }

  void _recompute() {
    final all = [..._quick, ..._open, ..._offered];
    setState(() {
      _total = all.length;
      _active = all.where((d) => _isActive(d)).length;
      _done = all.where((d) => d['status'] == 'completed').length;
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.uid.isEmpty) return;
    final db = FirebaseFirestore.instance;
    void onErr(Object e) {
      if (FirebaseAuth.instance.currentUser == null) return;
      debugPrint('[_StatsRow] stream error: $e');
    }

    _quickSub = db.collection('quick_gigs').where('hostId', isEqualTo: widget.uid).snapshots().listen((s) {
      _quick = s.docs.map((d) => d.data() as Map).toList();
      _recompute();
    }, onError: onErr);
    _openSub = db.collection('open_gigs').where('hostId', isEqualTo: widget.uid).snapshots().listen((s) {
      _open = s.docs.map((d) => d.data() as Map).toList();
      _recompute();
    }, onError: onErr);
    _offeredSub = db.collection('offered_gigs').where('hostId', isEqualTo: widget.uid).snapshots().listen((s) {
      _offered = s.docs.map((d) => d.data() as Map).toList();
      _recompute();
    }, onError: onErr);
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
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _StatCard(label: 'Posted', value: _total, color: kAmber)),
          const SizedBox(width: 10),
          Expanded(child: _StatCard(label: 'Active', value: _active, color: const Color(0xFF22C55E))),
          const SizedBox(width: 10),
          Expanded(child: _StatCard(label: 'Done', value: _done, color: kBlue)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$value',
            style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: kSub, fontSize: 12)),
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
      children: preview.map((d) => GigTile(data: d, showActions: false)).toList(),
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
  const _WorkerMapSection({required this.hostName});

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
  List<_WorkerData> _workers = [];
  StreamSubscription? _workerSub;
  BuildContext? _context;

  @override
  void initState() {
    super.initState();
    _initMap();
    _startWorkersSub();
  }

  Future<void> _initMap() async {
    final hasGms = await GmsAvailability.isAvailable;
    if (mounted) setState(() => _useGoogleMaps = hasGms);
    _fetchAndCenterMap();
  }

  @override
  void dispose() {
    _workerSub?.cancel();
    _googleMapController?.dispose();
    _osmController.dispose();
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
      setState(() => _myLocation = loc);
      if (_useGoogleMaps) {
        _googleMapController?.animateCamera(
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
      if (mounted) setState(() => _workers = workers);
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
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
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
          width: 32,
          height: 32,
          child: GestureDetector(
            onTap: ctx != null ? () => _showWorkerSheet(ctx, worker) : null,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.lightBlue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: const Icon(Icons.person_rounded, color: Colors.white, size: 16),
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

  @override
  Widget build(BuildContext context) {
    _context = context;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final borderColor = Theme.of(context).dividerColor;

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
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 280,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: _useGoogleMaps
                    ? GoogleMap(
                        gestureRecognizers: _mapInteractive
                            ? <Factory<OneSequenceGestureRecognizer>>{
                                Factory<OneSequenceGestureRecognizer>(
                                  () => EagerGestureRecognizer(),
                                ),
                              }
                            : const <Factory<OneSequenceGestureRecognizer>>{},
                        onMapCreated: (controller) {
                          _googleMapController = controller;
                          if (_myLocation != null) {
                            _googleMapController?.animateCamera(
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
                          }
                        },
                      )
                    : _buildOsmMap(),
              ),
            ),
            // Tap-to-interact overlay
            if (!_mapInteractive)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
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
            // Lock-map button shown while map is interactive
            if (_mapInteractive)
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
                    color: _myLocation != null
                        ? const Color(0xFF22C55E)
                        : kSub,
                  ),
                ),
              ),
            ),
          ],
        ),
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

void _showModal(
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
