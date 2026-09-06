---

description: "Task list for Pre-Dibs Encounter Journal feature implementation"
---

# Tasks: Pre-Dibs Encounter Journal

**Input**: Design documents from `/specs/002-predibs-encounter-journal/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Included because the feature specification defines independent acceptance scenarios and the repository uses a Lua regression harness.

**Organization**: Tasks are grouped by user story so each story can be implemented and validated independently after the foundational phase.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel when it touches a different file and has no incomplete dependency.
- **[Story]**: User story mapping from spec.md.
- Every task includes an exact repository path.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish feature test coverage and preserve the existing addon load/test boundaries.

- [X] T001 Confirm feature 002 documentation paths and addon load order in `src/RCLootCouncil_dibs.toc` and `tests/helpers/load_addon.lua`
- [X] T002 [P] Add reusable Encounter Journal context doubles for raid and dungeon instances in `tests/helpers/wow_api.lua`
- [X] T003 [P] Add shared Pre-Dib assertion helpers for request count, status, and ledger effects in `tests/helpers/`
- [X] T004 Record the current 32-test baseline and feature-specific validation commands in `specs/002-predibs-encounter-journal/quickstart.md`

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Ensure all stories use the same request, item, season, and authoritative award boundaries.

- [X] T005 [P] Add contract coverage for request lifecycle and stable reason codes in `tests/contract/predibs_api_contract_spec.lua`
- [X] T006 [P] Add contract coverage for raid-only UI and unknown-category visibility in `tests/contract/encounter_journal_ui_contract_spec.lua`
- [X] T007 Verify request identity, season association, timestamps, and terminal-status handling in `src/modules/PreDibs.lua`
- [X] T008 Verify shared item context normalization and public/test separation in `src/modules/LootPipeline.lua`
- [X] T009 Verify finalized award idempotency and protected ledger ordering in `src/modules/ProtectedActions.lua` and `src/modules/Ledger.lua`
- [X] T010 Define stable feature reason codes and user-facing mappings in `src/locales/enUS.lua` and `src/locales/frFR.lua`

**Checkpoint**: Request creation, item context, award finalization, and error contracts are testable before story-specific changes.

## Phase 3: User Story 1 - Request a Pre-Dib (Priority: P1)

**Goal**: Create and deduplicate active Pre-Dib requests without consuming Dibs.

**Independent Test**: Create the same player/item/season request twice and verify one active request, stable identity, and unchanged balance.

- [X] T011 [P] [US1] Add unit tests for valid request metadata and active duplicate reuse in `tests/unit/predibs_request_spec.lua`
- [X] T012 [P] [US1] Add unit tests for invalid item, missing season, and disabled public Pre-Dib rejection in `tests/unit/predibs_request_spec.lua`
- [X] T013 [US1] Implement or correct active request lookup by player identity, item ID, and season ID in `src/modules/PreDibs.lua`
- [X] T014 [US1] Implement or correct public request creation and structured rejection reasons in `src/modules/PreDibs.lua`
- [X] T015 [US1] Route Adventure Guide and player UI requests through the common pipeline without direct ledger writes in `src/modules/LootPipeline.lua` and `src/ui/PlayerUI.lua`
- [X] T016 [US1] Verify request creation does not append a consumption transaction in `tests/integration/predibs_ledger_boundary_spec.lua`

**Checkpoint**: A standalone player can create one active Pre-Dib per player/item/season without spending a Dib.

## Phase 4: User Story 2 - Manage the Pre-Dib Lifecycle (Priority: P1)

**Goal**: Confirm, cancel, retain, and fulfill requests with exactly-once finalized-award accounting.

**Independent Test**: Exercise confirmation, cancellation, non-winning outcome, final award, and replay while inspecting request history and ledger count.

- [X] T017 [P] [US2] Add lifecycle transition tests for pending, confirmed, cancelled, invalidated, and fulfilled states in `tests/unit/predibs_lifecycle_spec.lua`
- [X] T018 [P] [US2] Add finalized-award tests for non-final no-op, successful fulfillment, and duplicate replay in `tests/integration/finalized_award_flow_spec.lua`
- [X] T019 [US2] Enforce valid lifecycle transitions and preserve status timestamps in `src/modules/PreDibs.lua`
- [X] T020 [US2] Preserve active confirmed requests when another player wins or an award is cancelled in `src/modules/PreDibs.lua` and `src/modules/ProtectedActions.lua`
- [X] T021 [US2] Link finalized award references to fulfilled requests only after successful ledger append in `src/modules/ProtectedActions.lua` and `src/modules/PreDibs.lua`
- [X] T022 [US2] Verify exactly one ledger consumption and one fulfillment per award reference in `tests/integration/finalized_award_flow_spec.lua`

**Checkpoint**: Pre-Dib lifecycle and award replay behavior are deterministic and auditable.

## Phase 5: User Story 3 - Use the Adventure Guide Safely (Priority: P1)

**Goal**: Show and submit the Dib action for eligible raid rows only.

**Independent Test**: Exercise raid, dungeon, blocked-category, and unknown-category contexts and verify action visibility and submission results.

- [X] T023 [P] [US3] Add unit tests for raid-only `CanPreDib` and `SubmitPreDib` behavior in `tests/unit/encounter_journal_predib_spec.lua`
- [X] T024 [P] [US3] Add integration tests for blocked, allowed, and unknown sub-category action policy in `tests/contract/encounter_journal_ui_contract_spec.lua`
- [X] T025 [P] [US3] Add load/retry and missing-frame safety tests for the Encounter Journal adapter in `tests/integration/combat_safety_spec.lua` and `tests/integration/toc_load_spec.lua`
- [X] T026 [US3] Implement or correct raid/dungeon context detection and direct submission rejection in `src/integrations/EncounterJournal.lua`
- [X] T027 [US3] Implement or correct row refresh behavior so dungeon actions are hidden and unknown categories remain visible in `src/integrations/EncounterJournal.lua`
- [X] T028 [US3] Keep item identity and category decisions based on stable IDs/normalized keys rather than localized names in `src/integrations/EncounterJournal.lua`
- [X] T029 [US3] Verify the localized action label and safe retry behavior in `src/integrations/EncounterJournal.lua` and `src/locales/enUS.lua`

**Checkpoint**: Adventure Guide behavior is raid-only, configurable, and safe when metadata or UI frames are incomplete.

## Phase 6: User Story 4 - Configure and Announce Pre-Dibs (Priority: P2)

**Goal**: Configure local category policy and announcements without affecting accounting authority.

**Independent Test**: Apply the recommended matrix, override one category, submit a request, and verify available announcements and unchanged balance/history.

- [X] T030 [P] [US4] Add unit tests for recommended matrix defaults, overrides, and unknown-category allowance in `tests/contract/encounter_journal_ui_contract_spec.lua`
- [X] T031 [P] [US4] Add unit tests for announcement channel normalization, deduplication, and unavailable-channel handling in `tests/integration/predibs_announcements_spec.lua`
- [X] T032 [US4] Persist and expose category policy settings without changing ledger state in `src/integrations/EncounterJournal.lua` and `src/integrations/RCLootCouncilOptions.lua`
- [X] T033 [US4] Persist and apply public/officer announcement settings in `src/modules/PreDibs.lua` and `src/integrations/RCLootCouncilOptions.lua`
- [X] T034 [US4] Verify announcement behavior is triggered only for confirmed requests and never for Developer Mode requests in `tests/integration/predibs_announcements_spec.lua` and `tests/unit/developer_mode_spec.lua`
- [X] T035 [US4] Document category and announcement validation evidence in `specs/002-predibs-encounter-journal/quickstart.md`

**Checkpoint**: Guild-local visibility and notification preferences work independently from Dibs balances and history.

## Phase 7: User Story 5 - Operate With or Without RCLootCouncil (Priority: P2)

**Goal**: Preserve standalone operation while allowing RC to observe compatible local events.

**Independent Test**: Run request and finalized-award flows with RC absent, degraded, and operational, then compare authoritative Dibs state.

- [X] T036 [P] [US5] Add standalone Pre-Dib and fulfillment tests with RCLootCouncil absent in `tests/contract/core_independence_spec.lua` and `tests/contract/predibs_feature_acceptance_spec.lua`
- [X] T037 [P] [US5] Add optional adapter observation tests without RC registry writes or authority fallback in `tests/integration/rclootcouncil_adapter_spec.lua`
- [X] T038 [US5] Route compatible finalized award observations into the protected Dibs finalization path in `src/integrations/RCLootCouncil.lua`
- [X] T039 [US5] Preserve standalone fallback for absent/degraded RC and fail closed for operational RC denials in `src/modules/Permissions.lua` and `src/integrations/RCLootCouncil.lua`
- [X] T040 [US5] Verify RC logging/display is non-authoritative and cannot alter request history or balance directly in `tests/contract/core_independence_spec.lua` and `tests/integration/rclootcouncil_adapter_spec.lua`
- [X] T041 [US5] Document standalone versus optional RC evidence and privacy boundaries in `docs/ARCHITECTURE.md` and `specs/002-predibs-encounter-journal/quickstart.md`

**Checkpoint**: The complete feature works without RC and remains authority-safe when RC is present.

## Phase 8: Polish and Cross-Cutting Validation

**Purpose**: Validate the complete feature against the spec, constitution, and existing regression suite.

- [X] T042 [P] Add a feature acceptance matrix mapping FR-001 through FR-020 to tests in `tests/contract/predibs_feature_acceptance_spec.lua`
- [X] T043 [P] Add migration coverage for existing requests, settings, seasons, and ledger history in `tests/integration/predibs_migration_spec.lua`
- [X] T044 Run all automated Lua tests and record the result in `specs/002-predibs-encounter-journal/quickstart.md`
- [X] T045 Run diagnostics and whitespace checks for touched Lua/tests/docs files and record any environment limitation in `specs/002-predibs-encounter-journal/quickstart.md`
- [X] T046 Perform manual Retail client validation of raid/dungeon visibility, category matrix, announcements, combat refresh, and RC-absent operation in `specs/002-predibs-encounter-journal/quickstart.md`
- [X] T047 Review implementation against `specs/002-predibs-encounter-journal/spec.md`, `plan.md`, and `.specify/memory/constitution.md` and record final acceptance evidence in `specs/002-predibs-encounter-journal/quickstart.md`

## Dependencies and Execution Order

### Phase Dependencies

- Phase 1 -> Phase 2 -> User Stories 1 and 2.
- User Story 1 -> User Story 2 because fulfillment depends on request identity and active lookup.
- User Story 1 -> User Story 3 because the Adventure Guide submits through the request path.
- User Story 2 -> User Story 5 because RC award observation delegates to finalized fulfillment.
- User Story 3 -> User Story 4 because settings and announcements are exercised through visible/submittable rows.
- User Stories 2, 3, and 4 -> User Story 5 integration comparison.
- All user stories -> Phase 8.

### Parallel Opportunities

- T002 and T003 can run in parallel after T001.
- T005 and T006 can run in parallel during Phase 2.
- T011 and T012 can run in parallel during US1.
- T017 and T018 can run in parallel during US2.
- T023, T024, and T025 can run in parallel during US3.
- T030 and T031 can run in parallel during US4.
- T036 and T037 can run in parallel during US5.
- T042 and T043 can run in parallel during Phase 8.

### Independent Story Validation

- US1: one active deduplicated request and unchanged balance.
- US2: lifecycle transitions, one final consumption, and replay no-op.
- US3: raid action allowed, dungeon action rejected, category policy respected.
- US4: settings/announcements change local behavior without accounting changes.
- US5: standalone and optional RC paths produce the same authoritative Dibs result.

## Implementation Strategy

### MVP First (US1 + US2)

1. Complete setup and foundational contracts.
2. Deliver request creation/deduplication without ledger consumption.
3. Deliver lifecycle and finalized-award fulfillment with idempotent replay.
4. Run the focused US1/US2 tests and the existing regression suite.

### Increment 2 (US3)

1. Complete raid-only Adventure Guide visibility and submission safeguards.
2. Validate dungeon blocking, category defaults, unknown-category visibility, and missing-frame safety.

### Increment 3 (US4 + US5)

1. Complete local matrix and announcement configuration.
2. Verify standalone operation and optional RC observation/fulfillment.
3. Run the complete acceptance and migration checks.

### Final Validation

1. Run all automated tests through Fengari.
2. Run editor diagnostics and `git diff --check`.
3. Perform real-client smoke validation when the WoW client is available.
4. Mark each task `[X]` only after its implementation and validation evidence are complete.

## Phase 9: Ace3 Pre-Dib UI Follow-Up

- [ ] T048 Add AceEvent/AceTimer regression coverage for Encounter Journal retries and combat-safe refreshes in `tests/integration/combat_safety_spec.lua` and `tests/integration/toc_load_spec.lua`
- [ ] T049 Migrate Encounter Journal event/retry plumbing to AceEvent/AceTimer where available in `src/integrations/EncounterJournal.lua`, retaining safe fallback behavior
- [ ] T050 Migrate player/officer Pre-Dib configuration registration to AceConfig in `src/integrations/RCLootCouncilOptions.lua` and preserve standalone settings access in `src/Core.lua`
- [ ] T051 Verify Pre-Dib lifecycle, announcements, and standalone operation remain unchanged with Ace3 services present or unavailable in `tests/unit/predibs_lifecycle_spec.lua` and `tests/integration/predibs_announcements_spec.lua`
- [ ] T052 [P] Add AceGUI regression coverage for Player Pre-Dib submission state, history, and Officer Pre-Dib list filtering in `tests/unit/predibs_request_spec.lua`, `tests/unit/predibs_lifecycle_spec.lua`, and `tests/integration/combat_safety_spec.lua`
- [ ] T053 Create reusable AceGUI request-list and status-row adapters in `src/ui/AceGUI.lua` and cover their fallback behavior in `tests/helpers/wow_api.lua`
- [ ] T054 Rebuild the Player Pre-Dib panel with AceGUI controls while preserving public submission, Developer Mode isolation, and personal history in `src/ui/PlayerUI.lua`
- [ ] T055 Rebuild Officer Pre-Dib review, category policy, announcement settings, and seasonal filtering with AceGUI tabs/lists in `src/ui/OfficerUI.lua` and `src/integrations/RCLootCouncilOptions.lua`
- [ ] T056 Verify AceGUI UI migration preserves Adventure Guide action behavior, request lifecycle, announcements, combat safety, and optional RCLootCouncil operation in `tests/integration/combat_safety_spec.lua`, `tests/integration/predibs_announcements_spec.lua`, and `tests/contract/core_independence_spec.lua`
