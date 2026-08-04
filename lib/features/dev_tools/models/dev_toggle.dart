/// One row in the Developer Options modal. New dev-only feature flags are
/// added by appending a descriptor to the registry in `dev_toggles.dart` —
/// the modal itself never needs to change.
class DevToggleDescriptor {
  final String id;
  final String label;
  final String description;
  final Future<bool> Function() getValue;
  final Future<void> Function(bool enabled) setValue;

  const DevToggleDescriptor({
    required this.id,
    required this.label,
    required this.description,
    required this.getValue,
    required this.setValue,
  });
}
