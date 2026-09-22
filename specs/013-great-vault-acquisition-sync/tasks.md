---

description: "Actionable task list for Great Vault acquisition tracking and guild sync"
---

# Tasks: Great Vault Acquisition Tracking and Guild Sync

**Input**: Design documents from `/specs/013-great-vault-acquisition-sync/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/`, and `quickstart.md`

**Organization**: Tasks are grouped by user story so each increment can be implemented and tested independently. Tests are included because the feature specification defines independent tests, measurable outcomes, migration coverage, and protocol contracts.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare the existing addon and test harness for the feature without changing runtime behavior.

- [X] T001 Add the Great Vault integration load entry and feature test fixture path in `src/RCLootCouncil_dibs.toc` and `tests/helpers/great_vault_fixture.lua`
- [X] T002 [P] Add shared Great Vault enum, record, digest, and review type annotations in `src/Types.lua`
- [X] T003 [P] Add the focused Great Vault test file names and Fengari invocation notes to `specs/013-great-vault-acquisition-sync/quickstart.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish persistence, identity, scope, and diagnostic boundaries required by every user story.

**CRITICAL**: No user story implementation should begin until this phase is complete.

- [X] T004 Extend the default guild database shape and readiness checks for Vault acquisition metadata and sync state in `src/Core.lua`
- [X] T005 Implement additive guild schema migration from version 6 to version 7, preserving legacy acquisition fields and classifying missing evidence as legacy/manual in `src/Core.lua`
- [X] T006 [P] Define canonical acquisition identity, reset context, content projection, and bounded-copy helpers in `src/modules/PreDibs.lua`
- [X] T007 [P] Add Great Vault diagnostic scopes and localized status/reason keys with English fallback in `src/locales/enUS.lua` and `src/locales/frFR.lua`
- [X] T008 [P] Add fixture builders for guild scope, characters, acquisition states, reset contexts, and sync projections in `tests/helpers/great_vault_fixture.lua`
- [X] T009 Add the feature module to the existing standalone/RCLootCouncil-optional loading path and ensure initialization is safe when the Retail Great Vault API is absent in `src/RCLootCouncil_dibs.toc` and `src/integrations/GreatVault.lua`

**Checkpoint**: Schema version 7, stable identity helpers, guild/character isolation, diagnostics, and test fixtures are available without changing Dibs ledger behavior.

---

## Phase 3: User Story 1 - Record a Great Vault acquisition (Priority: P1) MVP

**Goal**: Record exactly one confirmed claim when reliable Retail evidence exists, while preserving the manual `/dibs vault` fallback and never changing the Dibs ledger.

**Independent Test**: In a supported Retail fixture, claim one reward and verify one acquisition with player, item, season, reset, timestamp, source, and confirmation state; verify that opening/viewing a choice creates none, and manual fallback creates a labeled record when detection is unavailable.

### Tests for User Story 1

- [X] T010 [P] [US1] Add unit coverage for automatic, manual, unavailable, ambiguous, no-season, invalid-item, and duplicate acquisition outcomes in `tests/unit/great_vault_acquisition_spec.lua`
- [X] T011 [P] [US1] Add contract coverage for detector results and `/dibs vault <itemID> [difficulty]` outcomes in `tests/contract/great_vault_acquisition_spec.lua`
- [X] T012 [P] [US1] Add standalone capability fixtures proving that missing Retail APIs do not prevent local manual recording in `tests/integration/great_vault_retail_capability_spec.lua`

### Implementation for User Story 1

- [X] T013 [US1] Replace display-only Vault deduplication with stable character/reset/item/source identity and idempotent acquisition creation in `src/modules/PreDibs.lua`
- [X] T014 [US1] Preserve `/dibs vault <itemID> [difficulty]` while routing it through the shared acquisition validator and returning `RECORDED_MANUAL`, `ALREADY_RECORDED`, `REVIEW_REQUIRED`, and related outcomes in `src/Core.lua`, `src/modules/PreDibs.lua`, and `src/ui/PlayerUI.lua`
- [X] T015 [US1] Implement the capability probe and Retail claim adapter so only complete claim evidence creates `AUTOMATIC_CONFIRMED` records in `src/integrations/GreatVault.lua`
- [X] T016 [US1] Reject Vault-open and reward-choice observations as confirmed claims, retain ambiguous observations as explicitly unverified only when permitted, and expose manual-only diagnostics through `src/integrations/GreatVault.lua` and `src/ui/PlayerUI.lua`
- [X] T017 [US1] Verify every US1 persistence path leaves `Dibs.Ledger` and ledger transaction collections unchanged, with regression assertions in `tests/integration/predibs_ledger_boundary_spec.lua`

**Checkpoint**: A player can record a reliable claim or manual fallback locally, duplicate events are idempotent, and no Vault action consumes or grants a Dib.

---

## Phase 4: User Story 2 - Preserve trustworthy acquisition status (Priority: P1)

**Goal**: Make verification state visible and ensure only appropriate acquisition states affect protected-loot eligibility.

**Independent Test**: Create automatic, manual, legacy, unverified, Officer-confirmed, rejected, and reference-only records; inspect player and Officer projections and evaluate each record through the configured eligibility policy.

### Tests for User Story 2

- [X] T018 [P] [US2] Add unit coverage for allowed status transitions, immutable evidence, required review reasons, and idempotent review decisions in `tests/unit/great_vault_review_spec.lua`
- [X] T019 [P] [US2] Add eligibility coverage for confirmed, uncertain, rejected, reference-only, and Catalyst records in `tests/unit/great_vault_eligibility_spec.lua`
- [X] T020 [P] [US2] Add privacy contract coverage for Player versus Officer acquisition projections in `tests/contract/great_vault_privacy_spec.lua`

### Implementation for User Story 2

- [X] T021 [US2] Extend `CharacterEligibility` to consume verification-aware Vault evidence and apply the existing unknown-data policy without duplicating acquisition rules in `src/modules/CharacterEligibility.lua`
- [X] T022 [US2] Implement authorized Officer confirmation, rejection, reference-only retention, actor/reason/timestamp audit data, and immutable original evidence in `src/modules/PreDibs.lua` and `src/modules/Permissions.lua`
- [X] T023 [US2] Add Player acquisition status, source, reset, sync state, and eligibility explanation to the player projection in `src/ui/PlayerUI.lua` and `src/ui/LogsUI.lua`
- [X] T024 [US2] Add Officer acquisition review filters and actions for unresolved, conflicting, stale, manual, legacy, and ambiguous records in `src/ui/OfficerUI.lua`
- [X] T025 [US2] Localize all new statuses, review actions, warnings, diagnostics, and help text in `src/locales/enUS.lua` and `src/locales/frFR.lua`

**Checkpoint**: Players see their own status and explanation, Officers can resolve uncertainty with audited decisions, and eligibility never silently counts rejected or reference-only evidence.

---

## Phase 5: User Story 3 - Synchronize confirmed acquisitions within the guild (Priority: P1)

**Goal**: Synchronize authorized, guild-scoped Vault acquisition projections through existing `DIBS` and `SyncV2` boundaries without transmitting live loot data.

**Independent Test**: Record one confirmed acquisition on Client A, synchronize two same-guild authorized clients, verify one matching record and eligibility result on Client B, then reject cross-guild, unauthorized, private-evidence, and live-loot messages without local mutation.

### Tests for User Story 3

- [X] T026 [P] [US3] Add contract tests for `VAULT_DIGEST`, `VAULT_FETCH`, `VAULT_DETAIL`, and `VAULT_ACK` validation and apply results in `tests/contract/great_vault_sync_contract_spec.lua`
- [X] T027 [P] [US3] Add same-guild, cross-guild, unauthorized-sender, duplicate, stale, conflict, and forbidden-live-loot integration coverage in `tests/integration/great_vault_sync_privacy_spec.lua`

### Implementation for User Story 3

- [X] T028 [US3] Add Vault logical message types, bounded digest entries, and request projections to the existing protocol allowlist and envelope validation in `src/modules/SyncV2.lua`
- [X] T029 [US3] Implement `VAULT_DIGEST` and bounded `VAULT_FETCH` generation using guild-safe identity, revision, hash, status, and ordering metadata in `src/modules/SyncV2.lua`
- [X] T030 [US3] Implement validated `VAULT_DETAIL` transfer and `VAULT_ACK` results using existing serializer, chunk, expiry, sender, and guild checks in `src/modules/SyncV2.lua`
- [X] T031 [US3] Add atomic application of new Vault details with idempotent replay, stale revision, conflict, and rejected outcomes in `src/modules/PreDibs.lua` and `src/modules/SyncV2.lua`
- [X] T032 [US3] Extend forbidden-data validation and privacy projection checks so Vault sync excludes candidates, votes, responses, loot sessions, live discussions, and unauthorized Officer evidence in `src/modules/Sync.lua` and `src/modules/SyncV2.lua`
- [X] T033 [US3] Verify Vault sync remains local-only and usable when RCLootCouncil is unavailable in `tests/integration/great_vault_sync_privacy_spec.lua` and `tests/integration/rclootcouncil_capability_spec.lua`

**Checkpoint**: Same-guild authorized clients converge on bounded Vault records, while invalid scope, authority, privacy, integrity, and live-loot payloads are rejected without mutation.

---

## Phase 6: User Story 4 - Recover after reload, reconnect, or delayed delivery (Priority: P1)

**Goal**: Recover missing or out-of-order Vault records safely after reloads, reconnects, delayed chunks, and guild changes.

**Independent Test**: Deliver detail before digest, replay after reload, expire an incomplete transfer, reconnect a lagging receiver, and verify eventual convergence without duplicate or partial acquisition effects.

### Tests for User Story 4

- [X] T034 [P] [US4] Add digest-before/after-detail, replay, reconnect, chunk expiry, retry, and convergence coverage in `tests/integration/great_vault_sync_recovery_spec.lua`
- [X] T035 [P] [US4] Add guild-change, unguilded-character, cross-scope, immutable-identity conflict, and last-write-wins rejection coverage in `tests/integration/great_vault_isolation_spec.lua`

### Implementation for User Story 4

- [X] T036 [US4] Stage validated Vault detail transfers until identity, guild scope, content hash, and completion are confirmed, discarding incomplete or expired data in `src/modules/SyncV2.lua`
- [X] T037 [US4] Reuse heartbeat, roster, reconnect, sync-behind, and bounded retry state to request missing or newer Vault records after reconnect in `src/modules/SyncV2.lua`
- [X] T038 [US4] Preserve guild-scoped and unguilded character-scoped acquisition ownership across login, guild changes, and migration in `src/Core.lua` and `src/modules/PreDibs.lua`
- [X] T039 [US4] Route immutable identity conflicts to Officer review and prevent last-write-wins replacement in `src/modules/PreDibs.lua`, `src/modules/SyncV2.lua`, and `src/ui/OfficerUI.lua`

**Checkpoint**: Delayed, duplicated, partial, stale, and conflicting delivery paths are recoverable or reviewable and never create partial or duplicate eligibility effects.

---

## Phase 7: User Story 5 - Review, migrate, and correct historical records (Priority: P2)

**Goal**: Preserve existing Vault history, expose safe migration/review controls, and support deduplicated import without inventing evidence.

**Independent Test**: Load legacy records, run migration, confirm one, reject one, apply a full-data package twice, and verify original evidence, audit decisions, and zero ledger transactions.

### Tests for User Story 5

- [X] T040 [P] [US5] Add migration coverage for version 6 records, missing fields, old source labels, no-season records, guild isolation, repeat migration, and future-schema recovery in `tests/integration/great_vault_migration_spec.lua`
- [X] T041 [P] [US5] Add import/export deduplication and review-audit coverage for repeated full-data packages in `tests/integration/great_vault_import_spec.lua`

### Implementation for User Story 5

- [X] T042 [US5] Add migration metadata, legacy status defaults, source normalization, reset/evidence backfill rules, and no-ledger-mutation guarantees in `src/Core.lua` and `src/modules/PreDibs.lua`
- [X] T043 [US5] Add migration preview and historical record review actions with explicit confirmation/rejection reasons in `src/ui/OfficerUI.lua` and `src/ui/LogsUI.lua`
- [X] T044 [US5] Extend Vault acquisition projections in full-data backup/import paths with stable identity deduplication, scope validation, and preserved review history in `src/modules/ImportExport.lua` and `src/modules/Backup.lua`
- [X] T045 [US5] Add migration and correction diagnostics through the Dibs diagnostic policy without exposing private evidence to unauthorized users in `src/modules/PreDibs.lua` and `src/ui/DebugLogsUI.lua`

**Checkpoint**: Existing history remains accessible and accurately classified, review corrections are audited, repeated imports are idempotent, and no migration or import changes the Dibs ledger.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Complete release documentation, localization, compatibility, performance, and validation gates across all stories.

- [X] T046 [P] Add Great Vault command/help, protocol, privacy, migration, and diagnostic documentation to `docs/PROTOCOL.md`, `docs/RC_OPTIONS.md`, `docs/ARCHITECTURE.md`, and the affected English/French player and Officer guides
- [X] T047 [P] Add a dated changelog entry describing schema version 7, protocol behavior, manual fallback, privacy, and compatibility impact in `CHANGELOG.md`
- [X] T048 Update the addon version and Great Vault module load order consistently in `src/RCLootCouncil_dibs.toc`, `README.md`, release documentation, and affected validation artifacts
- [X] T049 [P] Add bounded-history, sorting, date visibility, empty/error state, narrow/wide window, and search responsiveness acceptance coverage for acquisition views in `tests/integration/great_vault_ui_spec.lua`
- [X] T050 Run focused Great Vault tests and the full Fengari suite from `specs/013-great-vault-acquisition-sync/quickstart.md`, recording results in `docs/audits/B13_Implementation_Evidence.md`
- [ ] T051 Perform one-client Retail validation for claim capability, manual fallback, reset context, reload/reconnect replay, combat safety, and unavailable API behavior and record evidence in `docs/audits/B13_Retail_Validation_Checklist.md`
- [ ] T052 Perform two-client same-guild, cross-guild, privacy, recovery, conflict, unguilded, and malformed-message validation and record evidence in `docs/audits/B13_Guild_Sync_Validation_Evidence.md`
- [X] T053 Review all new player-facing controls against constitution Principles XVIII, XXI, and XXII and close any localization, help-text, sorting, visibility, guide, or screenshot gaps in the affected `src/ui/`, `src/locales/`, `docs/player/`, and `docs/officer/` files

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No runtime dependency; prepares the module load path, annotations, fixture path, and quickstart notes.
- **Foundational (Phase 2)**: Depends on Setup and blocks every user story; establishes schema 7, identity, scope, diagnostics, and capability-safe initialization.
- **User Story 1 (Phase 3)**: Depends on Foundational and is the MVP increment.
- **User Story 2 (Phase 4)**: Depends on Foundational and the shared acquisition model from US1; eligibility/review can be developed in parallel with sync once the model is stable.
- **User Story 3 (Phase 5)**: Depends on the persisted acquisition projection from US1 and verification/privacy rules from US2.
- **User Story 4 (Phase 6)**: Depends on US3 message and transfer semantics.
- **User Story 5 (Phase 7)**: Depends on Foundational migration hooks and the final acquisition/review identity; it can begin alongside US3 after the model contract is fixed.
- **Polish (Phase 8)**: Depends on all desired stories and must complete before release.

### User Story Completion Order

```text
Foundational -> US1 MVP -> US2 status/eligibility -> US3 guild sync -> US4 recovery
                                      \-> US5 migration/review
