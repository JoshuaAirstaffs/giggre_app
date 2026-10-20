import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/profile_tab_theme.dart';

/// Accent colour for wallet screens: gold for Gig Host, blue otherwise.
Color walletAccentFor(String? role) => role == 'host' ? kGold : kBlue;

/// "‹ Title" row used at the top of wallet screens. The whole row is the
/// back button with a 48px tap target.
class WalletPageHeader extends StatelessWidget {
  const WalletPageHeader({super.key, required this.title, required this.tokens});

  final String title;
  final ProfileTabTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.maybePop(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 17,
                  color: tokens.textPrimary,
                ),
              ),
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small uppercase section label (same style as ProfileTab).
class WalletSectionHeader extends StatelessWidget {
  const WalletSectionHeader({super.key, required this.label, required this.tokens});

  final String label;
  final ProfileTabTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: tokens.textMuted,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
      ),
    );
  }
}
