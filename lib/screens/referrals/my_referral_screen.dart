import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:qr_flutter/qr_flutter.dart';
// import 'package:flutter/services.dart';

class MyReferralScreen extends StatefulWidget {
  const MyReferralScreen({super.key});

  @override
  State<MyReferralScreen> createState() => _MyReferralScreenState();
}

class _MyReferralScreenState extends State<MyReferralScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;

  final List<Map<String, dynamic>> referralMap = [
    {'label': '🐣 First Steps', 'referrals': 1, 'level': 1},
    {'label': '🎉 Party of Three', 'referrals': 3, 'level': 2},
    {'label': '🖐️ High Five!', 'referrals': 5, 'level': 3},
    {'label': '🔥 Double Digits', 'referrals': 10, 'level': 4},
    {'label': '🌱 Squad\'s Growing', 'referrals': 20, 'level': 5},
    {'label': '🚀 Trailblazer', 'referrals': 30, 'level': 6},
    {'label': '💪 Fifty & Thriving', 'referrals': 50, 'level': 7},
    {'label': '🎯 Three-Quarter Beast', 'referrals': 75, 'level': 8},
    {'label': '💯 Century Club', 'referrals': 100, 'level': 9},
    {'label': '⭐ Rising Star', 'referrals': 125, 'level': 10},
    {'label': '🏗️ Community Builder', 'referrals': 150, 'level': 11},
    {'label': '🕸️ Web Weaver', 'referrals': 175, 'level': 12},
    {'label': '👑 Double Century King', 'referrals': 200, 'level': 13},
    {'label': '🔗 The Connector', 'referrals': 300, 'level': 14},
    {'label': '⚡ Powerhouse', 'referrals': 350, 'level': 15},
    {'label': '📣 Loud & Proud', 'referrals': 400, 'level': 16},
    {'label': '🧲 Human Magnet', 'referrals': 450, 'level': 17},
    {'label': '🏆 Half-Thousand Hero', 'referrals': 500, 'level': 18},
    {'label': '🌊 Unstoppable Wave', 'referrals': 550, 'level': 19},
    {'label': '🦸 Super Connector', 'referrals': 600, 'level': 20},
    {'label': '🌍 Seven Hundred Strong', 'referrals': 700, 'level': 21},
    {'label': '💎 Elite Recruiter', 'referrals': 800, 'level': 22},
    {'label': '🏁 Final Stretch', 'referrals': 900, 'level': 23},
    {'label': '🐐 Legendary GOAT', 'referrals': 1000, 'level': 24},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor =
        isDark ? const Color(0xFF90CAF9) : const Color(0xFF2164F3);
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: const Text(
          'My Referrals',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController!,
          labelColor: primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: primaryColor,
          indicatorWeight: 2.5,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          tabs: const [
            Tab(text: 'Referral Code'),
            Tab(text: 'My Referrals'),
            Tab(text: 'Roadmap'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _ReferralCodeTab(referralMap: referralMap),
            const _PeopleReferredTab(),
            _ReferralRoadmapTab(referralMap: referralMap),
          ],
        ),
      ),
    );
  }
}

// ── Tab 1: Referral Code (Wireframe/Skeleton) ─────────────────────────────────

