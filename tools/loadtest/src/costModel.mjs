// Analytical estimate of the Firestore reads/writes and Cloud Functions work a
// stage will cause, derived from the code audit (docs/architecture-audit.md).
// Used for the plan, the approval ceiling and the live budget guard. The run
// itself COUNTS real reads/writes; reports always prefer measured numbers and
// label these as estimates.
//
// Billing facts used: a query/listen that returns 0 docs bills 1 read; a
// listener bills 1 read per added/modified/removed doc it receives.

// Per-session baseline: everything HomeScreen + ModeShell open regardless of
// intent (both Worker and Host shells stay mounted — audit §Session baseline).
const BASELINE_MIN1_QUERIES = 31; // config docs, user doc, 8 active/pending-cancel, 6 assignment, support, groups, gig_points, unverified, hostId x6 ...
const BASELINE_WRITES_WORKER = 4; // fcmTokens arrayUnion x2, isOnline true/false
const BASELINE_WRITES_HOST = 2;   // fcmTokens x2 (isOnline only toggles in worker mode)
const LOCATION_WRITE_WORKER = 1;  // users.location on worker dashboard load

const INTENT = {
  // reads/writes on top of the baseline; "gigUpdates" = writes that change an
  // open gig (seen by every open_gigs listener); "msgs" = chat messages sent.
  browse:   { reads: 3 + 8 + 1, writes: 0 },               // detail host gets, skills, filters
  explore:  { reads: 20 + 2, writes: 0 },                  // notifications sheet, profile
  apply:    { reads: 12 + 3, writes: 2, gigUpdates: 1 },   // guard+checks+gig get; update+notification
  chat:     { reads: 27 + 4, writes: 0, msgsPerSession: 5 },
  post:     { reads: 4, writes: 1.25, gigCreates: 1 },     // guard reads; gig (+ offered slot batch)
  manage:   { reads: 6, writes: 1.2, gigUpdates: 1 },      // detail sheet listeners; select
  register: { reads: 3, writes: 1.1 },                     // userId + referral-code checks; batch
};

