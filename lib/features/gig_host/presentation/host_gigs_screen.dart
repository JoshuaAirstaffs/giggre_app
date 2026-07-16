import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_colors.dart';
import 'widgets/host_gig_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Full Gigs Screen — filterable, paginated
// ─────────────────────────────────────────────────────────────────────────────
class HostGigsScreen extends StatefulWidget {
  final String uid;
  // True when hosted as the "My gigs" tab root inside HostShell — suppresses
  // the AppBar's back arrow since there's no dashboard-level route to pop to.
  final bool isTabRoot;
  const HostGigsScreen({
    super.key,
    required this.uid,
    this.isTabRoot = false,
  });

  @override
  State<HostGigsScreen> createState() => _HostGigsScreenState();
}

class _HostGigsScreenState extends State<HostGigsScreen> {
  String _typeFilter = 'all';
  String _statusFilter = 'all';
  List<Map<String, dynamic>> _quick = [], _open = [], _offered = [];
  bool _loading = true;
  late StreamSubscription _quickSub, _openSub, _offeredSub;

  static const _pageSize = 5;
  int _visibleCount = _pageSize;

  static const _activeStatuses = [
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
    final db = FirebaseFirestore.instance;

    void onErr(Object e) {
      debugPrint('[HostGigsScreen] stream error: $e');
      if (mounted) setState(() => _loading = false);
    }

    _quickSub = db
        .collection('quick_gigs')
        .where('hostId', isEqualTo: widget.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (s) => setState(() {
            _quick = s.docs.map((d) {
              final m = Map<String, dynamic>.from(d.data());
              m['gigType'] = m['gigType'] ?? 'quick';
              m['docId'] = d.id;
              return m;
            }).toList();
            _loading = false;
          }),
          onError: onErr,
        );

    _openSub = db
        .collection('open_gigs')
        .where('hostId', isEqualTo: widget.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (s) => setState(() {
            _open = s.docs.map((d) {
              final m = Map<String, dynamic>.from(d.data());
              m['gigType'] = m['gigType'] ?? 'open';
              m['docId'] = d.id;
              return m;
            }).toList();
            _loading = false;
          }),
          onError: onErr,
        );

    _offeredSub = db
        .collection('offered_gigs')
        .where('hostId', isEqualTo: widget.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (s) => setState(() {
            _offered = s.docs.map((d) {
              final m = Map<String, dynamic>.from(d.data());
              m['gigType'] = m['gigType'] ?? 'offered';
              m['docId'] = d.id;
              return m;
            }).toList();
            _loading = false;
          }),
          onError: onErr,
        );
  }

