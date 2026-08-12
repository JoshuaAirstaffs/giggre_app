import 'mock_gig.dart';
import 'mock_host.dart';

/// Purely local example data for the automated demo — this never triggers a
/// real push notification.
class MockNotificationData {
  final String title;
  final String body;

  const MockNotificationData({required this.title, required this.body});
}

final mockOfferNotification = MockNotificationData(
  title: 'New Gig Offer from ${mockMariaSantos.name}',
  body:
      '${mockOfferedGigCeilingLight.title} · '
      '\$${mockOfferedGigCeilingLight.payment}',
);
