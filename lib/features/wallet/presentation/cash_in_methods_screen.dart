import 'package:flutter/material.dart';

import '../../../core/theme/profile_tab_theme.dart';
import 'gcash_cash_in_screen.dart';
import 'widgets/wallet_page_header.dart';

/// Lists the ways a user can top up their wallet. Only GCash opens a flow;
/// QR Ph, Card and Cash on Hand show "coming soon" for now.
class CashInMethodsScreen extends StatelessWidget {
  const CashInMethodsScreen({super.key, this.role});

  final String? role;

  // TODO: replace with the real flows for each method.
  void _comingSoon(BuildContext context, String method) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$method is coming soon.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    final accent = walletAccentFor(role);

    return Scaffold(
      backgroundColor: tokens.screenBg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WalletPageHeader(title: 'Cash-in Methods', tokens: tokens),
              const SizedBox(height: 4),
              Text(
                'Choose how you want to add money to your Gig Wallet.',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),

              WalletSectionHeader(label: 'E-wallets', tokens: tokens),
              const SizedBox(height: 10),
              _MethodTile(
                name: 'GCash',
                description: 'Cash in instantly from your GCash account',
                icon: Icons.phone_android_rounded,
                accent: accent,
                tokens: tokens,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GcashCashInScreen(role: role),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _MethodTile(
                name: 'Maya',
                description: 'Cash in from your Maya account',
                icon: Icons.account_balance_wallet_outlined,
                accent: accent,
                tokens: tokens,
                onTap: () => _comingSoon(context, 'Maya'),
              ),
              const SizedBox(height: 20),

              WalletSectionHeader(label: 'QR & Cards', tokens: tokens),
              const SizedBox(height: 10),
              _MethodTile(
                name: 'QR Ph',
                description: 'Scan with any bank or e-wallet app',
                icon: Icons.qr_code_2_rounded,
                accent: accent,
                tokens: tokens,
                onTap: () => _comingSoon(context, 'QR Ph'),
              ),
              const SizedBox(height: 10),
              _MethodTile(
                name: 'Credit / Debit Card',
                description: 'Visa or Mastercard',
                icon: Icons.credit_card_rounded,
                accent: accent,
                tokens: tokens,
                onTap: () => _comingSoon(context, 'Card payments'),
              ),
              const SizedBox(height: 20),

              WalletSectionHeader(label: 'Pay with cash', tokens: tokens),
              const SizedBox(height: 10),
              _MethodTile(
                name: 'Over-the-Counter',
                description: '7-Eleven, Cebuana, Palawan and more',
                icon: Icons.storefront_rounded,
                accent: accent,
                tokens: tokens,
                onTap: () => _comingSoon(context, 'Over-the-Counter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.name,
    required this.description,
    required this.icon,
    required this.accent,
    required this.tokens,
    required this.onTap,
  });

  final String name;
  final String description;
  final IconData icon;
  final Color accent;
  final ProfileTabTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tokens.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tokens.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: tokens.textMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
