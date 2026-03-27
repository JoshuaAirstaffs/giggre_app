import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_provider.dart';
import '../../auth/presentation/login_screen.dart';
import 'post_quick_gig_screen.dart';
import 'post_open_gig_screen.dart';
import 'post_offered_gig_screen.dart';
import 'gig_host_profile_screen.dart';
import '../services/quick_gig_matching_service.dart';

class GigHostScreen extends StatefulWidget {
  const GigHostScreen({super.key});

  @override
  State<GigHostScreen> createState() => _GigHostScreenState();
}

class _GigHostScreenState extends State<GigHostScreen> {
  String _userName = '';

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
    setState(() => _userName = doc.data()?['name'] ?? '');
  }

  void _showProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GigHostProfileScreen()),
    );
  }

  void _showTemplates() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final cardColor = Theme.of(context).cardColor;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: kBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bookmark_add_outlined, color: kBlue, size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              'Saved Templates',
              style: TextStyle(color: onSurface, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Save your gig posts as templates\nfor faster reposting.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kSub, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: kBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBlue.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.construction_rounded, color: kBlue, size: 16),
                  SizedBox(width: 8),
                  Text('Templates coming soon', style: TextStyle(color: kBlue, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Log Out',
            style:
                TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: const Text('Are you sure you want to log out?',
            style: TextStyle(color: kSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: kSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstName = _userName.split(' ').first;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          tooltip: 'Switch Role',
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: kSub, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: kAmber.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.business_center_outlined,
                    color: kAmber, size: 16),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Gig Host',
                    style: TextStyle(
                        color: onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                const Text('Dashboard',
                    style: TextStyle(color: kSub, fontSize: 10)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle_outlined, color: kSub),
            onPressed: _showProfile,
          ),
          IconButton(
            tooltip: 'Saved Templates',
            icon: const Icon(Icons.bookmark_add_outlined, color: kSub),
            onPressed: _showTemplates,
          ),
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Log Out',
            icon: const Icon(Icons.logout_rounded, color: kSub),
            onPressed: _logout,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Greeting ──────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: kAmber.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.account_circle_rounded,
                        color: kAmber, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    firstName.isNotEmpty ? 'Hey, $firstName 👋' : 'Welcome, Host!',
                    style: TextStyle(
                        color: onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text('Manage your gigs and find workers.',
                  style: TextStyle(color: kSub, fontSize: 13)),
              const SizedBox(height: 24),

              // ── Stats ─────────────────────────────────────────
              _StatsRow(uid: uid),
              const SizedBox(height: 28),

              // ── Workers Map ───────────────────────────────────
              const _WorkerMapSection(),
              const SizedBox(height: 28),

              // ── Post a Gig ────────────────────────────────────
              Text('Post a Gig',
                  style: TextStyle(
                      color: onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _GigTypeCard(
                title: 'Quick Gig',
                subtitle: 'Simple tasks — no skills required',
                example: 'e.g. Dishwashing, Cleaning, Delivery',
                icon: Icons.flash_on_rounded,
                accentColor: kAmber,
                badge: 'AVAILABLE',
                badgeColor: kAmber,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PostQuickGigScreen(hostName: _userName),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _GigTypeCard(
                title: 'Open Gig',
                subtitle: 'Skilled tasks for qualified workers',
                example: 'e.g. Plumbing, Web Dev, Accounting',
                icon: Icons.workspace_premium_outlined,
                accentColor: kBlue,
                badge: 'AVAILABLE',
                badgeColor: kBlue,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PostOpenGigScreen(hostName: _userName),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _GigTypeCard(
                title: 'Offered Gig',
                subtitle: 'Direct offers to specific workers',
                example: 'e.g. Invite someone you trust',
                icon: Icons.send_rounded,
                accentColor: const Color(0xFF8B5CF6),
                badge: 'AVAILABLE',
                badgeColor: const Color(0xFF8B5CF6),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PostOfferedGigScreen(hostName: _userName),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ── Recent Gigs ───────────────────────────────────
              Text('Your Gigs',
                  style: TextStyle(
                      color: onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _RecentGigsList(uid: uid),
            ],
          ),
        ),
      ),
    );
  }
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
  late StreamSubscription _quickSub, _openSub, _offeredSub;

  static bool _isActive(String s) =>
      s == 'scanning' || s == 'active' || s == 'open' || s == 'offered';

  void _recompute() {
    final all = [..._quick, ..._open, ..._offered];
    setState(() {
      _total = all.length;
      _active = all.where((d) => _isActive(d['status'] as String? ?? '')).length;
      _done = all.where((d) => d['status'] == 'completed').length;
    });
  }

  @override
  void initState() {
    super.initState();
    final db = FirebaseFirestore.instance;
    _quickSub = db.collection('quick_gigs').where('hostId', isEqualTo: widget.uid).snapshots().listen((s) {
      _quick = s.docs.map((d) => d.data() as Map).toList();
      _recompute();
    });
    _openSub = db.collection('open_gigs').where('hostId', isEqualTo: widget.uid).snapshots().listen((s) {
      _open = s.docs.map((d) => d.data() as Map).toList();
      _recompute();
    });
    _offeredSub = db.collection('offered_gigs').where('hostId', isEqualTo: widget.uid).snapshots().listen((s) {
      _offered = s.docs.map((d) => d.data() as Map).toList();
      _recompute();
    });
  }

  @override
  void dispose() {
    _quickSub.cancel();
    _openSub.cancel();
    _offeredSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(label: 'Posted', value: _total, color: kAmber),
        const SizedBox(width: 10),
        _StatCard(label: 'Active', value: _active, color: const Color(0xFF22C55E)),
        const SizedBox(width: 10),
        _StatCard(label: 'Done', value: _done, color: kBlue),
      ],
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
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
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
//  Your Gigs List  (all 3 types, filterable)
// ─────────────────────────────────────────────────────────────────────────────
class _RecentGigsList extends StatefulWidget {
  final String uid;
  const _RecentGigsList({required this.uid});

  @override
  State<_RecentGigsList> createState() => _RecentGigsListState();
}

class _RecentGigsListState extends State<_RecentGigsList> {
  String _filter = 'all';
  List<Map<String, dynamic>> _quick = [], _open = [], _offered = [];
  bool _loading = true;
  late StreamSubscription _quickSub, _openSub, _offeredSub;

  @override
  void initState() {
    super.initState();
    final db = FirebaseFirestore.instance;

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
            }));

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
            }));

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
            }));
  }

  @override
  void dispose() {
    _quickSub.cancel();
    _openSub.cancel();
    _offeredSub.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final List<Map<String, dynamic>> all;
    switch (_filter) {
      case 'quick':
        all = List.from(_quick);
        break;
      case 'open':
        all = List.from(_open);
        break;
      case 'offered':
        all = List.from(_offered);
        break;
      default:
        all = [..._quick, ..._open, ..._offered];
    }
    all.sort((a, b) {
      final aTs = a['createdAt'] as Timestamp?;
      final bTs = b['createdAt'] as Timestamp?;
      if (aTs == null || bTs == null) return 0;
      return bTs.toDate().compareTo(aTs.toDate());
    });
    return all;
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

    final filtered = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Filter tabs ──────────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterTab(label: 'All', selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
              const SizedBox(width: 8),
              _FilterTab(label: 'Quick', selected: _filter == 'quick', color: kAmber, onTap: () => setState(() => _filter = 'quick')),
              const SizedBox(width: 8),
              _FilterTab(label: 'Open', selected: _filter == 'open', color: kBlue, onTap: () => setState(() => _filter = 'open')),
              const SizedBox(width: 8),
              _FilterTab(label: 'Offered', selected: _filter == 'offered', color: const Color(0xFF8B5CF6), onTap: () => setState(() => _filter = 'offered')),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Gig tiles ────────────────────────────────────────────
        if (filtered.isEmpty)
          _EmptyGigsPlaceholder(filter: _filter)
        else
          ...filtered.map((d) => _GigTile(data: d)),
      ],
    );
  }
}

