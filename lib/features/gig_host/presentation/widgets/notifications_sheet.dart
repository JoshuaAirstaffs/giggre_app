import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/app_colors.dart';

// Shows recent gig activity derived from quick_gigs / open_gigs / offered_gigs.
// Items older than [_kWindow] are filtered out; a 60-second timer refreshes
// the list so expired items drop off while the sheet is open.
const _kWindow = Duration(minutes: 30);

class NotificationsSheet extends StatefulWidget {
  const NotificationsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NotificationsSheet(),
    );
  }

  @override
  State<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<NotificationsSheet> {
  final _db = FirebaseFirestore.instance;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _quickGigs = [];
  List<Map<String, dynamic>> _openGigs = [];
  List<Map<String, dynamic>> _offeredGigs = [];
  bool _loading = true;

  StreamSubscription? _quickSub, _openSub, _offeredSub;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _listenGigs();
    // Refresh every 60 s so items age out while the sheet stays open
    _ticker = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _quickSub?.cancel();
    _openSub?.cancel();
    _offeredSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  void _listenGigs() {
    void listen(String col, String gigType,
        void Function(List<Map<String, dynamic>>) onData) {
      _db
          .collection(col)
          .where('hostId', isEqualTo: _uid)
          .snapshots()
          .listen((snap) {
        final list = snap.docs.map((d) {
          final m = Map<String, dynamic>.from(d.data());
          m['gigType'] = gigType;
          return m;
        }).toList();
        onData(list);
        if (mounted) setState(() => _loading = false);
      }, onError: (_) {
        if (mounted) setState(() => _loading = false);
      });
    }

    _quickSub = _db
        .collection('quick_gigs')
        .where('hostId', isEqualTo: _uid)
        .snapshots()
        .listen((snap) {
      _quickGigs = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['gigType'] = 'quick';
        return m;
      }).toList();
      if (mounted) setState(() => _loading = false);
    }, onError: (_) => setState(() => _loading = false));

    _openSub = _db
        .collection('open_gigs')
        .where('hostId', isEqualTo: _uid)
        .snapshots()
        .listen((snap) {
      _openGigs = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['gigType'] = 'open';
        return m;
      }).toList();
      if (mounted) setState(() {});
    });

    _offeredSub = _db
        .collection('offered_gigs')
        .where('hostId', isEqualTo: _uid)
        .snapshots()
        .listen((snap) {
      _offeredGigs = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['gigType'] = 'offered';
        return m;
      }).toList();
      if (mounted) setState(() {});
    });

    // suppress unused warning for the local helper
    listen;
  }

  List<_ActivityItem> get _activities {
    final all = [..._quickGigs, ..._openGigs, ..._offeredGigs];
    final items = <_ActivityItem>[];
    final now = DateTime.now();

    for (final gig in all) {
      final gigTitle = gig['title'] as String? ?? 'Gig';
      final workerName = gig['assignedWorkerName'] as String? ??
          gig['workerName'] as String? ?? 'Worker';
      final gigType = gig['gigType'] as String? ?? 'quick';
      final payMethod = gig['paymentMethod'] as String? ?? 'cash';
      final capitalized =
          payMethod.isNotEmpty ? payMethod[0].toUpperCase() + payMethod.substring(1) : 'Cash';

      void tryAdd(String field, _ActivityType type, String title, String body) {
        final ts = gig[field] as Timestamp?;
        if (ts == null) return;
        final dt = ts.toDate().toLocal();
        if (now.difference(dt) <= _kWindow) {
          items.add(_ActivityItem(
            type: type,
            title: title,
            body: body,
            timestamp: dt,
            gigType: gigType,
          ));
        }
      }

      tryAdd(
        'completedAt',
        _ActivityType.completed,
        '"$gigTitle" Completed',
        'Payment confirmed · $capitalized',
      );
      tryAdd(
        'workCompletedAt',
        _ActivityType.taskComplete,
        'Task Done — Awaiting Confirmation',
        '$workerName finished "$gigTitle"',
      );
      tryAdd(
        'workStartedAt',
        _ActivityType.working,
        '$workerName Started Working',
        'Work in progress on "$gigTitle"',
      );
      tryAdd(
        'arrivedAt',
        _ActivityType.arrived,
        '$workerName Has Arrived',
        'Ready to start work on "$gigTitle"',
      );
      tryAdd(
        'assignedAt',
        _ActivityType.assigned,
        'Worker Assigned',
        '$workerName accepted "$gigTitle"',
      );
    }

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final activities = _activities;

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
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
            // ── Handle ────────────────────────────────────────────────
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

            // ── Header ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: kAmber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.notifications_outlined,
                        color: kAmber, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Activity',
                          style: TextStyle(
                              color: onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Text(
                        activities.isEmpty
                            ? 'No recent activity'
                            : '${activities.length} update${activities.length == 1 ? '' : 's'}',
                        style: TextStyle(
                            color: activities.isEmpty ? kSub : kAmber,
                            fontSize: 12),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Last 30 min',
                        style: TextStyle(
                            color: kSub,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: kBorder),

            // ── Body ──────────────────────────────────────────────────
            if (_loading)
              const Expanded(
                child:
                    Center(child: CircularProgressIndicator(color: kAmber)),
              )
            else if (activities.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_none_rounded,
                          size: 56,
                          color: kSub.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      const Text('All quiet right now',
                          style: TextStyle(
                              color: kSub,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const Text(
                          'Gig movements will appear here',
                          style: TextStyle(color: kSub, fontSize: 12)),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  itemCount: activities.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ActivityTile(
                    item: activities[i],
                    isDark: isDark,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Data model
// ─────────────────────────────────────────────────────────────────────────────
enum _ActivityType { completed, taskComplete, working, arrived, assigned }

class _ActivityItem {
  final _ActivityType type;
  final String title;
  final String body;
  final DateTime timestamp;
  final String gigType;

  const _ActivityItem({
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.gigType,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tile
// ─────────────────────────────────────────────────────────────────────────────
class _ActivityTile extends StatelessWidget {
  final _ActivityItem item;
  final bool isDark;

  const _ActivityTile({required this.item, required this.isDark});

  static ({IconData icon, Color color}) _style(_ActivityType t) {
    switch (t) {
      case _ActivityType.completed:
        return (
          icon: Icons.check_circle_outline_rounded,
          color: const Color(0xFF10B981)
        );
      case _ActivityType.taskComplete:
        return (icon: Icons.task_alt_rounded, color: kBlue);
      case _ActivityType.working:
        return (icon: Icons.construction_rounded, color: kBlue);
      case _ActivityType.arrived:
        return (icon: Icons.where_to_vote_rounded, color: kBlue);
      case _ActivityType.assigned:
        return (icon: Icons.person_add_alt_1_rounded, color: kAmber);
    }
  }

  static Color _typeColor(String gigType) {
    if (gigType == 'open') return kBlue;
    if (gigType == 'offered') return const Color(0xFF8B5CF6);
    return kAmber;
  }

  static String _fmtTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final s = _style(item.type);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final typeColor = _typeColor(item.gigType);
    final typeLabel = item.gigType == 'quick'
        ? 'Quick'
        : item.gigType == 'open'
            ? 'Open'
            : 'Offered';

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark
            ? s.color.withValues(alpha: 0.07)
            : s.color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: s.color.withValues(alpha: 0.3), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: s.color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(s.icon, color: s.color, size: 20),
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(item.title,
                          style: TextStyle(
                              color: onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(_fmtTime(item.timestamp),
                        style: const TextStyle(
                            color: kSub, fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(item.body,
                    style: const TextStyle(
                        color: kSub, fontSize: 12, height: 1.4)),
                const SizedBox(height: 6),
                // Gig type chip
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(typeLabel,
                      style: TextStyle(
                          color: typeColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}