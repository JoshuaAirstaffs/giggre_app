import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Settings → Blocked Users — lists everyone the current user has blocked
/// (their own `users/{uid}.blockedUsers` array) with an Unblock action per
/// row. Reachable from both WorkerSettingsScreen and the host profile's
/// inline Settings section.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  Set<String> _unblocking = {};

  Future<void> _unblock(String blockedUid) async {
    if (_uid.isEmpty) return;
    setState(() => _unblocking = {..._unblocking, blockedUid});
    try {
      await FirebaseFirestore.instance.collection('users').doc(_uid).update({
        'blockedUsers': FieldValue.arrayRemove([blockedUid]),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not unblock this user. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _unblocking = {..._unblocking}..remove(blockedUid));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: onSurface,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Blocked Users',
          style: TextStyle(
            color: onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: isDark ? kBorder : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      body: _uid.isEmpty
          ? const SizedBox.shrink()
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(_uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final blockedIds =
                    (snap.data?.data()?['blockedUsers'] as List<dynamic>? ??
                            [])
                        .map((e) => e.toString())
                        .toList();

                if (blockedIds.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.block_rounded,
                            size: 40,
                            color: kSub.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No blocked users',
                            style: TextStyle(
                              color: onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            "People you block will show up here so you can unblock them anytime.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: kSub, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return FutureBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
                  future: Future.wait(
                    blockedIds.map(
                      (id) => FirebaseFirestore.instance
                          .collection('users')
                          .doc(id)
                          .get(),
                    ),
                  ),
                  builder: (context, userSnap) {
                    if (userSnap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = userSnap.data ?? [];
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: docs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final data = doc.data();
                        final name = data?['name'] as String? ?? 'User';
                        final photoUrl = data?['photoUrl'] as String? ?? '';
                        final isUnblocking = _unblocking.contains(doc.id);

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: kBlue.withValues(alpha: 0.15),
                                backgroundImage: photoUrl.isNotEmpty
                                    ? NetworkImage(photoUrl)
                                    : null,
                                child: photoUrl.isEmpty
                                    ? Text(
                                        name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          color: kBlue,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    color: onSurface,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton(
                                onPressed: isUnblocking
                                    ? null
                                    : () => _unblock(doc.id),
                                child: isUnblocking
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Unblock'),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}
