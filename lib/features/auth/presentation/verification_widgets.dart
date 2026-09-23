import 'package:flutter/material.dart';

import '../../../core/theme/profile_tab_theme.dart';

// Shared visual pieces for the email/phone verification screens — kept here
// so both stay pixel-consistent with each other and with the rest of the
// auth flow (gold gradient CTA, ProfileTabTokens-driven surfaces).

const kVerifyGold = Color(0xFFF0A830);
const kVerifyGoldDeep = Color(0xFFD88810);
const kVerifyBlue = Color(0xFF1B6CA8);
const kVerifyBlueLight = Color(0xFF4A9FDB);

// Soft glowing circle behind the screen's headline icon, gently pulsing to
// signal "we're listening for you" while verification is pending.
class VerificationIconBadge extends StatefulWidget {
  final IconData icon;
  const VerificationIconBadge({super.key, required this.icon});

  @override
  State<VerificationIconBadge> createState() => _VerificationIconBadgeState();
}

class _VerificationIconBadgeState extends State<VerificationIconBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 108 + (t * 14),
              height: 108 + (t * 14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kVerifyBlue.withValues(alpha: 0.10 - (t * 0.05)),
              ),
            ),
            child!,
          ],
        );
      },
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [kVerifyBlueLight, kVerifyBlue],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: kVerifyBlue.withValues(alpha: 0.30),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(widget.icon, size: 40, color: Colors.white),
      ),
    );
  }
}

// Theme-aware error banner — the plain red[50] box read wrong in dark mode.
class VerificationErrorBanner extends StatelessWidget {
  final String message;
  const VerificationErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0x33E57373) : const Color(0xFFFDECEC);
    final border = isDark ? const Color(0x66E57373) : const Color(0xFFF6C6C6);
    final fg = isDark ? const Color(0xFFFFB4B4) : const Color(0xFFC62828);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: fg, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: fg, fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

// The gold-gradient CTA used across welcome/login/signup, reused here so the
// verification screens feel like part of the same flow instead of a
// bolted-on afterthought.
class VerificationGradientButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  const VerificationGradientButton({
    super.key,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ).copyWith(
          backgroundColor: WidgetStateProperty.all(Colors.transparent),
          shadowColor: WidgetStateProperty.all(Colors.transparent),
          overlayColor: WidgetStateProperty.all(
            Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: disabled
                  ? [kVerifyGold.withValues(alpha: 0.5), kVerifyGoldDeep.withValues(alpha: 0.5)]
                  : const [kVerifyGold, kVerifyGoldDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: disabled
                ? null
                : [
                    BoxShadow(
                      color: kVerifyGoldDeep.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// Card wrapper shared by both screens so the content sits on a raised
// surface instead of floating directly on the scaffold background.
class VerificationCard extends StatelessWidget {
  final ProfileTabTokens tokens;
  final Widget child;
  const VerificationCard({super.key, required this.tokens, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tokens.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}
