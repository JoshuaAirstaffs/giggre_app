import 'package:flutter/material.dart';
import '../../core/services/rating_service.dart';
import '../../core/widgets/rating_dialog.dart';
import 'models/dev_action.dart';

// Registry of every action row shown in the Developer Options modal, in
// display order. See `dev_toggles.dart` for the flag equivalent.

Future<void> _previewRating(BuildContext context, RateeRole role) async {
  final result = await RatingDialog.show(
    context: context,
    rateeId: 'preview-ratee',
    rateeName: role == RateeRole.worker ? 'Sample Worker' : 'Sample Host',
    rateeRole: role,
    // Ignored — preview mode never reaches RatingService.submit, so no gig
    // has to exist and nothing is written.
    gigId: 'preview-gig',
    gigCollection: 'quick_gigs',
    gigTitle: 'Sample Gig',
    preview: true,
  );
  if (!context.mounted) return;

  final summary = result == null
      ? 'Skipped — no rating submitted.'
      : 'Would submit ${result.stars}★'
            '${result.tags.isEmpty ? '' : ' · ${result.tags.join(', ')}'}'
            '${result.comment == null ? '' : ' · “${result.comment}”'}';
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(summary)));
}

final List<DevActionDescriptor> devActions = [
  DevActionDescriptor(
    id: 'ratings.previewWorkerDialog',
    label: 'Preview: rate a worker',
    description:
        'Opens the post-gig rating dialog a host sees, with the worker tag '
        'set. Nothing is written to Firestore.',
    icon: Icons.star_rounded,
    run: (context) => _previewRating(context, RateeRole.worker),
  ),
  DevActionDescriptor(
    id: 'ratings.previewHostDialog',
    label: 'Preview: rate a host',
    description:
        'Same dialog in the other direction — what a worker sees after '
        'payment is confirmed, with the host tag set.',
    icon: Icons.star_half_rounded,
    run: (context) => _previewRating(context, RateeRole.host),
  ),
];
