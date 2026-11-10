import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../main.dart' show flavor;
import '../tutorial_videos/tutorial_region.dart';

/// Profile → Settings → Promo Code. Redeems a code made in giggre-admin →
/// Promotions (functions/src/promos.ts → redeemPromoCode) and lists the
/// user's gig cashback vouchers.
class PromoCodeScreen extends StatefulWidget {
  const PromoCodeScreen({super.key});

  @override
  State<PromoCodeScreen> createState() => _PromoCodeScreenState();
}

class _PromoCodeScreenState extends State<PromoCodeScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  static final _region = flavor == 'prod' ? 'us-central1' : 'asia-east2';

  @override
  void initState() {
    super.initState();
    TutorialRegion.ensure(context); // ₱ or $ wording for listed promos
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _redeemCode(String code) async {
    _ctrl.text = code;
    await _redeem();
  }

  Future<void> _redeem() async {
    final code = _ctrl.text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (code.isEmpty) {
      setState(() => _error = 'Enter a promo code.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await FirebaseFunctions.instanceFor(region: _region)
          .httpsCallable('redeemPromoCode')
          .call({'code': code});
      final data = Map<String, dynamic>.from(res.data as Map);
      if (!mounted) return;
      _ctrl.clear();
      await _showSuccess(data);
    } on FirebaseFunctionsException catch (e) {
      setState(() => _error = switch (e.code) {
            'not-found' || 'already-exists' || 'failed-precondition' =>
              e.message ?? 'This promo code can\'t be used.',
            'unauthenticated' => 'Please sign in again to use a promo code.',
            _ => 'Couldn\'t redeem the code right now. Please try again.',
          });
    } catch (_) {
      setState(() => _error = 'Couldn\'t redeem the code right now. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showSuccess(Map<String, dynamic> d) {
    final type = d['type'] as String?;
    final icon = switch (type) {
      'gig_points' => Icons.stars_rounded,
      'wallet_credit' => Icons.account_balance_wallet_rounded,
      _ => Icons.local_offer_rounded,
    };
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: kGold.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, color: kGold, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              (d['name'] as String?) ?? 'Promo applied',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Theme.of(ctx).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              (d['message'] as String?) ?? 'Your promo code was applied.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: kSub, fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Great!')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final card = Theme.of(context).cardColor;
    final divider = Theme.of(context).dividerColor;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text('Promo Code', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Have a promo code?',
              style: TextStyle(color: onSurface, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
            'Enter it below to get Gig Points, Gig Wallet credit or a cashback voucher.',
            style: TextStyle(color: kSub, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_\- ]')),
              LengthLimitingTextInputFormatter(30),
            ],
            onSubmitted: (_) => _redeem(),
            style: TextStyle(color: onSurface, fontSize: 16, letterSpacing: 1.5, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'e.g. GIG-7KQ2XM',
              hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.35), letterSpacing: 0),
              filled: true,
              fillColor: card,
              prefixIcon: const Icon(Icons.local_offer_outlined, color: kGold),
              errorText: _error,
              errorMaxLines: 3,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: divider)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: divider)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kGold, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _busy ? null : _redeem,
              style: ElevatedButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Redeem', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 28),
          if (uid != null) _OffersList(uid: uid, busy: _busy, onRedeem: _redeemCode),
          _PublicPromosList(busy: _busy, onRedeem: _redeemCode),
          if (uid != null) _VoucherList(uid: uid),
        ],
      ),
    );
  }
}

/// The user's gig cashback vouchers (promo_vouchers where uid == me).
class _VoucherList extends StatelessWidget {
  final String uid;
  const _VoucherList({required this.uid});

