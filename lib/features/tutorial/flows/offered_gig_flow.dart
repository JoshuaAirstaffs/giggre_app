import '../models/tutorial_flow.dart';
import '../models/tutorial_step.dart';

// devOnly: true — only shown when the "Offered Gig Tutorial" toggle in
// Developer Options is on (see dev_toggles.dart). Reuses the shared
// 'postGig.*' anchors from quick_gig_flow.dart wherever Offered Gig's form
// uses the same shared field helpers as the other post-gig screens.
const offeredGigFlow = TutorialFlow(
  id: 'offeredGig',
  devOnly: true,
  steps: [
    TutorialStep(
      id: 'offeredGig.worker',
      anchorId: 'offeredGig.worker',
      title: 'Choose a worker',
      body: 'Pick the worker you want to offer this gig to directly — no '
          'search or applicants needed.',
    ),
    TutorialStep(
      id: 'offeredGig.title',
      anchorId: 'postGig.title',
      title: 'Give it a title',
      body: 'A short, specific title helps the worker know what they’re '
          'being offered.',
    ),
    TutorialStep(
      id: 'offeredGig.description',
      anchorId: 'postGig.description',
      title: 'Describe the work',
      body: 'Anything the worker should know before accepting.',
    ),
    TutorialStep(
      id: 'offeredGig.skillRequired',
      anchorId: 'postGig.skillRequired',
      title: 'Confirm the skill',
      body: 'Should match what this worker is being offered the job for.',
    ),
    TutorialStep(
      id: 'offeredGig.experienceLevel',
      anchorId: 'postGig.experienceLevel',
      title: 'Set the experience level',
      body: 'Just a record of the expected level for this job.',
    ),
    TutorialStep(
      id: 'offeredGig.amount',
      anchorId: 'postGig.amount',
      title: 'Set the pay',
      body: 'What the worker earns if they accept the offer.',
    ),
    TutorialStep(
      id: 'offeredGig.schedule',
      anchorId: 'postGig.schedule',
      title: 'Pick a date and time',
      body: 'Set when the work should happen.',
    ),
    TutorialStep(
      id: 'offeredGig.location',
      anchorId: 'postGig.location',
      title: 'Confirm the location',
      body: 'We use your GPS by default — switch to the map if the job is '
          'somewhere else.',
    ),
    TutorialStep(
      id: 'offeredGig.submit',
      anchorId: 'postGig.submit',
      title: 'Send the offer',
      body: 'The worker gets notified and can accept or decline.',
    ),
    TutorialStep(
      id: 'offeredGig.hostCard',
      anchorId: 'offeredGig.hostCard',
      title: 'Offer sent',
      body: 'This card tracks it. Tap it any time to check the status.',
      advance: TutorialAdvance.autoOnAnchor,
    ),
    TutorialStep(
      id: 'offeredGig.status',
      anchorId: 'offeredGig.status',
      title: 'Waiting for a response',
      body: 'We’ll update this as soon as the worker accepts or declines.',
      advance: TutorialAdvance.autoOnAnchor,
    ),
    TutorialStep(
      id: 'offeredGig.detailProgress',
      anchorId: 'offeredGig.detail.progress',
      title: 'Track the gig',
      body: 'Once they accept, follow their progress here — and mark the '
          'gig complete once the work is done.',
      advance: TutorialAdvance.autoOnAnchor,
    ),
  ],
);
