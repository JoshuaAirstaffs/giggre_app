import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:giggre_app/services/delete_acc_service.dart';
import 'package:giggre_app/features/gig_host/presentation/my_documents_screen.dart';
import 'package:giggre_app/features/gig_worker/presentation/verification_screen.dart';
import 'package:giggre_app/screens/referrals/my_referral_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/profile_tab_theme.dart';
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

const _kProfileStatsModeKey = 'profile_stats_mode';

const _kBadgeLabels = {
  'unverified': 'Unverified',
  'verified': 'Verified',
  'pending': 'Pending',
  'rejected': 'Rejected',
};

const _kBadgeColors = {
  'unverified': Colors.blue,
  'verified': _kGreen,
  'pending': Colors.orangeAccent,
  'rejected': Colors.red,
};

// ── Shared accents (identical across light/dark per the design system) ──────
const _kCoverStart = Color(0xFF2B6FB5);
const _kCoverEnd = Color(0xFF1F4D80);
const _kGreen = Color(0xFF2E9E6B);
const _kRed = Color(0xFFE5484D);
const _kPurple = Color(0xFF8B6FD8);
const _kGoldDeep = Color(0xFFD88810);
// Gold read as flat text needs a deeper shade on light surfaces for contrast;
// the brand gold (kGold) already contrasts fine on dark surfaces/icon tints.
const _kGoldTextLight = Color(0xFFB06E00);

// Formats a phone number for display only — never mutates the stored value.
String _formatPhoneForDisplay(String raw) {
  if (raw.trim().isEmpty) return raw;
  final hasPlus = raw.trim().startsWith('+');
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return raw;

  var countryCode = '';
  var rest = digits;
  if (hasPlus) {
    final codeLen = digits.length > 10 ? digits.length - 10 : 1;
    countryCode = digits.substring(0, codeLen.clamp(1, 3));
    rest = digits.substring(countryCode.length);
  }

  final groups = <String>[];
  final chunkSizes = rest.length == 10 ? const [3, 3, 4] : null;
  var i = 0;
  if (chunkSizes != null) {
    for (final size in chunkSizes) {
      groups.add(rest.substring(i, i + size));
      i += size;
    }
  } else {
    while (i < rest.length) {
      final end = (i + 3 < rest.length) ? i + 3 : rest.length;
      groups.add(rest.substring(i, end));
      i = end;
    }
  }

  final formatted = groups.join(' ');
  return hasPlus ? '+$countryCode $formatted' : formatted;
}

