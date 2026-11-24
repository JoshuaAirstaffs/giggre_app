# How each metric is measured

Everything in a report's operation tables, counters, checks and timeline is **measured** by the generator processes (`src/metrics.mjs`). Cost and Cloud Functions numbers are **estimates**. Workload inputs are **assumptions**.

## Terms

| Term | Meaning |
|---|---|
| Unique daily users | Distinct synthetic identities in the stage (1k/5k/10k/15k). This is **not** concurrency. |
| Session | One app open → use → close by one user. A user has 1–3 sessions a day. |
| Concurrent sessions | Sessions open at the same instant. "Test peak" is on the compressed clock. "Real-world peak" is the same sessions spread over 24 h. |
| Operation | One client SDK call (get, query, write, transaction, callable) or a listener's first snapshot. |
| Ops/s | Operations per second through the generator's token bucket. It is capped by `maxOpsPerSec`, which ramps from 10% to 100% over `rampUpMin`. |

## Latency

Latency is the wall-clock time from just before the SDK call until its promise settles. For listeners, it is the time until the **first server snapshot**.

- Percentiles come from up to 5,000 reservoir samples per operation per process. When there are several processes, these are merged in proportion to each process's count.
- p50, p95 and p99 are nearest-rank values. "max" is exact.
- Composite operations such as `gig.apply`, `chat.send` and `gig.post` time the whole user-visible step, including the guard reads.
- `chat.delivery` is the time from the sender's `addDoc` call until a **second client signed in as the recipient** receives the message in its listener. It is measured on one machine clock.
- `gig.propagation` is the time from a host's post until it first appears in a different session's open-gigs listener.
- `map.clusterCpuMs` is the app's O(n²) clustering run in **Node**. It shows how the work grows with the number of gigs; it is not a phone measurement.

## Reads and writes

These follow Firestore billing rules:

| Operation | Reads billed |
|---|---|
| Get | 1 |
| Query | the number of docs returned, minimum 1 |
| Listener, first snapshot | the number of docs returned, minimum 1 |
| Listener, afterwards | 1 per document change delivered |
| Transaction | its `get`s, multiplied by the number of attempts |

Writes count each set, update, add and batch item. `readsBy` breaks reads down by source:
- `openGigsGlobal` and `onlineUsersGlobal` are the two global listeners.
- `roomUnread` is the per-room badges.

**Not counted:** reads done by Cloud Functions (shown as an estimate), security-rule `get()`s (not billed), and the SDK's own retries.

## Errors

- **Expected rejection:** an outcome the app itself would show as "no", such as gig unavailable, already applied, slot full, already assigned, not editable, duplicate account, invalid credentials, invalid input or a pending request. Denied security probes also count here.
- **Unexpected error:** everything else (`permission-denied` on a normal flow, `unavailable`, `deadline-exceeded`, `resource-exhausted`, `aborted` after retries, crashes).

Unexpected error rate = unexpected ÷ all operations.

## Checks

| Check | Pass condition |
|---|---|
| race.noLostApplications | applicants stored = successful concurrent applies |
| race.singleSlotOneSelectAccepted | at most 1 of 2 concurrent selections succeeds (WARNING if not) |
| race.duplicateExclusiveAssignment | at most 1 worker ever sees "assigned" on a single-slot gig (FAIL) |
| race.multiSlotNoOverfill | slot docs ≤ workerSlots and = filledSlotCount |
| chat.noMissingMessages / chat.messageOrdering | the peer received every message, in send order |
| consistency.* | read back after the run: created gigs exist, filled ≤ slots, no duplicate applicants, slot docs match the count, assigned gigs have a worker, sent messages exist |
| security.* | the probe was **denied** with `permission-denied` (FAIL otherwise) |
| browse.listHasGigs | a session saw at least 1 gig (WARNING) |

## Verdict

- **FAIL:** a latency p95 above its `fail` value, the unexpected error rate above `fail`, any FAIL-class check failing, or the run aborted.
- **WARNING:** any `warn` threshold breached, a WARNING-class check failing, or the generator saturated (event-loop p99 above 200 ms or CPU above 85%).
- **PASS:** none of the above.

An operation with no samples is reported as "not exercised" and never counts as a pass.

## Emulator caveats

- It is one JVM on this Mac, so latency under load reflects the emulator, not Google's servers.
- Composite indexes are not enforced: queries that would need an index in the cloud still succeed.
- There are no quotas, no regional latency and no billing.
- Functions run only with `--with-functions`. Push sends from functions fail harmlessly, because synthetic users have fake FCM tokens and demo projects have no credentials.
