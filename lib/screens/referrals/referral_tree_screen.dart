import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:giggre_app/core/utils/currency_formatter.dart';
import 'package:giggre_app/main.dart' show flavor;

// Everyone who joined through the signed-in user, and who they invited in
// turn, plus what that network has earned them. Built server-side by the
// getMyReferralTree Cloud Function (functions/src/referralTree.ts), since a
// user can only read their own referrals_list. Mirrors giggre-admin's
// Referral tree page.

// Callables live in the same region as the project's Firestore triggers
// (see functions/src/region.ts).
final _functionsRegion = flavor == 'prod' ? 'us-central1' : 'asia-east2';

// Referral rates are set in pesos in giggre-admin's Referral settings
const _currency = 'PHP';

/// Branches open by default down to this level
const _autoOpenDepth = 2;

const _blue = Color(0xFF2164F3);
const _purple = Color(0xFF7C3AED);
const _orange = Color(0xFFD97706);
const _green = Color(0xFF16A34A);
const _red = Color(0xFFDC2626);

class _TreeNode {
  _TreeNode({
    required this.uid,
    required this.name,
    required this.isVerified,
    required this.joinedMs,
    required this.depth,
    required this.gigDone,
  });

  final String uid;
  final String name;
  final bool isVerified;
  final int? joinedMs;
  final int depth;
  final bool gigDone;
  final List<_TreeNode> children = [];

  int get descendants => children.fold(0, (s, c) => s + 1 + c.descendants);
}

class _LevelEarning {
  _LevelEarning(Map<String, dynamic> d)
      : label = d['label'] as String? ?? '',
        rate = (d['rate'] as num?)?.toDouble() ?? 0,
        promoActive = d['promoActive'] == true,
        promoUntilMs = (d['promoUntilMs'] as num?)?.toInt(),
        people = (d['people'] as num?)?.toInt() ?? 0,
        qualified = (d['qualified'] as num?)?.toInt() ?? 0,
        earned = (d['earned'] as num?)?.toDouble() ?? 0,
        capped = d['capped'] == true,
        maxEarn = (d['maxEarn'] as num?)?.toDouble() ?? 0;

  final String label;
  final double rate;
  final bool promoActive;
  final int? promoUntilMs;
  final int people;
  final int qualified;
  final double earned;
  final bool capped;
  final double maxEarn;
}

class ReferralTreeScreen extends StatefulWidget {
  const ReferralTreeScreen({super.key});

  @override
  State<ReferralTreeScreen> createState() => _ReferralTreeScreenState();
}

class _ReferralTreeScreenState extends State<ReferralTreeScreen> {
  bool _loading = true;
  String? _error;

  String _rootName = '';
  String? _rootCode;
  bool _rootVerified = false;
  bool _rootGigDone = false;
  List<_TreeNode> _tree = [];
  List<int> _levelCounts = [];
  bool _truncated = false;

  List<_LevelEarning>? _earnings;
  double _totalEarned = 0;
  double _totalMax = 0;
  bool _totalCapped = false;
  int _deeperPeople = 0;

