// Deterministic synthetic data. Every virtual user (VU) has a stable identity
// derived from (seed, index): same stage + seed => same people, so reports are
// comparable and cleanup knows exactly what it created.
//
// Field shapes mirror the app (see docs/architecture-audit.md §Data model).
// Nothing here talks to Firebase.

export function rng(seed) {
  // mulberry32
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return {
    next,
    int: (lo, hi) => lo + Math.floor(next() * (hi - lo + 1)),
    float: (lo, hi) => lo + next() * (hi - lo),
    pick: (xs) => xs[Math.floor(next() * xs.length)],
    chance: (p) => next() < p,
    /** weights: {key: weight} */
    weighted(weights) {
      const entries = Object.entries(weights).filter(([k]) => !k.startsWith('$'));
      const total = entries.reduce((s, [, w]) => s + w, 0);
      let r = next() * total;
      for (const [k, w] of entries) { if ((r -= w) <= 0) return k; }
      return entries[entries.length - 1][0];
    },
    /** Box-Muller lognormal around a median. */
    lognormal(median, sigma) {
      const u = Math.max(next(), 1e-9), v = next();
      const z = Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
      return median * Math.exp(sigma * z);
    },
  };
}

const FIRST = ['Ana', 'Ben', 'Carla', 'Dan', 'Ella', 'Franco', 'Gia', 'Hector', 'Ines', 'Jun', 'Kat', 'Leo', 'Mia', 'Nico', 'Olga', 'Paolo', 'Queenie', 'Rico', 'Sofia', 'Tomas'];
const LAST = ['Reyes', 'Santos', 'Cruz', 'Bautista', 'Garcia', 'Mendoza', 'Torres', 'Flores', 'Ramos', 'Aquino'];
// Skill names are synthetic and prefixed so they never collide with real
// `skills` docs; the emulator seed creates a matching `skills` collection.
export const SKILLS = ['LT Plumbing', 'LT Cleaning', 'LT Moving', 'LT Delivery', 'LT Gardening', 'LT Painting', 'LT Electrical', 'LT Tutoring'];
const GIG_TITLES = {
  'LT Plumbing': 'Fix leaking sink', 'LT Cleaning': 'Deep clean 2BR condo', 'LT Moving': 'Help move boxes',
  'LT Delivery': 'Same-day parcel run', 'LT Gardening': 'Trim garden hedges', 'LT Painting': 'Repaint bedroom wall',
  'LT Electrical': 'Install ceiling fan', 'LT Tutoring': 'Math tutor for grade 6',
};

export const pad = (n, w = 6) => String(n).padStart(w, '0');

/** Identity of VU #index in a population. Role is decided by index so the
 *  worker/host split is exact, not just expected. */
export function identity({ seed, index, roles, emailDomain, runTag }) {
  const r = rng(seed * 1_000_003 + index);
  // Evenly interleaved: user i is a host when the running host count steps
  // up, so any population size gets round(n * hostShare) hosts.
  const role = Math.floor((index + 1) * roles.host) > Math.floor(index * roles.host) ? 'host' : 'worker';
  const first = r.pick(FIRST), last = r.pick(LAST);
  return {
    index,
    role,
    // Stable across runs of the same stage so returning users really return.
    email: `lt-${role[0]}-${pad(index)}@${emailDomain}`,
    password: `lt-${runTag}-${pad(index)}-pw`,
    name: `${first} ${last} (LT)`,
    skills: [r.pick(SKILLS), r.pick(SKILLS)].filter((v, i, a) => a.indexOf(v) === i),
  };
}

export function geoPoint(r, box) {
  return { lat: r.float(box.latMin, box.latMax), lng: r.float(box.lngMin, box.lngMax) };
}

/** Haversine km — same maths the app uses client-side for the radius filter. */
export function distanceKm(a, b) {
  const R = 6371, toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat), dLng = toRad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/** Content for a host-posted gig. Firestore-specific values (GeoPoint,
 *  Timestamp) are attached by the scenario that writes it. */
export function gigContent(r, { gigMix, flexible }) {
  const skill = r.pick(SKILLS);
  const multi = r.chance(gigMix.multiSlotShare);
  const workerSlots = multi ? r.int(gigMix.slotsRange[0], gigMix.slotsRange[1]) : 1;
  const hourly = r.chance(0.3);
  const rate = hourly ? r.int(80, 250) : r.int(300, 3000);
  return {
    skill,
    title: `${GIG_TITLES[skill]} [LT]`,
    description: 'Synthetic load-test gig. Not a real job.',
    experienceLevel: r.pick(['entry', 'intermediate', 'expert']),
    payType: hourly ? 'hourly' : 'flat',
    budget: rate,
    hourlyRate: hourly ? rate : null,
    workDurationHours: r.chance(0.6) ? r.int(1, 8) : null,
    workerSlots,
    flexible,
    scheduledInHours: flexible ? null : r.int(6, 24 * 6),
    address: `${r.int(1, 999)} Load Test St., Makati`,
  };
}

export function chatText(r) {
  return r.pick([
    'Hi, is this gig still available?', 'I can start tomorrow morning.', 'What tools should I bring?',
    'Sure, see you then.', 'Can you share the exact address?', 'Running 10 minutes late, sorry!',
    'Done, please check.', 'Thanks!', 'How long will it take?', 'Is parking available?',
  ]);
}
