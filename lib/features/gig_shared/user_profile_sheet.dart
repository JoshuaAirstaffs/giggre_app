import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/models/rating_summary.dart';
import '../../core/services/rating_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/providers/current_user_provider.dart';
import '../../core/theme/app_colors.dart';
import '../reports/models/report_content_type.dart';
import '../reports/report_service.dart';
import 'active_gig_theme.dart';

/// Shared "view someone's profile" drawer — avatar, name, verification
/// badge, rating, member-since date, bio, skills, an optional "recent
/// related completed gigs" section, and Report/Block actions. Used both from
/// the gig host's applicant list (gig_detail_sheet.dart) and the worker's
/// gig-listing preview (gig_map_section.dart), so it always looks and
/// behaves the same regardless of which side of a gig you're viewing from.
Future<void> showUserProfileSheet(
  BuildContext context, {
  required String uid,
  required String fallbackName,
  required String surface,
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
          })>(
        future: () async {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          final matches = matchSkillsForCompletedGigs.isEmpty
              ? <CompletedGigMatch>[]
              : await fetchSkillMatchedCompletedGigs(
                  uid,
                  matchSkillsForCompletedGigs,
                );
          return (userDoc: userDoc, matches: matches);
        }(),
        builder: (_, snap) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final onSurface = activeGigTextPrimary(isDark);
          final data = snap.data?.userDoc.data();
          final matchedGigs = snap.data?.matches ?? const [];
          final name = (data?['name'] as String?)?.trim().isNotEmpty == true
              ? data!['name'] as String
              : fallbackName;
          final photoUrl = data?['photoUrl'] as String? ?? '';
          final bio = data?['bio'] as String? ?? '';
          final skills = (data?['skills'] as List<dynamic>? ?? [])
              .map((s) => s.toString())
              .toList();
          final summary = RatingSummary.fromUserData(data, RateeRole.worker);
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                      Text(
                                        summary.label,
                                        style: const TextStyle(
                                          color: kSub,
                                          fontSize: 13,
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
                            if (currentUid != null && currentUid != uid) ...[
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
                                          contentType: ReportContentType.user,
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
                                        setSheetState(() => blocking = true);
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
                                      borderRadius: BorderRadius.circular(20),
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
                          ...matchedGigs.map(
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
                                        color: activeGigTextMuted(isDark),
                                        fontSize: 12.5,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    DateFormat('MMM d, y').format(
                                      g.completedAt,
                                    ),
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
  final String title;
  final DateTime completedAt;
  const CompletedGigMatch({required this.title, required this.completedAt});
}

// Up to the 3 most recent gigs this worker completed whose required skill(s)
// overlap with [requiredSkills] — shown on the profile sheet so a host can
// judge relevant experience at a glance. open_gigs carries a
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
  bool overlaps(Set<String> gigSkills) => gigSkills.any(wanted.contains);
  final results = <CompletedGigMatch>[];

  void collect(
    QuerySnapshot<Map<String, dynamic>> snap,
    Set<String> Function(Map<String, dynamic> data) skillsOf,
  ) {
    for (final doc in snap.docs) {
      final data = doc.data();
      if (!overlaps(skillsOf(data))) continue;
      final completedAt = (data['completedAt'] as Timestamp?)?.toDate();
      if (completedAt == null) continue;
      results.add(
        CompletedGigMatch(
          title: data['title'] as String? ?? '',
          completedAt: completedAt,
        ),
      );
    }
  }

  Set<String> openSkills(Map<String, dynamic> d) =>
      (d['requiredSkills'] as List<dynamic>? ?? [])
          .map((s) => s.toString().toLowerCase().trim())
          .toSet();
  Set<String> offeredSkills(Map<String, dynamic> d) {
    final s = (d['skillRequired'] as String? ?? '').toLowerCase().trim();
    return s.isEmpty ? const {} : {s};
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
  collect(snaps[0], openSkills);
  collect(snaps[1], offeredSkills);

  for (final doc in snaps[2].docs) {
    final slot = doc.data();
    final gigId = slot['gigId'] as String?;
    final gigCollection = slot['gigCollection'] as String?;
    if (gigId == null || gigCollection == null || gigCollection == 'quick_gigs') {
      continue;
    }
    final gigSnap = await db.collection(gigCollection).doc(gigId).get();
    final gigData = gigSnap.data();
    if (gigData == null) continue;
    final gigSkills = gigCollection == 'open_gigs'
        ? openSkills(gigData)
        : offeredSkills(gigData);
    if (!overlaps(gigSkills)) continue;
    final completedAt = (slot['completedAt'] as Timestamp?)?.toDate();
    if (completedAt == null) continue;
    results.add(
      CompletedGigMatch(
        title: gigData['title'] as String? ?? '',
        completedAt: completedAt,
      ),
    );
  }

  results.sort((a, b) => b.completedAt.compareTo(a.completedAt));
  return results.take(3).toList();
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

  const ProfileAvatar({
    super.key,
    required this.photoUrl,
    required this.name,
    required this.size,
  });

  Widget _initialsFallback() {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      decoration: const BoxDecoration(color: kBlue, shape: BoxShape.circle),
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
