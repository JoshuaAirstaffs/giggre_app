import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:giggre_app/core/providers/current_user_provider.dart';
import 'package:giggre_app/core/widgets/account_not_verified_modal.dart';
import 'package:giggre_app/core/services/sign_out_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:giggre_app/screens/app_contents/contact_us.dart';
import 'package:giggre_app/screens/app_contents/help_faq.dart';
import 'package:giggre_app/screens/app_contents/privacy_policy.dart';
import 'package:giggre_app/screens/app_contents/terms_and_conditions.dart';
import 'package:provider/provider.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:giggre_app/core/widgets/app_update_checker.dart';
import 'package:giggre_app/core/widgets/update_card.dart';
import 'package:giggre_app/core/widgets/entrance_animation.dart';
import 'package:giggre_app/screens/app_contents/about_giggre.dart';
import 'package:giggre_app/screens/giggre-updates.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/profile_tab_theme.dart';
import '../../../services/delete_acc_service.dart';
import '../../auth/presentation/welcome_screen.dart';
import '../../../screens/host/host_shell.dart';
import '../../../screens/worker/worker_shell.dart';
import '../../../widgets/active_gig_bar.dart';
import '../../wallet/presentation/wallet_screen.dart';
import 'profile_tab.dart';
import '../../gig_points/presentation/gig_points_button.dart';
import '../../gig_points/presentation/gig_points_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String _userName = '';
  String _photoUrl = '';
  String? _selectedRole;
  bool _saving = false;
  bool _hasUpdate = false;
  bool _pendingDeletion = false;
  String _deletionStatus = 'pending_deletion';
  List<Map<String, dynamic>> _updates = [];
  bool _internetAvailable = true;
  Timer? _internetCheckTimer;
  Stream<ActiveGigInfo?>? _activeGigStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUser();
    _fetchUpdates();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _activeGigStream = watchActiveWorkerGig(uid);
    _hasUpdate = AppUpdateChecker.updateAvailable.value;
    AppUpdateChecker.updateAvailable.addListener(_onUpdateAvailableChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowVerifyPrompt();
      _checkInternet();
      _internetCheckTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _checkInternet(),
      );
    });
  }

  // Replaces the old always-on "not verified" banner: shown once, right after
  // a fresh login (never on a restored session), only if still unverified.
  void _maybeShowVerifyPrompt() {
    final provider = context.read<CurrentUserProvider>();
    if (!provider.takeVerifyPromptAfterLogin()) return;
    showAccountNotVerifiedModal(
      context,
      onStatusRechecked: provider.updateVerificationStatus,
    );
  }

  void _onUpdateAvailableChanged() {
    if (mounted) setState(() => _hasUpdate = AppUpdateChecker.updateAvailable.value);
  }

  // The device's radios can go quiet while the screen is off, so the stale
  // "no internet" state from right before a lock can otherwise linger for up
  // to the full 30s timer period after the user turns the screen back on —
  // recheck immediately on resume instead of waiting for that tick.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkInternet();
    }
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
    WidgetsBinding.instance.removeObserver(this);
    AppUpdateChecker.updateAvailable.removeListener(_onUpdateAvailableChanged);
    _internetCheckTimer?.cancel();
    super.dispose();
  }


  Future<void> _fetchUpdates() async {
    try {
      final response = await FirebaseFirestore.instance
          .collection('app_content')
          .doc('updates')
          .collection('items')
          .get();

      // sortNumber 0 = hidden/unpublished in giggre-admin.
      final items = response.docs
          .where((doc) => ((doc.data()['sortNumber'] as num?) ?? 0) > 0)
          .map((doc) {
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
                        MaterialPageRoute(
                          builder: (_) => const WelcomeScreen(),
                        ),
                        (route) => false,
                      );
                    }
                    await clearing;
                    await FirebaseAuth.instance.signOut();
                  },
                  child: const Text(
                    'Log Out',
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

  void _openGigPoints() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GigPointsScreen()),
    );
  }

  void _openWallet() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WalletScreen(role: _selectedRole)),
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
                'Log Out?',
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
                          'Log Out',
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
      if (!mounted) return;
      await performSignOut(context);
    }
  }

  final GlobalKey<RefreshIndicatorState> _refreshKey =
      GlobalKey<RefreshIndicatorState>();
  int _refreshGeneration = 0;

  Future<void> _refreshAll() async {
    await Future.wait([_loadUser(), _fetchUpdates()]);
    if (mounted) setState(() => _refreshGeneration++);
  }

  void _openGiggreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _GiggreMenu(
        hasPendingUpdate: _hasUpdate,
        onUpdate: AppUpdateChecker.promptUpdateNow,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      // Location off is handled app-wide by LocationGate (main.dart).
      bottomSheet: !_internetAvailable
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
          child: Image.asset('assets/images/logo.png', height: 32),
        ),
        actions: [
          // Gig Points sits directly beside the profile (ProfileTab) button.
          GigPointsButton(onTap: _openGigPoints),
          const SizedBox(width: 8),
          _IconSquareButton(icon: Icons.person_rounded, onTap: _openProfile),
          const SizedBox(width: 8),
          _IconSquareButton(
            icon: Icons.account_balance_wallet_rounded,
            onTap: _openWallet,
          ),
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
            EntranceAnimation(
              key: ValueKey('profile-$_refreshGeneration'),
              type: EntranceAnimationType.fadeInSlideUp,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: kGold.withValues(alpha: 0.15),
                    backgroundImage: _photoUrl.isNotEmpty
                        ? CachedNetworkImageProvider(_photoUrl)
                        : null,
                    child: _photoUrl.isEmpty
                        ? const Icon(
                            Icons.person_rounded,
                            color: kGold,
                            size: 28,
                          )
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
            ),

            // ── Update banner (preserved) ─────────────────
            if (_hasUpdate) ...[
              const SizedBox(height: 14),
              GestureDetector(
                onTap: AppUpdateChecker.promptUpdateNow,
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

            const SizedBox(height: 20),

            // ── 3. Image carousel ─────────────────────────
            EntranceAnimation(
              key: ValueKey('carousel-$_refreshGeneration'),
              type: EntranceAnimationType.fadeInSlideUp,
              delay: const Duration(milliseconds: 80),
              child: _TestimonialCarousel(key: ValueKey(_refreshGeneration)),
            ),

            const SizedBox(height: 24),

            // ── 4. Role segmented control ─────────────────
            EntranceAnimation(
              key: ValueKey('role-$_refreshGeneration'),
              type: EntranceAnimationType.fadeInSlideUp,
              delay: const Duration(milliseconds: 160),
              child: _RoleSegmentedControl(
                selectedRole: _selectedRole,
                onSelect: _selectRole,
              ),
            ),

            // ── 5. Gold continue button ───────────────────
            if (_selectedRole != null) ...[
              const SizedBox(height: 16),
              EntranceAnimation(
                key: ValueKey('continue-$_refreshGeneration'),
                type: EntranceAnimationType.fadeInSlideUp,
                child: SizedBox(
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
                      backgroundColor: _selectedRole == 'worker'
                          ? kBlue
                          : kGold,
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
              ),
            ],

            const SizedBox(height: 28),

            // ── 6. Giggre Updates section ─────────────────
            EntranceAnimation(
              key: ValueKey('updates-header-$_refreshGeneration'),
              delay: const Duration(milliseconds: 240),
              child: Row(
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
            ),
            const SizedBox(height: 14),

            ..._updates
                .take(3)
                .toList()
                .asMap()
                .entries
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: EntranceAnimation(
                      key: ValueKey('update-${entry.key}-$_refreshGeneration'),
                      type: EntranceAnimationType.fadeInSlideUp,
                      delay: Duration(milliseconds: 280 + entry.key * 60),
                      child: UpdateCard(
                        title: entry.value['title'] as String,
                        date: entry.value['dateCreated'] as DateTime,
                        category: entry.value['category'] as String,
                        description: entry.value['body'] as String,
                      ),
                    ),
                  ),
                ),

            const SizedBox(height: 16),

            // ── Footer ────────────────────────────────────
            EntranceAnimation(
              key: ValueKey('footer-$_refreshGeneration'),
              delay: const Duration(milliseconds: 320),
              child: Container(
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
                    Image.asset(
                      'assets/images/logo.png',
                      width: 94,
                      height: 64,
                    ),
                    const Text(
                      'The fastest way to find gigs or get help near you.',
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
                        _FooterLink('Help', HelpFaq()),
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

const _kSupportContactName = 'Julius Airstaffs';
const _kSupportContactNumber = '0916-872-0618';

// Tap the logo 3 times to reach the maintainer's direct contact info.
class _SecretLogoTap extends StatefulWidget {
  const _SecretLogoTap();

  @override
  State<_SecretLogoTap> createState() => _SecretLogoTapState();
}

class _SecretLogoTapState extends State<_SecretLogoTap> {
  int _taps = 0;

  void _onTap() {
    _taps++;
    if (_taps >= 3) {
      _taps = 0;
      showDialog(
        context: context,
        builder: (_) => const _SupportContactDialog(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: Image.asset('assets/images/logo.png', height: 40),
    );
  }
}

class _SupportContactDialog extends StatelessWidget {
  const _SupportContactDialog();

  static const _accent = kGold;

  Future<void> _callNumber(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: _kSupportContactNumber);
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open dialer')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A2236) : Colors.white;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = isDark ? Colors.white54 : kSub;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.support_agent_rounded,
                color: _accent,
                size: 42,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Support Contact',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'For internal use only',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.person_rounded,
                        color: _accent,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _kSupportContactName,
                          style: TextStyle(
                            color: onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _callNumber(context),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.phone_rounded,
                          color: _accent,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _kSupportContactNumber,
                            style: TextStyle(
                              color: onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.call_rounded,
                          color: _accent,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Close',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      title: 'Terms of Service',
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
      title: 'Help & FAQ',
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
                const _SecretLogoTap(),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
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
                  'The fastest way to find gigs or get help near you',
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
    final alpha = isDark
        ? (item.tintAlphaLight + 0.08).clamp(0.0, 1.0)
        : item.tintAlphaLight;
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

  /// Optional MP4 (set in giggre-admin's Content Management). `picture`, if
  /// also set, is shown as the video's cover while it loads.
  final String video;

  /// ISO country codes (e.g. PH, US) this slide is limited to, set in
  /// giggre-admin. Empty — including slides saved before the field existed —
  /// means every country.
  final List<String> countries;

  const _CarouselItem({
    required this.picture,
    required this.sortNumber,
    this.video = '',
    this.countries = const [],
  });

  bool get hasVideo => video.isNotEmpty;

  /// Country used when the user's location couldn't be detected (location
  /// off, permission denied, lookup failed) — they see the US slides.
  static const defaultCountry = 'US';

  bool showsIn(String? countryCode) =>
      countries.isEmpty ||
      countries.contains((countryCode ?? defaultCountry).toUpperCase());

  factory _CarouselItem.fromMap(Map<String, dynamic> data) {
    final rawCountries = data['countries'];
    return _CarouselItem(
      picture: data['picture'] as String? ?? '',
      sortNumber: (data['sortNumber'] as num?)?.toInt() ?? 0,
      video: data['video'] as String? ?? '',
      countries: rawCountries is List
          ? rawCountries.whereType<String>().map((c) => c.toUpperCase()).toList()
          : const [],
    );
  }
}

class _TestimonialCarousel extends StatefulWidget {
  const _TestimonialCarousel({super.key});

  @override
  State<_TestimonialCarousel> createState() => _TestimonialCarouselState();
}

class _TestimonialCarouselState extends State<_TestimonialCarousel>
    with RouteAware {
  int _current = 0;
  // Another screen is on top of Home — the carousel stays mounted under it,
  // so videos must stop and auto-slide must not land on (and start) one.
  bool _covered = false;
  // False once Home is scrolled so that less than half the carousel shows
  bool _inView = true;
  PageRoute<void>? _subscribedRoute;
  List<_CarouselItem> _slides = [];
  bool _loading = true;
  // Starts with sound on; one choice applies to every video slide
  bool _muted = false;
  final CarouselSliderController _carousel = CarouselSliderController();
  final _videos = _CarouselVideoCache();
  // Slide whose video already advanced the carousel — two copies of a slide
  // can be built at once mid-swipe, and only one may move it on.
  int? _advancedFrom;

  @override
  void initState() {
    super.initState();
    _fetchSlides();
    // Slides can be limited by country; make sure it gets detected
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CurrentUserProvider>().ensureCountryCode();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // welcomeRouteObserver is the app's one RouteObserver (main.dart's
    // navigatorObservers), not specific to WelcomeScreen.
    final route = ModalRoute.of(context);
    if (route is PageRoute<void> && route != _subscribedRoute) {
      if (_subscribedRoute != null) welcomeRouteObserver.unsubscribe(this);
      _subscribedRoute = route;
      welcomeRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() => setState(() => _covered = true);

  @override
  void didPopNext() => setState(() => _covered = false);

  @override
  void dispose() {
    welcomeRouteObserver.unsubscribe(this);
    _videos.dispose();
    super.dispose();
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    // Reported after a short delay, so the carousel may be gone by now
    if (!mounted) return;
    final inView = info.visibleFraction >= 0.5;
    if (inView != _inView) setState(() => _inView = inView);
  }

  void _advanceFrom(int index) {
    if (index != _current || _advancedFrom == index) return;
    _advancedFrom = index;
    _carousel.nextPage();
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
              // A slide shows with an image, a video, or both
              .where(
                (item) =>
                    item.sortNumber != 0 &&
                    (item.picture.isNotEmpty || item.hasVideo),
              )
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

    // Only the slides meant for this user's country (US until a location is
    // detected). Filtered here rather than at fetch time so a country
    // detected after loading still applies.
    final countryCode = context.select<CurrentUserProvider, String?>(
      (p) => p.countryCode,
    );
    final slides = _slides.where((s) => s.showsIn(countryCode)).toList();

    if (slides.isEmpty) return const SizedBox.shrink();

    final current = _current.clamp(0, slides.length - 1);
    // A lone slide stays put — no auto-advance, looping, swipe or dots.
    final hasMultiple = slides.length > 1;
    // A video slide holds the carousel until it finishes, then advances itself.
    final currentIsVideo = slides[current].hasVideo;

    return Column(
      children: [
        VisibilityDetector(
          key: const Key('home-carousel'),
          onVisibilityChanged: _onVisibilityChanged,
          child: SizedBox(
            width: double.infinity,
            child: CarouselSlider.builder(
              carouselController: _carousel,
              itemCount: slides.length,
              options: CarouselOptions(
                viewportFraction: 1.0,
                padEnds: false,
                enlargeCenterPage: false,
                autoPlay:
                    hasMultiple && !currentIsVideo && !_covered && _inView,
                enableInfiniteScroll: hasMultiple,
                scrollPhysics: hasMultiple
                    ? null
                    : const NeverScrollableScrollPhysics(),
                autoPlayInterval: const Duration(seconds: 5),
                autoPlayAnimationDuration: const Duration(milliseconds: 600),
                autoPlayCurve: Curves.easeInOut,
                onPageChanged: (index, _) => setState(() {
                  _current = index;
                  _advancedFrom = null;
                }),
              ),
              itemBuilder: (context, index, _) {
                final slide = slides[index];
                if (!slide.hasVideo) {
                  return _SlideItem(pictureUrl: slide.picture);
                }
                return _VideoSlideItem(
                  videoUrl: slide.video,
                  coverUrl: slide.picture,
                  videos: _videos,
                  isActive: index == _current,
                  onScreen: !_covered && _inView,
                  loop: !hasMultiple,
                  muted: _muted,
                  onToggleMute: () => setState(() => _muted = !_muted),
                  onFinished: hasMultiple ? () => _advanceFrom(index) : null,
                );
              },
            ),
          ),
        ),
        if (hasMultiple) ...[
          const SizedBox(height: 12),
          AnimatedSmoothIndicator(
            activeIndex: current,
            count: slides.length,
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

/// A carousel slide that plays an MP4 over its cover image, with a
/// mute/unmute button.
///
/// Only the slide on screen loads and plays its video (so the carousel doesn't
/// download every video up front). Its player comes from [videos], which keeps
/// it after the slide scrolls away, so coming back plays again instantly. When
/// it finishes, [onFinished] advances the carousel; a lone slide loops
/// instead. If the video can't load, the cover stays up and the carousel moves
/// on after the usual 5 seconds.
class _VideoSlideItem extends StatefulWidget {
  final String videoUrl;
  final String coverUrl;
  final _CarouselVideoCache videos;
  final bool isActive;
  // False while another screen covers Home
  final bool onScreen;
  final bool loop;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback? onFinished;

  const _VideoSlideItem({
    required this.videoUrl,
    required this.coverUrl,
    required this.videos,
    required this.isActive,
    required this.onScreen,
    required this.loop,
    required this.muted,
    required this.onToggleMute,
    this.onFinished,
  });

  @override
  State<_VideoSlideItem> createState() => _VideoSlideItemState();
}

class _VideoSlideItemState extends State<_VideoSlideItem>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _finishedFired = false;
  Timer? _fallback;
  // Fires at the video's exact end — position updates only arrive about
  // every 500ms, and some devices send the completion event late.
  Timer? _endTimer;
  // While the video is open full screen, that page handles its ending
  bool _fullscreen = false;
  // Paused by the viewer — shared with the full screen page so both agree
  final _paused = ValueNotifier<bool>(false);
  // False while the app is in the background or the phone is locked. Handled
  // here, not by rebuilding: no frames run then, and the carousel's timers
  // could otherwise move on to this slide and start it with the screen off.
  bool _appActive = true;

  // Allowed to play: the current slide, Home is the visible screen, and the
  // app is in front. Our own full screen page covers Home too, but the video
  // carries on there.
  bool get _on =>
      widget.isActive && (widget.onScreen || _fullscreen) && _appActive;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appActive = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    if (_on) _activate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasOn = _on;
    _appActive = state == AppLifecycleState.resumed;
    if (_on && !wasOn) {
      _resumePlayback();
    } else if (!_on && wasOn) {
      _pausePlayback();
    }
  }

  @override
  void didUpdateWidget(covariant _VideoSlideItem old) {
    super.didUpdateWidget(old);
    final wasOn = old.isActive && (old.onScreen || _fullscreen) && _appActive;
    if (_on && !wasOn) {
      old.isActive ? _resumePlayback() : _activate();
    } else if (!_on && wasOn) {
      _pausePlayback();
    }
    if (widget.muted != old.muted && _ready) {
      _controller?.setVolume(widget.muted ? 0 : 1);
    }
  }

  Future<void> _activate() async {
    _endTimer?.cancel();
    _fallback?.cancel();
    // Hold the "finished" signal until playback has really restarted — a
    // reused player still reports its last run as completed until the seek.
    _finishedFired = true;
    try {
      final controller = await widget.videos.obtain(widget.videoUrl);
      if (!mounted) return;
      if (!identical(controller, _controller)) {
        // First time here, or the cache swapped in the downloaded copy
        _controller?.removeListener(_onTick);
        controller.addListener(_onTick);
        setState(() {
          _controller = controller;
          _ready = true;
        });
      }
      if (!_on) return;
      await controller.setVolume(widget.muted ? 0 : 1);
      await controller.setLooping(widget.loop);
      await controller.seekTo(Duration.zero);
      if (!mounted || !_on) return;
      _paused.value = false;
      await controller.play();
      _finishedFired = false;
    } catch (e) {
      debugPrint('Carousel video error: $e');
      // Keep the cover image and let the carousel move on as for an image.
      if (mounted && _on && widget.onFinished != null) {
        _finishedFired = false;
        _fallback = Timer(const Duration(seconds: 5), _finish);
      }
    }
  }

  void _pausePlayback() {
    _fallback?.cancel();
    _endTimer?.cancel();
    _controller?.pause();
  }

  // Back in view on the same slide (Home uncovered, or the app reopened):
  // carry on from where it stopped, unless the viewer paused it or it ended.
  void _resumePlayback() {
    final controller = _controller;
    if (!_ready || controller == null) {
      _activate();
      return;
    }
    if (!_paused.value &&
        !controller.value.isPlaying &&
        !controller.value.isCompleted) {
      controller.play();
      _finishedFired = false;
    }
    _onTick();
  }

  void _onTick() {
    final v = _controller?.value;
    if (v == null ||
        !v.isInitialized ||
        widget.loop ||
        !_on ||
        _fullscreen) {
      return;
    }
    // The player's own completion event, with the position as a backup for
    // platforms that report it a beat late — either way, advance right away.
    final ended =
        v.isCompleted ||
        (v.duration > Duration.zero && v.position >= v.duration);
    if (ended) {
      _finish();
      return;
    }
    // Re-aimed on every update so it tracks the real playback position;
    // held off while paused or buffering so a stall can't advance early.
    _endTimer?.cancel();
    if (v.isPlaying && !v.isBuffering && v.duration > Duration.zero) {
      _endTimer = Timer(v.duration - v.position, _finish);
    }
  }

  Future<void> _openFullscreen() async {
    final controller = _controller;
    if (controller == null || _fullscreen) return;
    _fullscreen = true;
    _endTimer?.cancel();
    final ended = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => _FullscreenVideoPage(
          controller: controller,
          muted: widget.muted,
          onToggleMute: widget.onToggleMute,
          paused: _paused,
          endsOnFinish: !widget.loop,
        ),
      ),
    );
    _fullscreen = false;
    if (!mounted) return;
    // Finished while full screen: move the carousel on, as it would have.
    // Closed early: carry on playing here and re-aim the end timer.
    ended == true ? _finish() : _onTick();
  }

  void _finish() {
    if (_finishedFired || !mounted || !widget.isActive) return;
    _finishedFired = true;
    widget.onFinished?.call();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    _paused.value = !_paused.value;
    _paused.value ? controller.pause() : controller.play();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fallback?.cancel();
    _endTimer?.cancel();
    // The player belongs to the carousel's cache, which outlives this slide
    _controller?.removeListener(_onTick);
    if (widget.isActive) _controller?.pause();
    _paused.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.coverUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: widget.coverUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(color: Theme.of(context).cardColor),
                errorWidget: (context, url, error) =>
                    Container(color: Theme.of(context).cardColor),
              )
            else
              // No cover: a spinner until the first frame is ready
              Container(
                color: Theme.of(context).cardColor,
                child: _ready
                    ? null
                    : const Center(
                        child: CircularProgressIndicator(
                          color: kGold,
                          strokeWidth: 2,
                        ),
                      ),
              ),
            if (_ready && controller != null)
              // Tapping the video pauses it and brings up the controls, which
              // stay until it plays again (tap again, or the center button)
              ValueListenableBuilder<bool>(
                valueListenable: _paused,
                builder: (context, paused, _) => _AutoHideControls(
                  pinned: paused,
                  onTap: _togglePlay,
                  controls: [
                    if (paused)
                      Center(
                        child: _VideoOverlayButton(
                          icon: Icons.play_arrow_rounded,
                          label: 'Play',
                          size: 32,
                          onTap: _togglePlay,
                        ),
                      ),
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: _VideoCountdown(controller: controller),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Row(
                        children: [
                          _VideoOverlayButton(
                            icon: widget.muted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            label: widget.muted ? 'Unmute' : 'Mute',
                            onTap: widget.onToggleMute,
                          ),
                          const SizedBox(width: 8),
                          _VideoOverlayButton(
                            icon: Icons.fullscreen_rounded,
                            label: 'Full screen',
                            onTap: _openFullscreen,
                          ),
                        ],
                      ),
                    ),
                  ],
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: controller.value.size.width,
                      height: controller.value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Remaining time of a video, e.g. 0:07, on a dark pill
class _VideoCountdown extends StatelessWidget {
  final VideoPlayerController controller;

  const _VideoCountdown({required this.controller});

  // Rounded up so it reads 0:01 until the very end
  static String _format(Duration d) {
    final total = (d.inMilliseconds / 1000).ceil();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, v, _) {
        final left = v.duration - v.position;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _format(left.isNegative ? Duration.zero : left),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}

/// Round translucent icon button shown over a video
class _VideoOverlayButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;

  const _VideoOverlayButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            color: Colors.white,
            size: size,
            semanticLabel: label,
          ),
        ),
      ),
    );
  }
}

/// A carousel video played full screen in landscape, on the same player as
/// its slide so it carries on from where it was. Pops with `true` when the
/// video finishes (if [endsOnFinish]), so the carousel can move on.
class _FullscreenVideoPage extends StatefulWidget {
  final VideoPlayerController controller;
  final bool muted;
  final VoidCallback onToggleMute;
  // The slide's own paused state, so pausing here carries back to it
  final ValueNotifier<bool> paused;
  final bool endsOnFinish;

  const _FullscreenVideoPage({
    required this.controller,
    required this.muted,
    required this.onToggleMute,
    required this.paused,
    required this.endsOnFinish,
  });

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  late bool _muted = widget.muted;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    widget.controller.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    // Back to portrait with the status/navigation bars on
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  void _onTick() {
    final v = widget.controller.value;
    if (!widget.endsOnFinish || !v.isInitialized) return;
    final ended =
        v.isCompleted ||
        (v.duration > Duration.zero && v.position >= v.duration);
    if (ended) _close(true);
  }

  void _close(bool ended) {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop(ended);
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    widget.onToggleMute();
  }

  void _togglePlay() {
    final paused = widget.paused;
    paused.value = !paused.value;
    paused.value ? widget.controller.pause() : widget.controller.play();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<bool>(
        valueListenable: widget.paused,
        builder: (context, paused, _) => _AutoHideControls(
          // Controls stay up while paused
          pinned: paused,
          controls: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Row(
                    children: [
                      _VideoOverlayButton(
                        icon: paused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        label: paused ? 'Play' : 'Pause',
                        onTap: _togglePlay,
                      ),
                      const SizedBox(width: 12),
                      _VideoCountdown(controller: controller),
                      const SizedBox(width: 12),
                      // Drag or tap to jump; the vertical padding gives the
                      // thin bar a finger-sized touch area
                      Expanded(
                        child: VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          colors: VideoProgressColors(
                            playedColor: kGold,
                            bufferedColor: Colors.white.withValues(alpha: 0.4),
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _VideoOverlayButton(
                        icon: _muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        label: _muted ? 'Unmute' : 'Mute',
                        onTap: _toggleMute,
                      ),
                      const SizedBox(width: 8),
                      _VideoOverlayButton(
                        icon: Icons.fullscreen_exit_rounded,
                        label: 'Exit full screen',
                        onTap: () => _close(false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
      ),
    );
  }
}

/// Video controls that start hidden. Tapping the video fades them in; they
/// fade slowly away again after [_showFor] without a touch, and tapping the
/// video while they're up hides them straight away. With [onTap], tapping the
/// video calls that instead. While [pinned] (e.g. paused) they stay up.
class _AutoHideControls extends StatefulWidget {
  final Widget child;
  // Laid out in a Stack over [child], e.g. Positioned buttons
  final List<Widget> controls;
  final bool pinned;
  final VoidCallback? onTap;

  const _AutoHideControls({
    required this.child,
    required this.controls,
    this.pinned = false,
    this.onTap,
  });

  @override
  State<_AutoHideControls> createState() => _AutoHideControlsState();
}

class _AutoHideControlsState extends State<_AutoHideControls> {
  static const _showFor = Duration(seconds: 3);

  late bool _visible = widget.pinned;
  Timer? _hideTimer;
  // Fingers on the controls — no fading out mid-drag on the time slider
  int _touches = 0;

  @override
  void didUpdateWidget(covariant _AutoHideControls old) {
    super.didUpdateWidget(old);
    if (widget.pinned == old.pinned) return;
    if (widget.pinned) {
      _hideTimer?.cancel();
      setState(() => _visible = true);
    } else if (_visible) {
      // Unpinned (e.g. playing again): fade out after the usual delay
      _restartHideTimer();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _toggle() {
    setState(() => _visible = !_visible);
    _visible ? _restartHideTimer() : _hideTimer?.cancel();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    if (_touches > 0 || widget.pinned) return;
    _hideTimer = Timer(_showFor, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _release() {
    if (_touches > 0) _touches--;
    if (_visible) _restartHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap ?? _toggle,
          child: widget.child,
        ),
        IgnorePointer(
          ignoring: !_visible,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            // Quick to appear, slow to fade out
            duration: Duration(milliseconds: _visible ? 200 : 800),
            curve: Curves.easeInOut,
            // Using a control keeps them up, then 3s more after letting go
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                _touches++;
                _hideTimer?.cancel();
              },
              onPointerUp: (_) => _release(),
              onPointerCancel: (_) => _release(),
              child: Stack(fit: StackFit.expand, children: widget.controls),
            ),
          ),
        ),
      ],
    );
  }
}

class _CachedPlayer {
  final VideoPlayerController controller;
  final bool fromFile;

  const _CachedPlayer(this.controller, {required this.fromFile});
}

/// The carousel's video players, kept for as long as the carousel is on
/// screen so swiping back to a video that already played starts it again
/// instantly rather than reloading it.
///
/// Each video is also saved to the device the first time it plays (in its
/// own cache, so big videos don't push the carousel images out of theirs).
/// Once that copy is ready, the next visit swaps the streaming player for one
/// that reads the file — streaming players can re-download from the start
/// after a replay — and later app launches play from the file straight away.
class _CarouselVideoCache {
  static final _files = CacheManager(
    Config(
      'carouselVideos',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 20,
    ),
  );

  final _players = <String, Future<_CachedPlayer>>{};
  final _downloading = <String>{};
  // Streaming players replaced by a downloaded copy. A slide may still be
  // showing one for a moment, so they're only disposed with the carousel.
  final _retired = <VideoPlayerController>[];
  bool _disposed = false;

  Future<VideoPlayerController> obtain(String url) async {
    final pending = _players[url] ??= _create(url);
    var player = await pending;
    if (!player.fromFile && identical(_players[url], pending)) {
      final cached = await _files.getFileFromCache(url);
      if (cached != null && identical(_players[url], pending)) {
        final upgrade = _upgrade(player, cached.file);
        _players[url] = upgrade;
        player = await upgrade;
      }
    }
    return player.controller;
  }

  Future<_CachedPlayer> _create(String url) async {
    final cached = await _files.getFileFromCache(url);
    final controller = cached != null
        ? VideoPlayerController.file(
            cached.file,
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          )
        : VideoPlayerController.networkUrl(
            Uri.parse(url),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          );
    try {
      await controller.initialize();
    } catch (_) {
      _players.remove(url);
      await controller.dispose();
      rethrow;
    }
    if (_disposed) {
      await controller.dispose();
      throw StateError('Carousel closed');
    }
    if (cached == null) _download(url);
    return _CachedPlayer(controller, fromFile: cached != null);
  }

  // Falls back to the streaming player if the saved file won't open
  Future<_CachedPlayer> _upgrade(_CachedPlayer streaming, File file) async {
    final controller = VideoPlayerController.file(
      file,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    try {
      await controller.initialize();
    } catch (e) {
      debugPrint('Carousel video cache error: $e');
      await controller.dispose();
      return streaming;
    }
    if (_disposed) {
      await controller.dispose();
      return streaming;
    }
    _retired.add(streaming.controller);
    return _CachedPlayer(controller, fromFile: true);
  }

  void _download(String url) {
    if (!_downloading.add(url)) return;
    _files
        .downloadFile(url)
        .then<void>(
          (_) {},
          onError: (Object e) =>
              debugPrint('Carousel video download failed: $e'),
        )
        .whenComplete(() => _downloading.remove(url));
  }

  void dispose() {
    _disposed = true;
    for (final pending in _players.values) {
      pending.then((p) => p.controller.dispose()).catchError((_) {});
    }
    for (final controller in _retired) {
      controller.dispose();
    }
    _players.clear();
    _retired.clear();
  }
}
