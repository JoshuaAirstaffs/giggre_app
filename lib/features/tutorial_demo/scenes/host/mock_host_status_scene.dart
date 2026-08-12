import 'package:flutter/material.dart';
import '../../mock/mock_gig.dart';
import '../../widgets/demo_host_gig_status_card.dart';
import '../../widgets/demo_theme.dart';

/// Host-side confirmation once a worker accepts/is assigned — reused across
/// the Quick/Open/Offered Gig sequences' final beat.
class MockHostStatusScene extends StatelessWidget {
  final String heading;
  final MockGigData gig;
  final String status;
  final Color statusColor;
  final String? subline;

  const MockHostStatusScene({
    super.key,
    required this.heading,
    required this.gig,
    required this.status,
    this.statusColor = dProgressStatus,
    this.subline,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: dProgressStatus, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  heading,
                  style: const TextStyle(
                    color: dTitle,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        DemoHostGigStatusCard(
          gig: gig,
          status: status,
          statusColor: statusColor,
          subline: subline,
        ),
      ],
    );
  }
}
