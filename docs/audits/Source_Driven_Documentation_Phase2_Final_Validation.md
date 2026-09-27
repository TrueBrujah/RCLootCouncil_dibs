# Source-Driven Documentation Phase 2 Final Validation

- Date: 2026-09-25
- Mode: Read-only validation. This report is the only file created during this final-validation pass. No source, tests, generated artifacts, staging area, or commits were changed.

## Results

| Gate | Result | Evidence |
| --- | --- | --- |
| Concept catalog | PASS | 26 unique canonical IDs; 0 validation errors/warnings; every concept binds to a current Lua function, module, source line, and symbol. Concepts describe existing behavior rather than padding the count. |
| 7 gap dispositions | PASS | All seven matrix rows have explicit dispositions and current-source evidence; no `MISSING` row remains. Details below. |
| 3 orphan-key dispositions | PASS | `UI_HELP_ENCOUNTER` = REMOVE; `UI_HELP_REASON` = REUSE; `UI_HELP_SETUP_ASSISTANT` = REUSE. Locale validation has 0 orphan warnings. |
| Validator integrity | PASS | Existing Pester fixtures cover duplicate/bad IDs, locale omissions, unknown help keys, invalid audience/permission/scope/version, and Developer-to-Player leakage. A disposable source-copy fixture injected `UI_HELP_ORPHAN_PROBE` and received exactly one `orphan-help-key` warning. Detector remains active in `DibsDocumentation.psm1`. |
| Localization | PASS | enUS and frFR load into `Dibs.L`; they are the only `src/locales` catalogs. Pester locale checks and source catalog validation pass; strict UTF-8 and mojibake scans pass. |
| Role filtering | FAIL | Officer, GM, and Developer concept placement passes. Player output contains developer implementation provenance for its player-visible `sync.status` concept; details below. |
| Generated artifacts | PASS | All eight named artifacts exist; generator `-Check` reports current. Pester deterministic-render/generation tests pass. JSON/CSV rendering tests pass. |
| PS5.1 | PASS | Pester 3.4.0: 25 passed, 0 failed. |
| PS7.6.6 | PASS | Host confirmed as PowerShell 7.6.6; Pester 3.4.0: 25 passed, 0 failed. |
| Cross-version determinism | PASS | Temporary-root generation compares all eight SHA-256 hashes: 8/8 MATCH. |
| Lua regression | PARTIAL | Fresh full suite: 654 passed, 1 failed across 140 files. The sole failure is confirmed pre-existing and reproduced exactly in isolation. |
| PlayerUI diagnostic | LUACONTRACT_DIAGNOSTIC | Current editor diagnostics are only unknown custom `---@doc.*` annotations at `PlayerUI.lua`; no current unclosed-block diagnostic. Fengari loads and tests PlayerUI successfully. |
| Business behavior isolation | PASS | Source diff is annotations, localized help, and presentation descriptions/tooltips. No business/runtime mutation was found. |
| Worktree scope | PASS | 28 tracked Phase 2 files; no staged changes. The two pre-existing untracked audits remain present and untouched. No commit was created. |
| Added TODO classification | STALE_AGENT_METADATA | No Phase 2 TODO/FIXME was added. The identifiable quoted item in the older installation audit is explicitly external session/agent-tool metadata, not unfinished repository work. |

## Catalog

The 26 canonical IDs are: `guild.ledger.status`, `guild.season`, `guild.setup`, `ledger.adjust`, `ledger.adjust.reason`, `ledger.audit.history`, `ledger.balance`, `loot.eligibility`, `officer.audit.timeline`, `officer.review.requests`, `player.readiness`, `player.status`, `predibs.announcement.channels`, `predibs.encounter.mode`, `predibs.request`, `rank.allocation`, `rclootcouncil.history.reconciliation`, `rclootcouncil.response.mapping`, `setup.assistant.readiness`, `setup.reconciliation`, `sync.coordinator`, `sync.peer.status`, `sync.protocol.state`, `sync.raid.relay`, `sync.raid.reminder`, and `sync.status`.

Current model findings: 0 errors, 0 warnings, 0 duplicate IDs, 0 missing enUS values, and 0 missing frFR values. The temporary orphan fixture confirmed that an unreferenced localized help key still produces an `orphan-help-key` warning.

## Gap Dispositions

| Original gap | Disposition | Source evidence |
| --- | --- | --- |
| Player RCLootCouncil status | `ADD_DOC_CONCEPT` | `player.status` is bound to `Dibs.PlayerUI.GetStatusPresentation`; localized optional-integration help is attached to the Player status badge. |
| Officer review requests | `ADD_HELP` | `UI_HELP_REVIEW_REQUESTS` is wired to the Officer request heading and columns; `Disputes.ListForOfficer` owns the projection. |
| RCLootCouncil history reconciliation | `ADD_HELP` | Localized section and status/winner/classification/evidence/review tooltips are wired to the history preview; `Dibs.RCLootCouncil.GetHistoryRows` is annotated. |
| Announcements | `ADD_HELP` | Localized audience/channel help is wired to public and Officer channel controls; raid reminder controls have their own help. `Dibs.PreDibs.GetAnnouncementSettings` is annotated. |
| Player raid readiness | `ADD_DOC_CONCEPT` | `player.readiness` is bound to `Readiness.Evaluate`; Player-facing readiness explanation uses localized help. |
| Ledger and audit history columns | `ADD_HELP` | Shared localized audit help is used by Player, Officer, and log history tables; `Ledger.GetHistory` and `Disputes.GetTimeline` are annotated. |
| Raid Relay | `ADD_HELP` | The actual RCLootCouncil-options reminder message/send controls are localized via `Dibs.RaidRelay.SendReminder`. `Dibs.RaidRelay.Broadcast` is Developer-only guild-state sync; no proposal/confirm or one-debit UI exists. |

