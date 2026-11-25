// User actions. Each mirrors a real app code path (file references in
// docs/architecture-audit.md). Business-rule outcomes throw Rejection so they
// are counted as expected, not as failures.
import { createUserWithEmailAndPassword, signInWithEmailAndPassword } from 'firebase/auth';
import {
  doc, collection, collectionGroup, query, where, orderBy, limit,
  arrayUnion, arrayRemove, increment, GeoPoint, Timestamp, serverTimestamp, documentId, updateDoc,
} from 'firebase/firestore';
import {
  cGet, cQuery, cListen, cSet, cUpdate, cAdd, cBatch, cTxn, createClient, destroyClient, Rejection,
} from '../firebase.mjs';
import { gigContent, chatText, distanceKm } from '../synthetic.mjs';
import { ACTIVE } from './session.mjs';
import { postQuickGig } from './quickGigs.mjs';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const GIG_COLS = ['quick_gigs', 'open_gigs', 'offered_gigs'];
const marker = (vu) => ({ [vu.world.cfg.safety.syntheticMarkerField]: vu.world.runId });

// ── Registration (register_screen.dart / welcome_screen.dart) ──────────────
export async function register(vu) {
  const { auth, db } = vu.client;
  const w = vu.world;
  await w.regLimiter.take();
  // Edge cases first: duplicate e-mail and weak password are app-level "no".
  if (vu.r.chance(0.03) && w.population.returning.length) {
    const existing = vu.r.pick(w.population.returning);
    await vu.m.time('auth.register', async () => {
      try { await createUserWithEmailAndPassword(auth, existing.email, w.password(existing.email)); }
      catch (e) { if (e.code === 'auth/email-already-in-use') throw new Rejection('duplicate-account'); throw e; }
    }).catch(() => {});
  }
  if (vu.r.chance(0.01)) {
    await vu.m.time('auth.register', async () => {
      try { await createUserWithEmailAndPassword(auth, `weak-${vu.person.email}`, '123'); }
      catch (e) { if (e.code === 'auth/weak-password') throw new Rejection('invalid-input'); throw e; }
    }).catch(() => {});
  }
  await vu.limiter.take();
  let cred;
  try {
    cred = await vu.m.time('auth.register', () => createUserWithEmailAndPassword(auth, vu.person.email, w.password(vu.person.email)));
  } catch (e) {
    if (e.code !== 'auth/email-already-in-use') throw e; // RETEST against a kept project
    cred = await vu.m.time('auth.login', () => signInWithEmailAndPassword(auth, vu.person.email, w.password(vu.person.email)));
  }
  vu.uid = cred.user.uid;
  vu.person.uid = vu.uid;

  // generateUserId(): 3 letters + 6 digits, collision-checked.
  const L = () => String.fromCharCode(65 + vu.r.int(0, 25));
  let userId;
  do {
    userId = `${L()}${L()}${L()}${vu.r.int(100000, 999999)}`;
  } while (!(await cQuery(vu, query(collection(db, 'users'), where('userId', '==', userId), limit(1)), 'register.userIdCheck')).empty);
  let code;
  do {
    code = `${L()}${L()}${vu.r.int(10, 99)}${L()}${L()}${vu.r.int(10, 99)}`;
  } while (!(await cQuery(vu, query(collection(db, 'users'), where('referrals.referral_code', '==', code), limit(1)), 'register.referralCheck')).empty);

  const referrer = vu.r.chance(0.2) && w.population.returning.length ? vu.r.pick(w.population.returning) : null;
  const now = Timestamp.now();
  const user = {
    userId, email: vu.person.email, name: vu.person.name, legalAgeConfirmed: true, legalAgeConfirmedAt: now,
    phone: `+63917${String(vu.person.index).padStart(7, '0')}`, balance: 0, createdAt: now, skills: vu.person.skills,
    openGigsUnlocked: false, signInMethod: 'email', slot: 'AVAILABLE', availableForGigs: true, isVerified: 'unverified',
    termsAccepted: true, termsAcceptedAt: now, acceptanceRate: 1.0,
    referredBy: referrer?.uid ?? null,
    referrals: {
      referral_code: code, referral_level: 0, referrals_count: 0, verified_referrals: 0, not_verified_referrals: 0,
      pending_referrals: 0, cancelled_referrals: 0, rejected_referrals: 0,
      referredByUID: referrer?.uid ?? null, referredByName: referrer?.name ?? null,
    },
    location: new GeoPoint(vu.person.lat, vu.person.lng),
    ...marker(vu),
  };
  await cBatch(vu, db, (b) => {
    b.set(doc(db, 'users', vu.uid), user);
    if (!referrer) return 1;
    b.set(doc(db, 'users', referrer.uid, 'referrals_list', vu.uid), {
      name: vu.person.name, email: vu.person.email, joined_at: now, referral_code_used: 'LTREF', isVerified: 'unverified',
    });
    return 2;
  }, 'register.createProfile');
  // HomeScreen role pick.
  await cUpdate(vu, doc(db, 'users', vu.uid), { role: vu.person.role }, 'register.role');
}

