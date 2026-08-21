/// Purely local example data for the automated demo — never read from or
/// written to Firestore. Distances/performance figures illustrate the sort
/// of factors a match can involve; they are not a claim about the exact
/// production matching algorithm.
class MockWorkerData {
  final String name;
  final String skill;
  final String verification;
  final double distanceMiles;
  final bool activeMode;
  final bool quickGigsOn;
  final String performance;

  const MockWorkerData({
    required this.name,
    required this.skill,
    required this.verification,
    required this.distanceMiles,
    required this.activeMode,
    required this.quickGigsOn,
    this.performance = '',
  });
}

const juanDelaCruz = MockWorkerData(
  name: 'Mike Johnson',
  skill: 'Electrician',
  verification: 'Verified',
  distanceMiles: 0.5,
  activeMode: true,
  quickGigsOn: true,
  performance: 'Excellent',
);

const markReyes = MockWorkerData(
  name: 'David Kim',
  skill: 'Plumber',
  verification: 'Verified',
  distanceMiles: 0.8,
  activeMode: true,
  quickGigsOn: true,
  performance: 'Good',
);

const carloGarcia = MockWorkerData(
  name: 'Alex Turner',
  skill: 'General Assistance',
  verification: 'Verified',
  distanceMiles: 1.5,
  activeMode: true,
  quickGigsOn: false,
  performance: 'Good',
);

const mockNearbyWorkers = [juanDelaCruz, markReyes, carloGarcia];
