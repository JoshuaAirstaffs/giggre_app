import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:giggre_app/services/delete_acc_service.dart';
import 'package:giggre_app/features/gig_host/presentation/my_documents_screen.dart';
import 'package:giggre_app/features/gig_worker/presentation/verification_screen.dart';
import 'package:giggre_app/screens/referrals/my_referral_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../gig_worker/presentation/gig_history_screen.dart';
import '../../gig_worker/presentation/worker_ratings_screen.dart';
import '../../gig_worker/presentation/worker_settings_screen.dart';
import '../../gig_worker/presentation/widgets/toolchest_sheet.dart';
import '../../gig_worker/presentation/widgets/worker_notifications_sheet.dart';
import '../../gig_host/presentation/widgets/notifications_sheet.dart' as host_notif;
import '../../gig_host/presentation/widgets/favorite_workers_sheet.dart';
import '../../gig_host/presentation/widgets/payment_history_sheet.dart';
import '../../gig_host/presentation/widgets/ratings_given_sheet.dart';
import '../../gig_host/presentation/host_gigs_screen.dart';

const _kBadgeLabels = {
  'unverified': 'Unverified',
  'verified': 'Verified',
  'pending': 'Pending',
  'rejected': 'Rejected',
};

const _kBadgeColors = {
  'unverified': Colors.blue,
  'verified': Colors.green,
  'pending': Colors.orangeAccent,
  'rejected': Colors.red,
};

// ─────────────────────────────────────────────────────────────────────────────
//  ProfileTab — shared profile tab for both Worker and Host screens
// ─────────────────────────────────────────────────────────────────────────────
class ProfileTab extends StatefulWidget {
  final String initialRole; // 'worker' or 'host'
  final VoidCallback? onSwitchRole; // navigates to the other role screen
  final VoidCallback? onLogout;