```

### Parallel Opportunities

- T002, T003, T006, T007, and T008 can run in parallel during Setup/Foundation.
- US1 tests T010-T012 can run in parallel before implementation.
- US2 tests T018-T020 can run in parallel; Player and Officer UI work can then proceed in separate files.
- US3 contract/privacy tests T026-T027 can run in parallel; digest, transfer, and projection work can be split after the protocol boundary is agreed.
- US4 recovery and isolation tests T034-T035 can run in parallel.
- US5 migration and import tests T040-T041 can run in parallel.
- Documentation, changelog, UI acceptance tests, and release evidence tasks T046-T053 can run in parallel after the relevant implementation is stable.

## Parallel Example: User Story 1

```text
Task T010: unit acquisition state and idempotence tests in tests/unit/great_vault_acquisition_spec.lua
Task T011: acquisition/manual command contract tests in tests/contract/great_vault_acquisition_spec.lua
Task T012: standalone capability tests in tests/integration/great_vault_retail_capability_spec.lua

After the tests are defined:
Task T013: shared identity and persistence in src/modules/PreDibs.lua
Task T014: manual command integration in src/Core.lua, src/modules/PreDibs.lua, and src/ui/PlayerUI.lua
Task T015: Retail adapter in src/integrations/GreatVault.lua
```

## Implementation Strategy

### MVP First: User Story 1 Only

1. Complete Setup and Foundational phases.
2. Complete US1 tests and local acquisition implementation.
3. Run the focused US1 suite and confirm no Dibs ledger mutation.
4. Perform the one-client Retail capability/manual fallback check.
5. Stop before guild sync if the Retail claim signal remains unavailable; ship only when the manual-only behavior is explicitly acceptable for the release scope.

### Incremental Delivery

1. Add US2 status, eligibility, review, and privacy projections.
2. Add US3 same-guild digest/detail synchronization.
3. Add US4 reconnect, delayed transfer, conflict, and isolation recovery.
4. Add US5 migration, import, and historical correction workflows.
5. Complete Polish and all Retail/two-client release gates.

### Notes

- Every task has a sequential ID and an exact repository path.
- `[P]` is used only where tasks touch different files or independent test surfaces.
- `[US1]` through `[US5]` map directly to the five user stories in `spec.md`.
- Tests are listed before implementation within each story to preserve the requested contract-first workflow.
- No task creates a second Vault database, a second addon transport, a live-loot sync path, or a Dibs ledger side effect.
