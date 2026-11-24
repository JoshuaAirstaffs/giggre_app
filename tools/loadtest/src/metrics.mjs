// Metric collection. Each generator process owns a Metrics instance and sends
// serialisable snapshots to the controller, which merges them. Everything here
// is measured; nothing is estimated.
//
// Latency = wall time from just before the SDK call to the promise settling
// (or, for listeners, to the first snapshot from the SERVER — fromCache false).
// Reads are counted the way Firestore bills them: docs returned, minimum 1 per
// query/listen, and 1 per document change delivered to a listener afterwards.

const RESERVOIR = 5000;

class Samples {
  constructor() { this.n = 0; this.xs = []; this.sum = 0; this.max = 0; }
  add(v) {
    this.n++; this.sum += v; if (v > this.max) this.max = v;
    if (this.xs.length < RESERVOIR) this.xs.push(v);
    else { const j = Math.floor(Math.random() * this.n); if (j < RESERVOIR) this.xs[j] = v; }
  }
  toJSON() { return { n: this.n, sum: this.sum, max: this.max, xs: this.xs }; }
  static merge(list) {
    const out = { n: 0, sum: 0, max: 0, xs: [] };
    for (const s of list) {
      out.n += s.n; out.sum += s.sum; out.max = Math.max(out.max, s.max);
      // Weighted subsample so each process contributes proportionally.
      const keep = Math.min(s.xs.length, Math.ceil(RESERVOIR * (s.n / Math.max(1, list.reduce((a, b) => a + b.n, 0)))));
      out.xs.push(...s.xs.slice(0, keep));
    }
    return out;
  }
}

export function percentiles(samples) {
  const xs = [...samples.xs].sort((a, b) => a - b);
  const q = (p) => (xs.length ? xs[Math.min(xs.length - 1, Math.floor(p * xs.length))] : null);
  return { count: samples.n, mean: samples.n ? samples.sum / samples.n : null, p50: q(0.5), p95: q(0.95), p99: q(0.99), max: samples.n ? samples.max : null };
}

/** Error codes that are the app's business rules saying no, not failures. */
export const EXPECTED_REJECTIONS = new Set([
  'gig-unavailable', 'already-applied', 'slot-full', 'already-assigned', 'not-editable',
  'duplicate-account', 'invalid-credentials', 'invalid-input', 'request-pending',
]);

export class Metrics {
  constructor() {
    this.ops = {};            // name -> { ok, expected, unexpected, errors: {code: n}, lat: Samples }
    this.counters = { reads: 0, writes: 0, deletes: 0, listenerEvents: 0, callables: 0 };
    this.readsBy = {};        // label -> reads
    this.timeline = {};       // minute -> { ops, errors, reads, writes, active, started }
    this.checks = {};         // correctness checks name -> { passed, failed, details: [] }
    this.window = [];         // recent [t, ok|err] for live abort checks
    this.t0 = Date.now();
    this.active = 0; this.peakActive = 0; this.queued = 0; this.sessions = { started: 0, completed: 0, failed: 0 };
  }

  minute() { const m = Math.floor((Date.now() - this.t0) / 60000); return (this.timeline[m] ??= { ops: 0, errors: 0, reads: 0, writes: 0, active: 0, started: 0 }); }

  op(name) { return (this.ops[name] ??= { ok: 0, expected: 0, unexpected: 0, errors: {}, lat: new Samples() }); }

  /** Time an async operation. `classify(err)` may return an expected-rejection code. */
  async time(name, fn) {
    const t = performance.now();
    try {
      const v = await fn();
      this.record(name, performance.now() - t, null);
      return v;
    } catch (e) {
      this.record(name, performance.now() - t, e);
      throw e;
    }
  }

  record(name, ms, err) {
    const o = this.op(name), tl = this.minute();
    tl.ops++;
    if (!err) { o.ok++; o.lat.add(ms); this.window.push([Date.now(), 0]); return; }
    const code = err.expectedCode ?? err.code ?? err.name ?? 'unknown';
    o.errors[code] = (o.errors[code] ?? 0) + 1;
    const expectedDenial = name === 'probe' && err.code === 'permission-denied'; // security probes must be denied
    if (expectedDenial || (err.expectedCode && EXPECTED_REJECTIONS.has(err.expectedCode))) { o.expected++; o.lat.add(ms); this.window.push([Date.now(), 0]); }
    else { o.unexpected++; tl.errors++; this.window.push([Date.now(), 1]); }
  }

