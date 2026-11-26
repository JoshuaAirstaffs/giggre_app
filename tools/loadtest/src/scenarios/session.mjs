// One virtual-user session: sign in (or register), open the app the way
// HomeScreen + ModeShell do (both Worker and Host shells mounted, so both
// listener sets run), perform the session's intent plus secondary actions with
// think time, then close (isOnline false, listeners off).
//
// Every Firestore path, field and query shape here comes from the code audit
// (docs/architecture-audit.md). Change it when the app changes.
import { signInWithEmailAndPassword, createUserWithEmailAndPassword } from 'firebase/auth';
import {
  doc, collection, collectionGroup, query, where, orderBy, limit,
  arrayUnion, GeoPoint, Timestamp, serverTimestamp,
} from 'firebase/firestore';
import { createClient, destroyClient, cGet, cQuery, cListen, cUpdate, cBatch, Rejection } from '../firebase.mjs';
import { rng } from '../synthetic.mjs';
import * as A from './actions.mjs';

export const ACTIVE = ['navigating', 'arrived', 'working', 'task_complete', 'payment'];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function runSession(world, s) {
  const { m } = world;
  const r = rng(s.sessionSeed);
  const person = world.population.byIndex[s.user];
  const vu = { m, limiter: world.limiter, listeners: [], r, s, world, person, uid: null, client: null, gigs: new Map(), rooms: [] };
  const deadline = Date.now() + s.realDurationSec * 1000;
  m.sessionStart();
  let ok = true;
  try {
    vu.client = await createClient(world.env, `u${s.user}`);
    if (s.intent === 'register') await A.register(vu);
    else await login(vu);
    world.active.set(vu.uid, vu);

    await appOpen(vu);

    const plan = sessionActions(vu);
    for (const step of plan) {
      if (Date.now() > deadline || world.stopping) break;
      await sleep(think(vu));
      try { await step(vu); }
      catch (e) { if (e.code === 'lt-stopped') break; /* already recorded by the wrapper */ }
    }
    // Stay in the app (listeners open, receiving fan-out) until the session ends.
    while (Date.now() < deadline && !world.stopping) await sleep(Math.min(5000, deadline - Date.now()));
  } catch (e) {
    ok = false;
    if (e.code !== 'lt-stopped') m.record('session.fatal', 0, e);
  } finally {
    await closeApp(vu).catch(() => {});
    if (vu.uid) world.active.delete(vu.uid);
    m.sessionEnd(ok);
  }
}

const think = (vu) => {
  const [lo, hi] = vu.world.cfg.workload.sessionLength.thinkTimeSec;
  return vu.r.float(lo, hi) * 1000;
};

/** Primary intent first, then secondary actions by probability. */
function sessionActions(vu) {
  const p = vu.world.cfg.workload.secondaryActionProbability;
  const isWorker = vu.person.role === 'worker';
  const steps = [];
  const primary = {
    browse: [A.browseList, A.openGigDetail, A.openGigDetail],
    explore: [A.openNotifications, A.viewProfile, A.openChatList],
    apply: [A.browseList, A.openGigDetail, A.applyToGig, A.watchApplication],
    chat: [A.openChatList, A.chatConversation],
    post: [A.postGig],
    manage: [A.reviewApplicants],
    register: [A.browseList],
  }[vu.s.intent] ?? [A.browseList];
  steps.push(...primary);
  if (vu.r.chance(p.switchToMap)) steps.push(A.mapViewport);
  if (vu.r.chance(p.openGigDetail)) steps.push(A.openGigDetail);
  if (vu.r.chance(p.openNotifications)) steps.push(A.openNotifications);
  if (vu.r.chance(p.openChatList)) steps.push(A.openChatList);
  if (vu.r.chance(p.viewProfile)) steps.push(A.viewProfile);
  if (vu.r.chance(p.updateProfile)) steps.push(A.updateProfile);
  if (vu.r.chance(p.refreshList)) steps.push(A.browseList);
  steps.push(isWorker ? A.advanceMyGig : A.advanceHostedGig); // lifecycle progress if any
  if (vu.r.chance(vu.world.cfg.workload.securityProbeShare ?? 0.02)) steps.push(A.securityProbe);
  return steps;
}