// ── Browsing (GigMapSection) ────────────────────────────────────────────────
function visibleGigs(vu) {
  const me = { lat: vu.person.lat, lng: vu.person.lng };
  const list = [...vu.gigs.values()].filter((g) =>
    g.col === 'open_gigs' && g.hostId !== vu.uid && g.slotsClosed !== true &&
    ['open', 'partially_filled'].includes(g.status) && (g.filledSlotCount ?? 0) < (g.workerSlots ?? 1) && g.location);
  const withD = list.map((g) => ({ g, d: distanceKm(me, { lat: g.location.latitude, lng: g.location.longitude }) }));
  const near = withD.filter((x) => x.d <= 10);
  return (near.length ? near : withD.sort((a, b) => a.d - b.d).slice(0, 10)).map((x) => x.g);
}

/** The list is fed by the global listener opened in appOpen; "refresh" in the
 *  app re-renders from it, so this only records what the user would see. */
export async function browseList(vu) {
  const t = performance.now();
  const n = visibleGigs(vu).length;
  vu.m.sample('browse.clientFilterMs', performance.now() - t);
  vu.m.check('browse.listHasGigs', n > 0, { uid: vu.uid, visible: n });
}

/** Map viewport: the app has NO geographic Firestore query — pan/zoom only
 *  re-filters and re-clusters the already-loaded gigs on the device. We time
 *  the same O(n²) clustering in Node as an indicator (not a device number). */
export async function mapViewport(vu) {
  const gigs = [...vu.gigs.values()].filter((g) => g.col === 'open_gigs' && g.location);
  const t = performance.now();
  for (const zoomRadiusKm of [5, 2, 0.8]) {
    const used = new Set();
    for (let i = 0; i < gigs.length; i++) {
      if (used.has(i)) continue;
      used.add(i);
      for (let j = i + 1; j < gigs.length; j++) {
        if (used.has(j)) continue;
        const a = gigs[i].location, b = gigs[j].location;
        if (distanceKm({ lat: a.latitude, lng: a.longitude }, { lat: b.latitude, lng: b.longitude }) < zoomRadiusKm) used.add(j);
      }
    }
  }
  vu.m.sample('map.clusterCpuMs', performance.now() - t);
  vu.m.sample('map.markersLoaded', gigs.length);
  // Selecting a marker opens the same detail sheet as the list.
  await openGigDetail(vu);
}

export async function openGigDetail(vu) {
  const g = vu.r.pick(visibleGigs(vu));
  if (!g) return;
  vu.lastViewed = g;
  await cGet(vu, doc(vu.client.db, 'users', g.hostId), 'gig.detail', 'gigDetail'); // fetchHostInfo
}

// ── Applying (applyToOpenGig, gig_map_section.dart) ─────────────────────────
async function guardUnverifiedLimit(vu) {
  const { db } = vu.client;
  const [user, cfg] = await Promise.all([
    cGet(vu, doc(db, 'users', vu.uid), 'guard.limit', 'guard'),
    cGet(vu, doc(db, 'general_config', 'unverified_limits'), 'guard.limit', 'guard'),
  ]);
  if (cfg.data()?.enabled && user.data()?.isVerified !== 'verified') {
    await cGet(vu, doc(db, 'transaction_totals', vu.uid), 'guard.limit', 'guard');
  }
}

