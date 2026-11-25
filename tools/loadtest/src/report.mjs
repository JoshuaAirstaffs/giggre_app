// Markdown reports. Every number is labelled: [measured], [estimate],
// [assumption] or "not tested". A stage report is written after every
// completed or aborted run; the comparison report covers all completed stages.
import { writeFileSync, readFileSync, existsSync, mkdirSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { REPORTS_DIR } from './config.mjs';
import { priceMeasured } from './costModel.mjs';

const f0 = (n) => (n == null || Number.isNaN(n) ? '—' : Math.round(n).toLocaleString('en-US'));
const ms = (n) => (n == null ? '—' : `${Math.round(n)} ms`);
const pct = (n) => `${(n * 100).toFixed(2)}%`;
const usd = (n) => `$${n.toFixed(2)}`;
const STAGE_USERS = { 1: 1000, 2: 5000, 3: 10000, 4: 15000 };

function latRow(name, o) {
  if (!o) return `| ${name} | 0 | — | — | — | — | — | not exercised |`;
  const l = o.latency ?? {};
  return `| ${name} | ${f0(o.ok + o.expected + o.unexpected)} | ${ms(l.p50)} | ${ms(l.p95)} | ${ms(l.p99)} | ${ms(l.max)} | ${f0(o.expected)} | ${f0(o.unexpected)}${Object.keys(o.errors ?? {}).length ? ` (${Object.entries(o.errors).map(([k, v]) => `${k}:${v}`).join(', ')})` : ''} |`;
}

function opTable(merged, prefixes) {
  const names = Object.keys(merged.ops).filter((k) => prefixes.some((p) => k === p || k.startsWith(`${p}.`))).sort();
  if (!names.length) return '_Not exercised in this run._\n';
  return ['| Operation | Count | p50 | p95 | p99 | max | Expected rejections | Unexpected errors |', '|---|---:|---:|---:|---:|---:|---:|---|',
    ...names.map((n) => latRow(n, merged.ops[n]))].join('\n') + '\n';
}

function xychart(title, xs, series) {
  if (xs.length < 2) return '';
  const step = Math.max(1, Math.ceil(xs.length / 40));
  const pick = (arr) => arr.filter((_, i) => i % step === 0);
  return ['```mermaid', 'xychart-beta', `  title "${title}"`, `  x-axis "minute" [${pick(xs).join(', ')}]`,
    ...series.map((s) => `  line [${pick(s).map((v) => Math.round(v)).join(', ')}]`), '```', ''].join('\n');
}

const nextPrompt = (stage, verdict, stageIds) => {
  const next = stageIds.find((s) => s > stage);
  if (!next) return `The ${f0(STAGE_USERS[stage] ?? 0)}-user load test has completed.\n\nOverall Result: ${verdict}\n\nThis was the final stage. Testing stops here.`;
  return `The ${f0(STAGE_USERS[stage])}-user load test has completed.\n\nOverall Result: ${verdict}\n\nWould you like to proceed with the ${f0(STAGE_USERS[next])}-user load test?\n\n1. YES — Proceed to the next stage\n2. NO — Stop testing\n3. OPTIMIZE — Review performance problems first\n4. RETEST — Repeat the current stage`;
};
export { nextPrompt };

export function writeStageReport({ plan, merged, evaluation, consistency, resources, run, cfg, setup, stageIds, auditPath }) {
  mkdirSync(REPORTS_DIR, { recursive: true });
  const fn = `stage-${plan.stage}-${plan.users}-users-${run.runId}.md`;
  const file = path.join(REPORTS_DIR, fn);
  const c = merged.counters;
  const durMin = (Date.parse(run.endedAt) - Date.parse(run.startedAt)) / 60000;
  const measuredUsd = priceMeasured(cfg.pricing, { reads: c.reads, writes: c.writes, deletes: c.deletes });
  const u = plan.usage;
  const totalOps = evaluation.errors.total;
  const okOps = totalOps - evaluation.errors.unexpected;
  const minutes = Object.keys(merged.timeline).map(Number).sort((a, b) => a - b);
  const tl = (k) => minutes.map((mm) => merged.timeline[mm][k]);
  const bott = bottlenecks(merged, plan, evaluation);
  const emu = !plan.env.billable && plan.env.hosts;

  const md = `# Giggre load test — Stage ${plan.stage}: ${f0(plan.users)} users

Run \`${run.runId}\` · ${run.startedAt} → ${run.endedAt} · environment **${plan.envName}** (\`${plan.env.projectId}\`)

Legend: **[measured]** observed during this run · **[estimate]** computed from the cost model or list prices · **[assumption]** configured workload input · **not tested** = no data.

## 1. Executive summary

${run.result === 'ABORTED' ? `**The run was aborted:** ${run.abortReason}\n\n` : ''}${evaluation.findings.length ? evaluation.findings.map((x) => `- ${x}`).join('\n') : '- All thresholds met.'}
${emu ? `\n> **Emulator caveat.** This stage ran against the local Firebase Emulator Suite. It validates correctness, security rules, read/write volumes and contention behaviour. Its latencies reflect a single local Java process, **not** Cloud Firestore at scale, and the emulator does not enforce composite-index requirements or production quotas. Treat latency verdicts as indicative only.\n` : ''}
## 2. Overall result

**${run.result === 'ABORTED' ? 'FAIL (ABORTED)' : evaluation.verdict}**

## 3. Test environment

| Item | Value |
|---|---|
| Environment | ${plan.envName} (${plan.env.projectId}) ${plan.env.billable ? '— billable' : '— not billable'} |
| Cloud Functions | ${plan.withFunctions ? 'emulated (trigger load measured)' : 'not running (trigger load estimated only)'} |
| Generator processes | ${plan.generatorProcesses} on ${resources[0]?.cores ?? '?'} CPU cores |
| Generator peak CPU / event-loop p99 / RSS | ${Math.round(evaluation.generator.maxCpuPct)}% / ${Math.round(evaluation.generator.maxLoopP99Ms)} ms / ${f0(Math.max(0, ...resources.flatMap((r) => r.rssMb ?? [])))} MB [measured] |
| Emulator JVM CPU p90 / max / RSS | ${evaluation.emulator?.cpuP90 != null ? `${Math.round(evaluation.emulator.cpuP90)}% / ${Math.round(evaluation.emulator.cpuMax)}% / ${f0(evaluation.emulator.rssMaxMb)} MB [measured]${evaluation.emulator.saturated ? ' — **busy**' : ''}` : 'not sampled'} |
| Firebase JS SDK | client SDK, one app instance per virtual user, rules enforced |

## 4. Test configuration

| Setting | Value |
|---|---|
| Plan hash | \`${plan.hash.slice(0, 16)}\` |
| Simulated day compressed into | ${plan.compressedDurationMin} min (${plan.timeScale}) |
| Max concurrency / ops per second / registrations per min | ${plan.maxConcurrency} / ${plan.maxOpsPerSec} / ${plan.maxRegistrationsPerMin} |
| Worker / host split | ${cfg.workload.roles.worker * 100}% / ${cfg.workload.roles.host * 100}% [assumption] |
| Primary intents | ${Object.entries(cfg.workload.primaryIntent).filter(([k]) => !k.startsWith('$')).map(([k, v]) => `${k} ${v * 100}%`).join(', ')} [assumption] |
| Seed data | ${f0(setup?.gigs)} open gigs, ${f0(setup?.rooms)} chat rooms, ${f0(setup?.counters?.authAccounts)} returning accounts (setup writes ${f0(setup?.counters?.writes)}, failures ${f0(setup?.counters?.failures)}) |

## 5. Unique simulated users

${f0(plan.users)} planned (${f0(plan.roleCount.worker)} workers, ${f0(plan.roleCount.host)} hosts, ${f0(plan.newUsers)} registering during the day) · ${f0(plan.sessionsTotal)} sessions planned · ${f0(merged.sessions.started)} started, ${f0(merged.sessions.completed)} completed, ${f0(merged.sessions.failed)} failed [measured]

## 6. Peak concurrent users

${f0(merged.peakActive)} concurrent sessions [measured] (plan expected ${f0(plan.expectedPeakConcurrency)}, cap ${plan.maxConcurrency}; sessions that waited for a free slot: ${f0(merged.queued)})

## 7. Test duration

${durMin.toFixed(1)} min real time (planned ${plan.compressedDurationMin} min)

${xychart('Active sessions and session starts per minute', minutes, [tl('active'), tl('started')])}
## 8–10. Operations

| | Count |
|---|---:|
| Total operations | ${f0(totalOps)} |
| Successful (incl. expected business-rule rejections) | ${f0(okOps)} |
| Expected rejections (gig taken, already applied, …) | ${f0(evaluation.errors.expected)} |
| Unexpected failures | ${f0(evaluation.errors.unexpected)} (${pct(evaluation.errors.rate)}) |

${xychart('Operations and unexpected errors per minute', minutes, [tl('ops'), tl('errors')])}
## 11. Authentication performance

${opTable(merged, ['auth', 'register'])}
## 12. Gig browsing performance (list)

The app has one global listener for all open gigs (\`open_gigs where status in [open, partially_filled]\`, no limit). \`browse.list\` is the time to its first server snapshot. Average gigs delivered per session open: ${f0((merged.readsBy.openGigsGlobal ?? 0) / Math.max(1, merged.sessions.started))} reads [measured].

${opTable(merged, ['browse', 'gig.detail', 'open'])}
## 13. Google Maps performance

- **Backend geographic queries:** none exist. The map uses the same global open-gigs listener as the list and filters/clusters on the device. [measured from code]
- Client-side clustering cost for the loaded gig set, timed in Node as an indicator only (device numbers need the integration test): ${opTable(merged, ['map'])}
- **Google Maps Platform requests sent by this test: 0.** Map SDK rendering, marker bitmaps, camera movement and frame times are **not tested** here; run \`templates/map_render_perf_test.dart\` on a device (see the skill's reference/maps-device-testing.md).
- Real-world billable Maps usage comes from Places Autocomplete/Details on the three post-gig screens (no session token). Estimated for this day's ${f0(Object.entries(plan.intents).filter(([k]) => k.endsWith(':post')).reduce((s, [, v]) => s + v, 0))} post sessions at ~4 autocomplete + 1 details each: ${usd((Object.entries(plan.intents).filter(([k]) => k.endsWith(':post')).reduce((s, [, v]) => s + v, 0)) * (4 * cfg.pricing.maps.placesAutocompletePer1000 + cfg.pricing.maps.placeDetailsPer1000) / 1000)} [estimate, assumption on keystroke bursts].

## 14. Gig posting performance

${opTable(merged, ['gig.post', 'gig.edit', 'gig.cancel'])}
Visibility of a new gig to other online workers (post → appears in another session's listener): ${merged.ops['gig.propagation']?.latency ? `p50 ${ms(merged.ops['gig.propagation'].latency.p50)}, p95 ${ms(merged.ops['gig.propagation'].latency.p95)} over ${f0(merged.ops['gig.propagation'].latency.count)} gigs` : 'not observed'} [measured]

## 15. Gig application performance

${opTable(merged, ['gig.apply', 'gig.accept', 'gig.decline', 'gig.statusWatch', 'lifecycle', 'race'])}
## 16. Chat performance

${opTable(merged, ['chat'])}
## 17. Firestore reads and writes

| | Measured (client SDK) | Plan estimate |
|---|---:|---:|
| Reads | ${f0(c.reads)} | ${f0(u.client.reads)} |
| …of which listener updates after first snapshot | ${f0(c.listenerEvents)} | |
| Writes | ${f0(c.writes)} | ${f0(u.client.writes)} |
| Deletes | ${f0(c.deletes)} | |
| Callable invocations | ${f0(c.callables)} | |
| Cloud Functions reads (server side) | not measured | ${f0(u.functions.reads)} [estimate] |

Top read sources [measured]:

| Source | Reads | Share |
|---|---:|---:|
${Object.entries(merged.readsBy).sort((a, b) => b[1] - a[1]).slice(0, 12).map(([k, v]) => `| ${k} | ${f0(v)} | ${pct(v / Math.max(1, c.reads))} |`).join('\n')}

${xychart('Reads and writes per minute', minutes, [tl('reads'), tl('writes')])}
## 18. Estimated Firebase costs

| | Amount |
|---|---:|
| Measured client usage at list prices | ${usd(measuredUsd)} [estimate] |
| Plan estimate incl. Cloud Functions | ${usd(plan.cost.equivalentUsd)} [estimate] |
| Actually billed | ${plan.env.billable ? 'see Cloud Billing (not readable from here)' : '$0.00 (emulator)'} |
| Extrapolated to one real day at this user count | ${usd(measuredUsd + u.functions.reads / 1e5 * cfg.pricing.firestore.readsPer100k)} / day, ~${usd((measuredUsd + u.functions.reads / 1e5 * cfg.pricing.firestore.readsPer100k) * 30)} / month [estimate] |

Prices from config/pricing.json (verified on: ${cfg.pricing.verifiedOn}).

## 19. Estimated Google Maps costs

This test sent **0** Maps Platform requests ($0.00). Mobile Maps SDK map loads are not billed per load; the web build (\`google_maps_flutter_web\`) is. Places usage estimate: see §13.

## 20. Bottlenecks and errors

${bott.map((b) => `- ${b}`).join('\n') || '- None identified.'}

Top unexpected error codes [measured]:

${Object.entries(merged.ops).filter(([op, o]) => op !== 'probe' && o.unexpected > 0).flatMap(([op, o]) => Object.entries(o.errors ?? {}).map(([code, n]) => [op, code, n])).sort((a, b) => b[2] - a[2]).slice(0, 15).map(([op, code, n]) => `- \`${op}\` → \`${code}\` × ${f0(n)}`).join('\n') || '- none'}

