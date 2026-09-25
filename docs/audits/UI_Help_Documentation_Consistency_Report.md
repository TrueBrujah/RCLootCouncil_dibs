# UI Help and Documentation Consistency Report

## Scope and Outcome

This audit reviewed localized help and role documentation for Player, Officer, Guild Master, and Developer UI surfaces. The inventory is recorded in [UI_Help_Documentation_Matrix.md](UI_Help_Documentation_Matrix.md).

The matrix contains 35 reviewed UI concept groups: 33 improved or explicitly resolved, no open gaps, 1 already consistent, and 1 intentionally technical-only. The Phase 2 catalog contains 26 source-annotated concepts with complete enUS/frFR help and labels. Tooltips remain concise and focused on meaning, authority, scope, consequence, or next action; longer workflows remain in the role guides.

No ledger, governance, permission, SyncV2 protocol, RCLootCouncil decision, SavedVariables schema, or loot-calculation behavior was changed. Phase 2 adds documentation annotations, localized help, and presentation descriptions only.

## Phase 1 Improvements Retained

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

## Phase 2 Dispositions

- Player RCLootCouncil status: `ADD_DOC_CONCEPT`; `player.status` is attached to `Dibs.PlayerUI.GetStatusPresentation`, and localized optional-integration help is attached to the status badge.
- Officer review requests: `ADD_HELP`; localized help is wired to the Officer queue heading and columns.
- RCLootCouncil history reconciliation: `ADD_HELP`; localized help covers status, winner, classification, evidence, and review columns while the section explains read-only preview.
- Announcements: `ADD_HELP`; public and Officer channel controls use localized help, and the raid reminder setting/send action have their own localized explanation.
- Player raid readiness: `ADD_DOC_CONCEPT`; `player.readiness` is attached to the evaluator and the player explanation uses readiness help.
- Ledger and audit history: `ADD_HELP`; a shared localized audit description is used in Player, Officer, and log tables.
- Raid Relay: `ADD_HELP` for the actual Officer/GM raid-reminder control. The separate guild-state broadcast remains Developer-only; source contains no award proposal/confirm or one-debit UI.

Legacy key decisions: `UI_HELP_ENCOUNTER` is `REMOVE` because it has no current consumer; Encounter mode and historical encounter evidence already use `UI_HELP_PREDIB_MODE` and `UI_HELP_ENCOUNTER_EVIDENCE`. `UI_HELP_REASON` is `REUSE` at `Ledger.AdminAdjust`; `UI_HELP_SETUP_ASSISTANT` is `REUSE` at `SetupAssistant.Evaluate`.

Data health remains `OK`. Protocol implementation terms remain `TECHNICAL_ONLY` and are excluded from normal Player documentation.

## Documentation Alignment

- Player help and role guidance were aligned across the English and French Player Guides, especially balance scope, Pre-Dib ownership, and read-only player capabilities.
- Officer and GM guides were aligned in English and French around setup authority, audited adjustments, review workflows, and related operations.
- Developer Sync protocol documentation now distinguishes normal UI terminology from technical state and implementation terminology.
- The matrix maps reviewed concepts to role documentation, records all seven Phase 2 dispositions, and documents the three legacy-key decisions.

## Validation

- Documentation validation: 26 concepts, 0 errors, 0 warnings, 0 locale gaps, and 0 duplicate IDs.
- Pester 3.4.0 under Windows PowerShell 5.1: 25 passed, 0 failed; under PowerShell 7.6.6: 25 passed, 0 failed.
- Cross-version temporary generation and SHA-256 comparison: 8/8 generated artifacts match.
- `-Generate` and `-Check`: passed; all eight generated artifacts are current.
- Focused Fengari UI-help, relay, options, and Player UI run before the last test addition: 18 passed, 0 failed. Final UI-help spec including Phase 2 bilingual assertions: 11 passed, 0 failed.
- Full Fengari suite: 654 passed, 1 failed across 140 files. The only failure is `tests/integration/predibs_sync_recovery_spec.lua:50`, “uses AceComm registration and AceTimer for one bounded anti-entropy heartbeat” (`expected 1, got 2`). This is the known timer-count issue and was not changed.
- `git diff --check`: passed; Git emitted only its existing LF-to-CRLF working-copy notices.
- The editor diagnostics provider continues to report a stale unclosed-function error at the `player.status` annotation in `PlayerUI.lua`; the current source is syntactically accepted by focused and full Fengari runs. Refresh the editor analysis cache before treating that diagnostic as resolved.

## Follow-Up

Phase 3 should validate these concise descriptions in the retail client with Player, Officer, and GM accounts, then review newly added UI concepts when the corresponding controls or authority boundaries change. Do not broaden this inventory into a full documentation migration without a separately approved scope.