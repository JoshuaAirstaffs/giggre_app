---
target: group chat screens
total_score: 29
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 1
target_identity: "file:/Users/admin/giggre_app/lib/features/group_chat"
timestamp: 2026-11-06T19-07-50Z
slug: lib-features-group-chat
---
Method: design review only (native). Source review of group-chat branch after layout, clarify, typeset, colorize, adapt, harden, optimize, polish passes.

## Design Health Score
| # | Heuristic | Score | Key Issue |
|---|---|---|---|
| 1 | Visibility of System Status | 3 | No photo upload progress, no group "seen" |
| 2 | Match System / Real World | 3 | Plain, specific copy |
| 3 | User Control and Freedom | 3 | Swipe-back fixed; no undo after remove |
| 4 | Consistency and Standards | 3 | One search; location card vs 1:1 map remains |
| 5 | Error Prevention | 3 | Blocked filtered; limit explained |
| 6 | Recognition Rather Than Recall | 3 | Rule visible; long-press-only actions remain |
| 7 | Flexibility and Efficiency | 2 | No reply/mentions/in-group search/group-from-gig |
| 8 | Aesthetic and Minimalist Design | 3 | Groups without photos identical |
| 9 | Error Recovery | 3 | Failed photo lost |
| 10 | Help and Documentation | 3 | "Who you can add" explainer |
| Total | | 29/40 | Good |

## Design Specificity Verdict
Still category-generic: no trust signals, no gig context, location weaker than 1:1.

## Priority Issues
1. [P1] No trust signals on members (verified, rating from publicProfiles). /impeccable bolder
2. [P2] Groups without photos look identical; monogram on id-derived color. /impeccable colorize
3. [P2] Location text card vs 1:1 map; failed photo lost (needs retry). /impeccable harden
4. [P2] Copy/Report only via long-press, no reply; one-time hint. /impeccable onboard

## Persona Red Flags
- Casey: picker Next still top-right.
- Jordan: no hint that messages can be long-pressed.
- Alex: New chat now 2 taps; no mentions/reply/search.
- Hana: no group-from-gig; no verification on members.

## Minor Observations
Fixed 220x260 crop; panorama softness at 1.5x decode; "…" names loading; 1:1 chat lacks photo labels and avatar decode.