async function workerBusy(vu, statuses) {
  const { db } = vu.client;
  const qs = [
    query(collectionGroup(db, 'workers'), where('workerId', '==', vu.uid), where('status', 'in', statuses), limit(1)),
    ...GIG_COLS.map((c) => query(collection(db, c), where('workerId', '==', vu.uid), where('status', 'in', statuses), limit(1))),
  ];
  const snaps = await Promise.all(qs.map((q) => cQuery(vu, q, 'guard.activeGig', 'guard')));
  return snaps.some((s) => !s.empty);
}

export async function applyToGig(vu) {
  if (vu.person.role !== 'worker') return;
  const target = vu.lastViewed ?? vu.r.pick(visibleGigs(vu));
  if (!target) return;
  await applyTo(vu, target.id);
}

export async function applyTo(vu, gigId, opName = 'gig.apply') {
  const { db } = vu.client;
  const ref = doc(db, 'open_gigs', gigId);
  await vu.m.time(opName, async () => {
    await guardUnverifiedLimit(vu);
    const snap = await cGet(vu, ref, 'gig.apply.read', 'apply');
    const g = snap.data();
    if (!g) throw new Rejection('gig-unavailable');
    const slots = g.workerSlots ?? 1, filled = g.filledSlotCount ?? 0;
    if (g.slotsClosed) throw new Rejection('gig-unavailable');
    if (slots > 1 ? !(['open', 'partially_filled'].includes(g.status) && filled < slots) : g.status !== 'open') throw new Rejection('slot-full');
    if ((g.applicants ?? []).some((a) => a.workerId === vu.uid)) throw new Rejection('already-applied');
    if (await workerBusy(vu, ['cancellation_requested'])) throw new Rejection('request-pending');
    if (await workerBusy(vu, ACTIVE)) throw new Rejection('already-assigned');
    await cUpdate(vu, ref, { applicants: arrayUnion({ workerId: vu.uid, workerName: vu.person.name }) }, 'gig.apply.write');
    vu.appliedTo = { gigId, hostId: g.hostId, title: g.title };
    vu.world.applications.push({ gigId, workerId: vu.uid });
    cAdd(vu, collection(db, 'notifications'), {
      userId: g.hostId, category: 'new_applicant', message: `${vu.person.name} applied to ${g.title}`,
      workerName: vu.person.name, workerId: vu.uid, gigId, gigTitle: g.title, createdAt: serverTimestamp(),
    }, 'gig.apply.notify').catch(() => {});
  });
}

/** Worker keeps the gig open to see whether they got picked. */
export async function watchApplication(vu) {
  if (!vu.appliedTo) return;
  await cListen(vu, doc(vu.client.db, 'open_gigs', vu.appliedTo.gigId), 'gig.statusWatch', 'statusWatch', (snap) => {
    const d = snap.data?.();
    if (d?.workerId === vu.uid && d.status === 'navigating') vu.m.check('gig.assignmentSeenByWorker', true);
  });
}