  const ProfileTab({
    super.key,
    required this.initialRole,
    this.onSwitchRole,
    this.onLogout,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  late String _viewRole;
  bool _loading = true;

  String _uid = '';
  String _name = '';
  String _email = '';
  String _phone = '';
  String _bio = '';
  String _company = '';
  String _photoUrl = '';
  String _createdAt = '';
  String _isVerified = '';

  // Worker stats
  double _ratingAsWorker = 5.0;
  int _workerRatingCount = 0;
  Map<String, double> _earningsByCode = {};
  Map<String, double> _weeklyByCode = {};
  int _completedGigsWorker = 0;
  List<String> _skills = [];

  // Host stats
  double _ratingAsHost = 5.0;
  int _hostRatingCount = 0;
  int _gigsPosted = 0;
  int _activeGigs = 0;
  int _completedGigsHost = 0;
  Map<String, double> _spentByCurrency = {};
  double _completionRate = 0;

  List<Map<String, dynamic>> _quickGigsDocs = [];
  List<Map<String, dynamic>> _openGigsDocs = [];
  List<Map<String, dynamic>> _offeredGigsDocs = [];

  StreamSubscription? _profileSub;
  StreamSubscription? _quickGigsSub;
  StreamSubscription? _openGigsSub;
  StreamSubscription? _offeredGigsSub;

  static const _activeStatuses = [
    'open',
    'in_progress',
    'navigating',
    'arrived',
    'working',
    'task_complete',
    'payment',
  ];

  @override
  void initState() {
    super.initState();
    _viewRole = widget.initialRole;
    _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _listenToProfile();
    _listenToHostGigs();
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _quickGigsSub?.cancel();
    _openGigsSub?.cancel();
    _offeredGigsSub?.cancel();
    super.dispose();
  }

  void _listenToProfile() {
    if (_uid.isEmpty) return;
    _profileSub = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .snapshots()
        .listen((doc) {
          final data = doc.data() ?? {};

          String createdAtStr = '';
          if (data['createdAt'] != null) {
            final ts = data['createdAt'] as Timestamp;
            final dt = ts.toDate();
            createdAtStr =
                'Member since ${_monthName(dt.month)} ${dt.year}';
          }

          final earningsMap =
              data['earnings'] as Map<String, dynamic>? ?? {};
          final totalMap =
              earningsMap['total'] as Map<String, dynamic>? ?? {};
          final weeklyMap =
              earningsMap['weekly'] as Map<String, dynamic>? ?? {};

          final earningsByCode = <String, double>{};
          totalMap.forEach(
              (k, v) => earningsByCode[k] = (v as num? ?? 0).toDouble());

          final weeklyByCode = <String, double>{};
          weeklyMap.forEach(
              (k, v) => weeklyByCode[k] = (v as num? ?? 0).toDouble());

          final skillsXP =
              data['skillsXP'] as Map<String, dynamic>? ?? {};

          if (!mounted) return;
          setState(() {
            _name = data['name'] ?? '';
            _email =
                FirebaseAuth.instance.currentUser?.email ??
                data['email'] ??
                '';
            _phone = data['phone'] ?? '';
            _bio = data['bio'] ?? '';
            _company = data['company'] ?? '';
            _photoUrl =
                data['photoUrl'] ??
                FirebaseAuth.instance.currentUser?.photoURL ??
                '';
            _createdAt = createdAtStr;
            _isVerified = data['isVerified'] ?? '';

            _ratingAsWorker =
                (data['ratingAsWorker'] as num? ?? 5.0).toDouble();
            _workerRatingCount =
                (data['ratingCount'] as num? ?? 0).toInt();
            _earningsByCode = earningsByCode;
            _weeklyByCode = weeklyByCode;
            _completedGigsWorker =
                (earningsMap['completedGigs'] as num? ?? 0).toInt();
            _skills = skillsXP.keys.toList();

            _ratingAsHost =
                (data['ratingAsHost'] as num? ?? 5.0).toDouble();
            _hostRatingCount =
                (data['ratingAsHostCount'] as num? ?? 0).toInt();

            _loading = false;
          });
        });
  }

  void _listenToHostGigs() {
    if (_uid.isEmpty) return;

    _quickGigsSub = FirebaseFirestore.instance
        .collection('quick_gigs')
        .where('hostId', isEqualTo: _uid)
        .snapshots()
        .listen((snap) {
          _quickGigsDocs = snap.docs.map((d) {
            final m = Map<String, dynamic>.from(d.data());
            m['docId'] = d.id;
            m['gigType'] = 'quick';
            return m;
          }).toList();
          _recomputeHostStats();
        });

    _openGigsSub = FirebaseFirestore.instance
        .collection('open_gigs')
        .where('hostId', isEqualTo: _uid)
        .snapshots()
        .listen((snap) {
          _openGigsDocs = snap.docs.map((d) {
            final m = Map<String, dynamic>.from(d.data());
            m['docId'] = d.id;
            m['gigType'] = 'open';
            return m;
          }).toList();
          _recomputeHostStats();
        });

    _offeredGigsSub = FirebaseFirestore.instance
        .collection('offered_gigs')
        .where('hostId', isEqualTo: _uid)
        .snapshots()
        .listen((snap) {
          _offeredGigsDocs = snap.docs.map((d) {
            final m = Map<String, dynamic>.from(d.data());
            m['docId'] = d.id;
            m['gigType'] = 'offered';
            return m;
          }).toList();
          _recomputeHostStats();
        });
  }

  void _recomputeHostStats() {
    final allDocs = [
      ..._quickGigsDocs,
      ..._openGigsDocs,
      ..._offeredGigsDocs,
    ];
    int gigsPosted = allDocs.length;
    int activeGigs = 0;
    int completedGigs = 0;
    final Map<String, double> spentByCode = {};

    for (final d in allDocs) {
      final status = d['status'] as String? ?? '';
      if (_activeStatuses.contains(status)) activeGigs++;
      if (status == 'completed') {
        completedGigs++;
        final amount = (d['budget'] as num? ?? 0).toDouble();
        final code = (d['currencyCode'] as String?) ?? 'PHP';
        spentByCode[code] = (spentByCode[code] ?? 0) + amount;
      }
    }

    if (!mounted) return;
    setState(() {
      _gigsPosted = gigsPosted;
      _activeGigs = activeGigs;
      _completedGigsHost = completedGigs;
      _spentByCurrency = spentByCode;
      _completionRate =
          gigsPosted > 0 ? (completedGigs / gigsPosted) * 100 : 0;
    });
  }

  String _monthName(int month) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month];
  }

