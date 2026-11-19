import 'package:flutter/material.dart';
import '../../../../core/models/rating_summary.dart';
import '../../../tutorial/widgets/tutorial_anchor.dart';
import '../../../../core/widgets/dashboard_header_bar.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Worker Header — blue gradient band
// ─────────────────────────────────────────────────────────────────────────────
class WorkerHeader extends StatelessWidget {
  final String userId;
  final String email;
  final String phone;
  final RatingSummary rating;
  final String memberSince;
  final bool isDark;
  final bool showBackButton;
  final VoidCallback? onNotifications;
  final VoidCallback? onSwitchToHost;
  // House button top-left → the Home screen.
  final VoidCallback? onGoHome;
  final VoidCallback? onTutorial;
  // Optional line under the title (the worker's earnings)
  final Widget? subtitle;
  // band + a pinned bar over the page: see DashboardHeaderPart.
  final DashboardHeaderPart part;
  final bool solid;

  const WorkerHeader({
    super.key,
    required this.userId,
    required this.email,
    required this.phone,
    required this.rating,
    required this.memberSince,
    required this.isDark,
    this.showBackButton = true,
    this.onNotifications,
    this.onSwitchToHost,
    this.onGoHome,
    this.onTutorial,
    this.subtitle,
    this.part = DashboardHeaderPart.full,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    // Even when a caller asks for the back arrow, don't render one with
    // nothing to pop to (e.g. if ever shown at the root of the navigator).
    final showBack = showBackButton && Navigator.canPop(context);

    // Same bar as the Gig Host dashboard (DashboardHeaderBar), so switching
    // mode doesn't shift anything in the header.
    return DashboardHeaderBar(
      colors: const [Color(0xFF2B6FB5), Color(0xFF1F4D80)],
      isHost: false,
      onGoHome: onGoHome,
      showBack: showBack,
      onSwitchMode: onSwitchToHost,
      subtitle: subtitle,
      part: part,
      solid: solid,
      actions: [
        if (onTutorial != null)
          HeaderCircleButton(
            icon: Icons.school_outlined,
            tooltip: 'Tutorial',
            onTap: onTutorial,
          ),
        if (onNotifications != null)
          TutorialAnchor(
            id: 'workerHome.notificationsBell',
            child: HeaderCircleButton(
              icon: Icons.notifications_outlined,
              tooltip: 'Notifications',
              onTap: onNotifications,
            ),
          ),
      ],
    );
  }
}
