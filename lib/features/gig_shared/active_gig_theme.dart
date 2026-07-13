import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Active Gig design tokens — shared by the worker (blue) and host (gold)
//  "in progress" screens so both stay visually consistent. Structural colors
//  (bg/card/border/text) flip with the app theme; brand and status accents
//  (green/red) stay the same in both themes and both roles.
// ─────────────────────────────────────────────────────────────────────────────
Color activeGigScreenBg(bool isDark) => isDark ? kBg : const Color(0xFFF4F6FA);
Color activeGigCardBg(bool isDark) => isDark ? kCard : Colors.white;
Color activeGigCardBorder(bool isDark) =>
    isDark ? kBorder : const Color(0xFFE4E9F0);
const double kActiveGigCardRadius = 16.0;
Color activeGigTextPrimary(bool isDark) =>
    isDark ? Colors.white : const Color(0xFF17263D);
Color activeGigTextSecondary(bool isDark) =>
    isDark ? const Color(0xFFB6C2D1) : const Color(0xFF5A6778);
Color activeGigTextMuted(bool isDark) =>
    isDark ? kSub : const Color(0xFF94A0B0);
Color activeGigTextDisabled(bool isDark) =>
    isDark ? const Color(0xFF64748B) : const Color(0xFFB7C0CD);
const Color kActiveGigSuccessGreen = Color(0xFF2E9E6B);
const Color kActiveGigDestructiveRed = Color(0xFFE5484D);
Color activeGigDestructiveBorder(bool isDark) =>
    isDark ? Colors.redAccent.withValues(alpha: 0.35) : const Color(0xFFF5C6C8);
Color activeGigDividerColor(bool isDark) =>
    isDark ? kBorder : const Color(0xFFEEF2F7);
Color activeGigTrackBg(bool isDark) =>
    isDark ? const Color(0xFF334155) : const Color(0xFFE4E9F0);

/// Role accent — swaps the brand color used for the header gradient, step
/// tracker fill, and icon tints. Structural tokens above stay identical for
/// both roles.
class ActiveGigAccent {
  final Color gradientStart;
  final Color gradientEnd;
  final Color solid;
  final Color onWhiteText;
  const ActiveGigAccent({
    required this.gradientStart,
    required this.gradientEnd,
    required this.solid,
    required this.onWhiteText,
  });
}

const kWorkerAccent = ActiveGigAccent(
  gradientStart: Color(0xFF2B6FB5),
  gradientEnd: Color(0xFF1F4D80),
  solid: Color(0xFF2B6FB5),
  onWhiteText: Color(0xFF2B6FB5),
);

const kHostAccent = ActiveGigAccent(
  gradientStart: Color(0xFFF0A830),
  gradientEnd: Color(0xFFD88810),
  solid: Color(0xFFD88810),
  onWhiteText: Color(0xFFB06E00),
);