## 21. Data consistency findings

| Check | Passed | Failed | Verdict |
|---|---:|---:|---|
${evaluation.checks.map((r) => `| ${r.name} | ${f0(r.passed)} | ${f0(r.failed)} | ${r.status} |`).join('\n') || '| (no checks ran) | | | |'}

${evaluation.checks.filter((r) => r.failed && r.details?.length).map((r) => `<details><summary>${r.name} — examples</summary>\n\n\`\`\`json\n${JSON.stringify(r.details.slice(0, 5), null, 2)}\n\`\`\`\n</details>`).join('\n\n')}

## 22. Recommended optimizations

${recommendations(merged, evaluation, plan).map((r) => `- ${r}`).join('\n')}

These are proposals only. No application code was changed.

## 23. Approval status for the next stage

**Not approved.** The next stage needs a new, stage-specific approval typed by a person (\`node cli.mjs approve --stage ${plan.stage + 1}\`). This report does not authorise anything.

\`\`\`text
${nextPrompt(plan.stage, run.result === 'ABORTED' ? 'FAIL' : evaluation.verdict, stageIds)}
\`\`\`

---
Latency thresholds [configurable, provisional]:

| Operation | p95 | warn | fail | Verdict |
|---|---:|---:|---:|---|
${evaluation.latency.map((l) => `| ${l.op} | ${ms(l.p95)} | ${l.warn} | ${l.fail} | ${l.status} |`).join('\n')}

Architecture audit used for this model: \`${auditPath}\`.
`;
  writeFileSync(file, md);
  return file;
}

