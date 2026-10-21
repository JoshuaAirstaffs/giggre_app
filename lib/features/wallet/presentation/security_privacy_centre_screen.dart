import 'package:flutter/material.dart';

import 'package:giggre_app/screens/app_contents/contact_us.dart';
import 'package:giggre_app/screens/app_contents/help_faq.dart';
import 'package:giggre_app/screens/app_contents/privacy_policy.dart';
import 'package:giggre_app/screens/app_contents/terms_and_conditions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/profile_tab_theme.dart';
import '../../gig_worker/presentation/verification_screen.dart';

/// Security and Privacy Centre. Opened from the Wallet's security banner.
/// Layout mirrors WalletScreen / ProfileTab.
///
/// Keep the copy here factual — only describe protections the app really
/// has. Update it as wallet features (top-ups, withdrawals) go live.
class SecurityPrivacyCentreScreen extends StatelessWidget {
  const SecurityPrivacyCentreScreen({super.key, this.role});

  /// 'worker' → blue, 'host' → gold (same rule as the Wallet).
  final String? role;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    final accent = role == 'host' ? kGold : kBlue;

    void open(Widget screen) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
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
              // ── Title (whole row is the back button) ───────────────────
              Semantics(
                button: true,
                label: 'Back',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.maybePop(context),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 48,
                      minWidth: 48,
                    ),
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
                            'Security and Privacy Centre',
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
              ),
              const SizedBox(height: 4),

              // ── Intro card ─────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: tokens.cardSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: tokens.cardBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.verified_user_rounded,
                        color: accent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your safety comes first',
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'How Giggre protects your account, Gig Wallet and '
                            'personal information, and what you can do to '
                            'stay safe.',
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── How we protect you ─────────────────────────────────────
              _SectionHeader(label: 'How we protect you', tokens: tokens),
              const SizedBox(height: 10),
              _InfoCard(
                tokens: tokens,
                children: [
                  _InfoRow(
                    icon: Icons.lock_outline_rounded,
                    accent: accent,
                    tokens: tokens,
                    title: 'Encrypted connections',
                    body:
                        'Everything sent between the app and our servers is '
                        'encrypted in transit, so it can\'t be read along '
                        'the way.',
                  ),
                  _Divider(tokens: tokens),
                  _InfoRow(
                    icon: Icons.cloud_done_outlined,
                    accent: accent,
                    tokens: tokens,
                    title: 'Secure cloud storage',
                    body:
                        'Your data is stored on Google Cloud (Firebase), '
                        'which encrypts it at rest.',
                  ),
                  _Divider(tokens: tokens),
                  _InfoRow(
                    icon: Icons.badge_outlined,
                    accent: accent,
                    tokens: tokens,
                    title: 'Verified accounts',
                    body:
                        'Users can verify their identity, so you know who '
                        'you\'re working with or hiring.',
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Keep your account safe ─────────────────────────────────
              _SectionHeader(label: 'Keep your account safe', tokens: tokens),
              const SizedBox(height: 10),
              _InfoCard(
                tokens: tokens,
                children: [
                  _InfoRow(
                    icon: Icons.password_rounded,
                    accent: accent,
                    tokens: tokens,
                    title: 'Never share your password or codes',
                    body:
                        'Giggre staff will never ask for your password or '
                        'one-time verification codes.',
                  ),
                  _Divider(tokens: tokens),
                  _InfoRow(
                    icon: Icons.handshake_outlined,
                    accent: accent,
                    tokens: tokens,
                    title: 'Keep payments in the app',
                    body:
                        'Be careful if someone asks you to pay or get paid '
                        'outside Giggre. We can\'t help with off-app '
                        'payments.',
                  ),
                  _Divider(tokens: tokens),
                  _InfoRow(
                    icon: Icons.phonelink_lock_outlined,
                    accent: accent,
                    tokens: tokens,
                    title: 'Log out on shared devices',
                    body:
                        'Always log out if you use Giggre on a phone that '
                        'isn\'t yours.',
                  ),
                  _Divider(tokens: tokens),
                  _LinkRow(
                    icon: Icons.verified_outlined,
                    accent: accent,
                    tokens: tokens,
                    label: 'Verify your account',
                    onTap: () => open(const VerificationScreen()),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Privacy ────────────────────────────────────────────────
              _SectionHeader(label: 'Your privacy', tokens: tokens),
              const SizedBox(height: 10),
              _InfoCard(
                tokens: tokens,
                children: [
                  _LinkRow(
                    icon: Icons.privacy_tip_outlined,
                    accent: accent,
                    tokens: tokens,
                    label: 'Privacy Policy',
                    onTap: () => open(PrivacyPolicy()),
                  ),
                  _Divider(tokens: tokens),
                  _LinkRow(
                    icon: Icons.description_outlined,
                    accent: accent,
                    tokens: tokens,
                    label: 'Terms and Conditions',
                    onTap: () => open(const TermsAndConditions()),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Help ───────────────────────────────────────────────────
              _SectionHeader(label: 'Need help?', tokens: tokens),
              const SizedBox(height: 10),
              _InfoCard(
                tokens: tokens,
                children: [
                  _LinkRow(
                    icon: Icons.report_outlined,
                    accent: accent,
                    tokens: tokens,
                    label: 'Report a problem or suspicious activity',
                    onTap: () => open(const ContactUs()),
                  ),
                  _Divider(tokens: tokens),
                  _LinkRow(
                    icon: Icons.help_outline_rounded,
                    accent: accent,
                    tokens: tokens,
                    label: 'Help & FAQ',
                    onTap: () => open(HelpFaq()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Building blocks
// ─────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.tokens});

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

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children, required this.tokens});

  final List<Widget> children;
  final ProfileTabTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.tokens});

  final ProfileTabTokens tokens;

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, indent: 64, color: tokens.divider);
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 19, color: accent),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.accent,
    required this.tokens,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color accent;
  final ProfileTabTokens tokens;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconTile(icon: icon, accent: accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.accent,
    required this.tokens,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final ProfileTabTokens tokens;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _IconTile(icon: icon, accent: accent),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: tokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
