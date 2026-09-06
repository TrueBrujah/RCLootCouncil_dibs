# Tasks: Independent Dibs Core

**Input**: Design documents from /specs/001-dibs-core/

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/core-api.md, quickstart.md

## Format: [ID] [P?] [Story] Description

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Align addon structure and baseline persistence contracts for core delivery

- [X] T001 Confirm core module load order and required files in src/RCLootCouncil_dibs.toc
- [X] T002 Align SavedVariables bootstrap and schema version defaults in src/Core.lua
- [X] T003 Add core feature documentation references in ./README.md
- [X] T004 Align command surface for core-only workflows in src/Core.lua

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Implement invariant enforcement shared by all user stories

- [X] T005 Implement season registry primitives and active-season selection in src/modules/Seasons.lua
- [X] T006 [P] Implement rank allocation policy persistence by season and rank index in src/modules/RankRules.lua
- [X] T007 [P] Implement append-only transaction append and lookup primitives in src/modules/Ledger.lua
- [X] T008 Implement transaction validation rules for required audit fields in src/modules/Ledger.lua
- [X] T009 Implement permission role foundation for PLAYER/OFFICER/GM contexts in src/modules/Permissions.lua; preserve legacy DIBS_ADMIN appointments as non-authorizing history
- [X] T010 Implement protected authoritative mutation routing in src/modules/ProtectedActions.lua

**Checkpoint**: Core invariants are enforced before story implementation.

## Phase 3: User Story 1 - Configure Seasonal Rank Allocations (Priority: P1)

**Goal**: Allow authorized users to create seasons, set active season, and configure rank-specific allocations.

**Independent Test**: Create season, set active season, configure two rank allocations, and read them back unchanged.

- [X] T011 [US1] Implement createSeason and listSeasons behavior from contract in src/modules/Seasons.lua
- [X] T012 [US1] Implement setActiveSeason behavior from contract in src/modules/Seasons.lua
- [X] T013 [US1] Implement setRankAllocation behavior from contract in src/modules/RankRules.lua
- [X] T014 [US1] Implement getRankAllocation behavior from contract in src/modules/RankRules.lua
- [X] T015 [US1] Route season and rank policy commands through protected actions in src/modules/ProtectedActions.lua
- [X] T016 [US1] Expose season and allocation management entry points in src/Core.lua

**Checkpoint**: Seasonal allocation setup is functional and independently testable.

## Phase 4: User Story 2 - Maintain Player Seasonal Balances from Ledger (Priority: P1)

**Goal**: Record authoritative transactions and expose deterministic player seasonal balances from ledger history.

**Independent Test**: Record allocation/grant/use/refund for one player and confirm derived remaining balance and history.

- [X] T017 [US2] Implement appendTransaction contract behavior with idempotent replay handling in src/modules/Ledger.lua
- [X] T018 [US2] Implement getTransactions query behavior by season and player in src/modules/Ledger.lua
- [X] T019 [US2] Implement getPlayerSeasonState derived balance projection in src/modules/Ledger.lua
- [X] T020 [US2] Enforce authoritative acceptance path for transaction writes in src/modules/ProtectedActions.lua
- [X] T021 [US2] Expose player seasonal balance and history read paths in src/ui/PlayerUI.lua
- [X] T022 [US2] Add officer-facing seasonal player state visibility in src/ui/OfficerUI.lua

**Checkpoint**: Ledger-backed balances are deterministic and visible to intended roles.

## Phase 5: User Story 3 - Correct Errors with Compensating Transactions (Priority: P2)

**Goal**: Correct mistakes through explicit compensating entries while preserving immutable history.

**Independent Test**: Submit mistaken transaction, add compensating correction, and verify both rows remain with audit metadata.

- [X] T023 [US3] Implement correction action validation for refund/revoke/admin-adjustment flows in src/modules/Ledger.lua
- [X] T024 [US3] Enforce required reason field for administrative adjustment transactions in src/modules/Ledger.lua
- [X] T025 [US3] Persist actor identity metadata for authoritative corrections in src/modules/Ledger.lua
- [X] T026 [US3] Expose correction workflows through protected action commands in src/modules/ProtectedActions.lua
- [X] T027 [US3] Expose immutable correction history visibility in src/ui/OfficerUI.lua

**Checkpoint**: Correction workflows are auditable and do not mutate prior rows.

## Phase 6: User Story 4 - Preserve History Across Rank Changes (Priority: P2)

**Goal**: Support rank changes without silently rewriting historical allocations or transactions.

**Independent Test**: Change rank after prior activity and verify historical rows keep original rank while future rows use updated rank.

- [X] T028 [US4] Persist playerRankIndex snapshot at transaction-append time in src/modules/Ledger.lua
- [X] T029 [US4] Ensure rank updates affect only future transaction captures in src/modules/RankRules.lua
- [X] T030 [US4] Preserve historical transaction views across rank changes in src/modules/Ledger.lua
- [X] T031 [US4] Add rank-change handling diagnostics for officers in src/ui/OfficerUI.lua