class _ReferralCodeTab extends StatelessWidget {
  const _ReferralCodeTab({required this.referralMap});
  final List<Map<String, dynamic>> referralMap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor =
        isDark ? const Color(0xFF90CAF9) : const Color(0xFF2164F3);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final shimmer =
        isDark ? const Color(0xFF2C2C2C) : const Color(0xFFEEEEEE);
    final shimmerDark =
        isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0);

    Widget skeletonBox(double width, double height, {double radius = 8}) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: shimmer,
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    Widget card(Widget child) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // ── Progress Card skeleton ──
          card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  skeletonBox(120, 14),
                  skeletonBox(60, 22, radius: 20),
                ],
              ),
              const SizedBox(height: 14),
              skeletonBox(80, 36),
              const SizedBox(height: 10),
              skeletonBox(double.infinity, 10),
              const SizedBox(height: 8),
              skeletonBox(160, 12),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      skeletonBox(50, 11),
                      const SizedBox(height: 4),
                      skeletonBox(100, 13),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      skeletonBox(30, 11),
                      const SizedBox(height: 4),
                      skeletonBox(100, 13),
                    ],
                  ),
                ],
              ),
            ],
          )),

          const SizedBox(height: 20),

          // ── Referral Code Card skeleton ──
          card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              skeletonBox(140, 14),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                height: 64,
                decoration: BoxDecoration(
                  color: shimmerDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: shimmer, width: 1.5),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                height: 48,
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy_rounded,
                          size: 16, color: primaryColor.withOpacity(0.4)),
                      const SizedBox(width: 6),
                      Text(
                        'Copy Code',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: primaryColor.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          )),

          const SizedBox(height: 20),

          // ── QR Code Card skeleton ──
          card(Column(
            children: [
              skeletonBox(140, 14),
              const SizedBox(height: 16),
              Container(
                width: 204,
                height: 204,
                decoration: BoxDecoration(
                  color: shimmerDark,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    Icons.qr_code_2_rounded,
                    size: 80,
                    color: onSurface.withOpacity(0.1),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              skeletonBox(80, 13),
            ],
          )),

          const SizedBox(height: 20),

          // ── Coming Soon banner ──
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: primaryColor.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.construction_rounded,
                    size: 16, color: primaryColor.withOpacity(0.6)),
                const SizedBox(width: 8),
                Text(
                  'Referral Code feature coming soon',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: primaryColor.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/*
── COMMENTED OUT: _ReferralCodeTabState (restore when feature is ready) ──

class _ReferralCodeTabState extends State<_ReferralCodeTab> {
  final _auth = FirebaseAuth.instance;
  bool _isLoading = true;
  String _referralCode = '';
  int _referralsCount = 0;
  int _referralLevel = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (doc.exists) {
        final data = doc.data();
        setState(() {
          _referralCode = data?['referrals']?['referral_code'] ?? '';
          _referralsCount = (data?['referrals']?['referrals_count'] ?? 0) as int;
          _referralLevel = (data?['referrals']?['referral_level'] ?? 0) as int;
        });
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<int> get _milestones =>
      widget.referralMap.map((e) => e['referrals'] as int).toList();

  int get _nextMilestone {
    for (final m in _milestones) {
      if (_referralsCount < m) return m;
    }
    return _milestones.last;
  }

  int get _prevMilestone {
    int prev = 0;
    for (final m in _milestones) {
      if (_referralsCount < m) return prev;
      prev = m;
    }
    return _milestones.last;
  }

  double get _progress {
    final range = _nextMilestone - _prevMilestone;
    final current = _referralsCount - _prevMilestone;
    if (range <= 0) return 1.0;
    return (current / range).clamp(0.0, 1.0);
  }

  String get _currentLabel {
    String label = widget.referralMap.first['label'] as String;
    for (final m in widget.referralMap) {
      if (_referralsCount >= (m['referrals'] as int)) {
        label = m['label'] as String;
      }
    }
    return label;
  }

  String get _nextLabel {
    for (final m in widget.referralMap) {
      if (_referralsCount < (m['referrals'] as int)) {
        return m['label'] as String;
      }
    }
    return widget.referralMap.last['label'] as String;
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _referralCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Referral code copied!'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? const Color(0xFF90CAF9) : const Color(0xFF2164F3);
    final greenColor = isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final surfaceVariant = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF5F5F5);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final isMaxed = _referralsCount >= _milestones.last;
    // ... full build with Progress Card, Referral Code Card, QR Code Card
  }
}
*/

// ── Tab 2: People Referred ────────────────────────────────────────────────────

class _PeopleReferredTab extends StatelessWidget {
  const _PeopleReferredTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(child: Text('My Referrals')),
    );
  }
}

// ── Tab 3: Referral Roadmap ───────────────────────────────────────────────────

class _ReferralRoadmapTab extends StatefulWidget {
  const _ReferralRoadmapTab({required this.referralMap});
  final List<Map<String, dynamic>> referralMap;

  @override
  State<_ReferralRoadmapTab> createState() => _ReferralRoadmapTabState();
}

class _ReferralRoadmapTabState extends State<_ReferralRoadmapTab> {
  final _auth = FirebaseAuth.instance;
  bool _isLoading = true;
  int _totalReferrals = 0;
  int _currentLevel = 0;

  @override
  void initState() {
    super.initState();
    _loadReferralData();
  }

