// Host-side counterpart to kWorkerActiveGigStatuses (worker_active_gig.dart)
// — statuses that mean "this gig is actively underway" from the host's
// perspective, spanning single- and multi-worker gigs. Do not invent new
// status values here; keep in sync with GigStep (gig_shared/active_gig_step.dart).
const List<String> kHostActiveGigStatuses = [
  'in_progress',
  'partially_filled',
  'filled',
  'navigating',
  'arrived',
  'working',
  'task_complete',
  'payment',
  'cancellation_requested',
];
