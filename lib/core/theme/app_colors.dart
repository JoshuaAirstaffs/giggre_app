import 'package:flutter/material.dart';

const kBg     = Color(0xFF0F172A);
const kCard   = Color(0xFF1E293B);
const kBlue   = Color(0xFF046BD2);
const kAmber  = Color(0xFFFBBF24);
const kGold   = Color(0xFFF0A830); // brand accent — stays the same in light & dark
const kSub    = Color(0xFF94A3B8);
const kBorder = Color(0xFF2D3F55);

// ── Chat text roles ─────────────────────────────────────────────────────────
// Shared by the one-to-one and group chats so their small text can't drift.
// Measured against the app's seed scheme: meta (68%) is 5.65:1 on the light
// chat background #F1F5F9, 5.88:1 on white, 6.91:1 on kBg, 6.05:1 on kCard;
// sender (80%) is 7.8–9.1:1. All clear WCAG AA (4.5:1).

/// Message time, pending / seen marks, day dividers, empty-state body.
Color chatMetaColor(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.68);

/// Time under a message run.
TextStyle chatMetaStyle(BuildContext context) => TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w500,
  color: chatMetaColor(context),
);

/// Who sent a run of group messages.
TextStyle chatSenderStyle(BuildContext context) => TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
);

/// Blue for text, links, icons and tinted badges. kBlue stays for fills
/// (white on kBlue is 5.2:1), but as text it drops to 4.4:1 on a light grey
/// bubble and ~2:1 on dark surfaces. Measured worst cases: light #0360BE
/// 5.12:1 (on its own 12% tint), dark #7AB8F7 4.80:1 (grey800 bubble).
Color blueText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF7AB8F7)
    : const Color(0xFF0360BE);
