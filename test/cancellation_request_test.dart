import 'package:flutter_test/flutter_test.dart';
import 'package:giggre_app/core/utils/cancellation_request.dart';

// The worker-side cancellation notices used to assume every pending request
// was the worker's own, so a host-requested cancellation read as "admin is
// reviewing your request" on the worker's screen. These pin the requester
// read that now drives that copy.
void main() {
  Map<String, dynamic> gigWithReasons(List<dynamic> reasons) => {
    'status': 'cancellation_requested',
    'cancellation_reason': reasons,
  };

  group('cancellationRequestedBy', () {
    test('reads the last entry, not the first', () {
      final data = gigWithReasons([
        {'reason': 'earlier', 'approved': false, 'requestedBy': 'worker'},
        {'reason': 'current', 'approved': null, 'requestedBy': 'host'},
      ]);
      expect(cancellationRequestedBy(data), 'host');
      expect(isHostRequestedCancellation(data), isTrue);
    });

    test('worker-initiated request is not attributed to the host', () {
      final data = gigWithReasons([
        {'reason': 'sick', 'approved': null, 'requestedBy': 'worker'},
      ]);
      expect(cancellationRequestedBy(data), 'worker');
      expect(isHostRequestedCancellation(data), isFalse);
    });

    test('null for missing, empty or malformed cancellation_reason', () {
      expect(cancellationRequestedBy(null), isNull);
      expect(cancellationRequestedBy({'status': 'working'}), isNull);
      expect(cancellationRequestedBy(gigWithReasons([])), isNull);
      expect(cancellationRequestedBy(gigWithReasons(['not a map'])), isNull);
    });

    test('legacy entry without requestedBy is not read as host', () {
      final data = gigWithReasons([
        {'reason': 'no requester field', 'approved': null},
      ]);
      expect(cancellationRequestedBy(data), isNull);
      expect(isHostRequestedCancellation(data), isFalse);
    });
  });

  group('hostCancellationRequestUpdate', () {
    // host_gig_card's cancel used to write neither of these: without
    // cancellationRequestedAt the request never showed in either side's
    // notification list (tryAdd bails on a null timestamp), and without
    // lastProgressStatus the host's stepper jumped to 'working'.
    test('carries the frozen step and the requested-at timestamp', () {
      final update = hostCancellationRequestUpdate(
        reason: 'weather',
        lastProgressStatus: 'navigating',
      );
      expect(update['status'], 'cancellation_requested');
      expect(update['lastProgressStatus'], 'navigating');
      expect(update['cancellationRequestedAt'], isNotNull);
      expect(update.containsKey('cancellation_reason'), isTrue);
    });
  });

  group('kHostCancellableSlotStatuses', () {
    test('covers every active slot stage but an already-pending one', () {
      expect(
        kHostCancellableSlotStatuses,
        containsAll(<String>[
          'navigating',
          'arrived',
          'working',
          'task_complete',
          'payment',
        ]),
      );
      expect(
        kHostCancellableSlotStatuses,
        isNot(contains('cancellation_requested')),
      );
    });
  });

  group('pendingCancellationBlockMessage', () {
    test("host request doesn't claim the worker asked", () {
      expect(
        pendingCancellationBlockMessage(kCancelRequesterHost),
        contains("The host's request"),
      );
    });

    test('worker and system requests keep the original copy', () {
      for (final by in [kCancelRequesterWorker, 'system']) {
        expect(
          pendingCancellationBlockMessage(by),
          startsWith('Your cancellation request'),
        );
      }
    });
  });

  group('releasedWorkersFor', () {
    Map<String, dynamic> slot(String id, String status, {String? by}) => {
      'workerId': id,
      'workerName': id.toUpperCase(),
      'status': status,
      if (by != null)
        'cancellation_reason': [
          {'reason': 'r', 'approved': true, 'requestedBy': by},
        ],
    };

    test('a cancelled slot names who asked', () {
      final host = releasedWorkersFor([
        slot('a', 'cancelled', by: kCancelRequesterHost),
      ]);
      expect(host.single.byHost, isTrue);
      final worker = releasedWorkersFor([
        slot('b', 'cancelled', by: kCancelRequesterWorker),
      ]);
      expect(worker.single.byHost, isFalse);
    });

    test('active slots are not released', () {
      expect(
        releasedWorkersFor([slot('c', 'working'), slot('d', 'navigating')]),
        isEmpty,
      );
    });

    test('legacy entries without requestedBy read as the worker', () {
      final out = releasedWorkersFor([slot('e', 'cancelled')]);
      expect(out.single.requestedBy, kCancelRequesterWorker);
    });
  });

  group('cancellationApprovedBySystem', () {
    Map<String, dynamic> approved(String? by) => {
      'cancellation_reason': [
        {'reason': 'r', 'approved': true, 'approvedBy': ?by},
      ],
    };

    test('auto-approved requests are recognised', () {
      expect(cancellationApprovedBySystem(approved('system')), isTrue);
    });

    test('admin approvals and missing data are not', () {
      expect(cancellationApprovedBySystem(approved('someAdminUid')), isFalse);
      expect(cancellationApprovedBySystem(approved(null)), isFalse);
      expect(cancellationApprovedBySystem(null), isFalse);
    });
  });
}
