---
target: group chat screens
total_score: 30
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 0
target_identity: "file:/Users/admin/giggre_app/lib/features/group_chat"
timestamp: 2026-11-06T19-15-03Z
slug: lib-features-group-chat
---
Method: design review only (native). Source review after trust signals, initials avatars, shared map bubble, failed-send retry, bottom Next.

## Design Health Score
| # | Heuristic | Score | Key Issue |
|---|---|---|---|
| 1 | Visibility of System Status | 3 | No upload progress, no group "seen" |
| 2 | Match System / Real World | 3 | Ratings in app wording |
| 3 | User Control and Freedom | 3 | No undo after removing a member |
| 4 | Consistency and Standards | 3 | 1:1 chat now lags group chat |
| 5 | Error Prevention | 3 | Solid |
| 6 | Recognition Rather Than Recall | 3 | Long-press-only actions |
| 7 | Flexibility and Efficiency | 2 | No reply/mentions/search/group-from-gig |
| 8 | Aesthetic and Minimalist Design | 3 | Clean; rating line density acceptable |
| 9 | Error Recovery | 4 | Failed sends kept with retry/remove |
| 10 | Help and Documentation | 3 | Explainer and guiding empty states |
| Total | | 30/40 | Good |

## Design Specificity Verdict
Now reads as Giggre: verified + "as Gig Worker/Host" ratings, shared map. Remaining gap: no gig connection.

## Priority Issues
1. [P2] Groups not connected to gigs (start from gig, share gig card). /impeccable shape
2. [P2] Message actions hidden (long-press), no reply; one-time hint. /impeccable onboard
3. [P2] 1:1 chat lacks photo labels, avatar decode sizing, failed-photo retry. /impeccable harden

## Persona Red Flags
- Casey: bottom Next with keyboard unverified.
- Jordan: no long-press hint.
- Alex: New chat 2 taps; no mentions/reply/search.
- Hana: trust visible now; no group-from-gig.

## Minor Observations
Device-unverified: initials in busy list, bottom Next + keyboard, map in rounded bubbles. Panorama softness. "…" member names.
