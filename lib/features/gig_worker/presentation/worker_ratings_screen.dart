import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Worker Ratings & Reviews Screen
//  Shows all ratings received by the worker from gig hosts.
// ─────────────────────────────────────────────────────────────────────────────

class WorkerRatingsScreen extends StatefulWidget {
  const WorkerRatingsScreen({super.key});

  @override
  State<WorkerRatingsScreen> createState() => _WorkerRatingsScreenState();
}

class _WorkerRatingsScreenState extends State<WorkerRatingsScreen> {
  bool _loading = true;
  List<_RatingItem> _items = [];

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

    try {
      final results = await Future.wait([
        _fetchCollection('quick_gigs', uid, 'quick'),
        _fetchCollection('open_gigs', uid, 'open'),
        _fetchCollection('offered_gigs', uid, 'offered'),
      ]);

      final all = results.expand((e) => e).toList()
        ..sort((a, b) {
          if (a.ratedAt == null && b.ratedAt == null) return 0;
          if (a.ratedAt == null) return 1;
          if (b.ratedAt == null) return -1;
          return b.ratedAt!.compareTo(a.ratedAt!);
        });

      setState(() {
        _items = all;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[WorkerRatings] load error: $e');
      setState(() => _loading = false);
    }
  }

  Future<List<_RatingItem>> _fetchCollection(
      String collection, String uid, String type) async {
    final snap = await FirebaseFirestore.instance
        .collection(collection)
        .where('workerId', isEqualTo: uid)
        .get();

    return snap.docs.where((doc) {
      final rating = (doc.data()['hostRating'] as num?)?.toInt() ?? 0;
      return rating > 0;
    }).map((doc) {
      final d = doc.data();
      final ratedAt = (d['hostRatedAt'] as Timestamp?)?.toDate();
      return _RatingItem(
        gigTitle: d['title'] as String? ?? type,
        hostName: d['hostName'] as String? ?? '',
        rating: (d['hostRating'] as num).toInt(),
        gigType: type,
        ratedAt: ratedAt,
      );
    }).toList();
  }

  double get _avgRating {
    if (_items.isEmpty) return 0;
    return _items.fold<double>(0, (acc, e) => acc + e.rating) / _items.length;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _RatingsHeader(
            isDark: isDark,
            avgRating: _avgRating,
            ratingCount: _items.length,
            items: _items,
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: kAmber))
                : _items.isEmpty
                    ? _EmptyState(onSurface: onSurface)
                    : RefreshIndicator(
                        color: kAmber,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          itemCount: _items.length,
                          itemBuilder: (ctx, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _RatingCard(
                              item: _items[i],
                              isDark: isDark,
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Data model
// ─────────────────────────────────────────────────────────────────────────────

class _RatingItem {
  final String gigTitle;
  final String hostName;
  final int rating;
  final String gigType;
  final DateTime? ratedAt;

  const _RatingItem({
    required this.gigTitle,
    required this.hostName,
    required this.rating,
    required this.gigType,
    this.ratedAt,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Header
// ─────────────────────────────────────────────────────────────────────────────

class _RatingsHeader extends StatelessWidget {
  final bool isDark;
  final double avgRating;
  final int ratingCount;
  final List<_RatingItem> items;

  const _RatingsHeader({
    required this.isDark,
    required this.avgRating,
    required this.ratingCount,
    required this.items,
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
                  const Text('Ratings & Reviews',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        avgRating.toStringAsFixed(1),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            height: 1),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: List.generate(5, (i) {
                          final full = i < avgRating.floor();
                          final half = !full && i < avgRating && avgRating - i >= 0.5;
                          return Icon(
                            full
                                ? Icons.star_rounded
                                : half
                                    ? Icons.star_half_rounded
                                    : Icons.star_outline_rounded,
                            color: kAmber,
                            size: 18,
                          );
                        }),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$ratingCount ${ratingCount == 1 ? 'review' : 'reviews'}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  Expanded(child: _RatingBreakdown(items: items)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatingBreakdown extends StatelessWidget {
  // Placeholder — wired to actual items in the stateful parent via a getter
  final List<_RatingItem> items;
  const _RatingBreakdown({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(5, (i) {
        final star = 5 - i;
        final count = items.where((e) => e.rating == star).length;
        final fraction = items.isEmpty ? 0.0 : count / items.length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Text('$star',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 11)),
              const SizedBox(width: 4),
              const Icon(Icons.star_rounded, color: kAmber, size: 11),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(kAmber),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 20,
                child: Text(
                  '$count',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 11),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Rating card
// ─────────────────────────────────────────────────────────────────────────────

class _RatingCard extends StatelessWidget {
  final _RatingItem item;
  final bool isDark;

  const _RatingCard({required this.item, required this.isDark});

  static const _labels = ['', 'Poor', 'Fair', 'Good', 'Great', 'Excellent'];

  Color get _typeColor {
    switch (item.gigType) {
      case 'quick':
        return kAmber;
      case 'open':
        return const Color(0xFF10B981);
      default:
        return kBlue;
    }
  }

  IconData get _typeIcon {
    switch (item.gigType) {
      case 'quick':
        return Icons.bolt_rounded;
      case 'open':
        return Icons.work_outline_rounded;
      default:
        return Icons.handshake_outlined;
    }
  }

  String get _typeLabel {
    switch (item.gigType) {
      case 'quick':
        return 'Quick';
      case 'open':
        return 'Open';
      default:
        return 'Offered';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    final divider = Theme.of(context).dividerColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _typeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(_typeIcon, color: _typeColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(item.gigTitle,
                          style: TextStyle(
                              color: onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    _TypeBadge(label: _typeLabel, color: _typeColor),
                  ],
                ),
                if (item.hostName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.person_outline_rounded,
                          size: 12, color: kSub),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('by ${item.hostName}',
                            style:
                                const TextStyle(color: kSub, fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    ...List.generate(
                      5,
                      (i) => Icon(
                        i < item.rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: kAmber,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.rating < _labels.length
                          ? _labels[item.rating]
                          : '',
                      style: const TextStyle(
                          color: kAmber,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                    if (item.ratedAt != null) ...[
                      const Spacer(),
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded,
                              size: 11, color: kSub),
                          const SizedBox(width: 3),
                          Text(_fmtDate(item.ratedAt!),
                              style: const TextStyle(
                                  color: kSub, fontSize: 11)),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month]} ${dt.day}, ${dt.year}';
  }
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
        borderRadius: BorderRadius.circular(20),
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
          Icon(Icons.star_border_rounded,
              size: 64, color: onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('No ratings yet',
              style: TextStyle(
                  color: onSurface.withValues(alpha: 0.5),
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          const Text('Ratings from hosts will appear here',
              style: TextStyle(color: kSub, fontSize: 13)),
        ],
      ),
    );
  }
}