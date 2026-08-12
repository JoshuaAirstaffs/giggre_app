import 'mock_worker.dart';

/// Purely local example data for the automated demo — no real interest in
/// a gig is ever recorded. Mirrors the fields the real "Interested
/// Workers" list shows per worker (see `_ApplicantTile`).
class MockApplicationData {
  final MockWorkerData worker;
  final double rating;
  final int ratingCount;
  final int completedGigs;

  const MockApplicationData({
    required this.worker,
    this.rating = 4.9,
    this.ratingCount = 12,
    this.completedGigs = 8,
  });
}

const mockOpenGigApplicants = [
  MockApplicationData(worker: juanDelaCruz, ratingCount: 21, completedGigs: 14),
  MockApplicationData(worker: markReyes, rating: 4.7, ratingCount: 9, completedGigs: 6),
];
