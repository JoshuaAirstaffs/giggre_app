import 'package:flutter/material.dart';

enum SocialProvider { google, apple }

/// A Google or Apple sign-in button styled like the store badges: a raised
/// light pill with a soft shadow, the logo on the left and a two-line label
/// ("Continue with" over the provider name), so it reads clearly as a button.
///
/// Shared by the welcome, login and register screens.
class SocialSignInButton extends StatelessWidget {
  const SocialSignInButton({
    super.key,
    required this.provider,
    required this.loading,
    required this.onPressed,
    this.caption = 'Continue with',
    this.height = 56,
    this.radius = 16,
  });

  final SocialProvider provider;
  final bool loading;
  final VoidCallback onPressed;
  final String caption;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isGoogle = provider == SocialProvider.google;

    final bg = isDark ? const Color(0xFF243247) : const Color(0xFFF7F8FA);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.06);
    final fg = isDark ? Colors.white : const Color(0xFF1F1F1F);
    final sub = isDark ? Colors.white70 : const Color(0xFF5F6368);
    final shape = BorderRadius.circular(radius);

    final logo = loading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : isGoogle
        ? Image.asset('assets/images/g-logo.png', width: 24, height: 24)
        : Icon(Icons.apple, color: fg, size: 28);

    return Semantics(
      button: true,
      label: '$caption ${isGoogle ? 'Google' : 'Apple'}',
      excludeSemantics: true,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: shape,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: shape,
            side: BorderSide(color: border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: loading ? null : onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  logo,
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loading ? 'Signing in…' : caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.1,
                            fontWeight: FontWeight.w500,
                            color: sub,
                          ),
                        ),
                        Text(
                          isGoogle ? 'Google' : 'Apple',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                      ],
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