// ── Posting (post_open_gig_screen.dart / post_offered_gig_screen.dart) ─────
export async function postGig(vu) {
  if (vu.person.role !== 'host') return;
  const { db } = vu.client;
  const w = vu.world;
  if (vu.r.chance(w.cfg.workload.gigMix.quick ?? 0)) return postQuickGig(vu);
  const flexible = vu.r.chance(w.cfg.workload.gigMix.flexibleShare);
  const c = gigContent(vu.r, { gigMix: w.cfg.workload.gigMix, flexible });
  const loc = { lat: vu.person.lat + vu.r.float(-0.02, 0.02), lng: vu.person.lng + vu.r.float(-0.02, 0.02) };
  const offered = vu.r.chance(w.cfg.workload.gigMix.offered);
  await guardUnverifiedLimit(vu);
  const base = {
    hostId: vu.uid, hostName: vu.person.name, title: c.title, description: c.description,
    experienceLevel: c.experienceLevel, budget: c.budget, currencyCode: 'PHP', payType: c.payType,
    ...(c.hourlyRate ? { hourlyRate: c.hourlyRate } : {}),
    ...(c.workDurationHours ? { workDurationHours: c.workDurationHours } : {}),
    location: new GeoPoint(loc.lat, loc.lng), address: c.address,
    createdAt: Timestamp.now(),
    ...(c.flexible ? {} : { scheduledDate: Timestamp.fromMillis(Date.now() + c.scheduledInHours * 3600_000) }),
    ratePerSlot: c.budget, filledSlotCount: 0, slotsCompleted: 0,
    place: { country: 'Philippines', countryCode: 'PH', region: 'Metro Manila', city: 'Makati' },
    ...marker(vu),
  };
  if (!offered) {
    const ref = await vu.m.time('gig.post', () => cAdd(vu, collection(db, 'open_gigs'), {
      ...base, requiredSkills: [c.skill], status: 'open', gigType: 'open', workerSlots: c.workerSlots,
    }, 'gig.post.write'));
    w.pendingVisibility.set(ref.id, { at: Date.now(), by: vu.uid, seen: false });
    w.createdGigs.push({ col: 'open_gigs', id: ref.id, hostId: vu.uid, workerSlots: c.workerSlots });
    vu.gigs.set(`open_gigs/${ref.id}`, { col: 'open_gigs', id: ref.id, ...base, status: 'open', workerSlots: c.workerSlots, applicants: [] });
    if (vu.r.chance(0.15)) { await sleep(2000); await editGig(vu, 'open_gigs', ref.id); }
    return;
  }
  // Offered: pick 1..slots recipients the host "knows".
  const n = c.workerSlots;
  const recipients = [];
  for (let i = 0; i < n && w.population.workers.length; i++) recipients.push(vu.r.pick(w.population.workers));
  const uniq = [...new Map(recipients.filter((x) => x.uid).map((x) => [x.uid, x])).values()];
  if (!uniq.length) return;
  for (const p of uniq) await cGet(vu, doc(db, 'users', p.uid), 'gig.post.pickWorker', 'post');
  const data = { ...base, skillRequired: c.skill, status: 'offered', gigType: 'offered', workerSlots: uniq.length };
  if (uniq.length === 1) Object.assign(data, { workerId: uniq[0].uid, workerName: uniq[0].name });
  await vu.m.time('gig.post', async () => {
    const ref = await cAdd(vu, collection(db, 'offered_gigs'), data, 'gig.post.write');
    w.createdGigs.push({ col: 'offered_gigs', id: ref.id, hostId: vu.uid, workerSlots: uniq.length });
    if (uniq.length > 1) {
      await cBatch(vu, db, (b) => {
        for (const p of uniq) {
          b.set(doc(db, 'offered_gigs', ref.id, 'workers', p.uid), {
            workerId: p.uid, workerName: p.name, gigId: ref.id, gigCollection: 'offered_gigs', hostId: vu.uid,
            hostName: vu.person.name, rate: c.budget, currencyCode: 'PHP', status: 'offered', offeredAt: serverTimestamp(),
          });
        }
        return uniq.length;
      }, 'gig.post.slots');
    }
  });
}

/** saveGigEdit (edit_gig.dart): transaction re-checking canEditGig. */
export async function editGig(vu, col, id) {
  const { db } = vu.client;
  const ref = doc(db, col, id);
  await cTxn(vu, db, async (tx, count) => {
    const snap = await tx.get(ref); count.read();
    const g = snap.data();
    const editable = g && g.status === 'open' && g.slotsClosed !== true && !(g.applicants?.length) &&
      !g.assignedWorkerId && !g.workerId && (g.filledSlotCount ?? 0) === 0;
    if (!editable) throw new Rejection('not-editable');
    tx.update(ref, { budget: g.budget + 50, ratePerSlot: g.budget + 50, description: `${g.description} (edited)`, editedAt: serverTimestamp() });
    count.write();
  }, 'gig.edit').catch((e) => { if (!e.expectedCode) throw e; });
}

// ── Host reviews applicants and selects (gig_detail_sheet.dart _selectWorker)
export async function reviewApplicants(vu) {
  if (vu.person.role !== 'host') return;
  const { db } = vu.client;
  const mine = [...vu.gigs.values()].filter((g) => g.col === 'open_gigs' && g.hostId === vu.uid && ['open', 'partially_filled'].includes(g.status));
  const withApplicants = mine.filter((g) => (g.applicants ?? []).length);
  const g = vu.r.pick(withApplicants.length ? withApplicants : mine);
  if (!g) return;
  const ref = doc(db, 'open_gigs', g.id);
  await cListen(vu, ref, 'gig.detailSheet', 'detailSheet');
  await cListen(vu, collection(db, 'open_gigs', g.id, 'workers'), 'gig.detailSheet', 'detailSheet');
  if (!withApplicants.length) {
    if (vu.r.chance(0.05)) await cancelUnassigned(vu, g);
    return;
  }
  const fresh = (await cGet(vu, ref, 'gig.detail', 'detailSheet')).data();
  const applicant = vu.r.pick(fresh?.applicants ?? []);
  if (!applicant) return;
  if (vu.r.chance(0.1)) {
    await cUpdate(vu, ref, { applicants: arrayRemove(applicant) }, 'gig.decline');
    return;
  }
  await selectWorker(vu, g.id, fresh, applicant).catch(() => {});
}

