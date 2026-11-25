// Quick-gig smart dispatch — mirrors quick_gig_matching_service.dart. In the
// real app this runs entirely on the HOST'S device (no Cloud Function), so
// here the host's own VU performs every dispatch write, and a short-lived
// client stands in for whichever candidate worker is being offered the gig
// (the accept/decline write must come from that worker's own auth — see
// firestore.rules match /quick_gigs, which keys off `assignedWorkerId ==
// request.auth.uid` / the candidate's own `workers/{uid}` slot doc).
//
// This is docs/architecture-audit.md §8 risk 8 ("Quick-gig matching on the
// host phone"), previously marked "not simulated (documented)". The critical
// cost driver is `findBestWorker`'s unbounded `users` scan, run once per
// dispatch attempt — that scan is reproduced exactly (same four `where`
// clauses). What is deliberately simplified, and why it's still a fair
// substitute for load-testing purposes:
//  - No resume-after-app-restart handling — not meaningful within one
//    session.
//  - No backfill search for a worker cancelling mid-gig (a second-order
//    flow; the primary dispatch loop is what drives the read volume).
//  - Worker selection is nearest-eligible rather than the real composite
//    proximity/acceptance/rating score — same scan, same candidate pool,
//    different tie-break; doesn't change read volume or race exposure.
//  - The candidate's response is decided immediately (after a short
//    representative delay) instead of literally polling every 3s for up to
//    a 30s review window — this keeps the *operations* (same documents,
//    same fields, same rules path, same opportunity for two concurrent
//    dispatches to pick the same worker) identical while avoiding minutes of
//    real wall-clock spent waiting on a result the test already knows, the
//    same tradeoff already made for chat/think-time delays elsewhere here.
//  - Every dispatch therefore resolves to accept-or-decline; the real app's
//    separate "nobody responded within the review window" timeout-cleanup
//    path (host-side exclusion + penalty with no counterpart write from the
//    worker) is folded into the decline case above rather than exercised as
//    its own branch.
import {
  doc, collection, query, where, GeoPoint, Timestamp, serverTimestamp, deleteField, arrayUnion, increment,
} from 'firebase/firestore';
import { cQuery, cUpdate, cAdd, cTxn, createClient, destroyClient, Rejection } from '../firebase.mjs';
import { signInWithEmailAndPassword } from 'firebase/auth';
import { gigContent, distanceKm } from '../synthetic.mjs';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const marker = (vu) => ({ [vu.world.cfg.safety.syntheticMarkerField]: vu.world.runId });

// ── Post (post_quick_gig_screen.dart) ───────────────────────────────────────
export async function postQuickGig(vu) {
  if (vu.person.role !== 'host') return;
  const { db } = vu.client;
  const w = vu.world;
  const cfg = w.cfg.workload.quickGigs;
  const c = gigContent(vu.r, { gigMix: w.cfg.workload.gigMix, flexible: true });
  const loc = { lat: vu.person.lat + vu.r.float(-0.02, 0.02), lng: vu.person.lng + vu.r.float(-0.02, 0.02) };
  const data = {
    hostId: vu.uid, hostName: vu.person.name, title: c.title, description: c.description,
    category: c.skill, budget: c.budget, currencyCode: 'PHP', payType: c.payType,
    ...(c.hourlyRate ? { hourlyRate: c.hourlyRate } : {}),
    ...(c.workDurationHours ? { workDurationHours: c.workDurationHours } : {}),
    duration: c.workDurationHours ? `${c.workDurationHours}h` : 'Flexible',
    location: new GeoPoint(loc.lat, loc.lng), address: c.address, status: 'scanning', gigType: 'quick',
    createdAt: Timestamp.now(), workerSlots: c.workerSlots, ratePerSlot: c.budget,
    filledSlotCount: 0, slotsCompleted: 0, exclusionList: [],
    ...marker(vu),
  };
  const ref = await vu.m.time('quickgig.post', () => cAdd(vu, collection(db, 'quick_gigs'), data, 'quickgig.post.write'));
  w.createdGigs.push({ col: 'quick_gigs', id: ref.id, hostId: vu.uid, workerSlots: c.workerSlots });
  // Fire-and-forget in the real app; here we await it (bounded to a handful
  // of fast attempts — see file header) so the session accounts for its cost
  // before moving on to its next scripted step.
  const gigMeta = { ratePerSlot: c.budget, currencyCode: 'PHP' };
  await runQuickGigSearch(vu, ref.id, loc, c.workerSlots, gigMeta, cfg).catch((e) => vu.m.record('quickgig.search', 0, e));
}

