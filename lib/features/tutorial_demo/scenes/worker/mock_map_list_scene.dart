import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../mock/mock_gig.dart';
import '../../widgets/demo_fade_in.dart';
import '../../widgets/demo_theme.dart';

/// Simplified Map/List toggle for Open Gigs — a self-contained visual, not
/// the real `GigMapSection` (which streams live Firestore gigs and calls
/// Google/Flutter Maps). [isMapView] switches which representation shows.
class MockOpenGigMapListScene extends StatelessWidget {
  final bool isMapView;
  final MockGigData highlighted;

  const MockOpenGigMapListScene({
    super.key,
    required this.isMapView,
    this.highlighted = mockOpenGigElectrician,
  });

  static const _otherTitles = ['Clean the yard', 'Move furniture'];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 20),
        _ViewToggle(isMapView: isMapView),
        const SizedBox(height: 16),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: isMapView
                ? _MapView(highlighted: highlighted, others: _otherTitles)
                : _ListView(highlighted: highlighted, others: _otherTitles),
          ),
        ),
      ],
    );
  }
}

class _ViewToggle extends StatelessWidget {
  final bool isMapView;
  const _ViewToggle({required this.isMapView});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: dCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment('Map', Icons.map_rounded, isMapView),
          _segment('List', Icons.list_rounded, !isMapView),
        ],
      ),
    );
  }

  Widget _segment(String label, IconData icon, bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: active ? kGold : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: active ? Colors.white : dBody),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : dBody,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapView extends StatelessWidget {
  final MockGigData highlighted;
  final List<String> others;
  const _MapView({required this.highlighted, required this.others});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 260,
        height: 220,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: dCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: dBorder),
        ),
        child: Stack(
          children: [
            const Center(
              child: Icon(Icons.map_rounded, color: dBorder, size: 110),
            ),
            Positioned(
              top: 40,
              left: 100,
              child: DemoFadeIn(child: _pin(highlighted.title, kGold)),
            ),
            Positioned(
              top: 120,
              left: 40,
              child: DemoFadeIn(
                delay: const Duration(milliseconds: 300),
                child: _pin(others[0], kBlue),
              ),
            ),
            Positioned(
              bottom: 30,
              right: 40,
              child: DemoFadeIn(
                delay: const Duration(milliseconds: 500),
                child: _pin(others[1], kBlue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pin(String label, Color color) {
    return Icon(Icons.location_on_rounded, color: color, size: 30);
  }
}

class _ListView extends StatelessWidget {
  final MockGigData highlighted;
  final List<String> others;
  const _ListView({required this.highlighted, required this.others});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        DemoFadeIn(child: _tile(highlighted.title, '\$${highlighted.payment}', kGold)),
        for (var i = 0; i < others.length; i++)
          DemoFadeIn(
            delay: Duration(milliseconds: 200 + i * 150),
            child: _tile(others[i], '\$${400 + i * 100}', kBlue),
          ),
      ],
    );
  }

  Widget _tile(String title, String pay, Color accent) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent == kGold ? kGold : dBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.work_outline_rounded, color: accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: dTitle,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ),
          Text(
            pay,
            style: TextStyle(
              color: accent,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
