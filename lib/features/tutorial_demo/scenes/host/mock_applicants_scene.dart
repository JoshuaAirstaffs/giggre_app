import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../mock/mock_application.dart';
import '../../mock/mock_gig.dart';
import '../../widgets/demo_fade_in.dart';
import '../../widgets/demo_theme.dart';

/// Shows the Open Gig live on the worker-facing map/list, with a few
/// skilled workers "viewing" it.
class MockGigLiveOnWorkerFeedScene extends StatelessWidget {
  final MockGigData gig;
  final int viewerCount;

  const MockGigLiveOnWorkerFeedScene({
    super.key,
    required this.gig,
    this.viewerCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 240,
            height: 150,
            decoration: BoxDecoration(
              color: dCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: dBorder),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.map_rounded, color: dBorder, size: 90),
                Positioned(
                  top: 34,
                  left: 100,
                  child: DemoFadeIn(
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: kGold,
                      size: 30,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '"${gig.title}" is now visible to nearby workers',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: dTitle,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          DemoFadeIn(
            delay: const Duration(milliseconds: 500),
            child: Text(
              '$viewerCount skilled workers viewing this gig',
              style: const TextStyle(color: dBody, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Interested Workers" section, matching the real Open Gig detail sheet's
/// `_buildApplicantsSection`/`_ApplicantTile` exactly: a heading with a
/// count badge, one row per interested worker with a rating line and a
/// green "Select" button, replaced with a checkmark once chosen.
class MockApplicantsScene extends StatelessWidget {
  final List<MockApplicationData> applicants;
  final String? selectedWorkerName;

  const MockApplicantsScene({
    super.key,
    required this.applicants,
    this.selectedWorkerName,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Interested Workers',
                style: TextStyle(
                  color: dTitle,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: dOpenStatus.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${applicants.length}',
                  style: const TextStyle(
                    color: dOpenStatus,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < applicants.length; i++)
            DemoFadeIn(
              delay: Duration(milliseconds: 150 + i * 350),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _InterestedWorkerRow(
                  applicant: applicants[i],
                  isSelected: applicants[i].worker.name == selectedWorkerName,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InterestedWorkerRow extends StatelessWidget {
  final MockApplicationData applicant;
  final bool isSelected;
  const _InterestedWorkerRow({required this.applicant, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final worker = applicant.worker;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: dCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isSelected ? dProgressStatus : dBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: kGold.withValues(alpha: 0.15),
            child: Text(
              worker.name.isNotEmpty ? worker.name[0] : '?',
              style: const TextStyle(color: kGold, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  worker.name,
                  style: const TextStyle(
                    color: dTitle,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: const TextStyle(color: dMuted, fontSize: 10.5),
                    children: [
                      const TextSpan(text: '★ ', style: TextStyle(color: kGold)),
                      TextSpan(
                        text:
                            '${applicant.rating.toStringAsFixed(1)} (${applicant.ratingCount}) · ${applicant.completedGigs} gigs done',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: isSelected
                ? const Icon(Icons.check_circle_rounded, color: dProgressStatus)
                : ElevatedButton(
                    onPressed: null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: dProgressStatus,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: dProgressStatus,
                      disabledForegroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Select',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
