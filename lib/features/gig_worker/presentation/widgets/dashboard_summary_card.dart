import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/providers/current_user_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../tutorial/widgets/tutorial_anchor.dart';

const _kOnlineGreen = Color(0xFF2BB673);

// ─────────────────────────────────────────────────────────────────────────────
//  Worker dashboard cards:
//  AvailabilityCard — Online (main switch) with Quick Gigs + Auto Accept under
//    it, all in one place (rendered by the caller so it can overlap the
//    header).
//  EarningsHeaderLine — earnings as one line in the header.
// ─────────────────────────────────────────────────────────────────────────────
class AvailabilityCard extends StatelessWidget {
  final bool isOnline;
  final ValueChanged<bool> onOnlineChanged;
  final bool seekingQuickGigs;
  final ValueChanged<bool> onQuickGigsChanged;
  final bool autoAccept;
  final ValueChanged<bool> onAutoAcceptChanged;

  const AvailabilityCard({
    super.key,
    required this.isOnline,
    required this.onOnlineChanged,
    required this.seekingQuickGigs,
    required this.onQuickGigsChanged,
    required this.autoAccept,
    required this.onAutoAcceptChanged,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final dividerColor = Theme.of(context).dividerColor;
    return Material(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── Online: the main switch ─────────────────────────────
          TutorialAnchor(
            id: 'workerHome.activeMode',
            child: Semantics(
              toggled: isOnline,
              label: isOnline
                  ? 'Online, hosts nearby can offer you gigs'
                  : 'Offline, hidden from hosts',
              child: InkWell(
                onTap: () => onOnlineChanged(!isOnline),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isOnline ? _kOnlineGreen : kSub,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isOnline ? 'Online' : 'Offline',
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              isOnline
                                  ? 'Hosts nearby can offer you gigs'
                                  : "You're hidden from hosts",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: kSub, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      _SmallSwitch(
                        value: isOnline,
                        activeColor: _kOnlineGreen,
                        onChanged: onOnlineChanged,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: dividerColor),

          // ── Options under Online ────────────────────────────────
          // Greyed out while offline: neither does anything then (Quick Gig
          // matching needs the worker online too).
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: TutorialAnchor(
                    id: 'workerHome.quickGigsToggle',
                    child: _OptionTile(
                      label: 'Quick Gigs',
                      description: 'Instant offers',
                      value: seekingQuickGigs,
                      enabled: isOnline,
                      activeColor: _kOnlineGreen,
                      onChanged: onQuickGigsChanged,
                    ),
                  ),
                ),
                VerticalDivider(width: 1, color: dividerColor),
                Expanded(
                  child: _OptionTile(
                    label: 'Auto Accept',
                    description: 'Auto-book matches',
                    value: autoAccept,
                    enabled: isOnline,
                    activeColor: kGold,
                    onChanged: onAutoAcceptChanged,
                  ),
                ),
              ],
            ),
          ),
          if (!isOnline)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Go online to use these',
                  style: TextStyle(color: kSub, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final String description;
  final bool value;
  final bool enabled;
  final Color activeColor;
  final ValueChanged<bool> onChanged;

  const _OptionTile({
    required this.label,
    required this.description,
    required this.value,
    required this.enabled,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: '$label, $description',
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _SmallSwitch(
                      value: value,
                      activeColor: activeColor,
                      onChanged: enabled ? onChanged : null,
                    ),
                  ],
                ),
                Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kSub, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallSwitch extends StatelessWidget {
  final bool value;
  final Color activeColor;
  final ValueChanged<bool>? onChanged;

  const _SmallSwitch({
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: FittedBox(
        child: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: activeColor,
        ),
      ),
    );
  }
}

/// The worker's earnings as one line in the dashboard header:
/// "₱12,450 earned · ₱1,200 this week".
class EarningsHeaderLine extends StatelessWidget {
  final Map<String, double> totalByCurrency;
  final Map<String, double> weeklyByCurrency;

  const EarningsHeaderLine({
    super.key,
    required this.totalByCurrency,
    required this.weeklyByCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final defaultCurrencyCode = context
        .watch<CurrentUserProvider>()
        .currencyCode;
    // Each currency shown on its own, never converted (a converted total
    // would drift with exchange rates and not match the wallet). The
    // worker's current currency leads, then the rest alphabetically; only
    // currencies with money in them, so a PH-only worker never sees "+ $0".
    // Nothing earned at all: "₱0" in their current currency.
    List<String> amounts(Map<String, double> byCode) {
      final codes =
          byCode.entries.where((e) => e.value > 0).map((e) => e.key).toList()
            ..sort((a, b) {
              if (a == defaultCurrencyCode) return -1;
              if (b == defaultCurrencyCode) return 1;
              return a.compareTo(b);
            });
      if (codes.isEmpty) {
        return [CurrencyFormatter.format(0, defaultCurrencyCode)];
      }
      return [for (final c in codes) CurrencyFormatter.format(byCode[c]!, c)];
    }

    final totals = amounts(totalByCurrency);
    final weekly = amounts(weeklyByCurrency).join(' + ');

    return Semantics(
      label:
          '${totals.join(' and ')} earned, '
          '${weekly.replaceAll(' + ', ' and ')} this week',
      child: ExcludeSemantics(
        // Two currencies can run long on small phones: wraps to a second
        // line rather than cutting off an amount.
        child: Text.rich(
          TextSpan(
            children: [
              for (var i = 0; i < totals.length; i++) ...[
                if (i > 0) const TextSpan(text: ' + '),
                TextSpan(
                  text: totals[i],
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              TextSpan(text: ' earned · $weekly this week'),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ),
    );
  }
}
