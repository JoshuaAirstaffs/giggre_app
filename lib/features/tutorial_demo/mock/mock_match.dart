import 'mock_worker.dart';

/// Purely local example data driving the Quick Gig "searching/matching"
/// animation — no real dispatch or matching engine is invoked.
class MockMatchData {
  final List<MockWorkerData> candidates;
  final MockWorkerData selected;

  const MockMatchData({required this.candidates, required this.selected});
}

const mockQuickGigMatch = MockMatchData(
  candidates: mockNearbyWorkers,
  selected: juanDelaCruz,
);
