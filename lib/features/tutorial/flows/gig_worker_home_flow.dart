import '../models/tutorial_flow.dart';
import '../models/tutorial_step.dart';

// All steps live on the worker dashboard (GigWorkerScreen); step 4's anchor
// is the dashboard avatar.
const gigWorkerHomeFlow = TutorialFlow(
  id: 'gigWorkerHome',
  steps: [
    TutorialStep(
      id: 'gigWorkerHome.activeMode',
      anchorId: 'workerHome.activeMode',
      title: 'Turn on Active Mode',
      body: 'This lets Gig Hosts know you’re online and available for '
          'work right now.',
    ),
    TutorialStep(
      id: 'gigWorkerHome.quickGigs',
      anchorId: 'workerHome.quickGigsToggle',
      title: 'Quick Gigs',
      body: 'Turn this on if you’re available for instant gig offers — '
          'tasks that don’t need specific skills, like errands, moving '
          'items, or general help. You can accept or decline each one, but '
          'your acceptance rate, performance, and distance from the host '
          'all affect how often you’re offered a Quick Gig. See Decline '
          'Information in Settings for details.',
    ),
    TutorialStep(
      id: 'gigWorkerHome.findOpenGigs',
      anchorId: 'workerHome.gigViewToggle',
      title: 'Find Open Gigs',
      body: 'Switch between Map and List to browse Open Gigs nearby. You '
          'can only apply to ones matching the skills a host requires.',
    ),
    TutorialStep(
      id: 'gigWorkerHome.avatar',
      anchorId: 'workerHome.avatar',
      title: 'Manage your skills',
      body: 'Tap your avatar to open your Profile, then choose My '
          'Toolchest to add or manage the skills you’re qualified in.',
    ),
    TutorialStep(
      id: 'gigWorkerHome.notifications',
      anchorId: 'workerHome.notificationsBell',
      title: 'Don’t miss a direct offer',
      body: 'Hosts can offer a gig directly to you, especially if '
          'they’ve worked with you before. Make sure Giggre notifications '
          'are enabled in your device settings so you never miss one.',
    ),
  ],
);
