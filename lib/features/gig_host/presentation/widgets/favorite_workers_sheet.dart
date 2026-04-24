import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Favorite Workers sheet
// ─────────────────────────────────────────────────────────────────────────────
class FavoriteWorkersSheet extends StatefulWidget {
  final String hostId;
  const FavoriteWorkersSheet({super.key, required this.hostId});

  @override
  State<FavoriteWorkersSheet> createState() => _FavoriteWorkersSheetState();
}

class _FavoriteWorkersSheetState extends State<FavoriteWorkersSheet> {
  bool _loading = true;
  List<Map<String, dynamic>> _workers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = FirebaseFirestore.instance;
    final hostDoc = await db.collection('users').doc(widget.hostId).get();
    final ids = (hostDoc.data()?['favoriteWorkerIds'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    if (ids.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final docs = await Future.wait(
      ids.map((id) => db.collection('users').doc(id).get()),
    );

    final workers = <Map<String, dynamic>>[];
    for (final doc in docs) {
      if (doc.exists) {
        final data = Map<String, dynamic>.from(doc.data()!);
        data['uid'] = doc.id;
        workers.add(data);
      }
    }

    if (mounted) {
      setState(() {
        _workers = workers;
        _loading = false;
      });
    }
  }

  Future<void> _unfavorite(String workerId) async {
    setState(() => _workers.removeWhere((w) => w['uid'] == workerId));
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.hostId)
        .set(
          {'favoriteWorkerIds': FieldValue.arrayRemove([workerId])},
          SetOptions(merge: true),
        );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    const pink = Color(0xFFEC4899);

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
                      color: pink.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.favorite_rounded,
                        color: pink, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Favorite Workers',
                          style: TextStyle(
                              color: onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Text(
                        _loading ? '...' : '${_workers.length} saved',
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
                child: Center(
                    child: CircularProgressIndicator(color: kAmber)),
              )
            else if (_workers.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.favorite_border_rounded,
                          color: kSub.withValues(alpha: 0.35), size: 52),
                      const SizedBox(height: 12),
                      const Text('No favorite workers yet',
                          style: TextStyle(color: kSub, fontSize: 14)),
                      const SizedBox(height: 6),
                      const Text(
                        'Tap the heart icon on a worker\nin your Gig History to save them here.',
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
                  itemCount: _workers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) => _FavoriteWorkerCard(
                    worker: _workers[i],
                    isDark: isDark,
                    onUnfavorite: () =>
                        _unfavorite(_workers[i]['uid'] as String),
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
//  Single card
// ─────────────────────────────────────────────────────────────────────────────
class _FavoriteWorkerCard extends StatelessWidget {
  final Map<String, dynamic> worker;
  final bool isDark;
  final VoidCallback onUnfavorite;

  const _FavoriteWorkerCard({
    required this.worker,
    required this.isDark,
    required this.onUnfavorite,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final name = worker['name'] as String? ?? 'Worker';
    final photoUrl = worker['photoUrl'] as String? ?? '';
    final rating = (worker['ratingAsWorker'] as num? ?? 5.0).toDouble();
    final ratingCount = (worker['ratingCount'] as num? ?? 0).toInt();
    final skills = (worker['skills'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final isOnline = worker['isOnline'] as bool? ?? false;
    const pink = Color(0xFFEC4899);

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
          Stack(
            children: [
              _WorkerAvatar(photoUrl: photoUrl, size: 52),
              if (isOnline)
                Positioned(
                  right: 1,
                  bottom: 1,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: isDark
                              ? const Color(0xFF1A1A2E)
                              : Colors.white,
                          width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        color: onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(
                  children: [
                    ...List.generate(5, (i) {
                      final full = i < rating.floor();
                      final half =
                          !full && i < rating && rating - i >= 0.5;
                      return Icon(
                        full
                            ? Icons.star_rounded
                            : half
                                ? Icons.star_half_rounded
                                : Icons.star_outline_rounded,
                        color: kAmber,
                        size: 12,
                      );
                    }),
                    const SizedBox(width: 4),
                    Text(rating.toStringAsFixed(1),
                        style: TextStyle(
                            color: onSurface,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 3),
                    Text('($ratingCount)',
                        style:
                            const TextStyle(color: kSub, fontSize: 10)),
                  ],
                ),
                if (skills.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: skills
                        .take(3)
                        .map((s) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: kBlue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(s,
                                  style: const TextStyle(
                                      color: kBlue, fontSize: 10)),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onUnfavorite,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: pink.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.favorite_rounded,
                  color: pink, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Avatar
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerAvatar extends StatelessWidget {
  final String photoUrl;
  final double size;
  const _WorkerAvatar({required this.photoUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    if (photoUrl.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, _) => _DefaultAvatar(size: size),
          errorWidget: (_, _, _) => _DefaultAvatar(size: size),
        ),
      );
    }
    return _DefaultAvatar(size: size);
  }
}

class _DefaultAvatar extends StatelessWidget {
  final double size;
  const _DefaultAvatar({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: kAmber.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: kAmber.withValues(alpha: 0.4), width: 2),
      ),
      child: Icon(Icons.account_circle_rounded,
          color: kAmber, size: size * 0.6),
    );
  }
}