// ── The dispatch loop (startAutoSearch) ─────────────────────────────────────
export async function runQuickGigSearch(vu, gigId, gigLocation, workerSlots, gigMeta, cfg) {
  const { db } = vu.client;
  const w = vu.world;
  const gigRef = doc(db, 'quick_gigs', gigId);
  const hostId = vu.uid, hostName = vu.person.name;
  const excluded = [hostId];
  let filled = 0;
  let attempts = 0;

  while (attempts < cfg.maxDispatchAttempts && filled < workerSlots && !w.stopping) {
    attempts++;
    const candidate = await findBestWorker(vu, { gigLocation, excluded, hostId });
    if (!candidate) {
      await sleep(cfg.retryIntervalMs);
      continue;
    }
    excluded.push(candidate.uid);
    const workerRef = doc(db, 'users', candidate.uid);

    if (workerSlots <= 1) {
      // Transactional (mirrors quick_gig_matching_service.dart's fixed
      // _dispatchToWorker): re-checks the worker is still AVAILABLE right
      // before locking them, so a concurrent host's search racing for the
      // same candidate loses cleanly instead of both locking them at once.
      const dispatched = await cTxn(vu, db, async (tx, count) => {
        const wsnap = await tx.get(workerRef); count.read();
        if (wsnap.data()?.slot !== 'AVAILABLE') throw new Rejection('already-assigned');
        tx.update(workerRef, { slot: 'LOCKED' });
        tx.update(gigRef, { status: 'in_progress', assignedWorkerId: candidate.uid, assignedWorkerName: candidate.name, dispatchedAt: serverTimestamp() });
        count.write(); count.write();
      }, 'quickgig.dispatch').then(() => true).catch((e) => { if (e.expectedCode) return false; throw e; });
      if (!dispatched) {
        await cUpdate(vu, gigRef, { exclusionList: arrayUnion(candidate.uid) }, 'quickgig.dispatch').catch(() => {});
        continue;
      }
      const accepted = vu.r.chance(cfg.acceptShare);
      await sleep(cfg.responseDelayMs);
      await respondToDispatch(w, { candidate, gigId, isMulti: false, accept: accepted });
      if (accepted) { filled = 1; vu.world.assignments.push({ gigId, workerId: candidate.uid, single: true, quick: true }); break; }
      // Declined: candidate's own write already reset status/cleared
      // assignedWorkerId/added itself to exclusionList (mirrors
      // _declineDispatch) — loop again for the next candidate.
      continue;
    }

    // Multi-slot: same transactional guard, dispatching to this candidate's
    // own slot doc instead of singular fields on the gig doc.
    const slotRef = doc(db, 'quick_gigs', gigId, 'workers', candidate.uid);
    const dispatched = await cTxn(vu, db, async (tx, count) => {
      const wsnap = await tx.get(workerRef); count.read();
      if (wsnap.data()?.slot !== 'AVAILABLE') throw new Rejection('already-assigned');
      tx.update(workerRef, { slot: 'LOCKED' });
      tx.set(slotRef, {
        workerId: candidate.uid, workerName: candidate.name, gigId, gigCollection: 'quick_gigs', hostId, hostName,
        rate: gigMeta.ratePerSlot, currencyCode: gigMeta.currencyCode, status: 'in_progress', dispatchedAt: serverTimestamp(),
      });
      count.write(); count.write();
    }, 'quickgig.dispatch').then(() => true).catch((e) => { if (e.expectedCode) return false; throw e; });
    if (!dispatched) {
      await cUpdate(vu, gigRef, { exclusionList: arrayUnion(candidate.uid) }, 'quickgig.dispatch').catch(() => {});
      continue;
    }
    if (filled === 0) await cUpdate(vu, gigRef, { status: 'scanning' }, 'quickgig.dispatch').catch(() => {});
    const accepted = vu.r.chance(cfg.acceptShare);
    await sleep(cfg.responseDelayMs);
    await respondToDispatch(w, { candidate, gigId, isMulti: true, accept: accepted });
    if (accepted) {
      await cTxn(vu, db, async (tx, count) => {
        const snap = await tx.get(gigRef); count.read();
        const f = (snap.data()?.filledSlotCount ?? 0) + 1;
        tx.update(gigRef, { filledSlotCount: f, status: f >= workerSlots ? 'filled' : 'partially_filled' });
        count.write();
      }, 'quickgig.slotAccepted');
      filled++;
      vu.world.assignments.push({ gigId, workerId: candidate.uid, single: false, quick: true });
      continue;
    }
    // Declined: the candidate's own write already set their slot to
    // 'declined' and added them to the parent's exclusionList — loop again.
  }

  if (filled < workerSlots) {
    await cUpdate(vu, gigRef, {
      status: filled > 0 ? 'partially_filled' : 'no_worker',
      ...(workerSlots <= 1 && filled === 0 ? { assignedWorkerId: deleteField(), assignedWorkerName: deleteField() } : {}),
    }, 'quickgig.searchClosed').catch(() => {});
  }
}