  /** A sample that isn't an operation (e.g. chat delivery latency). */
  sample(name, ms) { this.op(name).ok++; this.op(name).lat.add(ms); }

  reads(n, label) { const k = Math.max(1, n); this.counters.reads += k; this.minute().reads += k; this.readsBy[label] = (this.readsBy[label] ?? 0) + k; }
  listenerReads(n, label) { if (n <= 0) return; this.counters.reads += n; this.counters.listenerEvents += n; this.minute().reads += n; this.readsBy[label] = (this.readsBy[label] ?? 0) + n; }
  writes(n = 1) { this.counters.writes += n; this.minute().writes += n; }
  deletes(n = 1) { this.counters.deletes += n; }
  callable() { this.counters.callables++; }

  check(name, passed, detail) {
    const c = (this.checks[name] ??= { passed: 0, failed: 0, details: [] });
    if (passed) c.passed++; else { c.failed++; if (c.details.length < 20) c.details.push(detail); }
  }

  sessionStart() { this.active++; this.peakActive = Math.max(this.peakActive, this.active); this.sessions.started++; this.minute().started++; }
  sessionEnd(ok) { this.active--; ok ? this.sessions.completed++ : this.sessions.failed++; }
  noteActive() { const tl = this.minute(); tl.active = Math.max(tl.active, this.active); }

  /** Unexpected error rate over the last `sec` seconds. */
  windowErrorRate(sec) {
    const cut = Date.now() - sec * 1000;
    this.window = this.window.filter(([t]) => t >= cut);
    const errs = this.window.reduce((s, [, e]) => s + e, 0);
    return { n: this.window.length, rate: this.window.length ? errs / this.window.length : 0 };
  }

  toJSON() {
    return {
      ops: Object.fromEntries(Object.entries(this.ops).map(([k, o]) => [k, { ...o, lat: o.lat.toJSON() }])),
      counters: this.counters, readsBy: this.readsBy, timeline: this.timeline, checks: this.checks,
      peakActive: this.peakActive, sessions: this.sessions, queued: this.queued, t0: this.t0,
    };
  }
}

/** Merge snapshots from several generator processes. */
export function mergeSnapshots(snaps) {
  const out = { ops: {}, counters: { reads: 0, writes: 0, deletes: 0, listenerEvents: 0, callables: 0 }, readsBy: {}, timeline: {}, checks: {}, peakActive: 0, sessions: { started: 0, completed: 0, failed: 0 }, queued: 0 };
  const lat = {};
  for (const s of snaps) {
    for (const [k, o] of Object.entries(s.ops)) {
      const d = (out.ops[k] ??= { ok: 0, expected: 0, unexpected: 0, errors: {} });
      d.ok += o.ok; d.expected += o.expected; d.unexpected += o.unexpected;
      for (const [c, n] of Object.entries(o.errors)) d.errors[c] = (d.errors[c] ?? 0) + n;
      (lat[k] ??= []).push(o.lat);
    }
    for (const [k, v] of Object.entries(s.counters)) out.counters[k] += v;
    for (const [k, v] of Object.entries(s.readsBy)) out.readsBy[k] = (out.readsBy[k] ?? 0) + v;
    for (const [m, t] of Object.entries(s.timeline)) {
      const d = (out.timeline[m] ??= { ops: 0, errors: 0, reads: 0, writes: 0, active: 0, started: 0 });
      for (const k of Object.keys(d)) d[k] += t[k];
    }
    for (const [k, c] of Object.entries(s.checks)) {
      const d = (out.checks[k] ??= { passed: 0, failed: 0, details: [] });
      d.passed += c.passed; d.failed += c.failed; d.details.push(...c.details.slice(0, 20 - d.details.length));
    }
    out.peakActive += s.peakActive; // upper bound across processes
    for (const k of Object.keys(out.sessions)) out.sessions[k] += s.sessions[k];
    out.queued += s.queued;
  }
  for (const [k, list] of Object.entries(lat)) out.ops[k].latency = percentiles(Samples.merge(list));
  return out;
}
