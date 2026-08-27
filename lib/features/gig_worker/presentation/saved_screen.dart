import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:provider/provider.dart';

import '../../../core/providers/current_user_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/worker_active_gig.dart';
import 'widgets/gig_map_section.dart';

String _collectionForGigType(String gigType) =>
    gigType == 'offered' ? 'offered_gigs' : 'open_gigs';

bool _isActive(String gigType, String status) =>
    status == (gigType == 'offered' ? 'offered' : 'open');

String _statusLabel(String status) {
  if (status.isEmpty) return 'Unknown';
  return status
      .split('_')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

String _fmtScheduleGrid(Timestamp ts) {
  const weekdays = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final dt = ts.toDate().toLocal();
  final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final m = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  return '${weekdays[dt.weekday]}, ${months[dt.month]} ${dt.day} · $h:$m $period';
}

// ─────────────────────────────────────────────────────────────────────────────
//  Saved tab — flat list of the current worker's bookmarked gigs. Tapping a
//  gig opens the exact same detail sheet as the Home map/list
//  (showFullGigDetailSheet), so applying/accepting works identically here.
// ─────────────────────────────────────────────────────────────────────────────
class SavedScreen extends StatefulWidget {
  final String uid;

  const SavedScreen({super.key, required this.uid});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  StreamSubscription? _profileSub;
  String _workerName = '';
  String _isVerified = '';
  List<String> _workerSkills = [];
  DateTime? _suspendedUntil;

  @override
  void initState() {
    super.initState();
    _listenToProfile();
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    super.dispose();
  }

  void _listenToProfile() {
    _profileSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .snapshots()
        .listen((doc) {
          final data = doc.data() ?? {};
          final skillsXP = data['skillsXP'] as Map<String, dynamic>? ?? {};
          final suspendedUntilTs = data['suspended_until'] as Timestamp?;
          DateTime? suspendedUntil;
          if (suspendedUntilTs != null) {
            final dt = suspendedUntilTs.toDate();
            if (dt.isAfter(DateTime.now())) suspendedUntil = dt;
          }
          if (!mounted) return;
          setState(() {
            _workerName = data['name'] as String? ?? '';
            _isVerified = data['isVerified'] as String? ?? '';
            _workerSkills = skillsXP.keys.toList();
            _suspendedUntil = suspendedUntil;
          });
        });
  }

  CollectionReference<Map<String, dynamic>> get _savedRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('savedGigs');

  void _unsave(String gigId) {
    _savedRef.doc(gigId).delete();
  }

  void _toggleBookmark(String gigId, String gigType, Set<String> savedIds) {
    final doc = _savedRef.doc(gigId);
    if (savedIds.contains(gigId)) {
      doc.delete();
    } else {
      doc.set({'gigType': gigType, 'savedAt': FieldValue.serverTimestamp()});
    }
  }

  // Firestore whereIn supports at most 30 values per query.
  Future<Map<String, Map<String, dynamic>>> _fetchGigs(
    Map<String, String> gigTypeById,
  ) async {
    final result = <String, Map<String, dynamic>>{};
    final byCollection = <String, List<String>>{};
    gigTypeById.forEach((gigId, gigType) {
      byCollection
          .putIfAbsent(_collectionForGigType(gigType), () => [])
          .add(gigId);
    });

    for (final entry in byCollection.entries) {
      final ids = entry.value;
      for (var i = 0; i < ids.length; i += 30) {
        final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
        final snap = await FirebaseFirestore.instance
            .collection(entry.key)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          result[doc.id] = doc.data();
        }
      }
    }
    return result;
  }

  // Mirrors GigWorkerScreen._acceptOfferedGig's Firestore writes. This tab
  // has no active-gig overlay of its own, so on success it just confirms via
  // snackbar and points the worker back to Home instead of showing it inline.
  Future<void> _acceptOfferedGig(GigMarkerData gig) async {
    if (_suspendedUntil != null && DateTime.now().isBefore(_suspendedUntil!)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your account is currently suspended.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }
    if (await workerHasPendingCancellation(widget.uid)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Your cancellation request hasn't been approved by the admin yet.",
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (await workerHasActiveGig(widget.uid)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You need to finish your current gig before taking or accepting another one.',
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    try {
      if (gig.isMultiWorker) {
        final db = FirebaseFirestore.instance;
        final gigRef = db.collection('offered_gigs').doc(gig.id);
        final slotRef = gigRef.collection('workers').doc(widget.uid);
        await db.runTransaction((tx) async {
          final gigSnap = await tx.get(gigRef);
          final gigData = gigSnap.data() ?? {};
          final slots = (gigData['workerSlots'] as num?)?.toInt() ?? 1;
          final filled = (gigData['filledSlotCount'] as num?)?.toInt() ?? 0;
          final newFilled = filled + 1;
          tx.update(slotRef, {
            'status': 'navigating',
            'acceptedAt': FieldValue.serverTimestamp(),
          });
          tx.update(gigRef, {
            'filledSlotCount': newFilled,
            'status': newFilled >= slots ? 'filled' : 'partially_filled',
          });
        });
      } else {
        await FirebaseFirestore.instance
            .collection('offered_gigs')
            .doc(gig.id)
            .update({
              'status': 'navigating',
              'acceptedAt': FieldValue.serverTimestamp(),
            });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gig accepted! Head to Home to get started.'),
            backgroundColor: Color(0xFF22C55E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[Saved] accept offered gig error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't accept this gig. Please try again."),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // Re-reads the gig doc live right before opening the sheet — the list's
  // cached data can lag behind (e.g. a gig gets filled or started while it
  // just sits bookmarked), and that's exactly the status this sheet's
  // Apply/Take-Gig gating depends on to stay disabled.
  Future<void> _showGigDetail(
    BuildContext context,
    String gigId,
    String gigType,
    Set<String> savedIds,
  ) async {
    final snap = await FirebaseFirestore.instance
        .collection(_collectionForGigType(gigType))
        .doc(gigId)
        .get();
    if (!context.mounted) return;
    if (!snap.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This gig no longer exists.')),
      );
      return;
    }
    final gig = gigMarkerFromDoc(gigId, snap.data()!, gigType,
        workerUid: widget.uid);
    if (gig == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This gig's location is missing.")),
      );
      return;
    }
    // Without this, applyToOpenGig has no location to compare against and
    // silently skips its different-country/too-far safeguards entirely —
    // exactly what let an out-of-country saved gig through.
    final userProvider = context.read<CurrentUserProvider>();
    final myLocation =
        (userProvider.lastLat != null && userProvider.lastLng != null)
            ? LatLng(userProvider.lastLat!, userProvider.lastLng!)
            : null;
    showFullGigDetailSheet(
      context,
      gig: gig,
      uid: widget.uid,
      workerName: _workerName,
      isVerified: _isVerified,
      workerSkills: _workerSkills,
      bookmarkedGigIds: savedIds,
      onToggleBookmark: (id, type) => _toggleBookmark(id, type, savedIds),
      myLocation: myLocation,
      onOfferedGigAccepted: _acceptOfferedGig,
      onSeeOnMap: () => _openFullScreenMap(context, gig.position),
    );
  }

  // Opens the same fullscreen map view as the Home tab's "expand" button,
  // seeded to open already centered on this gig.
  void _openFullScreenMap(BuildContext context, LatLng focus) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          body: GigMapSection(
            fullScreen: true,
            uid: widget.uid,
            workerName: _workerName,
            seekingQuickGigs: false,
            isVerified: _isVerified,
            workerSkills: _workerSkills,
            onOfferedGigAccepted: _acceptOfferedGig,
            externalFocusRequest: ValueNotifier(focus),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(
          'Saved',
          style: TextStyle(
            color: onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _savedRef.orderBy('savedAt', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: kGold.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.bookmark_outline_rounded,
                            color: kGold, size: 28),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No saved gigs yet',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Bookmark a gig from its details to find it here later.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: onSurface.withValues(alpha: 0.6),
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final gigTypeById = {
              for (final doc in docs)
                doc.id: doc.data()['gigType'] as String? ?? 'open',
            };
            final savedIds = docs.map((d) => d.id).toSet();

            return FutureBuilder<Map<String, Map<String, dynamic>>>(
              future: _fetchGigs(gigTypeById),
              builder: (context, gigsSnap) {
                if (!gigsSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final gigsById = gigsSnap.data!;
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final gigId = docs[i].id;
                    final data = gigsById[gigId];
                    if (data == null) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: Theme.of(context).cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                              color: Theme.of(context).dividerColor),
                        ),
                        elevation: 0,
                        child: ListTile(
                          title: Text(
                            'No longer available',
                            style: TextStyle(
                              color: onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => _unsave(gigId),
                          ),
                        ),
                      );
                    }
                    final title = data['title'] as String? ?? 'Untitled Gig';
                    final hostName = data['hostName'] as String? ?? '';
                    final address = data['address'] as String? ?? '';
                    final budget = (data['budget'] as num?)?.toDouble() ?? 0;
                    final currencyCode =
                        (data['currencyCode'] as String?) ?? 'USD';
                    final status = data['status'] as String? ?? '';
                    final gigType = gigTypeById[gigId] ?? 'open';
                    final active = _isActive(gigType, status);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: Theme.of(context).cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      elevation: 0,
                      child: ListTile(
                        onTap: () =>
                            _showGigDetail(context, gigId, gigType, savedIds),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: kGold.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child:
                              const Icon(Icons.bookmark_rounded, color: kGold),
                        ),
                        title: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: onSurface, fontWeight: FontWeight.w700, fontSize: 14.5),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: [
                            Text(
                              hostName.isNotEmpty ? hostName : '—',
                              style: const TextStyle(
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              ' • ',
                              style: TextStyle(
                                color: onSurface.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(budget, currencyCode),
                              style: const TextStyle(
                                color: Color(0xFF2B6FB5),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                            ],),

                            Text(
                              address.isNotEmpty ? address : '—',
                              style: const TextStyle(
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _fmtScheduleGrid(data['scheduledDate'] as Timestamp? ??
                                  Timestamp.now()),
                              style: TextStyle(
                                color: onSurface.withValues(alpha: 0.5),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: active ? Colors.green : kSub,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _statusLabel(status),
                                  style: TextStyle(
                                    color: active ? Colors.green : kSub,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => _unsave(gigId),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
