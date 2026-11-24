// Deliberate contention: many workers apply to the same gig at once, then the
// host fires concurrent selections (double tap / two devices). Uses the same
// code paths as the app (applyTo / selectWorker), so it reports what the app
// would actually do under contention.
import { signInWithEmailAndPassword } from 'firebase/auth';
import { doc, collection, getDoc, getDocs, onSnapshot, addDoc, GeoPoint, Timestamp } from 'firebase/firestore';
import { createClient, destroyClient } from '../firebase.mjs';
import { applyTo, selectWorker } from './actions.mjs';

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
