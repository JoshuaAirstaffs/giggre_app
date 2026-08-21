import 'package:flutter/material.dart';
import '../../../gig_worker/presentation/widgets/offered_gig_offer_card.dart';
import '../../mock/mock_gig.dart';
import '../../mock/mock_gig_marker.dart';
import '../../widgets/demo_theme.dart';

/// Shows a direct Offered Gig from the worker's point of view, reusing the
/// real (pure, data-in/callback-out) `OfferedGigOfferCard` — it takes a
/// plain `GigMarkerData` value object, never a live Firestore stream, so
/// it's safe to reuse as-is with mock data.
class MockOfferedGigViewScene extends StatelessWidget {
  final MockGigData gig;
  final String hostName;
  final String perspectiveLabel;

  const MockOfferedGigViewScene({
    super.key,
    required this.gig,
    required this.hostName,
    this.perspectiveLabel = "On the worker's phone",
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          Text(
            perspectiveLabel,
            style: const TextStyle(
              color: dMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          OfferedGigOfferCard(
            gig: mockGigMarker(gig, hostName: hostName),
            description: gig.description,
            skillRequired: gig.requiredSkill ?? '',
            onAccept: () {},
            onDecline: () {},
            onDecideLater: () {},
          ),
        ],
      ),
    );
  }
}