**Checkpoint**: Historical integrity is preserved across rank transitions.

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final validation, documentation alignment, and release readiness for core feature

- [X] T032 [P] Align core contract wording with delivered behavior in specs/001-dibs-core/contracts/core-api.md
- [X] T033 [P] Update validation record scenarios for implemented behavior in specs/001-dibs-core/quickstart.md
- [X] T034 Execute automated Lua harness validation from quickstart in tests/run.lua
- [X] T035 Document constitution-aligned core boundaries and non-goals in docs/ARCHITECTURE.md
- [X] T036 Verify no core code path requires RCLootCouncil or Encounter Journal in src/integrations/RCLootCouncil.lua and src/integrations/EncounterJournal.lua, and record evidence in specs/001-dibs-core/quickstart.md
- [X] T037 Add explicit validation step for SC-001 (derived balance parity) in specs/001-dibs-core/quickstart.md
- [X] T038 Add explicit validation step for SC-002 (idempotent replay no-op) in specs/001-dibs-core/quickstart.md
- [X] T039 Add explicit validation step for SC-003 and SC-004 (compensating correction + rank-history preservation) in specs/001-dibs-core/quickstart.md
- [X] T040 Add explicit validation step for SC-005 (core independence from RC/EJ/sync context) in specs/001-dibs-core/quickstart.md
- [X] T041 Add core API stability and regression checklist for later features in specs/001-dibs-core/contracts/core-api.md and tests/contract/core_api_contract_spec.lua

## Dependencies & Execution Order

### Phase Dependencies

- Phase 1 -> Phase 2 -> Phase 3/4/5/6 -> Phase 7
- User stories start only after Phase 2 is complete.
- Priority order for delivery is US1 + US2 first, then US3 and US4.

### User Story Dependencies

- US1 depends on foundational season/rank/permission routing (T005-T010).
- US2 depends on US1 season context plus foundational ledger validation.
- US3 depends on US2 transaction flow and immutable ledger invariants.
- US4 depends on US1 rank policy and US2 transaction snapshot behavior.

### Within Each User Story

- Contract-facing module behavior first.
- Protected action routing second.
- UI visibility and diagnostics last.

### Parallel Opportunities

- T006 and T007 can run in parallel after T005.
- T032 and T033 can run in parallel during Phase 7.
- T037, T038, T039, and T040 can run in parallel during Phase 7 documentation pass.
- US3 and US4 can proceed in parallel after US2 checkpoint.

## Parallel Example: Foundational

- Task: T006 [P] Implement rank allocation policy persistence by season and rank index in src/modules/RankRules.lua
- Task: T007 [P] Implement append-only transaction append and lookup primitives in src/modules/Ledger.lua

## Parallel Example: Polish

- Task: T032 [P] Align core contract wording with delivered behavior in specs/001-dibs-core/contracts/core-api.md
- Task: T033 [P] Update validation record scenarios for implemented behavior in specs/001-dibs-core/quickstart.md

## Implementation Strategy

### MVP First (US1 + US2)

1. Complete Phase 1 and Phase 2.
2. Deliver US1 seasonal rank allocation setup.
3. Deliver US2 ledger-backed player balance behavior.
4. Validate independently using quickstart scenarios A and B.

### Increment 2

1. Deliver US3 compensating correction workflows.
2. Deliver US4 rank-change historical integrity.
3. Run full SC-001..SC-005 validation and API stability checks in Phase 7.

## Phase 8: Ace3 Core Infrastructure Follow-Up

- [X] T042 Add embedded Ace3 load-order and LibStub coexistence contract coverage in `src/RCLootCouncil_dibs.toc`, `tests/helpers/load_addon.lua`, and `tests/contract/core_independence_spec.lua`
- [X] T043 Migrate non-domain event lifecycle registration to AceEvent where it reduces duplicate frame plumbing in `src/Core.lua`, while retaining Lua core APIs and SavedVariables behavior
- [X] T044 Validate Dibs core behavior with embedded Ace3, externally supplied LibStub services, and RCLootCouncil absent in `tests/contract/core_api_contract_spec.lua` and `tests/contract/core_independence_spec.lua`
- [X] T045 [P] Add UI regression coverage for officer tabs, seasonal selector, player balance/history, search, and pagination in `tests/integration/combat_safety_spec.lua` and `tests/unit/candidate_status_spec.lua`
- [X] T046 Create an AceGUI window adapter that owns only reusable Dibs window lifecycle and layout in `src/ui/AceGUI.lua` and register it in `src/RCLootCouncil_dibs.toc` and `tests/helpers/load_addon.lua`
- [X] T047 Rebuild the core Officer and Player window shells with AceGUI tabs, scrollable lists, search, pagination, and combat-safe open/close behavior in `src/ui/OfficerUI.lua` and `src/ui/PlayerUI.lua`
- [X] T048 Verify AceGUI presentation preserves seasonal ledger calculations, permissions, and standalone operation without moving domain rules into UI callbacks in `tests/contract/core_api_contract_spec.lua` and `tests/integration/combat_safety_spec.lua`
