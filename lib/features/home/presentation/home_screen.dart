import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:giggre_app/core/providers/current_user_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:giggre_app/screens/app_contents/contact_us.dart';
import 'package:giggre_app/screens/app_contents/help_faq.dart';
import 'package:giggre_app/screens/app_contents/privacy_policy.dart';
import 'package:giggre_app/screens/app_contents/terms_and_conditions.dart';
import 'package:provider/provider.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:giggre_app/core/widgets/update_card.dart';
import 'package:giggre_app/screens/app_contents/about_giggre.dart';
import 'package:giggre_app/screens/giggre-updates.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/profile_tab_theme.dart';
import '../../../services/delete_acc_service.dart';
import '../../auth/presentation/welcome_screen.dart';
import '../../../screens/host/host_shell.dart';
import '../../../screens/worker/worker_shell.dart';
import '../../../widgets/active_gig_bar.dart';
import '../../gig_worker/presentation/verification_screen.dart';
import 'profile_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _userName = '';
  String _photoUrl = '';
  String? _selectedRole;
  bool _saving = false;
  bool _hasUpdate = false;
  bool _updateDismissed = false;
  bool _pendingDeletion = false;
  String _deletionStatus = 'pending_deletion';
  List<Map<String, dynamic>> _updates = [];
  bool _locationServiceEnabled = true;
  StreamSubscription<ServiceStatus>? _locationServiceSub;
  bool _internetAvailable = true;
  Timer? _internetCheckTimer;
  Stream<ActiveGigInfo?>? _activeGigStream;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _fetchUpdates();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _activeGigStream = watchActiveWorkerGig(uid);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAppUpdate();
      _initLocationServiceListener();
      _checkInternet();
      _internetCheckTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _checkInternet(),
      );
    });
  }

  Future<void> _initLocationServiceListener() async {
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) return;
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (mounted) setState(() => _locationServiceEnabled = enabled);
    _locationServiceSub = Geolocator.getServiceStatusStream().listen((status) {
      if (!mounted) return;
      setState(() => _locationServiceEnabled = status == ServiceStatus.enabled);
    });
  }

  Future<void> _checkInternet() async {
    if (kIsWeb) return;
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 5));
      final ok = result.isNotEmpty && result.first.rawAddress.isNotEmpty;
      if (mounted) setState(() => _internetAvailable = ok);
    } catch (_) {
      if (mounted) setState(() => _internetAvailable = false);
    }
  }

  @override
  void dispose() {
    _internetCheckTimer?.cancel();
    _locationServiceSub?.cancel();
    super.dispose();
  }

  Future<void> _checkAppUpdate() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        if (!mounted) return;
        setState(() => _hasUpdate = true);
        _showUpdateModal();
      }
    } catch (e) {
      debugPrint('[AppUpdate] check error: $e');
    }
  }

  void _showUpdateModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cardColor = Theme.of(ctx).cardColor;
        final borderColor = Theme.of(ctx).dividerColor;
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: kBlue.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
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
                  child: const Center(
                    child: Icon(
                      Icons.system_update_rounded,
                      color: kBlue,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'New Update Available',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'A new version of Giggre is available. Update now to get the latest features and improvements.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kSub, fontSize: 13.5, height: 1.6),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.of(ctx, rootNavigator: true).pop();
                      try {
                        await InAppUpdate.performImmediateUpdate();
                      } catch (e) {
                        debugPrint('[AppUpdate] update error: $e');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Update Now',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx, rootNavigator: true).pop();
                    if (mounted) setState(() => _updateDismissed = true);
                  },
                  child: const Text(
                    'Later',
                    style: TextStyle(color: kSub, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _fetchUpdates() async {
    try {
      final response = await FirebaseFirestore.instance
          .collection('app_content')
          .doc('updates')
          .collection('items')
          .get();

      final items = response.docs.map((doc) {
        final data = doc.data();
        if (data['dateCreated'] is Timestamp) {
          data['dateCreated'] = (data['dateCreated'] as Timestamp).toDate();
        }
        return data;
      }).toList();

      items.sort((a, b) {
        final aDate = a['dateCreated'] as DateTime?;
        final bDate = b['dateCreated'] as DateTime?;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      setState(() => _updates = items);
    } catch (e) {
      debugPrint('Error fetching updates: $e');
    }
  }

  void _showBetaModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cardColor = Theme.of(ctx).cardColor;
        final borderColor = Theme.of(ctx).dividerColor;
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: kBlue.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: kAmber.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.science_outlined,
                      color: kAmber,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: kAmber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kAmber.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'BETA VERSION',
                    style: TextStyle(
                      color: kAmber,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'You\'re using a Beta build',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Giggre is still in early access. Some features may be incomplete, change without notice, or behave unexpectedly.\n\nWe appreciate your patience as we continue building.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kSub, fontSize: 13.5, height: 1.6),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      'Got it, let\'s go!',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = doc.data();
    if (!mounted) return;
    setState(() {
      _userName = data?['name'] ?? '';
      _selectedRole = data?['role'];
      _photoUrl = data?['photoUrl'] ?? '';
    });
    final homeProvider = context.read<CurrentUserProvider>();
    homeProvider.setCurrentUserInfo(
      FirebaseAuth.instance.currentUser?.email,
      data?['name'],
      uid,
      data?['userId'],
      data?['isVerified'],
    );
    homeProvider.initCurrencyCode(uid, data ?? {});
    if (data?['pendingDeletion'] == true) {
      final reqSnap = await FirebaseFirestore.instance
          .collection('account_delete_requests')
          .where('userId', isEqualTo: uid)
          .where('status', whereIn: ['pending_deletion', 'approved'])
          .limit(1)
          .get();
      final status = reqSnap.docs.isNotEmpty
          ? reqSnap.docs.first['status'] as String
          : 'pending_deletion';
      if (!mounted) return;
      setState(() {
        _pendingDeletion = true;
        _deletionStatus = status;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPendingDeletionModal();
      });
    }
  }

  void _showPendingDeletionModal() {
    final isApproved = _deletionStatus == 'approved';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Theme.of(ctx).cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Theme.of(ctx).dividerColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.delete_forever_outlined,
                      color: Colors.redAccent,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  isApproved
                      ? 'Account Deletion Approved'
                      : 'Account Pending Deletion',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  isApproved
                      ? 'Your account deletion request has been approved by the admin. The deletion process will be completed after 30 days from the date you submitted your request. After completion, your profile and account details cannot be restored. Your account will be permanently deactivated, and your identity will be anonymized in shared gig records and other related history data.'
                      : 'Your account deletion request is pending admin review. Once approved, the deletion process will be completed after 30 days from the date you submitted your request. You can cancel this request at any time to restore full access.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      await DeleteAccountService.cancelDeletion(ctx);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        setState(() {
                          _pendingDeletion = false;
                          _deletionStatus = 'pending_deletion';
                        });
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1B6CA8),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel Deletion',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    Future<void>? clearing;
                    if (mounted) {
                      clearing = context
                          .read<CurrentUserProvider>()
                          .clearUser();
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                        (route) => false,
                      );
                    }
                    await clearing;
                    await FirebaseAuth.instance.signOut();
                  },
                  child: const Text(
                    'Sign Out',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectRole(String role) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _selectedRole = role;
    });

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'role': role,
      });
    }

    if (mounted) setState(() => _saving = false);
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          body: ProfileTab(
            initialRole: _selectedRole ?? 'worker',
            isTabRoot: false,
            onLogout: _logout,
          ),
        ),
      ),
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
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Colors.redAccent,
                  size: 22,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Log out?',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
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
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(20),
                            ),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context, false),
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
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text(
                          'Log out',
                          style: TextStyle(
                            color: Colors.redAccent,
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

    if (confirm == true) {
      Future<void>? clearing;
      if (mounted) {
        clearing = context.read<CurrentUserProvider>().clearUser();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      }
      await clearing;
      await GoogleSignIn().disconnect();
      await FirebaseAuth.instance.signOut();
    }
  }

  final GlobalKey<RefreshIndicatorState> _refreshKey =
      GlobalKey<RefreshIndicatorState>();
  int _carouselRefreshKey = 0;

  Future<void> _refreshAll() async {
    await Future.wait([_loadUser(), _fetchUpdates()]);
    if (mounted) setState(() => _carouselRefreshKey++);
  }

  void _openGiggreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _GiggreMenu(
        hasPendingUpdate: _hasUpdate && _updateDismissed,
        onUpdate: _showUpdateModal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isVerified = context.watch<CurrentUserProvider>().isVerified;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      bottomSheet: !_locationServiceEnabled
          ? SafeArea(
              child: Container(
                width: double.infinity,
                color: Colors.orange.shade700,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_off_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Location is turned off. Enable it to find nearby gigs.',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Geolocator.openLocationSettings(),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Enable',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : !_internetAvailable
          ? SafeArea(
              child: Container(
                width: double.infinity,
                color: Colors.red.shade700,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No internet connection. Some features may not work.',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: GestureDetector(
          onTap: _openGiggreMenu,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Gold bolt logo
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: kGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.bolt_rounded, color: kGold, size: 22),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Giggre',
                style: TextStyle(
                  color: onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        actions: [
          _IconSquareButton(icon: Icons.person_rounded, onTap: _openProfile),
          const SizedBox(width: 16),
          _IconSquareButton(icon: Icons.logout_rounded, onTap: _logout),
          const SizedBox(width: 10),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<ActiveGigInfo?>(
          stream: _activeGigStream,
          builder: (context, activeGigSnap) {
            final activeGig = activeGigSnap.data;
            return Stack(
              children: [
                _buildHomeContent(
                  context,
                  bottomPadding: activeGig != null ? 16 + 86 : 16,
                  isVerified: isVerified,
                ),
                if (activeGig != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ActiveGigBar(gig: activeGig),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHomeContent(
    BuildContext context, {
    required double bottomPadding,
    required String? isVerified,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final firstName = _userName.split(' ').first;
    final currentYear = DateTime.now().year;
    return RefreshIndicator(
      key: _refreshKey,
      onRefresh: _refreshAll,
      color: kGold,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 2. Profile strip ──────────────────────────
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: kGold.withValues(alpha: 0.15),
                  backgroundImage: _photoUrl.isNotEmpty
                      ? CachedNetworkImageProvider(_photoUrl)
                      : null,
                  child: _photoUrl.isEmpty
                      ? const Icon(Icons.person_rounded, color: kGold, size: 28)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        firstName.isNotEmpty
                            ? 'Hey, $firstName 👋'
                            : 'Welcome back 👋',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Choose a mode to get started',
                        style: TextStyle(color: kSub, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── Update banner (preserved) ─────────────────
            if (_hasUpdate) ...[
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _showUpdateModal,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: kBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBlue.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.system_update_rounded,
                        color: kBlue,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'A new version of Giggre is available!',
                          style: TextStyle(
                            color: kBlue,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: kBlue,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Update',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // ── Verification banner ───────────────────────
            if (isVerified != 'verified') ...[
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VerificationScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        color: Colors.amber,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Your account is not yet verified.',
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Verify Now',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── 3. Image carousel ─────────────────────────
            _TestimonialCarousel(key: ValueKey(_carouselRefreshKey)),

            const SizedBox(height: 24),

            // ── 4. Role segmented control ─────────────────
            _RoleSegmentedControl(
              selectedRole: _selectedRole,
              onSelect: _selectRole,
            ),

            // ── 5. Gold continue button ───────────────────
            if (_selectedRole != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving
                      ? null
                      : () {
                          if (_selectedRole == 'host') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const HostShell(),
                              ),
                            );
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const WorkerShell(),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedRole == 'worker' ? kBlue : kGold,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedRole == 'worker'
                                  ? 'Continue as Gig Worker'
                                  : 'Continue as Gig Host',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                ),
              ),
            ],

            const SizedBox(height: 28),

            // ── 6. Giggre Updates section ─────────────────
            Row(
              children: [
                Text(
                  'Giggre Updates',
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => GiggreUpdates()),
                  ),
                  child: const Text(
                    'See all',
                    style: TextStyle(
                      color: kGold,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            ..._updates
                .take(3)
                .map(
                  (update) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: UpdateCard(
                      title: update['title'] as String,
                      date: update['dateCreated'] as DateTime,
                      category: update['category'] as String,
                      description: update['body'] as String,
                    ),
                  ),
                ),

            const SizedBox(height: 16),

            // ── Footer ────────────────────────────────────
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset('assets/images/logo.png', width: 94, height: 64),
                  const Text(
                    'The fastest way to find gigs or hire workers near you.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: kSub),
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _FooterLink('About', AboutGiggre()),
                      _FooterLink('Terms', TermsAndConditions()),
                      _FooterLink('Privacy', PrivacyPolicy()),
                      _FooterLink('Help/FAQ', HelpFaq()),
                      _FooterLink('Contact Us', ContactUs()),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Copyright © $currentYear Giggre. All rights reserved.',
                    style: const TextStyle(fontSize: 12, color: kSub),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Small rounded-square icon button (AppBar actions)
// ─────────────────────────────────────────────
class _IconSquareButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconSquareButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Icon(icon, color: kSub, size: 19),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Role segmented control
// ─────────────────────────────────────────────
class _RoleSegmentedControl extends StatelessWidget {
  final String? selectedRole;
  final ValueChanged<String> onSelect;

  const _RoleSegmentedControl({
    required this.selectedRole,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final borderColor = Theme.of(context).dividerColor;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _RoleHalf(
                  icon: Icons.work_outline_rounded,
                  label: 'Gig Worker',
                  subtitle: 'Find gigs & earn money',
                  isSelected: selectedRole == 'worker',
                  selectedColor: kBlue,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(15),
                    bottomLeft: Radius.circular(15),
                  ),
                  onTap: () => onSelect('worker'),
                ),
              ),
              Container(width: 1, color: borderColor),
              Expanded(
                child: _RoleHalf(
                  icon: Icons.storefront_outlined,
                  label: 'Gig Host',
                  subtitle: 'Post gigs & find talent',
                  isSelected: selectedRole == 'host',
                  selectedColor: kGold,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(15),
                    bottomRight: Radius.circular(15),
                  ),
                  onTap: () => onSelect('host'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleHalf extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final Color selectedColor;
  final BorderRadius borderRadius;
  final VoidCallback onTap;

  const _RoleHalf({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.selectedColor,
    required this.borderRadius,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isSelected
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    final subColor = isSelected ? Colors.white70 : kSub;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? selectedColor
              : selectedColor.withValues(alpha: 0),
          borderRadius: borderRadius,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? Colors.white : kSub, size: 26),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: subColor, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Footer link
// ─────────────────────────────────────────────
class _FooterLink extends StatelessWidget {
  final String label;
  final Widget screen;

  const _FooterLink(this.label, this.screen);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
      child: Text(label, style: const TextStyle(fontSize: 12, color: kBlue)),
    );
  }
}

// ─────────────────────────────────────────────
//  Giggre menu (bottom sheet)
// ─────────────────────────────────────────────
const _kMenuGreen = Color(0xFF2E9E6B);
const _kMenuBlue = Color(0xFF2B6FB5);
const _kMenuPurple = Color(0xFF8B6FD8);
const _kMenuGoldDeep = Color(0xFFD88810);
const _kMenuPink = Color(0xFFEC4899);
const _kMenuSubtleLight = Color(0xFFB7C0CD);
const _kMenuHandleLight = Color(0xFFD5DCE6);

class _GiggreMenuItem {
  final String title;
  final IconData icon;
  final Widget screen;
  final Color color;
  final double tintAlphaLight;

  const _GiggreMenuItem({
    required this.title,
    required this.icon,
    required this.screen,
    required this.color,
    required this.tintAlphaLight,
  });
}

class _GiggreMenu extends StatelessWidget {
  final bool hasPendingUpdate;
  final VoidCallback onUpdate;

  const _GiggreMenu({this.hasPendingUpdate = false, required this.onUpdate});

  static final List<_GiggreMenuItem> gigMenuData = [
    _GiggreMenuItem(
      title: 'About Giggre',
      icon: Icons.info_outline_rounded,
      screen: AboutGiggre(),
      color: _kMenuBlue,
      tintAlphaLight: 0.12,
    ),
    _GiggreMenuItem(
      title: 'Terms & Conditions',
      icon: Icons.description_outlined,
      screen: TermsAndConditions(),
      color: _kMenuPurple,
      tintAlphaLight: 0.14,
    ),
    _GiggreMenuItem(
      title: 'Privacy Policy',
      icon: Icons.shield_outlined,
      screen: PrivacyPolicy(),
      color: _kMenuGreen,
      tintAlphaLight: 0.12,
    ),
    _GiggreMenuItem(
      title: 'Help/FAQ',
      icon: Icons.help_outline_rounded,
      screen: HelpFaq(),
      color: _kMenuGoldDeep,
      tintAlphaLight: 0.14,
    ),
    _GiggreMenuItem(
      title: 'Contact Us',
      icon: Icons.mail_outline_rounded,
      screen: ContactUs(),
      color: _kMenuPink,
      tintAlphaLight: 0.14,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    final handleColor = isDark ? Colors.white24 : _kMenuHandleLight;
    final subtleText = isDark ? tokens.textMuted : _kMenuSubtleLight;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.cardSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: handleColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),
                Image.asset('assets/images/logo.png', height: 40),
                const SizedBox(height: 12),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final version = snapshot.hasData
                        ? 'Version ${snapshot.data!.version}'
                        : 'Version ...';
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          version,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (hasPendingUpdate)
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              onUpdate();
                            },
                            child: Container(
                              height: 20,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: kBlue,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Update Available',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            height: 20,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _kMenuGreen.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              '✓ Latest',
                              style: TextStyle(
                                color: _kMenuGreen,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  'The fastest way to find jobs or hire workers near you',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subtleText, fontSize: 10.5),
                ),
                const SizedBox(height: 16),
                Container(height: 1, color: tokens.divider),
                for (var i = 0; i < gigMenuData.length; i++) ...[
                  _GiggreMenuRow(
                    item: gigMenuData[i],
                    isDark: isDark,
                    textColor: tokens.textPrimary,
                    chevronColor: subtleText,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => gigMenuData[i].screen),
                    ),
                  ),
                  if (i < gigMenuData.length - 1)
                    Divider(height: 1, color: tokens.divider),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GiggreMenuRow extends StatelessWidget {
  final _GiggreMenuItem item;
  final bool isDark;
  final Color textColor;
  final Color chevronColor;
  final VoidCallback onTap;

  const _GiggreMenuRow({
    required this.item,
    required this.isDark,
    required this.textColor,
    required this.chevronColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final alpha =
        isDark ? (item.tintAlphaLight + 0.08).clamp(0.0, 1.0) : item.tintAlphaLight;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 55,
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: alpha),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(item.icon, color: item.color, size: 17),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                item.title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: chevronColor, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Testimonial Carousel  (images from Firestore)
// ─────────────────────────────────────────────
class _CarouselItem {
  final String picture;
  final int sortNumber;

  const _CarouselItem({required this.picture, required this.sortNumber});

  factory _CarouselItem.fromMap(Map<String, dynamic> data) {
    return _CarouselItem(
      picture: data['picture'] as String? ?? '',
      sortNumber: (data['sortNumber'] as num?)?.toInt() ?? 0,
    );
  }
}

class _TestimonialCarousel extends StatefulWidget {
  const _TestimonialCarousel({super.key});

  @override
  State<_TestimonialCarousel> createState() => _TestimonialCarouselState();
}

class _TestimonialCarouselState extends State<_TestimonialCarousel> {
  int _current = 0;
  List<_CarouselItem> _slides = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchSlides();
  }

  Future<void> _fetchSlides() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('app_content')
          .doc('carousel_items')
          .collection('items')
          .get();

      final items =
          snapshot.docs
              .map((doc) => _CarouselItem.fromMap(doc.data()))
              .where((item) => item.sortNumber != 0 && item.picture.isNotEmpty)
              .toList()
            ..sort((a, b) => a.sortNumber.compareTo(b.sortNumber));

      if (mounted) {
        setState(() {
          _slides = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: Theme.of(context).cardColor,
            child: const Center(
              child: CircularProgressIndicator(color: kGold, strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    if (_slides.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: CarouselSlider.builder(
            itemCount: _slides.length,
            options: CarouselOptions(
              viewportFraction: 1.0,
              padEnds: false,
              enlargeCenterPage: false,
              autoPlay: true,
              autoPlayInterval: const Duration(seconds: 5),
              autoPlayAnimationDuration: const Duration(milliseconds: 600),
              autoPlayCurve: Curves.easeInOut,
              onPageChanged: (index, _) => setState(() => _current = index),
            ),
            itemBuilder: (context, index, _) {
              return _SlideItem(pictureUrl: _slides[index].picture);
            },
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSmoothIndicator(
          activeIndex: _current,
          count: _slides.length,
          effect: const ExpandingDotsEffect(
            activeDotColor: kGold,
            dotColor: Color(0x5994A3B8), // kSub @ 35% opacity
            dotHeight: 6,
            dotWidth: 6,
            expansionFactor: 3.5,
            spacing: 6,
          ),
        ),
      ],
    );
  }
}

class _SlideItem extends StatelessWidget {
  final String pictureUrl;

  const _SlideItem({required this.pictureUrl});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: CachedNetworkImage(
          imageUrl: pictureUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          placeholder: (context, url) => Container(
            color: Theme.of(context).cardColor,
            child: const Center(
              child: CircularProgressIndicator(color: kGold, strokeWidth: 2),
            ),
          ),
          errorWidget: (context, url, error) =>
              Container(color: Theme.of(context).cardColor),
        ),
      ),
    );
  }
}
