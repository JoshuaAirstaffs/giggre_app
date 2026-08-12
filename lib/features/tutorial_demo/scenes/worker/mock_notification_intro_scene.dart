import 'package:flutter/material.dart';
import '../../mock/mock_notification.dart';
import '../../widgets/demo_notification_banner.dart';

/// Opening beat of the Direct/Offered Gig worker sequence — a notification
/// slides in as if it just arrived.
class MockNotificationIntroScene extends StatelessWidget {
  const MockNotificationIntroScene({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 60),
        DemoNotificationBanner(notification: mockOfferNotification),
      ],
    );
  }
}
