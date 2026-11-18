import 'package:flutter/material.dart';

import 'header_home_button.dart';
import 'mode_switch.dart';

/// Shared gradient band for the Gig Worker and Gig Host dashboards. Both use
/// the same layout — same padding, same 38 px title row, same button sizes,
/// the mode toggle at the same spot and a subtitle line of the same height —
/// so switching mode only changes colours and content; nothing moves.
class DashboardHeaderBar extends StatelessWidget {
  final List<Color> colors;
  final VoidCallback? onGoHome;
  final bool showBack;
  /// Round 38 px buttons (HeaderCircleButton), left of the mode toggle.
  final List<Widget> actions;
  final bool isHost;
  final VoidCallback? onSwitchMode;
  final Widget? subtitle;

  const DashboardHeaderBar({
    super.key,
    required this.colors,
    required this.isHost,
    this.onGoHome,
    this.showBack = false,
    this.actions = const [],
    this.onSwitchMode,
    this.subtitle,
  });

  static const double rowHeight = 38;
  static const double subtitleMinHeight = 20;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(26),
        bottomRight: Radius.circular(26),
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 44),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: rowHeight,
                  child: Row(
                    children: [
                      if (onGoHome != null) ...[
                        HeaderHomeButton(onTap: onGoHome!),
                        const SizedBox(width: 10),
                      ],
                      if (showBack) ...[
                        _BackButton(onTap: () => Navigator.pop(context)),
                        const SizedBox(width: 10),
                      ],
                      const Expanded(
                        child: Text(
                          'Dashboard',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      for (final a in actions) ...[a, const SizedBox(width: 8)],
                      if (onSwitchMode != null)
                        ModeSwitch(isHost: isHost, onSwitch: onSwitchMode!),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: subtitleMinHeight),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: subtitle ?? const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round translucent 38 px header button, with an optional red dot.
class HeaderCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool showDot;

  const HeaderCircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.white.withValues(alpha: 0.18),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: Colors.white, size: 19),
        ),
      ),
    );
    final withDot = Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        if (showDot)
          Positioned(
            top: 6,
            right: 6,
            child: IgnorePointer(
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              ),
            ),
          ),
      ],
    );
    return tooltip == null ? withDot : Tooltip(message: tooltip!, child: withDot);
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 15),
      ),
    );
  }
}
