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
import 'package:giggre_app/screens/chat/home_chat.dart';
import 'package:provider/provider.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:giggre_app/core/widgets/update_card.dart';
import 'package:giggre_app/screens/app_contents/about_giggre.dart';
import 'package:giggre_app/screens/giggre-updates.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/delete_acc_service.dart';
import '../../auth/presentation/login_screen.dart';
import '../../gig_host/presentation/gig_host_screen.dart';
import '../../gig_worker/presentation/gig_worker_screen.dart';
import '../../../widgets/active_gig_bar.dart';

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
  bool _hasUnreadMessages = false;
  bool _hasUnreadGigMessages = false;
  bool _hasUpdate = false;
  bool _updateDismissed = false;
  bool _pendingDeletion = false;
  String _deletionStatus = 'pending_deletion';
  StreamSubscription? _roomsStreamSub;
  final List<StreamSubscription> _roomSubs = [];
  StreamSubscription? _gigRoomsStreamSub;
  final List<StreamSubscription> _gigRoomSubs = [];
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
    _listenForUnreadMessages();
    _listenForUnreadGigMessages();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _activeGigStream = watchActiveWorkerGig(uid);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAppUpdate();
      _initLocationServiceListener();
      _checkInternet();
      _internetCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkInternet());
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
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
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
    _roomsStreamSub?.cancel();
    for (final sub in _roomSubs) sub.cancel();
    _gigRoomsStreamSub?.cancel();
    for (final sub in _gigRoomSubs) sub.cancel();
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
                    child: Icon(Icons.system_update_rounded, color: kBlue, size: 32),
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
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx, rootNavigator: true).pop();
                    if (mounted) setState(() => _updateDismissed = true);
                  },
                  child: const Text('Later', style: TextStyle(color: kSub, fontSize: 13)),
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

  void _listenForUnreadMessages() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _roomsStreamSub = FirebaseFirestore.instance
        .collection('chat_rooms')
        .where('userId', isEqualTo: uid)
        .where('isSupport', isEqualTo: true)
        .snapshots()
        .listen(
          (roomsSnap) {
            for (final sub in _roomSubs) sub.cancel();
            _roomSubs.clear();

            if (roomsSnap.docs.isEmpty) {
              if (mounted) setState(() => _hasUnreadMessages = false);
              return;
            }

            final Map<int, bool> roomUnread = {};

            for (int i = 0; i < roomsSnap.docs.length; i++) {
              final room = roomsSnap.docs[i];
              final sub = FirebaseFirestore.instance
                  .collection('chat_rooms')
                  .doc(room.id)
                  .collection('messages')
                  .where('isSupport', isEqualTo: true)
                  .where('hasSeen', isEqualTo: false)
                  .limit(1)
                  .snapshots()
                  .map((s) => s.docs.isNotEmpty)
                  .listen(
                    (hasUnread) {
                      roomUnread[i] = hasUnread;
                      final anyUnread = roomUnread.values.any((v) => v);
                      if (mounted) setState(() => _hasUnreadMessages = anyUnread);
                      debugPrint('[Unread] Badge → $anyUnread');
                    },
                    onError: (e) => debugPrint('[HomeScreen] message stream error: $e'),
                  );
              _roomSubs.add(sub);
            }
          },
          onError: (e) {
            if (FirebaseAuth.instance.currentUser == null) return;
            debugPrint('[HomeScreen] rooms stream error: $e');
          },
        );
  }

  void _listenForUnreadGigMessages() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _gigRoomsStreamSub = FirebaseFirestore.instance
        .collection('chat_rooms')
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen(
          (roomsSnap) {
            for (final sub in _gigRoomSubs) sub.cancel();
            _gigRoomSubs.clear();

            if (roomsSnap.docs.isEmpty) {
              if (mounted) setState(() => _hasUnreadGigMessages = false);
              return;
            }

            final Map<int, bool> roomUnread = {};

            for (int i = 0; i < roomsSnap.docs.length; i++) {
              final room = roomsSnap.docs[i];
              final participants =
                  (room.data()['participants'] as List<dynamic>?) ?? [];
              final otherUid =
                  participants.firstWhere((p) => p != uid, orElse: () => '') as String;

              if (otherUid.isEmpty) continue;

              final sub = FirebaseFirestore.instance
                  .collection('chat_rooms')
                  .doc(room.id)
                  .collection('messages')
                  .where('senderId', isEqualTo: otherUid)
                  .where('hasSeen', isEqualTo: false)
                  .limit(1)
                  .snapshots()
                  .map((s) => s.docs.isNotEmpty)
                  .listen(
                    (hasUnread) {
                      roomUnread[i] = hasUnread;
                      final anyUnread = roomUnread.values.any((v) => v);
                      if (mounted) setState(() => _hasUnreadGigMessages = anyUnread);
                      debugPrint('[Unread] Gig Badge → $anyUnread');
                    },
                    onError: (e) =>
                        debugPrint('[HomeScreen] gig message stream error: $e'),
                  );
              _gigRoomSubs.add(sub);
            }
          },
          onError: (e) {
            if (FirebaseAuth.instance.currentUser == null) return;
            debugPrint('[HomeScreen] gig rooms stream error: $e');
          },
        );
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
                    child: Icon(Icons.science_outlined, color: kAmber, size: 32),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
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
      WidgetsBinding.instance.addPostFrameCallback(
        (_) { if (mounted) _showPendingDeletionModal(); },
      );
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
                    child: Icon(Icons.delete_forever_outlined,
                        color: Colors.redAccent, size: 32),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  isApproved ? 'Account Deletion Approved' : 'Account Pending Deletion',
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
                  style: const TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
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
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel Deletion',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    if (mounted) {
                      context.read<CurrentUserProvider>().clearUser();
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    }
                    await FirebaseAuth.instance.signOut();
                  },
                  child: const Text('Sign Out',
                      style: TextStyle(color: Colors.grey, fontSize: 14)),
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
                child: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 22),
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
                        child: const Text('Cancel', style: TextStyle(color: kSub, fontSize: 15)),
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
      _roomsStreamSub?.cancel();
      for (final sub in _roomSubs) sub.cancel();
      _roomSubs.clear();
      if (mounted) {
        context.read<CurrentUserProvider>().clearUser();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _GiggreMenu(
        hasPendingUpdate: _hasUpdate && _updateDismissed,
        onUpdate: _showUpdateModal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      bottomSheet: !_locationServiceEnabled
          ? SafeArea(
              child: Container(
                width: double.infinity,
                color: Colors.orange.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.location_off_rounded, color: Colors.white, size: 20),
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
                      child: const Text('Enable', style: TextStyle(fontWeight: FontWeight.bold)),
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
                'giggre',
                style: TextStyle(
                  color: onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        actions: [
          _IconSquareButton(
            icon: Icons.message_outlined,
            dot: _hasUnreadMessages || _hasUnreadGigMessages,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HomeChat()),
            ),
          ),
          const SizedBox(width: 8),
          _IconSquareButton(
            icon: Icons.logout_rounded,
            onTap: _logout,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<ActiveGigInfo?>(
          stream: _activeGigStream,
          builder: (context, activeGigSnap) {
            final activeGig = activeGigSnap.data;
            return Stack(
              children: [
                _buildHomeContent(context, bottomPadding: activeGig != null ? 16 + 86 : 16),
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

  Widget _buildHomeContent(BuildContext context, {required double bottomPadding}) {
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
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: kBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kBlue.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.system_update_rounded,
                              color: kBlue, size: 18),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'A new version of Giggre is available!',
                              style: TextStyle(
                                  color: kBlue,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: kBlue,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Update',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
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
                                      builder: (_) => const GigHostScreen()),
                                );
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const GigWorkerScreen()),
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
                                  color: Colors.white, strokeWidth: 2),
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
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward_rounded,
                                    size: 20),
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
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                ..._updates.take(3).map(
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
                      Image.asset('assets/images/logo.png',
                          width: 94, height: 64),
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
  final bool dot;

  const _IconSquareButton({
    required this.icon,
    required this.onTap,
    this.dot = false,
  });

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
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(icon, color: kSub, size: 19),
            if (dot)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 1.5,
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
    final textColor =
        isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final subColor = isSelected ? Colors.white70 : kSub;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor : selectedColor.withValues(alpha: 0),
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
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => screen)),
      child: Text(label, style: const TextStyle(fontSize: 12, color: kBlue)),
    );
  }
}

