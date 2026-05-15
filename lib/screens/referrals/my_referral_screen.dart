import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

// ── Tab 1: Referral Code ──────────────────────────────────────────────────────

class _ReferralCodeTab extends StatefulWidget {
  const _ReferralCodeTab({required this.referralMap});
  final List<Map<String, dynamic>> referralMap;

  @override
  State<_ReferralCodeTab> createState() => _ReferralCodeTabState();
}

class _ReferralCodeTabState extends State<_ReferralCodeTab> {
  final _auth = FirebaseAuth.instance;
  bool _isLoading = true;
  String _referralCode = '';
  int _referralsCount = 0;
  int _referralLevel = 0;
  bool _justCopied = false;

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
          _referralsCount =
              (data?['referrals']?['referrals_count'] ?? 0) as int;
          _referralLevel =
              (data?['referrals']?['referral_level'] ?? 0) as int;
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

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _referralCode));
    setState(() => _justCopied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Referral code copied!',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        backgroundColor: const Color(0xFF2E7D32),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _justCopied = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor =
        isDark ? const Color(0xFF90CAF9) : const Color(0xFF2164F3);
    final greenColor =
        isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final surfaceVariant =
        isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF5F5F5);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final isMaxed = _referralsCount >= _milestones.last;
    final activeColor = isMaxed ? greenColor : primaryColor;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Progress Card ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [activeColor, activeColor.withOpacity(0.75)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: activeColor.withOpacity(0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMaxed ? '🐐 Legendary GOAT' : _currentLabel,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_referralsCount referral${_referralsCount == 1 ? '' : 's'} total',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.2),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'L$_referralLevel',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (!isMaxed) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progress to next level',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.75),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${(_progress * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 8,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${_nextMilestone - _referralsCount} more referrals to unlock $_nextLabel',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                ] else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '🎉 You\'ve unlocked all milestones!',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Referral Code Card ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: activeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.vpn_key_rounded,
                          size: 18, color: activeColor),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Your Referral Code',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: surfaceVariant,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: activeColor.withOpacity(0.2),
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          _referralCode.isEmpty ? '—' : _referralCode,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                            color: onSurface,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _referralCode.isEmpty ? null : _copyCode,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _justCopied ? greenColor : activeColor,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: (_justCopied ? greenColor : activeColor)
                                  .withOpacity(0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _justCopied
                              ? const Icon(Icons.check_rounded,
                                  key: ValueKey('check'),
                                  color: Colors.white,
                                  size: 22)
                              : const Icon(Icons.copy_rounded,
                                  key: ValueKey('copy'),
                                  color: Colors.white,
                                  size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Share this code with friends to earn referral rewards.',
                  style: TextStyle(
                    fontSize: 12,
                    color: onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── QR Code Card ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: activeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.qr_code_rounded,
                          size: 18, color: activeColor),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Scan to Share',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_referralCode.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: activeColor.withOpacity(0.15),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: _referralCode,
                      version: QrVersions.auto,
                      size: 180,
                      backgroundColor: Colors.white,
                      eyeStyle: QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: primaryColor,
                      ),
                      dataModuleStyle: QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: primaryColor,
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 180,
                    child: Center(
                      child: Text(
                        'No referral code available',
                        style:
                            TextStyle(color: onSurface.withOpacity(0.4)),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Ask friends to scan this to use your referral code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab 2: People Referred ────────────────────────────────────────────────────

class _PeopleReferredTab extends StatefulWidget {
  const _PeopleReferredTab();

  @override
  State<_PeopleReferredTab> createState() => _PeopleReferredTabState();
}

class _PeopleReferredTabState extends State<_PeopleReferredTab> {
  final _auth = FirebaseAuth.instance;
  final List<Map<String, dynamic>> _referrals = [];
  bool _isLoading = true;
  bool _isFetchingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDoc;

  static const _pageSize = 15;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadMore();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_isFetchingMore &&
          _hasMore) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_isFetchingMore || !_hasMore) return;
    setState(() => _isFetchingMore = true);

    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      Query query = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('referrals_list')
          .orderBy('joined_at', descending: true)
          .limit(_pageSize);

      if (_lastDoc != null) {
        query = query.startAfterDocument(_lastDoc!);
      }

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        setState(() => _hasMore = false);
        return;
      }

      _lastDoc = snapshot.docs.last;

      final newItems = await Future.wait(snapshot.docs.map((doc) async {
        final data = doc.data() as Map<String, dynamic>;

        String isVerified = 'unverified';
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(doc.id)
              .get();
          isVerified = userDoc.data()?['isVerified'] ?? 'unverified';
        } catch (_) {}

        return {
          'name'      : data['name'] ?? 'Unknown',
          'email'     : data['email'] ?? '',
          'joined_at' : data['joined_at'],
          'isVerified': isVerified,
        };
      }));

      setState(() {
        _referrals.addAll(newItems);
        if (snapshot.docs.length < _pageSize) _hasMore = false;
      });
    } catch (e) {
      debugPrint('Error loading referrals: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFetchingMore = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _referrals.clear();
      _lastDoc = null;
      _hasMore = true;
      _isLoading = true;
    });
    await _loadMore();
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return '';
    final dt = (timestamp as Timestamp).toDate();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Color _avatarColor(String name) {
    const colors = [
      Color(0xFF2164F3),
      Color(0xFF7C3AED),
      Color(0xFF0891B2),
      Color(0xFF059669),
      Color(0xFFD97706),
      Color(0xFFDC2626),
    ];
    return colors[name.codeUnits.first % colors.length];
  }

  // ── Verification chip ────────────────────────────────────────
  Widget _verificationChip(String status) {
    late IconData icon;
    late Color color;
    late String label;

    switch (status) {
      case 'verified':
        icon  = Icons.verified_rounded;
        color = const Color(0xFF2164F3);
        label = 'Verified';
        break;
      case 'pending':
        icon  = Icons.hourglass_top_rounded;
        color = const Color(0xFFD97706);
        label = 'Pending';
        break;
      default:
        icon  = Icons.remove_circle_outline_rounded;
        color = const Color(0xFF9E9E9E);
        label = 'Unverified';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final primaryColor =
        isDark ? const Color(0xFF90CAF9) : const Color(0xFF2164F3);
    final onSurface   = Theme.of(context).colorScheme.onSurface;
    final cardColor   = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final bgColor     = Theme.of(context).scaffoldBackgroundColor;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_referrals.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.group_add_rounded,
                  size: 40,
                  color: primaryColor.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'No referrals yet',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Share your referral code with friends\nand they\'ll appear here once they join.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: onSurface.withOpacity(0.45),
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: primaryColor,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // ── Summary header ──────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withOpacity(isDark ? 0.25 : 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.people_rounded,
                                size: 18, color: primaryColor),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_referrals.length}${_hasMore ? '+' : ''}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                              Text(
                                'Total Referred',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: onSurface.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withOpacity(isDark ? 0.25 : 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2164F3).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.verified_rounded,
                                size: 18, color: Color(0xFF2164F3)),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_referrals.where((r) => r['isVerified'] == 'verified').length}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2164F3),
                                ),
                              ),
                              Text(
                                'Verified',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: onSurface.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Section label ────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Text(
                'RECENTLY JOINED',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: onSurface.withOpacity(0.4),
                ),
              ),
            ),
          ),

          // ── List ─────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  // Loading spinner at bottom
                  if (index == _referrals.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final item       = _referrals[index];
                  final name       = item['name'] as String;
                  final email      = item['email'] as String;
                  final date       = _formatDate(item['joined_at']);
                  final isVerified = item['isVerified'] as String;
                  final color      = _avatarColor(name);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withOpacity(isDark ? 0.2 : 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          // ── Avatar ──
                          Stack(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      color,
                                      color.withOpacity(0.7),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    _initials(name),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              // verified dot indicator
                              if (isVerified == 'verified')
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2164F3),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: cardColor,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      size: 8,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),

                          const SizedBox(width: 12),

                          // ── Name + email + chips ──
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                // const SizedBox(height: 2),
                                // Text(
                                //   email,
                                //   style: TextStyle(
                                //     fontSize: 12,
                                //     color: onSurface.withOpacity(0.45),
                                //   ),
                                //   overflow: TextOverflow.ellipsis,
                                // ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    _verificationChip(isVerified),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2E7D32)
                                            .withOpacity(0.1),
                                        borderRadius:
                                            BorderRadius.circular(30),
                                        border: Border.all(
                                          color: const Color(0xFF2E7D32)
                                              .withOpacity(0.25),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.person_add_rounded,
                                            size: 10,
                                            color: Color(0xFF2E7D32),
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Joined',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF2E7D32),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 8),

                          // ── Date ──
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 12,
                                color: onSurface.withOpacity(0.3),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                date,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: onSurface.withOpacity(0.4),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: _referrals.length + (_hasMore ? 1 : 0),
              ),
            ),
          ),
        ],
      ),
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
          _totalReferrals =
              (data?['referrals']?['referrals_count'] ?? 0) as int;
          _currentLevel =
              (data?['referrals']?['referral_level'] ?? 0) as int;
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
    final primaryColor =
        isDark ? const Color(0xFF90CAF9) : const Color(0xFF2164F3);
    final greenColor =
        isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final surfaceVariant =
        isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF5F5F5);
    final outlineColor =
        isDark ? const Color(0xFF444444) : const Color(0xFFE0E0E0);
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
                          _isMaxed
                              ? '🐐 Legendary GOAT'
                              : _currentMilestoneLabel,
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
                if (!_isMaxed) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _levelProgress,
                      minHeight: 8,
                      backgroundColor: Colors.white.withOpacity(0.25),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white),
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
                                    ),
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
                              margin:
                                  const EdgeInsets.symmetric(vertical: 3),
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
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
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