function bottlenecks(merged, plan, ev) {
  const out = [];
  const c = merged.counters, rb = merged.readsBy;
  const top = Object.entries(rb).sort((a, b) => b[1] - a[1])[0];
  if (top && top[1] / Math.max(1, c.reads) > 0.3) out.push(`\`${top[0]}\` accounts for ${pct(top[1] / c.reads)} of all reads.`);
  if ((rb.onlineUsersGlobal ?? 0) > 0) out.push(`Global \`users where isOnline == true\` listener: ${f0(rb.onlineUsersGlobal)} reads. Every online/offline/location/FCM write by any worker is pushed to every open session, so this grows with concurrency².`);
  if ((rb.openGigsGlobal ?? 0) > 0) out.push(`Global open-gigs listener: ${f0(rb.openGigsGlobal)} reads (${f0(rb.openGigsGlobal / Math.max(1, merged.sessions.started))} per session). Grows with total open gigs × sessions, not with what a worker can reach.`);
  if ((rb.quickGigScanGlobal ?? 0) > 0) out.push(`Quick-gig dispatch: ${f0(rb.quickGigScanGlobal)} reads scanning for an eligible worker, re-run on every dispatch attempt by every searching host at once (audit §8 risk 8).`);
  const retries = merged.ops['gig.accept.retries'] ?? merged.ops['race.select.retries'];
  if (retries) out.push(`Transaction retries on gig selection: ${f0(retries.ok)} retried transactions.`);
  if (merged.queued > 0) out.push(`${f0(merged.queued)} session starts waited for the concurrency cap (${plan.maxConcurrency}); real users would not wait — raise the cap or add generator processes to test true peak.`);
  if (ev.generator.saturated) out.push('Load generator saturation (see §3) — distribute across more processes/machines before trusting latency.');
  return out;
}

