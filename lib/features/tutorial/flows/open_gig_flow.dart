import '../models/tutorial_flow.dart';
import '../models/tutorial_step.dart';

// devOnly: true — only shown when the "Open Gig Tutorial" toggle in
// Developer Options is on (see dev_toggles.dart). Reuses the shared
// 'postGig.*' anchors from quick_gig_flow.dart wherever Open Gig's form uses
// the same _buildTextField / _buildScheduleRow / _buildLocationSection /
// _buildWorkerSlotsStepper / _buildSkillDropdown / _buildExperienceDropdown
// helpers as the other post-gig screens.
const openGigFlow = TutorialFlow(
  id: 'openGig',
  devOnly: true,
  steps: [
    TutorialStep(
      id: 'openGig.title',
      anchorId: 'postGig.title',
      title: 'Give it a title',
      body: 'A short, specific title helps workers know what they’re '
          'applying for at a glance.',
    ),
    TutorialStep(
      id: 'openGig.description',
      anchorId: 'postGig.description',
      title: 'Describe the work',
      body: 'Deliverables, expectations, anything an applicant should know '
          'before they apply.',
    ),
    TutorialStep(
      id: 'openGig.requiredSkills',
      anchorId: 'postGig.skillRequired',
      title: 'Pick the skill needed',
      body: 'Only workers with this skill will be able to apply.',
    ),
    TutorialStep(
      id: 'openGig.experienceLevel',
      anchorId: 'postGig.experienceLevel',
      title: 'Set the experience level',
      body: 'Helps filter out applicants who aren’t a fit for this job.',
    ),
    TutorialStep(
      id: 'openGig.amount',
      anchorId: 'postGig.amount',
      title: 'Set the pay',
      body: 'What each hired worker earns for the gig.',
    ),
    TutorialStep(
      id: 'openGig.workerSlots',
      anchorId: 'postGig.workerSlots',
      title: 'Need more than one worker?',
      body: 'Bump this up if the job needs multiple people — each one is '
          'paid the amount above independently.',
    ),
    TutorialStep(
      id: 'openGig.schedule',
      anchorId: 'postGig.schedule',
      title: 'Pick a date and time',
      body: 'Set when the work should happen.',
    ),
    TutorialStep(
      id: 'openGig.location',
      anchorId: 'postGig.location',
      title: 'Confirm the location',
      body: 'We use your GPS by default — switch to the map if the job is '
          'somewhere else.',
    ),
    TutorialStep(
      id: 'openGig.submit',
      anchorId: 'postGig.submit',
      title: 'Post it',
      body: 'Once posted, nearby workers with the right skill can apply.',
    ),
    TutorialStep(
      id: 'openGig.hostCard',
      anchorId: 'openGig.hostCard',
      title: 'Your gig is live',
      body: 'This card tracks it. Tap it any time to review applicants.',
      advance: TutorialAdvance.autoOnAnchor,
    ),
    TutorialStep(
      id: 'openGig.applicants',
      anchorId: 'openGig.applicants',
      title: 'Review applicants',
      body: 'Interested workers show up here. Tap "Select" on the one you '
          'want to hire.',
      advance: TutorialAdvance.autoOnAnchor,
    ),
    TutorialStep(
      id: 'openGig.detailProgress',
      anchorId: 'openGig.detail.progress',
      title: 'Track the gig',
      body: 'Once you hire a worker, follow their progress here — and mark '
          'the gig complete once the work is done.',
      advance: TutorialAdvance.autoOnAnchor,
    ),
  ],
);