  String _money(num v, String ccy) =>
      NumberFormat.currency(symbol: ccy == 'PHP' ? '₱' : '\$', decimalDigits: v % 1 == 0 ? 0 : 2).format(v);

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('promo_vouchers').where('uid', isEqualTo: uid).snapshots(),
      builder: (context, snap) {
        final docs = [...?snap.data?.docs];
        if (docs.isEmpty) return const SizedBox.shrink();
        int ms(dynamic t) => t is Timestamp ? t.millisecondsSinceEpoch : 0;
        docs.sort((a, b) => ms(b.data()['createdAt']).compareTo(ms(a.data()['createdAt'])));
        final now = DateTime.now().millisecondsSinceEpoch;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My cashback vouchers',
                style: TextStyle(color: onSurface, fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Used automatically on your next completed gig as a host.',
              style: TextStyle(color: kSub, fontSize: 12),
            ),
            const SizedBox(height: 12),
            for (final d in docs) _tile(context, d.data(), now, ms),
          ],
        );
      },
    );
  }

  Widget _tile(BuildContext context, Map<String, dynamic> v, int now, int Function(dynamic) ms) {
    final ccy = (v['currencyCode'] as String?) ?? 'USD';
    final used = v['status'] == 'used';
    final expired = !used && ms(v['expiresAt']) < now;
    final what = v['mode'] == 'fixed'
        ? '${_money((v['amount'] as num?) ?? 0, ccy)} cashback'
        : '${v['percent']}% cashback (up to ${_money((v['maxCashback'] as num?) ?? 0, ccy)})';
    final expires = v['expiresAt'] is Timestamp
        ? DateFormat('MMM d, y').format((v['expiresAt'] as Timestamp).toDate())
        : null;
    final status = used
        ? 'Paid ${_money((v['cashbackAmount'] as num?) ?? 0, ccy)} to your wallet'
        : expired
            ? 'Expired'
            : expires != null
                ? 'Active · use by $expires'
                : 'Active';
    final color = used ? Colors.green : expired ? kSub : kGold;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(used ? Icons.check_circle_rounded : Icons.local_offer_rounded, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(what,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    )),
                const SizedBox(height: 2),
                Text('${v['promoCode'] ?? ''} · $status', style: const TextStyle(color: kSub, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── "For you" (promo_offers) and "Available promos" (promo_public) ──────────

Widget _promoTile(
  BuildContext context, {
  required String code,
  required String title,
  required String subtitle,
  String? note,
  required IconData icon,
  required Color color,
  required bool busy,
  required Future<void> Function(String) onRedeem,
}) {
  final onSurface = Theme.of(context).colorScheme.onSurface;
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
    decoration: BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: onSurface, fontWeight: FontWeight.w600, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: kSub, fontSize: 12)),
              if (note != null && note.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(note, style: const TextStyle(color: kSub, fontSize: 12, fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 4),
              Text(code, style: TextStyle(color: onSurface, fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        TextButton(
          onPressed: busy ? null : () => onRedeem(code),
          child: const Text('Use', style: TextStyle(fontWeight: FontWeight.bold, color: kGold)),
        ),
      ],
    ),
  );
}

String? _until(dynamic endsAt) =>
    endsAt is Timestamp ? 'Until ${DateFormat('MMM d, y').format(endsAt.toDate())}' : null;

/// Codes delivered to this user — private group sends and restricted codes.
class _OffersList extends StatelessWidget {
  final String uid;
  final bool busy;
  final Future<void> Function(String) onRedeem;
  const _OffersList({required this.uid, required this.busy, required this.onRedeem});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('promo_offers').where('uid', isEqualTo: uid).snapshots(),
      builder: (context, snap) {
        final now = DateTime.now();
        final docs = [...?snap.data?.docs].where((d) {
          final x = d.data();
          if (x['redeemed'] == true) return false;
          final end = x['endsAt'];
          return end is! Timestamp || end.toDate().isAfter(now);
        }).toList();
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('For you', style: TextStyle(color: onSurface, fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            for (final d in docs)
              _promoTile(
                context,
                code: (d.data()['code'] as String?) ?? '',
                title: (d.data()['name'] as String?) ?? 'Promo',
                subtitle: [
                  (d.data()['rewardText'] as String?) ?? '',
                  if (d.data()['access'] == 'restricted') 'Just for you',
                  ?_until(d.data()['endsAt']),
                ].where((t) => t.isNotEmpty).join(' · '),
                note: d.data()['note'] as String?,
                icon: d.data()['access'] == 'restricted' ? Icons.workspace_premium_rounded : Icons.card_giftcard_rounded,
                color: kGold,
                busy: busy,
                onRedeem: onRedeem,
              ),
            const SizedBox(height: 18),
          ],
        );
      },
    );
  }
}

/// Public codes the admin chose to list (promo_public), for this region.
class _PublicPromosList extends StatelessWidget {
  final bool busy;
  final Future<void> Function(String) onRedeem;
  const _PublicPromosList({required this.busy, required this.onRedeem});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ValueListenableBuilder<bool?>(
      valueListenable: TutorialRegion.isPhilippines,
      builder: (context, ph, _) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('promo_public').snapshots(),
        builder: (context, snap) {
          final now = DateTime.now();
          final docs = [...?snap.data?.docs].where((d) {
            final x = d.data();
            final start = x['startsAt'];
            final end = x['endsAt'];
            if (start is Timestamp && start.toDate().isAfter(now)) return false;
            if (end is Timestamp && end.toDate().isBefore(now)) return false;
            final region = x['region'] as String? ?? 'any';
            if (ph == true && region == 'US') return false;
            if (ph == false && region == 'PH') return false;
            return true;
          }).toList();
          if (docs.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Available promos', style: TextStyle(color: onSurface, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              for (final d in docs)
                _promoTile(
                  context,
                  code: (d.data()['code'] as String?) ?? d.id,
                  title: (d.data()['name'] as String?) ?? 'Promo',
                  subtitle: [
                    ((ph == true ? d.data()['rewardTextPHP'] : ph == false ? d.data()['rewardTextUSD'] : null) ??
                            d.data()['rewardText'] ??
                            '')
                        .toString(),
                    ?_until(d.data()['endsAt']),
                  ].where((t) => t.isNotEmpty).join(' · '),
                  icon: Icons.local_offer_rounded,
                  color: kBlue,
                  busy: busy,
                  onRedeem: onRedeem,
                ),
              const SizedBox(height: 18),
            ],
          );
        },
      ),
    );
  }
}
