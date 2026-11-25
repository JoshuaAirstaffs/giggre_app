// Creates the pre-existing marketplace for a stage: returning users (Auth +
// users/{uid} written with their own token, so rules apply), open gigs posted
// by synthetic hosts, and gig chat rooms with history. New users are NOT
// seeded — they register during the run.
import { writeFileSync, readFileSync, existsSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { STATE_DIR } from './config.mjs';
import { identity, rng, geoPoint, gigContent, chatText, SKILLS } from './synthetic.mjs';
import { signUpOrIn, commit, writeOp, ts, geo, SERVER_TIME, ownerToken } from './rest.mjs';

export function passwordFn(env) {
  let salt;
  if (env.hosts) salt = 'emulator-only-not-a-secret';
  else {
    salt = process.env.LOADTEST_PASSWORD_SALT;
    if (!salt || salt.length < 16) throw new Error('Set LOADTEST_PASSWORD_SALT (16+ chars) in the environment for non-emulator runs. It is never written to disk.');
  }
  return (email) => createHash('sha256').update(`${salt}:${email}`).digest('base64url').slice(0, 24);
}

export const populationFile = (envName, stage) => path.join(STATE_DIR, `population-${envName}-stage${stage}.json`);

export function loadPopulation(envName, stage) {
  const f = populationFile(envName, stage);
  if (!existsSync(f)) return null;
  return indexPopulation(JSON.parse(readFileSync(f, 'utf8')));
}

export function indexPopulation(raw) {
  const byIndex = raw.people;
  const returning = byIndex.filter((p) => p.uid && !p.isNew);
  const byUid = new Map(returning.map((p) => [p.uid, p]));
  const roomsByUid = new Map();
  for (const r of raw.rooms ?? []) for (const u of r.participants) (roomsByUid.get(u) ?? roomsByUid.set(u, []).get(u)).push(r);
  return { ...raw, byIndex, returning, byUid, roomsByUid, workers: returning.filter((p) => p.role === 'worker'), hosts: returning.filter((p) => p.role === 'host') };
}

async function pool(items, concurrency, fn, onProgress) {
  let i = 0, done = 0;
  const workers = Array.from({ length: concurrency }, async () => {
    while (i < items.length) {
      const idx = i++;
      await fn(items[idx], idx);
      if (++done % 500 === 0) onProgress?.(done, items.length);
    }
  });
  await Promise.all(workers);
}

/** Config docs the app reads on start. Emulator only (clients can't write them). */
export async function seedConfig(env) {
  const owner = ownerToken(env);
  const writes = [
    writeOp(env, 'general_config/maintenance', { enabled: false }),
    writeOp(env, 'general_config/gig_visibility_rules', { allowGigAccessForUnverified: true }),
    writeOp(env, 'general_config/live_support', { enabled: false }),
    writeOp(env, 'general_config/unverified_limits', { enabled: true, maxUsd: 100, resetPeriod: 'monthly' }),
    writeOp(env, 'app_content/word_filter', { words: ['ltblockedword'] }),
    writeOp(env, 'app_content/carousel_items', { enabled: true }),
    ...[1, 2, 3].map((i) => writeOp(env, `app_content/carousel_items/items/lt${i}`, { title: `Carousel ${i}`, order: i })),
    ...[1, 2, 3].map((i) => writeOp(env, `app_content/updates/items/lt${i}`, { title: `Update ${i}`, createdAt: ts(new Date()) })),
    ...SKILLS.map((s, i) => writeOp(env, `skills/lt${i}`, { name: s, category: 'Load test' })),
  ];
  await commit(env, writes, owner);
}

/**
 * Builds the population for a plan and seeds Firebase. Returns the indexed
 * population and setup counters (reported separately from the stage load).
 */
export async function seedStage({ plan, schedule, cfg, env, runId, log }) {
  const { workload, safety } = cfg;
  const password = passwordFn(env);
  const r = rng(plan.seed ^ 0x5eed);
  const box = safety.syntheticGeoSandbox;
  const counters = { authAccounts: 0, writes: 0, failures: 0 };
  const newTag = runId.slice(-6);

  const people = schedule.users.map((u) => {
    const id = identity({ seed: plan.seed, index: u.index, roles: workload.roles, emailDomain: safety.syntheticEmailDomain, runTag: `s${plan.stage}` });
    const loc = geoPoint(r, box);
    // New users get a per-run address so a RETEST can register them again.
    const email = u.isNew ? id.email.replace('lt-', `lt-n${newTag}-`) : id.email;
    return { index: u.index, role: u.role, isNew: u.isNew, email, name: id.name, skills: id.skills, lat: loc.lat, lng: loc.lng, uid: null };
  });

  if (env.hosts) await seedConfig(env);

  log(`Seeding ${people.filter((p) => !p.isNew).length} returning users...`);
  const tokens = new Map();
  // Billable environments: Firebase Auth allows only ~100 password sign-ins
  // per second per project (QUOTA_EXCEEDED beyond that), so sign in fewer at
  // a time and retry with backoff when the quota answers.
  const authPool = env.hosts ? 40 : 8;
  const authWithRetry = async (p) => {
    for (let attempt = 0; ; attempt++) {
      try { return await signUpOrIn(env, p.email, password(p.email)); }
      catch (e) {
        if (attempt >= 6 || !/QUOTA_EXCEEDED|TOO_MANY_ATTEMPTS/.test(String(e.message))) throw e;
        await new Promise((ok) => setTimeout(ok, 1500 * (attempt + 1) + Math.random() * 1000));
      }
    }
  };
  await pool(people.filter((p) => !p.isNew), authPool, async (p) => {
    try {
      const res = await authWithRetry(p);
      p.uid = res.localId; tokens.set(p.uid, res.idToken); counters.authAccounts++;
      await commit(env, [writeOp(env, `users/${p.uid}`, {
        userId: `LT${String(p.index).padStart(7, '0')}`, email: p.email, name: p.name, legalAgeConfirmed: true,
        legalAgeConfirmedAt: ts(new Date()), phone: `+63918${String(p.index).padStart(7, '0')}`, balance: 0,
        createdAt: ts(new Date()), skills: p.skills, openGigsUnlocked: false, signInMethod: 'email', slot: 'AVAILABLE',
        availableForGigs: true, isVerified: 'unverified', acceptanceRate: 1.0, role: p.role, isOnline: false,
        location: geo(p.lat, p.lng), currencyCode: 'PHP', countryCode: 'PH', fcmTokens: [],
        referrals: { referral_code: `LT${p.index}`, referral_level: 0, referrals_count: 0 },
        [safety.syntheticMarkerField]: runId,
      })], res.idToken);
      counters.writes++;
    } catch (e) {
      counters.failures++;
      if (counters.failures <= 5) log(`  seed user ${p.email}: ${e.message}`);
    }
  }, (d, n) => log(`  users ${d}/${n}`));

  const hosts = people.filter((p) => p.uid && p.role === 'host');
  const workers = people.filter((p) => p.uid && p.role === 'worker');
  const nGigs = Math.round((workload.seedData.existingOpenGigsPerThousandUsers * plan.users) / 1000);
  log(`Seeding ${nGigs} open gigs...`);
  const gigs = [];
  await pool(Array.from({ length: nGigs }, (_, i) => i), 20, async (i) => {
    const h = hosts[i % hosts.length];
    if (!h) return;
    const c = gigContent(r, { gigMix: workload.gigMix, flexible: r.chance(workload.gigMix.flexibleShare) });
    const id = `lt${plan.stage}g${String(i).padStart(6, '0')}${newTag}`;
    const data = {
      hostId: h.uid, hostName: h.name, title: c.title, description: c.description, requiredSkills: [c.skill],
      experienceLevel: c.experienceLevel, budget: c.budget, currencyCode: 'PHP', payType: c.payType,
      ...(c.hourlyRate ? { hourlyRate: c.hourlyRate } : {}),
      location: geo(h.lat + r.float(-0.02, 0.02), h.lng + r.float(-0.02, 0.02)), address: c.address,
      status: 'open', gigType: 'open', createdAt: ts(new Date()),
      ...(c.flexible ? {} : { scheduledDate: ts(new Date(Date.now() + c.scheduledInHours * 3600_000)) }),
      workerSlots: c.workerSlots, ratePerSlot: c.budget, filledSlotCount: 0, slotsCompleted: 0,
      place: { country: 'Philippines', countryCode: 'PH', region: 'Metro Manila', city: 'Makati' },
      [safety.syntheticMarkerField]: runId,
    };
    try {
      await commit(env, [writeOp(env, `open_gigs/${id}`, data)], tokens.get(h.uid));
      counters.writes++;
      gigs.push({ id, hostId: h.uid, workerSlots: c.workerSlots });
    } catch (e) { counters.failures++; if (counters.failures <= 10) log(`  seed gig: ${e.message}`); }
  });

  const nRooms = Math.round((workload.seedData.existingChatRoomsPerThousandUsers * plan.users) / 1000);
  log(`Seeding ${nRooms} gig chat rooms with history...`);
  const rooms = [];
  await pool(Array.from({ length: Math.min(nRooms, gigs.length * 4) }, (_, i) => i), 20, async (i) => {
    const g = gigs[i % gigs.length];
    const wk = workers[(i * 7919) % workers.length];
    if (!g || !wk) return;
    const roomId = `gig_${g.id}${i >= gigs.length ? `_${i}` : ''}`;
    const participants = [wk.uid, g.hostId];
    const [lo, hi] = workload.seedData.historyMessagesPerRoom;
    const n = r.int(lo, hi);
    try {
      await commit(env, [writeOp(env, `chat_rooms/${roomId}`, {
        gigId: g.id, isGigChat: true, participants, sendTo: 'Host', createdByUid: wk.uid, createdByName: wk.name,
        subject: 'Gig Chat', status: 'open', lastMessage: '', lastMessageSender: '', lastMessageSenderId: '',
        lastMessageAt: SERVER_TIME, createdAt: SERVER_TIME, workerUid: wk.uid, hostUid: g.hostId,
        [safety.syntheticMarkerField]: runId,
      })], tokens.get(wk.uid));
      counters.writes++;
      for (let k = 0; k < n; k += 20) {
        const batch = [];
        for (let j = k; j < Math.min(n, k + 20); j++) {
          const sender = j % 2 ? g.hostId : wk.uid;
          batch.push({ sender, op: writeOp(env, `chat_rooms/${roomId}/messages/m${String(j).padStart(4, '0')}`, {
            senderId: sender, isSupport: false, name: 'LT', text: chatText(r), hasSeen: j < n - 3, hasSeenByAdmin: false,
            hasSeenByPeer: j < n - 3, isAutoReply: false, isDeleted: false, createdAt: ts(new Date(Date.now() - (n - j) * 60_000)),
          }) });
        }
        // Each participant writes their own messages (rules check membership).
        for (const uid of participants) {
          const mine = batch.filter((b) => b.sender === uid).map((b) => b.op);
          if (mine.length) { await commit(env, mine, tokens.get(uid)); counters.writes += mine.length; }
        }
      }
      rooms.push({ id: roomId, gigId: g.id, participants });
    } catch (e) { counters.failures++; if (counters.failures <= 15) log(`  seed room: ${e.message}`); }
  });

  const raw = { envName: plan.envName, stage: plan.stage, runId, createdAt: new Date().toISOString(), people, gigs, rooms, counters };
  mkdirSync(STATE_DIR, { recursive: true });
  writeFileSync(populationFile(plan.envName, plan.stage), JSON.stringify(raw)); // no passwords or tokens
  return { population: indexPopulation(raw), counters, password };
}
