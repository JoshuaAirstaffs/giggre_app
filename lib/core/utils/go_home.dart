import 'package:flutter/material.dart';

import '../widgets/main_navigation.dart';

/// Bottom-nav "Home": back to the Home screen ("Choose a mode to get
/// started"), which sits underneath the Gig Worker / Gig Host screens. If
/// it isn't there (e.g. the app was opened straight into a dashboard), it
/// is opened fresh.
void goToHome(BuildContext context) {
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.popUntil((route) => route.isFirst);
  } else {
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainNavigation()),
      (route) => false,
    );
  }
}
