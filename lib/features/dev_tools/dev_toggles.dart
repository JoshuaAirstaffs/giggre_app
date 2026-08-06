import 'models/dev_toggle.dart';

// Registry of every toggle shown in the Developer Options modal, in display
// order. To add one: write its getValue/setValue and append it here —
// nothing in the hidden entry point or the modal needs to change.
//
// Quick Gig, Open Gig, and Offered Gig tutorials have no entries here — all
// three are shown to every user by default (see
// TutorialController.startIfNeeded) and replayed via their own "Tutorial"
// button, so there's nothing left for a dev toggle to control.
final List<DevToggleDescriptor> devToggles = [];