export async function selectWorker(vu, gigId, gig, applicant, opName = 'gig.accept', { legacy = false } = {}) {
  const { db } = vu.client;
  const ref = doc(db, 'open_gigs', gigId);
  const slots = gig.workerSlots ?? 1;
  if (slots <= 1 && !legacy) {
    // Single slot (app >= 3.0.8, gig_detail_sheet.dart _selectWorker): a
    // transaction that refuses when a worker is already set or the gig left 'open'.
    await cTxn(vu, db, async (tx, count) => {
      const snap = await tx.get(ref); count.read();
      const g = snap.data() ?? {};
      if (g.workerId) throw new Rejection('already-assigned');
      if (g.status !== 'open') throw new Rejection('gig-unavailable');
      if (!(g.applicants ?? []).some((a) => a.workerId === applicant.workerId)) throw new Rejection('gig-unavailable');
      tx.update(ref, {
        workerId: applicant.workerId, assignedWorkerId: applicant.workerId, assignedWorkerName: applicant.workerName,
        status: 'navigating', selectedAt: serverTimestamp(), applicants: arrayRemove(applicant),
      });
      count.write();
    }, opName, (e) => (e.code === 'permission-denied' ? new Rejection('already-assigned') : null));
    vu.world.assignments.push({ gigId, workerId: applicant.workerId, single: true });
    return;
  }
  if (slots <= 1) {
    // Single slot, app <= 3.0.7: plain update with no guard. Kept so the race
    // test proves the firestore.rules backstop also protects old app versions.
    await vu.limiter.take();
    await vu.m.time(opName, async () => {
      try {
        await updateDoc(ref, {
          workerId: applicant.workerId, assignedWorkerId: applicant.workerId, assignedWorkerName: applicant.workerName,
          status: 'navigating', selectedAt: serverTimestamp(), applicants: arrayRemove(applicant),
        });
      } catch (e) {
        // The workerId rule refusing a second assignment is the fix working.
        if (e.code === 'permission-denied') throw new Rejection('already-assigned');
        throw e;
      }
    });
    vu.m.writes(1);
    vu.world.assignments.push({ gigId, workerId: applicant.workerId, single: true });
    return;
  }
  await cTxn(vu, db, async (tx, count) => {
    const snap = await tx.get(ref); count.read();
    const g = snap.data();
    const filled = g.filledSlotCount ?? 0;
    if (filled >= (g.workerSlots ?? 1)) throw new Rejection('slot-full');
    const slotRef = doc(db, 'open_gigs', gigId, 'workers', applicant.workerId);
    const slot = await tx.get(slotRef); count.read();
    if (slot.exists()) throw new Rejection('already-assigned');
    tx.set(slotRef, {
      workerId: applicant.workerId, workerName: applicant.workerName, gigId, gigCollection: 'open_gigs',
      hostId: vu.uid, hostName: vu.person.name, rate: g.ratePerSlot ?? g.budget, currencyCode: 'PHP',
      status: 'navigating', selectedAt: serverTimestamp(),
    });
    const nf = filled + 1;
    tx.update(ref, { filledSlotCount: nf, status: nf >= g.workerSlots ? 'filled' : 'partially_filled', applicants: arrayRemove(applicant) });
    count.write(); count.write();
  }, opName);
  vu.world.assignments.push({ gigId, workerId: applicant.workerId, single: false });
}

async function cancelUnassigned(vu, g) {
  if (g.workerId || (g.filledSlotCount ?? 0) > 0) return;
  await cUpdate(vu, doc(vu.client.db, 'open_gigs', g.id), {
    cancellation_reason: arrayUnion({ reason: 'Load test: plans changed', approved: true, requestedBy: 'host' }),
    cancelledAt: serverTimestamp(), status: 'cancelled',
  }, 'gig.cancel');
}