class _FilterTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _FilterTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = kSub,
  });

  @override
  Widget build(BuildContext context) {
    final accent = selected ? color : kSub;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.15) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.5) : Theme.of(context).dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? accent : kSub,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _EmptyGigsPlaceholder extends StatelessWidget {
  final String filter;
  const _EmptyGigsPlaceholder({required this.filter});

  @override
  Widget build(BuildContext context) {
    final label = filter == 'all' ? 'gigs' : '$filter gigs';
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
            'No $label posted yet',
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
}

class _GigTile extends StatefulWidget {
  final Map<String, dynamic> data;
  const _GigTile({required this.data});

  @override
  State<_GigTile> createState() => _GigTileState();
}

class _GigTileState extends State<_GigTile> {
  static String _collectionFor(String gigType) {
    switch (gigType) {
      case 'open':    return 'open_gigs';
      case 'offered': return 'offered_gigs';
      default:        return 'quick_gigs';
    }
  }

  Future<void> _confirmCancel() async {
    final gigType = widget.data['gigType'] as String? ?? 'quick';
    final docId   = widget.data['docId']   as String? ?? '';
    if (docId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Cancel Gig',
            style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface)),
        content: const Text(
            'Mark this gig as cancelled? Workers will no longer see it.',
            style: TextStyle(color: kSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No', style: TextStyle(color: kSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Gig',
                style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance
        .collection(_collectionFor(gigType))
        .doc(docId)
        .update({'status': 'cancelled'});
    messenger.showSnackBar(const SnackBar(
      content: Text('Gig cancelled'),
      backgroundColor: Colors.orange,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _confirmDelete() async {
    final gigType = widget.data['gigType'] as String? ?? 'quick';
    final docId   = widget.data['docId']   as String? ?? '';
    if (docId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Gig',
            style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface)),
        content: const Text(
            'This will permanently remove the gig. This cannot be undone.',
            style: TextStyle(color: kSub)),
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
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance
        .collection(_collectionFor(gigType))
        .doc(docId)
        .delete();
    messenger.showSnackBar(const SnackBar(
      content: Text('Gig deleted'),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _dispatchGig() async {
    final gigType = widget.data['gigType'] as String? ?? 'quick';
    if (gigType != 'quick') return;
    final docId = widget.data['docId'] as String? ?? '';
    if (docId.isEmpty) return;
    final location = widget.data['location'] as GeoPoint?;
    if (location == null) return;

    // Reset to scanning (keep exclusion list — workers who declined stay excluded)
    await FirebaseFirestore.instance.collection('quick_gigs').doc(docId).update({
      'status': 'scanning',
      'assignedWorkerId': null,
      'assignedWorkerName': null,
      'searchStartedAt': FieldValue.serverTimestamp(),
    });

    // Start smart dispatch
    QuickGigMatchingService.startAutoSearch(gigId: docId, gigLocation: location);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Searching for available workers...'),
          backgroundColor: kAmber,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'scanning':   return kAmber;
      case 'dispatched': return kBlue;
      case 'accepted':   return const Color(0xFF22C55E);
      case 'open':       return const Color(0xFF22C55E);
      case 'offered':    return const Color(0xFF8B5CF6);
      case 'active':     return const Color(0xFF22C55E);
      case 'assigned':   return kBlue;
      case 'no_worker':  return Colors.redAccent;
      case 'completed':  return const Color(0xFF22C55E);
      case 'cancelled':  return Colors.redAccent;
      default:           return kSub;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'scanning':   return 'SCANNING';
      case 'dispatched': return 'DISPATCHED';
      case 'accepted':   return 'ACCEPTED';
      case 'no_worker':  return 'NO WORKER';
      case 'completed':  return 'COMPLETED';
      case 'cancelled':  return 'CANCELLED';
      default:           return status.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data      = widget.data;
    final gigType   = data['gigType'] as String? ?? 'quick';
    final status    = data['status']  as String? ?? 'scanning';
    final statusColor = _statusColor(status);
    final titleColor  = Theme.of(context).colorScheme.onSurface;
    final isClosed    = status == 'cancelled' || status == 'completed';

    final IconData typeIcon;
    final Color typeColor;
    final String typeLabel;
    switch (gigType) {
      case 'open':
        typeIcon  = Icons.workspace_premium_outlined;
        typeColor = kBlue;
        typeLabel = 'Open';
        break;
      case 'offered':
        typeIcon  = Icons.send_rounded;
        typeColor = const Color(0xFF8B5CF6);
        typeLabel = 'Offered';
        break;
      default:
        typeIcon  = Icons.flash_on_rounded;
        typeColor = kAmber;
        typeLabel = 'Quick';
    }

    String subtitle = '';
    if (gigType == 'open') {
      final skills = List<String>.from(data['requiredSkills'] ?? []);
      subtitle = skills.take(2).join(', ');
    } else if (gigType == 'offered') {
      final workerName = data['workerName'] as String? ?? '';
      if (workerName.isNotEmpty) subtitle = '→ $workerName';
    } else {
      final assignedWorkerName = data['assignedWorkerName'] as String?;
      if ((status == 'dispatched' || status == 'accepted') &&
          assignedWorkerName != null &&
          assignedWorkerName.isNotEmpty) {
        subtitle = '→ $assignedWorkerName';
      } else if (status == 'no_worker') {
        subtitle = 'No worker found';
      } else {
        subtitle = data['category'] as String? ?? '';
      }
    }

    final createdAt = data['createdAt'] != null
        ? (data['createdAt'] as Timestamp).toDate()
        : DateTime.now();
    final diff    = DateTime.now().difference(createdAt);
    final timeAgo = diff.inMinutes < 60
        ? '${diff.inMinutes}m ago'
        : diff.inHours < 24
            ? '${diff.inHours}h ago'
            : '${diff.inDays}d ago';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          // ── Type icon ──────────────────────────────
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(typeIcon, color: typeColor, size: 22),
          ),
          const SizedBox(width: 12),

          // ── Title + subtitle ───────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data['title'] as String? ?? 'Untitled Gig',
                        style: TextStyle(
                            color: titleColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                            color: typeColor,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (subtitle.isNotEmpty) ...[
                      Flexible(
                        child: Text(subtitle,
                            style:
                                const TextStyle(color: kSub, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const Text(' · ',
                          style: TextStyle(color: kSub, fontSize: 12)),
                    ],
                    Text(
                      '\$${(data['budget'] as num?)?.toStringAsFixed(0) ?? '0'}',
                      style: const TextStyle(
                          color: kAmber,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                    const Text(' · ',
                        style: TextStyle(color: kSub, fontSize: 12)),
                    Text(timeAgo,
                        style: const TextStyle(color: kSub, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // ── Status badge + menu ────────────────────
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 20,
                width: 20,
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_horiz_rounded,
                      color: kSub, size: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  onSelected: (val) {
                    if (val == 'dispatch') _dispatchGig();
                    if (val == 'cancel') _confirmCancel();
                    if (val == 'delete') _confirmDelete();
                  },
                  itemBuilder: (ctx) => [
                    if (!isClosed &&
                        gigType == 'quick' &&
                        (status == 'scanning' ||
                            status == 'no_worker' ||
                            status == 'dispatched'))
                      PopupMenuItem(
                        value: 'dispatch',
                        child: Row(
                          children: [
                            Icon(Icons.send_rounded, color: kAmber, size: 18),
                            const SizedBox(width: 10),
                            Text('Dispatch',
                                style: TextStyle(color: kAmber)),
                          ],
                        ),
                      ),
                    if (!isClosed)
                      const PopupMenuItem(
                        value: 'cancel',
                        child: Row(
                          children: [
                            Icon(Icons.cancel_outlined,
                                color: Colors.orange, size: 18),
                            SizedBox(width: 10),
                            Text('Cancel Gig',
                                style: TextStyle(color: Colors.orange)),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded,
                              color: Colors.redAccent, size: 18),
                          SizedBox(width: 10),
                          Text('Delete',
                              style: TextStyle(color: Colors.redAccent)),
                        ],
                      ),
                    ),
                  ],
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
//  Worker Data
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerData {
  final String id;
  final String name;
  final String skill;
  final LatLng position;

  _WorkerData({
    required this.id,
    required this.name,
    required this.skill,
    required this.position,
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
  const _WorkerMapSection();

  @override
  State<_WorkerMapSection> createState() => _WorkerMapSectionState();
}

class _WorkerMapSectionState extends State<_WorkerMapSection> {
  final _mapController = MapController();
  double _zoom = 12.0;
  LatLng? _myLocation;
  List<_WorkerData> _workers = [];
  StreamSubscription? _workerSub;

  @override
  void initState() {
    super.initState();
    _fetchAndCenterMap();
    _startWorkersSub();
  }

  @override
  void dispose() {
    _workerSub?.cancel();
    _mapController.dispose();
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
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      _mapController.move(_myLocation!, 14.0);
    } catch (_) {}
  }

  void _startWorkersSub() {
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
        );
      }).whereType<_WorkerData>().toList();
      if (mounted) setState(() => _workers = workers);
    });
  }

  // Grid cell size shrinks as zoom increases — smaller = less grouping
  static double _gridSize(double zoom) {
    if (zoom < 10) return 0.15;
    if (zoom < 11) return 0.08;
    if (zoom < 12) return 0.04;
    if (zoom < 13) return 0.02;
    if (zoom < 14) return 0.008;
    return 0.0; // individual markers
  }

  List<_WorkerCluster> _buildClusters() {
    final gridSize = _gridSize(_zoom);

    if (gridSize == 0.0) {
      return _workers
          .map((w) => _WorkerCluster(
                center: w.position,
                count: 1,
                workers: [w],
                singleWorker: w,
              ))
          .toList();
    }

    final Map<String, List<_WorkerData>> grid = {};
    for (final w in _workers) {
      final latKey = (w.position.latitude / gridSize).floor();
      final lngKey = (w.position.longitude / gridSize).floor();
      grid.putIfAbsent('$latKey:$lngKey', () => []).add(w);
    }

    return grid.values.map((group) {
      final avgLat = group.fold(0.0, (s, w) => s + w.position.latitude) / group.length;
      final avgLng = group.fold(0.0, (s, w) => s + w.position.longitude) / group.length;
      return _WorkerCluster(
        center: LatLng(avgLat, avgLng),
        count: group.length,
        workers: group,
        singleWorker: group.length == 1 ? group.first : null,
      );
    }).toList();
  }

  List<Marker> _buildMarkers() {
    return _buildClusters().map((cluster) {
      if (cluster.count == 1 && cluster.singleWorker != null) {
        return Marker(
          point: cluster.center,
          width: 40,
          height: 48,
          child: _WorkerPin(worker: cluster.singleWorker!),
        );
      }
      return Marker(
        point: cluster.center,
        width: 56,
        height: 56,
        child: _ClusterBadge(count: cluster.count, workers: cluster.workers),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
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
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 280,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(14.5995, 120.9842),
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
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
                            color: const Color(0xFF22C55E),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF22C55E).withValues(alpha: 0.45),
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
            'Zoom in to see individual workers · Tap a pin for details',
            style: TextStyle(color: kSub.withValues(alpha: 0.7), fontSize: 11),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Individual Worker Pin
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerPin extends StatelessWidget {
  final _WorkerData worker;
  const _WorkerPin({required this.worker});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showWorkerSheet(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: kBlue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: kBlue.withValues(alpha: 0.45),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 20),
          ),
          // Pointer triangle
          CustomPaint(
            painter: _TrianglePainter(color: kBlue),
            size: const Size(10, 6),
          ),
        ],
      ),
    );
  }

  void _showWorkerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cardColor = Theme.of(ctx).cardColor;
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
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
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: kBlue.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: kBlue, size: 30),
              ),
              const SizedBox(height: 12),
              Text(worker.name,
                  style: TextStyle(color: onSurface, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(worker.skill, style: const TextStyle(color: kSub, fontSize: 13)),
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
                      style: TextStyle(color: Color(0xFF22C55E), fontSize: 12)),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx),
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
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Cluster Badge
// ─────────────────────────────────────────────────────────────────────────────
class _ClusterBadge extends StatelessWidget {
  final int count;
  final List<_WorkerData> workers;
  const _ClusterBadge({required this.count, required this.workers});

  void _showWorkerList(BuildContext context) {
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
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              // Header
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
                        Text('$count Workers in this area',
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
              // Worker list
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
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: kBlue.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person,
                            color: kBlue, size: 22),
                      ),
                      title: Text(w.name,
                          style: TextStyle(
                              color: onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      subtitle: Row(
                        children: [
                          const Icon(Icons.work_outline_rounded,
                              color: kSub, size: 12),
                          const SizedBox(width: 4),
                          Text(w.skill,
                              style: const TextStyle(
                                  color: kSub, fontSize: 12)),
                          const SizedBox(width: 10),
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
                                  color: Color(0xFF22C55E),
                                  fontSize: 11)),
                        ],
                      ),
                      trailing: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                          backgroundColor:
                              kBlue.withValues(alpha: 0.1),
                          foregroundColor: kBlue,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          minimumSize: Size.zero,
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Offer',
                            style: TextStyle(
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
      onTap: () => _showWorkerList(context),
      child: Container(
        width: 56,
        height: 56,
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
                height: 1,
              ),
            ),
            const Text(
              'workers',
              style: TextStyle(
                  color: Colors.black87, fontSize: 8, letterSpacing: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Triangle pointer painter for worker pin
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
