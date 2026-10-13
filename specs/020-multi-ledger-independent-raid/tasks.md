# Tasks: Multi-Ledger Management and Independent Raid Sessions

**Input**: Design documents from `specs/020-multi-ledger-independent-raid/` (`plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`)

**Prerequisites**: `plan.md`, `spec.md`, `data-model.md`, `contracts/`

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to ([US1], [US2], [US3])
- Exact file paths are included in every description

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Register new module entries, configure TOC load order, and prepare shared test doubles.

- [X] T001 Update addon manifest load order in `src/RCLootCouncil_dibs.toc` to register `modules/MultiLedger.lua` and `modules/IndependentRaid.lua`
- [X] T002 [P] Create multi-ledger and independent raid test doubles in `tests/helpers/load_addon.lua`
- [X] T003 [P] Add multi-ledger test state and mock fixtures in `tests/helpers/distributed_ledger_fixture.lua`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish storage partitioning, migration of existing ledgers into `db.ledgers["guild-primary"]`, and core permission hooks.

**⚠️ CRITICAL**: No user story work can begin until this foundational phase is complete.

- [X] T004 Implement storage partitioning migration in `src/modules/Ledger.lua` migrating legacy `db.ledger` into `db.ledgers["guild-primary"]`
- [X] T005 [P] Add `Dibs.Ledger.GetActiveLedgerId` delegation and backward-compatible proxying in `src/modules/Ledger.lua`
- [X] T006 [P] Add unit test suite validating ledger storage migration and legacy compatibility in `tests/unit/b03_local_ledger_spec.lua`
- [X] T007 Register new action constants (`ledger.propose`, `ledger.approve`, `ledger.revoke`, `ledger.archive`) in `src/modules/Permissions.lua`

**Checkpoint**: Foundation ready - storage partition migration and permission actions registered.

---

## Phase 3: User Story 1 - Multi-Ledger Creation, GM Approval, and Switching (Priority: P1) 🎯 MVP

**Goal**: Enable Officers and GMs to create multiple isolated guild ledgers, require GM approval for proposed ledgers, synchronize all approved ledgers across guild members in the background, and provide an active ledger selector in the UI.

**Independent Test**: Propose a new ledger with an Officer character; verify it enters `PROPOSED` state. Approve it with the Guild Master; verify it transitions to `APPROVED` and broadcasts a `LEDGER_CATALOG` digest. Verify that transactions in the new ledger do not modify `guild-primary` balances, and switching active ledger in the UI updates displayed balances.

### Tests for User Story 1

- [X] T008 [P] [US1] Create unit tests for multi-ledger lifecycle (propose, approve, archive, switch) in `tests/unit/multi_ledger_spec.lua`
- [X] T009 [P] [US1] Create integration tests for multi-ledger background synchronization in `tests/integration/multi_ledger_sync_spec.lua`

### Implementation for User Story 1

- [X] T010 [US1] Implement `Dibs.MultiLedger` module with propose, approve, archive, and list operations in `src/modules/MultiLedger.lua`
- [X] T011 [US1] Add `LEDGER_APPROVED`, `LEDGER_REVOKED`, and `LEDGER_ARCHIVED` governance records and signature checks in `src/modules/Governance.lua`
- [X] T012 [US1] Implement multi-ledger catalog digest (`LEDGER_CATALOG`) and `ledgerId`-scoped `LEDGER_DIGEST` broadcast in `src/modules/SyncV2.lua`
- [X] T013 [US1] Implement background ingestion of missing ledger batches by `ledgerId` without active ledger dependency in `src/modules/SyncV2.lua`
- [X] T014 [US1] Implement active ledger selector dropdown and change notification events in `src/ui/PlayerUI.lua`
- [X] T015 [US1] Implement GM approval panel for proposed ledgers in `src/ui/OfficerUI.lua`

**Checkpoint**: User Story 1 is fully functional and testable independently. Multi-ledger creation, GM approval, background sync, and UI switching verified.

