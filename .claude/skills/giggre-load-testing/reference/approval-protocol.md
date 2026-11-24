# Approval protocol

## What the code enforces

These checks live in `src/approval.mjs`, `src/runner.mjs` and `src/state.mjs`.

1. **Typed by a person.** `approve` opens `/dev/tty` and needs this exact phrase:
   `APPROVE STAGE <N> <ENV> <USERS> USERS MAX $<ceiling>`.
   With no controlling terminal (agents, CI, piped stdin), it refuses.
2. **Bound to the plan.** The approval stores the stage, environment, project, users, duration, concurrency, ops/s, cost ceiling and a SHA-256 plan hash. The hash covers the stage preset, the environment and every config file. `run` recomputes the plan and rejects any difference.
3. **Single use, short-lived.** It expires after `safety.approvalTtlMinutes` (60). `run` writes its id to `state.usedApprovalIds` and deletes the file before any load starts. A newer approval for the same stage replaces older unused ones.
4. **Stage order.** Stage N runs only if stage N−1 is `completed`. Aborted and interrupted stages must be retested first.
5. **One run at a time.** A run records its pid in `state.current`. A second `run` refuses while that pid is alive.
6. **No resume.** If the recorded pid is gone, `status`, `approve` and `run` mark the run INTERRUPTED. Nothing restarts it.
7. **Locked environments.** `production` is `locked: true`. The runner refuses `giggre-prod` by name as well as by flag, and `validate` fails if the lock is removed.
8. **Billable ceiling.** For billable environments, the ceiling is twice the estimate (minimum $1). During the run, measured reads and writes priced at list rates are compared against it every 5 s, along with hard read, write and time limits. **This is not live billing data.**

## What it does not protect against

Someone with write access to the repo can forge an approval file, edit `state/`, or change the code. The gate stops accidental runs, stale approvals and agent self-approval through normal tools. It is not a security boundary. That is why the skill tells Claude never to create, copy or edit approval or state files.

## Emergency stop

`node cli.mjs stop` writes `state/STOP` and sends SIGTERM to the controller. Ctrl-C in the run's terminal does the same. Generators stop starting sessions, abort in-flight work at the next operation, and send their final metrics. Anything still alive is killed after 60 s. An ABORTED report is always written.

## Cleanup approval

- **Emulator:** `cleanup` wipes only the in-memory `demo-*` project. No confirmation is needed beyond running it.
- **Any other environment:** a person must type `DELETE <n> SYNTHETIC USERS IN <project>`. Cleanup acts only as synthetic accounts (`@loadtest.giggre.invalid`) and deletes only gigs carrying the `loadTestRunId` marker. Rule-protected leftovers are listed for manual removal, never force-deleted.
