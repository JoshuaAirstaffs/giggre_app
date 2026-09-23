# Tutorial Demo — Narration Script

Voiceover copy for every slide of **How Giggre Works** and the five **Gig Worker** demos. Companion to the recordings already in `assets/audio/tutorial/` for the Host demos (see `controller/demo_audio_controller.dart`).

**On-screen names ≠ code names** — the mock data's Dart identifiers don't match the names actually shown on screen. Use the display names below:

| Code identifier | Displayed as |
|---|---|
| `mockMariaSantos` (Host) | **Emily Carter** |
| `juanDelaCruz` (Worker) | **Mike Johnson** |
| `carloGarcia` (Worker) | **Alex Turner** |
| `markReyes` (Worker) | **David Kim** |

**Recording pattern note:** the Host demos don't narrate every slide — only the title card, one or two setup slides, and the final outcome slide get audio (`_narrationAssetsBySequence` in `demo_audio_controller.dart` spreads N files across the first N‑1 steps + the last step; everything in between plays silently under the background music). Every slide below has a line so you can record all of them, but if you want to match the Host demos' pacing, you only strictly need the ★ slides — the rest can stay silent.

Suggested file naming (matching the existing `01_Host_Offered_Gig.mp3` convention):
`01_Intro_How_It_Works.mp3`, `01_Worker_Active_Mode.mp3`, `01_Worker_Quick_Gigs.mp3`, `01_Worker_Open_Gigs.mp3`, `01_Worker_Toolchest.mp3`, `01_Worker_Offered_Gig.mp3`, etc.

---

## Intro: How Giggre Works
`sequences/how_giggre_works_sequence.dart` — id `demo.intro.howItWorks` — 12 slides, all ★ (pure explainer, no live-action beats to stay silent under)

1. **★ welcome** — *Welcome to Giggre*
   > "Welcome to Giggre — every gig, right in your area. Find work, or get trusted help nearby, fast, fair, and local."

2. **★ twoSided** — *One app, two sides*
   > "One app, two sides. Every gig on Giggre connects a Host who needs something done with a Worker ready to do it. Gig Hosts post work and get it done by a nearby worker. Gig Workers find gigs that match their skills, and get paid."

3. **★ hostQuickGig** — *Quick Gig (Gig Host)*
   > "For Gig Hosts: a Quick Gig is instant — no specific skill needed. Post it, and get matched with a nearby worker right away."

4. **★ hostOpenGig** — *Open Gig (Gig Host)*
   > "An Open Gig is for when you need a specific skill or qualification. Post it, let skilled workers apply, and pick the one you want."

5. **★ hostOfferedGig** — *Offered Gig (Gig Host)*
   > "An Offered Gig goes straight to a worker you already know or trust — no need to post it publicly."

6. **★ workerActiveMode** — *Active Mode (Gig Worker)*
   > "Now for Gig Workers. Active Mode puts you online, so hosts can see you're available for work right now."

7. **★ workerQuickGigs** — *Quick Gigs (Gig Worker)*
   > "Quick Gigs are instant opportunities that don't need a specific skill. Take it, or pass — the choice is yours on every one."

8. **★ workerOpenGigs** — *Open Gigs (Gig Worker)*
   > "Open Gigs let you browse the map or list, and take any gig once your verified skills match what it needs."

9. **★ workerToolchest** — *My Toolchest (Gig Worker)*
   > "My Toolchest is where you manage your skills. Add a new one any time — it just needs admin approval before it unlocks gigs that require it."

10. **★ workerOfferedGig** — *Offered Gig (Gig Worker)*
    > "And an Offered Gig arrives straight from a host you've worked with before — accept it right from the notification."

11. **★ trust** — *Fast, fair, and local*
    > "Fast, fair, and local: verified accounts and skills you can trust, gigs matched to workers nearby, and clear pay and status every step of the way."

12. **★ getStarted** — *That's Giggre in a nutshell*
    > "And that's Giggre in a nutshell. Pick a Host or Worker demo below to see it in action."

---

## Worker: Active Mode
`sequences/worker_active_mode_sequence.dart` — id `demo.worker.activeMode` — 3 slides

1. **★ titleCard** — *Active Mode*
   > "Watch Mike go online, so hosts can see he's available for work."

2. toggleOn — *dashboard, toggle flips on*
   > "Right now Mike's Active Mode is off — hosts can't see him as available. Watch what happens when he switches it on."

