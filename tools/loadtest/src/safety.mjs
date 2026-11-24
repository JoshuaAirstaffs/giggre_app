// Rate limiting, ramp-up and automatic stop conditions.
import { existsSync } from 'node:fs';
import { STOP_FILE } from './state.mjs';

/** Token bucket shared by every VU in a process. The rate ramps linearly from
 *  10% to 100% over `rampUpSec`, so load never starts as a cliff. */
export class Limiter {
  constructor(maxPerSec, rampUpSec) {
    this.max = maxPerSec; this.ramp = rampUpSec * 1000; this.t0 = Date.now();
    this.tokens = 1; this.last = Date.now(); this.waiters = 0; this.stopped = false;
  }
  rate() { const f = this.ramp > 0 ? Math.min(1, 0.1 + 0.9 * ((Date.now() - this.t0) / this.ramp)) : 1; return this.max * f; }
  async take() {
    for (;;) {
      if (this.stopped) throw Object.assign(new Error('load test stopping'), { code: 'lt-stopped' });
      const now = Date.now();
      const r = this.rate();
      this.tokens = Math.min(Math.max(1, r), this.tokens + ((now - this.last) / 1000) * r);
      this.last = now;
      if (this.tokens >= 1) { this.tokens -= 1; return; }
      await new Promise((res) => setTimeout(res, Math.ceil(((1 - this.tokens) / r) * 1000)));
    }
  }
}

/** Fixed-window limiter (registrations per minute). */
export class PerMinute {
  constructor(n) { this.n = n; this.win = 0; this.count = 0; }
  async take() {
    for (;;) {
      const w = Math.floor(Date.now() / 60000);
      if (w !== this.win) { this.win = w; this.count = 0; }
      if (this.count < this.n) { this.count++; return; }
      await new Promise((r) => setTimeout(r, 1000));
    }
  }
}

export function stopRequested() { return existsSync(STOP_FILE); }

/**
 * Evaluates hard stop conditions against merged live metrics.
 * Returns a reason string, or null to keep going.
 */
export function checkAbort({ live, plan, safety, elapsedMin, measuredCostUsd }) {
  if (stopRequested()) return 'Emergency stop requested (state/STOP present)';
  if (elapsedMin > plan.limits.maxRunMinutes) return `Run exceeded ${plan.limits.maxRunMinutes} min`;
  if (live.counters.reads > plan.limits.maxReads) return `Reads ${live.counters.reads} exceeded the stage limit ${plan.limits.maxReads}`;
  if (live.counters.writes > plan.limits.maxWrites) return `Writes ${live.counters.writes} exceeded the stage limit ${plan.limits.maxWrites}`;
  if (plan.env.billable && plan.cost.maxUsd > 0 && measuredCostUsd > plan.cost.maxUsd) {
    return `Measured usage priced at list rates ($${measuredCostUsd.toFixed(2)}) passed the approved ceiling $${plan.cost.maxUsd.toFixed(2)} (estimate, not billing)`;
  }
  if (live.window.n >= safety.minOpsBeforeErrorAbort && live.window.rate > safety.abortOnUnexpectedErrorRate) {
    return `Unexpected error rate ${(live.window.rate * 100).toFixed(1)}% over the last ${safety.errorRateWindowSec}s exceeds ${(safety.abortOnUnexpectedErrorRate * 100).toFixed(1)}%`;
  }
  const latencyAbort = !plan.env.hosts || safety.latencyAbortOnEmulator !== false;
  for (const [op, l] of latencyAbort ? Object.entries(live.p95 ?? {}) : []) {
    if (l != null && l > safety.abortOnP95LatencyMs && (live.opCounts?.[op] ?? 0) >= 50) return `p95 latency of ${op} is ${Math.round(l)} ms (> ${safety.abortOnP95LatencyMs} ms)`;
  }
  return null;
}
