// Minimal Firebase REST helpers for seeding, consistency checks and cleanup.
// Requests carry the synthetic user's ID token, so security rules apply.
// The emulator-only `owner` token (rules bypass) is used for two things only:
// seeding config docs that clients can never write, and wiping the emulator.
// It is refused for any non-emulator environment.

export function endpoints(env) {
  const emu = Boolean(env.hosts);
  return {
    emu,
    auth: emu ? `http://${env.hosts.auth}/identitytoolkit.googleapis.com/v1` : 'https://identitytoolkit.googleapis.com/v1',
    fs: emu ? `http://${env.hosts.firestore}/v1/projects/${env.projectId}/databases/(default)/documents`
      : `https://firestore.googleapis.com/v1/projects/${env.projectId}/databases/(default)/documents`,
    fsEmuAdmin: emu ? `http://${env.hosts.firestore}/emulator/v1/projects/${env.projectId}/databases/(default)/documents` : null,
    authEmuAdmin: emu ? `http://${env.hosts.auth}/emulator/v1/projects/${env.projectId}/accounts` : null,
    key: emu ? 'demo-key' : env.webConfig?.apiKey,
  };
}

async function j(res) {
  const txt = await res.text();
  let body; try { body = txt ? JSON.parse(txt) : {}; } catch { body = { raw: txt }; }
  if (!res.ok) {
    const msg = body?.error?.message ?? body?.error?.status ?? txt.slice(0, 200);
    throw Object.assign(new Error(`${res.status} ${msg}`), { status: res.status, body });
  }
  return body;
}

// ── Auth ───────────────────────────────────────────────────────────────────
export async function signUp(env, email, password) {
  const e = endpoints(env);
  return j(await fetch(`${e.auth}/accounts:signUp?key=${e.key}`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  }));
}

export async function signIn(env, email, password) {
  const e = endpoints(env);
  return j(await fetch(`${e.auth}/accounts:signInWithPassword?key=${e.key}`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  }));
}

export async function signUpOrIn(env, email, password) {
  try { return await signUp(env, email, password); }
  catch (err) {
    if (String(err.message).includes('EMAIL_EXISTS')) return signIn(env, email, password);
    throw err;
  }
}

export async function deleteSelf(env, idToken) {
  const e = endpoints(env);
  return j(await fetch(`${e.auth}/accounts:delete?key=${e.key}`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ idToken }),
  }));
}

// ── Firestore value encoding ───────────────────────────────────────────────
export const ts = (date) => ({ __ts: date instanceof Date ? date.toISOString() : date });
export const geo = (lat, lng) => ({ __geo: { latitude: lat, longitude: lng } });
export const SERVER_TIME = { __serverTime: true };

export function enc(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(enc) } };
  if (v.__ts) return { timestampValue: v.__ts };
  if (v.__geo) return { geoPointValue: v.__geo };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).filter(([, x]) => !x?.__serverTime).map(([k, x]) => [k, enc(x)])) } };
}

export function dec(v) {
  if (!v) return null;
  if ('nullValue' in v) return null;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('stringValue' in v) return v.stringValue;
  if ('timestampValue' in v) return new Date(v.timestampValue);
  if ('geoPointValue' in v) return v.geoPointValue;
  if ('arrayValue' in v) return (v.arrayValue.values ?? []).map(dec);
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields ?? {}).map(([k, x]) => [k, dec(x)]));
  if ('referenceValue' in v) return v.referenceValue;
  return null;
}

const serverTimeFields = (data) => Object.entries(data).filter(([, x]) => x?.__serverTime).map(([k]) => k);

/** One write for :commit. `path` is relative to documents/. */
export function writeOp(env, path, data, { mustNotExist = false } = {}) {
  const base = `projects/${env.projectId}/databases/(default)/documents`;
  const st = serverTimeFields(data);
  return {
    update: { name: `${base}/${path}`, fields: enc(data).mapValue.fields },
    ...(mustNotExist ? { currentDocument: { exists: false } } : {}),
    ...(st.length ? { updateTransforms: st.map((fieldPath) => ({ fieldPath, setToServerValue: 'REQUEST_TIME' })) } : {}),
  };
}

export async function commit(env, writes, token) {
  const e = endpoints(env);
  return j(await fetch(`${e.fs}:commit`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    body: JSON.stringify({ writes }),
  }));
}

export async function getDocRest(env, path, token) {
  const e = endpoints(env);
  const res = await fetch(`${e.fs}/${path}`, { headers: { authorization: `Bearer ${token}` } });
  if (res.status === 404) return null;
  const body = await j(res);
  return Object.fromEntries(Object.entries(body.fields ?? {}).map(([k, v]) => [k, dec(v)]));
}

/** List a collection (or subcollection) fully, paging. Returns [{id, data}]. */
export async function listDocs(env, collectionPath, token, pageSize = 300) {
  const e = endpoints(env);
  const out = [];
  let pageToken = '';
  do {
    const url = `${e.fs}/${collectionPath}?pageSize=${pageSize}${pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : ''}`;
    const body = await j(await fetch(url, { headers: { authorization: `Bearer ${token}` } }));
    for (const d of body.documents ?? []) {
      out.push({ id: d.name.split('/').pop(), name: d.name, data: Object.fromEntries(Object.entries(d.fields ?? {}).map(([k, v]) => [k, dec(v)])) });
    }
    pageToken = body.nextPageToken ?? '';
  } while (pageToken);
  return out;
}

export async function deleteDocRest(env, path, token) {
  const e = endpoints(env);
  const res = await fetch(`${e.fs}/${path}`, { method: 'DELETE', headers: { authorization: `Bearer ${token}` } });
  if (!res.ok && res.status !== 404) await j(res);
}

// ── Emulator-only admin ────────────────────────────────────────────────────
export function ownerToken(env) {
  if (!env.hosts || !env.projectId.startsWith('demo-')) throw new Error('owner token is emulator-only');
  return 'owner';
}

export async function emulatorUp(env) {
  try {
    const r = await fetch(`http://${env.hosts.firestore}/`, { signal: AbortSignal.timeout(1500) });
    const a = await fetch(`http://${env.hosts.auth}/`, { signal: AbortSignal.timeout(1500) });
    return r.ok && a.ok;
  } catch { return false; }
}

export async function wipeEmulator(env) {
  const e = endpoints(env);
  ownerToken(env);
  await fetch(e.fsEmuAdmin, { method: 'DELETE' });
  await fetch(e.authEmuAdmin, { method: 'DELETE' });
}

/** structuredQuery on a top-level collection with equality filters. Returns [{name, data}]. */
export async function runQuery(env, collectionId, equals, token, max = 1000) {
  const e = endpoints(env);
  const filters = Object.entries(equals).map(([field, value]) => ({ fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: enc(value) } }));
  const body = await j(await fetch(`${e.fs}:runQuery`, {
    method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    body: JSON.stringify({ structuredQuery: { from: [{ collectionId }], where: filters.length === 1 ? filters[0] : { compositeFilter: { op: 'AND', filters } }, limit: max } }),
  }));
  return body.filter((r) => r.document).map((r) => ({ name: r.document.name, data: Object.fromEntries(Object.entries(r.document.fields ?? {}).map(([k, v]) => [k, dec(v)])) }));
}
