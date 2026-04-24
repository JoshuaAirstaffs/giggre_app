import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:giggre_app/core/providers/current_user_provider.dart';
import 'package:giggre_app/screens/app_contents/contact_us.dart';
import 'package:giggre_app/screens/app_contents/help_faq.dart';
import 'package:giggre_app/screens/app_contents/privacy_policy.dart';
import 'package:giggre_app/screens/app_contents/terms_and_conditions.dart';
import 'package:giggre_app/screens/chat/home_chat.dart';
import 'package:provider/provider.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:giggre_app/core/widgets/update_card.dart';
import 'package:giggre_app/screens/app_contents/about_giggre.dart';
import 'package:giggre_app/screens/giggre-updates.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_provider.dart';
import '../../auth/presentation/login_screen.dart';
import '../../gig_host/presentation/gig_host_screen.dart';
import '../../gig_worker/presentation/gig_worker_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _userName = '';
  String? _selectedRole;
  bool _saving = false;
  bool _hasUnreadMessages = false;
  StreamSubscription? _roomsStreamSub;        // ← rooms-level sub
  final List<StreamSubscription> _roomSubs = []; // ← message-level subs
  List<Map<String, dynamic>> _updates = [];

  @override
  void initState() {
    super.initState();
    _loadUser();
    _fetchUpdates();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showBetaModal());
    _listenForUnreadMessages();
  }

  @override
  void dispose() {
    _roomsStreamSub?.cancel();
    for (final sub in _roomSubs) sub.cancel();
    super.dispose();
  }

 Future<void> _fetchUpdates() async {
  try {
    final response = await FirebaseFirestore.instance
        .collection('app_content')
        .doc('updates')
        .collection('items')
        .get();
    setState(() {
      _updates = response.docs.map((doc) {
        final data = doc.data();
        if (data['dateUpdated'] is Timestamp) {
          data['dateUpdated'] = (data['dateUpdated'] as Timestamp).toDate();
        }
        return data;
      }).toList();
    });
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
        .listen((roomsSnap) {
          // Cancel old message subs before setting up new ones
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
        }, onError: (e) => debugPrint('[HomeScreen] rooms stream error: $e'));
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
    });
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
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Log Out',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: kSub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: kSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _roomsStreamSub?.cancel();
      for (final sub in _roomSubs) {
        sub.cancel();
      }
      _roomSubs.clear();
      if (mounted) {
        context.read<CurrentUserProvider>().clearUser();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
      await FirebaseAuth.instance.signOut();
    }
  }

  
  
  final GlobalKey<RefreshIndicatorState> _refreshKey = GlobalKey<RefreshIndicatorState>();
  int _carouselRefreshKey = 0;

  Future<void> _refreshAll() async {
  await Future.wait([
    _loadUser(),
    _fetchUpdates()
  ]);
  if (mounted) setState(() => _carouselRefreshKey++);
}

  @override
  Widget build(BuildContext context) {
    final firstName = _userName.split(' ').first;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeProvider = context.read<ThemeProvider>();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    //get current year
    final currentYear = DateTime.now().year;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: kBlue.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.bolt, color: kAmber, size: 22),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: const Color(0xFF1E1E2C),
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (_) => const _GiggreMenu(),
                );
              },
              child: Text(
                'Giggre',
                style: TextStyle(
                  color: onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: kSub,
            ),
            onPressed: () => themeProvider.toggle(),
          ),
          IconButton(
            tooltip: 'Messages',
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.message_outlined, color: kSub),
                if (_hasUnreadMessages)
                  Positioned(
                    top: -2,
                    right: -2,
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
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HomeChat()),
              );
            },
          ),
          IconButton(
            tooltip: 'Log Out',
            icon: const Icon(Icons.logout_rounded, color: kSub),
            onPressed: _logout,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          key: _refreshKey,
          onRefresh: _refreshAll, 
          color: kBlue,
          child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: kBlue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.account_circle_rounded,
                        color: kBlue, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    firstName.isNotEmpty ? 'Hey, $firstName 👋' : 'Welcome back 👋',
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'How do you want to use Giggre today?',
                style: TextStyle(color: kSub, fontSize: 14),
              ),
              const SizedBox(height: 20),
              _TestimonialCarousel(key: ValueKey(_carouselRefreshKey)),
              const SizedBox(height: 28),
              _RoleCard(
                role: 'worker',
                title: 'Gig Worker',
                subtitle: 'Find gigs, earn money, and grow your skills.',
                icon: Icons.work_outline_rounded,
                accentColor: kBlue,
                isSelected: _selectedRole == 'worker',
                onTap: () => _selectRole('worker'),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                role: 'host',
                title: 'Gig Host',
                subtitle: 'Post gigs, find talent, and get things done.',
                icon: Icons.business_center_outlined,
                accentColor: kAmber,
                isSelected: _selectedRole == 'host',
                onTap: () => _selectRole('host'),
              ),
              if (_selectedRole != null) ...[
                const SizedBox(height: 20),
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
                                MaterialPageRoute(builder: (_) => const GigHostScreen()),
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
                      backgroundColor: _selectedRole == 'worker' ? kBlue : kAmber,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
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
                        : Text(
                            _selectedRole == 'worker'
                                ? 'Continue as Gig Worker'
                                : 'Continue as Gig Host',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: kAmber,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      'Giggre Updates',
                      style: TextStyle(color: onSurface, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GiggreUpdates(),
                        ),
                      );
                    },
                    child: const Text(
                      "See All",
                      style: TextStyle(color: kBlue, fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ..._updates
              .where((u) => u['sortNumber'] == 1)
              .map((update) => GestureDetector(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: UpdateCard(
                        title: update['title'] as String,
                        date: update['dateUpdated'] as DateTime,
                        category: update['category'] as String,
                        description: update['body'] as String,
                      ),
                    ),
              )),
               const SizedBox(height: 16),
               Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? Color(0xFF1E1E2C) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: Padding(padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset('assets/images/logo.png', width: 94, height: 64),
                    Text("The fatest way to find gigs or hire workers near you.", style: const TextStyle(fontSize: 12, color: kSub)),
                    const SizedBox(height: 8),
                    Divider(),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 16,
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => AboutGiggre() as Widget));
                          },
                          child: Text("About", style: const TextStyle(fontSize: 12, color: kBlue)),
                        ),
                         GestureDetector(
                          onTap: () {
                             Navigator.push(context, MaterialPageRoute(builder: (context) => TermsAndConditions() as Widget));
                          },
                          child: Text("Term", style: const TextStyle(fontSize: 12, color: kBlue)),
                        ),
                         GestureDetector(
                          onTap: () {
                             Navigator.push(context, MaterialPageRoute(builder: (context) => PrivacyPolicy() as Widget));
                          },
                          child: Text("Privacy", style: const TextStyle(fontSize: 12, color: kBlue)),
                        ),
                         GestureDetector(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => HelpFaq() as Widget));
                          },
                          child: Text("Help/FAQ", style: const TextStyle(fontSize: 12, color: kBlue)),
                        ),
                         GestureDetector(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => ContactUs() as Widget));
                          },
                          child: Text("Contact Us", style: const TextStyle(fontSize: 12, color: kBlue)),
                        )
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text("Copyright © $currentYear Giggre. All rights reserved.", style: const TextStyle(fontSize: 12, color: kSub)),
                  ],
                ),
                )
               )
            ],
          ),
        ),
      ),
      )
    );
  }
}

