import '../tutorial/flows/offered_gig_flow.dart';
import '../tutorial/flows/open_gig_flow.dart';
import '../tutorial/services/tutorial_service.dart';
import 'models/dev_toggle.dart';

// Registry of every toggle shown in the Developer Options modal, in display
// order. To add one: write its getValue/setValue and append it here —
// nothing in the hidden entry point or the modal needs to change.
//
// The Quick Gig tutorial has no entry here — it's shown to all users by
// default (see TutorialController.startIfNeeded) and replayed via its own
// "Tutorial" button, so there's nothing for a dev toggle to control. Open
// Gig and Offered Gig are still internal-only (TutorialFlow.devOnly),
// so each gets a toggle that both flips it on and force-replays it —
// otherwise a tester who already ran through it once would just have the
// toggle silently no-op.
DevToggleDescriptor _devOnlyFlowToggle({
  required String label,
  required String description,
  required String flowId,
}) {
  final service = TutorialService();
  return DevToggleDescriptor(
    id: flowId,
    label: label,
    description: description,
    getValue: () => service.isDevEnabled(flowId),
    setValue: (enabled) async {
      await service.setDevEnabled(flowId, enabled);
      if (enabled) await service.reset(flowId);
    },
  );
}

final List<DevToggleDescriptor> devToggles = [
  _devOnlyFlowToggle(
    label: 'Open Gig Tutorial',
    description: 'Show the Open Gig tutorial for testing. Hidden from '
        'regular users.',
    flowId: openGigFlow.id,
  ),
  _devOnlyFlowToggle(
    label: 'Offered Gig Tutorial',
    description: 'Show the Offered Gig tutorial for testing. Hidden from '
        'regular users.',
    flowId: offeredGigFlow.id,
  ),
];
