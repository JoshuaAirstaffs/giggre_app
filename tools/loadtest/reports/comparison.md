# Giggre load test — stage comparison

Generated 2026-11-23T23:23:06.177Z from the latest completed run of each stage. Values are **measured** except cost (**estimate** at list prices).

| Stage | Users | Env | Result | Peak sessions | Sessions | Reads | Reads/session | Writes | Unexpected errors | p95 list | p95 apply | p95 chat send | p95 delivery | Cost (est.) |
|---|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 1,000 | emulator | ABORTED | 82 | 1,270 | 287,032 | 226 | 6,556 | 0.21% | 59980 ms | 22105 ms | 5418 ms | 3566 ms | $0.18 |

Only one stage completed so far.

Untested here: device rendering/frame times, real Cloud Firestore latency (if emulator), Cloud Functions server-side load (unless run with --with-functions), push delivery.

Reports: [stage 1](stage-1-1000-users-20261123211322-s1-72211c.md)
