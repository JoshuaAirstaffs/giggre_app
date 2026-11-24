// Post-run data consistency checks and the PASS / WARNING / FAIL verdict.
import { endpoints, getDocRest, listDocs, ownerToken, signIn } from './rest.mjs';

/** Reads back what the run created and checks invariants. */
export async function consistencyChecks({ env, population, password, gens, log }) {
  const checks = {};
  const check = (name, ok, detail) => {
    const c = (checks[name] ??= { passed: 0, failed: 0, details: [] });
    if (ok) c.passed++; else { c.failed++; if (c.details.length < 20) c.details.push(detail); }
  };
  let token;
  if (endpoints(env).emu) token = ownerToken(env);
  else {
    const auditor = population.returning[0];
    token = (await signIn(env, auditor.email, password(auditor.email))).idToken; // normal user: rules apply
  }
  const gigs = gens.flatMap((g) => g.world?.createdGigs ?? []);
  const msgs = gens.flatMap((g) => g.world?.sentMessages ?? []);
  log(`consistency: ${gigs.length} created gigs, ${msgs.length} sent messages`);

  for (const g of gigs.slice(0, 3000)) {
    const d = await getDocRest(env, `${g.col}/${g.id}`, token).catch(() => undefined);
    check('consistency.createdGigPersisted', d !== null && d !== undefined, { gig: `${g.col}/${g.id}` });
    if (!d) continue;
    const slots = d.workerSlots ?? 1, filled = d.filledSlotCount ?? 0;
    check('consistency.filledWithinSlots', filled <= slots, { gig: g.id, filled, slots });
    const ids = (d.applicants ?? []).map((a) => a.workerId);
    check('consistency.noDuplicateApplicants', new Set(ids).size === ids.length, { gig: g.id, applicants: ids.length });
    if (slots > 1 && g.col === 'open_gigs') {
      const ws = await listDocs(env, `${g.col}/${g.id}/workers`, token).catch(() => []);
      const active = ws.filter((w) => !['declined', 'cancelled', 'no_worker'].includes(w.data.status)).length;
      check('consistency.slotDocsMatchCount', active === filled, { gig: g.id, slotDocs: active, filledSlotCount: filled });
    } else if (['navigating', 'arrived', 'working', 'task_complete', 'payment', 'completed'].includes(d.status) && g.col === 'open_gigs') {
      check('consistency.assignedGigHasWorker', Boolean(d.workerId), { gig: g.id, status: d.status });
    }
  }
  for (const msg of msgs.slice(0, 1000)) {
    const d = await getDocRest(env, `chat_rooms/${msg.roomId}/messages/${msg.id}`, token).catch(() => null);
    check('consistency.sentMessagePersisted', Boolean(d), msg);
  }
  return checks;
}

// Correctness checks that make a stage FAIL when any instance fails.
const FAIL_CHECKS = [
  'race.duplicateExclusiveAssignment', 'race.noLostApplications', 'race.multiSlotNoOverfill',
  'chat.noMissingMessages', 'chat.messageOrdering',
  'consistency.createdGigPersisted', 'consistency.filledWithinSlots', 'consistency.noDuplicateApplicants',
  'consistency.slotDocsMatchCount', 'consistency.assignedGigHasWorker', 'consistency.sentMessagePersisted',
];
const WARN_CHECKS = ['race.singleSlotOneSelectAccepted', 'browse.listHasGigs'];

export function evaluate({ merged, checks, thresholds, resources, emulator, aborted, isEmulator = false }) {
  const findings = [];
  let verdict = 'PASS';
  const bump = (v) => { if (v === 'FAIL' || (v === 'WARNING' && verdict === 'PASS')) verdict = v; };

  const lat = [];
  for (const [op, t] of Object.entries(thresholds.latencyP95)) {
    const o = merged.ops[op];
    if (!o?.latency?.count) { lat.push({ op, status: 'NOT EXERCISED', ...t }); continue; }
    const p95 = o.latency.p95;
    let status = p95 > t.fail ? 'FAIL' : p95 > t.warn ? 'WARNING' : 'PASS';
    const noteOnly = isEmulator && thresholds.latencyVerdictOnEmulator === 'note';
    if (noteOnly && status !== 'PASS') status = `${status} (emulator — note only)`;
    lat.push({ op, p95, status, ...t, count: o.latency.count });
    if (status === 'FAIL' || status === 'WARNING') { bump(status); findings.push(`${op} p95 ${Math.round(p95)} ms (${status}; warn ${t.warn}, fail ${t.fail})`); }
  }

  let total = 0, unexpected = 0, expected = 0;
  for (const o of Object.values(merged.ops)) { total += o.ok + o.expected + o.unexpected; unexpected += o.unexpected; expected += o.expected; }
  const errRate = total ? unexpected / total : 0;
  const er = thresholds.unexpectedErrorRate;
  const errStatus = errRate > er.fail ? 'FAIL' : errRate > er.warn ? 'WARNING' : 'PASS';
  if (errStatus !== 'PASS') { bump(errStatus); findings.push(`Unexpected error rate ${(errRate * 100).toFixed(2)}% (${errStatus})`); }

  const allChecks = { ...merged.checks, ...checks };
  const checkRows = [];
  for (const [name, c] of Object.entries(allChecks)) {
    let status = c.failed ? 'FAIL' : 'PASS';
    if (name.startsWith('security.')) status = c.failed ? 'FAIL' : 'PASS';
    else if (WARN_CHECKS.includes(name)) status = c.failed ? 'WARNING' : 'PASS';
    else if (!FAIL_CHECKS.includes(name)) status = c.failed ? 'WARNING' : 'PASS';
    checkRows.push({ name, ...c, status });
    if (status !== 'PASS') { bump(status); findings.push(`${name}: ${c.failed} failed / ${c.passed + c.failed}`); }
  }

  const g = thresholds.generator;
  const maxLoop = Math.max(0, ...resources.flatMap((r) => r.loopP99 ?? []));
  const maxCpu = Math.max(0, ...resources.flatMap((r) => r.cpuPct ?? []));
  const generatorSaturated = maxLoop > g.maxEventLoopP99Ms || maxCpu > g.maxCpuPercent;
  if (generatorSaturated) { bump('WARNING'); findings.push(`Load generator saturated (event-loop p99 ${Math.round(maxLoop)} ms, CPU ${Math.round(maxCpu)}%): latency numbers may be inflated by the generator`); }

  // ps %cpu is per core; >= 95% sustained means at least one core pegged.
  const emuCpu = emulator?.cpuPct ?? [];
  const emuSorted = [...emuCpu].sort((a, b) => a - b);
  const emuP90 = emuSorted.length ? emuSorted[Math.floor(emuSorted.length * 0.9)] : null;
  const emulatorSaturated = emuP90 != null && emuP90 >= 95;
  if (emulatorSaturated) { bump('WARNING'); findings.push(`Emulator busy (CPU p90 ${Math.round(emuP90)}%, max ${Math.round(emuSorted.at(-1))}%): slow results may describe the local emulator, not the app on Cloud Firestore`); }

  if (aborted) { verdict = 'FAIL'; findings.unshift(`ABORTED: ${aborted}`); }
  return { verdict, findings, latency: lat, errors: { total, unexpected, expected, rate: errRate, status: errStatus }, checks: checkRows, generator: { maxLoopP99Ms: maxLoop, maxCpuPct: maxCpu, saturated: generatorSaturated }, emulator: { cpuP90: emuP90, cpuMax: emuSorted.at(-1) ?? null, rssMaxMb: Math.max(0, ...(emulator?.rssMb ?? [])), saturated: emulatorSaturated } };
}
