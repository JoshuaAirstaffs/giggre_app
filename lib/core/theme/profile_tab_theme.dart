import 'package:flutter/material.dart';
import 'app_colors.dart';

// Theme-aware surface/text tokens for the redesigned Profile tab.
// Registered on ThemeData via `extensions:` in ThemeProvider — read with
// `Theme.of(context).extension<ProfileTabTokens>()!`.
class ProfileTabTokens extends ThemeExtension<ProfileTabTokens> {
  final Color screenBg;
  final Color cardSurface;
  final Color cardBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color divider;
  final Color insetBg;
  final double iconTintAlpha;
  final Color segmentTrack;

  const ProfileTabTokens({
    required this.screenBg,
    required this.cardSurface,
    required this.cardBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.divider,
    required this.insetBg,
    required this.iconTintAlpha,
    required this.segmentTrack,
  });

  static const light = ProfileTabTokens(
    screenBg: Color(0xFFF4F6FA),
    cardSurface: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFE4E9F0),
    textPrimary: Color(0xFF17263D),
    textSecondary: Color(0xFF5A6778),
    textMuted: Color(0xFF94A0B0),
    divider: Color(0xFFEEF2F7),
    insetBg: Color(0xFFFAFBFD),
    iconTintAlpha: 0.14,
    segmentTrack: Color(0xFFEAEEF4),
  );

  static const dark = ProfileTabTokens(
    screenBg: kBg,
    cardSurface: kCard,
    cardBorder: kBorder,
    textPrimary: Color(0xFFE8EDF5),
    textSecondary: Color(0xFFA9B4C4),
    textMuted: Color(0xFF7C8798),
    divider: Color(0x0FFFFFFF), // rgba(255,255,255,.06)
    insetBg: Color(0xFF19222F),
    iconTintAlpha: 0.22,
    segmentTrack: kCard,
  );

  @override
  ProfileTabTokens copyWith({
    Color? screenBg,
    Color? cardSurface,
    Color? cardBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? divider,
    Color? insetBg,
    double? iconTintAlpha,
    Color? segmentTrack,
  }) {
    return ProfileTabTokens(
      screenBg: screenBg ?? this.screenBg,
      cardSurface: cardSurface ?? this.cardSurface,
      cardBorder: cardBorder ?? this.cardBorder,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      divider: divider ?? this.divider,
      insetBg: insetBg ?? this.insetBg,
      iconTintAlpha: iconTintAlpha ?? this.iconTintAlpha,
      segmentTrack: segmentTrack ?? this.segmentTrack,
    );
  }

  @override
  ProfileTabTokens lerp(ThemeExtension<ProfileTabTokens>? other, double t) {
    if (other is! ProfileTabTokens) return this;
    return ProfileTabTokens(
      screenBg: Color.lerp(screenBg, other.screenBg, t)!,
      cardSurface: Color.lerp(cardSurface, other.cardSurface, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      insetBg: Color.lerp(insetBg, other.insetBg, t)!,
      iconTintAlpha: iconTintAlpha + (other.iconTintAlpha - iconTintAlpha) * t,
      segmentTrack: Color.lerp(segmentTrack, other.segmentTrack, t)!,
    );
  }
}
