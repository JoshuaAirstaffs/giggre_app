---
name: giggre-load-testing
description: "Simulate a day of Giggre usage (1k / 5k / 10k / 15k unique users) with Firebase client-SDK virtual users, enforce a typed approval before every stage, and produce PASS / WARNING / FAIL performance, cost and consistency reports. Use for load tests, scalability or capacity questions, Firestore read/cost projections, contention or race checks, or resuming and reporting on a previous load-test stage."
user-invocable: true
argument-hint: "[status | plan N | smoke | run N | report | stop | cleanup | audit]"
---

# Giggre load testing

The tooling lives in `tools/loadtest/` (Node, one dependency: `firebase`). This skill runs it **safely**. You may plan, validate, run the local smoke test, run a stage **that a person has already approved**, read reports and propose fixes. You may never approve a stage, never run against production, and never change app code without permission.

## Hard rules

These are enforced by the code as well. Never try to work around them.

1. **Approvals are typed by a person.** `node cli.mjs approve --stage N` reads `/dev/tty`. Your shell has no terminal, so you *cannot* approve, and you must never try (no `script`, `expect`, `unbuffer`, writing approval files, editing `state/`, or similar). If you ever see an approval you didn't watch the user create, ask before using it.
2. **One approval = one execution of one stage.** It is bound to the plan hash (stage, environment, users, duration, concurrency, cost ceiling and every config file). It expires after 60 minutes and is deleted when used. A config edit voids it. RETEST needs a new approval.
3. **Stages are strictly sequential:** stage N needs stage N−1 `completed`. Never run two at once. Never start the next stage because a test passed. Silence is not approval.
4. **Production is locked** (`environments.production.locked`). Do not unlock it, even if asked casually. Explain that the synthetic gigs would appear to real workers and fire real push notifications, and stop.
5. **On interruption, nothing resumes.** `status` marks orphaned runs INTERRUPTED. Report that and wait.
6. **Do not edit `config/*.json` to make a stage pass.** Threshold, budget or workload changes need the user's explicit say-so, and they void outstanding approvals.
7. **OPTIMIZE means propose first.** Write the proposed app/rules/functions change, its expected effect on the measured bottleneck, and its risk. Edit only after the user agrees.
8. Never fabricate metrics. Quote numbers from the report or raw JSON, labelled measured / estimate / assumption / not tested.

## Session start (every invocation)

```bash
cd tools/loadtest && node cli.mjs status
```

Show the user the stage table, the last result and the report paths, any INTERRUPTED run, and the next stage. If `node_modules` is missing, run `npm install` (it installs only `firebase@13.2.0`).

## Commands

| Command | Who | What |
|---|---|---|
| `status` | you | State, results, unused approvals. Never resumes. |
| `validate` | you | Static checks (configs, schedule, syntax, prod lock). No Firebase traffic. |
| `plan --stage N [--env E] [--full-day] [--with-functions]` | you | Users, sessions, test vs real-world peak concurrency, rate limits, estimated reads/writes/function reads, cost, safety limits and the exact approval phrase. |
| `emulator [--with-functions]` | you, in the background | Starts the Auth + Firestore (+ Functions) emulators for `demo-giggre-loadtest` with the repo's `firestore.rules`. Uses Android Studio's JBR if no Java is installed. |
| `smoke` | you, emulator only | 12 users for 3 minutes. Exercises every scenario, race and probe. Not a stage, no approval. Run it after app or config changes, before asking for a stage approval. |
| `approve --stage N …` | **the user only** | Shows the plan, then asks them to type `APPROVE STAGE N <ENV> <USERS> USERS MAX $<ceiling>`. |
| `run --stage N …` | you, only after the user says they approved | Refuses without a valid approval. Seeds, runs, auto-stops, then writes `reports/stage-N-…md` and `reports/comparison.md`. |
| `stop` | you or the user | Emergency stop. The controller stops generators and writes an ABORTED report. |
| `report` | you | Regenerates the cross-stage comparison. |
| `cleanup --env E` | the user (typed confirmation off-emulator) | Removes synthetic data. On the emulator it wipes the in-memory project. |

## Stage workflow

