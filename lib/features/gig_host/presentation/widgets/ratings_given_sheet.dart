import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/app_colors.dart';

class RatingsGivenSheet extends StatefulWidget {
  const RatingsGivenSheet({super.key});

  @override
  State<RatingsGivenSheet> createState() => _RatingsGivenSheetState();
}

class _RatingsGivenSheetState extends State<RatingsGivenSheet> {
  bool _loading = true;
  List<_RatingEntry> _ratings = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final db = FirebaseFirestore.instance;
    final collections = {
      'quick_gigs': 'quick',
      'open_gigs': 'open',
      'offered_gigs': 'offered',
    };

    try {
      final results = await Future.wait(
        collections.entries.map((e) => db
            .collection(e.key)
            .where('hostId', isEqualTo: uid)
            .get()),
      );

      final entries = <_RatingEntry>[];
      for (int i = 0; i < results.length; i++) {
        final gigType = collections.values.elementAt(i);
        for (final doc in results[i].docs) {
          final d = doc.data();
          final rating = (d['hostRating'] as num?)?.toInt() ?? 0;
          if (rating <= 0) continue;
          final ratedAt = d['hostRatedAt'] as Timestamp?;
          entries.add(_RatingEntry(
            gigTitle: d['title'] as String? ?? 'Gig',
            workerName: d['assignedWorkerName'] as String? ??
                d['workerName'] as String? ??
                'Worker',
            rating: rating,
            gigType: gigType,
            ratedAt: ratedAt?.toDate(),
          ));
        }
      }

      // Sort by ratedAt descending (nulls last)
      entries.sort((a, b) {
        if (a.ratedAt == null && b.ratedAt == null) return 0;
        if (a.ratedAt == null) return 1;
        if (b.ratedAt == null) return -1;
        return b.ratedAt!.compareTo(a.ratedAt!);
      });

      if (mounted) setState(() { _ratings = entries; _loading = false; });
    } catch (e) {
      debugPrint('[RatingsGivenSheet] load error: $e');
      if (mounted) setState(() => _loading = false);
    }
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
                    child: const Icon(Icons.star_rounded, color: kAmber, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ratings Given',
                          style: TextStyle(
                              color: onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Text(
                        _loading ? '...' : '${_ratings.length} rated',
                        style: const TextStyle(color: kSub, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: kBorder),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator(color: kAmber)),
              )
            else if (_ratings.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_border_rounded,
                          color: kSub.withValues(alpha: 0.35), size: 52),
                      const SizedBox(height: 12),
                      const Text('No ratings given yet',
                          style: TextStyle(color: kSub, fontSize: 14)),
                      const SizedBox(height: 6),
                      const Text(
                        'Rate workers after completing a gig\nto see your ratings here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kSub, fontSize: 12),
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
                  itemCount: _ratings.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _RatingCard(
                    entry: _ratings[i],
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
//  Data
// ─────────────────────────────────────────────────────────────────────────────
class _RatingEntry {
  final String gigTitle;
  final String workerName;
  final int rating;
  final String gigType;
  final DateTime? ratedAt;

  const _RatingEntry({
    required this.gigTitle,
    required this.workerName,
    required this.rating,
    required this.gigType,
    this.ratedAt,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Card
// ─────────────────────────────────────────────────────────────────────────────
class _RatingCard extends StatelessWidget {
  final _RatingEntry entry;
  final bool isDark;

  const _RatingCard({required this.entry, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final typeColor = entry.gigType == 'quick'
        ? kAmber
        : entry.gigType == 'open'
            ? kBlue
            : const Color(0xFF8B5CF6);
    final typeLabel = entry.gigType == 'quick'
        ? 'Quick'
        : entry.gigType == 'open'
            ? 'Open'
            : 'Offered';
    final typeIcon = entry.gigType == 'quick'
        ? Icons.bolt_rounded
        : entry.gigType == 'open'
            ? Icons.work_outline_rounded
            : Icons.handshake_outlined;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.grey.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? kBorder : Colors.grey.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.gigTitle,
                        style: TextStyle(
                            color: onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(typeLabel,
                          style: TextStyle(
                              color: typeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(Icons.person_outline_rounded,
                        size: 12, color: kSub),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        entry.workerName,
                        style: const TextStyle(color: kSub, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // Stars
                    ...List.generate(5, (i) => Icon(
                          i < entry.rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: kAmber,
                          size: 16,
                        )),
                    const SizedBox(width: 6),
                    Text(
                      entry.rating.toString(),
                      style: TextStyle(
                          color: onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                    ),
                    if (entry.ratedAt != null) ...[
                      const SizedBox(width: 8),
                      const Text('·', style: TextStyle(color: kSub)),
                      const SizedBox(width: 8),
                      Text(
                        _fmtDate(entry.ratedAt!),
                        style: const TextStyle(color: kSub, fontSize: 11),
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
