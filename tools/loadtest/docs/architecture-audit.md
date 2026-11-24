# Giggre architecture audit for load testing

Audited 2026-11-23 against branch `dev` (app 3.0.7). File references are `path:line` at that commit. **Re-audit after app changes** (see the skill's `reference/re-audit.md`), because the simulator replays these exact paths, fields and queries.

Status labels: **Fact** means read in code. **Inference** means deduced and not executed. **Assumption** means a workload input with no data behind it.

## 1. Platform

| Area | Finding |
|---|---|
| Flavors | `--dart-define=FLAVOR=dev\|prod` (`lib/main.dart:35`). dev runs on `simpleproject-8ff7a`, prod on `giggre-prod`. |
| Firestore regions | dev is in asia-east2; prod is nam5. Triggers run in us-central1 for every project except `simpleproject-8ff7a` (`functions/src/region.ts`). |
| Auth providers | Email/password, Google, Apple. There is no phone or anonymous auth. Google and Apple first call `checkAccountExists`. |
| State management | Provider with 3 app-scoped providers. Only `CurrentUserProvider` touches Firestore. Everything else is widget-level StreamBuilders or subscriptions, cancelled in `dispose()`. |
| Analytics | **None.** No `firebase_analytics` and no `logEvent`. The workload mix is therefore an **assumption**. |
| Existing tests | 11 unit/widget tests. No `integration_test/`, and the package is not in dev_dependencies. No tests for functions. |

## 2. What every session loads (the baseline)

`ModeShell` builds **both** `HostShell` and `WorkerShell` and keeps them mounted offstage (`lib/screens/mode_shell.dart:37-46`). Every tab is inside an `IndexedStack`. **Every user therefore runs both the worker and the host listener sets, whichever mode is showing.**

The simulator opens all of these (`src/scenarios/session.mjs → appOpen`):

| Source | Query | Bound |
|---|---|---|
| main.dart / providers | `general_config/maintenance`, `app_content/word_filter`, `general_config/gig_visibility_rules`, `general_config/live_support` listeners | 1 doc each |
| Auth restore + HomeScreen | `users/{uid}` get ×2 plus a listener | 1 doc |
| FCM register (×2, `push_notification_service.dart:79-103`) | `users where fcmTokens array-contains token` (**no limit**), then arrayUnion | — |
| HomeScreen | `app_content/updates/items`, carousel gets | small |
| Active / pending-cancel bars | 3 gig collections + collectionGroup `workers`, workerId + status in [...] | limit 1 (CG has no limit) |
| Shell chat badges | `chat_rooms where participants array-contains uid` (**no limit**), plus **one `limit(1)` unread listener per room** | grows with rooms |
| GigWorkerScreen | savedGigs, 6 assignment listeners, unverified-limit docs | small |
| **GigMapSection** (`gig_map_section.dart:2799`) | **`open_gigs where status in [open, partially_filled]`, global, with no geo bound and no limit** | **every open gig in the world** |
| **GigHostScreen** (`:451`, `:1738`) | **`users where isOnline == true`, global and unbounded** | **every online worker** |
| GigHostScreen / HostGigs / ProfileTab | `{quick,open,offered}_gigs where hostId == uid orderBy createdAt` (no limit), notifications limit 100 | own data |
| Worker mode | `users/{uid}` `isOnline: true` on start and resume, `false` on pause/detach/dispose; `location` once per load | writes |

### Consequences (Fact plus billing rules)

1. Every session reads every open gig. When any open gig changes (apply, post, edit, GSIN write), every open session is billed one read.
2. Every session reads every online worker. Every write to an online worker's `users` doc (isOnline, location, fcmTokens, earnings, slot) is billed one read to every open session. **This grows with concurrency squared.**
3. Every `users/{uid}` write also fires about 5 Cloud Functions (`syncPublicProfile`, `onVerificationChange` in us-central1, `onIncomingCall`, `onUserProfileWordFilter`, `onVerificationStatusChanged`).

## 3. Data model and flows used by the simulator

| Flow | Path and shape | Concurrency control |
|---|---|---|
| Register (`register_screen.dart:1277-1331`) | `userId` collision query, referral-code query, then a **WriteBatch** that sets `users/{uid}` (plus `users/{referrer}/referrals_list/{uid}`). Starts `isVerified:'unverified'`, `availableForGigs:true`, `slot:'AVAILABLE'`. | none needed |
| Post open gig (`post_open_gig_screen.dart:594`) | `open_gigs.add` with hostId, title, requiredSkills[1], budget, payType, location GeoPoint, status 'open', workerSlots, filledSlotCount 0, and `scheduledDate` (omitted for Flexible). | — |
| Post offered gig (`post_offered_gig_screen.dart:739-771`) | `offered_gigs.add`. A single recipient goes in `workerId` on the gig. Multiple recipients get a separate **batch** of `workers/{uid}` slot docs, which is not atomic with the add. | — |
| Quick gig | `quick_gigs.add` (status 'scanning'). Matching then runs **on the host's phone**: it queries all users where isOnline, availableForGigs, seekingQuickGigs and slot AVAILABLE, with no limit, and polls `get()` every 3 s. | in-memory only |
| Apply (`gig_map_section.dart:396-670`) | Limit-guard reads, gig get, 4+4 busy checks, then `update({applicants: arrayUnion(...)})` and a `notifications.add` (new_applicant). | **none**; arrayUnion on one hot doc |
| Select, single slot (`gig_detail_sheet.dart:841-853`) | Plain `update({workerId, assignedWorkerId, status:'navigating', ...})`. | **none: a race can reassign** |
| Select, multi slot (`:859-912`) | `runTransaction`: checks filled < slots and that the slot doc doesn't exist, then sets the slot and increments filledSlotCount. | transaction |
| Edit (`edit_gig.dart:51-90`) | Transaction that re-checks `canEditGig` (open, no applicants, nothing filled). | transaction |
| Lifecycle (`working_ui.dart`) | navigating → arrived → working → task_complete. **`workerLocation` is written on every GPS fix of 5 m or more** while navigating. The host then sets `payment` + paymentCode, and the worker confirms in a transaction that updates `users.earnings`. | transaction at payment |
| Gig chat (`lib/screens/chat/chat.dart`) | Room `chat_rooms/gig_{gigId}` is created lazily with `participants[2]`. Each send is `messages.add` plus a room `lastMessage` update (2 writes, not batched). There are **no unread counters**: badges are per-room `hasSeen == false limit 1` listeners. | — |
| Group chat | Created through callables only. Messages are client-written under strict key rules; read markers live in `lastRead.{uid}`. | — |

## 4. Security rules (`firestore.rules`) relevant to load and abuse

- `users` read is **public** (`allow read: if true`). This is temporary until most users run 3.0.1+, per the TEMPORARY comment above the rule.
- **`open_gigs` update is allowed for any signed-in user while `status == 'open'`** (or `partially_filled`), with no restriction on which fields change. It exists so workers can arrayUnion into `applicants`. The simulator probes this as `security.editForeignOpenGig`. Expect it to **fail** until the rule is narrowed.
- `_counters/{docId}` and `support_settings/{docId}` allow writes by any signed-in user (and `support_settings` by anyone). This is not exercised by the load test; it is noted for review.
- Chat message creates do 2–4 `get()` calls inside the rule (room, then both users for block checks). Those rule reads are not billed to the client, but they add latency.

## 5. Cloud Functions with load-sensitive behaviour

| Function | Trigger | Load profile |
|---|---|---|
| **`onOpenGigPosted`** (`functions/src/index.ts:148`) | open gig created | **Reads every `users` doc with `availableForGigs == true`** (unbounded, no geo), filters to 10 km in memory, and does one push per match (each push re-reads the user). Cost per gig is about the number of available workers. |
| GSIN `on*GigAssignGsku` (`gsin.ts:185-206`) | gig created | Transaction on a per-task-type counter. Its own comment records about 8% contention failures in a 200-gig burst (`retry: true`). |
| `checkExpiredGigSchedules` | every 5 min | Unbounded query on open/offered gigs with `scheduledDate <= now`. |
| `autoApproveStaleWorkerCancellations` | every 2 min | 3 unbounded queries. |
| `onGroupMessageCreated` | group message | Up to 50 pushes, each with a users read. |
| User-doc triggers ×5 | every `users/{uid}` update | Includes `onVerificationChange`, which is pinned to us-central1 (cross-region on dev). |
| Gig-doc triggers ×6–8 | every gig update | Progress, assigned, cascade, points, cashback, GSIN skill-change, declined. |

Global `maxInstances: 100`. Several modules use 50 or 10. No `concurrency` or `minInstances` is set.

## 6. Google Maps

| Item | Finding |
|---|---|
| Packages | `google_maps_flutter` 2.9 (+ web), `flutter_map` + OSM tiles as a fallback for Huawei and devices without Play services, `geolocator`, `geocoding` (platform geocoder). No clustering package. |
| Billable Google web APIs | **Places Autocomplete and Place Details only**, on the three post-gig screens. **No `sessiontoken` is sent**, so each debounced keystroke burst is billed as its own request. |
| Free or non-Google services | OSRM routing and Nominatim reverse geocoding, including a ~1 km-grid country check queued 1.1 s apart on the gig map. These are subject to the public services' usage policies, not Google billing. |
| Geographic queries | **None.** There is no geohash. All distance filtering (default 10 km) is Haversine on the device, over the global gig listener. |
| Markers and clustering | Canvas-drawn bitmaps, cached. Hand-rolled O(n²) clustering, recomputed when zoom changes by 0.3 or more. On the host map, avatar markers do an `http.get` of each photo. |
| Location updates | One-shot fixes, plus a 5 m `distanceFilter` stream that **writes to the gig doc on every fix** while navigating. |

**Test split:** backend "geo" load is the global listener and is fully exercised by the simulator. Rendering, frame times and marker cost need a device; see `templates/map_render_perf_test.dart`. The load test sends **0** Google Maps Platform requests.

## 7. Storage

Profile photos are 512 px, quality 80. Gig photos are up to 5 at 1600 px, quality 80. Chat attachments are **uncompressed** (up to 25 MB). Group images are 1600 px. The load test does **not** upload to Storage; that is listed as untested in every report.

## 8. Risks ranked for 8–15k users (Inference from sections 2–5)

| # | Risk | Why it scales badly | Simulator signal |
|---|---|---|---|
| 1 | Global `users isOnline==true` listener on every session | Reads grow with concurrency × user-doc writes | `readsBy.onlineUsersGlobal` |
| 2 | Global `open_gigs` listener on every session | Reads grow with open gigs × sessions, plus fan-out on every gig change | `readsBy.openGigsGlobal`, reads/session across stages |
| 3 | `onOpenGigPosted` reads all available workers per gig | Cost per gig grows linearly with the user base | plan estimate (functions); `--with-functions` to execute |
| 4 | Single-slot select without a transaction | Double tap or two devices can reassign the gig, and a worker is briefly told they won | `race.duplicateExclusiveAssignment` |
| 5 | `open_gigs` rule allows any field edit while open | Integrity and abuse | `security.editForeignOpenGig` |
| 6 | Apply = arrayUnion on one gig doc | Hot-document write contention on popular gigs | `race.noLostApplications`, apply p95 |
| 7 | Per-room unread listeners | Listener count grows with chat rooms per user | `readsBy.roomUnread` |
| 8 | Quick-gig matching on the host phone | Unbounded online-user query every 15 s per searching host | not simulated (documented) |

## 9. Workload assumptions (no analytics exist)

80% workers and 20% hosts. 5% of daily users are new. Sessions per user: 1 (55%), 2 (30%), 3 (15%). Median session 150 s. Hourly curve with a morning ramp, lunch bump and a 19:00 peak. Intents: browse 35%, explore 20%, apply 15%, chat 15%, post 10%, register 5%. All of this lives in `config/workload.json`, is printed in every plan and report, and should be replaced with real numbers once available (for example the share of `users.availableForGigs` and gigs posted per day from Firestore).
