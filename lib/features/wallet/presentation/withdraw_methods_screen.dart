import 'package:flutter/material.dart';

import '../../../core/theme/profile_tab_theme.dart';
import '../services/wallet_requests_service.dart';
import 'widgets/wallet_page_header.dart';
import 'withdraw_amount_screen.dart';

/// Lists the ways Giggre can pay out a withdrawal — the methods an admin set
/// up in giggre-admin → Gig Wallet → Settings → Withdraw methods (e-wallet,
/// cash pickup at the office, remittance center). Mirrors the Top Up flow:
/// method → amount → payout details, then an admin pays it out and approves.
class WithdrawMethodsScreen extends StatefulWidget {
  const WithdrawMethodsScreen({super.key, this.role});

  final String? role;

  @override
  State<WithdrawMethodsScreen> createState() => _WithdrawMethodsScreenState();
}

class _WithdrawMethodsScreenState extends State<WithdrawMethodsScreen> {
  WalletRequestConfig? _config;

  @override
  void initState() {
    super.initState();
    WalletRequestsService.fetchConfig().then((c) {
      if (mounted) setState(() => _config = c);
    });
  }

  void _open(WithdrawMethod m) {
    final c = _config;
    if (c == null) return;
    if (!c.canWithdraw) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Withdraw isn't available right now.")),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WithdrawAmountScreen(role: widget.role, method: m, config: c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    final accent = walletAccentFor(widget.role);
    final c = _config;
    List<WithdrawMethod> of(DepositKind k) =>
        c == null ? const [] : c.withdrawMethods.where((m) => m.kind == k).toList();

    Widget section(String label, DepositKind kind, IconData icon, String Function(WithdrawMethod) describe) {
      final list = of(kind);
      if (list.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          WalletSectionHeader(label: label, tokens: tokens),
          const SizedBox(height: 10),
          for (final m in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _WithdrawMethodTile(
                name: m.method,
                description: describe(m),
                icon: icon,
                accent: accent,
                tokens: tokens,
                onTap: () => _open(m),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: tokens.screenBg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WalletPageHeader(title: 'Withdraw Methods', tokens: tokens),
              const SizedBox(height: 4),
              Text(
                'Choose how you want to receive your GigCash. The amount is '
                'put on hold right away, and Giggre pays it out after review.',
                style: TextStyle(color: tokens.textSecondary, fontSize: 13, height: 1.45),
              ),
              if (c == null) ...[
                const SizedBox(height: 24),
                Center(child: CircularProgressIndicator(color: accent)),
              ] else if (!c.canWithdraw) ...[
                const SizedBox(height: 24),
                Text(
                  "Withdrawals aren't available right now. Please check again later.",
                  style: TextStyle(color: tokens.textMuted, fontSize: 13.5),
                ),
              ] else ...[
                const SizedBox(height: 10),
                section('E-wallets & banks', DepositKind.ewallet, Icons.phone_android_rounded,
                    (m) => 'Giggre sends it to your ${m.method} account'),
                section('Pick up cash', DepositKind.office, Icons.apartment_rounded,
                    (m) => m.details.isNotEmpty ? m.details : 'Collect it in cash with a valid ID'),
                section('Remittance center', DepositKind.remittance, Icons.local_atm_rounded,
                    (m) => 'Claim it with a control number and a valid ID'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WithdrawMethodTile extends StatelessWidget {
  const _WithdrawMethodTile({
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
                      style: TextStyle(color: tokens.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.textSecondary, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: tokens.textMuted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