---

## Phase 4: User Story 2 - Officer Administration Empowerment (Priority: P1)

**Goal**: Permit verified Officers to configure seasons, rank rules, Pre-Dib options, and complete Guided Setup without Guild Master-only blockers, while keeping GM confirmation pending for guild-wide governance cutover.

**Independent Test**: Log in with an Officer character when GM is offline. Access guided setup, configure rank allocations, and create a season. Verify `Installation.GetStatus` reports no fatal `GUILD_MASTER_REQUIRED` blocker and `Installation.Initialize` succeeds with `PROPOSAL_CREATED`.

### Tests for User Story 2

- [X] T016 [P] [US2] Create unit tests for officer capability matrix and permissions in `tests/unit/permissions_spec.lua`
- [X] T017 [P] [US2] Create integration tests for officer-driven guided setup in `tests/integration/guided_setup_wizard_spec.lua`

### Implementation for User Story 2

- [X] T018 [US2] Reclassify `settings.modify`, `season.create`, `season.set`, `rank.set`, and `installation.mode.set` as `ADMIN_ACTIONS` in `src/modules/Permissions.lua`
- [X] T019 [US2] Update `Installation.GetStatus` to recognize verified officers and emit non-blocking warnings instead of `GUILD_MASTER_REQUIRED` in `src/modules/Installation.lua`
- [X] T020 [US2] Update `Installation.Initialize` to allow officer execution resulting in `PROPOSAL_CREATED` in `src/modules/Installation.lua`
- [X] T021 [US2] Update guided setup wizard steps to display officer-safe progress and pending GM confirmation banners in `src/modules/Wizard.lua`

**Checkpoint**: User Stories 1 and 2 functional. Officers can configure and prepare raids independently without operational roadblocks.

---

## Phase 5: User Story 3 - Independent Local Raid Sessions (Priority: P2)

**Goal**: Enable Master Looters to run independent, local-only raid sessions with zero guild network sync, standard RCLootCouncil DIB response integration for raiders without the addon, and post-raid award reconciliation for officers.

**Independent Test**: Start an independent raid session on the Master Looter client. Award an item to a raider who selected "DIB" in RCLootCouncil. Verify session points are deducted locally, 0 messages are sent to the guild channel, and an Officer can inspect and reconcile the award into an approved guild ledger.

### Tests for User Story 3

- [X] T022 [P] [US3] Create unit tests for independent raid session lifecycle and local accounting in `tests/unit/independent_raid_spec.lua`
- [X] T023 [P] [US3] Create integration tests for RCLootCouncil DIB response handling in independent mode in `tests/integration/rc_independent_award_spec.lua`

### Implementation for User Story 3

- [X] T024 [US3] Implement `Dibs.IndependentRaid` session manager (start, conclude, list, balance tracking) in `src/modules/IndependentRaid.lua`
- [X] T025 [US3] Add strict network inhibition preventing `Sync.Send` calls to `GUILD` or `OFFICER` channels during independent sessions in `src/modules/IndependentRaid.lua`
- [X] T026 [US3] Update `Dibs.RCLootCouncil.HandleAwardCallback` to intercept DIB awards during active independent sessions in `src/integrations/RCLootCouncil.lua`
- [X] T027 [US3] Implement read-only Great Vault eligibility lookup for independent raid candidate display in `src/modules/IndependentRaid.lua`
- [X] T028 [US3] Implement post-raid award reconciliation function `Dibs.IndependentRaid.ReconcileAward` into an approved guild ledger in `src/modules/IndependentRaid.lua`
- [X] T029 [US3] Add Independent Raid session management and reconciliation UI tab in `src/ui/OfficerUI.lua`

**Checkpoint**: User Stories 1, 2, and 3 functional. Independent raids operate completely locally with vanilla RCLootCouncil voting and optional officer reconciliation.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: End-to-end validation, documentation updates, and compliance checks.

