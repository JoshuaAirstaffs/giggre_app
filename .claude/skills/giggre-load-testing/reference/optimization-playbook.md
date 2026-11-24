# OPTIMIZE: propose, don't edit

When the user picks OPTIMIZE, produce a ranked proposal. **Change nothing until they agree.**

For each item, give:
- the measured symptom (report section and number);
- the root cause (`file:line`);
- the proposed change;
- the expected effect (estimated read, latency or cost delta, with the arithmetic shown);
- the risk and rollout (app release needed? old app versions still on phones?);
- how a RETEST will verify it.

## Usual candidates, by expected impact

These come from the audit. Confirm each against the measurements before proposing it.

1. **Global open-gigs listener** (`gig_map_section.dart:2799`)
   - Store a `geohash` on gig create. Existing gigs need a backfill.
   - Query the 3×3 cells around the worker, then filter to 10 km on the device. Add `limit()`.
   - Reads per session drop from "all open gigs" to "gigs nearby".
   - Old app versions keep the global listener until they update.
2. **Global `users where isOnline == true` listeners** (`gig_host_screen.dart:451, 1738`)
   - Make them geo-bounded and limited, or use a server-maintained nearby-online count.
   - Stop mounting the Host shell's live listeners while in Worker mode (and the reverse) in `mode_shell.dart`.
   - This removes the fan-out that grows with concurrency squared.
3. **`onOpenGigPosted` reads every available user** (`functions/src/index.ts:161`)
   - Do a geohash range query instead.
   - This is server-side only, so it ships without an app release.
4. **Single-slot select** (`gig_detail_sheet.dart:841`)
   - Use a transaction that requires `status == 'open'` and no `workerId`.
   - Optionally, a rule that blocks changing `workerId` once it is set.
5. **`open_gigs` update rule**
   - For non-hosts while open: `affectedKeys().hasOnly(['applicants'])`, plus a check that they only add themselves.
   - Ships without an app release, but old clients must still work.
6. **User-doc write volume**
   - Move `isOnline`, `location` and `fcmTokens` to a small `presence/{uid}` doc, so they stop triggering the 5 `users` triggers and the public-profile sync.
7. **Per-room unread listeners**
   - Keep a per-user unread counter updated by `onChatMessageCreated`.
   - Replaces N `limit(1)` listeners with 1 doc listener.
8. **Places Autocomplete**
   - Add a session token per search (bills a whole search as one session) and debounce harder.

Rules changes can be tested on the emulator immediately (smoke → RETEST). App changes need a rebuild only for device tests. The simulator reproduces the app's queries in `src/scenarios`, so update those to the new queries when proposing an app change, to measure the effect before shipping.
