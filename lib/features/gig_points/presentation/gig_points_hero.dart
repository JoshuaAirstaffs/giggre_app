import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/current_user_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../models/gig_points_models.dart';
import '../models/gig_points_request_models.dart';
import 'points_request_sheet.dart';
import 'points_requests_section.dart';
import 'reward_stage_style.dart';

final _numFmt = NumberFormat.decimalPattern();

/// Wallet-style balance card: available points, what's on hold, the GigCash
/// balance, and the two conversion actions (To GigCash / To Points).
///
/// "Available" is credited points only (functions/src/gigPoints.ts); held
/// points are already excluded and shown separately.
class GigPointsHero extends StatelessWidget {
  final GigPointsBalance? balance;
  final bool hasError;
  final VoidCallback onRetry;
  final Stream<PointsRequestLimits> limits;
  final VoidCallback onShowInfo;

  /// The user's pending request, if any — only one is allowed at a time,
  /// so while it exists the actions explain that instead of opening.
  final GigPointsRequest? pendingRequest;

  /// Gig Wallet balance, shown for context and used by To Points.
  final WalletBalance? wallet;

  const GigPointsHero({
    super.key,
    required this.balance,
    required this.hasError,
    required this.onRetry,
    required this.limits,
    required this.onShowInfo,
    this.pendingRequest,
    this.wallet,
  });

  @override
  Widget build(BuildContext context) {
    final b = balance;
    final white70 = Colors.white.withValues(alpha: 0.82);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFFF6B640), Color(0xFFE88A22), Color(0xFFD9671A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: kGold.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Soft decorative rings, purely visual.
            Positioned(
              right: -40,
              top: -50,
              child: _Ring(size: 170, opacity: 0.10),
            ),
            Positioned(
              right: 40,
              top: 60,
              child: _Ring(size: 90, opacity: 0.08),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.stars_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Available balance',
                          style: TextStyle(
                            color: white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: onShowInfo,
                        tooltip: 'How Gig Points work',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.info_outline_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (hasError)
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            "Couldn't load your balance.",
                            style: TextStyle(color: Colors.white, fontSize: 15),
                          ),
                        ),
                        TextButton(
                          onPressed: onRetry,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          child: const Text(
                            'Retry',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    )
                  else
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            b == null ? '–' : _numFmt.format(b.balance),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 40,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'pts',
                            style: TextStyle(
                              color: white70,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (!hasError && (b?.heldPoints ?? 0) > 0)
                        _HeroChip(
                          icon: Icons.lock_clock_outlined,
                          text: '${_numFmt.format(b!.heldPoints)} on hold',
                        ),
                      if (!hasError && (b?.pendingPoints ?? 0) > 0)
                        _HeroChip(
                          icon: Icons.hourglass_top_rounded,
                          text:
                              '${_numFmt.format(b!.pendingPoints)} processing',
                        ),
                      if (wallet != null)
                        _HeroChip(
                          icon: Icons.account_balance_wallet_outlined,
                          text:
                              '${formatCash(wallet!.balance, wallet!.currencyOr(context.watch<CurrentUserProvider>().currencyCode))} GigCash',
                        ),
                      if (pendingRequest != null)
                        _HeroChip(
                          icon: Icons.schedule_rounded,
                          text:
                              'Conversion of '
                              '${_numFmt.format(pendingRequest!.points)} pts in review',
                        ),
                      if (b?.fromCache == true && !hasError)
                        const _HeroChip(
                          icon: Icons.cloud_off_rounded,
                          text: 'Offline · last synced',
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: StreamBuilder<PointsRequestLimits>(
                      stream: limits,
                      builder: (context, snap) {
                        final l = snap.data;
                        return Row(
                          children: [
                            for (final (i, t) in PointsRequestType.values.indexed) ...[
                              if (i > 0) const SizedBox(width: 10),
                              Expanded(
                                child: _HeroAction(
                                  type: t,
                                  open:
                                      (l?.isOpen(t) ?? false) &&
                                      pendingRequest == null,
                                  onTap: l == null || b == null
                                      ? null
                                      : () => openPointsRequest(
                                          context,
                                          type: t,
                                          balance: b,
                                          wallet: wallet,
                                          limits: l,
                                          pending: pendingRequest,
                                        ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final double size;
  final double opacity;

  const _Ring({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: opacity),
          width: 18,
        ),
      ),
    ),
  );
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HeroChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 13),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _HeroAction extends StatelessWidget {
  final PointsRequestType type;
  final bool open;
  final VoidCallback? onTap;

  const _HeroAction({required this.type, required this.open, this.onTap});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFD9671A);
    return Semantics(
      button: true,
      label: '${type.title}${open ? '' : ', unavailable'}',
      child: Opacity(
        opacity: open ? 1 : 0.55,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          elevation: 0,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    type == PointsRequestType.toCash
                        ? Icons.account_balance_wallet_outlined
                        : Icons.stars_rounded,
                    color: accent,
                    size: 19,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      type.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: accent,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One card, three figures, separated by hairlines.
class GigPointsStatsStrip extends StatelessWidget {
  final GigPointsBalance? balance;

  const GigPointsStatsStrip({super.key, required this.balance});

  @override
  Widget build(BuildContext context) {
    final b = balance;
    String n(int Function(GigPointsBalance) f) =>
        b == null ? '–' : _numFmt.format(f(b));
    final divider = Container(
      width: 1,
      height: 34,
      color: Theme.of(context).dividerColor,
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              value: n((b) => b.pendingPoints),
              label: 'Processing',
              color: rewardStageStyle(RewardStage.approvedProcessing).color,
              hint: RewardStage.approvedProcessing.explanation,
            ),
          ),
          divider,
          Expanded(
            child: _Stat(
              value: n((b) => b.lifetimeEarned),
              label: 'Lifetime earned',
              color: kGigPointsGreen,
            ),
          ),
          divider,
          Expanded(
            child: _Stat(
              value: n((b) => b.gigsRewarded),
              label: 'Tasks rewarded',
              color: kBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final String? hint;

  const _Stat({
    required this.value,
    required this.label,
    required this.color,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: kSub, fontSize: 11.5),
          ),
        ],
      ),
    );
    return hint == null ? body : Tooltip(message: hint!, child: body);
  }
}
