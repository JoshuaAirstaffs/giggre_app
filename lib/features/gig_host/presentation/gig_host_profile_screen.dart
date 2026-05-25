import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:giggre_app/services/delete_account_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:giggre_app/features/gig_host/presentation/my_documents_screen.dart';
import 'package:giggre_app/features/gig_host/presentation/privacy_security_screen.dart';
import 'package:giggre_app/features/gig_worker/presentation/verification_screen.dart';
import 'package:giggre_app/screens/referrals/my_referral_screen.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import 'widgets/favorite_workers_sheet.dart';
import 'widgets/ratings_given_sheet.dart';
import 'widgets/payment_history_sheet.dart';
import 'widgets/notifications_sheet.dart';
import 'host_privacy_security_screen.dart';

class GigHostProfileScreen extends StatefulWidget {
  const GigHostProfileScreen({super.key});

  @override
  State<GigHostProfileScreen> createState() => _GigHostProfileScreenState();
}

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

class _GigHostProfileScreenState extends State<GigHostProfileScreen> {
  bool _loading = true;

  // Profile data
  String _userId = '';
  String _name = '';
  String _email = '';
  String _phone = '';
  String _bio = '';
  String _company = '';
  String _photoUrl = '';
  String _createdAt = '';
  double _ratingAsHost = 5.0;
  int _ratingCount = 0;
  String _isVerified = '';

  // Stats
  int _gigsPosted = 0;
  int _activeGigs = 0;
  int _completedGigs = 0;
  double _totalSpent = 0;

  double _completionRate = 0;

  StreamSubscription? _profileSub;
  StreamSubscription? _quickGigsSub;
  StreamSubscription? _openGigsSub;
  StreamSubscription? _offeredGigsSub;
  StreamSubscription? _notifSub;
  List<Map<String, dynamic>> _quickGigsDocs = [];
  List<Map<String, dynamic>> _openGigsDocs = [];
  List<Map<String, dynamic>> _offeredGigsDocs = [];

