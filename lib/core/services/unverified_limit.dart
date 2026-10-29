import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:giggre_app/core/services/fx_rates.dart';
import 'package:giggre_app/core/utils/currency_formatter.dart';
import 'package:giggre_app/core/widgets/account_not_verified_modal.dart';

// Unverified-account limit (admin: Settings → Unverified Account Limit).
//
// general_config/unverified_limits { enabled, maxUsd } caps everything an
// unverified user transacts on gigs — paid as a Gig Worker plus paid out as a
// Gig Host — in total while unverified. The server keeps the running totals in
// transaction_totals/{uid} { worker: {CCY: amt}, host: {CCY: amt} } as tasks
// are completed (functions/src/unverifiedLimits.ts).
//
// [guardUnverifiedLimit] is called before applying for / accepting / posting
// a gig. It returns true when the action may go ahead; otherwise it shows the
// limit prompt (with "Verify Now") and returns false. Any read failure lets
// the action through so a network blip never blocks work.
Future<bool> guardUnverifiedLimit(
  BuildContext context, {
  double amount = 0,
  String currencyCode = 'USD',
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return true;
  final db = FirebaseFirestore.instance;
  const server = GetOptions(source: Source.server);
  try {
    final results = await Future.wait([
      db.collection('users').doc(uid).get(server),
      db.collection('general_config').doc('unverified_limits').get(server),
    ]);
    if (results[0].data()?['isVerified'] == 'verified') return true;
    final cfg = results[1].data() ?? const {};
    final maxUsd = cfg['maxUsd'];
    if (cfg['enabled'] != true || maxUsd is! num || maxUsd <= 0) return true;

    final totalsSnap = await db.collection('transaction_totals').doc(uid).get(server);
    final fx = await FxRates.fetch();
    final totals = totalsSnap.data() ?? const {};
    double usedUsd = 0;
    for (final side in ['worker', 'host']) {
      final m = totals[side];
      if (m is! Map) continue;
      m.forEach((ccy, v) {
        if (v is num && ccy is String) usedUsd += _toUsd(fx, v.toDouble(), ccy);
      });
    }
    final newUsd = amount > 0 ? _toUsd(fx, amount, currencyCode) : 0.0;
    // Small epsilon so float rounding never blocks an exact-fit amount.
    if (usedUsd + newUsd <= maxUsd + 0.005) return true;

    if (!context.mounted) return false;
    final ccy = fx.knows(currencyCode) ? currencyCode : 'USD';
    String money(double usd) =>
        CurrencyFormatter.format(fx.fromUsd(usd, ccy) ?? usd, ccy);
    await _showLimitDialog(
      context,
      reached: usedUsd >= maxUsd,
      used: money(usedUsd),
      max: money(maxUsd.toDouble()),
      left: money((maxUsd - usedUsd).clamp(0, double.infinity).toDouble()),
    );
    return false;
  } catch (_) {
    return true;
  }
}

double _toUsd(FxRates fx, double amount, String ccy) {
  final per = fx.perUsd(ccy);
  return per == null || per <= 0 ? amount : amount / per;
}

Future<void> _showLimitDialog(
  BuildContext context, {
  required bool reached,
  required String used,
  required String max,
  required String left,
}) {
  return showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade700.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock_clock_outlined,
                color: Colors.orange.shade700, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            reached ? 'Transaction Limit Reached' : 'Over Your Transaction Limit',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            reached
                ? 'Unverified accounts can transact up to $max in total. '
                    'You have reached it, so verify your account to keep '
                    'taking and posting gigs.'
                : 'Unverified accounts can transact up to $max in total. '
                    'You have used $used, so only $left is left — this gig '
                    'would go over it. Verify your account to remove the limit.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (context.mounted) showAccountNotVerifiedModal(context);
              },
              child: const Text('Verify Now',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Not now'),
          ),
        ],
      ),
    ),
  );
}