// Joins a per-currency-code amount map into a display string using the
// existing CurrencyFormatter — unchanged calculation, just centralized.
String _formatByCode(Map<String, double> byCode) {
  if (byCode.isEmpty) return CurrencyFormatter.format(0, 'PHP');
  return (byCode.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
      .map((e) => CurrencyFormatter.format(e.value, e.key))
      .join('  ');
}

// ─────────────────────────────────────────────────────────────────────────────
//  ProfileTab — shared profile tab for both Worker and Host screens
// ─────────────────────────────────────────────────────────────────────────────
class ProfileTab extends StatefulWidget {
  final String initialRole; // 'worker' or 'host'
  final VoidCallback? onSwitchRole; // navigates to the other role screen
  final VoidCallback? onLogout;
  // True when this widget is the root of a bottom-nav tab (WorkerShell /
  // HostShell) — those shells can themselves be pushed on top of another
  // route (e.g. from the home screen's role picker), so Navigator.canPop()
  // can't reliably tell "tab root" apart from "pushed as its own screen".
  // Callers that push ProfileTab as a standalone screen should pass false.
  final bool isTabRoot;

  const ProfileTab({
    super.key,
    required this.initialRole,
    this.onSwitchRole,
    this.onLogout,
    this.isTabRoot = true,
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
    _loadViewRole();
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

  Future<void> _loadViewRole() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kProfileStatsModeKey);
    if ((saved == 'worker' || saved == 'host') && mounted) {
      setState(() => _viewRole = saved!);
    }
  }

  void _setViewRole(String role) {
    if (role == _viewRole) return;
    setState(() => _viewRole = role);
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setString(_kProfileStatsModeKey, role),
    );
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
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    final goldText = isDark ? kGold : _kGoldTextLight;

    if (_loading) {
      final accentColor = _viewRole == 'worker' ? kBlue : kGold;
      return Center(
        child: CircularProgressIndicator(color: accentColor, strokeWidth: 2),
      );
    }

    final totalStr = _formatByCode(_earningsByCode);
    final weeklyStr = _formatByCode(_weeklyByCode);
    final spentStr = _formatByCode(_spentByCurrency);

    final workerColumns = <_StatColumn>[
      if (_workerRatingCount > 0)
        _StatColumn(
          value: '${_ratingAsWorker.toStringAsFixed(1)} ★',
          label: 'Worker rating ($_workerRatingCount)',
          valueColor: goldText,
        ),
      _StatColumn(value: '$_completedGigsWorker', label: 'Gigs done'),
      _StatColumn(value: totalStr, label: 'Total earned', valueColor: kBlue),
    ];

    final hostColumns = <_StatColumn>[
      if (_hostRatingCount > 0)
        _StatColumn(
          value: '${_ratingAsHost.toStringAsFixed(1)} ★',
          label: 'Host rating ($_hostRatingCount)',
          valueColor: goldText,
        ),
      _StatColumn(
        value: '$_gigsPosted',
        label: 'Gigs posted',
        valueColor: goldText,
      ),
      _StatColumn(
        value: '$_completedGigsHost',
        label: 'Completed',
        valueColor: goldText,
      ),
    ];

    return Container(
      color: tokens.screenBg,
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title ──────────────────────────────────────────────────
              Row(
                children: [
                  if (!widget.isTabRoot)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => Navigator.maybePop(context),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 17,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                  Text(
                    'Profile',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Profile Header Card ──────────────────────────────────────
              _ProfileCard(
                name: _name,
                email: _email,
                phone: _phone,
                bio: _bio,
                photoUrl: _photoUrl,
                createdAt: _createdAt,
                isVerified: _isVerified,
                tokens: tokens,
                onEdit: _showEditProfile,
              ),
              const SizedBox(height: 16),

              // ── Role Stats Toggle ─────────────────────────────────────────
              _RoleToggle(
                selected: _viewRole,
                onChanged: _setViewRole,
                tokens: tokens,
              ),
              const SizedBox(height: 16),

              // ── Role-specific Stats ──────────────────────────────────────
              if (_viewRole == 'worker')
                _StatsCard(
                  columns: workerColumns,
                  footnote: '$weeklyStr earned this week',
                  tokens: tokens,
                )
              else
                _StatsCard(
                  columns: hostColumns,
                  footnote:
                      '$_activeGigs active · ${_completionRate.toStringAsFixed(0)}% completion · $spentStr spent',
                  tokens: tokens,
                ),
              const SizedBox(height: 20),

              // ── Account actions ──────────────────────────────────────────
              _SectionHeader(label: 'Account', tokens: tokens),
              const SizedBox(height: 10),
              _ActionCard(
                tokens: tokens,
                children: _viewRole == 'worker'
                    ? [
                        _ActionRow(
                          icon: Icons.construction_rounded,
                          iconColor: kGold,
                          label: 'My Toolchest',
                          badge:
                              _skills.isNotEmpty ? '${_skills.length}' : null,
                          badgeColor: kGold,
                          tokens: tokens,
                          onTap: () => ToolchestSheet.show(context, _uid),
                        ),
                        _ActionDivider(tokens: tokens),
                        _ActionRow(
                          icon: Icons.history_rounded,
                          iconColor: kBlue,
                          label: 'Gig History',
                          tokens: tokens,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const GigHistoryScreen(),
                            ),
                          ),
                        ),
                        _ActionDivider(tokens: tokens),
                        _ActionRow(
                          icon: Icons.star_outline_rounded,
                          iconColor: kGold,
                          label: 'Ratings & Reviews',
                          tokens: tokens,
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
                          tokens: tokens,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HostGigsScreen(uid: _uid),
                            ),
                          ),
                        ),
                        _ActionDivider(tokens: tokens),
                        _ActionRow(
                          icon: Icons.favorite_outline_rounded,
                          iconColor: const Color(0xFFEC4899),
                          label: 'Favorite Workers',
                          tokens: tokens,
                          onTap: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) =>
                                FavoriteWorkersSheet(hostId: _uid),
                          ),
                        ),
                        _ActionDivider(tokens: tokens),
                        _ActionRow(
                          icon: Icons.star_outline_rounded,
                          iconColor: kGold,
                          label: 'Ratings Given',
                          tokens: tokens,
                          onTap: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const RatingsGivenSheet(),
                          ),
                        ),
                        _ActionDivider(tokens: tokens),
                        _ActionRow(
                          icon: Icons.receipt_long_outlined,
                          iconColor: const Color(0xFF10B981),
                          label: 'Payment History',
                          tokens: tokens,
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
              _SectionHeader(label: 'Settings', tokens: tokens),
              const SizedBox(height: 10),
              _ActionCard(
                tokens: tokens,
                children: [
                  _ActionRow(
                    icon: Icons.notifications_outlined,
                    iconColor: kBlue,
                    label: 'Notifications',
                    tokens: tokens,
                    onTap: () => _viewRole == 'worker'
                        ? WorkerNotificationsSheet.show(context)
                        : host_notif.NotificationsSheet.show(context),
                  ),
                  _ActionDivider(tokens: tokens),
                  _ActionRow(
                    icon: Icons.description_rounded,
                    iconColor: _kPurple,
                    label: 'My Documents',
                    tokens: tokens,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MyDocumentsScreen(userId: _uid),
                      ),
                    ),
                  ),
                  _ActionDivider(tokens: tokens),
                  _ActionRow(
                    icon: Icons.shield_outlined,
                    iconColor: _kGreen,
                    label: 'Verification',
                    badge: _kBadgeLabels[_isVerified],
                    badgeColor: _kBadgeColors[_isVerified],
                    tokens: tokens,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const VerificationScreen(),
                      ),
                    ),
                  ),
                  _ActionDivider(tokens: tokens),
                  _ActionRow(
                    icon: Icons.card_giftcard,
                    iconColor: _kPurple,
                    label: 'My Referrals',
                    tokens: tokens,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MyReferralScreen(),
                      ),
                    ),
                  ),
                  _ActionDivider(tokens: tokens),
                  _ActionRow(
                    icon: Icons.settings_outlined,
                    iconColor: tokens.textSecondary,
                    label: 'Settings',
                    tokens: tokens,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WorkerSettingsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Switch Role ──────────────────────────────────────────────
              if (widget.onSwitchRole != null) ...[
                _SectionHeader(label: 'Switch Mode', tokens: tokens),
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
                      color: tokens.cardSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: tokens.cardBorder),
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
                                .withValues(alpha: tokens.iconTintAlpha),
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
                                  color: tokens.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                widget.initialRole == 'worker'
                                    ? 'Post gigs and hire workers'
                                    : 'Find gigs and earn money',
                                style: TextStyle(
                                  color: tokens.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: tokens.textSecondary,
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
                tokens: tokens,
                children: [
                  _ActionRow(
                    icon: Icons.logout_rounded,
                    iconColor: _kRed,
                    label: 'Log out',
                    labelColor: _kRed,
                    labelWeight: FontWeight.w600,
                    tokens: tokens,
                    onTap: _confirmLogout,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Delete Account (demoted to a text link) ───────────────────
              Center(
                child: GestureDetector(
                  onTap: () => DeleteAccountService.deleteAccount(context),
                  child: Text(
                    'Delete Account',
                    style: TextStyle(
                      color: _kRed,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: _kRed,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) {
                    if (!snap.hasData) return const SizedBox.shrink();
                    final info = snap.data!;
                    return Text(
                      'Giggre v${info.version} (${info.buildNumber})',
                      style: TextStyle(color: tokens.textMuted, fontSize: 10),
                    );
                  },
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
//  Profile Header Card
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileCard extends StatelessWidget {
  final String name, email, phone, bio, photoUrl, createdAt, isVerified;
  final ProfileTabTokens tokens;
  final VoidCallback onEdit;
  final bool isOwner;

  const _ProfileCard({
    required this.name,
    required this.email,
    required this.phone,
    required this.bio,
    required this.photoUrl,
    required this.createdAt,
    required this.isVerified,
    required this.tokens,
    required this.onEdit,
    this.isOwner = true,
  });

  bool get _verified => isVerified == 'verified';

  String get _subtitle {
    final joined = createdAt.replaceFirst('Member since ', '');
    if (joined.isEmpty) return _verified ? 'Verified account' : '';
    return _verified
        ? 'Verified account · member since $joined'
        : 'Member since $joined';
  }

  @override
  Widget build(BuildContext context) {
    final showAbout = isOwner || bio.isNotEmpty;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tokens.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cover ──
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 88,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_kCoverStart, _kCoverEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 14,
                child: GestureDetector(
                  onTap: onEdit,
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          color: _kCoverEnd,
                          size: 13,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Edit',
                          style: TextStyle(
                            color: _kCoverEnd,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Avatar overlapping the cover
              Positioned(
                bottom: -38,
                left: 20,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: tokens.cardSurface, width: 3.5),
                      ),
                      child: ClipOval(
                        child: photoUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: photoUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, _) => _DefaultAvatar(
                                  size: 76,
                                  name: name,
                                  tokens: tokens,
                                ),
                                errorWidget: (_, _, _) => _DefaultAvatar(
                                  size: 76,
                                  name: name,
                                  tokens: tokens,
                                ),
                              )
                            : _DefaultAvatar(
                                size: 76,
                                name: name,
                                tokens: tokens,
                              ),
                      ),
                    ),
                    if (_verified)
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: _kGreen,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: tokens.cardSurface, width: 2.5),
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 46),
          // ── Identity / contact / about ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isNotEmpty ? name : 'User',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                if (_subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    _subtitle,
                    style: TextStyle(color: tokens.textMuted, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
                const SizedBox(height: 14),
                Container(height: 1, color: tokens.divider),
                if (isOwner) ...[
                  const SizedBox(height: 14),
                  _ContactRow(
                    icon: Icons.email_outlined,
                    label: 'EMAIL',
                    value: email,
                    tokens: tokens,
                  ),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _ContactRow(
                      icon: Icons.phone_outlined,
                      label: 'PHONE',
                      value: _formatPhoneForDisplay(phone),
                      tokens: tokens,
                    ),
                  ],
                ],
                if (showAbout) ...[
                  const SizedBox(height: 16),
                  Text(
                    'ABOUT',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: bio.isEmpty ? onEdit : null,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: tokens.insetBg,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: tokens.cardBorder),
                      ),
                      child: Text(
                        bio.isNotEmpty
                            ? bio
                            : 'Add a short bio so hosts know you',
                        style: TextStyle(
                          color: bio.isNotEmpty
                              ? tokens.textSecondary
                              : tokens.textMuted,
                          fontSize: 12,
                          height: 1.5,
                        ),
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

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final ProfileTabTokens tokens;

  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: tokens.insetBg,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: tokens.textSecondary, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Role Stats Toggle — segmented control (local to this screen only; does
//  NOT change the app's active worker/host mode or nav shell).
// ─────────────────────────────────────────────────────────────────────────────
class _RoleToggle extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  final ProfileTabTokens tokens;

  const _RoleToggle({
    required this.selected,
    required this.onChanged,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tokens.segmentTrack,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: _RoleSegment(
              label: 'Gig Worker',
              icon: Icons.work_outline_rounded,
              isSelected: selected == 'worker',
              gradient: const [_kCoverStart, _kCoverEnd],
              onTap: () => onChanged('worker'),
              tokens: tokens,
            ),
          ),
          Expanded(
            child: _RoleSegment(
              label: 'Gig Host',
              icon: Icons.business_center_outlined,
              isSelected: selected == 'host',
              gradient: const [kGold, _kGoldDeep],
              onTap: () => onChanged('host'),
              tokens: tokens,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleSegment extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final List<Color> gradient;
  final VoidCallback onTap;
  final ProfileTabTokens tokens;

  const _RoleSegment({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.gradient,
    required this.onTap,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : tokens.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : tokens.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Stats Card — N columns with vertical dividers + optional footnote.
// ─────────────────────────────────────────────────────────────────────────────
class _StatColumn {
  final String value;
  final String label;
  final Color? valueColor;

  const _StatColumn({required this.value, required this.label, this.valueColor});
}

class _StatsCard extends StatelessWidget {
  final List<_StatColumn> columns;
  final String? footnote;
  final ProfileTabTokens tokens;

  const _StatsCard({
    required this.columns,
    required this.tokens,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < columns.length; i++) ...[
                if (i > 0) Container(width: 1, height: 34, color: tokens.divider),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        columns[i].value,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: columns[i].valueColor ?? tokens.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        columns[i].label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (footnote != null) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: tokens.divider),
            const SizedBox(height: 10),
            Text(
              footnote!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: tokens.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final ProfileTabTokens tokens;

  const _SectionHeader({required this.label, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: tokens.textMuted,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final List<Widget> children;
  final ProfileTabTokens tokens;

  const _ActionCard({required this.children, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.cardBorder),
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
  final FontWeight labelWeight;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onTap;
  final ProfileTabTokens tokens;

  const _ActionRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    required this.tokens,
    this.labelColor,
    this.labelWeight = FontWeight.w400,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 55,
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: tokens.iconTintAlpha),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: labelColor ?? tokens.textPrimary,
                  fontSize: 14,
                  fontWeight: labelWeight,
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
                  color: (badgeColor ?? kBlue)
                      .withValues(alpha: tokens.iconTintAlpha),
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
            Icon(
              Icons.chevron_right_rounded,
              color: tokens.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionDivider extends StatelessWidget {
  final ProfileTabTokens tokens;
  const _ActionDivider({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: tokens.divider);
  }
}

class _DefaultAvatar extends StatelessWidget {
  final double size;
  final String name;
  final ProfileTabTokens tokens;

  const _DefaultAvatar({
    required this.size,
    required this.tokens,
    this.name = '',
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty
        ? name.trim()[0].toUpperCase()
        : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tokens.insetBg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: tokens.textSecondary,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
        ),
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
