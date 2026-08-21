/// Purely local example data for the automated demo — never read from or
/// written to Firestore.
class MockGigData {
  final String title;
  final String description;
  final String location;
  final int payment;
  final String currencyCode;
  final String gigType; // 'quick' | 'open' | 'offered'
  final String? requiredSkill;
  final String status;
  final double distanceMiles;

  const MockGigData({
    required this.title,
    required this.description,
    required this.location,
    required this.payment,
    this.currencyCode = 'USD',
    required this.gigType,
    this.requiredSkill,
    required this.status,
    this.distanceMiles = 0,
  });
}

const mockQuickGigPackage = MockGigData(
  title: 'Pick up my package',
  description:
      'Pick up a package from the nearby courier office and deliver it to my home.',
  location: 'Austin, TX',
  payment: 20,
  gigType: 'quick',
  status: 'Searching for a Worker',
);

const mockOpenGigElectrician = MockGigData(
  title: 'Fix electrical outlet',
  description:
      'Need an electrician to inspect and repair an electrical outlet.',
  location: 'Austin, TX',
  payment: 120,
  gigType: 'open',
  requiredSkill: 'Electrician',
  status: 'Open',
  distanceMiles: 1.3,
);

const mockOfferedGigCeilingLight = MockGigData(
  title: 'Install ceiling light',
  description: 'Install a new ceiling light in the living room.',
  location: 'Austin, TX',
  payment: 95,
  gigType: 'offered',
  requiredSkill: 'Electrician',
  status: 'Offered',
);
