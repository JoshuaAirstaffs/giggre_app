// Deliberate contention: many workers apply to the same gig at once, then the
// host fires concurrent selections (double tap / two devices). Uses the same
// code paths as the app (applyTo / selectWorker), so it reports what the app
// would actually do under contention.
import { signInWithEmailAndPassword } from 'firebase/auth';
import { doc, collection, getDoc, getDocs, onSnapshot, addDoc, updateDoc, GeoPoint, Timestamp } from 'firebase/firestore';
import { createClient, destroyClient } from '../firebase.mjs';
import { applyTo, selectWorker } from './actions.mjs';
import { runQuickGigSearch } from './quickGigs.mjs';
import { rng } from '../synthetic.mjs';

export async function runRaces(world, log) {
  const { population, cfg, m } = world;
  const { raceGigsPerStage, applicantsPerRaceGig } = cfg.workload.contention;
  const hosts = population.hosts, workers = population.workers;
  if (hosts.length < 1 || workers.length < applicantsPerRaceGig) { log('race: not enough seeded users, skipped'); return; }
  log(`race: ${raceGigsPerStage} gigs x ${applicantsPerRaceGig} concurrent applicants`);

  for (let i = 0; i < raceGigsPerStage && !world.stopping; i++) {
    const multi = i % 4 === 3; // every 4th race gig has 2 slots
    const host = hosts[(i * 31) % hosts.length];
    const crew = Array.from({ length: applicantsPerRaceGig }, (_, k) => workers[(i * 97 + k * 13) % workers.length]);
    const people = [host, ...new Map(crew.map((c) => [c.uid, c])).values()];
    const vus = [];
    try {
      for (const p of people) {
        const client = await createClient(world.env, `race${i}-${p.index}`);
        await signInWithEmailAndPassword(client.auth, p.email, world.password(p.email));
        vus.push({ m, limiter: world.limiter, listeners: [], client, uid: client.auth.currentUser.uid, person: p, world, r: { chance: () => false } });
      }
      const [hv, ...wvs] = vus;
      const ref = await addDoc(collection(hv.client.db, 'open_gigs'), {
        hostId: hv.uid, hostName: host.name, title: `Race gig ${i} [LT]`, description: 'Contention test', requiredSkills: ['LT Moving'],
        experienceLevel: 'entry', budget: 500, currencyCode: 'PHP', payType: 'flat',
        location: new GeoPoint(host.lat, host.lng), address: 'Race St.', status: 'open', gigType: 'open',
        createdAt: Timestamp.now(), workerSlots: multi ? 2 : 1, ratePerSlot: 500, filledSlotCount: 0, slotsCompleted: 0,
        [cfg.safety.syntheticMarkerField]: world.runId,
      });
      m.writes(1);
      world.createdGigs.push({ col: 'open_gigs', id: ref.id, hostId: hv.uid, workerSlots: multi ? 2 : 1, race: true });

      // Every applicant watches the gig, like the worker app does.
      const believedAssigned = new Set();
      for (const wv of wvs) {
        wv.listeners.push(onSnapshot(doc(wv.client.db, 'open_gigs', ref.id), (s) => {
          const d = s.data();
          if (d?.workerId === wv.uid && d.status === 'navigating') believedAssigned.add(wv.uid);
        }));
      }

      // 1) Concurrent applications: arrayUnion on one hot document.
      const applied = await Promise.allSettled(wvs.map((wv) => applyTo(wv, ref.id, 'race.apply')));
      const okApplies = applied.filter((a) => a.status === 'fulfilled').length;
      const after = (await getDoc(ref)).data();
      m.reads(1, 'race');
      m.check('race.noLostApplications', (after.applicants ?? []).length === okApplies,
        { gig: ref.id, succeeded: okApplies, stored: (after.applicants ?? []).length });

      // 2) Concurrent selections from the host (double tap / two devices).
      const cands = (after.applicants ?? []).slice(0, multi ? 5 : 2);
      // Alternate single-slot races between the current app (transaction) and
      // old app versions (plain update) — the rules must stop both.
      const legacy = !multi && i % 2 === 1;
      const sel = await Promise.allSettled(cands.map((a) => selectWorker(hv, ref.id, after, a, legacy ? 'race.selectLegacy' : 'race.select', { legacy })));
      const okSel = sel.filter((s) => s.status === 'fulfilled').length;
      await new Promise((r) => setTimeout(r, 1500)); // let listeners settle
      const final = (await getDoc(ref)).data();
      const slots = (await getDocs(collection(hv.client.db, 'open_gigs', ref.id, 'workers'))).size;
      m.reads(2, 'race');
      if (multi) {
        m.check('race.multiSlotNoOverfill', okSel <= 2 && slots <= 2 && (final.filledSlotCount ?? 0) === slots,
          { gig: ref.id, selectsSucceeded: okSel, slotDocs: slots, filledSlotCount: final.filledSlotCount });
      } else {
        // Exclusive gig: only one selection should be accepted, and only one
        // worker should ever be shown "you got the gig".
        m.check('race.singleSlotOneSelectAccepted', okSel <= 1, { gig: ref.id, legacyClient: legacy, selectsSucceeded: okSel, finalWorker: final.workerId });
        m.check('race.duplicateExclusiveAssignment', believedAssigned.size <= 1,
          { gig: ref.id, workersToldAssigned: [...believedAssigned], finalWorker: final.workerId });
      }
    } catch (e) {
      m.record('race.setup', 0, e);
      log(`race ${i}: ${e.message}`);
    } finally {
      for (const v of vus) { for (const u of v.listeners) u(); await destroyClient(v.client); }
    }
  }
}

