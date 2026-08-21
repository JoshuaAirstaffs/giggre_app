import 'package:flutter/material.dart';
import '../../mock/mock_gig.dart';
import '../../widgets/demo_quick_gig_offer_card.dart';
import '../../widgets/demo_theme.dart';

/// Shows the Quick Gig offer from the worker's point of view.
class MockQuickGigOfferScene extends StatelessWidget {
  final MockGigData gig;
  final String perspectiveLabel;

  const MockQuickGigOfferScene({
    super.key,
    required this.gig,
    this.perspectiveLabel = "On the worker's phone",
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 20),
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
        DemoQuickGigOfferCard(gig: gig),
      ],
    );
  }
}