// ── Lifecycle (working_ui.dart, gig_detail_sheet.dart, payment sheets) ─────
export async function advanceMyGig(vu) {
  const { db } = vu.client;
  const snap = await cQuery(vu, query(collection(db, 'open_gigs'), where('workerId', '==', vu.uid), where('status', 'in', ACTIVE), limit(1)), 'lifecycle.find', 'lifecycle');
  const d = snap.docs[0];
  if (!d) return;
  const ref = d.ref, g = d.data();
  const next = {
    navigating: async () => {
      for (let i = 0; i < 3; i++) await cUpdate(vu, ref, { workerLocation: new GeoPoint(vu.person.lat + i * 0.0005, vu.person.lng) }, 'lifecycle.location');
      await cUpdate(vu, ref, { status: 'arrived', arrivedAt: serverTimestamp() }, 'lifecycle.transition');
    },
    arrived: () => cUpdate(vu, ref, { status: 'working', workStartedAt: serverTimestamp() }, 'lifecycle.transition'),
    working: () => cUpdate(vu, ref, { status: 'task_complete', durationSeconds: vu.r.int(1800, 14400), workCompletedAt: serverTimestamp() }, 'lifecycle.transition'),
    payment: () => confirmPayment(vu, ref),
  }[g.status];
  if (next) await next().catch(() => {});
}

async function confirmPayment(vu, ref) {
  const { db } = vu.client;
  const userRef = doc(db, 'users', vu.uid);
  await cTxn(vu, db, async (tx, count) => {
    const gs = await tx.get(ref); count.read();
    const us = await tx.get(userRef); count.read();
    const g = gs.data();
    if (g.status !== 'payment') throw new Rejection('not-editable');
    const e = us.data()?.earnings ?? {};
    const amount = g.finalAmount ?? g.budget ?? 0;
    tx.update(userRef, { earnings: { total: (e.total ?? 0) + amount, weekly: (e.weekly ?? 0) + amount, currentWeek: e.currentWeek ?? 'LT', completedGigs: (e.completedGigs ?? 0) + 1, updatedAt: serverTimestamp() } });
    tx.update(ref, { status: 'completed', completedAt: serverTimestamp(), paymentConfirmedAt: serverTimestamp(), paymentConfirmedBy: 'worker' });
    count.write(); count.write();
  }, 'lifecycle.payment');
}

export async function advanceHostedGig(vu) {
  const g = [...vu.gigs.values()].find((x) => x.col === 'open_gigs' && x.hostId === vu.uid && x.status === 'task_complete' && x.workerId);
  if (!g) return;
  const { db } = vu.client;
  await cUpdate(vu, doc(db, 'open_gigs', g.id), {
    status: 'payment', paymentMethod: 'cash', paymentCode: String(vu.r.int(100000, 999999)),
    paymentInitiatedAt: serverTimestamp(), finalAmount: g.budget,
  }, 'lifecycle.hostConfirm').catch(() => {});
  await cUpdate(vu, doc(db, 'users', g.workerId), { slot: 'AVAILABLE' }, 'lifecycle.hostConfirm').catch(() => {});
}

// ── Notifications, profile, chat list ──────────────────────────────────────
export async function openNotifications(vu) {
  const { db } = vu.client;
  const q = vu.person.role === 'worker'
    ? query(collection(db, 'notifications'), where('userId', '==', vu.uid), limit(20))
    : query(collection(db, 'notifications'), where('userId', '==', vu.uid), orderBy('createdAt', 'desc'), limit(20));
  await cQuery(vu, q, 'notifications.open', 'notifications');
  await cListen(vu, doc(db, 'verification_requests', vu.uid), 'notifications.open', 'notifications');
}

export async function viewProfile(vu) {
  const { db } = vu.client;
  await cGet(vu, doc(db, 'users', vu.uid), 'profile.view', 'profile');
  const other = vu.r.pick(vu.world.population.returning);
  if (other?.uid) await cGet(vu, doc(db, 'publicProfiles', other.uid), 'profile.view', 'profile');
}