// ─────────────────────────────────────────────
//  Giggre menu (bottom sheet)
// ─────────────────────────────────────────────
class _GiggreMenu extends StatelessWidget {
  final bool hasPendingUpdate;
  final VoidCallback onUpdate;

  const _GiggreMenu({
    this.hasPendingUpdate = false,
    required this.onUpdate,
  });

  static final List<Map<String, dynamic>> gigMenuData = [
    {'title': 'About Giggre', 'icon': Icons.info, 'screen': AboutGiggre()},
    {
      'title': 'Terms & Conditions',
      'icon': Icons.description,
      'screen': TermsAndConditions(),
    },
    {
      'title': 'Privacy Policy',
      'icon': Icons.privacy_tip,
      'screen': PrivacyPolicy(),
    },
    {'title': 'Help/FAQ', 'icon': Icons.help, 'screen': HelpFaq()},
    {
      'title': 'Contact Us',
      'icon': Icons.contact_support,
      'screen': ContactUs(),
    },
  ];

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final iconBg = isDark
            ? const Color(0xFF001B52)
            : const Color(0xFFEBF0FB);
        return Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Column(
                  children: [
                    Image.asset('assets/images/logo.png', height: 60),
                    const SizedBox(height: 12),
                    FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snapshot) {
                        final version = snapshot.hasData
                            ? 'Version ${snapshot.data!.version}'
                            : 'Version ...';
                        return Column(
                          children: [
                            Text(
                              version,
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black54,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (hasPendingUpdate)
                              GestureDetector(
                                onTap: () {
                                  Navigator.pop(context);
                                  onUpdate();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: kBlue,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'Update Available',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Latest',
                                  style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'The fastest way to find jobs or hire workers near you',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
                Divider(color: isDark ? Colors.white24 : Colors.black26),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: gigMenuData.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final item = gigMenuData[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => item['screen'] as Widget,
                            ),
                          );
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: iconBg,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(item['icon'] as IconData,
                                      color: kBlue),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  item['title'] as String,
                                  style: TextStyle(
                                    color:
                                        isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                            Icon(Icons.chevron_right,
                                color: isDark ? Colors.white : Colors.black),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

      final items = snapshot.docs
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
              onPageChanged: (index, _) =>
                  setState(() => _current = index),
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
