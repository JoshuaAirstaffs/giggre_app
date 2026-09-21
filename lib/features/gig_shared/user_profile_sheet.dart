import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/models/rating_review.dart';
import 'review_card.dart';
import '../../core/models/rating_summary.dart';
import '../../core/services/rating_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/providers/current_user_provider.dart';
import '../../core/widgets/avatars/giggre_avatar.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/worker_skills.dart';
import '../reports/models/report_content_type.dart';
import '../reports/report_service.dart';
import 'active_gig_theme.dart';

/// Shared "view someone's profile" drawer — avatar, name, verification
/// badge, rating, completed-gig count, recent reviews, member-since date,
/// bio, skills, an optional "recent related completed gigs" section, and
/// Report/Block actions. Used both from the gig host's applicant list
/// (gig_detail_sheet.dart) and the worker's gig-listing preview
/// (gig_map_section.dart), so it always looks and behaves the same
/// regardless of which side of a gig you're viewing from.
///
/// [role] says which reputation is being viewed: `worker` for someone being
/// considered for a gig, `host` for whoever posted one. Workers and hosts
/// keep entirely separate ratings and reviews, so getting this wrong shows
/// the other side's score.
Future<void> showUserProfileSheet(
  BuildContext context, {
  required String uid,
  required String fallbackName,
  required String surface,
  required RateeRole role,
  List<String> matchSkillsForCompletedGigs = const [],
  Future<void> Function()? onBlocked,
}) async {
  if (uid.isEmpty) return;
  final currentUid = FirebaseAuth.instance.currentUser?.uid;

  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      // Declared here (not inside FutureBuilder/StatefulBuilder's own
      // builder callbacks) so they survive those callbacks re-running while
      // still being scoped to this one sheet instance.
      bool blocked = false;
      bool blocking = false;

      return FutureBuilder<
        ({
          DocumentSnapshot<Map<String, dynamic>> userDoc,
          List<CompletedGigMatch> matches,
          List<RatingReview> reviews,
          int completedGigs,
        })
      >(
        future: () async {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          // Run the three independent reads together — the sheet shows a
          // spinner until all of them land either way.
          final rest = await Future.wait([
            matchSkillsForCompletedGigs.isEmpty
                ? Future.value(<CompletedGigMatch>[])
                : fetchSkillMatchedCompletedGigs(
                    uid,
                    matchSkillsForCompletedGigs,
                  ),
            RatingService.recentReviews(userId: uid, role: role),
            countCompletedGigs(uid, role, userDoc.data()),
          ]);
          return (
            userDoc: userDoc,
            matches: rest[0] as List<CompletedGigMatch>,
            reviews: rest[1] as List<RatingReview>,
            completedGigs: rest[2] as int,
          );
        }(),
        builder: (_, snap) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final onSurface = activeGigTextPrimary(isDark);
          final data = snap.data?.userDoc.data();
          final matchedGigs = snap.data?.matches ?? const [];
          final reviews = snap.data?.reviews ?? const <RatingReview>[];
          final completedGigs = snap.data?.completedGigs ?? 0;
          final name = (data?['name'] as String?)?.trim().isNotEmpty == true
              ? data!['name'] as String
              : fallbackName;
          final photoUrl = data?['photoUrl'] as String? ?? '';
          final bio = data?['bio'] as String? ?? '';
          final skills = workerSkillsFrom(data);
          final summary = RatingSummary.fromUserData(data, role);
          final isVerified = data?['isVerified'] as String? ?? 'unverified';
          final memberSince = (data?['createdAt'] as Timestamp?)?.toDate();

          return StatefulBuilder(
            builder: (ctx, setSheetState) {
              return Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  MediaQuery.of(ctx).viewPadding.bottom + 20,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).cardColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: snap.connectionState != ConnectionState.done
                    ? const SizedBox(
                        height: 160,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : blocked
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(
                                    alpha: 0.12,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.block_rounded,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'User blocked',
                                  style: TextStyle(
                                    color: onSurface,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 17,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            onBlocked != null
                                ? '$name has been blocked and their application removed.'
                                : '$name has been blocked. You won\'t see their content anymore, and they can\'t message you.',
                            style: const TextStyle(
                              color: kSub,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Done',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 36,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ProfileAvatar(
                                  photoUrl: photoUrl,
                                  name: name,
                                  size: 52,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              name,
                                              style: TextStyle(
                                                color: onSurface,
                                                fontSize: 17,
                                                fontWeight: FontWeight.w700,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          verificationBadge(ctx, isVerified),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.star_rounded,
                                            color: kGold,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              completedGigs > 0
                                                  ? '${summary.label} · '
                                                        '$completedGigs ${role == RateeRole.worker ? 'gigs done' : 'gigs hosted'}'
                                                  : summary.label,
                                              style: const TextStyle(
                                                color: kSub,
                                                fontSize: 13,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (memberSince != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Member since ${DateFormat('MMMM y').format(memberSince)}',
                                          style: const TextStyle(
                                            color: kSub,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (currentUid != null &&
                                    currentUid != uid) ...[
                                  IconButton(
                                    icon: const Icon(
                                      Icons.flag_outlined,
                                      color: Colors.orange,
                                    ),
                                    tooltip: 'Report',
                                    onPressed: blocking
                                        ? null
                                        : () {
                                            Navigator.pop(ctx);
                                            ReportService.show(
                                              context,
                                              contentType:
                                                  ReportContentType.user,
                                              contentId: uid,
                                              contentSnapshot: bio,
                                              contentAuthorId: uid,
                                              surface: surface,
                                            );
                                          },
                                  ),
                                  IconButton(
                                    icon: blocking
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.block_rounded,
                                            color: Colors.redAccent,
                                          ),
                                    tooltip: 'Block',
                                    onPressed: blocking
                                        ? null
                                        : () async {
                                            setSheetState(
                                              () => blocking = true,
                                            );
                                            try {
                                              await FirebaseFirestore.instance
                                                  .collection('users')
                                                  .doc(currentUid)
                                                  .update({
                                                    'blockedUsers':
                                                        FieldValue.arrayUnion([
                                                          uid,
                                                        ]),
                                                  });
                                              await onBlocked?.call();
                                              setSheetState(() {
                                                blocking = false;
                                                blocked = true;
                                              });
                                            } catch (e) {
                                              setSheetState(
                                                () => blocking = false,
                                              );
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Could not block this user. Please try again.',
                                                    ),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                  ),
                                ],
                              ],
                            ),
                            if (bio.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                'About',
                                style: TextStyle(
                                  color: onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                bio,
                                style: TextStyle(
                                  color: activeGigTextMuted(isDark),
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ],
                            if (skills.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Skills',
                                style: TextStyle(
                                  color: onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: skills
                                    .map(
                                      (s) => Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: kHostAccent.solid.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          s,
                                          style: TextStyle(
                                            color: kHostAccent.solid,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                            if (reviews.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Text(
                                    'Reviews',
                                    style: TextStyle(
                                      color: onSurface,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // The list is capped at the most recent few, so
                                  // say how many there are in total rather than
                                  // implying these are all of them.
                                  if (summary.count > reviews.length)
                                    Text(
                                      'showing ${reviews.length} of ${summary.count}',
                                      style: TextStyle(
                                        color: activeGigTextMuted(isDark),
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...reviews.map(
                                (r) => ReviewCard(
                                  review: r,
                                  isDark: isDark,
                                  onSurface: onSurface,
                                ),
                              ),
                            ],
                            if (matchedGigs.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Recent Related Completed Gigs',
                                style: TextStyle(
                                  color: onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...matchedGigs
                                  .take(3)
                                  .map(
                                    (g) => Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.check_circle_rounded,
                                            color: Color(0xFF10B981),
                                            size: 14,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              g.title.isNotEmpty
                                                  ? g.title
                                                  : 'Untitled gig',
                                              style: TextStyle(
                                                color: activeGigTextMuted(
                                                  isDark,
                                                ),
                                                fontSize: 12.5,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            DateFormat(
                                              'MMM d, y',
                                            ).format(g.completedAt),
                                            style: const TextStyle(
                                              color: kSub,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                            ],
                          ],
                        ),
                      ),
              );
            },
          );
        },
      );
    },
  );
}

class CompletedGigMatch {
  /// Gig document id — the dedupe key, since a multi-worker gig can surface
  /// both from its top-level document and from this worker's slot.
  final String id;
  final String title;
  final DateTime completedAt;

  /// Which of the wanted skills this gig actually required, in the gig's own
  /// casing — what makes the row "relevant" rather than merely completed.
  final List<String> matchedSkills;

  /// 'Open gig' or 'Offered gig', for context on where the work came from.
  final String gigType;

  const CompletedGigMatch({
    required this.id,
    required this.title,
    required this.completedAt,
    this.matchedSkills = const [],
    this.gigType = '',
  });
}

/// How many matches [fetchSkillMatchedCompletedGigs] returns at most. Each
/// surface shows as much of that as it has room for — the sheet a few, the
/// full profile screen all of them behind a "show all".
const int kSkillMatchedGigLimit = 12;

// The most recent gigs this worker completed whose required skill(s) overlap
// with [requiredSkills], newest first and capped at [kSkillMatchedGigLimit] —
// shown on the profile so a host can judge relevant experience at a glance.
// Each match carries the overlapping skills, so the row can say why it is
// relevant rather than just that it happened. open_gigs carries a
// `requiredSkills` list; offered_gigs carries a single `skillRequired`
// string; quick_gigs has no skill field at all and never matches. Multi-
// worker gigs (any collection) track this worker's own completion on their
// `workers/{uid}` subcollection doc instead of the top-level gig doc, so
// that's queried separately via collectionGroup, same as
// gig_history_screen.dart's _fetchMultiWorkerCompletions.
Future<List<CompletedGigMatch>> fetchSkillMatchedCompletedGigs(
  String workerId,
  List<String> requiredSkills,
) async {
  final wanted = requiredSkills
      .map((s) => s.toLowerCase().trim())
      .where((s) => s.isNotEmpty)
      .toSet();
  if (wanted.isEmpty) return [];

  final db = FirebaseFirestore.instance;

  // Keyed by gig id so the same gig arriving from two queries lands once.
  final results = <String, CompletedGigMatch>{};

  /// The wanted skills this gig required, keeping the gig's own casing for
  /// display. Empty means the gig is not relevant.
  List<String> matchesIn(List<String> gigSkills) =>
      gigSkills.where((s) => wanted.contains(s.toLowerCase().trim())).toList();

  void collect(
    QuerySnapshot<Map<String, dynamic>> snap,
    List<String> Function(Map<String, dynamic> data) skillsOf,
    String gigType,
  ) {
    for (final doc in snap.docs) {
      final data = doc.data();
      final matched = matchesIn(skillsOf(data));
      if (matched.isEmpty) continue;
      final completedAt = (data['completedAt'] as Timestamp?)?.toDate();
      if (completedAt == null) continue;
      results[doc.id] = CompletedGigMatch(
        id: doc.id,
        title: data['title'] as String? ?? '',
        completedAt: completedAt,
        matchedSkills: matched,
        gigType: gigType,
      );
    }
  }

  List<String> openSkills(Map<String, dynamic> d) =>
      (d['requiredSkills'] as List<dynamic>? ?? [])
          .map((s) => s.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
  List<String> offeredSkills(Map<String, dynamic> d) {
    final s = (d['skillRequired'] as String? ?? '').trim();
    return s.isEmpty ? const [] : [s];
  }

  final snaps = await Future.wait([
    db
        .collection('open_gigs')
        .where('assignedWorkerId', isEqualTo: workerId)
        .where('status', isEqualTo: 'completed')
        .get(),
    db
        .collection('offered_gigs')
        .where('workerId', isEqualTo: workerId)
        .where('status', isEqualTo: 'completed')
        .get(),
    db
        .collectionGroup('workers')
        .where('workerId', isEqualTo: workerId)
        .where('status', isEqualTo: 'completed')
        .get(),
  ]);
  collect(snaps[0], openSkills, 'Open gig');
  collect(snaps[1], offeredSkills, 'Offered gig');

  for (final doc in snaps[2].docs) {
    final slot = doc.data();
    final gigId = slot['gigId'] as String?;
    final gigCollection = slot['gigCollection'] as String?;
    if (gigId == null ||
        gigCollection == null ||
        gigCollection == 'quick_gigs' ||
        results.containsKey(gigId)) {
      continue;
    }
    final gigSnap = await db.collection(gigCollection).doc(gigId).get();
    final gigData = gigSnap.data();
    if (gigData == null) continue;
    final isOpen = gigCollection == 'open_gigs';
    final matched = matchesIn(
      isOpen ? openSkills(gigData) : offeredSkills(gigData),
    );
    if (matched.isEmpty) continue;
    final completedAt = (slot['completedAt'] as Timestamp?)?.toDate();
    if (completedAt == null) continue;
    results[gigId] = CompletedGigMatch(
      id: gigId,
      title: gigData['title'] as String? ?? '',
      completedAt: completedAt,
      matchedSkills: matched,
      gigType: isOpen ? 'Open gig' : 'Offered gig',
    );
  }

  final sorted = results.values.toList()
    ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  return sorted.take(kSkillMatchedGigLimit).toList();
}

// Verified users get a plain "Verified" badge. A non-verified one who still
// got through only did so because general_config/gig_visibility_rules.
// allowGigAccessForUnverified was on — labeled "Provisional" rather than a
// bare "Unverified" so it reads as an intentional, admin-controlled override
// rather than a bug letting anyone through.
Widget verificationBadge(BuildContext context, String isVerified) {
  final allowUnverified = context
      .watch<CurrentUserProvider>()
      .allowGigAccessForUnverified;
  final (label, color) = isVerified == 'verified'
      ? ('Verified', const Color(0xFF10B981))
      : allowUnverified
      ? ('Provisional', kAmber)
      : ('Unverified', Colors.redAccent);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class ProfileAvatar extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final double size;

  /// The disc behind the initials when there is no photo.
  ///
  /// Brand blue by default, which is right on a neutral card. A surface that
  /// sits on a coloured header passes its own instead — the blue is lighter
  /// than either header gradient, so left alone it jumps forward out of the
  /// ring rather than sitting in it.
  final Color fallbackColor;

  /// The Giggre character this user picked, if any.
  ///
  /// Wins over [photoUrl], which holds a still of the same avatar for screens
  /// that do not know about them. Passing it here is what makes the picked
  /// character move rather than sit there as a flat picture.
  final String? avatarId;

  const ProfileAvatar({
    super.key,
    required this.photoUrl,
    required this.name,
    required this.size,
    this.fallbackColor = kBlue,
    this.avatarId,
  });

  Widget _initialsFallback() {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      decoration: BoxDecoration(color: fallbackColor, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatar = GiggreAvatar.forId(avatarId, size: size);
    if (avatar != null) return avatar;

    final url = photoUrl;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: (url != null && url.isNotEmpty)
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _initialsFallback(),
              )
            : _initialsFallback(),
      ),
    );
  }
}

/// Gig collections a host's gigs can live in. All three carry `hostId`, so
/// each one costs a single count() aggregate.
const _kHostGigCollections = ['quick_gigs', 'open_gigs', 'offered_gigs'];

/// How many gigs this host has posted, whatever became of them — the headline
/// number on a host profile, where a low completed count can just as easily
/// mean "posted last week" as "no-one turned up".
///
/// Counted server-side, so none of the gig documents transfer.
Future<int> countPostedGigs(String uid) async {
  try {
    final db = FirebaseFirestore.instance;
    final counts = await Future.wait(
      _kHostGigCollections.map(
        (c) => db.collection(c).where('hostId', isEqualTo: uid).count().get(),
      ),
    );
    return counts.fold<int>(0, (total, c) => total + (c.count ?? 0));
  } catch (e) {
    // A denied read should cost the stat, not the profile.
    debugPrint('[UserProfileSheet] posted gig count failed: $e');
    return 0;
  }
}

/// How many gigs this person has completed in [role].
///
/// A worker's total is already maintained on their user doc by
/// EarningsService, so that side costs no extra read. A host has no such
/// counter, so their posted gigs are counted with three count() aggregates —
/// server-side tallies that never transfer the documents themselves.
Future<int> countCompletedGigs(
  String uid,
  RateeRole role,
  Map<String, dynamic>? userData,
) async {
  if (role == RateeRole.worker) {
    final earnings = userData?['earnings'] as Map<String, dynamic>?;
    return (earnings?['completedGigs'] as num?)?.toInt() ?? 0;
  }

  try {
    final db = FirebaseFirestore.instance;
    final counts = await Future.wait(
      _kHostGigCollections.map(
        (c) => db
            .collection(c)
            .where('hostId', isEqualTo: uid)
            .where('status', isEqualTo: 'completed')
            .count()
            .get(),
      ),
    );
    return counts.fold<int>(0, (total, c) => total + (c.count ?? 0));
  } catch (e) {
    // A missing index or a denied read should cost the count, not the sheet.
    debugPrint('[UserProfileSheet] completed gig count failed: $e');
    return 0;
  }
}