async function login(vu) {
  const { auth } = vu.client;
  const { email } = vu.person;
  const pw = vu.world.password(email);
  // A few sessions fat-finger the password first (expected rejection).
  if (vu.r.chance(0.02)) {
    await vu.m.time('auth.login', async () => {
      try { await signInWithEmailAndPassword(auth, email, `${pw}-wrong`); }
      catch (e) { if (['auth/wrong-password', 'auth/invalid-credential', 'auth/invalid-login-credentials'].includes(e.code)) throw new Rejection('invalid-credentials'); throw e; }
    }).catch(() => {});
  }
  await vu.limiter.take();
  const cred = await vu.m.time('auth.login', () => signInWithEmailAndPassword(auth, email, pw));
  vu.uid = cred.user.uid;
  // Long sessions force a token refresh like an app resumed after an hour.
  if (vu.s.realDurationSec > 400) await vu.m.time('auth.tokenRefresh', () => cred.user.getIdToken(true));
}

/** Everything that loads on HomeScreen and the two mounted shells. */
export async function appOpen(vu) {
  const { db } = vu.client, uid = vu.uid, me = doc(db, 'users', uid);
  const t0 = performance.now();
  const L = (target, op, label, cb) => cListen(vu, target, op, label, cb);

  // main.dart / CurrentUserProvider / LiveSupportBubble
  const initial = [
    L(doc(db, 'general_config', 'maintenance'), 'open.config', 'config'),
    L(doc(db, 'app_content', 'word_filter'), 'open.config', 'config'),
    L(doc(db, 'general_config', 'gig_visibility_rules'), 'open.config', 'config'),
    L(doc(db, 'general_config', 'live_support'), 'open.config', 'config'),
    L(me, 'open.userDoc', 'userDoc'),
  ];
  await cGet(vu, me, 'open.userDoc', 'userDoc');      // AuthGate restore
  await cGet(vu, me, 'open.userDoc', 'userDoc');      // HomeScreen._loadUser
  // FCM registerForUser runs twice (setCurrentUserInfo is called twice).
  const token = `lt-fcm-${uid}`;
  for (let i = 0; i < 2; i++) {
    await cQuery(vu, query(collection(db, 'users'), where('fcmTokens', 'array-contains', token)), 'open.fcmTokens', 'fcmTokens');
    await cUpdate(vu, me, { fcmTokens: arrayUnion(token) }, 'open.fcmRegister');
  }
  await cQuery(vu, collection(db, 'app_content', 'updates', 'items'), 'open.content', 'content');
  await cGet(vu, doc(db, 'app_content', 'carousel_items'), 'open.content', 'content');
  await cQuery(vu, collection(db, 'app_content', 'carousel_items', 'items'), 'open.content', 'content');

  const gigCols = ['quick_gigs', 'open_gigs', 'offered_gigs'];
  const statusQ = (statuses) => [
    ...gigCols.map((c) => query(collection(db, c), where('workerId', '==', uid), where('status', 'in', statuses), limit(1))),
    query(collectionGroup(db, 'workers'), where('workerId', '==', uid), where('status', 'in', statuses)),
  ];
  initial.push(
    L(doc(db, 'gig_points', uid), 'open.misc', 'misc'),
    ...statusQ(ACTIVE).map((q) => L(q, 'open.activeGig', 'activeGig')),
    ...statusQ(['cancellation_requested']).map((q) => L(q, 'open.activeGig', 'activeGig')),
    // Shell chat badges (identical queries share one listen target in the SDK).
    L(query(collection(db, 'chat_rooms'), where('userId', '==', uid), where('isSupport', '==', true)), 'open.chatBadges', 'chatBadges'),
    L(query(collection(db, 'group_chats'), where('participants', 'array-contains', uid), orderBy('lastMessageAt', 'desc')), 'open.chatBadges', 'chatBadges'),
    L(query(collection(db, 'chat_rooms'), where('participants', 'array-contains', uid)), 'open.chatBadges', 'chatBadges', (snap) => {
      vu.rooms = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    }),
    // GigWorkerScreen
    L(collection(db, 'users', uid, 'savedGigs'), 'open.worker', 'worker'),
    L(query(collection(db, 'quick_gigs'), where('assignedWorkerId', '==', uid), where('status', '==', 'in_progress')), 'open.worker', 'worker'),
    L(query(collection(db, 'offered_gigs'), where('workerId', '==', uid), where('status', '==', 'offered')), 'open.worker', 'worker'),
    L(query(collection(db, 'open_gigs'), where('workerId', '==', uid), where('status', '==', 'navigating')), 'open.worker', 'worker'),
    L(query(collectionGroup(db, 'workers'), where('workerId', '==', uid), where('status', '==', 'navigating')), 'open.worker', 'worker'),
    L(query(collectionGroup(db, 'workers'), where('workerId', '==', uid), where('gigCollection', '==', 'quick_gigs'), where('status', '==', 'in_progress')), 'open.worker', 'worker'),
    L(query(collectionGroup(db, 'workers'), where('workerId', '==', uid), where('gigCollection', '==', 'offered_gigs'), where('status', '==', 'offered')), 'open.worker', 'worker'),
    L(doc(db, 'general_config', 'unverified_limits'), 'open.worker', 'worker'),
    L(doc(db, 'transaction_totals', uid), 'open.worker', 'worker'),
    // GigMapSection: the GLOBAL open-gigs listener (no geo bound, no limit).
    L(query(collection(db, 'open_gigs'), where('status', 'in', ['open', 'partially_filled'])), 'browse.list', 'openGigsGlobal', (snap) => onOpenGigs(vu, snap)),
    // GigHostScreen / HostGigsScreen / ProfileTab
    L(query(collection(db, 'open_gigs'), where('hostId', '==', uid), where('status', '==', 'open')), 'open.host', 'host'),
    L(query(collection(db, 'users'), where('isOnline', '==', true)), 'open.onlineUsers', 'onlineUsersGlobal'),
    L(query(collection(db, 'notifications'), where('userId', '==', uid), orderBy('createdAt', 'desc'), limit(100)), 'open.host', 'host'),
    ...gigCols.map((c) => L(query(collection(db, c), where('hostId', '==', uid), orderBy('createdAt', 'desc')), 'open.host', 'hostGigs', (snap) => {
      for (const d of snap.docs) vu.gigs.set(`${c}/${d.id}`, { col: c, id: d.id, ...d.data() });
    })),
  );
  await Promise.all(initial);
  await cGet(vu, me, 'open.userDoc', 'userDoc'); // gig filters (GigMapSection)
  await cQuery(vu, collection(db, 'skills'), 'open.skills', 'skills'); // once per app process = once per session

  // Per-room unread listeners (one per chat room, from shells + HomeChat).
  for (const room of vu.rooms.slice(0, 30)) {
    const other = (room.participants ?? []).find((p) => p !== uid);
    if (other) vu.listeners.length < 200 && cListen(vu, query(collection(db, 'chat_rooms', room.id, 'messages'), where('senderId', '==', other), where('hasSeen', '==', false), limit(1)), 'open.roomUnread', 'roomUnread');
  }
  // Worker mode active → online + location (users/{uid} writes fan out to
  // every session holding the global isOnline listener).
  if (vu.person.role === 'worker') {
    await cUpdate(vu, me, { isOnline: true }, 'open.setOnline');
    vu.online = true;
    await cUpdate(vu, me, { location: new GeoPoint(vu.person.lat, vu.person.lng) }, 'open.location');
    // Dashboard toggle (gig_worker_screen.dart _seekingQuickGigs), default
    // off — only a share of workers opt in, same as the real app.
    if (vu.r.chance(vu.world.cfg.workload.quickGigs?.seekingShare ?? 0)) {
      await cUpdate(vu, me, { seekingQuickGigs: true }, 'open.setOnline');
    }
  }
  vu.m.sample('session.appOpenReady', performance.now() - t0);
}

