import '../models/tutorial_flow.dart';
import '../models/tutorial_step.dart';

// Anchors live on the three speed-dial bubbles in host_speed_dial.dart —
// only mounted while the dial is open, so this flow is started once that
// open animation finishes (see HostShell._toggleDial).
const gigTypesFlow = TutorialFlow(
  id: 'gigTypes',
  steps: [
    TutorialStep(
      id: 'gigTypes.quickGig',
      anchorId: 'gigHost.quickGigBubble',
      title: 'Quick Gig',
      body: 'Use this when you need an instant worker for a task that '
          'doesn’t require specific skills or qualifications. For example: '
          'personal errands, moving items, simple household tasks, or '
          'other general assistance.',
    ),
    TutorialStep(
      id: 'gigTypes.openGig',
      anchorId: 'gigHost.openGigBubble',
      title: 'Open Gig',
      body: 'Use this when the gig requires specific skills or '
          'qualifications. For example: hiring an electrician, plumber, '
          'graphic designer, or other skilled worker.',
    ),
    TutorialStep(
      id: 'gigTypes.offeredGig',
      anchorId: 'gigHost.offeredGigBubble',
      title: 'Offered Gig',
      body: 'Use this when you already have a favorite or previously '
          'hired worker and want to offer them a gig directly again.',
    ),
  ],
);
