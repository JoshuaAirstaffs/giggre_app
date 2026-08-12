/// Purely local example data for the automated demo — never read from or
/// written to Firestore, and never touches a real user's skills. Status
/// values match the real Toolchest's request states exactly (see
/// `toolchest_sheet.dart`'s `_ApplySkillCard._statusBadge` — "Approved"/
/// "Pending", not "Verified"/"Pending Verification").
class MockSkillData {
  final String name;
  final String status; // 'approved' | 'pending'

  const MockSkillData({required this.name, required this.status});
}

const mockExistingSkills = [
  MockSkillData(name: 'Electrician', status: 'approved'),
  MockSkillData(name: 'General Assistance', status: 'approved'),
];

const mockNewSkillPending = MockSkillData(name: 'Carpentry', status: 'pending');

const mockNewSkillApproved = MockSkillData(name: 'Carpentry', status: 'approved');
