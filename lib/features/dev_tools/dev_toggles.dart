import 'models/dev_toggle.dart';

// Registry of every toggle shown in the Developer Options modal, in display
// order. To add one: write its getValue/setValue and append it here —
// nothing in the hidden entry point or the modal needs to change.
//
// (The Quick Gig tutorial used to have a gate here, but it's now shown to
// all users by default — see TutorialController.startIfNeeded — and users
// replay it themselves via the "Tutorial" button on Post Quick Gig, so
// there's nothing left for a dev toggle to control.)
final List<DevToggleDescriptor> devToggles = [];