  Future<void> _loadReferralData() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      final response = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (response.exists) {
        final data = response.data();
        setState(() {
          _totalReferrals = (data?['referrals']?['referrals_count'] ?? 0) as int;
          _currentLevel = (data?['referrals']?['referral_level'] ?? 0) as int;
        });
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _currentMilestoneLabel {
    String label = widget.referralMap.first['label'] as String;
    for (final m in widget.referralMap) {
      if (_currentLevel >= (m['level'] as int)) {
        label = m['label'] as String;
      }
    }
    return label;
  }

  int get _nextMilestoneReferrals {
    for (final m in widget.referralMap) {
      if (_currentLevel < (m['level'] as int)) {
        return m['referrals'] as int;
      }
    }
    return widget.referralMap.last['referrals'] as int;
  }

  int get _prevMilestoneReferrals {
    int prev = 0;
    for (final m in widget.referralMap) {
      if (_currentLevel < (m['level'] as int)) return prev;
      prev = m['referrals'] as int;
    }
    return widget.referralMap.last['referrals'] as int;
  }

  double get _levelProgress {
    final range = _nextMilestoneReferrals - _prevMilestoneReferrals;
    final current = _totalReferrals - _prevMilestoneReferrals;
    if (range <= 0) return 1.0;
    return (current / range).clamp(0.0, 1.0);
  }

  bool get _isMaxed =>
      _currentLevel >= (widget.referralMap.last['level'] as int);

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? const Color(0xFF90CAF9) : const Color(0xFF2164F3);
    final greenColor = isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final surfaceVariant = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF5F5F5);
    final outlineColor = isDark ? const Color(0xFF444444) : const Color(0xFFE0E0E0);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final totalLevels = widget.referralMap.length;
    final unlockedCount = widget.referralMap
        .where((m) => _currentLevel >= (m['level'] as int))
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        children: [
          // ── Hero Header Card ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isMaxed
                    ? [greenColor, greenColor.withOpacity(0.7)]
                    : [primaryColor, primaryColor.withOpacity(0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isMaxed ? '🐐 Legendary GOAT' : _currentMilestoneLabel,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Level $_currentLevel of $totalLevels',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.people_rounded,
                              size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            '$_totalReferrals',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Progress bar
                if (!_isMaxed) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _levelProgress,
                      minHeight: 8,
                      backgroundColor: Colors.white.withOpacity(0.25),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_nextMilestoneReferrals - _totalReferrals} more referrals to next level',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                ] else
                  Text(
                    '🎉 You\'ve unlocked all milestones!',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Stats Row ──
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🏆 Unlocked',
                        style: TextStyle(
                          fontSize: 11,
                          color: onSurface.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$unlockedCount / $totalLevels',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: greenColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🔒 Remaining',
                        style: TextStyle(
                          fontSize: 11,
                          color: onSurface.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${totalLevels - unlockedCount}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Section Label ──
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Milestones',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Roadmap ──
          ...widget.referralMap.asMap().entries.map((entry) {
            final index = entry.key;
            final milestone = entry.value;
            final required = milestone['referrals'] as int;
            final label = milestone['label'] as String;
            final level = milestone['level'] as int;
            final isReached = _currentLevel >= level;
            final isNext = !isReached &&
                (index == 0 ||
                    _currentLevel >=
                        (widget.referralMap[index - 1]['level'] as int));
            final isLast = index == widget.referralMap.length - 1;

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Timeline column ──
                  SizedBox(
                    width: 44,
                    child: Column(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isReached
                                ? greenColor
                                : isNext
                                    ? primaryColor.withOpacity(0.12)
                                    : surfaceVariant,
                            border: Border.all(
                              color: isReached
                                  ? greenColor
                                  : isNext
                                      ? primaryColor
                                      : outlineColor,
                              width: isNext ? 2 : 1.5,
                            ),
                            boxShadow: isReached || isNext
                                ? [
                                    BoxShadow(
                                      color: (isReached
                                              ? greenColor
                                              : primaryColor)
                                          .withOpacity(0.25),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: isReached
                                ? const Icon(Icons.check_rounded,
                                    size: 18, color: Colors.white)
                                : Text(
                                    '$level',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isNext
                                          ? primaryColor
                                          : onSurface.withOpacity(0.35),
                                    ),
                                  ),
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                color: isReached
                                    ? greenColor.withOpacity(0.5)
                                    : outlineColor.withOpacity(0.4),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // ── Milestone card ──
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isReached
                              ? greenColor.withOpacity(0.07)
                              : isNext
                                  ? primaryColor.withOpacity(0.05)
                                  : cardColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isReached
                                ? greenColor.withOpacity(0.35)
                                : isNext
                                    ? primaryColor.withOpacity(0.35)
                                    : outlineColor.withOpacity(0.4),
                            width: isNext ? 1.5 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isReached
                                          ? greenColor
                                          : isNext
                                              ? onSurface
                                              : onSurface.withOpacity(0.35),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.people_outline_rounded,
                                        size: 12,
                                        color: isReached
                                            ? greenColor.withOpacity(0.7)
                                            : onSurface.withOpacity(0.35),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$required referrals',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isReached
                                              ? greenColor.withOpacity(0.7)
                                              : onSurface.withOpacity(0.35),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (isReached)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: greenColor,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  '✓ Unlocked',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            else if (isNext)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: primaryColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: primaryColor.withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  '→ Next',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: primaryColor,
                                  ),
                                ),
                              )
                            else
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 16,
                                color: onSurface.withOpacity(0.25),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}