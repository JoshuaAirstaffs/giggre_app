# Giggre load test — stage comparison

Generated 2026-11-25T22:09:32.787Z from the latest completed run of each stage. Values are **measured** except cost (**estimate** at list prices).

| Stage | Users | Env | Result | Peak sessions | Sessions | Reads | Reads/session | Writes | Unexpected errors | p95 list | p95 apply | p95 chat send | p95 delivery | Cost (est.) |
|---|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 1,000 | emulator | PASS | 70 | 1,596 | 359,190 | 225 | 8,972 | 0.00% | 35083 ms | 8396 ms | 3556 ms | 1531 ms | $0.23 |
| 2 | 1,500 | emulator | PASS | 73 | 2,396 | 661,048 | 276 | 13,428 | 0.00% | 3876 ms | 2998 ms | 857 ms | 485 ms | $0.42 |

Reads per session went from 225 (stage 1) to 276 (stage 2). Flat means cost scales linearly with users; rising means it scales faster (global listeners).

Untested here: device rendering/frame times, real Cloud Firestore latency (if emulator), Cloud Functions server-side load (unless run with --with-functions), push delivery.

Reports: [stage 1](stage-1-1000-users-20261124224038-s1-17e9a0.md) · [stage 2](stage-2-1500-users-20261125163221-s2-f1ce02.md)
