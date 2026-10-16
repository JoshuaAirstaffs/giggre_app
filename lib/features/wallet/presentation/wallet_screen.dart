import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/current_user_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/profile_tab_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import 'cash_in_methods_screen.dart';
import 'choose_recipient_screen.dart';
import 'security_privacy_centre_screen.dart';

// Hidden until payment methods exist. Flip to true to bring the
// "Set as default payment method" row back.
const bool _kShowDefaultPaymentToggle = false;

// Security and Privacy Centre is built but hidden for now — the banner shows
// "coming soon" instead. Flip to true to open the real screen.
const bool _kShowSecurityCentre = true;

/// Wallet screen. Layout mirrors ProfileTab: themed background, back arrow +
/// bold title row, then scrollable content.
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key, this.role});

  /// The mode picked on Home: 'worker' → blue, 'host' → gold.
  /// Anything else (e.g. null) falls back to worker blue.
  final String? role;

  // TODO: replace with the real Top Up / Transfer / Send flows.
  void _comingSoon(BuildContext context, String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$action is coming soon.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _WalletAccent.forRole(role, isDark: isDark);

    return _WalletAccentScope(
      accent: accent,
      child: Scaffold(
        backgroundColor: tokens.screenBg,
        body: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hero: back, title, GigCash amount, badge ───────────────
              _WalletHero(uid: uid, tokens: tokens),
              Divider(height: 1, thickness: 1, color: tokens.divider),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  // ── Wallet actions ─────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _WalletActionButton(
                          label: 'Top Up',
                          icon: Icons.add_card_rounded,
                          tokens: tokens,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CashInMethodsScreen(role: role),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _WalletActionButton(
                          label: 'Transfer',
                          icon: Icons.swap_horiz_rounded,
                          tokens: tokens,
                          onTap: () => _comingSoon(context, 'Transfer'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _WalletActionButton(
                          label: 'Send',
                          icon: Icons.north_east_rounded,
                          tokens: tokens,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChooseRecipientScreen(role: role),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Default payment toggle (hidden for now) ────────────────
                  if (_kShowDefaultPaymentToggle) ...[
                    _DefaultPaymentToggle(tokens: tokens),
                    const SizedBox(height: 16),
                  ],

                  // ── Security info banner ───────────────────────────────────
                  _SecurityBanner(
                    onTap: _kShowSecurityCentre
                        ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  SecurityPrivacyCentreScreen(role: role),
                            ),
                          )
                        : () => _comingSoon(context, 'Security and Privacy Centre'),
                  ),
                  const SizedBox(height: 16),

                  // ── Transaction history ────────────────────────────────────
                  _TransactionHistory(uid: uid, tokens: tokens),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletHero extends StatelessWidget {
  const _WalletHero({required this.uid, required this.tokens});

  final String? uid;
  final ProfileTabTokens tokens;

  @override
  Widget build(BuildContext context) {
    final accent = _WalletAccent.of(context);
    final currencyCode = context.watch<CurrentUserProvider>().currencyCode;
    final symbol = CurrencyFormatter.symbol(currencyCode);
    final number = NumberFormat.currency(symbol: '', decimalDigits: 2);

    return ClipRect(
      child: Stack(
        children: [
          // Soft accent glow in the top-right corner.
          Positioned(
            top: -120,
            right: -110,
            child: IgnorePointer(
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.fill.withValues(alpha: 0.22),
                      accent.fill.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.maybePop(context),
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Gig Wallet',
                                style: TextStyle(
                                  color: accent.fg,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'GigCash',
                                style: TextStyle(
                                  color: tokens.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Live: updates when the user doc's balance changes.
                              StreamBuilder<
                                DocumentSnapshot<Map<String, dynamic>>
                              >(
                                stream: uid == null
                                    ? null
                                    : FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(uid)
                                          .snapshots(),
                                builder: (context, snap) {
                                  if (snap.connectionState ==
                                          ConnectionState.waiting &&
                                      !snap.hasData) {
                                    return SizedBox(
                                      height: 42,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            color: accent.fill,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  final balance =
                                      (snap.data?.data()?['balance'] as num?)
                                          ?.toDouble() ??
                                      0;
                                  return FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: '$symbol ',
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w600,
                                              color: tokens.textSecondary,
                                            ),
                                          ),
                                          TextSpan(
                                            text: snap.hasError
                                                ? '—'
                                                : number
                                                      .format(balance)
                                                      .trim(),
                                            style: TextStyle(
                                              fontSize: 36,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.6,
                                              color: tokens.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Round Giggre badge.
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: accent.fill,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: accent.fill.withValues(alpha: 0.3),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.bolt_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletActionButton extends StatelessWidget {
  const _WalletActionButton({
    required this.label,
    required this.icon,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final ProfileTabTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: tokens.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: tokens.cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: _WalletAccent.of(context).fg),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
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

// TODO: persist this choice (e.g. a field on the user doc) once the payment
// flow reads it. For now it only lives in memory while the screen is open.
class _DefaultPaymentToggle extends StatefulWidget {
  const _DefaultPaymentToggle({required this.tokens});

  final ProfileTabTokens tokens;

  @override
  State<_DefaultPaymentToggle> createState() => _DefaultPaymentToggleState();
}

class _DefaultPaymentToggleState extends State<_DefaultPaymentToggle> {
  bool _isDefault = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Set as default payment method',
              style: TextStyle(
                color: widget.tokens.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch(
            value: _isDefault,
            onChanged: (v) => setState(() => _isDefault = v),
            activeThumbColor: Colors.white,
            activeTrackColor: _WalletAccent.of(context).fill,
          ),
        ],
      ),
    );
  }
}

class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _WalletAccent.of(context);
    final radius = BorderRadius.circular(12);
    // Light tint instead of a solid fill so it doesn't outshout the balance.
    return Material(
      color: accent.fill.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: accent.fill.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, color: accent.fg, size: 19),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Find out how we keep your Gig Wallet secure',
                  style: TextStyle(
                    color: accent.fg,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: accent.fg, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Transaction history
//
//  Reads users/{uid}/wallet_transactions, newest first. Expected fields:
//    title        String     e.g. "Top Up via GCash", "Payment for Gig #123"
//    amount       num        signed: positive = money in, negative = money out
//    type         String     top_up | transfer | send | earning | withdraw | refund
//    currencyCode String?    defaults to the user's currency
//    status       String?    completed | pending | failed (default completed)
//    createdAt    Timestamp
//  Only the backend (Cloud Functions / Admin SDK) should write these.
// ─────────────────────────────────────────────
class _TransactionHistory extends StatelessWidget {
  const _TransactionHistory({required this.uid, required this.tokens});

  final String? uid;
  final ProfileTabTokens tokens;

  @override
  Widget build(BuildContext context) {
    final userCurrency = context.watch<CurrentUserProvider>().currencyCode;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transaction History',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: uid == null
                ? null
                : FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('wallet_transactions')
                      .orderBy('createdAt', descending: true)
                      .limit(50)
                      .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                debugPrint('[Wallet] history error: ${snap.error}');
                return _HistoryMessage(
                  icon: Icons.error_outline_rounded,
                  text: "Couldn't load transactions.",
                  tokens: tokens,
                );
              }
              if (!snap.hasData) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: _WalletAccent.of(context).fill,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                );
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return _HistoryMessage(
                  icon: Icons.receipt_long_rounded,
                  text: 'No transactions yet.',
                  tokens: tokens,
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < docs.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: tokens.divider),
                    _TransactionRow(
                      data: docs[i].data(),
                      fallbackCurrency: userCurrency,
                      tokens: tokens,
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.icon,
    required this.text,
    required this.tokens,
  });

  final IconData icon;
  final String text;
  final ProfileTabTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 36, color: tokens.textMuted),
            const SizedBox(height: 8),
            Text(
              text,
              style: TextStyle(color: tokens.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.data,
    required this.fallbackCurrency,
    required this.tokens,
  });

  final Map<String, dynamic> data;
  final String fallbackCurrency;
  final ProfileTabTokens tokens;

  static const _kIn = Color(0xFF2BB673);
  static const _kOut = Colors.redAccent;

  static IconData _iconFor(String type) => switch (type) {
    'top_up' => Icons.add_card_rounded,
    'transfer' => Icons.swap_horiz_rounded,
    'send' => Icons.north_east_rounded,
    'withdraw' => Icons.account_balance_rounded,
    'earning' => Icons.work_outline_rounded,
    'refund' => Icons.replay_rounded,
    _ => Icons.receipt_long_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final amount = (data['amount'] as num?)?.toDouble() ?? 0;
    final type = data['type'] as String? ?? '';
    final title = data['title'] as String? ?? 'Transaction';
    final status = data['status'] as String? ?? 'completed';
    final code = data['currencyCode'] as String? ?? fallbackCurrency;
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

    final isIn = amount >= 0;
    final color = isIn ? _kIn : _kOut;
    final formatted = NumberFormat.currency(
      symbol: '${CurrencyFormatter.symbol(code)} ',
      decimalDigits: 2,
    ).format(amount.abs());

    final subtitle = [
      if (createdAt != null) DateFormat('MMM d, yyyy · h:mm a').format(createdAt),
      if (status != 'completed') status[0].toUpperCase() + status.substring(1),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(_iconFor(type), size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: tokens.textMuted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isIn ? '+' : '−'} $formatted',
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Role accent: blue for Gig Worker, gold for Gig Host
// ─────────────────────────────────────────────
class _WalletAccent {
  const _WalletAccent({required this.fill, required this.fg});

  /// Brand colour for fills, tints, switch tracks and spinners.
  final Color fill;

  /// Colour for icons and text. Same brand gold as Home's Gig Host card.
  final Color fg;

  factory _WalletAccent.forRole(String? role, {required bool isDark}) {
    if (role == 'host') {
      return const _WalletAccent(fill: kGold, fg: kGold);
    }
    return const _WalletAccent(fill: kBlue, fg: kBlue);
  }

  static _WalletAccent of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WalletAccentScope>()?.accent ??
      const _WalletAccent(fill: kBlue, fg: kBlue);
}

class _WalletAccentScope extends InheritedWidget {
  const _WalletAccentScope({required this.accent, required super.child});

  final _WalletAccent accent;

  @override
  bool updateShouldNotify(_WalletAccentScope old) =>
      old.accent.fill != accent.fill || old.accent.fg != accent.fg;
}
