import 'package:flutter/material.dart';
import '../../../../core/models/rating_summary.dart';
import '../../../tutorial/widgets/tutorial_anchor.dart';

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
  final VoidCallback? onTutorial;

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
    this.onTutorial,
  });

  @override
  Widget build(BuildContext context) {
    // Even when a caller asks for the back arrow, don't render one with
    // nothing to pop to (e.g. if ever shown at the root of the navigator).
    final showBack = showBackButton && Navigator.canPop(context);

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(26),
        bottomRight: Radius.circular(26),
      ),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2B6FB5), Color(0xFF1F4D80)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 44),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title row ────────────────────────────────────────────
                Row(
                  children: [
                    if (showBack) ...[
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    const Expanded(
                      child: Text(
                        'Gig Worker Dashboard',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (onTutorial != null) ...[
                      GestureDetector(
                        onTap: onTutorial,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.school_outlined,
                            color: Colors.white,
                            size: 19,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (onNotifications != null) ...[
                      GestureDetector(
                        onTap: onNotifications,
                        child: TutorialAnchor(
                          id: 'workerHome.notificationsBell',
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.notifications_outlined,
                              color: Colors.white,
                              size: 19,
                            ),
                          ),
                        ),
                      ),
                      if (onSwitchToHost != null) const SizedBox(width: 8),
                    ],
                    if (onSwitchToHost != null)
                      GestureDetector(
                        onTap: onSwitchToHost,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.sync_alt,
                            color: Colors.white,
                            size: 19,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
