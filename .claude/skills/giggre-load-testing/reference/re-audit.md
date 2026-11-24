# Re-audit after app changes

The simulator is only as faithful as `tools/loadtest/docs/architecture-audit.md`. Redo the relevant part when any of these change:

| Changed | Look at | Update |
|---|---|---|
| `lib/features/gig_worker/presentation/widgets/gig_map_section.dart` (list/map queries, apply) | listener queries, apply guard and write | `session.mjs appOpen`, `actions.mjs applyTo/visibleGigs` |
| `lib/features/gig_host/presentation/post_*_gig_screen.dart`, gig models | fields written on create | `actions.mjs postGig`, `seed.mjs` gig shape |
| `gig_detail_sheet.dart` (`_selectWorker`), `edit_gig.dart`, `working_ui.dart`, payment sheets | transactions vs plain updates, statuses | `actions.mjs selectWorker/editGig/advance*`, `race.mjs` |
| `lib/screens/chat/chat.dart`, shells, `home_chat.dart` | message fields, badges, listeners | `actions.mjs chatConversation`, `session.mjs` badges |
| `mode_shell.dart`, `worker_shell.dart`, `host_shell.dart`, `home_screen.dart`, providers | what loads per session | `session.mjs appOpen`, `costModel.mjs BASELINE_*` |
| `register_screen.dart`, `welcome_screen.dart` | user doc fields | `actions.mjs register`, `seed.mjs` user shape |
| `firestore.rules` | anything | Run `smoke`: rule changes show up as `permission-denied` (unexpected) or as probe results. |
| `functions/src/*` triggers | fan-out per write | `costModel.mjs` function estimates. Audit section 5. |

## Procedure

1. Diff since the audit commit: `git diff <audit-commit> -- lib functions/src firestore.rules`. The audit header gives the date and branch.
2. For each changed flow, confirm the exact path, the fields, the query shape (`where` / `orderBy` / `limit`, collection or collectionGroup), whether it is a get or a listener, and whether it is a transaction, batch or plain write. Cite `file:line`.
3. Update the scenario code to match. **Do not invent fields.** If something is unclear, read the code; don't guess.
4. Update the audit doc: date, facts, risks table.
5. Run `node cli.mjs validate` and `node cli.mjs smoke`. Explain any new unexpected errors before asking for a stage approval.
6. Tell the user that plan hashes changed, so earlier approvals are void (they always are after a config change, but code changes don't alter the hash, so say it explicitly).