//GIGGRE MENU
class _GiggreMenu extends StatelessWidget {
  const _GiggreMenu({super.key});

  static final List<Map<String, dynamic>> gigMenuData = [
    {'title': 'About Giggre', 'icon': Icons.info, 'screen': AboutGiggre()},
    {'title': 'Terms & Conditions', 'icon': Icons.description, 'screen': TermsAndConditions()},
    {'title': 'Privacy Policy', 'icon': Icons.privacy_tip, 'screen': PrivacyPolicy()},
    {'title': 'Help/FAQ', 'icon': Icons.help, 'screen': HelpFaq()},
    {'title': 'Contact Us', 'icon': Icons.contact_support, 'screen': ContactUs()},
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
        final iconBg = isDark ? const Color(0xFF001B52) : const Color(0xFFEBF0FB);
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
                    Text(
                      "Version 1.0.0.0.0.0",
                      style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "The fastest way to find jobs or hire workers near you",
                      style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 10),
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
                          Navigator.push(context, MaterialPageRoute(builder: (context) => item['screen'] as Widget));
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
                                  child: Icon(item['icon'] as IconData, color: kBlue),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  item['title'] as String,
                                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                                ),
                              ],
                            ),
                            Icon(Icons.chevron_right, color: isDark ? Colors.white : Colors.black),
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
//  Testimonial Carousel
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

class _UpdateItem {
  final String title;
  final String body;
  final String category;
  final int sortNumber;
  final DateTime? dateCreated;

  const _UpdateItem({
    required this.title,
    required this.body,
    required this.category,
    required this.sortNumber,
    this.dateCreated,
  });

  factory _UpdateItem.fromMap(Map<String, dynamic> data) {
    return _UpdateItem(
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      category: data['category'] as String? ?? '',
      sortNumber: (data['sortNumber'] as num?)?.toInt() ?? 0,
      dateCreated: data['dateCreated'] != null
          ? (data['dateCreated'] as Timestamp).toDate()
          : null,
    );
  }

  String get formattedDate {
    if (dateCreated == null) return '';
    return '${dateCreated!.month.toString().padLeft(2, '0')}/${dateCreated!.day.toString().padLeft(2, '0')}/${dateCreated!.year}';
  }

  IconData get icon {
    switch (category.toLowerCase()) {
      case 'announcement':
        return Icons.campaign;
      case 'feature':
        return Icons.star;
      case 'bug fix':
        return Icons.bug_report;
      case 'improvement':
        return Icons.trending_up;
      default:
        return Icons.update;
    }
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
            color: kCard,
            child: const Center(
              child: CircularProgressIndicator(color: kBlue, strokeWidth: 2),
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
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_slides.length, (i) {
            final active = i == _current;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active ? kBlue : kSub.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
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
            color: kCard,
            child: const Center(
              child: CircularProgressIndicator(color: kBlue, strokeWidth: 2),
            ),
          ),
          errorWidget: (context, url, error) => Container(color: kCard),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Role Card
// ─────────────────────────────────────────────
class _RoleCard extends StatelessWidget {
  final String role;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.role,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final borderColor = Theme.of(context).dividerColor;
    final titleColor = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withValues(alpha: 0.12) : cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accentColor : borderColor,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accentColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? accentColor : titleColor,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: kSub, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedOpacity(
              opacity: isSelected ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}