  void _showEditProfile() {
    final nameCtrl = TextEditingController(text: _name);
    final companyCtrl = TextEditingController(text: _company);
    final phoneCtrl = TextEditingController(text: _phone);
    final bioCtrl = TextEditingController(text: _bio);
    bool saving = false;
    XFile? pickedImage;
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final cardColor = Theme.of(ctx).cardColor;
          final onSurface = Theme.of(ctx).colorScheme.onSurface;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 28,
              ),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 24,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: kBorder,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Edit Profile',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Avatar picker
                      Center(
                        child: GestureDetector(
                          onTap: saving
                              ? null
                              : () async {
                                  final source =
                                      await showDialog<ImageSource>(
                                    context: ctx,
                                    builder: (c) => AlertDialog(
                                      backgroundColor:
                                          Theme.of(c).cardColor,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16),
                                      ),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ListTile(
                                            leading: const Icon(
                                              Icons.camera_alt_rounded,
                                              color: kBlue,
                                            ),
                                            title: const Text('Camera'),
                                            onTap: () => Navigator.pop(
                                              c,
                                              ImageSource.camera,
                                            ),
                                          ),
                                          ListTile(
                                            leading: const Icon(
                                              Icons.photo_library_rounded,
                                              color: kBlue,
                                            ),
                                            title:
                                                const Text('Gallery'),
                                            onTap: () => Navigator.pop(
                                              c,
                                              ImageSource.gallery,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  if (source == null) return;
                                  final picked =
                                      await ImagePicker().pickImage(
                                    source: source,
                                    imageQuality: 80,
                                    maxWidth: 512,
                                  );
                                  if (picked != null) {
                                    setModal(() => pickedImage = picked);
                                  }
                                },
                          child: Stack(
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: kBlue.withValues(alpha: 0.5),
                                    width: 2,
                                  ),
                                ),
                                child: ClipOval(
                                  child: pickedImage != null
                                      ? Image.file(
                                          File(pickedImage!.path),
                                          fit: BoxFit.cover,
                                        )
                                      : _photoUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: _photoUrl,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, _, _) =>
                                              const Icon(
                                            Icons.person,
                                            size: 40,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.person,
                                          size: 40,
                                        ),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: kBlue,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: cardColor,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _EditField(
                        ctrl: nameCtrl,
                        label: 'Full Name',
                        icon: Icons.person_outline_rounded,
                        isDark: isDark,
                        cardColor: cardColor,
                        onSurface: onSurface,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _EditField(
                        ctrl: companyCtrl,
                        label: 'Company / Business',
                        icon: Icons.business_outlined,
                        isDark: isDark,
                        cardColor: cardColor,
                        onSurface: onSurface,
                      ),
                      const SizedBox(height: 12),
                      _EditField(
                        ctrl: phoneCtrl,
                        label: 'Phone Number',
                        icon: Icons.phone_outlined,
                        isDark: isDark,
                        cardColor: cardColor,
                        onSurface: onSurface,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.grey.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? kBorder
                                : Colors.grey.withValues(alpha: 0.2),
                          ),
                        ),
                        child: TextFormField(
                          controller: bioCtrl,
                          maxLines: 3,
                          maxLength: 200,
                          style: TextStyle(
                            color: onSurface,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            labelText: 'About / Bio',
                            labelStyle: const TextStyle(
                              color: kSub,
                              fontSize: 13,
                            ),
                            prefixIcon: const Padding(
                              padding: EdgeInsets.only(bottom: 40),
                              child: Icon(
                                Icons.notes_rounded,
                                color: kSub,
                                size: 20,
                              ),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            counterStyle: const TextStyle(
                              color: kSub,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) {
                                    return;
                                  }
                                  setModal(() => saving = true);
                                  final uid = FirebaseAuth
                                      .instance.currentUser?.uid;
                                  if (uid == null) return;
                                  try {
                                    String? newPhotoUrl;
                                    if (pickedImage != null) {
                                      final ref = FirebaseStorage
                                          .instance
                                          .ref()
                                          .child(
                                            'profile_images/$uid.jpg',
                                          );
                                      await ref.putFile(
                                        File(pickedImage!.path),
                                      );
                                      newPhotoUrl =
                                          await ref.getDownloadURL();
                                    }
                                    final updates = <String, dynamic>{
                                      'name': nameCtrl.text.trim(),
                                      'company':
                                          companyCtrl.text.trim(),
                                      'phone': phoneCtrl.text.trim(),
                                      'bio': bioCtrl.text.trim(),
                                    };
                                    if (newPhotoUrl != null) {
                                      updates['photoUrl'] = newPhotoUrl;
                                    }
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(uid)
                                        .update(updates);
                                    if (!mounted) return;
                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                    }
                                  } catch (_) {
                                    setModal(() => saving = false);
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: saving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white70,
                                  ),
                                )
                              : const Text(
                                  'Save Changes',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Log out',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      widget.onLogout?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final accentColor = _viewRole == 'worker' ? kBlue : kGold;

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: accentColor, strokeWidth: 2),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Profile Header Card ──────────────────────────────────────
          _ProfileCard(
            name: _name,
            email: _email,
            phone: _phone,
            bio: _bio,
            company: _company,
            photoUrl: _photoUrl,
            createdAt: _createdAt,
            isVerified: _isVerified,
            isDark: isDark,
            cardColor: cardColor,
            onSurface: onSurface,
            onEdit: _showEditProfile,
          ),
          const SizedBox(height: 20),

          // ── Role Switcher ────────────────────────────────────────────
          _RoleSwitcher(
            selected: _viewRole,
            onChanged: (r) => setState(() => _viewRole = r),
            isDark: isDark,
            cardColor: cardColor,
            onSurface: onSurface,
          ),
          const SizedBox(height: 16),

          // ── Role-specific Stats ──────────────────────────────────────
          if (_viewRole == 'worker')
            _WorkerStats(
              rating: _ratingAsWorker,
              ratingCount: _workerRatingCount,
              earningsByCode: _earningsByCode,
              weeklyByCode: _weeklyByCode,
              completedGigs: _completedGigsWorker,
              isDark: isDark,
              cardColor: cardColor,
              onSurface: onSurface,
            )
          else
            _HostStats(
              rating: _ratingAsHost,
              ratingCount: _hostRatingCount,
              gigsPosted: _gigsPosted,
              activeGigs: _activeGigs,
              completedGigs: _completedGigsHost,
              spentByCurrency: _spentByCurrency,
              completionRate: _completionRate,
              isDark: isDark,
              cardColor: cardColor,
              onSurface: onSurface,
            ),
          const SizedBox(height: 20),

          // ── Account actions ──────────────────────────────────────────
          _SectionHeader(label: 'Account', onSurface: onSurface),
          const SizedBox(height: 10),
          _ActionCard(
            isDark: isDark,
            cardColor: cardColor,
            children: _viewRole == 'worker'
                ? [
                    _ActionRow(
                      icon: Icons.construction_rounded,
                      iconColor: kGold,
                      label: 'My Toolchest',
                      badge: _skills.isNotEmpty ? '${_skills.length}' : null,
                      badgeColor: kGold,
                      onTap: () => ToolchestSheet.show(context, _uid),
                    ),
                    _ActionDivider(isDark: isDark),
                    _ActionRow(
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
                    _ActionDivider(isDark: isDark),
                    _ActionRow(
                      icon: Icons.star_outline_rounded,
                      iconColor: kGold,
                      label: 'Ratings & Reviews',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const WorkerRatingsScreen(),
                        ),
                      ),
                    ),
                  ]
                : [
                    _ActionRow(
                      icon: Icons.history_rounded,
                      iconColor: kBlue,
                      label: 'Gig History',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HostGigsScreen(uid: _uid),
                        ),
                      ),
                    ),
                    _ActionDivider(isDark: isDark),
                    _ActionRow(
                      icon: Icons.favorite_outline_rounded,
                      iconColor: const Color(0xFFEC4899),
                      label: 'Favorite Workers',
                      onTap: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) =>
                            FavoriteWorkersSheet(hostId: _uid),
                      ),
                    ),
                    _ActionDivider(isDark: isDark),
                    _ActionRow(
                      icon: Icons.star_outline_rounded,
                      iconColor: kGold,
                      label: 'Ratings Given',
                      onTap: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const RatingsGivenSheet(),
                      ),
                    ),
                    _ActionDivider(isDark: isDark),
                    _ActionRow(
                      icon: Icons.receipt_long_outlined,
                      iconColor: const Color(0xFF10B981),
                      label: 'Payment History',
                      onTap: () {
                        final completed = [
                          ..._quickGigsDocs,
                          ..._openGigsDocs,
                          ..._offeredGigsDocs,
                        ]
                            .where(
                              (g) =>
                                  (g['status'] as String?) ==
                                  'completed',
                            )
                            .toList();
                        PaymentHistorySheet.show(
                          context: context,
                          completedGigs: completed,
                        );
                      },
                    ),
                  ],
          ),
          const SizedBox(height: 16),

          // ── Settings ─────────────────────────────────────────────────
          _SectionHeader(label: 'Settings', onSurface: onSurface),
          const SizedBox(height: 10),
          _ActionCard(
            isDark: isDark,
            cardColor: cardColor,
            children: [
              _ActionRow(
                icon: Icons.notifications_outlined,
                iconColor: const Color(0xFF8B5CF6),
                label: 'Notifications',
                onTap: () => _viewRole == 'worker'
                    ? WorkerNotificationsSheet.show(context)
                    : host_notif.NotificationsSheet.show(context),
              ),
              _ActionDivider(isDark: isDark),
              _ActionRow(
                icon: Icons.description_rounded,
                iconColor: const Color(0xFF8B5CF6),
                label: 'My Documents',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MyDocumentsScreen(userId: _uid),
                  ),
                ),
              ),
              _ActionDivider(isDark: isDark),
              _ActionRow(
                icon: Icons.verified_outlined,
                iconColor: kBlue,
                label: 'Verification',
                badge: _kBadgeLabels[_isVerified],
                badgeColor: _kBadgeColors[_isVerified],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const VerificationScreen(),
                  ),
                ),
              ),
              _ActionDivider(isDark: isDark),
              _ActionRow(
                icon: Icons.card_giftcard,
                iconColor: const Color(0xFF8B5CF6),
                label: 'My Referrals',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MyReferralScreen(),
                  ),
                ),
              ),
              _ActionDivider(isDark: isDark),
              _ActionRow(
                icon: Icons.settings_outlined,
                iconColor: kSub,
                label: 'Settings',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WorkerSettingsScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Switch Role ──────────────────────────────────────────────
          if (widget.onSwitchRole != null) ...[
            _SectionHeader(label: 'Switch Mode', onSurface: onSurface),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: widget.onSwitchRole,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 18,
                ),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? kBorder
                        : Colors.grey.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: (widget.initialRole == 'worker'
                                ? kGold
                                : kBlue)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        widget.initialRole == 'worker'
                            ? Icons.business_center_outlined
                            : Icons.work_outline_rounded,
                        color: widget.initialRole == 'worker'
                            ? kGold
                            : kBlue,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.initialRole == 'worker'
                                ? 'Switch to Host Mode'
                                : 'Switch to Worker Mode',
                            style: TextStyle(
                              color: onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            widget.initialRole == 'worker'
                                ? 'Post gigs and hire workers'
                                : 'Find gigs and earn money',
                            style: const TextStyle(
                              color: kSub,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: kSub,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Logout ───────────────────────────────────────────────────
          _ActionCard(
            isDark: isDark,
            cardColor: cardColor,
            children: [
              _ActionRow(
                icon: Icons.logout_rounded,
                iconColor: Colors.redAccent,
                label: 'Log out',
                labelColor: Colors.redAccent,
                onTap: _confirmLogout,
                showArrow: false,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Delete Account ───────────────────────────────────────────
          _ActionCard(
            isDark: isDark,
            cardColor: cardColor,
            children: [
              _ActionRow(
                icon: Icons.delete_outline_rounded,
                iconColor: Colors.redAccent,
                label: 'Delete Account',
                labelColor: Colors.redAccent,
                onTap: () => DeleteAccountService.deleteAccount(context),
                showArrow: true,
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Profile Header Card
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileCard extends StatelessWidget {
  final String name,
      email,
      phone,
      bio,
      company,
      photoUrl,
      createdAt,
      isVerified;
  final bool isDark;
  final Color cardColor, onSurface;
  final VoidCallback onEdit;

  const _ProfileCard({
    required this.name,
    required this.email,
    required this.phone,
    required this.bio,
    required this.company,
    required this.photoUrl,
    required this.createdAt,
    required this.isVerified,
    required this.isDark,
    required this.cardColor,
    required this.onSurface,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? kBorder : Colors.grey.withValues(alpha: 0.15),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Gradient banner ──
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 90,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kBlue, Color(0xFF6366F1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              // Edit button
              Positioned(
                top: 12,
                right: 14,
                child: GestureDetector(
                  onTap: onEdit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_outlined, color: Colors.white, size: 13),
                        SizedBox(width: 5),
                        Text(
                          'Edit',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Avatar overlapping banner
              Positioned(
                bottom: -36,
                left: 18,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: cardColor, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: photoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: photoUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                const _DefaultAvatar(size: 76),
                            errorWidget: (_, _, _) =>
                                const _DefaultAvatar(size: 76),
                          )
                        : const _DefaultAvatar(size: 76),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 44),
          // ── Name / badge ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        name.isNotEmpty ? name : 'User',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isVerified == 'verified') ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.verified, color: kBlue, size: 17),
                    ],
                  ],
                ),
                if (company.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    company,
                    style: const TextStyle(color: kSub, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (isVerified.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (_kBadgeColors[isVerified] ?? Colors.grey)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: (_kBadgeColors[isVerified] ?? Colors.grey)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      _kBadgeLabels[isVerified] ?? isVerified,
                      style: TextStyle(
                        color: _kBadgeColors[isVerified] ?? Colors.grey,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Divider(
                  color: isDark
                      ? kBorder
                      : Colors.grey.withValues(alpha: 0.15),
                  height: 1,
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: email,
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.phone_outlined,
                    label: 'Phone',
                    value: phone,
                  ),
                ],
                if (createdAt.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Joined',
                    value: createdAt.replaceFirst('Member since ', ''),
                  ),
                ],
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.grey.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? kBorder
                            : Colors.grey.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Text(
                      bio,
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 13,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Role Switcher
// ─────────────────────────────────────────────────────────────────────────────
class _RoleSwitcher extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  final bool isDark;
  final Color cardColor, onSurface;

  const _RoleSwitcher({
    required this.selected,
    required this.onChanged,
    required this.isDark,
    required this.cardColor,
    required this.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _RoleChip(
            label: 'Gig Worker',
            icon: Icons.work_outline_rounded,
            isSelected: selected == 'worker',
            accentColor: kBlue,
            onTap: () => onChanged('worker'),
            isDark: isDark,
            onSurface: onSurface,
          ),
          _RoleChip(
            label: 'Gig Host',
            icon: Icons.business_center_outlined,
            isSelected: selected == 'host',
            accentColor: kGold,
            onTap: () => onChanged('host'),
            isDark: isDark,
            onSurface: onSurface,
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;
  final bool isDark;
  final Color onSurface;

  const _RoleChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
    required this.isDark,
    required this.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : kSub,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : kSub,
                  fontSize: 13,
                  fontWeight: isSelected
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Worker Stats
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerStats extends StatelessWidget {
  final double rating;
  final int ratingCount;
  final Map<String, double> earningsByCode;
  final Map<String, double> weeklyByCode;
  final int completedGigs;
  final bool isDark;
  final Color cardColor, onSurface;

  const _WorkerStats({
    required this.rating,
    required this.ratingCount,
    required this.earningsByCode,
    required this.weeklyByCode,
    required this.completedGigs,
    required this.isDark,
    required this.cardColor,
    required this.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    final totalStr = earningsByCode.isEmpty
        ? CurrencyFormatter.format(0, 'PHP')
        : (earningsByCode.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => CurrencyFormatter.format(e.value, e.key))
            .join('  ');

    final weeklyStr = weeklyByCode.isEmpty
        ? CurrencyFormatter.format(0, 'PHP')
        : (weeklyByCode.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => CurrencyFormatter.format(e.value, e.key))
            .join('  ');

    return Column(
      children: [
        // Reputation row
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? kBorder : Colors.grey.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ReputationItem(
                icon: Icons.star_rounded,
                iconColor: Colors.amber,
                value: rating.toStringAsFixed(1),
                label: 'Worker Rating',
                sub: '($ratingCount)',
                onSurface: onSurface,
              ),
              _VertDivider(),
              _ReputationItem(
                icon: Icons.check_circle_outline_rounded,
                iconColor: const Color(0xFF10B981),
                value: '$completedGigs',
                label: 'Gigs Done',
                onSurface: onSurface,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Earnings grid
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _StatCard(
              label: 'Total Earnings',
              value: totalStr,
              icon: Icons.payments_outlined,
              color: const Color(0xFF10B981),
              isDark: isDark,
              cardColor: cardColor,
              onSurface: onSurface,
              compact: true,
            ),
            _StatCard(
              label: 'This Week',
              value: weeklyStr,
              icon: Icons.trending_up_rounded,
              color: kBlue,
              isDark: isDark,
              cardColor: cardColor,
              onSurface: onSurface,
              compact: true,
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Host Stats
// ─────────────────────────────────────────────────────────────────────────────
class _HostStats extends StatelessWidget {
  final double rating;
  final int ratingCount;
  final int gigsPosted, activeGigs, completedGigs;
  final Map<String, double> spentByCurrency;
  final double completionRate;
  final bool isDark;
  final Color cardColor, onSurface;

  const _HostStats({
    required this.rating,
    required this.ratingCount,
    required this.gigsPosted,
    required this.activeGigs,
    required this.completedGigs,
    required this.spentByCurrency,
    required this.completionRate,
    required this.isDark,
    required this.cardColor,
    required this.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    final spentStr = spentByCurrency.isEmpty
        ? CurrencyFormatter.format(0, 'PHP')
        : (spentByCurrency.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => CurrencyFormatter.format(e.value, e.key))
            .join('  ');

    return Column(
      children: [
        // Reputation row
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? kBorder : Colors.grey.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ReputationItem(
                icon: Icons.star_rounded,
                iconColor: Colors.amber,
                value: rating.toStringAsFixed(1),
                label: 'Host Rating',
                sub: '($ratingCount)',
                onSurface: onSurface,
              ),
              _VertDivider(),
              _ReputationItem(
                icon: Icons.percent,
                iconColor: kGold,
                value: '${completionRate.toStringAsFixed(0)}%',
                label: 'Completion',
                onSurface: onSurface,
              ),
              _VertDivider(),
              _ReputationItem(
                icon: Icons.check_circle_outline_rounded,
                iconColor: const Color(0xFF10B981),
                value: '$completedGigs/$gigsPosted',
                label: 'Completed',
                onSurface: onSurface,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _StatCard(
              label: 'Gigs Posted',
              value: '$gigsPosted',
              icon: Icons.work_outline_rounded,
              color: kGold,
              isDark: isDark,
              cardColor: cardColor,
              onSurface: onSurface,
            ),
            _StatCard(
              label: 'Active Gigs',
              value: '$activeGigs',
              icon: Icons.bolt_rounded,
              color: kBlue,
              isDark: isDark,
              cardColor: cardColor,
              onSurface: onSurface,
            ),
            _StatCard(
              label: 'Completed',
              value: '$completedGigs',
              icon: Icons.check_circle_outline_rounded,
              color: const Color(0xFF10B981),
              isDark: isDark,
              cardColor: cardColor,
              onSurface: onSurface,
            ),
            _StatCard(
              label: 'Total Spent',
              value: spentStr,
              icon: Icons.payments_outlined,
              color: const Color(0xFFEC4899),
              isDark: isDark,
              cardColor: cardColor,
              onSurface: onSurface,
              compact: true,
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ReputationItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final String? sub;
  final Color onSurface;

  const _ReputationItem({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.onSurface,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                color: onSurface,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (sub != null) ...[
              const SizedBox(width: 2),
              Text(sub!, style: const TextStyle(color: kSub, fontSize: 11)),
            ],
          ],
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: const TextStyle(color: kSub, fontSize: 11),
        ),
      ],
    );
  }
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 36,
        color: kBorder,
      );
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final bool isDark;
  final Color cardColor, onSurface;
  final bool compact;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.cardColor,
    required this.onSurface,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? kBorder : Colors.grey.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        color: onSurface,
                        fontSize: compact ? 13 : 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      label,
                      style: const TextStyle(color: kSub, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Colored top accent bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color onSurface;

  const _SectionHeader({required this.label, required this.onSurface});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: kBlue,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: onSurface.withValues(alpha: 0.55),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final List<Widget> children;
  final bool isDark;
  final Color cardColor;

  const _ActionCard({
    required this.children,
    required this.isDark,
    required this.cardColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? kBorder : Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onTap;
  final bool showArrow;

  const _ActionRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.labelColor,
    this.badge,
    this.badgeColor,
    this.showArrow = true,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
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
                ),
              ),
            ),
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: (badgeColor ?? kBlue).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    color: badgeColor ?? kBlue,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (showArrow)
              const Icon(
                Icons.chevron_right_rounded,
                color: kSub,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionDivider extends StatelessWidget {
  final bool isDark;
  const _ActionDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: isDark
          ? kBorder.withValues(alpha: 0.5)
          : Colors.grey.withValues(alpha: 0.12),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: kSub, size: 15),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(color: kSub, fontSize: 12)),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
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
        color: kBlue.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.account_circle_rounded,
        color: kBlue,
        size: size * 0.6,
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final bool isDark;
  final Color cardColor, onSurface;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _EditField({
    required this.ctrl,
    required this.label,
    required this.icon,
    required this.isDark,
    required this.cardColor,
    required this.onSurface,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? kBorder : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        validator: validator,
        style: TextStyle(color: onSurface, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: kSub, fontSize: 13),
          prefixIcon: Icon(icon, color: kSub, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}
