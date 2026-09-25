# Source-Driven Documentation Phase 2 Implementation

Status: Implementation and automated validation complete. No commit was created.

## Scope and Outcome

Expanded the source-driven catalog from 10 to 26 concepts by annotating 16 meaningful source surfaces. The seven Phase 1 UI-help gaps now have explicit dispositions in [UI_Help_Documentation_Matrix.md](UI_Help_Documentation_Matrix.md), and the consistency report has been updated. The existing schema and generator were sufficient; no generator changes or broad documentation migration were needed.

The three legacy help keys were reviewed against current source:

| Key | Decision | Source evidence |
| --- | --- | --- |
| `UI_HELP_ENCOUNTER` | REMOVE | No current consumer. Encounter mode uses `UI_HELP_PREDIB_MODE`; historical award encounter evidence uses `UI_HELP_ENCOUNTER_EVIDENCE`. |
| `UI_HELP_REASON` | REUSE | `ledger.adjust.reason` at `Ledger.AdminAdjust` references the key. |
| `UI_HELP_SETUP_ASSISTANT` | REUSE | `setup.assistant.readiness` at `SetupAssistant.Evaluate` references the key. |

## Seven Gap Dispositions

| Phase 1 gap | Disposition | Implementation |
| --- | --- | --- |
| Player RCLootCouncil status | `ADD_DOC_CONCEPT` | `player.status` documents the localized status badge and optional Standalone behavior. |
| Officer review requests | `ADD_HELP` | Localized help is attached to the queue heading and review columns. |
| RCLootCouncil historical reconciliation | `ADD_HELP` | Localized help covers candidate status, winner, classification, evidence, review, and the read-only preview. |
| Announcements | `ADD_HELP` | Public and Officer channel destinations and reminder controls have localized audience/scope descriptions. |
| Player raid readiness | `ADD_DOC_CONCEPT` | `player.readiness` documents the evaluator and the Player-facing readiness explanation. |
| Ledger and audit history columns | `ADD_HELP` | Shared localized audit help is used across Player, Officer, and log tables. |
| Raid Relay | `ADD_HELP` | The real Officer/GM raid-reminder controls are documented. The distinct guild-state broadcast remains Developer-only; source has no award proposal/confirmation or one-debit UI. |

## Generated Artifacts

Regenerated and checked all eight files under `docs/generated/`:

- `player-guide.md`
- `officer-guide.md`
- `gm-guide.md`
- `developer-reference.md`
- `ui-reference.md`
- `terminology.md`
- `documentation.csv`
- `documentation.json`

## Validation

- Documentation validation: 26 concepts, 0 errors, 0 warnings, 0 missing enUS/frFR values, and 0 duplicate IDs.
- Windows PowerShell 5.1 Pester 3.4.0: 25 passed, 0 failed.
- PowerShell 7.6.6 Pester 3.4.0: 25 passed, 0 failed.
- Cross-version isolated generation: all 8/8 artifact SHA-256 hashes match between Windows PowerShell 5.1 and PowerShell 7.
- Generator `-Generate` and `-Check`: passed; generated artifacts are current.
- Focused Fengari UI-help, relay, options, and Player UI run before the last test addition: 18 passed, 0 failed. Final UI-help spec including Phase 2 bilingual assertions: 11 passed, 0 failed.
- Full Fengari suite after all changes: 654 passed, 1 failed across 140 files. The sole failure is the pre-existing heartbeat timer assertion at `tests/integration/predibs_sync_recovery_spec.lua:50` (`expected 1, got 2`). It matches the previously documented failure and was not changed.
- `git diff --check`: passed; Git emitted only its existing LF-to-CRLF working-copy notices.

The editor diagnostics provider still reports an unclosed function at the `player.status` annotation in `src/ui/PlayerUI.lua`. The current source has a single, closed function declaration; the focused Player UI tests and full Fengari suite load it successfully. The diagnostic appears stale and remains an editor-cache follow-up, not a reproduced Lua syntax failure.

## Behavior and Data Boundaries

Changes are documentation annotations, English/French help strings, table/tooltips, and existing options descriptions only. No ledger or loot-calculation behavior, authorization decision, business rule, RCLootCouncil decision, SyncV2 protocol behavior, SavedVariables schema, or data value was changed. Runtime permissions remain controlled by the existing protected-action service; documentation metadata is not used for authorization.

The two pre-existing unrelated untracked audit files were left untouched. No files were staged or committed.

## Phase 3 Recommendations

- Validate the revised help in the Retail client with Player, Officer, and Guild Master accounts, especially the history and reminder controls.
- Revisit the matrix when those controls or their authority boundaries change; keep protocol internals Developer-only.
- Consider further source annotations only when they clarify a user-visible concept or a meaningful maintainer contract; avoid a broad migration.
