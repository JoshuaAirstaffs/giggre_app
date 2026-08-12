import 'package:flutter/material.dart';

/// Light-mode palette for the demo — deliberately matching the exact hex
/// values the real screens already use for their (always-light) card
/// surfaces: [HostGigCard]'s `_kTitleColor`/`_kBodyColor`/etc. and
/// `ThemeProvider.lightTheme`/`ProfileTabTokens.light`. The demo is meant
/// to look like the real app, so it borrows the real app's colors rather
/// than inventing a separate one.
const dBg = Color(0xFFF1F5F9); // ThemeProvider.lightTheme.scaffoldBackgroundColor
const dCard = Colors.white;
const dBorder = Color(0xFFE4E9F0); // HostGigCard._kCardBorder
const dTitle = Color(0xFF17263D); // HostGigCard._kTitleColor
const dBody = Color(0xFF5A6778); // HostGigCard._kBodyColor
const dMuted = Color(0xFF94A0B0); // HostGigCard._kMutedColor
const dChevron = Color(0xFFB7C0CD); // HostGigCard._kChevronColor

// Status colors, matching HostGigCard's `_statusMeta` exactly.
const dOpenStatus = Color(0xFF2B6FB5);
const dProgressStatus = Color(0xFF2E9E6B);
const dCancelStatus = Color(0xFFE5484D);
const dWrapUpStatus = Color(0xFFB06E00);
const dOfferedStatus = Color(0xFF8B5CF6);
