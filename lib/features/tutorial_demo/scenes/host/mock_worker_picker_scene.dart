import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../mock/mock_worker.dart';
import '../../widgets/demo_fade_in.dart';
import '../../widgets/demo_theme.dart';

/// Mirrors the real "Select Gig Worker" sheet (`post_offered_gig_screen.dart`
/// → `_WorkerPickerSheet`) that opens when a host taps the Worker field
/// while posting an Offered Gig: a search bar and a favorites list, with
/// the chosen worker highlighted then checked off.
class MockWorkerPickerSheetScene extends StatelessWidget {
  final List<MockWorkerData> favorites;
  final MockWorkerData? selected;

  const MockWorkerPickerSheetScene({
    super.key,
    required this.favorites,
    this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 20),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: dBorder,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Select Gig Worker',
          style: TextStyle(
            color: dTitle,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: dBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dBorder),
            ),
            child: const Row(
              children: [
                Icon(Icons.search_rounded, color: dMuted, size: 18),
                SizedBox(width: 8),
                Text(
                  'Search your favorites…',
                  style: TextStyle(color: dMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (var i = 0; i < favorites.length; i++)
                DemoFadeIn(
                  delay: Duration(milliseconds: 150 + i * 200),
                  child: _WorkerRow(
                    worker: favorites[i],
                    isSelected: favorites[i].name == selected?.name,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WorkerRow extends StatelessWidget {
  final MockWorkerData worker;
  final bool isSelected;
  const _WorkerRow({required this.worker, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? kGold.withValues(alpha: 0.08) : dCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isSelected ? kGold : dBorder),
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
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.favorite_rounded, color: Color(0xFFEC4899), size: 11),
                    const SizedBox(width: 4),
                    Text(
                      '${worker.skill} · Favorite',
                      style: const TextStyle(color: dMuted, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isSelected)
            const Icon(Icons.check_circle_rounded, color: kGold, size: 20),
        ],
      ),
    );
  }
}

/// Confirmation shown right after the host sends the offer.
class MockOfferSentScene extends StatelessWidget {
  final MockWorkerData worker;
  const MockOfferSentScene({super.key, required this.worker});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: kBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.send_rounded, color: kBlue, size: 30),
          ),
          const SizedBox(height: 16),
          Text(
            'Offer sent to ${worker.name}',
            style: const TextStyle(
              color: dTitle,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Waiting for a response…',
            style: TextStyle(color: dBody, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
