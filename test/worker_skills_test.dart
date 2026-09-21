import 'package:flutter_test/flutter_test.dart';
import 'package:giggre_app/core/utils/worker_skills.dart';

void main() {
  test('skills come from skillsXP, strongest first', () {
    expect(
      workerSkillsFrom({
        'skillsXP': {'Barista': 3, 'Deep cleaning': 12, 'Bar work': 7},
      }),
      ['Deep cleaning', 'Bar work', 'Barista'],
    );
  });

  test('equal experience falls back to alphabetical, so order is stable', () {
    expect(
      workerSkillsFrom({
        'skillsXP': {'waiting': 1, 'Bar work': 1, 'assembly': 1},
      }),
      ['assembly', 'Bar work', 'waiting'],
    );
  });

  test('the empty legacy skills array does not mask real skills', () {
    // Every user document carries `skills: []` from registration. Reading it
    // instead of skillsXP is what left profiles blank.
    expect(
      workerSkillsFrom({
        'skills': <dynamic>[],
        'skillsXP': {'Bar work': 4},
      }),
      ['Bar work'],
    );
  });

  test('a populated legacy array is still honoured when there is no XP', () {
    expect(
      workerSkillsFrom({
        'skills': ['Driving', ' Lifting '],
      }),
      ['Driving', 'Lifting'],
    );
  });

  test('missing, empty and malformed data give an empty list, never a throw', () {
    expect(workerSkillsFrom(null), isEmpty);
    expect(workerSkillsFrom({}), isEmpty);
    expect(workerSkillsFrom({'skillsXP': <String, dynamic>{}}), isEmpty);
    expect(workerSkillsFrom({'skillsXP': {'  ': 5}}), isEmpty);
    expect(workerSkillsFrom({'skillsXP': {'Bar work': null}}), ['Bar work']);
  });

  test('a host with no skills shows none rather than falling over', () {
    expect(workerSkillsFrom({'name': 'Riverside Cafe', 'skills': []}), isEmpty);
  });
}