  int _unreadNotifCount = 0;

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
    _listenToProfile();
    _listenForUnread();
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _quickGigsSub?.cancel();
    _openGigsSub?.cancel();
    _offeredGigsSub?.cancel();
    _notifSub?.cancel();
    super.dispose();
  }

  void _listenToProfile() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _profileSub?.cancel();
    _profileSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
          final data = doc.data() ?? {};

          String createdAtStr = '';
          if (data['createdAt'] != null) {
            final ts = data['createdAt'] as Timestamp;
            final dt = ts.toDate();
            createdAtStr = 'Member since ${_monthName(dt.month)} ${dt.year}';
          }

          if (!mounted) return;
          setState(() {
            _userId = data['userId'] ?? '';
            _name = data['name'] ?? '';
            _email =
                FirebaseAuth.instance.currentUser?.email ?? data['email'] ?? '';
            _phone = data['phone'] ?? '';
            _bio = data['bio'] ?? '';
            _company = data['company'] ?? '';
            _photoUrl =
                data['photoUrl'] ??
                FirebaseAuth.instance.currentUser?.photoURL ??
                '';
            _createdAt = createdAtStr;
            _ratingAsHost = (data['ratingAsHost'] as num? ?? 5.0).toDouble();
            _ratingCount = (data['ratingAsHostCount'] as num? ?? 0).toInt();
            _loading = false;
            _isVerified = data['isVerified'] ?? false;
          });
        }, onError: (e) => debugPrint('[GigHostProfile] profile: $e'));

    _quickGigsSub?.cancel();
    _quickGigsSub = FirebaseFirestore.instance
        .collection('quick_gigs')
        .where('hostId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
          _quickGigsDocs = snap.docs.map((d) {
            final m = Map<String, dynamic>.from(d.data());
            m['docId'] = d.id;
            m['gigType'] = 'quick';
            return m;
          }).toList();
          _recomputeStats();
        }, onError: (e) => debugPrint('[GigHostProfile] quick_gigs: $e'));

    _openGigsSub?.cancel();
    _openGigsSub = FirebaseFirestore.instance
        .collection('open_gigs')
        .where('hostId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
          _openGigsDocs = snap.docs.map((d) {
            final m = Map<String, dynamic>.from(d.data());
            m['docId'] = d.id;
            m['gigType'] = 'open';
            return m;
          }).toList();
          _recomputeStats();
        }, onError: (e) => debugPrint('[GigHostProfile] open_gigs: $e'));

    _offeredGigsSub?.cancel();
    _offeredGigsSub = FirebaseFirestore.instance
        .collection('offered_gigs')
        .where('hostId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
          _offeredGigsDocs = snap.docs.map((d) {
            final m = Map<String, dynamic>.from(d.data());
            m['docId'] = d.id;
            m['gigType'] = 'offered';
            return m;
          }).toList();
          _recomputeStats();
        }, onError: (e) => debugPrint('[GigHostProfile] offered_gigs: $e'));
  }

  void _listenForUnread() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    _notifSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          setState(() {
            _unreadNotifCount = snapshot.docs.length;
          });
        }, onError: (e) => debugPrint('[GigHostProfile] notif: $e'));
  }

  void _recomputeStats() {
    final allDocs = [..._quickGigsDocs, ..._openGigsDocs, ..._offeredGigsDocs];
    int gigsPostedCount = allDocs.length;
    int activeGigsCount = 0;
    int completedCount = 0;
    double totalSpentAmt = 0;

    for (final d in allDocs) {
      final status = d['status'] as String? ?? '';
      if (_activeStatuses.contains(status)) activeGigsCount++;
      if (status == 'completed') {
        completedCount++;
        totalSpentAmt += (d['budget'] as num? ?? 0).toDouble();
      }
    }

    if (!mounted) return;
    setState(() {
      _gigsPosted = gigsPostedCount;
      _activeGigs = activeGigsCount;
      _completedGigs = completedCount;
      _totalSpent = totalSpentAmt;
      _completionRate = (completedCount / gigsPostedCount) * 100;
    });
  }

  void _showGigHistory() {
    final completed =
        [
            ..._quickGigsDocs,
            ..._openGigsDocs,
            ..._offeredGigsDocs,
          ].where((g) => (g['status'] as String?) == 'completed').toList()
          ..sort((a, b) {
            final aTs = a['completedAt'] as Timestamp?;
            final bTs = b['completedAt'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GigHistorySheet(gigs: completed),
    );
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

  Future<void> _pickAvatar(
    void Function(void Function()) setModal,
    void Function(XFile) onPicked,
  ) async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Change Profile Photo',
          style: TextStyle(
            color: Theme.of(ctx).colorScheme.onSurface,
            fontSize: 15,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: kAmber),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: kAmber),
              title: const Text('Choose from Library'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 512,
    );
    if (picked != null) setModal(() => onPicked(picked));
  }

  void _showEditPersonalInfo() {
    final nameCtrl = TextEditingController(text: _name);
    final companyCtrl = TextEditingController(text: _company);
    final bioCtrl = TextEditingController(text: _bio);
    final phoneCtrl = TextEditingController(text: _phone);
    bool saving = false;
    XFile? pickedImage;
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final cardColor = Theme.of(ctx).cardColor;
          final onSurface = Theme.of(ctx).colorScheme.onSurface;
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
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
                      'Edit Personal Info',
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Avatar picker ─────────────────────────────────────
                    Center(
                      child: GestureDetector(
                        onTap: saving
                            ? null
                            : () => _pickAvatar(
                                setModal,
                                (img) => pickedImage = img,
                              ),
                        child: Stack(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: kAmber.withValues(alpha: 0.5),
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
                                        placeholder: (c, u) =>
                                            const _DefaultAvatar(size: 80),
                                        errorWidget: (c, u, e) =>
                                            const _DefaultAvatar(size: 80),
                                      )
                                    : const _DefaultAvatar(size: 80),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: kAmber,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: cardColor,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  color: Colors.black,
                                  size: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _ModalField(
                      controller: nameCtrl,
                      label: 'Full Name',
                      icon: Icons.person_outline_rounded,
                      isDark: isDark,
                      cardColor: cardColor,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    _ModalField(
                      controller: companyCtrl,
                      label: 'Company / Business',
                      icon: Icons.business_outlined,
                      isDark: isDark,
                      cardColor: cardColor,
                    ),
                    const SizedBox(height: 12),
                    _ModalField(
                      controller: phoneCtrl,
                      label: 'Phone Number',
                      icon: Icons.phone_outlined,
                      isDark: isDark,
                      cardColor: cardColor,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    // Bio
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
                        style: TextStyle(color: onSurface, fontSize: 14),
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
                                if (!formKey.currentState!.validate()) return;
                                setModal(() => saving = true);
                                final uid =
                                    FirebaseAuth.instance.currentUser?.uid;
                                if (uid == null) return;
                                final messenger = ScaffoldMessenger.of(context);
                                try {
                                  String? newPhotoUrl;
                                  if (pickedImage != null) {
                                    final ref = FirebaseStorage.instance
                                        .ref()
                                        .child('profile_images/$uid.jpg');
                                    await ref.putFile(File(pickedImage!.path));
                                    newPhotoUrl = await ref.getDownloadURL();
                                  }
                                  final updates = <String, dynamic>{
                                    'name': nameCtrl.text.trim(),
                                    'company': companyCtrl.text.trim(),
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
                                  setState(() {
                                    _name = nameCtrl.text.trim();
                                    _company = companyCtrl.text.trim();
                                    _phone = phoneCtrl.text.trim();
                                    _bio = bioCtrl.text.trim();
                                    if (newPhotoUrl != null) {
                                      _photoUrl = newPhotoUrl;
                                    }
                                  });
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: const Row(
                                        children: [
                                          Icon(
                                            Icons.check_circle_outline,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          SizedBox(width: 10),
                                          Text('Profile updated'),
                                        ],
                                      ),
                                      backgroundColor: kBlue,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      margin: const EdgeInsets.all(16),
                                    ),
                                  );
                                } catch (_) {
                                  setModal(() => saving = false);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAmber,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
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
                                  color: Colors.black54,
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
          );
        },
      ),
    );
  }

  void _showRatingsGiven() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const RatingsGivenSheet(),
    );
  }

  void _showPaymentHistory() {
    final completed = [
      ..._quickGigsDocs,
      ..._openGigsDocs,
      ..._offeredGigsDocs,
    ].where((g) => (g['status'] as String?) == 'completed').toList();

    PaymentHistorySheet.show(context: context, completedGigs: completed);
  }

  void _showFavoriteWorkers() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FavoriteWorkersSheet(hostId: uid),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: kSub,
            size: 20,
          ),
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
                child: Icon(
                  Icons.account_circle_outlined,
                  color: kAmber,
                  size: 16,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'My Profile',
                  style: TextStyle(
                    color: onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Text(
                  'Gig Host',
                  style: TextStyle(color: kSub, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kAmber))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Personal Info Card ─────────────────────────────
                    _SectionCard(
                      isDark: isDark,
                      cardColor: cardColor,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Personal Info',
                                style: TextStyle(
                                  color: onSurface,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: _showEditPersonalInfo,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kAmber.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: kAmber.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.edit_outlined,
                                        color: kAmber,
                                        size: 13,
                                      ),
                                      SizedBox(width: 5),
                                      Text(
                                        'Edit',
                                        style: TextStyle(
                                          color: kAmber,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Avatar + identity
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _Avatar(photoUrl: _photoUrl, size: 72),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          _name.isNotEmpty ? _name : 'Gig Host',
                                          style: TextStyle(
                                            color: onSurface,
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (_isVerified == 'verified')
                                          Icon(
                                            Icons.verified,
                                            color: kBlue,
                                            size: 16,
                                          ),
                                      ],
                                    ),
                                    if (_company.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        _company,
                                        style: const TextStyle(
                                          color: kSub,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    // Star rating
                                    Row(
                                      children: [
                                        ...List.generate(5, (i) {
                                          final full =
                                              i < _ratingAsHost.floor();
                                          final half =
                                              !full &&
                                              i < _ratingAsHost &&
                                              _ratingAsHost - i >= 0.5;
                                          return Icon(
                                            full
                                                ? Icons.star_rounded
                                                : half
                                                ? Icons.star_half_rounded
                                                : Icons.star_outline_rounded,
                                            color: kAmber,
                                            size: 16,
                                          );
                                        }),
                                        const SizedBox(width: 6),
                                        Text(
                                          _ratingAsHost.toStringAsFixed(1),
                                          style: TextStyle(
                                            color: onSurface,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '($_ratingCount ${_ratingCount == 1 ? 'rating' : 'ratings'})',
                                          style: const TextStyle(
                                            color: kSub,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),
                          const Divider(color: kBorder, height: 1),
                          const SizedBox(height: 16),

                          // Info rows
                          _InfoRow(
                            icon: Icons.email_outlined,
                            label: 'Email',
                            value: _email,
                          ),
                          if (_phone.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _InfoRow(
                              icon: Icons.phone_outlined,
                              label: 'Phone',
                              value: _phone,
                            ),
                          ],
                          // if (_userId.isNotEmpty) ...[
                          //   const SizedBox(height: 10),
                          //   _InfoRow(
                          //       icon: Icons.badge_outlined,
                          //       label: 'User ID',
                          //       value: _userId),
                          // ],
                          if (_createdAt.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _InfoRow(
                              icon: Icons.calendar_today_outlined,
                              label: 'Joined',
                              value: _createdAt.replaceFirst(
                                'Member since ',
                                '',
                              ),
                            ),
                          ],

                          // Bio
                          if (_bio.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.04)
                                    : Colors.grey.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? kBorder
                                      : Colors.grey.withValues(alpha: 0.15),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'About',
                                    style: TextStyle(
                                      color: kSub,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _bio,
                                    style: TextStyle(
                                      color: onSurface,
                                      fontSize: 13,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Stats Cards ────────────────────────────────────
                    _SectionLabel(label: 'Overview', onSurface: onSurface),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.55,
                      children: [
                        _StatCard2(
                          label: 'Gigs Posted',
                          value: '$_gigsPosted',
                          icon: Icons.work_outline_rounded,
                          color: kAmber,
                          cardColor: cardColor,
                          isDark: isDark,
                        ),
                        _StatCard2(
                          label: 'Active Gigs',
                          value: '$_activeGigs',
                          icon: Icons.bolt_rounded,
                          color: kBlue,
                          cardColor: cardColor,
                          isDark: isDark,
                        ),
                        _StatCard2(
                          label: 'Completed',
                          value: '$_completedGigs',
                          icon: Icons.check_circle_outline_rounded,
                          color: const Color(0xFF10B981),
                          cardColor: cardColor,
                          isDark: isDark,
                        ),
                        _StatCard2(
                          label: 'Total Spent',
                          value: _totalSpent > 0
                              ? '₱${_totalSpent.toStringAsFixed(0)}'
                              : '₱0',
                          icon: Icons.payments_outlined,
                          color: const Color(0xFFEC4899),
                          cardColor: cardColor,
                          isDark: isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(18),
                      // height: 62,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 12,
                        children: [
                          Text(
                            'Reputation',
                            style: TextStyle(
                              color: kBlue,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.star,
                                    color: Colors.amber,
                                    size: 20,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '$_ratingAsHost ($_ratingCount)',
                                    style: TextStyle(
                                      color: onSurface,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Avg Rating',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: Color(0xFF10B981),
                                    size: 20,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '$_completedGigs/$_gigsPosted',
                                    style: TextStyle(
                                      color: onSurface,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Gigs Completed',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(Icons.percent, color: kBlue, size: 20),
                                  SizedBox(height: 4),
                                  Text(
                                    '${_completionRate.toStringAsFixed(2)}%',
                                    style: TextStyle(
                                      color: onSurface,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Completion Rate',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // ── Account ────────────────────────────────────────
                    _SectionLabel(label: 'Account', onSurface: onSurface),
                    const SizedBox(height: 12),
                    _SectionCard(
                      isDark: isDark,
                      cardColor: cardColor,
                      child: Column(
                        children: [
                          _MenuRow(
                            icon: Icons.description_rounded,
                            iconColor: const Color.fromARGB(255, 152, 4, 210),
                            label: 'My Documents',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => MyDocumentsScreen(
                                    userId:
                                        FirebaseAuth.instance.currentUser!.uid,
                                  ),
                                ),
                              );
                            },
                          ),
                          _Divider(isDark: isDark),
                          _MenuRow(
                            icon: Icons.history_rounded,
                            iconColor: kBlue,
                            label: 'Gig History',
                            onTap: _showGigHistory,
                          ),
                          _Divider(isDark: isDark),
                          _MenuRow(
                            icon: Icons.favorite_outline_rounded,
                            iconColor: const Color(0xFFEC4899),
                            label: 'Favorite Workers',
                            onTap: _showFavoriteWorkers,
                          ),
                          _Divider(isDark: isDark),
                          _MenuRow(
                            icon: Icons.star_outline_rounded,
                            iconColor: kAmber,
                            label: 'Ratings Given',
                            onTap: _showRatingsGiven,
                          ),
                          _Divider(isDark: isDark),
                          _MenuRow(
                            icon: Icons.receipt_long_outlined,
                            iconColor: const Color(0xFF10B981),
                            label: 'Payment History',
                            onTap: _showPaymentHistory,
                          ),
                          _Divider(isDark: isDark),
                          _MenuRow(
                            icon: Icons.card_giftcard,
                            iconColor: const Color(0xFF8B5CF6),
                            label: 'My Referrals',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => MyReferralScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Settings ───────────────────────────────────────
                    _SectionLabel(label: 'Settings', onSurface: onSurface),
                    const SizedBox(height: 12),
                    _SectionCard(
                      isDark: isDark,
                      cardColor: cardColor,
                      child: Column(
                        children: [
                          _MenuRow(
                            icon: Icons.verified_outlined,
                            iconColor: kBlue,
                            label: 'Verification',
                            badge: _kBadgeLabels[_isVerified],
                            badgeColor: _kBadgeColors[_isVerified],
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const VerificationScreen(),
                              ),
                            ),
                          ),
                          _Divider(isDark: isDark),
                          _MenuRow(
                            icon: Icons.notifications_outlined,
                            iconColor: kAmber,
                            label: 'Notifications',
                            onTap: () => NotificationsSheet.show(context),
                          ),

                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                 Container(
  padding: const EdgeInsets.all(16),
  width: double.infinity,
  decoration: BoxDecoration(
    color: Colors.red[50],
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: Colors.red),
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      // trash icon
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.delete,
          color: Colors.red,
          size: 18,
        ),
      ),
      const SizedBox(width: 12),
     Expanded(
  child: GestureDetector(
    onTap: () => DeleteAccountService.deleteAccount(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Delete Account', style: TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.w600)),
        Text('Permanently delete your account and data', style: TextStyle(color: Colors.grey[800], fontSize: 12)),
      ],
    ),
  ),
),
      const SizedBox(width: 8),
      Icon(Icons.chevron_right_rounded, color: Colors.grey),
    ],
  ),
),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
}

// ── Reusable widgets ───────────────────────────────────────────────────────────

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
        border: Border.all(color: kAmber.withValues(alpha: 0.4), width: 2),
      ),
      child: Icon(
        Icons.account_circle_rounded,
        color: kAmber,
        size: size * 0.6,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color onSurface;
  const _SectionLabel({required this.label, required this.onSurface});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: kAmber,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: onSurface,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  final Color cardColor;
  final bool isDark;
  const _SectionCard({
    required this.child,
    required this.cardColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? kBorder : Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: kSub, size: 16),
        const SizedBox(width: 10),
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

class _StatCard2 extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color cardColor;
  final bool isDark;

  const _StatCard2({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.cardColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
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
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(label, style: const TextStyle(color: kSub, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _MenuRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.badge,
    this.badgeColor,
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
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: onSurface, fontSize: 14),
              ),
            ),
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (badgeColor ?? kAmber).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    color: badgeColor ?? kAmber,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.chevron_right_rounded, color: kSub, size: 20),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final bool isDark;
  const _Divider({required this.isDark});

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

class _ModalField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool isDark;
  final Color cardColor;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _ModalField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.isDark,
    required this.cardColor,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
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
        controller: controller,
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

// ─────────────────────────────────────────────────────────────────────────────
//  Gig History — list sheet
// ─────────────────────────────────────────────────────────────────────────────
class _GigHistorySheet extends StatefulWidget {
  final List<Map<String, dynamic>> gigs;
  const _GigHistorySheet({required this.gigs});

  @override
  State<_GigHistorySheet> createState() => _GigHistorySheetState();
}

class _GigHistorySheetState extends State<_GigHistorySheet> {
  final _db = FirebaseFirestore.instance;
  final _hostId = FirebaseAuth.instance.currentUser?.uid ?? '';
  Set<String> _favoriteWorkerIds = {};

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    if (_hostId.isEmpty) return;
    final doc = await _db.collection('users').doc(_hostId).get();
    if (!mounted) return;
    final list =
        (doc.data()?['favoriteWorkerIds'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    setState(() => _favoriteWorkerIds = list.toSet());
  }

  Future<void> _toggleFavorite(String workerId) async {
    if (_hostId.isEmpty || workerId.isEmpty) return;
    final isFav = _favoriteWorkerIds.contains(workerId);
    setState(() {
      if (isFav) {
        _favoriteWorkerIds.remove(workerId);
      } else {
        _favoriteWorkerIds.add(workerId);
      }
    });
    await _db.collection('users').doc(_hostId).set({
      'favoriteWorkerIds': isFav
          ? FieldValue.arrayRemove([workerId])
          : FieldValue.arrayUnion([workerId]),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
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
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: kBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: kBlue,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gig History',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${widget.gigs.length} completed',
                        style: const TextStyle(color: kSub, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: kBorder),
            // Body
            if (widget.gigs.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.work_off_outlined,
                        color: kSub.withValues(alpha: 0.35),
                        size: 52,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No completed gigs yet',
                        style: TextStyle(color: kSub, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: widget.gigs.length,
                  separatorBuilder: (_, i) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final gig = widget.gigs[i];
                    final workerId =
                        gig['assignedWorkerId'] as String? ??
                        gig['workerId'] as String? ??
                        '';
                    return _GigHistoryCard(
                      gig: gig,
                      isDark: isDark,
                      isFavorite: _favoriteWorkerIds.contains(workerId),
                      onFavoriteToggle: () => _toggleFavorite(workerId),
                      onTap: () => showModalBottomSheet(
                        context: ctx,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => _GigHistoryDetailSheet(gig: gig),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Individual completed gig card
// ─────────────────────────────────────────────────────────────────────────────
class _GigHistoryCard extends StatelessWidget {
  final Map<String, dynamic> gig;
  final bool isDark;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;

  const _GigHistoryCard({
    required this.gig,
    required this.isDark,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final gigType = gig['gigType'] as String? ?? 'quick';
    final title = gig['title'] as String? ?? 'Gig';
    final budget = (gig['budget'] as num?)?.toDouble() ?? 0;
    final workerName =
        gig['assignedWorkerName'] as String? ??
        gig['workerName'] as String? ??
        '';
    final completedAt = gig['completedAt'] as Timestamp?;
    final durationSec = (gig['durationSeconds'] as num?)?.toInt();

    final typeColor = gigType == 'quick'
        ? kAmber
        : gigType == 'open'
        ? kBlue
        : const Color(0xFF8B5CF6);
    final typeLabel = gigType == 'quick'
        ? 'Quick'
        : gigType == 'open'
        ? 'Open'
        : 'Offered';
    final typeIcon = gigType == 'quick'
        ? Icons.bolt_rounded
        : gigType == 'open'
        ? Icons.work_outline_rounded
        : Icons.handshake_outlined;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.grey.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? kBorder : Colors.grey.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            // Type icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(typeIcon, color: typeColor, size: 20),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          typeLabel,
                          style: TextStyle(
                            color: typeColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (workerName.isNotEmpty) ...[
                        const Icon(
                          Icons.person_outline_rounded,
                          size: 12,
                          color: kSub,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            workerName,
                            style: const TextStyle(color: kSub, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 2),
                        GestureDetector(
                          onTap: onFavoriteToggle,
                          child: Icon(
                            isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 14,
                            color: isFavorite
                                ? Colors.redAccent
                                : kSub.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (completedAt != null) ...[
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: kSub,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _fmtDate(completedAt),
                          style: const TextStyle(color: kSub, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                  if (durationSec != null && durationSec > 0) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.timer_outlined, size: 12, color: kSub),
                        const SizedBox(width: 3),
                        Text(
                          _fmtDuration(durationSec),
                          style: const TextStyle(color: kSub, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Budget + chevron
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₱${budget.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Icon(Icons.chevron_right_rounded, color: kSub, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(Timestamp ts) {
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
    final dt = ts.toDate().toLocal();
    return '${months[dt.month]} ${dt.day}, ${dt.year}';
  }

  static String _fmtDuration(int seconds) {
    if (seconds < 60) return '$seconds sec';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Gig history detail sheet (read-only)
// ─────────────────────────────────────────────────────────────────────────────
class _GigHistoryDetailSheet extends StatelessWidget {
  final Map<String, dynamic> gig;
  const _GigHistoryDetailSheet({required this.gig});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final gigType = gig['gigType'] as String? ?? 'quick';
    final title = gig['title'] as String? ?? 'Gig';
    final description = gig['description'] as String? ?? '';
    final budget = (gig['budget'] as num?)?.toDouble() ?? 0;
    final address = gig['address'] as String? ?? '';
    final workerName =
        gig['assignedWorkerName'] as String? ??
        gig['workerName'] as String? ??
        '';
    final completedAt = gig['completedAt'] as Timestamp?;
    final workStartedAt = gig['workStartedAt'] as Timestamp?;
    final workCompletedAt = gig['workCompletedAt'] as Timestamp?;
    final durationSec = (gig['durationSeconds'] as num?)?.toInt();

    final typeColor = gigType == 'quick'
        ? kAmber
        : gigType == 'open'
        ? kBlue
        : const Color(0xFF8B5CF6);
    final typeLabel = gigType == 'quick'
        ? 'Quick Gig'
        : gigType == 'open'
        ? 'Open Gig'
        : 'Offered Gig';
    final typeIcon = gigType == 'quick'
        ? Icons.bolt_rounded
        : gigType == 'open'
        ? Icons.work_outline_rounded
        : Icons.handshake_outlined;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            // Handle
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

            // Title + completed badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Completed',
                    style: TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Type chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(typeIcon, color: typeColor, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    typeLabel,
                    style: TextStyle(
                      color: typeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Gig details card ─────────────────────────────────────
            _HistoryDetailCard(
              isDark: isDark,
              title: 'Gig Details',
              children: [
                if (description.isNotEmpty)
                  _HistoryDetailRow(
                    icon: Icons.notes_rounded,
                    label: 'Description',
                    value: description,
                    onSurface: onSurface,
                  ),
                _HistoryDetailRow(
                  icon: Icons.attach_money_rounded,
                  label: 'Budget',
                  value: '₱${budget.toStringAsFixed(0)}',
                  valueColor: kAmber,
                  onSurface: onSurface,
                ),
                if (address.isNotEmpty)
                  _HistoryDetailRow(
                    icon: Icons.location_on_outlined,
                    label: 'Location',
                    value: address,
                    onSurface: onSurface,
                  ),
                if (workerName.isNotEmpty)
                  _HistoryDetailRow(
                    icon: Icons.person_outline_rounded,
                    label: 'Worker',
                    value: workerName,
                    valueColor: kBlue,
                    onSurface: onSurface,
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Timeline card ────────────────────────────────────────
            _HistoryDetailCard(
              isDark: isDark,
              title: 'Timeline',
              children: [
                if (workStartedAt != null)
                  _HistoryDetailRow(
                    icon: Icons.play_circle_outline_rounded,
                    label: 'Work Started',
                    value: _fmtDateTime(workStartedAt),
                    onSurface: onSurface,
                  ),
                if (workCompletedAt != null)
                  _HistoryDetailRow(
                    icon: Icons.stop_circle_outlined,
                    label: 'Work Ended',
                    value: _fmtDateTime(workCompletedAt),
                    onSurface: onSurface,
                  ),
                _HistoryDetailRow(
                  icon: Icons.verified_rounded,
                  label: 'Completed On',
                  value: completedAt != null ? _fmtDateTime(completedAt) : '—',
                  valueColor: const Color(0xFF10B981),
                  onSurface: onSurface,
                ),
                if (durationSec != null && durationSec > 0)
                  _HistoryDetailRow(
                    icon: Icons.hourglass_bottom_rounded,
                    label: 'Total Time Spent',
                    value: _fmtDuration(durationSec),
                    valueColor: kAmber,
                    onSurface: onSurface,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDateTime(Timestamp ts) {
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
    final dt = ts.toDate().toLocal();
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month]} ${dt.day}, ${dt.year}  $h:$m $period';
  }

  static String _fmtDuration(int seconds) {
    if (seconds < 60) return '$seconds sec';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }
}

class _HistoryDetailCard extends StatelessWidget {
  final bool isDark;
  final String title;
  final List<Widget> children;

  const _HistoryDetailCard({
    required this.isDark,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? kBorder : Colors.grey.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: onSurface,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...children.expand((w) => [w, const SizedBox(height: 12)]).toList()
            ..removeLast(),
        ],
      ),
    );
  }
}

class _HistoryDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final Color onSurface;

  const _HistoryDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onSurface,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: kSub),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: kSub,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: valueColor ?? onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