3. **★ online** — *You're online and available for work*
   > "He's online now, and available for work. Active Mode lets Gig Hosts know he's ready to take on a gig."

---

## Worker: Quick Gigs
`sequences/worker_quick_gigs_sequence.dart` — id `demo.worker.quickGigs` — 6 slides

1. **★ titleCard** — *Quick Gigs*
   > "Watch Mike receive — and take — an instant Quick Gig offer."

2. toggleOn — *dashboard, Quick Gigs toggle flips on*
   > "Mike's already online. Now he turns Quick Gigs on, so instant offers can start coming in."

3. explain — *What are Quick Gigs?*
   > "Quick Gigs are instant opportunities that don't need a specific skill. Mike can Take It or Pass on each one — availability and distance from the host may factor into which ones he sees."

4. offerArrives — *Pick up my package, $20*
   > "A Quick Gig just came in: pick up a package from the nearby courier office and deliver it — for twenty dollars."

5. accepted — *Gig taken!*
   > "Mike takes it — gig taken!"

6. **★ declineInfo** — *Good to know*
   > "Good to know: acceptance and performance may be considered for future Quick Gigs, and declines are monitored — check Decline Information for details. These are illustrative factors, not a guarantee of the exact matching algorithm."

---

## Worker: Open Gigs
`sequences/worker_open_gigs_sequence.dart` — id `demo.worker.openGigs` — 7 slides

1. **★ titleCard** — *Open Gigs*
   > "Watch a worker browse Open Gigs, and take one that matches their verified skills."

2. mapView — *map with gig pins*
   > "Open Gigs show up on the map, wherever nearby work is posted."

3. listView — *same gigs, list view*
   > "Switch to the list view to scan them at a glance instead."

4. detailNoMatch — *Fix electrical outlet, Alex Turner, missing skill*
   > "Alex opens 'Fix electrical outlet' — but he's missing the Electrician skill, so he can't take it. He can pass any time before he's selected."

5. explain — *Only verified skills unlock Take Gig*
   > "The Take Gig button stays greyed out until your verified skills match what the gig needs — manage your skills any time in My Toolchest."

6. detailMatch — *same gig, Mike Johnson, skill verified*
   > "Mike opens the same gig — he's a verified Electrician, so the skill matches, and Take Gig is ready to go."

7. **★ applied** — *applied*
   > "He takes it — Mike's applied for the gig."

---

## Worker: My Toolchest
`sequences/worker_toolchest_sequence.dart` — id `demo.worker.toolchest` — 7 slides

1. **★ titleCard** — *My Toolchest*
   > "Watch Mike add a new skill to his Toolchest, and get it approved."

2. navigate — *Profile → My Toolchest*
   > "From his profile, Mike opens My Toolchest."

3. existingSkills — *Electrician (Approved), General Assistance (Approved)*
   > "He already has two approved skills: Electrician, and General Assistance."

4. addSkillPending — *Carpentry (Pending)*
   > "He adds Carpentry — it goes in as Pending, waiting on admin approval."

5. addSkillApproved — *Carpentry (Approved)*
   > "Once it's reviewed, Carpentry comes back Approved."

6. reminder — *Keep your skills updated*
   > "Add new skills any time in My Toolchest — just remember, each one needs admin approval before it unlocks gigs that require it."

7. **★ backToOpenGig** — *Fix electrical outlet*
   > "Now back on 'Fix electrical outlet' — with his Toolchest up to date, Mike's ready to take any gig his verified skills unlock."

---

## Worker: Offered Gig
`sequences/worker_direct_offer_sequence.dart` — id `demo.worker.directOffer` — 5 slides

1. **★ titleCard** — *Offered Gig*
   > "Watch Mike receive — and accept — a gig offered directly to him."

2. notification — *New Gig Offer from Emily Carter*
   > "A notification comes in: Emily Carter has a new gig offer for him — installing a ceiling light."

3. offerDetail — *Install ceiling light, $95, Emily Carter*
   > "The details: install a new ceiling light in the living room, ninety-five dollars, from Emily Carter."

4. accepted — *Offer accepted!*
   > "Mike accepts — and Emily's notified right away."

5. **★ reminder** — *Never miss an Offered Gig*
   > "Never miss an Offered Gig — keep Giggre notifications enabled so hosts can reach you directly."