function recommendations(merged, ev, plan) {
  const r = [];
  const rb = merged.readsBy;
  if ((rb.openGigsGlobal ?? 0) > 0) r.push('Bound the worker gig listener geographically (geohash range on a `geohash` field written at post time, e.g. 5-char cells around the worker) and add `limit()`; keep the 10 km filter client-side for exactness.');
  if ((rb.onlineUsersGlobal ?? 0) > 0) r.push('Replace the host dashboard\'s global `users where isOnline == true` listeners with a geohash-bounded, limited query (or a server-maintained "online workers nearby" count), and stop mounting the Host shell\'s listeners while in Worker mode.');
  r.push('`onOpenGigPosted` reads every `availableForGigs` user for each new open gig; query by geohash range instead so cost stays proportional to nearby workers.');
  if ((rb.quickGigScanGlobal ?? 0) > 0) r.push('Bound quick-gig dispatch\'s worker search by geohash range too (it is the same unbounded-scan shape as the open-gigs/online-users listeners, just run from the host\'s device per dispatch attempt instead of as a standing listener).');
  if (ev.checks.some((c) => c.name.startsWith('race.single') && c.failed)) r.push('Make single-slot selection a transaction that requires `status == "open"` and no `workerId` (same pattern as the multi-slot path), so a double tap or a second device cannot reassign.');
  if (ev.checks.some((c) => c.name === 'security.editForeignOpenGig' && c.failed)) r.push('Tighten the `open_gigs` update rule: while `status == "open"`, a non-host should only be able to change `applicants` (affectedKeys().hasOnly([\'applicants\'])).');
  r.push('Write `isOnline` and `location` less often (or to a separate small doc) — each write to `users/{uid}` also triggers ~5 Cloud Functions.');
  r.push('Cap per-room unread listeners (one `limit(1)` listener per chat room, duplicated by both shells) with a per-user unread counter maintained by the existing `onChatMessageCreated` trigger.');
  return r;
}