  @override
  void dispose() {
    _quickSub.cancel();
    _openSub.cancel();
    _offeredSub.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    List<Map<String, dynamic>> all;
    switch (_typeFilter) {
      case 'quick':
        all = List.from(_quick);
        break;
      case 'open':
        all = List.from(_open);
        break;
      case 'offered':
        all = List.from(_offered);
        break;
      default:
        all = [..._quick, ..._open, ..._offered];
    }

    if (_statusFilter == 'all') {
      // no-op — "All Statuses" means all, including completed/cancelled.
    } else if (_statusFilter == 'active') {
      all = all
          .where((d) => _activeStatuses.contains(d['status'] as String? ?? ''))
          .toList();
    } else {
      all = all
          .where((d) => (d['status'] as String? ?? '') == _statusFilter)
          .toList();
    }

    all.sort((a, b) {
      final aTs = a['createdAt'] as Timestamp?;
      final bTs = b['createdAt'] as Timestamp?;
      if (aTs == null || bTs == null) return 0;
      return bTs.toDate().compareTo(aTs.toDate());
    });
    return all;
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        automaticallyImplyLeading: !widget.isTabRoot,
        leading: widget.isTabRoot
            ? null
            : IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: onSurface,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
        title: Text(
          'My Gigs',
          style: TextStyle(
            color: onSurface,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: kAmber, strokeWidth: 2),
            )
          : Column(
              children: [
                // ── Stat cards (moved here from the dashboard) ───
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _StatsRow(uid: widget.uid),
                ),
                const SizedBox(height: 12),

                // ── Filter dropdowns ─────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: GigDropdown(
                          value: _typeFilter,
                          items: const [
                            ('all', 'All Types'),
                            ('quick', 'Quick Gig'),
                            ('open', 'Open Gig'),
                            ('offered', 'Offered Gig'),
                          ],
                          onChanged: (v) => setState(() {
                            _typeFilter = v;
                            _visibleCount = _pageSize;
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GigDropdown(
                          value: _statusFilter,
                          items: const [
                            ('all', 'All Statuses'),
                            ('active', 'Active'),
                            ('scanning', 'Scanning'),
                            ('no_worker', 'No Worker'),
                            ('completed', 'Completed'),
                            ('cancelled', 'Cancelled'),
                          ],
                          onChanged: (v) => setState(() {
                            _statusFilter = v;
                            _visibleCount = _pageSize;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Gig list ─────────────────────────────────────
                Expanded(
                  child: filtered.isEmpty
                      ? _EmptyGigsPlaceholder(
                          typeFilter: _typeFilter,
                          statusFilter: _statusFilter,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: _visibleCount < filtered.length
                              ? _visibleCount + 1
                              : filtered.length,
                          itemBuilder: (ctx, i) {
                            if (i == _visibleCount) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: OutlinedButton(
                                  onPressed: () => setState(
                                    () => _visibleCount += _pageSize,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: kAmber,
                                    side: BorderSide(
                                      color: kAmber.withValues(alpha: 0.5),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                  child: Text(
                                    'Load more (${filtered.length - _visibleCount} remaining)',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              );
                            }
                            return HostGigCard(data: filtered[i]);
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Stats Row — moved here from the host dashboard, which now leads with the
//  new-applicants summary card instead.
// ─────────────────────────────────────────────────────────────────────────────
class _StatsRow extends StatefulWidget {
  final String uid;
  const _StatsRow({required this.uid});

  @override
  State<_StatsRow> createState() => _StatsRowState();
}

class _StatsRowState extends State<_StatsRow> {
  int _total = 0, _active = 0, _done = 0;
  List<Map> _quick = [], _open = [], _offered = [];
  StreamSubscription? _quickSub, _openSub, _offeredSub;

  static bool _isActive(Map d) {
    final s = d['status'] as String? ?? '';
    if (s == 'completed' || s == 'cancelled' || s.isEmpty) return false;
    final assignedWorker = d['assignedWorkerId'] as String?;
    return assignedWorker != null && assignedWorker.isNotEmpty;
  }

  void _recompute() {
    final all = [..._quick, ..._open, ..._offered];
    setState(() {
      _total = all.length;
      _active = all.where((d) => _isActive(d)).length;
      _done = all.where((d) => d['status'] == 'completed').length;
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.uid.isEmpty) return;
    final db = FirebaseFirestore.instance;
    void onErr(Object e) {
      if (FirebaseAuth.instance.currentUser == null) return;
      debugPrint('[_StatsRow] stream error: $e');
    }

    _quickSub = db.collection('quick_gigs').where('hostId', isEqualTo: widget.uid).snapshots().listen((s) {
      _quick = s.docs.map((d) => d.data() as Map).toList();
      _recompute();
    }, onError: onErr);
    _openSub = db.collection('open_gigs').where('hostId', isEqualTo: widget.uid).snapshots().listen((s) {
      _open = s.docs.map((d) => d.data() as Map).toList();
      _recompute();
    }, onError: onErr);
    _offeredSub = db.collection('offered_gigs').where('hostId', isEqualTo: widget.uid).snapshots().listen((s) {
      _offered = s.docs.map((d) => d.data() as Map).toList();
      _recompute();
    }, onError: onErr);
  }

  @override
  void dispose() {
    _quickSub?.cancel();
    _openSub?.cancel();
    _offeredSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _StatCard(label: 'Posted', value: _total, color: kAmber)),
          const SizedBox(width: 10),
          Expanded(child: _StatCard(label: 'Active', value: _active, color: const Color(0xFF22C55E))),
          const SizedBox(width: 10),
          Expanded(child: _StatCard(label: 'Done', value: _done, color: kBlue)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$value',
            style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: kSub, fontSize: 12)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Dropdown filter widget
// ─────────────────────────────────────────────────────────────────────────────
class GigDropdown extends StatelessWidget {
  final String value;
  final List<(String, String)> items;
  final ValueChanged<String> onChanged;

  const GigDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final divider = Theme.of(context).dividerColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isActive = value != 'all';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? kAmber.withValues(alpha: 0.07) : cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? kAmber.withValues(alpha: 0.5) : divider,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: cardColor,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: isActive ? kAmber : kSub,
            size: 18,
          ),
          style: TextStyle(
            color: isActive ? kAmber : onSurface,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e.$1,
                  child: Text(
                    e.$2,
                    style: TextStyle(
                      color: e.$1 == value ? kAmber : onSurface,
                      fontSize: 13,
                      fontWeight: e.$1 == value
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Empty state
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyGigsPlaceholder extends StatelessWidget {
  final String typeFilter;
  final String statusFilter;
  const _EmptyGigsPlaceholder({
    required this.typeFilter,
    required this.statusFilter,
  });

  @override
  Widget build(BuildContext context) {
    final typeLabel = typeFilter == 'all' ? '' : '$typeFilter ';
    final statusLabel = statusFilter == 'all' ? '' : '$statusFilter ';
    final label = '$statusLabel${typeLabel}gigs';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: kAmber.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.inbox_outlined, color: kAmber, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              'No $label found',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try adjusting your filters.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kSub, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