/** findBestWorker: the unbounded scan that is the actual risk this closes. */
async function findBestWorker(vu, { gigLocation, excluded, hostId }) {
  const { db } = vu.client;
  const snap = await cQuery(vu, query(
    collection(db, 'users'),
    where('isOnline', '==', true), where('availableForGigs', '==', true),
    where('seekingQuickGigs', '==', true), where('slot', '==', 'AVAILABLE'),
  ), 'quickgig.scan', 'quickGigScanGlobal');

  let best = null, bestD = Infinity;
  for (const d of snap.docs) {
    if (excluded.includes(d.id) || d.id === hostId) continue;
    const data = d.data();
    if ((data.blockedUsers ?? []).includes(hostId)) continue;
    const geo = data.location;
    if (!geo) continue;
    if (!data.email) continue; // need their login to simulate the accept/decline write
    const dist = distanceKm(gigLocation, { lat: geo.latitude, lng: geo.longitude });
    if (dist < bestD) { bestD = dist; best = { uid: d.id, name: data.name ?? 'Worker', email: data.email }; }
  }
  return best;
}

/** The dispatched candidate's own accept/decline write — must come from
 *  their auth (firestore.rules requires assignedWorkerId/slot-doc ownership),
 *  so this signs in briefly as them, exactly like race.mjs's per-candidate
 *  clients and session.mjs's chat peer. Uses the email read straight off
 *  their scanned `users` doc (not the static pre-seeded population map),
 *  so a worker who registered live during this same run is just as
 *  reachable as one seeded before the stage started. */
async function respondToDispatch(world, { candidate, gigId, isMulti, accept }) {
  const client = await createClient(world.env, `qg${candidate.uid.slice(0, 6)}`);
  const pvu = { m: world.m, limiter: world.limiter, listeners: [] };
  try {
    await pvu.limiter.take();
    await signInWithEmailAndPassword(client.auth, candidate.email, world.password(candidate.email));
    const { db } = client;
    if (isMulti) {
      const slotRef = doc(db, 'quick_gigs', gigId, 'workers', candidate.uid);
      if (accept) {
        await cUpdate(pvu, slotRef, { status: 'navigating', acceptedAt: serverTimestamp() }, 'quickgig.respond');
        await cUpdate(pvu, doc(db, 'users', candidate.uid), { slot: 'LOCKED', acceptanceRate: increment(0.02) }, 'quickgig.respond');
      } else {
        await cUpdate(pvu, slotRef, { status: 'declined' }, 'quickgig.respond').catch(() => {});
        await cUpdate(pvu, doc(db, 'quick_gigs', gigId), { exclusionList: arrayUnion(candidate.uid) }, 'quickgig.respond').catch(() => {});
        await cUpdate(pvu, doc(db, 'users', candidate.uid), { slot: 'AVAILABLE', acceptanceRate: increment(-0.1) }, 'quickgig.respond').catch(() => {});
      }
    } else if (accept) {
      await cUpdate(pvu, doc(db, 'quick_gigs', gigId), { status: 'navigating', acceptedAt: serverTimestamp(), workerId: candidate.uid }, 'quickgig.respond');
      await cUpdate(pvu, doc(db, 'users', candidate.uid), { slot: 'LOCKED', acceptanceRate: increment(0.02) }, 'quickgig.respond');
    } else {
      await cUpdate(pvu, doc(db, 'quick_gigs', gigId), {
        status: 'scanning', assignedWorkerId: deleteField(), assignedWorkerName: deleteField(), exclusionList: arrayUnion(candidate.uid),
      }, 'quickgig.respond').catch(() => {});
      await cUpdate(pvu, doc(db, 'users', candidate.uid), { slot: 'AVAILABLE', acceptanceRate: increment(-0.1) }, 'quickgig.respond').catch(() => {});
    }
  } catch (e) {
    world.m.record('quickgig.respond', 0, e);
  } finally {
    for (const u of pvu.listeners) u();
    await destroyClient(client);
  }
}