function onOpenGigs(vu, snap) {
  const w = vu.world;
  for (const ch of snap.docChanges()) {
    const key = `open_gigs/${ch.doc.id}`;
    if (ch.type === 'removed') { vu.gigs.delete(key); continue; }
    vu.gigs.set(key, { col: 'open_gigs', id: ch.doc.id, ...ch.doc.data() });
    if (ch.type === 'added') {
      const posted = w.pendingVisibility.get(ch.doc.id);
      if (posted && posted.by !== vu.uid && !posted.seen) {
        posted.seen = true;
        vu.m.sample('gig.propagation', Date.now() - posted.at);
      }
    }
  }
}

async function closeApp(vu) {
  if (vu.client && vu.uid) {
    const killed = vu.r.chance(vu.world.cfg.workload.sessionEnd?.killedShare ?? 0.05);
    if (vu.online && !killed) {
      await cUpdate(vu, doc(vu.client.db, 'users', vu.uid), { isOnline: false }, 'close.setOffline').catch(() => {});
    }
  }
  for (const u of vu.listeners) { try { u(); } catch { /* ignore */ } }
  vu.listeners = [];
  if (vu.peer) await vu.peer.close().catch(() => {});
  if (vu.client) await destroyClient(vu.client);
}

export { cBatch, Timestamp, serverTimestamp, createUserWithEmailAndPassword };