/** Cross-stage comparison from the raw JSON of each stage's latest completed run. */
export function writeComparisonReport(state, cfg) {
  const rows = [];
  for (const [stage, st] of Object.entries(state.stages).filter(([k]) => /^\d+$/.test(k)).sort((a, b) => a[0] - b[0])) {
    const run = [...(st.runs ?? [])].reverse().find((x) => x.rawPath && existsSync(x.rawPath));
    if (!run) continue;
    const raw = JSON.parse(readFileSync(run.rawPath, 'utf8'));
    const m = raw.merged, c = m.counters;
    const p95 = (op) => m.ops[op]?.latency?.p95;
    rows.push({ stage, users: raw.plan.users, env: raw.plan.envName, result: run.result, peak: m.peakActive, sessions: m.sessions.started,
      reads: c.reads, writes: c.writes, readsPerSession: c.reads / Math.max(1, m.sessions.started),
      errRate: raw.evaluation.errors.rate, list: p95('browse.list'), apply: p95('gig.apply'), send: p95('chat.send'), deliv: p95('chat.delivery'),
      usd: priceMeasured(cfg.pricing, c), report: run.reportPath });
  }
  const file = path.join(REPORTS_DIR, 'comparison.md');
  const md = `# Giggre load test — stage comparison

Generated ${new Date().toISOString()} from the latest completed run of each stage. Values are **measured** except cost (**estimate** at list prices).

| Stage | Users | Env | Result | Peak sessions | Sessions | Reads | Reads/session | Writes | Unexpected errors | p95 list | p95 apply | p95 chat send | p95 delivery | Cost (est.) |
|---|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
${rows.map((r) => `| ${r.stage} | ${f0(r.users)} | ${r.env} | ${r.result} | ${f0(r.peak)} | ${f0(r.sessions)} | ${f0(r.reads)} | ${f0(r.readsPerSession)} | ${f0(r.writes)} | ${pct(r.errRate)} | ${ms(r.list)} | ${ms(r.apply)} | ${ms(r.send)} | ${ms(r.deliv)} | ${usd(r.usd)} |`).join('\n')}

${rows.length >= 2 ? `Reads per session went from ${f0(rows[0].readsPerSession)} (stage ${rows[0].stage}) to ${f0(rows.at(-1).readsPerSession)} (stage ${rows.at(-1).stage}). Flat means cost scales linearly with users; rising means it scales faster (global listeners).` : 'Only one stage completed so far.'}

Untested here: device rendering/frame times, real Cloud Firestore latency (if emulator), Cloud Functions server-side load (unless run with --with-functions), push delivery.

Reports: ${rows.map((r) => `[stage ${r.stage}](${path.basename(r.report)})`).join(' · ')}
`;
  writeFileSync(file, md);
  return file;
}

export function listReports() {
  if (!existsSync(REPORTS_DIR)) return [];
  return readdirSync(REPORTS_DIR).filter((x) => x.endsWith('.md')).map((x) => path.join(REPORTS_DIR, x));
}
