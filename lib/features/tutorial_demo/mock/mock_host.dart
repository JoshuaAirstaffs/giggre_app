/// Purely local example data for the automated demo — never read from or
/// written to Firestore.
class MockHostData {
  final String name;
  final String location;

  const MockHostData({required this.name, required this.location});
}

const mockMariaSantos = MockHostData(name: 'Emily Carter', location: 'Austin, TX');
