import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../mock/mock_notification.dart';
import 'demo_theme.dart';

/// Slide-down notification banner used to open the "worker receives a
/// direct offer" moment. Purely visual — never registers a real push
/// notification.
class DemoNotificationBanner extends StatefulWidget {
  final MockNotificationData notification;
  const DemoNotificationBanner({super.key, required this.notification});

  @override
  State<DemoNotificationBanner> createState() =>
      _DemoNotificationBannerState();
}

class _DemoNotificationBannerState extends State<DemoNotificationBanner> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      offset: _visible ? Offset.zero : const Offset(0, -1.4),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 350),
        opacity: _visible ? 1 : 0,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: dCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: dBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kBlue.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: kBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.notification.title,
                      style: const TextStyle(
                        color: dTitle,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.notification.body,
                      style: const TextStyle(color: dBody, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