- [X] T030 [P] Execute end-to-end test scenarios defined in `specs/020-multi-ledger-independent-raid/quickstart.md` using Fengari

## Phase 7: Archived Ledger Deletion Extension

- [X] T031 Amend Principle IV and Feature 020 to define the narrowly scoped GM deletion exception.
- [X] T032 Add GM-only, confirmed deletion and governance audit recording in `src/modules/MultiLedger.lua` and `src/modules/Governance.lua`.
- [X] T033 Add guild-wide `LEDGER_DELETE` tombstone transport and sender validation in `src/modules/SyncV2.lua`.
- [X] T034 Add archived-ledger deletion controls to `src/ui/OfficerUI.lua` and document the lifecycle in officer guides.
- [X] T035 Add focused lifecycle and synchronization regression tests in `tests/unit/multi_ledger_spec.lua` and `tests/integration/multi_ledger_sync_spec.lua`.
- [X] T036 [P] Update English and French Player and Officer guides in `docs/` reflecting multi-ledger and independent raid workflows
- [X] T037 [P] Add dated entry in `CHANGELOG.md` documenting multi-ledger, officer setup empowerment, and independent raid sessions
- [X] T038 Verify git diff, format consistency, and whitespace validation via `git diff --check`

---

## Dependencies & Execution Order

### Phase Dependencies

```text
Phase 1: Setup (T001-T003)
  │
  ▼
Phase 2: Foundational (T004-T007) [CRITICAL BLOCKER]
  │
  ├───────────────────────────────┐
  ▼                               ▼
Phase 3: User Story 1 (T008-T015) [P1] 🎯 MVP    Phase 4: User Story 2 (T016-T021) [P1]
  │                                                │
  └──────────────────────┬─────────────────────────┘
                         ▼
Phase 5: User Story 3 (T022-T029) [P2]
  │
  ▼
Phase 6: Polish & Cross-Cutting (T030)
  │
  ▼
Phase 7: Archived Ledger Deletion Extension (T031-T038)
```

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Phase 2 (Foundational). Independent of US2 and US3.
- **User Story 2 (P1)**: Depends on Phase 2 (Foundational). Independent of US1 and US3 (can proceed in parallel with US1).
- **User Story 3 (P2)**: Depends on Phase 2 (Foundational). Integrates with US1's multi-ledger reconciliation API.

---

## Parallel Opportunities

- **Phase 1**: `T002` and `T003` can execute in parallel.
- **Phase 2**: `T005`, `T006`, and `T007` can execute in parallel once `T004` completes.
- **Phase 3 (US1)**: Test tasks `T008` and `T009` can execute in parallel before implementation. UI tasks `T014` and `T015` can execute in parallel once `T010` is complete.
- **Phase 4 (US2)**: Test tasks `T016` and `T017` can execute in parallel. Implementation tasks `T018`, `T019`, and `T021` touch separate files and can proceed in parallel.
- **Phase 5 (US3)**: Test tasks `T022` and `T023` can execute in parallel.
- **Phase 6**: `T030` is the focused end-to-end validation gate.
- **Phase 7**: `T031` and `T032` touch separate domain files; `T034` and `T036` are UI/documentation work after the lifecycle contract is defined; `T035` and `T038` are validation tasks.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001`-`T003`).
2. Complete Phase 2: Foundational (`T004`-`T007`).
3. Complete Phase 3: User Story 1 (`T008`-`T015`).
4. **STOP and VALIDATE**: Verify that multiple guild ledgers can be proposed, approved by the GM, and switched in the UI with zero cross-ledger balance bleed.

### Incremental Delivery

1. **Increment 1 (MVP)**: Multi-ledger partition, propose, approve, switch, background sync (US1).
2. **Increment 2**: Officer empowerment for seasons, rank allocations, and Guided Setup (US2).
3. **Increment 3**: Independent local raid sessions with vanilla RCLootCouncil voting (US3).
4. **Increment 4**: Documentation, quickstart verification, and release preparation (Phase 6).
