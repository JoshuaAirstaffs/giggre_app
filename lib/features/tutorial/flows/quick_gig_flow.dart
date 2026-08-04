import '../models/tutorial_flow.dart';
import '../models/tutorial_step.dart';

// Anchor ids are namespaced 'postGig.*' where the step targets a field the
// Open Gig / Offered Gig forms share (post_open_gig_screen.dart and
// post_offered_gig_screen.dart use the same _buildTextField / _buildScheduleRow
// / _buildLocationSection helpers), so a future flow can reuse the same
// TutorialAnchor wrappers instead of inventing new ids for identical fields.
const quickGigFlow = TutorialFlow(
  id: 'quickGig',
  steps: [
    TutorialStep(
      id: 'quickGig.title',
      anchorId: 'postGig.title',
      title: 'Give it a title',
      body: "A short, specific title — like \"Wash dishes after event\" — "
          'helps workers know what they’re signing up for at a glance.',
    ),
    TutorialStep(
      id: 'quickGig.description',
      anchorId: 'postGig.description',
      title: 'Add the details',
      body: 'Anything a worker should know before accepting — tools needed, '
          'access instructions, expected duration.',
    ),
    TutorialStep(
      id: 'quickGig.amount',
      anchorId: 'postGig.amount',
      title: 'Set the pay',
      body: 'This is what each worker earns for the gig. Fair, competitive '
          'pay gets matched faster.',
    ),
    TutorialStep(
      id: 'quickGig.workerSlots',
      anchorId: 'postGig.workerSlots',
      title: 'Need more than one worker?',
      body: 'Bump this up if the job needs multiple people — each one is '
          'paid the amount above independently.',
    ),
    TutorialStep(
      id: 'quickGig.schedule',
      anchorId: 'postGig.schedule',
      title: 'Pick a date and time',
      body: 'Set when the work should happen. Leave it as-is for as-soon-as-'
          'possible gigs.',
    ),
    TutorialStep(
      id: 'quickGig.location',
      anchorId: 'postGig.location',
      title: 'Confirm the location',
      body: 'We use your GPS by default — switch to the map if the job is '
          'somewhere else.',
    ),
    TutorialStep(
      id: 'quickGig.submit',
      anchorId: 'postGig.submit',
      title: 'Post it',
      body: 'Once you post, we start matching nearby workers right away.',
    ),
    TutorialStep(
      id: 'quickGig.hostCard',
      anchorId: 'quickGig.hostCard',
      title: 'Your gig is live',
      body: 'This card tracks it. Tap it any time to check on the search.',
      advance: TutorialAdvance.autoOnAnchor,
    ),
    TutorialStep(
      id: 'quickGig.searching',
      anchorId: 'quickGig.searching',
      title: 'Searching for a worker',
      body: 'We’re checking nearby workers’ availability. This can take a '
          'few minutes — feel free to close this and keep using the app.',
      advance: TutorialAdvance.autoOnAnchor,
    ),
    TutorialStep(
      id: 'quickGig.detailProgress',
      anchorId: 'quickGig.detail.progress',
      title: 'Track the gig',
      body: 'Once a worker accepts, follow their progress here — and mark '
          'the gig complete once the work is done.',
      advance: TutorialAdvance.autoOnAnchor,
    ),
  ],
);
