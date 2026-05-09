import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/app_colors.dart';

class AdminGigConfigSheet extends StatefulWidget {
  const AdminGigConfigSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AdminGigConfigSheet(),
    );
  }

  @override
  State<AdminGigConfigSheet> createState() => _AdminGigConfigSheetState();
}

class _AdminGigConfigSheetState extends State<AdminGigConfigSheet> {
  final _db = FirebaseFirestore.instance;

  Map<String, dynamic>? _suspension;
  Map<String, dynamic>? _matching;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchConfigs();
  }

  Future<void> _fetchConfigs() async {
    try {
      final results = await Future.wait([
        _db.collection('quick_gig_config').doc('decline_suspension').get(),
        _db.collection('quick_gig_config').doc('matching_engine').get(),
      ]);
      if (!mounted) return;
      setState(() {
        _suspension = results[0].data();
        _matching = results[1].data();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: kSub.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: kAmber.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.tune_rounded, color: kAmber, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Gig Config',
                          style: TextStyle(
                              color: onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      const Text('Admin-managed settings',
                          style: TextStyle(color: kSub, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Divider(color: kSub.withValues(alpha: 0.15), height: 1),
            // Body
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: kAmber))
                  : _error != null
                      ? Center(
                          child: Text('Failed to load config',
                              style: TextStyle(color: kSub, fontSize: 13)))
                      : ListView(
                          controller: controller,
                          padding: const EdgeInsets.all(20),
                          children: [
                            _SectionCard(
                              icon: Icons.block_rounded,
                              iconColor: Colors.redAccent,
                              title: 'Decline & Suspension',
                              children: _buildSuspensionRows(),
                            ),
                            const SizedBox(height: 16),
                            _SectionCard(
                              icon: Icons.settings_suggest_rounded,
                              iconColor: kBlue,
                              title: 'Matching Engine',
                              children: _buildMatchingRows(),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSuspensionRows() {
    final d = _suspension;
    if (d == null) return [const _EmptyRow()];

    final freeLimit = d['free_decline_limit'];
    final enabled = d['suspension_enabled'];
    final tiers = d['suspension_tier_table'] as List<dynamic>? ?? [];

    return [
      _ConfigRow(
        label: 'Free Decline Limit',
        value: freeLimit?.toString() ?? '—',
        icon: Icons.remove_circle_outline_rounded,
        iconColor: Colors.orangeAccent,
      ),
      _ConfigRow(
        label: 'Suspension Enabled',
        value: enabled == true ? 'Yes' : 'No',
        icon: enabled == true
            ? Icons.check_circle_outline_rounded
            : Icons.cancel_outlined,
        iconColor: enabled == true ? Colors.greenAccent : kSub,
      ),
      if (tiers.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text('Suspension Tiers',
            style: TextStyle(
                color: kSub, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ...tiers.asMap().entries.map((e) {
          final tier = e.value as Map<dynamic, dynamic>;
          final trigger = tier['decline_count_trigger'];
          final duration = tier['suspension_duration_minutes'];
          return _TierRow(
            tier: e.key + 1,
            trigger: trigger?.toString() ?? '—',
            duration: duration?.toString() ?? '—',
          );
        }),
      ],
    ];
  }

  List<Widget> _buildMatchingRows() {
    final d = _matching;
    if (d == null) return [const _EmptyRow()];

    final reassignment = d['allow_reassignment_after_exhaustion'];
    final maxAttempts = d['max_dispatch_attempts'];
    final maxRadius = d['max_search_radius_km'];
    final reviewWindow = d['review_window_seconds'];
    final timeout = d['search_timeout_minutes'];

    return [
      _ConfigRow(
        label: 'Allow Reassignment',
        value: reassignment == true ? 'Yes' : 'No',
        icon: reassignment == true
            ? Icons.check_circle_outline_rounded
            : Icons.cancel_outlined,
        iconColor: reassignment == true ? Colors.greenAccent : kSub,
      ),
      _ConfigRow(
        label: 'Max Dispatch Attempts',
        value: maxAttempts?.toString() ?? '—',
        icon: Icons.repeat_rounded,
        iconColor: kBlue,
      ),
      _ConfigRow(
        label: 'Max Search Radius (km)',
        value: maxRadius != null ? maxRadius.toString() : 'Unlimited',
        icon: Icons.radar_rounded,
        iconColor: Colors.tealAccent,
      ),
      _ConfigRow(
        label: 'Review Window (sec)',
        value: reviewWindow?.toString() ?? '—',
        icon: Icons.timer_outlined,
        iconColor: Colors.purpleAccent,
      ),
      _ConfigRow(
        label: 'Search Timeout (min)',
        value: timeout?.toString() ?? '—',
        icon: Icons.hourglass_bottom_rounded,
        iconColor: Colors.orangeAccent,
      ),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Section Card
// ─────────────────────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kSub.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      color: onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Config Row
// ─────────────────────────────────────────────────────────────────────────────
class _ConfigRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  const _ConfigRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: const TextStyle(color: kSub, fontSize: 12)),
          ),
          Text(value,
              style: TextStyle(
                  color: onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tier Row
// ─────────────────────────────────────────────────────────────────────────────
class _TierRow extends StatelessWidget {
  final int tier;
  final String trigger;
  final String duration;

  const _TierRow({
    required this.tier,
    required this.trigger,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tierBg = isDark
        ? Colors.redAccent.withValues(alpha: 0.08)
        : Colors.redAccent.withValues(alpha: 0.05);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tierBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('$tier',
                  style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('After $trigger declines',
                style: const TextStyle(color: kSub, fontSize: 11)),
          ),
          Text('$duration min suspension',
              style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Empty Row
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyRow extends StatelessWidget {
  const _EmptyRow();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No config available',
            style: TextStyle(color: kSub, fontSize: 12)),
      ),
    );
  }
}