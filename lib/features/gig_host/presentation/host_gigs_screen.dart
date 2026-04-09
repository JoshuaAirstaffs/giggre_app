import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_colors.dart';
import '../services/quick_gig_matching_service.dart';
import 'widgets/gig_detail_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Full Gigs Screen — filterable, paginated
// ─────────────────────────────────────────────────────────────────────────────
class HostGigsScreen extends StatefulWidget {
  final String uid;
  const HostGigsScreen({super.key, required this.uid});

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
    'in_progress', 'navigating', 'arrived', 'working', 'task_complete', 'payment',
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
        .listen((s) => setState(() {
              _quick = s.docs.map((d) {
                final m = Map<String, dynamic>.from(d.data());
                m['gigType'] = m['gigType'] ?? 'quick';
                m['docId'] = d.id;
                return m;
              }).toList();
              _loading = false;
            }), onError: onErr);

    _openSub = db
        .collection('open_gigs')
        .where('hostId', isEqualTo: widget.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((s) => setState(() {
              _open = s.docs.map((d) {
                final m = Map<String, dynamic>.from(d.data());
                m['gigType'] = m['gigType'] ?? 'open';
                m['docId'] = d.id;
                return m;
              }).toList();
              _loading = false;
            }), onError: onErr);

    _offeredSub = db
        .collection('offered_gigs')
        .where('hostId', isEqualTo: widget.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((s) => setState(() {
              _offered = s.docs.map((d) {
                final m = Map<String, dynamic>.from(d.data());
                m['gigType'] = m['gigType'] ?? 'offered';
                m['docId'] = d.id;
                return m;
              }).toList();
              _loading = false;
            }), onError: onErr);
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

    if (_statusFilter != 'all') {
      if (_statusFilter == 'active') {
        all = all
            .where((d) =>
                _activeStatuses.contains(d['status'] as String? ?? ''))
            .toList();
      } else {
        all = all
            .where((d) => (d['status'] as String? ?? '') == _statusFilter)
            .toList();
      }
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
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: onSurface, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'My Gigs',
          style: TextStyle(
              color: onSurface,
              fontSize: 17,
              fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: kAmber, strokeWidth: 2))
          : Column(
              children: [
                // ── Filter dropdowns ─────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                            ('completed', 'Completed'),
                            ('cancelled', 'Cancelled'),
                            ('no_worker', 'No Worker'),
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
                          statusFilter: _statusFilter)
                      : ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: _visibleCount < filtered.length
                              ? _visibleCount + 1
                              : filtered.length,
                          itemBuilder: (ctx, i) {
                            if (i == _visibleCount) {
                              return Padding(
                                padding:
                                    const EdgeInsets.only(top: 4),
                                child: OutlinedButton(
                                  onPressed: () => setState(
                                      () => _visibleCount += _pageSize),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: kAmber,
                                    side: BorderSide(
                                        color: kAmber.withValues(
                                            alpha: 0.5)),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                  child: Text(
                                    'Load more (${filtered.length - _visibleCount} remaining)',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              );
                            }
                            return GigTile(data: filtered[i]);
                          },
                        ),
                ),
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
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: isActive ? kAmber : kSub, size: 18),
          style: TextStyle(
            color: isActive ? kAmber : onSurface,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
          items: items
              .map((e) => DropdownMenuItem(
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
                  ))
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
              child:
                  const Icon(Icons.inbox_outlined, color: kAmber, size: 30),
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

// ─────────────────────────────────────────────────────────────────────────────
//  Gig Tile
// ─────────────────────────────────────────────────────────────────────────────
class GigTile extends StatefulWidget {
  final Map<String, dynamic> data;
  const GigTile({super.key, required this.data});

  @override
  State<GigTile> createState() => _GigTileState();
}

class _GigTileState extends State<GigTile> {
  static String _collectionFor(String gigType) {
    switch (gigType) {
      case 'open':
        return 'open_gigs';
      case 'offered':
        return 'offered_gigs';
      default:
        return 'quick_gigs';
    }
  }

  void _showDetail() {
    final gigType = widget.data['gigType'] as String? ?? 'quick';
    final docId = widget.data['docId'] as String? ?? '';
    if (docId.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GigDetailSheet(gigId: docId, gigType: gigType),
    );
  }

  Future<void> _confirmCancel() async {
    final gigType = widget.data['gigType'] as String? ?? 'quick';
    final docId = widget.data['docId'] as String? ?? '';
    if (docId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Cancel Gig',
            style:
                TextStyle(color: Theme.of(ctx).colorScheme.onSurface)),
        content: const Text(
            'Mark this gig as cancelled? Workers will no longer see it.',
            style: TextStyle(color: kSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No', style: TextStyle(color: kSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Gig',
                style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance
        .collection(_collectionFor(gigType))
        .doc(docId)
        .update({'status': 'cancelled'});
    messenger.showSnackBar(const SnackBar(
      content: Text('Gig cancelled'),
      backgroundColor: Colors.orange,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _confirmDelete() async {
    final gigType = widget.data['gigType'] as String? ?? 'quick';
    final docId = widget.data['docId'] as String? ?? '';
    if (docId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Gig',
            style:
                TextStyle(color: Theme.of(ctx).colorScheme.onSurface)),
        content: const Text(
            'This will permanently remove the gig. This cannot be undone.',
            style: TextStyle(color: kSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep', style: TextStyle(color: kSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    await FirebaseFirestore.instance
        .collection(_collectionFor(gigType))
        .doc(docId)
        .delete();
    messenger.showSnackBar(const SnackBar(
      content: Text('Gig deleted'),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _dispatchGig() async {
    final gigType = widget.data['gigType'] as String? ?? 'quick';
    if (gigType != 'quick') return;
    final docId = widget.data['docId'] as String? ?? '';
    if (docId.isEmpty) return;
    final location = widget.data['location'] as GeoPoint?;
    if (location == null) return;

    await FirebaseFirestore.instance
        .collection('quick_gigs')
        .doc(docId)
        .update({
      'status': 'scanning',
      'assignedWorkerId': null,
      'assignedWorkerName': null,
      'searchStartedAt': FieldValue.serverTimestamp(),
    });

    QuickGigMatchingService.startAutoSearch(
        gigId: docId, gigLocation: location);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Searching for available workers...'),
          backgroundColor: kAmber,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'scanning':
        return kAmber;
      case 'in_progress':
        return kBlue;
      case 'accepted':
        return const Color(0xFF22C55E);
      case 'open':
        return const Color(0xFF22C55E);
      case 'offered':
        return const Color(0xFF8B5CF6);
      case 'active':
        return const Color(0xFF22C55E);
      case 'assigned':
        return kBlue;
      case 'no_worker':
        return Colors.redAccent;
      case 'completed':
        return const Color(0xFF22C55E);
      case 'cancelled':
        return Colors.redAccent;
      default:
        return kSub;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'scanning':
        return 'SCANNING';
      case 'in_progress':
        return 'IN PROGRESS';
      case 'accepted':
        return 'ACCEPTED';
      case 'no_worker':
        return 'NO WORKER';
      case 'completed':
        return 'COMPLETED';
      case 'cancelled':
        return 'CANCELLED';
      default:
        return status.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final gigType = data['gigType'] as String? ?? 'quick';
    final status = data['status'] as String? ?? 'scanning';
    final statusColor = _statusColor(status);
    final titleColor = Theme.of(context).colorScheme.onSurface;
    final isClosed = status == 'cancelled' || status == 'completed';

    final IconData typeIcon;
    final Color typeColor;
    final String typeLabel;
    switch (gigType) {
      case 'open':
        typeIcon = Icons.workspace_premium_outlined;
        typeColor = kBlue;
        typeLabel = 'Open';
        break;
      case 'offered':
        typeIcon = Icons.send_rounded;
        typeColor = const Color(0xFF8B5CF6);
        typeLabel = 'Offered';
        break;
      default:
        typeIcon = Icons.flash_on_rounded;
        typeColor = kAmber;
        typeLabel = 'Quick';
    }

    String subtitle = '';
    if (gigType == 'open') {
      final skills = List<String>.from(data['requiredSkills'] ?? []);
      subtitle = skills.take(2).join(', ');
    } else if (gigType == 'offered') {
      final workerName = data['workerName'] as String? ?? '';
      if (workerName.isNotEmpty) subtitle = '→ $workerName';
    } else {
      final assignedWorkerName = data['assignedWorkerName'] as String?;
      if (status == 'in_progress' &&
          assignedWorkerName != null &&
          assignedWorkerName.isNotEmpty) {
        subtitle = '→ $assignedWorkerName';
      } else if (status == 'no_worker') {
        subtitle = 'No worker found';
      } else {
        subtitle = data['category'] as String? ?? '';
      }
    }

    final createdAt = data['createdAt'] != null
        ? (data['createdAt'] as Timestamp).toDate()
        : DateTime.now();
    final diff = DateTime.now().difference(createdAt);
    final timeAgo = diff.inMinutes < 60
        ? '${diff.inMinutes}m ago'
        : diff.inHours < 24
            ? '${diff.inHours}h ago'
            : '${diff.inDays}d ago';

    return GestureDetector(
      onTap: _showDetail,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            // ── Type icon ──────────────────────────────
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(typeIcon, color: typeColor, size: 22),
            ),
            const SizedBox(width: 12),

            // ── Title + subtitle ───────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          data['title'] as String? ?? 'Untitled Gig',
                          style: TextStyle(
                              color: titleColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          typeLabel,
                          style: TextStyle(
                              color: typeColor,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (subtitle.isNotEmpty) ...[
                        Flexible(
                          child: Text(subtitle,
                              style: const TextStyle(
                                  color: kSub, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const Text(' · ',
                            style:
                                TextStyle(color: kSub, fontSize: 12)),
                      ],
                      Text(
                        '₱${(data['budget'] as num?)?.toStringAsFixed(0) ?? '0'}',
                        style: const TextStyle(
                            color: kAmber,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                      const Text(' · ',
                          style: TextStyle(color: kSub, fontSize: 12)),
                      Text(timeAgo,
                          style: const TextStyle(
                              color: kSub, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // ── Status badge + menu ────────────────────
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 20,
                  width: 20,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_horiz_rounded,
                        color: kSub, size: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    onSelected: (val) {
                      if (val == 'dispatch') _dispatchGig();
                      if (val == 'cancel') _confirmCancel();
                      if (val == 'delete') _confirmDelete();
                    },
                    itemBuilder: (ctx) => [
                      if (!isClosed &&
                          gigType == 'quick' &&
                          (status == 'scanning' ||
                              status == 'no_worker' ||
                              status == 'in_progress'))
                        PopupMenuItem(
                          value: 'dispatch',
                          child: Row(
                            children: [
                              Icon(Icons.send_rounded,
                                  color: kAmber, size: 18),
                              const SizedBox(width: 10),
                              Text('Dispatch',
                                  style: TextStyle(color: kAmber)),
                            ],
                          ),
                        ),
                      if (!isClosed)
                        const PopupMenuItem(
                          value: 'cancel',
                          child: Row(
                            children: [
                              Icon(Icons.cancel_outlined,
                                  color: Colors.orange, size: 18),
                              SizedBox(width: 10),
                              Text('Cancel Gig',
                                  style:
                                      TextStyle(color: Colors.orange)),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded,
                                color: Colors.redAccent, size: 18),
                            SizedBox(width: 10),
                            Text('Delete',
                                style: TextStyle(
                                    color: Colors.redAccent)),
                          ],
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
    );
  }
}