  /// Branches toggled away from their default open/closed state
  final Set<String> _toggled = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _tree.isEmpty;
      _error = null;
    });
    try {
      final result = await FirebaseFunctions.instanceFor(region: _functionsRegion)
          .httpsCallable('getMyReferralTree')
          .call();
      final data = Map<String, dynamic>.from(result.data as Map);
      _apply(data);
    } catch (e) {
      debugPrint('[ReferralTree] load failed: $e');
      if (mounted) {
        setState(() => _error = "Couldn't load your referral tree. Pull down to try again.");
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _apply(Map<String, dynamic> data) {
    final root = Map<String, dynamic>.from(data['root'] as Map? ?? {});
    final members = (data['members'] as List? ?? [])
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();

    // Link everyone under their referrer, oldest first
    final nodes = <String, _TreeNode>{};
    final referrerOf = <String, String>{};
    for (final m in members) {
      final uid = m['uid'] as String;
      nodes[uid] = _TreeNode(
        uid: uid,
        name: m['name'] as String? ?? 'Giggre user',
        isVerified: m['isVerified'] == true,
        joinedMs: (m['joinedMs'] as num?)?.toInt(),
        depth: (m['depth'] as num?)?.toInt() ?? 1,
        gigDone: m['gigDone'] == true,
      );
      referrerOf[uid] = m['referrerId'] as String? ?? '';
    }
    final tree = <_TreeNode>[];
    for (final n in nodes.values) {
      final parent = nodes[referrerOf[n.uid]];
      (parent?.children ?? tree).add(n);
    }
    int byJoined(_TreeNode a, _TreeNode b) => (a.joinedMs ?? 0).compareTo(b.joinedMs ?? 0);
    void sortAll(List<_TreeNode> list) {
      list.sort(byJoined);
      for (final n in list) {
        sortAll(n.children);
      }
    }
    sortAll(tree);

    final counts = <int>[];
    for (final n in nodes.values) {
      while (counts.length < n.depth) {
        counts.add(0);
      }
      counts[n.depth - 1]++;
    }

    final earnings = data['earnings'] == null
        ? null
        : Map<String, dynamic>.from(data['earnings'] as Map);

    setState(() {
      _rootName = root['name'] as String? ?? 'You';
      _rootCode = root['referralCode'] as String?;
      _rootVerified = root['isVerified'] == true;
      _rootGigDone = root['gigDone'] == true;
      _tree = tree;
      _levelCounts = counts;
      _truncated = data['truncated'] == true;
      _earnings = earnings == null
          ? null
          : (earnings['levels'] as List? ?? [])
              .map((l) => _LevelEarning(Map<String, dynamic>.from(l as Map)))
              .toList();
      _totalEarned = (earnings?['total'] as num?)?.toDouble() ?? 0;
      _totalMax = (earnings?['totalMax'] as num?)?.toDouble() ?? 0;
      _totalCapped = earnings?['totalCapped'] == true;
      _deeperPeople = (earnings?['deeperPeople'] as num?)?.toInt() ?? 0;
      _toggled.clear();
    });
  }

  String _money(double n) => CurrencyFormatter.format(n, _currency);

  String _levelName(int i) => switch (i) {
        0 => 'Invited directly',
        _ => 'Level ${i + 1}',
      };

  String? _fmtDate(int? ms) {
    if (ms == null) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  bool _isOpen(_TreeNode n) => (n.depth < _autoOpenDepth) != _toggled.contains(n.uid);

  void _toggle(String uid) => setState(() {
        if (!_toggled.remove(uid)) _toggled.add(uid);
      });

  void _setAll(bool open) {
    // Express "everything open/closed" as toggles relative to each default
    final next = <String>{};
    void walk(List<_TreeNode> nodes) {
      for (final n in nodes) {
        if (n.children.isNotEmpty && (n.depth < _autoOpenDepth) != open) next.add(n.uid);
        walk(n.children);
      }
    }
    walk(_tree);
    setState(() => _toggled
      ..clear()
      ..addAll(next));
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? const Color(0xFF90CAF9) : _blue;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: const Text(
          'Referral Tree',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                color: primaryColor,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    if (_error != null) _errorBanner(),
                    _summary(),
                    const SizedBox(height: 16),
                    _earningsCard(),
                    const SizedBox(height: 16),
                    _treeCard(),
                  ],
                ),
              ),
      ),
    );
  }

  // ── Pieces ────────────────────────────────────────────────────────────────

  Color get _cardColor =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1E1E) : Colors.white;

  Color get _onSurface => Theme.of(context).colorScheme.onSurface;

  BoxDecoration _cardDecoration() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: _cardColor,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Widget _errorBanner() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _red.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _red.withOpacity(0.25)),
        ),
        child: Text(_error!, style: const TextStyle(color: _red, fontSize: 13)),
      );

  Widget _summary() {
    Widget stat(String value, String label, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: _cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color ?? _onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: _onSurface.withOpacity(0.5)),
                ),
              ],
            ),
          ),
        );

    return Row(
      children: [
        stat(_earnings == null ? '—' : _money(_totalEarned), 'Referral earnings', color: _green),
      ],
    );
  }

  Widget _earningsCard() {
    final earnings = _earnings;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Referral earnings',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _onSurface),
          ),
          const SizedBox(height: 12),
          if (earnings == null)
            Text(
              "Referral rates haven't been set up yet.",
              style: TextStyle(fontSize: 13, color: _onSurface.withOpacity(0.5)),
            )
          else ...[
            for (final e in earnings) _earningRow(e),
            Divider(color: _onSurface.withOpacity(0.12), height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _onSurface),
                  ),
                ),
                Text(
                  _money(_totalEarned),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _green),
                ),
              ],
            ),
            if (_totalMax > 0) ...[
              const SizedBox(height: 8),
              _limitBar(_totalEarned, _totalMax, reachedLabel: 'Total limit reached'),
            ],
            if (_earningsNotes(earnings).isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _earningsNotes(earnings),
                style: TextStyle(fontSize: 11, color: _onSurface.withOpacity(0.5), height: 1.5),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _earningsNotes(List<_LevelEarning> earnings) => [
        if (earnings.any((e) => e.capped)) 'Levels that hit their limit stop earning more.',
        if (_totalCapped) 'Your total is capped at ${_money(_totalMax)}.',
        if (_deeperPeople > 0)
          '$_deeperPeople ${_deeperPeople == 1 ? 'person' : 'people'} deeper than '
              '${_levelName(earnings.length - 1)} earn nothing.',
      ].join(' ');

  Widget _earningRow(_LevelEarning e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e.label,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _onSurface),
                ),
              ),
              Text(
                _money(e.earned),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _green),
              ),
            ],
          ),
          if (e.promoActive) ...[
            const SizedBox(height: 4),
            _pill(
              e.promoUntilMs != null ? 'Promo until ${_fmtDate(e.promoUntilMs)}' : 'Promo',
              _blue,
            ),
          ],
          if (e.maxEarn > 0) ...[
            const SizedBox(height: 6),
            _limitBar(e.earned, e.maxEarn, reachedLabel: 'Limit reached', reached: e.capped || e.earned >= e.maxEarn),
          ],
        ],
      ),
    );
  }

  Widget _limitBar(double earned, double max, {required String reachedLabel, bool? reached}) {
    final isReached = reached ?? earned >= max;
    final color = isReached ? _orange : _green;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              isReached ? reachedLabel : '${_money(max - earned)} left',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
            ),
            const Spacer(),
            Text(
              'of ${_money(max)}',
              style: TextStyle(fontSize: 11, color: _onSurface.withOpacity(0.45)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: max > 0 ? (earned / max).clamp(0.0, 1.0) : 0,
            minHeight: 4,
            backgroundColor: _onSurface.withOpacity(0.08),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  Widget _treeCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your network',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _onSurface),
                ),
              ),
              if (_tree.isNotEmpty) ...[
                _textButton('Expand all', () => _setAll(true)),
                const SizedBox(width: 6),
                _textButton('Collapse all', () => _setAll(false)),
              ],
            ],
          ),
          if (_levelCounts.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              [for (var i = 0; i < _levelCounts.length; i++) '${_levelName(i)}: ${_levelCounts[i]}']
                  .join(' · '),
              style: TextStyle(fontSize: 11, color: _onSurface.withOpacity(0.5)),
            ),
          ],
          const SizedBox(height: 14),
          _rootRow(),
          if (_tree.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  "You haven't invited anyone yet.\nShare your referral code to grow your network.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: _onSurface.withOpacity(0.5), height: 1.5),
                ),
              ),
            )
          else
            _children(_tree),
          if (_truncated)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Your network is very large — only part of it is shown.',
                style: TextStyle(fontSize: 11, color: _onSurface.withOpacity(0.5)),
              ),
            ),
          if (_tree.isNotEmpty) ...[
            const SizedBox(height: 16),
            _legend(),
          ],
        ],
      ),
    );
  }

  Widget _textButton(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _onSurface.withOpacity(0.15)),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _onSurface.withOpacity(0.7)),
          ),
        ),
      );

  Widget _rootRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _blue.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _avatar(_rootVerified),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '$_rootName (you)',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _onSurface),
            ),
          ),
          if (_rootCode != null) ...[
            const SizedBox(width: 8),
            Text(
              _rootCode!,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: _onSurface.withOpacity(0.5),
              ),
            ),
          ],
          const SizedBox(width: 8),
          _gigBadge(_rootGigDone),
        ],
      ),
    );
  }

  /// One level of the tree, hanging off a vertical connector line
  Widget _children(List<_TreeNode> nodes) {
    return Container(
      margin: const EdgeInsets.only(left: 14),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: _onSurface.withOpacity(0.12))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final n in nodes) _nodeItem(n)],
      ),
    );
  }

  Widget _nodeItem(_TreeNode n) {
    final open = _isOpen(n);
    final hasChildren = n.children.isNotEmpty;
    final date = _fmtDate(n.joinedMs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: hasChildren ? () => _toggle(n.uid) : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: hasChildren
                      ? Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: _onSurface.withOpacity(0.15)),
                          ),
                          child: AnimatedRotation(
                            turns: open ? 0.25 : 0,
                            duration: const Duration(milliseconds: 250),
                            child: Icon(Icons.chevron_right_rounded, size: 16, color: _onSurface.withOpacity(0.6)),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 6),
                _avatar(n.isVerified),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _onSurface),
                      ),
                      if (date != null || hasChildren)
                        Text(
                          [
                            if (date != null) 'Joined $date',
                            if (hasChildren) '${n.descendants} below',
                          ].join(' · '),
                          style: TextStyle(fontSize: 10.5, color: _onSurface.withOpacity(0.45)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _levelChip(n.depth),
                const SizedBox(width: 6),
                _gigBadge(n.gigDone),
              ],
            ),
          ),
        ),
        if (hasChildren)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: Alignment.topLeft,
            child: open ? _children(n.children) : const SizedBox(width: double.infinity),
          ),
      ],
    );
  }

  Widget _avatar(bool verified) => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: verified ? _blue.withOpacity(0.12) : _onSurface.withOpacity(0.06),
        ),
        child: Icon(
          verified ? Icons.verified_rounded : Icons.person_rounded,
          size: 14,
          color: verified ? _blue : _onSurface.withOpacity(0.45),
        ),
      );

  Widget _levelChip(int depth) {
    final color = switch (depth) {
      1 => _blue,
      2 => _purple,
      3 => _orange,
      _ => _onSurface.withOpacity(0.45),
    };
    return _pill('L$depth', color);
  }

  Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.6)),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color),
        ),
      );

  Widget _gigBadge(bool done) => Tooltip(
        message: done ? 'Completed at least 1 gig' : 'No completed gigs yet',
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (done ? _green : _red).withOpacity(0.12),
          ),
          child: Icon(
            done ? Icons.check_rounded : Icons.close_rounded,
            size: 13,
            color: done ? _green : _red,
          ),
        ),
      );

  Widget _legend() {
    final style = TextStyle(fontSize: 11, color: _onSurface.withOpacity(0.5));
    Widget item(Widget icon, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [icon, const SizedBox(width: 4), Text(label, style: style)],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        item(const Icon(Icons.verified_rounded, size: 13, color: _blue), 'Verified'),
        item(_gigBadge(true), 'Completed a gig'),
        item(_gigBadge(false), 'None yet'),
        item(_levelChip(1), 'Invited by you'),
        item(_levelChip(2), 'Invited by your referral'),
        Text('Tap a person to show or hide who they invited', style: style),
      ],
    );
  }
}