export function estimateUsage({ spec, cfg, schedule, conc, intents, roleCount }) {
  const { workload, pricing } = cfg;
  const S = schedule.sessions.length;
  const T = schedule.realDurationSec;
  const totalSessionSec = schedule.sessions.reduce((s, x) => s + x.realDurationSec, 0);
  const avgConc = Math.min(totalSessionSec / T, spec.maxConcurrency);
  const avgDur = totalSessionSec / S;
  const workerSessions = schedule.sessions.filter((s) => s.role === 'worker').length;
  const avgOnlineWorkers = avgConc * (workerSessions / S);

  const count = (intent) => Object.entries(intents).filter(([k]) => k.endsWith(`:${intent}`)).reduce((s, [, v]) => s + v, 0);
  const posts = count('post') * INTENT.post.gigCreates;
  const seedOpen = Math.round((workload.seedData.existingOpenGigsPerThousandUsers * spec.users) / 1000);
  const avgOpenGigs = seedOpen + posts * 0.5; // half the day's posts still open on average
  const seedRooms = Math.round((workload.seedData.existingChatRoomsPerThousandUsers * spec.users) / 1000);
  const roomsPerUser = (2 * seedRooms) / spec.users + 0.3;

  const gigUpdateEvents = count('apply') + count('manage') + posts * 2; // + gsku write per post
  const onlineUserDocWrites = workerSessions * (BASELINE_WRITES_WORKER + LOCATION_WRITE_WORKER);
  // Every open-gig change reaches every session listening at that moment.
  const gigFanoutReads = gigUpdateEvents * avgConc;
  const onlineFanoutReads = onlineUserDocWrites * avgConc;

  const breakdown = {
    baseline: S * (BASELINE_MIN1_QUERIES + 2 * roomsPerUser),
    browse: S * avgOpenGigs + gigFanoutReads, // the global open_gigs listener
    onlineUsers: S * avgOnlineWorkers + onlineFanoutReads, // global users isOnline==true listener
    intents: 0,
  };
  let writes = workerSessions * (BASELINE_WRITES_WORKER + LOCATION_WRITE_WORKER) + (S - workerSessions) * BASELINE_WRITES_HOST;
  let msgs = 0;
  for (const [k, n] of Object.entries(intents)) {
    const m = INTENT[k.split(':')[1]];
    if (!m) continue;
    breakdown.intents += n * m.reads;
    writes += n * m.writes;
    if (m.msgsPerSession) { msgs += n * m.msgsPerSession; }
  }
  writes += msgs * 2; // message add + room lastMessage update
  // Setup (seeding) before the day starts: returning users' docs, open gigs,
  // chat rooms with history. Billed too on a real project.
  const returningUsers = schedule.users.filter((u) => !u.isNew).length;
  const [hLo, hHi] = workload.seedData.historyMessagesPerRoom;
  const setupWrites = returningUsers + seedOpen + seedRooms * (1 + (hLo + hHi) / 2);
  writes += setupWrites;
  breakdown.chatDelivery = msgs * 3; // peer listener + unread listeners
  const reads = Object.values(breakdown).reduce((a, b) => a + b, 0);

  // Cloud Functions (deployed triggers; only executed in the emulator when
  // --with-functions is used, otherwise estimate only).
  const availableWorkers = roleCount.worker; // availableForGigs defaults to true at signup
  const openPosts = posts * workload.gigMix.open;
  const userDocWrites = writes * 0.35; // share of writes that hit users/{uid}
  const fnBreakdown = {
    onOpenGigPosted: openPosts * availableWorkers, // reads every availableForGigs user per open gig
    userDocTriggers: userDocWrites * 1.2,          // syncPublicProfile etc. reading/writing
    gigTriggers: gigUpdateEvents * 2,
    chatTriggers: msgs * 2,
  };
  const fnInvocations = userDocWrites * 5 + gigUpdateEvents * 7 + posts * 5 + msgs * 2;
  const fnReads = Object.values(fnBreakdown).reduce((a, b) => a + b, 0);

  const p = pricing.firestore;
  const fsCost = (r, w) => (r / 1e5) * p.readsPer100k + (w / 1e5) * p.writesPer100k;
  const fnCost = (fnInvocations / 1e6) * pricing.functions.invocationsPerMillion +
    fnInvocations * pricing.functions.avgGbSecondsPerInvocation * pricing.functions.gbSecondPrice;
  const equivalentUsd = fsCost(reads + fnReads, writes) + fnCost;
  const billable = Boolean(spec.env.billable);
  return {
    assumptions: {
      avgConcurrentSessions: round(avgConc),
      avgSessionSec: round(avgDur),
      avgOpenGigs: round(avgOpenGigs),
      avgOnlineWorkers: round(avgOnlineWorkers),
      roomsPerUser: round(roomsPerUser, 2),
      availableForGigsWorkers: availableWorkers,
      note: 'Listener fan-out assumes every session keeps the global open_gigs and users(isOnline) listeners open, as the app does with both shells mounted.',
    },
    client: { reads: Math.round(reads), writes: Math.round(writes), setupWrites: Math.round(setupWrites), messages: Math.round(msgs), breakdown: roundAll(breakdown) },
    functions: { invocations: Math.round(fnInvocations), reads: Math.round(fnReads), breakdown: roundAll(fnBreakdown) },
    maps: { requests: 0 },
    cost: {
      pricingVerifiedOn: pricing.verifiedOn,
      equivalentUsd,
      estimateUsd: billable ? equivalentUsd : 0,
      // Ceiling = 2x the estimate (minimum $1) for billable envs. The live
      // guard aborts when measured usage priced at list rates passes it.
      maxUsd: billable ? Math.max(1, Math.ceil(equivalentUsd * 2)) : 0,
    },
  };
}

const round = (x, d = 0) => Math.round(x * 10 ** d) / 10 ** d;
const roundAll = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, Math.round(v)]));

/** Price measured counters at list rates (for reports and the live guard). */
export function priceMeasured(pricing, { reads, writes, deletes = 0, fnInvocations = 0 }) {
  const p = pricing.firestore;
  return (reads / 1e5) * p.readsPer100k + (writes / 1e5) * p.writesPer100k + (deletes / 1e5) * p.deletesPer100k +
    (fnInvocations / 1e6) * pricing.functions.invocationsPerMillion;
}
