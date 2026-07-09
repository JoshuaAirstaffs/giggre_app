import 'package:cloud_firestore/cloud_firestore.dart';

class EarningsService {
  // Updates a worker's aggregated earnings inside an existing Firestore
  // transaction. Reads the current earnings map, handles the ISO-week reset
  // if the stored week differs from currentWeek, then writes the new totals.
  //
  // Call this alongside the gig status update so both writes are atomic.
  static Future<void> incrementInTransaction({
    required Transaction tx,
    required DocumentReference workerRef,
    required double budget,
    required String currencyCode,
    required String currentWeek,
  }) async {
    final workerSnap = await tx.get(workerRef);
    final data = workerSnap.data() as Map<String, dynamic>? ?? {};
    final earningsData = (data['earnings'] as Map<String, dynamic>?) ?? {};

    final storedWeek = earningsData['currentWeek'] as String? ?? '';
    final rawTotal =
        Map<String, dynamic>.from(
          (earningsData['total'] as Map<String, dynamic>?) ?? {},
        );
    // Reset weekly bucket when the calendar week has rolled over.
    final rawWeekly =
        storedWeek == currentWeek
            ? Map<String, dynamic>.from(
                (earningsData['weekly'] as Map<String, dynamic>?) ?? {},
              )
            : <String, dynamic>{};

    rawTotal[currencyCode] =
        ((rawTotal[currencyCode] as num?)?.toDouble() ?? 0) + budget;
    rawWeekly[currencyCode] =
        ((rawWeekly[currencyCode] as num?)?.toDouble() ?? 0) + budget;

    final prevCompleted =
        (earningsData['completedGigs'] as num?)?.toInt() ?? 0;

    tx.update(workerRef, {
      'earnings': {
        'total': rawTotal,
        'weekly': rawWeekly,
        'currentWeek': currentWeek,
        'completedGigs': prevCompleted + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    });
  }

  // Returns the current ISO 8601 week label, e.g. "2026-W28".
  // ISO weeks start on Monday; week 1 contains the first Thursday of the year.
  static String currentWeekLabel() {
    final now = DateTime.now();
    // The ISO week-year is the year of the Thursday in the same week.
    final thursday = now.subtract(Duration(days: now.weekday - 4));
    final weekYear = thursday.year;
    final jan4 = DateTime(weekYear, 1, 4);
    final week1Monday = jan4.subtract(Duration(days: jan4.weekday - 1));
    final weekNumber = (now.difference(week1Monday).inDays ~/ 7) + 1;
    return '$weekYear-W${weekNumber.toString().padLeft(2, '0')}';
  }
}
