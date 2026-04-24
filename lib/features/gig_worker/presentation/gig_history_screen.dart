import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Gig History Screen — all completed gigs for the current worker
// ─────────────────────────────────────────────────────────────────────────────

class GigHistoryScreen extends StatefulWidget {
  const GigHistoryScreen({super.key});

  @override
  State<GigHistoryScreen> createState() => _GigHistoryScreenState();
}

class _GigHistoryScreenState extends State<GigHistoryScreen> {
  bool _loading = true;
  List<_HistoryItem> _items = [];
  double _totalEarnings = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }

    final results = await Future.wait([
      _fetchCollection('quick_gigs', uid, 'Quick'),
      _fetchCollection('open_gigs', uid, 'Open'),
      _fetchCollection('offered_gigs', uid, 'Offered'),
    ]);

    final all = results.expand((e) => e).toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));

    final total = all.fold<double>(0, (acc, e) => acc + e.budget);

    setState(() {
      _items = all;
      _totalEarnings = total;
      _loading = false;
    });
  }

  Future<List<_HistoryItem>> _fetchCollection(
      String collection, String uid, String type) async {
    final snap = await FirebaseFirestore.instance
        .collection(collection)
        .where('workerId', isEqualTo: uid)
        .where('status', isEqualTo: 'completed')
        .get();

    return snap.docs.map((doc) {
      final d = doc.data();
      final completedAt = (d['completedAt'] as Timestamp?)?.toDate() ??
          (d['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now();
      return _HistoryItem(
        id: doc.id,
        type: type,
        title: d['title'] as String? ?? type,
        address: d['address'] as String? ?? '',
        budget: (d['budget'] as num?)?.toDouble() ?? 0,
        completedAt: completedAt,
        hostName: d['hostName'] as String? ?? '',
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _GigHistoryHeader(
            isDark: isDark,
            totalEarnings: _totalEarnings,
            gigCount: _items.length,
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kBlue))
                : _items.isEmpty
                    ? _EmptyState(onSurface: onSurface)
                    : RefreshIndicator(
                        color: kBlue,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          itemCount: _items.length,
                          itemBuilder: (ctx, i) {
                            final prev = i > 0 ? _items[i - 1] : null;
                            final item = _items[i];
                            final showHeader = prev == null ||
                                !_sameMonth(prev.completedAt, item.completedAt);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showHeader) _MonthHeader(date: item.completedAt),
                                _GigHistoryCard(item: item),
                                const SizedBox(height: 10),
                              ],
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Data model
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryItem {
  final String id;
  final String type;
  final String title;
  final String address;
  final double budget;
  final DateTime completedAt;
  final String hostName;

  const _HistoryItem({
    required this.id,
    required this.type,
    required this.title,
    required this.address,
    required this.budget,
    required this.completedAt,
    required this.hostName,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Header
// ─────────────────────────────────────────────────────────────────────────────

class _GigHistoryHeader extends StatelessWidget {
  final bool isDark;
  final double totalEarnings;
  final int gigCount;

  const _GigHistoryHeader({
    required this.isDark,
    required this.totalEarnings,
    required this.gigCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF0A1628), const Color(0xFF0F2040)]
              : [const Color(0xFF046BD2), const Color(0xFF1E88E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Gig History',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _StatChip(
                      label: 'Total Gigs',
                      value: '$gigCount',
                      icon: Icons.work_history_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatChip(
                      label: 'Total Earned',
                      value: '\$${totalEarnings.toStringAsFixed(2)}',
                      icon: Icons.payments_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                Text(label,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Month separator
// ─────────────────────────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  final DateTime date;
  const _MonthHeader({required this.date});

  static const _months = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        '${_months[date.month]} ${date.year}',
        style: const TextStyle(
            color: kSub,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Card
// ─────────────────────────────────────────────────────────────────────────────

class _GigHistoryCard extends StatelessWidget {
  final _HistoryItem item;
  const _GigHistoryCard({required this.item});

  Color get _typeColor {
    switch (item.type) {
      case 'Quick':
        return kAmber;
      case 'Open':
        return const Color(0xFF10B981);
      default:
        return kBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final divider = Theme.of(context).dividerColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final d = item.completedAt;
    final dateStr =
        '${d.month}/${d.day}/${d.year}  ${_hour(d.hour)}:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _typeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.check_circle_rounded, color: _typeColor, size: 20),
          ),
          const SizedBox(width: 12),
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
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text('\$${item.budget.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _TypeBadge(label: item.type, color: _typeColor),
                    if (item.hostName.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'by ${item.hostName}',
                          style: const TextStyle(color: kSub, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                if (item.address.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded,
                          color: kSub, size: 12),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(item.address,
                            style:
                                const TextStyle(color: kSub, fontSize: 11),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        color: kSub, size: 11),
                    const SizedBox(width: 3),
                    Text(dateStr,
                        style:
                            const TextStyle(color: kSub, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _hour(int h) => h == 0 ? 12 : h > 12 ? h - 12 : h;
}

class _TypeBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _TypeBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final Color onSurface;
  const _EmptyState({required this.onSurface});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.work_history_outlined,
              size: 64, color: onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('No completed gigs yet',
              style: TextStyle(
                  color: onSurface.withValues(alpha: 0.5),
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          const Text('Your finished gigs will appear here',
              style: TextStyle(color: kSub, fontSize: 13)),
        ],
      ),
    );
  }
}