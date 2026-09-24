import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giggre_app/features/gig_host/models/worker_slot_model.dart';

// The host's multi-worker cards are labelled "Worker 1/2/3…". The number has
// to stay put when someone else leaves, or "Worker 2 is no longer
// continuing" would point at the wrong card.
void main() {
  Map<String, dynamic> slot(
    String id,
    int minute, {
    String status = 'working',
    String field = 'selectedAt',
  }) => {
    'workerId': id,
    'status': status,
    field: Timestamp.fromDate(DateTime(2026, 9, 25, 9, minute)),
  };

  test('numbers follow the order workers joined', () {
    expect(workerSlotNumbers([slot('c', 3), slot('a', 1), slot('b', 2)]), {
      'a': 1,
      'b': 2,
      'c': 3,
    });
  });

  test('a cancelled worker keeps their number, so others do not shift', () {
    final numbers = workerSlotNumbers([
      slot('a', 1),
      slot('b', 2, status: 'cancelled'),
      slot('c', 3),
      slot('d', 4), // replacement
    ]);
    expect(numbers, {'a': 1, 'b': 2, 'c': 3, 'd': 4});
  });

  test('declined candidates get no number', () {
    expect(
      workerSlotNumbers([slot('a', 1), slot('x', 2, status: 'declined')]),
      {'a': 1},
    );
  });

  test('quick and offered gigs number by their own join field', () {
    expect(
      workerSlotNumbers([
        slot('q2', 5, field: 'dispatchedAt'),
        slot('q1', 1, field: 'dispatchedAt'),
        slot('o1', 3, field: 'offeredAt'),
      ]),
      {'q1': 1, 'o1': 2, 'q2': 3},
    );
  });

  test('a slot whose server timestamp is still pending goes last', () {
    expect(
      workerSlotNumbers([
        {'workerId': 'new', 'status': 'navigating'},
        slot('a', 1),
      ]),
      {'a': 1, 'new': 2},
    );
  });
}
