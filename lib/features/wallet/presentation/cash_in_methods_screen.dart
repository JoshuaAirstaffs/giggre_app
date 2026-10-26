import 'package:flutter/material.dart';

import '../../../core/theme/profile_tab_theme.dart';
import '../services/wallet_requests_service.dart';
import 'gcash_cash_in_screen.dart';
import 'widgets/wallet_page_header.dart';

/// Lists the ways a user can top up their wallet. A method opens when an
/// admin has set it up in giggre-admin → Gig Wallet → Settings (e-wallet
/// accounts, cash at office, remittance center); the rest say "coming soon".
/// Every method is a manual top up an admin confirms.
class CashInMethodsScreen extends StatefulWidget {
  const CashInMethodsScreen({super.key, this.role});

  final String? role;

  @override
  State<CashInMethodsScreen> createState() => _CashInMethodsScreenState();
}

class _CashInMethodsScreenState extends State<CashInMethodsScreen> {
  WalletRequestConfig? _config;

  @override
  void initState() {
    super.initState();
    WalletRequestsService.fetchConfig().then((c) {
      if (mounted) setState(() => _config = c);
    });
  }

  void _comingSoon(String method) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$method is coming soon.')),
    );
  }

  void _open(String method, DepositKind kind) {
    final c = _config;
    if (c == null) return;
    if (!c.canTopUp) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Top up isn't available right now.")),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GcashCashInScreen(
          role: widget.role,
          method: method,
          kind: kind,
          config: c,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    final accent = walletAccentFor(widget.role);
    final c = _config;
    bool has(DepositKind k, [String? m]) =>
        c != null && c.accountsOf(k, method: m).isNotEmpty;
    // The admin's label for a cash method, e.g. "Cash at Makati office".
    String label(DepositKind k, String fallback) {
      final list = c?.accountsOf(k) ?? const <DepositAccount>[];
      return list.isEmpty || list.first.method.trim().isEmpty
          ? fallback
          : list.first.method;
    }

    Widget tile(String name, String description, IconData icon, VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _MethodTile(
            name: name,
            description: description,
            icon: icon,
            accent: accent,
            tokens: tokens,
            onTap: onTap,
          ),
        );

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
                'Choose how you want to add money to your Gig Wallet. Giggre '
                'confirms each top up before it is added.',
                style: TextStyle(color: tokens.textSecondary, fontSize: 13, height: 1.45),
              ),
              if (c == null) ...[
                const SizedBox(height: 24),
                Center(child: CircularProgressIndicator(color: accent)),
              ] else ...[
                const SizedBox(height: 20),
                WalletSectionHeader(label: 'Pay with cash', tokens: tokens),
                const SizedBox(height: 10),
                if (has(DepositKind.office))
                  tile(
                    label(DepositKind.office, 'Cash at office'),
                    'Pay cash at a Giggre office and get an official receipt',
                    Icons.apartment_rounded,
                    () => _open(label(DepositKind.office, 'Cash at office'), DepositKind.office),
                  ),
                if (has(DepositKind.remittance))
                  tile(
                    label(DepositKind.remittance, 'Remittance center'),
                    'Palawan, Cebuana, M Lhuillier and other padala centers',
                    Icons.local_atm_rounded,
                    () => _open(label(DepositKind.remittance, 'Remittance center'), DepositKind.remittance),
                  ),
                tile(
                  'Over-the-Counter',
                  '7-Eleven, Bayad Center and more',
                  Icons.storefront_rounded,
                  () => _comingSoon('Over-the-Counter'),
                ),
                const SizedBox(height: 10),
                WalletSectionHeader(label: 'E-wallets', tokens: tokens),
                const SizedBox(height: 10),
                tile(
                  'GCash',
                  has(DepositKind.ewallet, 'GCash')
                      ? "Send to Giggre's GCash, then enter the reference number"
                      : 'Cash in from your GCash account',
                  Icons.phone_android_rounded,
                  () => has(DepositKind.ewallet, 'GCash')
                      ? _open('GCash', DepositKind.ewallet)
                      : _comingSoon('GCash'),
                ),
                tile(
                  'Maya',
                  'Cash in from your Maya account',
                  Icons.account_balance_wallet_outlined,
                  () => has(DepositKind.ewallet, 'Maya')
                      ? _open('Maya', DepositKind.ewallet)
                      : _comingSoon('Maya'),
                ),
                const SizedBox(height: 10),
                WalletSectionHeader(label: 'QR & Cards', tokens: tokens),
                const SizedBox(height: 10),
                tile('QR Ph', 'Scan with any bank or e-wallet app', Icons.qr_code_2_rounded,
                    () => _comingSoon('QR Ph')),
                tile('Credit / Debit Card', 'Visa or Mastercard', Icons.credit_card_rounded,
                    () => _comingSoon('Card payments')),
              ],
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
