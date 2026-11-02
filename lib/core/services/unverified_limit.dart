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
// a gig. It returns true when the action may go ahead. When the user is
// unverified and the gig would take them over the admin's limit (including a
// single gig that is bigger than the whole limit), it shows an "Unable to
// apply / accept / post" prompt explaining why (with "Verify Now") and returns
// false. Any read failure lets the action through so a network blip never
// blocks work.
enum LimitAction { apply, accept, post }

Future<bool> guardUnverifiedLimit(
  BuildContext context, {
  double amount = 0,
  String currencyCode = 'USD',
  LimitAction action = LimitAction.apply,
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
    final usedUsd =
        unverifiedLimitUsage(totalsSnap.data(), cfg, fx).totalUsd;
    final newUsd = amount > 0 ? _toUsd(fx, amount, currencyCode) : 0.0;
    // Small epsilon so float rounding never blocks an exact-fit amount.
    if (usedUsd + newUsd <= maxUsd + 0.005) return true;

    if (!context.mounted) return false;
    final ccy = fx.knows(currencyCode) ? currencyCode : 'USD';
    String money(double usd) =>
        CurrencyFormatter.format(fx.fromUsd(usd, ccy) ?? usd, ccy);
    final max = money(maxUsd.toDouble());
    final gig = CurrencyFormatter.format(amount, currencyCode);
    final isHost = action == LimitAction.post;
    final verb = switch (action) {
      LimitAction.apply => 'apply for',
      LimitAction.accept => 'accept',
      LimitAction.post => 'post',
    };
    final limitName = isHost
        ? 'the $max limit unverified accounts can spend on gigs'
        : 'the $max limit unverified accounts can earn';
    final String reason;
    if (usedUsd >= maxUsd - 0.005) {
      reason = "Your account isn't verified and you've already reached "
          '$limitName. Verify your account to $verb more gigs.';
    } else if (newUsd > maxUsd + 0.005) {
      reason = "Your account isn't verified. This gig "
          '${isHost ? 'costs' : 'pays'} $gig, which is more than '
          '$limitName. Verify your account to $verb it.';
    } else {
      final left = money(maxUsd - usedUsd);
      reason = "Your account isn't verified. This gig ($gig) would take you "
          'over $limitName — you only have $left left. Verify your account '
          'to $verb it.';
    }
    final resetNote = switch (cfg['resetPeriod']) {
      'daily' => ' The limit resets every day.',
      'weekly' => ' The limit resets every Monday.',
      'monthly' => ' The limit resets on the 1st of every month.',
      'yearly' => ' The limit resets every January 1.',
      _ => '',
    };
    await _showLimitDialog(
      context,
      title: switch (action) {
        LimitAction.apply => 'Unable to Apply',
        LimitAction.accept => 'Unable to Accept Gig',
        LimitAction.post => 'Unable to Post Gig',
      },
      message: reason + resetNote,
    );
    return false;
  } catch (_) {
    return true;
  }
}

// Mirror of periodKey() in functions/src/unverifiedLimits.ts — keep in sync.
// Calendar periods in Philippine time (UTC+8, no DST); weeks start Monday.
String unverifiedLimitPeriodKey(Map<String, dynamic> cfg, [DateTime? now]) {
  const periods = ['never', 'daily', 'weekly', 'monthly', 'yearly'];
  final p = periods.contains(cfg['resetPeriod']) ? cfg['resetPeriod'] as String : 'never';
  final e = cfg['resetEpoch'];
  final epoch = e is num && e > 0 ? e.round() : 0;
  final t = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
  String two(int n) => n.toString().padLeft(2, '0');
  final String bucket;
  switch (p) {
    case 'daily':
      bucket = '${t.year}-${two(t.month)}-${two(t.day)}';
    case 'weekly':
      final mon = DateTime.utc(t.year, t.month, t.day - (t.weekday - 1));
      bucket = '${mon.year}-${two(mon.month)}-${two(mon.day)}';
    case 'monthly':
      bucket = '${t.year}-${two(t.month)}';
    case 'yearly':
      bucket = '${t.year}';
    default:
      bucket = 'all';
  }
  return '$epoch|$p|$bucket';
}

class UnverifiedLimitUsage {
  final double workerUsd;
  final double hostUsd;
  const UnverifiedLimitUsage(this.workerUsd, this.hostUsd);
  double get totalUsd => workerUsd + hostUsd;
}

/// What the user has used in the current period, in USD (worker + host).
/// Totals from an earlier period (or before an admin reset) count as zero.
UnverifiedLimitUsage unverifiedLimitUsage(
  Map<String, dynamic>? totals,
  Map<String, dynamic> cfg,
  FxRates fx,
) {
  final raw = totals ?? const <String, dynamic>{};
  if ((raw['periodKey'] ?? '0|never|all') != unverifiedLimitPeriodKey(cfg)) {
    return const UnverifiedLimitUsage(0, 0);
  }
  double side(String key) {
    double sum = 0;
    final m = raw[key];
    if (m is Map) {
      m.forEach((ccy, v) {
        if (v is num && ccy is String) sum += _toUsd(fx, v.toDouble(), ccy);
      });
    }
    return sum;
  }

  return UnverifiedLimitUsage(side('worker'), side('host'));
}

double _toUsd(FxRates fx, double amount, String ccy) {
  final per = fx.perUsd(ccy);
  return per == null || per <= 0 ? amount : amount / per;
}

Future<void> _showLimitDialog(
  BuildContext context, {
  required String title,
  required String message,
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
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
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