export async function updateProfile(vu) {
  await cUpdate(vu, doc(vu.client.db, 'users', vu.uid), { bio: `Load test bio ${vu.r.int(1, 9999)}` }, 'profile.update');
}

export async function openChatList(vu) {
  const { db } = vu.client;
  const snap = await cQuery(vu, query(collection(db, 'chat_rooms'), where('participants', 'array-contains', vu.uid)), 'chat.list', 'chatList');
  vu.rooms = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  for (const room of vu.rooms.slice(0, 10)) {
    const other = (room.participants ?? []).find((p) => p !== vu.uid);
    if (other) await cGet(vu, doc(db, 'users', other), 'chat.list', 'chatList');
  }
}

// ── Chat (lib/screens/chat/chat.dart) ──────────────────────────────────────
function pickRoom(vu) {
  if (vu.appliedTo) return { id: `gig_${vu.appliedTo.gigId}`, gigId: vu.appliedTo.gigId, peer: vu.appliedTo.hostId };
  const seeded = vu.world.population.roomsByUid.get(vu.uid) ?? [];
  const r = seeded.length ? vu.r.pick(seeded) : null;
  return r ? { id: r.id, gigId: r.gigId, peer: r.participants.find((p) => p !== vu.uid) } : null;
}

export async function chatConversation(vu) {
  const room = pickRoom(vu);
  if (!room?.peer) return;
  const { db } = vu.client, w = vu.world;
  const roomRef = doc(db, 'chat_rooms', room.id);
  const msgs = collection(db, 'chat_rooms', room.id, 'messages');
  const roomSnap = await cListen(vu, roomRef, 'chat.open', 'chatOpen');
  await Promise.all([
    cListen(vu, doc(db, 'users', vu.uid), 'chat.open', 'chatOpen'),
    cListen(vu, doc(db, 'users', room.peer), 'chat.open', 'chatOpen'),
    cGet(vu, doc(db, 'users', room.peer), 'chat.open', 'chatOpen'),
  ]);
  if (!roomSnap?.exists()) {
    await cSet(vu, roomRef, {
      gigId: room.gigId, isGigChat: true, participants: [vu.uid, room.peer], sendTo: 'Peer', createdByUid: vu.uid,
      createdByName: vu.person.name, subject: 'Gig Chat', status: 'open', lastMessage: '', lastMessageSender: '',
      lastMessageSenderId: '', lastMessageAt: serverTimestamp(), createdAt: serverTimestamp(), ...marker(vu),
    }, 'chat.createRoom');
  }
  const page = await cQuery(vu, query(msgs, orderBy('createdAt', 'desc'), limit(20)), 'chat.history', 'chatHistory');
  const newest = page.docs[0]?.data().createdAt ?? Timestamp.fromMillis(0);
  await cListen(vu, query(msgs, orderBy('createdAt'), where('createdAt', '>', newest)), 'chat.open', 'chatLive');
  // Mark seen (first room snapshot).
  for (const [field, op] of [['hasSeen', 'chat.markSeen'], ['hasSeenByPeer', 'chat.markSeen']]) {
    const unseen = await cQuery(vu, query(msgs, where(field, '==', false), where('senderId', '!=', vu.uid)), op, 'chatSeen');
    if (!unseen.empty) await cBatch(vu, db, (b) => { unseen.docs.forEach((d) => b.update(d.ref, { [field]: true })); return unseen.size; }, op);
  }
  // Optional paired peer: a second client signed in as the other participant,
  // so delivery latency and ordering are measured on one clock.
  let peer = null;
  const peerPerson = w.population.byUid.get(room.peer);
  if (peerPerson && vu.r.chance(w.cfg.workload.chat.pairedDeliveryShare)) peer = await openPeer(vu, peerPerson, room.id);

  const [lo, hi] = w.cfg.workload.chat.messagesPerChatSession;
  const n = vu.r.int(lo, hi);
  for (let i = 0; i < n && !w.stopping; i++) {
    const nonce = `${vu.uid.slice(0, 6)}-${Date.now().toString(36)}-${i}`;
    const text = `${chatText(vu.r)} [lt:${nonce}]`;
    const sentAt = Date.now();
    peer?.expect(nonce, sentAt, i);
    const ref = await vu.m.time('chat.send', async () => {
      const r = await cAdd(vu, msgs, {
        senderId: vu.uid, isSupport: false, name: vu.person.name, text, hasSeen: false, hasSeenByAdmin: false,
        hasSeenByPeer: false, isAutoReply: false, isDeleted: false, createdAt: serverTimestamp(),
      }, 'chat.send.message');
      await cUpdate(vu, roomRef, { lastMessage: text, lastMessageSender: 'You', lastMessageSenderId: vu.uid, lastMessageAt: serverTimestamp() }, 'chat.send.room');
      return r;
    }).catch(() => null);
    if (ref) w.sentMessages.push({ roomId: room.id, id: ref.id, nonce });
    await sleep(vu.r.float(1.5, 6) * 1000);
  }
  if (peer) { await sleep(3000); peer.finish(); await peer.close(); }
}

