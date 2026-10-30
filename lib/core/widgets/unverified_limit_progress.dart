import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:giggre_app/core/providers/current_user_provider.dart';
import 'package:giggre_app/core/services/fx_rates.dart';
import 'package:giggre_app/core/services/unverified_limit.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/core/utils/currency_formatter.dart';
import 'package:giggre_app/core/widgets/account_not_verified_modal.dart';

/// Progress bar of the unverified-account limit (admin: Settings →
/// Unverified Account Limit) on the Gig Worker dashboard.
///
/// Live: listens to the limit config, the user's transaction_totals and the
/// FX rate, so it moves as soon as a gig completes or an admin changes /
/// resets the limit. Renders nothing (no space) when the user is verified or
/// the limit is off.
///
/// [embedded]: render as a section inside another card (the "Earned so far"
/// card) — a divider + the bar, no card of its own. Otherwise it is a
/// standalone card with [bottomSpacing] below it.
class UnverifiedLimitProgressCard extends StatefulWidget {
  final double bottomSpacing;
  final bool embedded;
  const UnverifiedLimitProgressCard({
    super.key,
    this.bottomSpacing = 16,
    this.embedded = false,
  });

  @override
  State<UnverifiedLimitProgressCard> createState() =>
      _UnverifiedLimitProgressCardState();
}

class _UnverifiedLimitProgressCardState
    extends State<UnverifiedLimitProgressCard> {
  final _subs = <StreamSubscription<dynamic>>[];
  Map<String, dynamic>? _cfg;
  Map<String, dynamic>? _totals;
  FxRates _fx = FxRates.usdOnly;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final db = FirebaseFirestore.instance;
    _subs.add(db
        .collection('general_config')
        .doc('unverified_limits')
        .snapshots()
        .listen((s) => setState(() => _cfg = s.data() ?? const {}),
            onError: (Object e) => debugPrint('[UnverifiedLimit] $e')));
    if (uid != null) {
      _subs.add(db
          .collection('transaction_totals')
          .doc(uid)
          .snapshots()
          .listen((s) => setState(() => _totals = s.data()),
              onError: (Object e) => debugPrint('[UnverifiedLimit] $e')));
    }
    _subs.add(FxRates.stream().listen((fx) => setState(() => _fx = fx)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<CurrentUserProvider>();
    final status = user.isVerified ?? 'unverified';
    final cfg = _cfg;
    final maxUsd = cfg?['maxUsd'];
    if (status == 'verified' ||
        cfg == null ||
        cfg['enabled'] != true ||
        maxUsd is! num ||
        maxUsd <= 0) {
      return const SizedBox.shrink();
    }

    final usage = unverifiedLimitUsage(_totals, cfg, _fx);
    final max = maxUsd.toDouble();
    final progress = (usage.totalUsd / max).clamp(0.0, 1.0);
    final reached = usage.totalUsd >= max - 0.005;
    final ccy = _fx.knows(user.currencyCode) ? user.currencyCode : 'USD';
    String money(double usd) =>
        CurrencyFormatter.format(_fx.fromUsd(usd, ccy) ?? usd, ccy);

    // Green = good (< 50%), yellow = getting close (50–79%),
    // red = warning (80%+ and limit reached).
    final Color barColor = progress >= 0.8
        ? const Color(0xFFE5484D)
        : progress >= 0.5
            ? const Color(0xFFF5C518)
            : const Color(0xFF2BB673);
    final resets = switch (cfg['resetPeriod']) {
      'daily' => 'Resets daily',
      'weekly' => 'Resets every Monday',
      'monthly' => 'Resets on the 1st',
      'yearly' => 'Resets every Jan 1',
      _ => null,
    };
    final left = reached ? 'Limit reached' : '${money(max - usage.totalUsd)} left';
    final pending = status == 'pending';
    final resetSentence = switch (cfg['resetPeriod']) {
      'daily' => 'It starts again from zero every day.',
      'weekly' => 'It starts again from zero every Monday.',
      'monthly' => 'It starts again from zero on the 1st of every month.',
      'yearly' => 'It starts again from zero every January 1.',
      _ => 'It counts everything until you verify.',
    };
    final tooltip =
        'Accounts that aren\'t verified yet can only earn up to ${money(max)} '
        'from gigs. Gigs you post as a host count toward it too. '
        '$resetSentence\n\n'
        'Once you reach it, you can\'t apply for or accept new gigs. '
        'Verify your account to remove the limit.';

    final onSurface = Theme.of(context).colorScheme.onSurface;
    final infoIcon = Tooltip(
        message: tooltip,
        triggerMode: TooltipTriggerMode.tap,
        showDuration: const Duration(seconds: 8),
        preferBelow: true,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(12),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          height: 1.4,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: kSub,
          ),
        ),
      );

    final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 16, color: barColor),
                const SizedBox(width: 6),
                const Text(
                  'Unverified earning limit',
                  style: TextStyle(
                    color: kSub,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                infoIcon,
                const Spacer(),
                Text(
                  '${(progress * 100).floor()}%',
                  style: TextStyle(
                    color: barColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: money(usage.totalUsd),
                    style: TextStyle(
                      color: onSurface,
                      fontSize: widget.embedded ? 15 : 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(
                    text: '  of ${money(max)}',
                    style: const TextStyle(color: kSub, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 8,
                  color: barColor,
                  backgroundColor: barColor.withValues(alpha: 0.15),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              [left, ?resets].join(' · '),
              style: TextStyle(
                color: reached ? barColor : kSub,
                fontSize: 12,
                fontWeight: reached ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (usage.hostUsd > 0) ...[
              const SizedBox(height: 2),
              Text(
                'Includes ${money(usage.hostUsd)} paid for gigs you hosted',
                style: const TextStyle(color: kSub, fontSize: 11),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    pending
                        ? 'Your verification is in review. The limit goes away once approved.'
                        : reached
                            ? "Verify your account to keep applying for gigs."
                            : 'Verify your account to remove this limit.',
                    style: const TextStyle(color: kSub, fontSize: 11.5),
                  ),
                ),
                if (!pending) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.orange.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => showAccountNotVerifiedModal(
                      context,
                      onStatusRechecked: (s) {
                        if (!mounted) return;
                        context
                            .read<CurrentUserProvider>()
                            .updateVerificationStatus(s);
                      },
                    ),
                    child: const Text(
                      'Verify Now',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ],
        );

    if (widget.embedded) {
      // Compact: one line (label + ⓘ · used / max) and the bar.
      // Orange label (red once nearly / fully used) so it stands out from
      // the earnings above.
      final accent = progress >= 0.8 ? barColor : Colors.orange.shade700;
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 14, color: accent),
                const SizedBox(width: 5),
                Text(
                  'Earning limit',
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                infoIcon,
                const Spacer(),
                Text(
                  reached
                      ? 'Limit reached'
                      : '${money(usage.totalUsd)} / ${money(max)}',
                  style: TextStyle(
                    color: reached
                        ? barColor
                        : Theme.of(context).colorScheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 5,
                  color: barColor,
                  backgroundColor: barColor.withValues(alpha: 0.15),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: widget.bottomSpacing),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: reached
                ? barColor.withValues(alpha: 0.5)
                : Theme.of(context).dividerColor,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: content,
      ),
    );
  }
}