// Deliberate contention for the quick-gig dispatch loop (quickGigs.mjs):
// _dispatchToWorker has no transaction guarding `users/{uid}.slot`, so two
// hosts searching concurrently over the same (small) eligible-worker pool can
// both pick and dispatch to the same candidate before either write lands —
// see docs/architecture-audit.md §8 risk 8. Two hosts race over one shared,
// tiny pool of candidates to make that collision likely instead of rare.
export async function runQuickGigRaces(world, log) {
  const { population, cfg, m } = world;
  const { quickGigRacePairs, candidatesPerQuickGigRace } = cfg.workload.contention;
  const hosts = population.hosts, workers = population.workers;
  if (!quickGigRacePairs || hosts.length < 2 || workers.length < candidatesPerQuickGigRace) {
    log('quick-gig race: not enough seeded users, skipped'); return;
  }
  log(`quick-gig race: ${quickGigRacePairs} pairs x ${candidatesPerQuickGigRace} shared candidates`);

  for (let i = 0; i < quickGigRacePairs && !world.stopping; i++) {
    const h1 = hosts[(i * 41) % hosts.length];
    const h2 = hosts[(i * 41 + 17) % hosts.length];
    const cands = Array.from({ length: candidatesPerQuickGigRace }, (_, k) => workers[(i * 53 + k * 19) % workers.length]);
    const people = [...new Map([h1, h2, ...cands].map((p) => [p.uid, p])).values()];
    if (people.length < 3) { log(`quick-gig race ${i}: host/candidate overlap, skipped`); continue; }
    const vus = new Map();
    try {
      for (const p of people) {
        const client = await createClient(world.env, `qgrace${i}-${p.index}`);
        await signInWithEmailAndPassword(client.auth, p.email, world.password(p.email));
        vus.set(p.uid, {
          m, limiter: world.limiter, listeners: [], client, uid: client.auth.currentUser.uid, person: p, world,
          r: rng(1_000_000 + i * 97 + p.index),
        });
      }
      const loc = new GeoPoint(h1.lat, h1.lng);
      // Make every candidate eligible and co-located, so both searches see
      // the exact same (tiny) pool on their very first scan.
      for (const w of cands) {
        const cv = vus.get(w.uid);
        await updateDoc(doc(cv.client.db, 'users', w.uid), {
          isOnline: true, availableForGigs: true, seekingQuickGigs: true, slot: 'AVAILABLE', location: loc,
        });
      }
      m.writes(cands.length);

      const postOne = async (host) => {
        const hv = vus.get(host.uid);
        const ref = await addDoc(collection(hv.client.db, 'quick_gigs'), {
          hostId: hv.uid, hostName: host.name, title: `Quick race gig ${i} [LT]`, description: 'Contention test',
          category: 'LT Moving', budget: 300, currencyCode: 'PHP', payType: 'flat', duration: 'Flexible',
          location: loc, address: 'Race St.', status: 'scanning', gigType: 'quick', createdAt: Timestamp.now(),
          workerSlots: 1, ratePerSlot: 300, filledSlotCount: 0, slotsCompleted: 0, exclusionList: [],
          [cfg.safety.syntheticMarkerField]: world.runId,
        });
        m.writes(1);
        world.createdGigs.push({ col: 'quick_gigs', id: ref.id, hostId: hv.uid, workerSlots: 1, race: true });
        await runQuickGigSearch(hv, ref.id, { lat: h1.lat, lng: h1.lng }, 1, { ratePerSlot: 300, currencyCode: 'PHP' }, cfg.workload.quickGigs);
        return ref.id;
      };

      const before = world.assignments.length;
      const [g1, g2] = await Promise.allSettled([postOne(h1), postOne(h2)]);
      const gigIds = [g1, g2].filter((r) => r.status === 'fulfilled').map((r) => r.value);
      const theseAssignments = world.assignments.slice(before).filter((a) => a.quick && gigIds.includes(a.gigId));
      const workerIds = theseAssignments.map((a) => a.workerId);
      const dupes = workerIds.length !== new Set(workerIds).size;
      m.check('race.quickGigNoDoubleDispatch', !dupes, { gigIds, assignments: theseAssignments });
    } catch (e) {
      m.record('race.quickGigSetup', 0, e);
      log(`quick-gig race ${i}: ${e.message}`);
    } finally {
      for (const v of vus.values()) { for (const u of v.listeners) u(); await destroyClient(v.client); }
    }
  }
}
