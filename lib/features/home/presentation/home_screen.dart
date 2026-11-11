import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
import 'package:cached_network_image/cached_network_image.dart';
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
import '../../../widgets/content_carousel.dart';
import '../../wallet/presentation/wallet_screen.dart';
import 'profile_tab.dart';
import '../../gig_points/presentation/gig_points_button.dart';
import '../../gig_points/presentation/gig_points_screen.dart';

// Widest the home column grows; wider screens (tablets) centre it
const double _kMaxContentWidth = 600;

// Gold or blue used *as text* shifts per theme to stay at 4.5:1 or more
// (kGold itself is ~1.9:1 on the light background).
Color _goldText(bool isDark) => isDark ? kGold : const Color(0xFF8F5A00);
Color _blueText(bool isDark) =>
    isDark ? const Color(0xFF5AA2F0) : const Color(0xFF0359B0);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String _userName = '';
  String _photoUrl = '';
  String? _selectedRole;
  bool _hasUpdate = false;
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
    if (mounted) {
      setState(() => _hasUpdate = AppUpdateChecker.updateAvailable.value);
    }
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
      // An item missing its date or text (e.g. a half-filled admin draft) is
      // skipped rather than crashing the cast in UpdateCard below.
      final items = response.docs
          .where((doc) => ((doc.data()['sortNumber'] as num?) ?? 0) > 0)
          .where((doc) {
            final data = doc.data();
            return data['dateCreated'] is Timestamp &&
                data['title'] is String &&
                data['body'] is String;
          })
          .map((doc) {
            final data = doc.data();
            if (data['dateCreated'] is Timestamp) {
              data['dateCreated'] = (data['dateCreated'] as Timestamp).toDate();
            }
            return data;
          })
          .toList();

      items.sort((a, b) {
        final aDate = a['dateCreated'] as DateTime?;
        final bDate = b['dateCreated'] as DateTime?;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      if (mounted) setState(() => _updates = items);
    } catch (e) {
      debugPrint('Error fetching updates: $e');
    }
  }

  Future<void> _loadUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // Offline with nothing cached, get() throws; Home keeps its "Welcome back"
    // defaults and pull-to-refresh retries.
    final DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    } catch (e) {
      debugPrint('Error loading user: $e');
      return;
    }
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
      setState(() => _deletionStatus = status);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPendingDeletionModal();
      });
    }
  }

  void _showPendingDeletionModal() {
    final isApproved = _deletionStatus == 'approved';
    var cancelling = false;

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
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(
                      ctx,
                    ).extension<ProfileTabTokens>()!.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                // Busy while cancelling so a second tap can't fire it twice;
                // the dialog only lifts once the cancellation really saved.
                StatefulBuilder(
                  builder: (ctx, setButtonState) => SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: cancelling
                          ? null
                          : () async {
                              setButtonState(() => cancelling = true);
                              final cancelled =
                                  await DeleteAccountService.cancelDeletion(
                                    ctx,
                                  );
                              if (!ctx.mounted) return;
                              if (!cancelled) {
                                setButtonState(() => cancelling = false);
                                return;
                              }
                              Navigator.pop(ctx);
                              setState(
                                () => _deletionStatus = 'pending_deletion',
                              );
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1B6CA8),
                        disabledBackgroundColor: const Color(
                          0xFF1B6CA8,
                        ).withValues(alpha: 0.6),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: cancelling
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                                semanticsLabel: 'Cancelling deletion',
                              ),
                            )
                          : const Text(
                              'Cancel Deletion',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
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
                  child: Text(
                    'Log Out',
                    style: TextStyle(
                      color: Theme.of(
                        ctx,
                      ).extension<ProfileTabTokens>()!.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // The saved role only picks where the next login lands, so Continue never
  // waits on it: Firestore applies the write locally at once and only
  // completes this future after the server confirms, which offline can be
  // never. A rejected write (e.g. rules) puts the previous choice back.
  Future<void> _selectRole(String role) async {
    // Every tap jumps to that role's carousel video, if giggre-admin set one:
    // continued from where it stopped when switching roles, from the start
    // when tapping the role whose video is already showing.
    _carouselKey.currentState?.playForRole(role);
    if (role == _selectedRole) return;
    final previous = _selectedRole;
    setState(() => _selectedRole = role);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'role': role,
      });
    } catch (e) {
      debugPrint('Error saving role: $e');
      if (!mounted || _selectedRole != role) return;
      setState(() => _selectedRole = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            role == 'host'
                ? "Couldn't switch to Gig Host. Please try again."
                : "Couldn't switch to Gig Worker. Please try again.",
          ),
        ),
      );
    }
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          body: ProfileTab(
            initialRole: _selectedRole ?? 'worker',
            isTabRoot: false,
            // ProfileTab confirms first, as in the shells; another dialog here
            // made Home's Log Out ask twice.
            onLogout: _performLogout,
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

  Future<void> _performLogout() async {
    if (!mounted) return;
    await performSignOut(context);
  }

  final GlobalKey<RefreshIndicatorState> _refreshKey =
      GlobalKey<RefreshIndicatorState>();
  final _carouselKey = GlobalKey<ContentCarouselState>();

  // Reloads the data in place. It used to also re-key every section, which
  // replayed all the entrance animations and rebuilt the carousel, restarting
  // its video, on every pull.
  Future<void> _refreshAll() async {
    await Future.wait([
      _loadUser(),
      _fetchUpdates(),
      if (_carouselKey.currentState case final carousel?)
        carousel.refreshSlides(),
    ]);
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
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: Semantics(
          button: true,
          label: 'Giggre menu',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: _openGiggreMenu,
            child: Image.asset('assets/images/logo.png', height: 32),
          ),
        ),
        actions: [
          // Gig Points sits directly beside the profile (ProfileTab) button.
          GigPointsButton(onTap: _openGigPoints),
          // Gaps are 4 less than they look: each square button below carries
          // 4pt of extra touch area on every side.
          const SizedBox(width: 4),
          _IconSquareButton(
            icon: Icons.person_rounded,
            label: 'Profile',
            onTap: _openProfile,
          ),
          _IconSquareButton(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Wallet',
            onTap: _openWallet,
          ),
          // Log out lives in Profile, as in the worker/host shells, not one
          // tap from Wallet. The square ends 20pt in, on the content's edge.
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<ActiveGigInfo?>(
          stream: _activeGigStream,
          builder: (context, activeGigSnap) {
            final activeGig = activeGigSnap.data;
            // Stacked, not overlaid: the offline banner used to be a
            // Scaffold bottomSheet drawn over the active gig bar, hiding the
            // gig right when connection trouble makes it matter most. The
            // content also ends above both, with no guessed bar height.
            return Column(
              children: [
                Expanded(child: _buildHomeContent(context)),
                // Location off is handled app-wide by LocationGate (main.dart).
                if (!_internetAvailable) const _OfflineBanner(),
                if (activeGig != null) ActiveGigBar(gig: activeGig),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHomeContent(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final secondaryText = Theme.of(
      context,
    ).extension<ProfileTabTokens>()!.textSecondary;
    final firstName = _userName.split(' ').first;
    final currentYear = DateTime.now().year;
    // On tablets the column stops at _kMaxContentWidth and centres, instead
    // of stretching the carousel and role cards across the whole screen;
    // phones keep the plain 20pt gutters.
    final viewport =
        MediaQuery.sizeOf(context).width -
        MediaQuery.paddingOf(context).horizontal;
    final gutter = math.max(20.0, (viewport - _kMaxContentWidth) / 2);
    return RefreshIndicator(
      key: _refreshKey,
      onRefresh: _refreshAll,
      color: kGold,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 2. Profile strip ──────────────────────────
            EntranceAnimation(
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: onSurface,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Choose a mode to get started',
                          style: TextStyle(color: secondaryText, fontSize: 13),
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
              Semantics(
                button: true,
                label: 'A new version of Giggre is available. Update',
                excludeSemantics: true,
                child: GestureDetector(
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
                        Icon(
                          Icons.system_update_rounded,
                          color: _blueText(isDark),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'A new version of Giggre is available!',
                            style: TextStyle(
                              color: _blueText(isDark),
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
              ),
            ],

            const SizedBox(height: 20),

            // ── 3. Image carousel ─────────────────────────
            EntranceAnimation(
              type: EntranceAnimationType.fadeInSlideUp,
              delay: const Duration(milliseconds: 80),
              child: ContentCarousel(key: _carouselKey),
            ),

            const SizedBox(height: 24),

            // ── 4. Role segmented control ─────────────────
            EntranceAnimation(
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
                type: EntranceAnimationType.fadeInSlideUp,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_selectedRole == 'host') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const HostShell()),
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
                      // White on both fills by design choice, though white on
                      // kGold is ~2.0:1 (below 4.5:1)
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _selectedRole == 'worker'
                                ? 'Continue as Gig Worker'
                                : 'Continue as Gig Host',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
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

            // ── 6. Giggre Updates section ─────────────────
            // Hidden with nothing to show (none published, or offline on a
            // fresh install): a lone header and See all read as broken.
            if (_updates.isNotEmpty) ...[
              // 16 + the 12pt See all touch padding = the usual 28 gap
              const SizedBox(height: 16),
              EntranceAnimation(
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
                    // Padded to a 44pt touch area; the text stays flush
                    // right with the cards below
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => GiggreUpdates()),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 0, 14),
                        child: Text(
                          'See all',
                          style: TextStyle(
                            color: _goldText(isDark),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),

              ..._updates
                  .take(3)
                  .toList()
                  .asMap()
                  .entries
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: EntranceAnimation(
                        type: EntranceAnimationType.fadeInSlideUp,
                        delay: Duration(milliseconds: 280 + entry.key * 60),
                        child: UpdateCard(
                          title: entry.value['title'] as String,
                          date: entry.value['dateCreated'] as DateTime,
                          category:
                              entry.value['category'] as String? ?? 'Update',
                          description: entry.value['body'] as String,
                        ),
                      ),
                    ),
                  ),

              const SizedBox(height: 16),
            ] else
              const SizedBox(height: 28),

            // ── Footer ────────────────────────────────────
            EntranceAnimation(
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
                    Text(
                      'The fastest way to find gigs or get help near you.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: secondaryText),
                    ),
                    const SizedBox(height: 8),
                    const Divider(),
                    // Spacing here comes from the links' own touch padding
                    // (8 across, 14 down), which keeps the 16pt gaps
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        _FooterLink('About', AboutGiggre()),
                        _FooterLink('Terms', TermsAndConditions()),
                        _FooterLink('Privacy', PrivacyPolicy()),
                        _FooterLink('Help', HelpFaq()),
                        _FooterLink('Contact Us', ContactUs()),
                      ],
                    ),
                    Text(
                      'Copyright © $currentYear Giggre. All rights reserved.',
                      style: TextStyle(fontSize: 12, color: secondaryText),
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
//  Offline banner (above the active gig bar)
// ─────────────────────────────────────────────
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    // liveRegion: screen readers announce it when it appears
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: Colors.red.shade700,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
    );
  }
}

// ─────────────────────────────────────────────
//  Small rounded-square icon button (AppBar actions)
// ─────────────────────────────────────────────
class _IconSquareButton extends StatelessWidget {
  final IconData icon;
  // Read by screen readers and shown on long-press, as GigPointsButton does
  final String label;
  final VoidCallback onTap;

  const _IconSquareButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        // 36pt square to look at, 44pt to touch (the iOS minimum)
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Icon(
                  icon,
                  color: Theme.of(
                    context,
                  ).extension<ProfileTabTokens>()!.textSecondary,
                  size: 19,
                ),
              ),
            ),
          ),
        ),
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
                  selectedForeground: Colors.white,
                  // White subtitle too: white70 on kBlue drops under 4.5:1
                  selectedSubtle: Colors.white,
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
                  // White by design choice, matching the Worker card, though
                  // white on kGold is ~2.0:1 (below 4.5:1)
                  selectedForeground: Colors.white,
                  selectedSubtle: Colors.white,
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
  // Label/icon and subtitle colours on the selected fill
  final Color selectedForeground;
  final Color selectedSubtle;
  final BorderRadius borderRadius;
  final VoidCallback onTap;

  const _RoleHalf({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.selectedColor,
    required this.selectedForeground,
    required this.selectedSubtle,
    required this.borderRadius,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isSelected
        ? selectedForeground
        : Theme.of(context).colorScheme.onSurface;
    final unselectedSubtle = Theme.of(
      context,
    ).extension<ProfileTabTokens>()!.textSecondary;
    final subColor = isSelected ? selectedSubtle : unselectedSubtle;

    // Selection is otherwise only the fill colour; say it for screen readers
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label, $subtitle',
      excludeSemantics: true,
      child: GestureDetector(
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
              Icon(
                icon,
                color: isSelected ? selectedForeground : unselectedSubtle,
                size: 26,
              ),
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
    // 12pt text padded to a 44pt-tall touch area
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: _blueText(Theme.of(context).brightness == Brightness.dark),
          ),
        ),
      ),
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
                            color: tokens.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (hasPendingUpdate)
                          Semantics(
                            button: true,
                            label: 'Update available. Update Giggre',
                            excludeSemantics: true,
                            child: GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                onUpdate();
                              },
                              child: Container(
                                height: 22,
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
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            height: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _kMenuGreen.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '✓ Latest',
                              style: TextStyle(
                                // Darker/lighter than the tint's green so the
                                // small label clears 4.5:1 in each theme
                                color: isDark
                                    ? const Color(0xFF4CC38E)
                                    : const Color(0xFF1F7A51),
                                fontSize: 11,
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
                  style: TextStyle(color: tokens.textSecondary, fontSize: 11),
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
