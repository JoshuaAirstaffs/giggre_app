import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/delete_acc_service.dart';
import 'widgets/worker_widgets.dart';

class WorkerSettingsScreen extends StatefulWidget {
  const WorkerSettingsScreen({super.key});

  @override
  State<WorkerSettingsScreen> createState() => _WorkerSettingsScreenState();
}

class _WorkerSettingsScreenState extends State<WorkerSettingsScreen> {
  final _db = FirebaseFirestore.instance;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  // Worker quick-gig status
  int _declineCount = 0;
  DateTime? _suspendedUntil;

  // Admin config
  Map<String, dynamic>? _suspensionConfig;
  Map<String, dynamic>? _matchingConfig;

  bool _loading = true;
  StreamSubscription? _profileSub;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _subscribeProfile();
    _fetchAdminConfig();
  }

  void _subscribeProfile() {
    if (_uid.isEmpty) return;
    _profileSub = _db.collection('users').doc(_uid).snapshots().listen((doc) {
      final data = doc.data() ?? {};
      final count = (data['decline_count'] as num?)?.toInt() ?? 0;
      final ts = data['suspended_until'] as Timestamp?;
      DateTime? until;
      if (ts != null) {
        final dt = ts.toDate();
        if (dt.isAfter(DateTime.now())) until = dt;
      }
      if (!mounted) return;
      setState(() {
        _declineCount = count;
        _suspendedUntil = until;
      });
      if (until != null) _startCountdown();
    }, onError: (_) {});
  }

  Future<void> _fetchAdminConfig() async {
    try {
      final results = await Future.wait([
        _db.collection('quick_gig_config').doc('decline_suspension').get(),
        _db.collection('quick_gig_config').doc('matching_engine').get(),
      ]);
      if (!mounted) return;
      setState(() {
        _suspensionConfig = results[0].data();
        _matchingConfig = results[1].data();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_suspendedUntil == null || DateTime.now().isAfter(_suspendedUntil!)) {
        _countdownTimer?.cancel();
        setState(() => _suspendedUntil = null);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _formatRemaining(DateTime until) {
    final diff = until.difference(DateTime.now());
    if (diff.isNegative) return 'Expired';
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    final s = diff.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
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
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: onSurface, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
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
              color: isDark ? kBorder : const Color(0xFFE2E8F0)),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kAmber))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 8),

                // ── Quick Gig Status ──────────────────────────────
                const SectionLabel('QUICK GIG STATUS'),
                const SizedBox(height: 8),
                _QuickGigStatusCard(
                  declineCount: _declineCount,
                  freeDeclineLimit: (_suspensionConfig?['free_decline_limit']
                          as num?)
                      ?.toInt() ??
                      0,
                  suspendedUntil: _suspendedUntil,
                  formatRemaining: _formatRemaining,
                ),
                const SizedBox(height: 24),

                // ── Gig Rules ─────────────────────────────────────
                const SectionLabel('GIG RULES (ADMIN CONFIG)'),
                const SizedBox(height: 8),
                _ConfigSection(
                  suspensionConfig: _suspensionConfig,
                  matchingConfig: _matchingConfig,
                ),
                const SizedBox(height: 24),

                // ── Account ───────────────────────────────────────
                const SectionLabel('ACCOUNT'),
                const SizedBox(height: 8),
                MenuCard(children: [
                  MenuRow(
                    icon: Icons.delete_outline_rounded,
                    iconColor: Colors.redAccent,
                    label: 'Delete Account',
                    labelColor: Colors.redAccent,
                    onTap: () => DeleteAccountService.deleteAccount(context),
                    showArrow: false,
                  ),
                ]),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Deleting your account is permanent and cannot be undone. All your data, including your worker profile, will be removed from Giggre.',
                    style: const TextStyle(
                        color: kSub, fontSize: 12, height: 1.6),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Quick Gig Status Card
// ─────────────────────────────────────────────────────────────────────────────
class _QuickGigStatusCard extends StatelessWidget {
  final int declineCount;
  final int freeDeclineLimit;
  final DateTime? suspendedUntil;
  final String Function(DateTime) formatRemaining;

  const _QuickGigStatusCard({
    required this.declineCount,
    required this.freeDeclineLimit,
    required this.suspendedUntil,
    required this.formatRemaining,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final isSuspended =
        suspendedUntil != null && DateTime.now().isBefore(suspendedUntil!);

    final declinesFree = freeDeclineLimit > 0
        ? '$declineCount / $freeDeclineLimit free'
        : '$declineCount';
    final declinesOver =
        freeDeclineLimit > 0 && declineCount > freeDeclineLimit;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSuspended
              ? Colors.redAccent.withValues(alpha: 0.4)
              : kSub.withValues(alpha: 0.12),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Decline count row
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (declinesOver ? Colors.orangeAccent : kAmber)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.remove_circle_outline_rounded,
                    color:
                        declinesOver ? Colors.orangeAccent : kAmber,
                    size: 17),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Decline Count',
                        style: TextStyle(color: kSub, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(declinesFree,
                        style: TextStyle(
                            color: declinesOver
                                ? Colors.orangeAccent
                                : Theme.of(context).colorScheme.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              if (freeDeclineLimit > 0)
                _DeclineBar(count: declineCount, limit: freeDeclineLimit),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: kSub.withValues(alpha: 0.12), height: 1),
          const SizedBox(height: 12),
          // Suspension status row
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (isSuspended ? Colors.redAccent : Colors.greenAccent)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  isSuspended
                      ? Icons.lock_clock_rounded
                      : Icons.check_circle_outline_rounded,
                  color: isSuspended ? Colors.redAccent : Colors.greenAccent,
                  size: 17,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Suspension',
                        style: TextStyle(color: kSub, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(
                      isSuspended
                          ? 'Suspended — ${formatRemaining(suspendedUntil!)}'
                          : 'Not suspended',
                      style: TextStyle(
                          color: isSuspended
                              ? Colors.redAccent
                              : Colors.greenAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Decline progress bar
// ─────────────────────────────────────────────────────────────────────────────
class _DeclineBar extends StatelessWidget {
  final int count;
  final int limit;
  const _DeclineBar({required this.count, required this.limit});

  @override
  Widget build(BuildContext context) {
    final progress = (count / limit).clamp(0.0, 1.0);
    final color = progress >= 1.0
        ? Colors.redAccent
        : progress >= 0.6
            ? Colors.orangeAccent
            : Colors.greenAccent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('${(progress * 100).toInt()}%',
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          width: 60,
          height: 6,
          decoration: BoxDecoration(
            color: kSub.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Config Section — decline/suspension + matching engine
// ─────────────────────────────────────────────────────────────────────────────
class _ConfigSection extends StatelessWidget {
  final Map<String, dynamic>? suspensionConfig;
  final Map<String, dynamic>? matchingConfig;

  const _ConfigSection({
    required this.suspensionConfig,
    required this.matchingConfig,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ConfigCard(
          icon: Icons.block_rounded,
          iconColor: Colors.redAccent,
          title: 'Decline & Suspension',
          rows: _buildSuspensionRows(context),
        ),
        const SizedBox(height: 12),
        _ConfigCard(
          icon: Icons.settings_suggest_rounded,
          iconColor: kBlue,
          title: 'Matching Engine',
          rows: _buildMatchingRows(context),
        ),
      ],
    );
  }

  List<Widget> _buildSuspensionRows(BuildContext context) {
    final d = suspensionConfig;
    if (d == null) return [_noData()];

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
        const SizedBox(height: 10),
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

  List<Widget> _buildMatchingRows(BuildContext context) {
    final d = matchingConfig;
    if (d == null) return [_noData()];

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

  Widget _noData() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child:
            Text('No config available', style: TextStyle(color: kSub, fontSize: 12)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Config Card
// ─────────────────────────────────────────────────────────────────────────────
class _ConfigCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<Widget> rows;

  const _ConfigCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.rows,
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
              Icon(icon, color: iconColor, size: 15),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      color: onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),
          ...rows,
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
                  style: const TextStyle(color: kSub, fontSize: 12))),
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
