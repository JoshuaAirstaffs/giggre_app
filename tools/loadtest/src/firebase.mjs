// Firebase client SDK per virtual user. Each VU gets its own FirebaseApp so it
// has its own auth state and its own connection, exactly like a phone. All
// traffic goes through the normal client APIs, so Firestore security rules
// apply to every operation (no Admin SDK anywhere in the simulator).
import { initializeApp, deleteApp } from 'firebase/app';
import { getAuth, connectAuthEmulator, inMemoryPersistence, setPersistence } from 'firebase/auth';
import {
  initializeFirestore, connectFirestoreEmulator, terminate,
  getDoc, getDocs, onSnapshot, setDoc, updateDoc, addDoc, deleteDoc, writeBatch, runTransaction,
} from 'firebase/firestore';
import { getFunctions, connectFunctionsEmulator, httpsCallable } from 'firebase/functions';

let appSeq = 0;

export function webConfig(env) {
  if (env.projectId.startsWith('demo-')) {
    // Demo projects never touch real Google services; the key is a placeholder.
    return { apiKey: 'demo-key', authDomain: `${env.projectId}.firebaseapp.com`, projectId: env.projectId, appId: '1:0:web:loadtest' };
  }
  const c = env.webConfig ?? {};
  if (!c.apiKey || !c.appId) throw new Error(`environments.${env.projectId}: webConfig.apiKey/appId missing`);
  return { apiKey: c.apiKey, authDomain: c.authDomain, projectId: c.projectId, appId: c.appId };
}

export async function createClient(env, label) {
  const app = initializeApp(webConfig(env), `lt-${label}-${++appSeq}`);
  const auth = getAuth(app);
  await setPersistence(auth, inMemoryPersistence);
  const db = initializeFirestore(app, {}); // memory cache only
  const fns = getFunctions(app, env.functionsRegion);
  if (env.hosts) {
    connectAuthEmulator(auth, `http://${env.hosts.auth}`, { disableWarnings: true });
    const [h, p] = env.hosts.firestore.split(':');
    connectFirestoreEmulator(db, h, Number(p));
    const [fh, fp] = env.hosts.functions.split(':');
    connectFunctionsEmulator(fns, fh, Number(fp));
  }
  return { app, auth, db, fns };
}

export async function destroyClient(c) {
  try { await terminate(c.db); } catch { /* ignore */ }
  try { await deleteApp(c.app); } catch { /* ignore */ }
}

/** Business-rule "no" (gig taken, already applied...) — counted separately
 *  from system failures. */
export class Rejection extends Error {
  constructor(code, msg) { super(msg ?? code); this.expectedCode = code; }
}

// ── Counted wrappers. `vu` = { m: Metrics, limiter, listeners: [] } ──────────

export async function cGet(vu, ref, op, label = op) {
  await vu.limiter.take();
  const snap = await vu.m.time(op, () => getDoc(ref));
  vu.m.reads(1, label);
  return snap;
}

export async function cQuery(vu, q, op, label = op) {
  await vu.limiter.take();
  const snap = await vu.m.time(op, () => getDocs(q));
  vu.m.reads(snap.size, label);
  return snap;
}

/** Starts a listener. Resolves with the first server snapshot (its latency is
 *  recorded under `op`). Later document changes are counted as reads. */
export function cListen(vu, target, op, label = op, onChange) {
  return new Promise((resolve) => {
    const t0 = performance.now();
    let first = true;
    const unsub = onSnapshot(
      target,
      { includeMetadataChanges: false },
      (snap) => {
        const isDoc = typeof snap.docChanges !== 'function';
        const changes = isDoc ? 1 : snap.docChanges().length;
        if (first) {
          first = false;
          vu.m.record(op, performance.now() - t0, null);
          vu.m.reads(isDoc ? 1 : snap.size, label);
          resolve(snap);
        } else if (!snap.metadata.hasPendingWrites) {
          vu.m.listenerReads(changes, label);
        }
        onChange?.(snap, first);
      },
      (err) => {
        if (first) { first = false; vu.m.record(op, performance.now() - t0, err); resolve(null); }
        else vu.m.record(`${op}.stream`, 0, err);
      },
    );
    vu.listeners.push(unsub);
  });
}

export async function cSet(vu, ref, data, op, opts) {
  await vu.limiter.take();
  await vu.m.time(op, () => (opts ? setDoc(ref, data, opts) : setDoc(ref, data)));
  vu.m.writes(1);
}

export async function cUpdate(vu, ref, data, op) {
  await vu.limiter.take();
  await vu.m.time(op, () => updateDoc(ref, data));
  vu.m.writes(1);
}

export async function cAdd(vu, col, data, op) {
  await vu.limiter.take();
  const ref = await vu.m.time(op, () => addDoc(col, data));
  vu.m.writes(1);
  return ref;
}

export async function cDelete(vu, ref, op) {
  await vu.limiter.take();
  await vu.m.time(op, () => deleteDoc(ref));
  vu.m.deletes(1);
}

export async function cBatch(vu, db, build, op) {
  await vu.limiter.take();
  const b = writeBatch(db);
  const n = build(b);
  await vu.m.time(op, () => b.commit());
  vu.m.writes(n);
}

/** Transaction with attempt counting. `fn(tx, count)` must call
 *  count.read()/count.write() for each tx.get/tx.set|update. */
export async function cTxn(vu, db, fn, op, mapErr) {
  await vu.limiter.take();
  let attempts = 0, reads = 0, writes = 0;
  const count = { read: () => reads++, write: () => writes++ };
  try {
    return await vu.m.time(op, async () => {
      try { return await runTransaction(db, (tx) => { attempts++; reads = 0; writes = 0; return fn(tx, count); }); }
      catch (e) { throw mapErr?.(e) ?? e; }
    });
  } finally {
    vu.m.reads(reads * Math.max(1, attempts), `${op}.txn`);
    vu.m.writes(writes);
    if (attempts > 1) vu.m.sample(`${op}.retries`, attempts - 1);
  }
}

export async function cCall(vu, fns, name, payload, op = `callable.${name}`) {
  await vu.limiter.take();
  vu.m.callable();
  return vu.m.time(op, () => httpsCallable(fns, name)(payload));
}
