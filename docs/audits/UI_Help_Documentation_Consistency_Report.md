# UI Help and Documentation Consistency Report

## Scope and Outcome

This audit reviewed localized help and role documentation for Player, Officer, Guild Master, and Developer UI surfaces. The inventory is recorded in [UI_Help_Documentation_Matrix.md](UI_Help_Documentation_Matrix.md).

The matrix contains 35 reviewed UI concept groups: 26 improved, 7 with follow-up gaps, 1 already consistent, and 1 intentionally technical-only. The 81 help-related localization keys in enUS and frFR are paired with no missing keys. Tooltips were kept concise and focused on meaning, authority, scope, consequence, or next action; longer workflows remain in the role guides.

No ledger, governance, permission, SyncV2 protocol, RCLootCouncil decision, SavedVariables schema, or loot-calculation behavior was intentionally changed as part of the help audit.

## Twenty Major Improvements

1. Clarified that a player's balance belongs to the current guild and active season, and distinguished requests from finalized awards or authorized adjustments.
2. Explained that submitting a Pre-Dib expresses interest; it neither awards loot nor spends Dibs.
3. Distinguished the Encounter request mode, which requires matching raid and difficulty context, from Wild Open policy.
4. Added meaning and next-step guidance for player request status and history scope.
5. Explained that switching between season and all-season history changes the view, not stored records.
6. Clarified that opening Guild Setup is read-only and that activation is a separate GM-authorized action.
7. Explained why detected historical evidence must be reviewed before initial setup and why uncertain evidence should remain unresolved.
8. Defined Include and Exclude in terms of the starting balance without implying that source history is deleted.
9. Explained the authority and review preconditions for Initialize DIBS / Continue Setup.
10. Reworked Setup Assistant help to explain blockers, raid-readiness impact, and the next safe action rather than repeat column labels.
11. Clarified that Guided Setup reuses existing pages and does not itself make decisions or initialize the guild ledger.
12. Explained Rank Allocation as a selected-season rule and clarified that rule edits do not rewrite historical transactions.
13. Distinguished a Dibs season from a game season and clarified that activating a new period preserves prior history.
14. Made Add and Remove Dibs help explicit about current-season scope and audit recording.
15. Explained that adjustment reasons are retained with actor, target, previous balance, and resulting balance, without editing original history.
16. Connected unavailable or behind synchronization state to the risk of missing canonical guild updates.
17. Explained that peer diagnostics show the latest response observed by this client and may be stale for offline or unresponsive peers.
18. Clarified that Loot Eligibility reflects active guild policy and why a category may be blocked or require review.
19. Separated RCLootCouncil response presentation mapping from Dibs policy eligibility.
20. Improved operational guidance for backups and restore confirmation, profile scope, import/export sensitivity, the local-only Developer Sandbox, and bounded in-memory debug logs.

## Open Gaps

The matrix keeps these seven areas visible rather than treating them as complete:

- Player-facing explanation and next action for optional RCLootCouncil status.
- Officer review-request column help and player next-action guidance.
- Historical RCLootCouncil reconciliation preview/finalize and evidence-column help.
- Announcement channel and audience scope.
- Player raid-readiness field help and consistent next steps.
- Consistent localized help for ledger and audit-history columns.
- Raid Relay authority, one-debit effect, and unavailable-state help.

Data health already has adequate introductory guidance and remains `OK`. Protocol implementation terms remain `TECHNICAL_ONLY` in diagnostics; they should not leak into normal player help.

## Documentation Alignment

- Player help and role guidance were aligned across the English and French Player Guides, especially balance scope, Pre-Dib ownership, and read-only player capabilities.
- Officer and GM guides were aligned in English and French around setup authority, audited adjustments, review workflows, and related operations.
- Developer Sync protocol documentation now distinguishes normal UI terminology from technical state and implementation terminology.
- The matrix maps each reviewed concept to the relevant role documentation and records the seven follow-up gaps.

## Validation

- `tests/unit/ui_help_content_spec.lua`: 10 passed, 0 failed.
- Full Fengari suite: 653 passed, 1 failed across 140 files. The failure is `tests/integration/predibs_sync_recovery_spec.lua:50`, “uses AceComm registration and AceTimer for one bounded anti-entropy heartbeat” (`expected 1, got 2`). Running that spec alone reproduces the same failure; it is the previously documented timer-count issue and is unrelated to UI-help content.
- Locale parity: 81 help-related keys in enUS and 81 in frFR; no unmatched keys.
- `git diff --check`: passed.
- The editor diagnostics still return `undefined field 'L' on class 'Dibs'` entries for PlayerUI locations whose current source now uses the local `helpText` alias. A source search confirms the direct help-key accesses were removed, but the diagnostics did not refresh after the rewrite; treat PlayerUI static analysis as unresolved until the editor analysis cache is refreshed and checked again.

## Follow-Up

Address the seven gaps above in a future documentation pass, prioritizing player readiness/status and destructive or authority-sensitive Officer workflows. Refresh the PlayerUI diagnostics before treating the static-analysis gate as clean.