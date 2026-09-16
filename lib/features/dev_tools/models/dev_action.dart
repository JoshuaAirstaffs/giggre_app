import 'package:flutter/material.dart';

/// One tappable row in the Developer Options modal, for things that *do*
/// something rather than flip a flag — previewing a dialog, replaying a
/// flow, dumping state. Added the same way as a toggle: write the descriptor
/// and append it to the registry in `dev_actions.dart`.
class DevActionDescriptor {
  final String id;
  final String label;
  final String description;
  final IconData icon;

  /// Runs when the row is tapped. The modal closes first, so this gets the
  /// screen's context rather than the sheet's — a dialog opened here is not
  /// torn down along with the sheet.
  final Future<void> Function(BuildContext context) run;

  const DevActionDescriptor({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.run,
  });
}