async function openPeer(vu, peerPerson, roomId) {
  const w = vu.world;
  const client = await createClient(w.env, `peer${peerPerson.index}`);
  const pvu = { m: vu.m, limiter: vu.limiter, listeners: [] };
  const expected = new Map();
  const seenOrder = [];
  try {
    await signInWithEmailAndPassword(client.auth, peerPerson.email, w.password(peerPerson.email));
  } catch (e) { vu.m.record('chat.peerLogin', 0, e); await destroyClient(client); return null; }
  const q = query(collection(client.db, 'chat_rooms', roomId, 'messages'), orderBy('createdAt'), where('createdAt', '>', Timestamp.now()));
  await cListen(pvu, q, 'chat.peerListen', 'chatPeer', (snap) => {
    for (const ch of snap.docChanges()) {
      if (ch.type !== 'added' || ch.doc.metadata.hasPendingWrites) continue;
      const m = /\[lt:([^\]]+)\]/.exec(ch.doc.data().text ?? '');
      const e = m && expected.get(m[1]);
      if (!e || e.got) continue;
      e.got = true;
      vu.m.sample('chat.delivery', Date.now() - e.sentAt);
      seenOrder.push(e.i);
    }
  });
  return {
    expect: (nonce, sentAt, i) => expected.set(nonce, { sentAt, i, got: false }),
    finish: () => {
      const missing = [...expected.values()].filter((e) => !e.got).length;
      vu.m.check('chat.noMissingMessages', missing === 0, { roomId, missing });
      const inOrder = seenOrder.every((v, i) => i === 0 || v > seenOrder[i - 1]);
      vu.m.check('chat.messageOrdering', inOrder, { roomId, seenOrder });
    },
    close: async () => { for (const u of pvu.listeners) u(); await destroyClient(client); },
  };
}

// ── Security probes: these MUST be denied by the rules ─────────────────────
export async function securityProbe(vu) {
  const { db } = vu.client, w = vu.world;
  const other = vu.r.pick(w.population.returning.filter((p) => p.uid && p.uid !== vu.uid));
  if (!other) return;
  const expectDenied = async (name, fn) => {
    try { await fn(); vu.m.check(name, false, { uid: vu.uid, target: other.uid }); }
    catch (e) { vu.m.check(name, e.code === 'permission-denied', { code: e.code }); }
  };
  await expectDenied('security.readOtherWallet', () => cGet(vu, doc(db, 'wallets', other.uid), 'probe', 'probe'));
  await expectDenied('security.readOtherNotifications', () => cQuery(vu, query(collection(db, 'notifications'), where('userId', '==', other.uid), limit(1)), 'probe', 'probe'));
  await expectDenied('security.forgeNotificationCategory', () => cAdd(vu, collection(db, 'notifications'), { userId: other.uid, category: 'payment', workerId: vu.uid, createdAt: serverTimestamp() }, 'probe'));
  await expectDenied('security.setOwnVerified', () => cUpdate(vu, doc(db, 'users', vu.uid), { isVerified: 'verified' }, 'probe'));
  // A synthetic open gig owned by someone else: changing a non-applicant field.
  const foreign = [...vu.gigs.values()].find((g) => g.col === 'open_gigs' && g.hostId !== vu.uid && g.status === 'open' && g[w.cfg.safety.syntheticMarkerField]);
  if (foreign) {
    await expectDenied('security.editForeignOpenGig', () => cUpdate(vu, doc(db, 'open_gigs', foreign.id), { budget: 1 }, 'probe'));
  }
}

export { documentId, increment };
