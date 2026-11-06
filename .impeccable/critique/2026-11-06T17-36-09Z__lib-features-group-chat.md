---
target: group chat screens
total_score: 26
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
target_identity: "file:/Users/admin/giggre_app/lib/features/group_chat"
timestamp: 2026-11-06T17-36-09Z
slug: lib-features-group-chat
closed: true
---
Method: design review only (detector not applicable, native platform). Source review; screens need a signed-in Firebase session and were not rendered.

## Design Health Score
| # | Heuristic | Score | Key Issue |
|---|---|---|---|
| 1 | Visibility of System Status | 3 | No photo upload progress, no group "seen" |
| 2 | Match System / Real World | 3 | Plain copy |
| 3 | User Control and Freedom | 3 | No undo after removing a member |
| 4 | Consistency and Standards | 2 | Magnifier = Find people vs "Search chats" field; location card vs 1:1 map |
| 5 | Error Prevention | 3 | Limits enforced, confirms on destructive actions |
| 6 | Recognition Rather Than Recall | 2 | Picker hides non-chatted people silently; icon-only New group |
| 7 | Flexibility and Efficiency | 2 | No reply, mentions, in-group search, group-from-gig |
| 8 | Aesthetic and Minimalist Design | 3 | Crowded Chats header |
| 9 | Error Recovery | 3 | Failed photo is lost |
| 10 | Help and Documentation | 2 | Add rule unexplained until failure |
| Total | | 26/40 | Acceptable |

## Design Specificity Verdict
Competent but category-generic messenger; nothing reflects gigs, host/worker roles, verification, or location. Matches the 1:1 chat visually.

## Priority Issues
1. [P1] Chats header overloaded (8 controls before content); magnifier (Find people) vs "Search chats" field read as the same thing. Fix: one search field with a "Find on Giggre" row; one New action (chat/group), thumb-zone. /impeccable layout
2. [P1] Add rule (accepted chats only) invisible until it fails. Fix: permanent hint under picker search; empty state action "Message someone first". /impeccable clarify
3. [P1] Timestamps grey.shade400 10pt (~1.9:1) and sender names grey.shade500 11.5pt (~2.6:1) fail AA. Fix: onSurface ~60%, name >=12pt w600; fix 1:1 chat too. /impeccable audit
4. [P2] Groups without photos look identical (same icon/tint as person placeholder). Fix: monogram on id-derived color. /impeccable colorize
5. [P2] Group location is a text card (1:1 has map); failed photo upload disappears. Fix: reuse map bubble; failed photo stays with retry. /impeccable harden

## Persona Red Flags
- Casey: New group + Next top-right; 42px round buttons; 1.9:1 timestamps.
- Jordan: icon-only New group; two searches; long-press-only Copy/Report.
- Hana (Gig Host, crew): no group-from-gig/favorites; applicant-only workers missing unexplained; no verification/rating on members.

## Minor Observations
Fixed 220x260 image crop; "…" member names while loading; compact rename button; plain day divider vs pill system lines; Admin badge contrast in dark mode.

## Questions to Consider
Group from a gig? Show verified/rating on members? Fold New group into one New action?