The matrix and Pester test explicitly enumerate all seven rows and reject any remaining `MISSING` disposition, so the gaps are not hidden from validation.

## Legacy Help Keys

| Key | Disposition | Evidence |
| --- | --- | --- |
| `UI_HELP_ENCOUNTER` | REMOVE | No current first-party consumer. Encounter mode uses `UI_HELP_PREDIB_MODE`; historical encounter evidence uses `UI_HELP_ENCOUNTER_EVIDENCE`. The obsolete key is absent from both locale catalogs. |
| `UI_HELP_REASON` | REUSE | `ledger.adjust.reason` references it at `Ledger.AdminAdjust`; this remains the help for an audited adjustment reason. |
| `UI_HELP_SETUP_ASSISTANT` | REUSE | `setup.assistant.readiness` references it at `SetupAssistant.Evaluate`. |

The orphan scan remains in `scripts/docs/DibsDocumentation.psm1` and emits the `orphan-help-key` rule. The current catalog produces 0 orphan warnings; the injected temporary key produced one warning.

## Role Boundary Finding

The role renderer correctly filters concepts by audience: Officer output includes review/admin operations, GM output includes setup/coordinator/reconciliation/rank/season/synchronization concepts, and Developer output includes technical protocol concepts. The Player guide nevertheless renders source provenance for `sync.status` as `src/modules/SyncV2.lua` and `Sync.GetStatus` ([player-guide.md](../generated/player-guide.md#L114), [SyncV2.lua](../../src/modules/SyncV2.lua#L239)). That exposes a Developer implementation name in Player output, so the requested Player role-output criterion fails even though the `sync.raid.relay` Developer-only concept itself is excluded. This final pass is read-only and did not change the renderer or generated artifact.

## Lua and Editor Diagnostics

The fresh full suite reports 654 passed, 1 failed (140 files). Isolating `tests/integration/predibs_sync_recovery_spec.lua` yields 4 passed, 1 failed with exactly:

`tests/integration/predibs_sync_recovery_spec.lua:50: expected 1, got 2`

This matches the previously documented, confirmed pre-existing heartbeat timer failure; the Phase 2 diff changes no timer or sync behavior. Classification: **CONFIRMED PRE-EXISTING**.

The current diagnostic provider flags the custom `---@doc.id`, `---@doc.category`, and related tags beginning at [PlayerUI.lua](../../src/ui/PlayerUI.lua#L364) as unknown annotations. The source has one closed `GetStatusPresentation` function; there is no current block-not-closed diagnostic. Fengari loads this file in the Player UI tests and the full suite. Classification: **LUACONTRACT_DIAGNOSTIC**.

## Worktree and TODO

The pre-report tracked diff is 28 files (1,745 insertions, 130 deletions):

- Audits: `UI_Help_Documentation_Consistency_Report.md`, `UI_Help_Documentation_Matrix.md`.
- Generated: all eight files under `docs/generated/`.
- Source: `RCLootCouncil.lua`, `RCLootCouncilOptions.lua`, `enUS.lua`, `frFR.lua`, `Disputes.lua`, `Installation.lua`, `Ledger.lua`, `PreDibs.lua`, `RaidRelay.lua`, `Readiness.lua`, `Seasons.lua`, `SyncV2.lua`, `LogsUI.lua`, `OfficerUI.lua`, `PlayerUI.lua`, and `SetupAssistant.lua`.
- Tests: `Generate-DibsDocs.Tests.ps1` and `ui_help_content_spec.lua`.

No files were staged. The two pre-existing untracked files remain present and untouched: `DIBS_Guided_Setup_Wizard_Post_Implementation_Validation.md` and `DIBS_Retail_Manual_Validation_Checklist.md`. The pre-existing untracked Phase 2 implementation report also remains. This final-validation report is the only additional workspace file created by this pass.

No new Phase 2 TODO/FIXME appears in the diff or Phase 2 reports. The older installation validation’s quoted `Completed: Implement P0 fix in Governance.ActivateV2 (1/4)` is explicitly described there as an unreproducible external session/agent-tool TODO. Classification: **STALE_AGENT_METADATA**; it is not unfinished Phase 2 work.

## Final Decision

**NOT READY TO COMMIT**

Reason: Player role output includes `SyncV2.lua` / `Sync.GetStatus` implementation provenance for the player-visible sync concept. Keep all other passing gates and the accepted pre-existing heartbeat failure as recorded above; resolve the Player output boundary in a separately authorized change, then repeat final validation.
