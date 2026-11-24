# Giggre load test

This tool simulates a day of Giggre usage with virtual users. Each virtual user is a separate Firebase **client SDK** app instance: it signs in, opens the same listeners the Flutter app opens, posts, applies, selects and chats with the app's exact field shapes, and goes through the real `firestore.rules`. Every stage needs a single-use approval typed by a person.

You normally drive it through the Claude Code skill `/giggre-load-testing`. This file covers manual use and setup.

## Install

```bash
cd tools/loadtest
npm install          # one dependency: firebase@13.2.0
node cli.mjs validate
```

**Requirements**
- Node 20 or newer.
- The Firebase CLI, to run the emulators.
- Java for the Firestore emulator. If none is installed, `node cli.mjs emulator` uses Android Studio's bundled JBR.

k6 is **not** used. Giggre has no HTTP API apart from a few callables, and k6 can't reproduce Firestore listeners, transactions or rules. The Node client SDK can.

## Typical flow (emulator, no billing)

```bash
node cli.mjs emulator            # terminal A, keep running (in-memory)
node cli.mjs smoke               # 12 users, 3 min, checks the scripts — no approval needed
node cli.mjs plan --stage 1      # review the proposal
node cli.mjs approve --stage 1   # a PERSON types the phrase shown
node cli.mjs run --stage 1       # ~60–75 min, then report + stop
node cli.mjs status
```

Reports are written to `reports/stage-<N>-<users>-users-<runId>.md`, plus `reports/comparison.md`. Raw metrics go to `reports/raw/` (gitignored).

## Layout

| Path | Contents |
|---|---|
| `cli.mjs` | Commands: status, validate, plan, approve, run, smoke, stop, report, emulator, cleanup |
| `config/stages.json` | The four presets (users, compression, concurrency, ops/s, registrations/min, processes) |
| `config/workload.json` | Workload **assumptions**: role split, arrivals per hour, sessions, intents, gig mix, chat, contention, seed data |
| `config/thresholds.json` | PASS / WARNING / FAIL targets (provisional) |
| `config/safety.json` | Hard stops, read/write limits, ramp-up, approval TTL, synthetic-data markers, geo sandbox |
| `config/pricing.json` | List prices for **estimates**. Verify before a billable run. |
| `config/environments.json` | `emulator` (default), `staging` (disabled), `production` (locked) |
| `src/runner.mjs` | Controller: the gate, seeding, generator processes, abort checks, report |
| `src/generator.mjs` | Runs its share of sessions and self-monitors CPU and event loop |
| `src/scenarios/` | `session.mjs` (app open), `actions.mjs` (user actions), `race.mjs` (contention) |
| `src/seed.mjs` | Synthetic returning users, open gigs, chat rooms, written through the rules |
| `src/approval.mjs`, `src/tty.mjs`, `src/state.mjs` | Approval gate, typed confirmation, persistent state |
| `src/metrics.mjs`, `src/analyze.mjs`, `src/report.mjs` | Measurement, verdict, Markdown reports |
| `src/costModel.mjs`, `src/plan.mjs` | Schedule and usage/cost estimate |
| `src/cleanup.mjs` | Synthetic-data removal |
| `docs/architecture-audit.md` | The code facts the scenarios replay |
| `state/` (gitignored) | `state.json`, approvals, population files, STOP flag. Holds no secrets. |

## Staging (billable): read this before enabling

`staging` points at the **dev** project `simpleproject-8ff7a`, which real testers use. A run there would:

- show synthetic gigs in testers' gig lists (inside `syntheticGeoSandbox`; move the box away from testers);
- fire `onOpenGigPosted`, which reads every available user and pushes to anyone within 10 km;
- create thousands of email/password Auth accounts (`@loadtest.giggre.invalid`).

**Recommended:** create a dedicated staging project, deploy the rules, indexes and functions to it, and put its web config in `environments.staging.webConfig`. Then set `enabled: true` and export a password salt before planning:

```bash
export LOADTEST_PASSWORD_SALT=$(openssl rand -hex 16)
```

The salt is never written to disk, so keep it for cleanup. Then update `config/pricing.json` (including `verifiedOn`) and run `plan --env staging`. The approval phrase includes the cost ceiling.

Production (`giggre-prod`) is locked and refused by the runner.

## Cleanup

| Environment | What `cleanup` does |
|---|---|
| Emulator | `node cli.mjs cleanup` wipes the in-memory demo project. Stopping the emulator also discards everything. |
| Staging | `node cli.mjs cleanup --env staging` needs a typed confirmation. It signs in as each synthetic user and deletes their gigs (marker-checked), messages, user doc and account, then lists rule-protected leftovers for `firebase firestore:delete`. |
