import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/app_colors.dart';
import 'skill_request_form.dart';

class ToolchestSheet extends StatefulWidget {
  final String uid;

  const ToolchestSheet({super.key, required this.uid});

  static void show(BuildContext context, String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ToolchestSheet(uid: uid),
    );
  }

  @override
  State<ToolchestSheet> createState() => _ToolchestSheetState();
}

class _ToolchestSheetState extends State<ToolchestSheet>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  Map<String, int> _skillsXP = {};
  List<QueryDocumentSnapshot> _requests = [];
  List<Map<String, dynamic>> _availableSkills = [];
  StreamSubscription? _userSub;
  StreamSubscription? _requestSub;
  StreamSubscription? _skillsSub;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _listenToUserSkills();
    _listenToRequests();
    _listenToAvailableSkills();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _userSub?.cancel();
    _requestSub?.cancel();
    _skillsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _listenToUserSkills() {
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final raw = snap.data()?['skillsXP'] as Map<String, dynamic>? ?? {};
      setState(() {
        _skillsXP = raw.map(
          (k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0),
        );
      });
    });
  }

  void _listenToRequests() {
    _requestSub = FirebaseFirestore.instance
        .collection('skill_requests')
        .where('userId', isEqualTo: widget.uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final sorted = snap.docs.toList()
        ..sort((a, b) {
          final aTs = a.data()['createdAt'] as Timestamp?;
          final bTs = b.data()['createdAt'] as Timestamp?;
          if (aTs == null && bTs == null) return 0;
          if (aTs == null) return 1;
          if (bTs == null) return -1;
          return bTs.compareTo(aTs);
        });
      setState(() => _requests = sorted);
      _syncApprovedSkillsToXP(sorted);
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _requests = []);
    });
  }

  Future<void> _syncApprovedSkillsToXP(
      List<QueryDocumentSnapshot> requests) async {
    final approvedNames = requests
        .where((doc) =>
            (doc.data() as Map<String, dynamic>)['status'] == 'approved')
        .map((doc) =>
            (doc.data() as Map<String, dynamic>)['skillName'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toSet();

    if (approvedNames.isEmpty) return;

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid);

    await FirebaseFirestore.instance.runTransaction((txn) async {
      final userDoc = await txn.get(userRef);
      final existingXP =
          userDoc.data()?['skillsXP'] as Map<String, dynamic>? ?? {};

      final updates = <String, dynamic>{};
      for (final name in approvedNames) {
        final alreadyPresent = existingXP.keys
            .any((k) => k.toLowerCase().trim() == name.toLowerCase().trim());
        if (!alreadyPresent) {
          updates['skillsXP.$name'] = 1;
        }
      }

      if (updates.isNotEmpty) {
        txn.update(userRef, updates);
      }
    });
  }

  void _listenToAvailableSkills() {
    _skillsSub = FirebaseFirestore.instance
        .collection('skills')
        .orderBy('name')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _availableSkills = snap.docs.map((d) {
          final data = d.data();
          return {
            ...data,
            'skillId': data['skillId'] ?? d.id,
            'skillDocId': d.id,
          };
        }).toList();
      });
    }, onError: (_) {});
  }

  // Returns the most recent non-rejected request status for a given skill name,
  // or empty string if no active request exists.
  String _requestStatusForSkill(String skillName) {
    final key = skillName.toLowerCase().trim();
    for (final doc in _requests) {
      final data = doc.data() as Map<String, dynamic>;
      final reqSkill = (data['skillName'] as String? ?? '').toLowerCase().trim();
      if (reqSkill == key) {
        return data['status'] as String? ?? 'pending';
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.88,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Drag handle ──────────────────────────────────────────────
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

          // ── Header ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kAmber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.construction_rounded,
                      color: kAmber, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Toolchest',
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Manage your skills & applications',
                      style: TextStyle(color: kSub, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Tab bar ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: kAmber,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.black,
                unselectedLabelColor: kSub,
                labelStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 12),
                padding: const EdgeInsets.all(4),
                dividerColor: Colors.transparent,
                tabs: [
                  const Tab(text: 'My Skills'),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Request',
                            style: TextStyle(fontSize: 12)),
                        if (_requests.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${_requests.length}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Tab(text: 'Apply'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // ── Tab content ──────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMySkillsTab(isDark),
                _buildRequestSkillTab(isDark),
                _buildApplySkillTab(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 1: My Skills ──────────────────────────────────────────────────────
  Widget _buildMySkillsTab(bool isDark) {
    final divider = Theme.of(context).dividerColor;

    // Approved requests whose skill isn't yet in skillsXP
    final approvedPending = _requests
        .where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'] as String? ?? '';
          if (status != 'approved') return false;
          final name = (data['skillName'] as String? ?? '').toLowerCase().trim();
          return !_skillsXP.keys
              .any((k) => k.toLowerCase().trim() == name);
        })
        .map((doc) =>
            (doc.data() as Map<String, dynamic>)['skillName'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();

    final hasAny = _skillsXP.isNotEmpty || approvedPending.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        const Text(
          'YOUR SKILLS',
          style: TextStyle(
            color: kSub,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 10),
        if (!hasAny)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: divider),
            ),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.workspace_premium_outlined,
                      color: kSub, size: 38),
                  SizedBox(height: 12),
                  Text(
                    'No skills awarded yet.',
                    style: TextStyle(
                        color: kSub,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Complete gigs to earn skills from admin.',
                    style: TextStyle(color: kSub, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else ...[
          ..._skillsXP.entries.map(
            (e) => _SkillChip(label: e.key, level: e.value, isDark: isDark),
          ),
          ...approvedPending.map(
            (name) => _SkillChip(
                label: name, level: 0, isDark: isDark, isApproved: true),
          ),
        ],
      ],
    );
  }

  // ── Tab 2: Request a Skill ────────────────────────────────────────────────
  Widget _buildRequestSkillTab(bool isDark) {
    final divider = Theme.of(context).dividerColor;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            children: [
              Row(
                children: [
                  const Text(
                    'MY SKILL REQUESTS',
                    style: TextStyle(
                      color: kSub,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const Spacer(),
                  if (_requests.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: kAmber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_requests.length}',
                        style: const TextStyle(
                            color: kAmber,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (_requests.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: divider),
                  ),
                  child: const Center(
                    child: Column(
                      children: [
                        Icon(Icons.send_outlined, color: kSub, size: 38),
                        SizedBox(height: 12),
                        Text(
                          'No requests yet.',
                          style: TextStyle(
                              color: kSub,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Tap the button below to submit one.',
                          style: TextStyle(color: kSub, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...(_requests.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _SkillRequestCard(data: data, isDark: isDark);
                })),
            ],
          ),
        ),
        // Fixed "New Request" button
        Container(
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(
                top: BorderSide(
                    color:
                        isDark ? kBorder : const Color(0xFFE2E8F0))),
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                SkillRequestForm.push(context);
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New Skill Request',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kAmber,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Tab 3: Apply a Skill ──────────────────────────────────────────────────
  Widget _buildApplySkillTab(bool isDark) {
    final divider = Theme.of(context).dividerColor;

    // Skills the user hasn't been awarded yet
    final unawardedSkills = _availableSkills.where((s) {
      final name = s['name'] as String? ?? '';
      return !_skillsXP.keys
          .any((u) => u.toLowerCase().trim() == name.toLowerCase().trim());
    }).toList();

    // Collect unique categories from unawarded skills
    final categories = unawardedSkills
        .map((s) => s['category'] as String? ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    // Apply search + category filter
    final query = _searchQuery.toLowerCase().trim();
    final applyList = unawardedSkills.where((s) {
      final name = (s['name'] as String? ?? '').toLowerCase();
      final cat = s['category'] as String? ?? '';
      final matchesSearch = query.isEmpty || name.contains(query);
      final matchesCategory =
          _selectedCategory == null || cat == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();

    return Column(
      children: [
        // ── Search + filter bar ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: 'Search skills…',
              hintStyle: const TextStyle(color: kSub, fontSize: 13),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: kSub, size: 18),
              suffixIcon: _searchQuery.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      child: const Icon(Icons.close_rounded,
                          color: kSub, size: 16),
                    )
                  : null,
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        // ── Category chips ──────────────────────────────────────────────
        if (categories.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              children: [
                _CategoryChip(
                  label: 'All',
                  selected: _selectedCategory == null,
                  isDark: isDark,
                  onTap: () => setState(() => _selectedCategory = null),
                ),
                ...categories.map((cat) => _CategoryChip(
                      label: cat,
                      selected: _selectedCategory == cat,
                      isDark: isDark,
                      onTap: () => setState(() => _selectedCategory =
                          _selectedCategory == cat ? null : cat),
                    )),
              ],
            ),
          ),

        const SizedBox(height: 8),

        // ── Results ────────────────────────────────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Row(
                children: [
                  const Text(
                    'AVAILABLE SKILLS',
                    style: TextStyle(
                      color: kSub,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                    ),
                  ),
                  if (applyList.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${applyList.length}',
                      style: const TextStyle(color: kSub, fontSize: 11),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              if (applyList.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: divider),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          query.isNotEmpty || _selectedCategory != null
                              ? Icons.search_off_rounded
                              : _availableSkills.isEmpty
                                  ? Icons.bolt_outlined
                                  : Icons.check_circle_outline_rounded,
                          color: kSub,
                          size: 38,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          query.isNotEmpty || _selectedCategory != null
                              ? 'No skills match your search.'
                              : _availableSkills.isEmpty
                                  ? 'No skills available yet.'
                                  : 'You have all available skills!',
                          style: const TextStyle(
                              color: kSub,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          query.isNotEmpty || _selectedCategory != null
                              ? 'Try a different search or category.'
                              : _availableSkills.isEmpty
                                  ? 'Check back later as admin adds skills.'
                                  : 'All listed skills have been awarded to you.',
                          style: const TextStyle(color: kSub, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...applyList.map((skill) {
                  final name = skill['name'] as String? ?? '';
                  final category = skill['category'] as String? ?? '';
                  final description = skill['description'] as String? ?? '';
                  final reqStatus = _requestStatusForSkill(name);
                  return _ApplySkillCard(
                    skillName: name,
                    category: category,
                    description: description,
                    requestStatus: reqStatus,
                    isDark: isDark,
                    onApply: () {
                      Navigator.pop(context);
                      SkillRequestForm.push(context,
                          initialSkillName: name,
                          initialCategory:
                              category.isNotEmpty ? category : null,
                          initialSkillId: skill['skillId'] as String?,
                          initialSkillDocId: skill['skillDocId'] as String?);
                    },
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Category filter chip
// ─────────────────────────────────────────────────────────────────────────────
class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? kAmber
              : isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? kAmber : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.black
                : kSub,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Apply skill card
// ─────────────────────────────────────────────────────────────────────────────
class _ApplySkillCard extends StatelessWidget {
  final String skillName;
  final String category;
  final String description;
  final String requestStatus; // '' = no request, else status value
  final bool isDark;
  final VoidCallback onApply;

  const _ApplySkillCard({
    required this.skillName,
    required this.category,
    required this.description,
    required this.requestStatus,
    required this.isDark,
    required this.onApply,
  });

  static ({Color bg, Color text, IconData icon, String label})
      _statusBadge(String status) {
    return switch (status) {
      'pending' => (
          bg: kAmber,
          text: Colors.black,
          icon: Icons.hourglass_empty_rounded,
          label: 'Pending',
        ),
      'under_review' => (
          bg: kBlue,
          text: Colors.white,
          icon: Icons.manage_search_rounded,
          label: 'Under Review',
        ),
      'need_more_info' => (
          bg: Colors.orangeAccent,
          text: Colors.black,
          icon: Icons.info_outline_rounded,
          label: 'Need Info',
        ),
      'approved' => (
          bg: const Color(0xFF22C55E),
          text: Colors.white,
          icon: Icons.check_circle_rounded,
          label: 'Approved',
        ),
      _ => (
          bg: kSub,
          text: Colors.white,
          icon: Icons.help_outline_rounded,
          label: status,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final hasActiveRequest =
        requestStatus.isNotEmpty && requestStatus != 'rejected';
    final badge =
        hasActiveRequest ? _statusBadge(requestStatus) : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: badge != null
              ? badge.bg.withValues(alpha: 0.4)
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: kAmber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.construction_rounded,
                color: kAmber, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  skillName,
                  style: TextStyle(
                      color: onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                if (category.isNotEmpty || description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    category.isNotEmpty && description.isNotEmpty
                        ? '$category · $description'
                        : category.isNotEmpty
                            ? category
                            : description,
                    style:
                        const TextStyle(color: kSub, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (badge != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: badge.bg.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: badge.bg.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(badge.icon, color: badge.bg, size: 11),
                  const SizedBox(width: 4),
                  Text(badge.label,
                      style: TextStyle(
                          color: badge.bg,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            )
          else
            GestureDetector(
              onTap: onApply,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: kAmber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: kAmber.withValues(alpha: 0.35)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.send_rounded, color: kAmber, size: 12),
                    SizedBox(width: 4),
                    Text('Apply',
                        style: TextStyle(
                            color: kAmber,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Skill request card
// ─────────────────────────────────────────────────────────────────────────────
class _SkillRequestCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isDark;

  const _SkillRequestCard({required this.data, required this.isDark});

  static ({Color bg, Color text, IconData icon}) _statusStyle(String status) {
    return switch (status) {
      'approved' => (
          bg: const Color(0xFF22C55E),
          text: Colors.white,
          icon: Icons.check_circle_rounded,
        ),
      'rejected' => (
          bg: Colors.redAccent,
          text: Colors.white,
          icon: Icons.cancel_rounded,
        ),
      'under_review' => (
          bg: kBlue,
          text: Colors.white,
          icon: Icons.manage_search_rounded,
        ),
      'need_more_info' => (
          bg: Colors.orangeAccent,
          text: Colors.black,
          icon: Icons.info_outline_rounded,
        ),
      _ => (
          bg: kAmber,
          text: Colors.black,
          icon: Icons.hourglass_empty_rounded,
        ),
    };
  }

  static String _statusLabel(String status) => switch (status) {
        'approved' => 'Approved',
        'rejected' => 'Rejected',
        'under_review' => 'Under Review',
        'need_more_info' => 'Need More Info',
        _ => 'Pending',
      };

  @override
  Widget build(BuildContext context) {
    final skillName = data['skillName'] as String? ?? '';
    final category = data['skillCategory'] as String? ?? '';
    final status = data['status'] as String? ?? 'pending';
    final adminRemarks = data['adminRemarks'] as String? ?? '';
    final createdAt = data['createdAt'] as Timestamp?;
    final proofCount = (data['proofUrls'] as List<dynamic>?)?.length ?? 0;
    final level = data['experienceLevel'] as String? ?? '';

    final style = _statusStyle(status);
    final label = _statusLabel(status);

    String dateStr = '';
    if (createdAt != null) {
      final d = createdAt.toDate().toLocal();
      dateStr = '${d.day}/${d.month}/${d.year}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F172A)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: style.bg.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(skillName,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: style.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(style.icon, color: style.text, size: 11),
                    const SizedBox(width: 4),
                    Text(label,
                        style: TextStyle(
                            color: style.text,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (category.isNotEmpty)
                _MetaTag(Icons.category_outlined, category),
              if (level.isNotEmpty)
                _MetaTag(Icons.trending_up_rounded, level),
              if (proofCount > 0)
                _MetaTag(Icons.attach_file_rounded,
                    '$proofCount file${proofCount > 1 ? 's' : ''}'),
              if (dateStr.isNotEmpty)
                _MetaTag(Icons.calendar_today_outlined, dateStr),
            ],
          ),
          if (adminRemarks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: style.bg.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: style.bg.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.admin_panel_settings_outlined,
                      color: style.bg, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      adminRemarks,
                      style: TextStyle(
                          color: style.bg, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaTag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaTag(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: kSub, size: 11),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(color: kSub, fontSize: 11)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Read-only skill chip
// ─────────────────────────────────────────────────────────────────────────────
class _SkillChip extends StatelessWidget {
  final String label;
  final int level;
  final bool isDark;
  final bool isApproved;

  const _SkillChip({
    required this.label,
    required this.level,
    required this.isDark,
    this.isApproved = false,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kAmber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: kAmber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.construction_rounded,
                color: kAmber, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isApproved)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: Color(0xFF22C55E), size: 11),
                  SizedBox(width: 4),
                  Text(
                    'Approved',
                    style: TextStyle(
                      color: Color(0xFF22C55E),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: kAmber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kAmber.withValues(alpha: 0.4)),
              ),
              child: Text(
                'Lvl $level',
                style: const TextStyle(
                  color: kAmber,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
