import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Toolchest Sheet — read-only list of skills awarded by admin
// ─────────────────────────────────────────────────────────────────────────────
class ToolchestSheet extends StatefulWidget {
  final String uid;

  const ToolchestSheet({super.key, required this.uid});

  static void show(BuildContext context, String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ToolchestSheet(uid: uid),
    );
  }

  @override
  State<ToolchestSheet> createState() => _ToolchestSheetState();
}

class _ToolchestSheetState extends State<ToolchestSheet> {
  List<String> _userSkills = [];
  StreamSubscription? _userSub;

  @override
  void initState() {
    super.initState();
    _listenToUserSkills();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }

  void _listenToUserSkills() {
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final skills = List<String>.from(snap.data()?['skills'] ?? []);
      setState(() => _userSkills = skills);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final divider = Theme.of(context).dividerColor;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            // ── Drag handle ──────────────────────────────────────────
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

            // ── Header ───────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kAmber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.construction_rounded,
                      color: kAmber, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Toolchest',
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Skills awarded by admin',
                      style: TextStyle(color: kSub, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Skills list ──────────────────────────────────────────
            Text(
              'YOUR SKILLS',
              style: const TextStyle(
                color: kSub,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),

            if (_userSkills.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: divider),
                ),
                child: const Center(
                  child: Text(
                    'No skills awarded yet.\nComplete gigs to earn skills from admin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kSub, fontSize: 13, height: 1.5),
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _userSkills
                    .map((skill) => _SkillChip(label: skill))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Read-only skill chip
// ─────────────────────────────────────────────────────────────────────────────
class _SkillChip extends StatelessWidget {
  final String label;

  const _SkillChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: kAmber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kAmber.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: kAmber,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
