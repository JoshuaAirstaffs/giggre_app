import '../models/tutorial_flow.dart';
import '../models/tutorial_step.dart';

// Reuses the shared 'postGig.*' anchors from quick_gig_flow.dart wherever
// Open Gig's form uses the same _buildTextField / _buildScheduleRow /
// _buildLocationSection / _buildWorkerSlotsStepper / _buildSkillDropdown /
// _buildExperienceDropdown helpers as the other post-gig screens.
const openGigFlow = TutorialFlow(
  id: 'openGig',
  steps: [
    TutorialStep(
      id: 'openGig.title',
      anchorId: 'postGig.title',
      title: 'Give it a title',
      body: 'A short, specific title helps workers know what they’re '
          'taking on at a glance.',
    ),
    TutorialStep(
      id: 'openGig.description',
      anchorId: 'postGig.description',
      title: 'Describe the gig',
      body: 'Deliverables, expectations, anything a worker should know '
          'before they take the gig.',
    ),
    TutorialStep(
      id: 'openGig.requiredSkills',
      anchorId: 'postGig.skillRequired',
      title: 'Pick the skill needed',
      body: 'Only workers with this skill will be able to take it.',
    ),
    TutorialStep(
      id: 'openGig.experienceLevel',
      anchorId: 'postGig.experienceLevel',
      title: 'Set the experience level',
      body: 'Helps filter out workers who aren’t a fit for this gig.',
    ),
    TutorialStep(
      id: 'openGig.amount',
      anchorId: 'postGig.amount',
      title: 'Set the pay',
      body: 'What each worker earns for taking the gig.',
    ),
    TutorialStep(
      id: 'openGig.workerSlots',
      anchorId: 'postGig.workerSlots',
      title: 'Need more than one worker?',
      body: 'Bump this up if the gig needs multiple people — each one is '
          'paid the amount above independently.',
    ),
    TutorialStep(
      id: 'openGig.schedule',
      anchorId: 'postGig.schedule',
      title: 'Pick a date and time',
      body: 'Set when the gig should happen.',
    ),
    TutorialStep(
      id: 'openGig.location',
      anchorId: 'postGig.location',
      title: 'Confirm the location',
      body: 'We use your GPS by default — switch to the map if the gig is '
          'somewhere else.',
    ),
    TutorialStep(
      id: 'openGig.submit',
      anchorId: 'postGig.submit',
      title: 'Post it',
      body: 'Once posted, nearby workers with the right skill can take it.',
    ),
    TutorialStep(
      id: 'openGig.hostCard',
      anchorId: 'openGig.hostCard',
      title: 'Your gig is live',
      body: 'This card tracks it. Tap it any time to review interested workers.',
      advance: TutorialAdvance.autoOnAnchor,
    ),
    TutorialStep(
      id: 'openGig.applicants',
      anchorId: 'openGig.applicants',
      title: 'Review interested workers',
      body: 'Interested workers show up here. Tap "Select" on the one you '
          'want to select.',
      advance: TutorialAdvance.autoOnAnchor,
    ),
    TutorialStep(
      id: 'openGig.detailProgress',
      anchorId: 'openGig.detail.progress',
      title: 'Track the gig',
      body: 'Once you select a worker, follow their progress here — and mark '
          'the gig complete once it\'s done.',
      advance: TutorialAdvance.autoOnAnchor,
    ),
  ],
);