1. `status`. If the next stage isn't stage 1, check its predecessor's report first.
2. If the emulator isn't running and the stage is on the emulator, start it in the background: `node cli.mjs emulator` with `run_in_background`. Wait for "All emulators ready" in its output.
3. If the app, rules or config changed since the last smoke: `node cli.mjs smoke`. Fix script problems (not app code) until it is clean. A smoke FAIL from real findings such as the security probe or the single-slot race is expected; say so.
4. `plan --stage N` and present the **Proposed configuration** block below.
5. Ask for approval in these words, then **stop and wait**:
   > To approve, please run this in your own terminal (it needs a keyboard):
   > `cd tools/loadtest && node cli.mjs approve --stage N` and type the phrase it shows. Tell me when it's done.
6. When they say it's done: `node cli.mjs run --stage N` in the background (stage 1 ≈ 60–75 min). Watch its output. If it aborts, report why.
7. When it finishes, read the stage report and give the summary in the exact format below. Then **wait**.
8. Their answer:
   - **YES** → go to step 4 for N+1. This is a new approval, not the old one.
   - **NO** → stop. Offer `cleanup`.
   - **OPTIMIZE** → read [reference/optimization-playbook.md](reference/optimization-playbook.md). Propose changes ranked by measured impact. Do not edit until they agree. After the fixes, smoke, then RETEST the stage with a fresh approval.
   - **RETEST** → step 4 for the same N (fresh approval).

### Proposed configuration block (step 4)

Always show these, taken from `plan`:

- Environment and project, and whether it is billable.
- Unique users (workers, hosts, new registrations), sessions, and real duration.
- **Test peak concurrency vs real-world peak**, and the stress factor. Make clear that compressing the day multiplies concurrency.
- Ops/s and registration rate limits, ramp-up, and the hard read/write/time limits.
- Estimated reads and writes, the function-read estimate, the cost ceiling, and the same day at production pace ($/day).
- Assumptions in force (workload.json) and what is **not tested** (device rendering, Storage uploads, push delivery, real Cloud latency on the emulator).

### Post-stage message (step 7, exact format)

Start with the result block, verbatim from the end of the run output:

```
The [CURRENT_USER_COUNT]-user load test has completed.

Overall Result: PASS / WARNING / FAIL

Would you like to proceed with the [NEXT_USER_COUNT]-user load test?

1. YES — Proceed to the next stage
2. NO — Stop testing
3. OPTIMIZE — Review performance problems first
4. RETEST — Repeat the current stage
```

Put it **after** a short summary:
- why the stage got its verdict;
- the top 3 bottlenecks with measured numbers;
- consistency and security check failures;
- the cost estimate;
- the report link.

For stage 4, there is no next stage: say testing is complete and link `reports/comparison.md`.

## Interpreting results

Read [reference/metrics.md](reference/metrics.md) before explaining a number. Key points:

- **Emulator runs** validate correctness, rules, read/write volume and contention. Their latencies come from one local Java process, and the emulator does **not** enforce composite indexes. Say this whenever you quote emulator latency.
- **Reads per session rising across stages** means cost grows faster than users (global listeners). It is the most important scaling signal.
- A **generator saturated** warning means the latency numbers are suspect. Reduce load per process (`generatorProcesses`) before drawing conclusions.
- Business-rule rejections (gig taken, already applied, slot full) are expected and are not errors.

## Keeping it in sync with the app

The simulator replays specific paths, fields and queries. After app changes that touch gigs, chat, users, rules or functions, follow [reference/re-audit.md](reference/re-audit.md) to update `docs/architecture-audit.md`, `src/scenarios/*.mjs` and `src/costModel.mjs`. Then run `validate` and `smoke`.

## Other references

- [reference/approval-protocol.md](reference/approval-protocol.md): how the gate works and what it does not protect against.
- [reference/maps-device-testing.md](reference/maps-device-testing.md) and [templates/map_render_perf_test.dart](templates/map_render_perf_test.dart): map rendering on a device.
- `tools/loadtest/README.md`: install, layout and staging setup.
- `tools/loadtest/docs/architecture-audit.md`: the code facts behind every scenario.
