import '../../core/utils/currency_formatter.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Gig progress steps — single source of truth for both the worker and host
//  "in progress" screens. Same 6-status Firestore values on both sides.
// ─────────────────────────────────────────────────────────────────────────────
enum GigStep { navigating, arrived, working, taskComplete, payment, completed }

GigStep gigStepFromStatus(String s) {
  switch (s) {
    case 'navigating':
      return GigStep.navigating;
    case 'arrived':
      return GigStep.arrived;
    case 'working':
      return GigStep.working;
    case 'task_complete':
      return GigStep.taskComplete;
    case 'payment':
      return GigStep.payment;
    case 'completed':
      return GigStep.completed;
    default:
      return GigStep.navigating;
  }
}

const kStepLabels = ['On the way', 'Arrived', 'Working', 'Done', 'Payment', 'Complete'];

// Title/body copy for the progress card's instruction block.
class GigStepCopy {
  final String title;
  final String body;
  const GigStepCopy(this.title, this.body);
}

GigStepCopy workerInstructionFor(
  GigStep step, {
  required double amount,
  required String currencyCode,
}) {
  switch (step) {
    case GigStep.navigating:
      return const GigStepCopy(
        'Head to the gig location',
        "We'll detect your arrival automatically within 40 m — no need to check in.",
      );
    case GigStep.arrived:
      return const GigStepCopy(
        "You've arrived!",
        'Waiting for the host to confirm and start the gig.',
      );
    case GigStep.working:
      return const GigStepCopy(
        'Gig in progress',
        'The host will mark the work as done when finished.',
      );
    case GigStep.taskComplete:
      return const GigStepCopy(
        'Work complete',
        'Waiting for the host to process your payment.',
      );
    case GigStep.payment:
      return GigStepCopy(
        'Payment processing',
        '${CurrencyFormatter.format(amount, currencyCode)} is on its way to you.',
      );
    case GigStep.completed:
      return const GigStepCopy(
        'All done — great work!',
        'This gig is complete. Rate your host below.',
      );
  }
}

GigStepCopy hostInstructionFor(
  GigStep step, {
  required String workerName,
  required double amount,
  required String currencyCode,
}) {
  switch (step) {
    case GigStep.navigating:
      return GigStepCopy(
        '$workerName is heading to your location',
        "Live location is shared · you'll be notified the moment they arrive.",
      );
    case GigStep.arrived:
      return GigStepCopy(
        '$workerName has arrived',
        'Confirm their arrival to start the gig.',
      );
    case GigStep.working:
      return const GigStepCopy(
        'Work in progress',
        'Mark the gig as done when the work is finished.',
      );
    case GigStep.taskComplete:
      return const GigStepCopy(
        'Work marked as done',
        'Review the work and proceed to payment.',
      );
    case GigStep.payment:
      return GigStepCopy(
        'Payment in progress',
        '${CurrencyFormatter.format(amount, currencyCode)} is being sent to $workerName.',
      );
    case GigStep.completed:
      return GigStepCopy(
        'Gig complete!',
        'Rate $workerName to help other hosts.',
      );
  }
}

// Display-only address cleanup — collapses immediate consecutive duplicate
// comma-separated parts (e.g. "Foo St, Foo St, City" -> "Foo St, City").
// Never writes back to Firestore; the stored value is untouched.
String dedupedAddress(String address) {
  final parts = address
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  final deduped = <String>[];
  for (final p in parts) {
    if (deduped.isEmpty || deduped.last.toLowerCase() != p.toLowerCase()) {
      deduped.add(p);
    }
  }
  return deduped.join(', ');
}

String fmtDist(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}
