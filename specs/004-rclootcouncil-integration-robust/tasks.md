---

description: "Task list for Robust RCLootCouncil Integration"

---

# Tasks: Robust RCLootCouncil Integration

**Input**: Design documents from `/specs/004-rclootcouncil-integration-robust/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Required by the feature specification. Add contract and regression tests before
the corresponding implementation, then run the full Lua suite and manual Retail scenarios.

**Organization**: Tasks are grouped by user story so each priority slice can be implemented,
tested, and demonstrated independently.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel when it touches a different file and has no incomplete dependency.
- **[Story]**: Maps the task to a user story from `spec.md`.
- Every task includes an exact repository path.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish fixtures, release metadata, and test surfaces for the adapter work.

- [X] T001 Confirm the current addon load order and integration entry points in `src/RCLootCouncil_dibs.toc`, `src/integrations/Ace3.lua`, and `src/integrations/RCLootCouncil.lua`.
- [X] T002 [P] Add RCLootCouncil presence, enabled-state, Master Looter, and callback fixtures in `tests/helpers/wow_api.lua`.
- [X] T003 [P] Add loader options for absent, operational, degraded, unsupported, late-loaded, and externally supplied RCLootCouncil surfaces in `tests/helpers/load_addon.lua`.
- [X] T004 [P] Add finalized-award event builders and duplicate/reload replay helpers in `tests/helpers/wow_api.lua`.
- [X] T005 [P] Add compatibility reason-code fixtures and English/French fallback strings in `src/locales/enUS.lua` and `src/locales/frFR.lua`.
- [X] T006 [P] Create the repository changelog entry format and release-version check notes in `CHANGELOG.md` and `specs/004-rclootcouncil-integration-robust/quickstart.md`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the shared capability, identity, provenance, and protected-accounting
boundaries required by every user story.

**Critical**: Complete this phase before implementing any user story.

- [X] T007 [P] Add contract coverage for capability states, required probes, and fail-closed behavior in `tests/contract/rclootcouncil_capability_spec.lua`.
- [X] T008 [P] Add contract coverage for normalized finalized-award inputs, outcomes, and rejection rules in `tests/contract/rclootcouncil_award_contract_spec.lua`.
- [X] T009 [P] Add contract coverage for the RCLootCouncil/Dibs authority matrix in `tests/contract/rclootcouncil_authority_spec.lua`.
- [X] T010 Implement the runtime capability snapshot and stable reason-code vocabulary in `src/integrations/RCLootCouncil.lua`.
- [X] T011 Centralize RCLootCouncil discovery, capability probes, and late-load rechecks in `src/integrations/RCLootCouncil.lua` and `src/Core.lua`.
- [X] T012 Implement idempotent hook markers, bounded retries, and recursion guards for loot, voting, options, and award callbacks in `src/integrations/RCLootCouncil.lua`.
- [X] T013 Define normalized Master Looter identity and local-actor validation helpers in `src/integrations/RCLootCouncil.lua` and `src/modules/Permissions.lua`.
- [X] T014 Define finalized-award provenance normalization and stable award-reference derivation in `src/integrations/RCLootCouncil.lua`.
- [X] T015 Extend protected finalized-award validation for source, response, status, identity, and provenance fields in `src/modules/ProtectedActions.lua`.
- [X] T016 Preserve award-reference idempotency across reloads and migrations in `src/modules/Ledger.lua` and `src/Core.lua`.
- [X] T017 Add adapter and finalized-award diagnostic scopes without exposing live loot data in `src/Core.lua`, `src/integrations/RCLootCouncil.lua`, and `src/ui/DebugLogsUI.lua`.
- [X] T018 Add synchronization privacy assertions preventing live candidates, votes, responses, and sessions from entering Dibs payloads in `tests/contract/sync_privacy_spec.lua`.

**Checkpoint**: Capability state, local Master Looter identity, stable award provenance, protected accounting, and privacy contracts are available before story work begins.

---

## Phase 3: User Story 1 - Use Dibs with or without RCLootCouncil (Priority: P1) MVP

**Goal**: Keep Dibs core and guild administration functional when RCLootCouncil is absent,
operational, degraded, unsupported, or loaded late.

**Independent Test**: Load each integration state, perform authorized and unauthorized Dibs
actions, and verify that seasons, balances, requests, and history remain intact.

### Tests for User Story 1

- [X] T019 [P] [US1] Add absent/operational/degraded/unsupported capability transition tests in `tests/integration/rclootcouncil_capability_spec.lua`.
- [X] T020 [P] [US1] Add Standalone persistence and late-load regression tests in `tests/integration/rclootcouncil_capability_spec.lua`.
- [X] T021 [P] [US1] Add options status and safe-fallback UI tests in `tests/integration/rclootcouncil_options_fallback_spec.lua`.

### Implementation for User Story 1

- [X] T022 [US1] Implement the final capability state machine and recheck transitions in `src/integrations/RCLootCouncil.lua`.
- [X] T023 [US1] Keep Standalone Dibs initialization and GM/officer administration independent of RCLootCouncil state in `src/Core.lua` and `src/modules/Permissions.lua`.
- [X] T024 [US1] Make late RCLootCouncil availability refresh supported projections without resetting Dibs state in `src/Core.lua` and `src/integrations/RCLootCouncil.lua`.
- [X] T025 [US1] Expose capability state, reason code, tested assumptions, and Standalone fallback in `src/integrations/RCLootCouncilOptions.lua` and `src/ui/PlayerUI.lua`.
- [X] T026 [US1] Preserve Dibs SavedVariables and migration behavior when RCLootCouncil is added, removed, disabled, or degraded in `src/Core.lua` and `tests/integration/migration_spec.lua`.

**Checkpoint**: Dibs works independently of RCLootCouncil and reports unsupported integration without data loss or authority expansion.

---

## Phase 4: User Story 2 - Finalize a DIB Award Safely (Priority: P1)

**Goal**: Let only the verified local RCLootCouncil Master Looter produce one protected Dib
consumption for one qualifying finalized DIB award.

**Independent Test**: Finalize a DIB award, replay it after reload, then process non-DIB,
test, ambiguous, and non-ML events while comparing ledger transaction counts and balances.

### Tests for User Story 2

- [X] T027 [P] [US2] Add finalized DIB award acceptance and protected-ledger assertions in `tests/integration/finalized_award_flow_spec.lua` and `tests/contract/rclootcouncil_award_contract_spec.lua`.
- [X] T028 [P] [US2] Add duplicate, reconnect, and reload idempotency tests in `tests/integration/rclootcouncil_award_replay_spec.lua`.
- [X] T029 [P] [US2] Add response normalization tests for explicit DIB, non-DIB, localized, empty, and ambiguous values in `tests/unit/rclootcouncil_response_spec.lua`.
- [X] T030 [P] [US2] Add non-ML client callback replay and Master Looter change tests in `tests/integration/rclootcouncil_award_replay_spec.lua` and `tests/integration/finalized_award_flow_spec.lua`.
- [X] T031 [P] [US2] Add missing-item, missing-winner, missing-session, test-status, and unsupported-state tests in `tests/integration/rclootcouncil_award_replay_spec.lua` and `tests/contract/rclootcouncil_award_contract_spec.lua`.

### Implementation for User Story 2

- [X] T032 [US2] Implement canonical explicit DIB response normalization and reject ambiguous text in `src/integrations/RCLootCouncil.lua`.
- [X] T033 [US2] Implement reload-stable award-reference derivation using immutable history identity or a unique session identity, rejecting ambiguous events in `src/integrations/RCLootCouncil.lua`.
- [X] T034 [US2] Revalidate operational capability, local actor identity, and current Master Looter immediately before finalization in `src/integrations/RCLootCouncil.lua`.
- [X] T035 [US2] Map finalized-award callback outcomes to ignored, rejected, awarded, and duplicate results in `src/integrations/RCLootCouncil.lua`.
- [X] T036 [US2] Route accepted awards through `ProtectedActions.FinalizeAward` and prohibit direct callback writes to `src/modules/Ledger.lua` in `src/integrations/RCLootCouncil.lua` and `src/modules/ProtectedActions.lua`.
- [X] T037 [US2] Persist complete award audit context and return the existing result for duplicate award references in `src/modules/ProtectedActions.lua` and `src/modules/Ledger.lua`.
- [X] T038 [US2] Add localized diagnostics for award acceptance, duplicate delivery, ignored events, and authority failures in `src/locales/enUS.lua`, `src/locales/frFR.lua`, and `src/integrations/RCLootCouncil.lua`.

**Checkpoint**: A qualifying finalized DIB award consumes exactly one Dib, and every duplicate, ambiguous, test, non-DIB, or non-ML event has no accounting effect.

---

## Phase 5: User Story 3 - Keep Authority Boundaries Clear (Priority: P1)

**Goal**: Keep guild administration with verified GM/officer roles while RCLootCouncil owns
loot-session permissions and the narrow local-ML award exception.

**Independent Test**: Run all settings, mode, season, rank, grant, removal, refund, adjustment,
loot, and finalized-award actions for each actor in the authority matrix.

### Tests for User Story 3

- [X] T039 [P] [US3] Add the complete GM/officer/ML/Raid Leader/Raid Assistant/council/player matrix in `tests/integration/rclootcouncil_authority_matrix_spec.lua`.
- [X] T040 [P] [US3] Add remote actor and claimed-payload authority rejection tests in `tests/integration/rclootcouncil_authority_matrix_spec.lua` and `tests/contract/rclootcouncil_authority_spec.lua`.
- [X] T041 [P] [US3] Add option, mode, season, rank, and manual-ledger protection regression tests in existing `tests/contract/*authority*` and `tests/integration/*boundary*` coverage.

### Implementation for User Story 3

- [X] T042 [US3] Apply the verified guild GM/officer policy to every RCLootCouncil settings and policy callback in `src/integrations/RCLootCouncilOptions.lua`.
- [X] T043 [US3] Ensure the Master Looter exception is limited to finalized DIB consumption and cannot call manual grant, removal, refund, adjustment, or settings actions in `src/modules/ProtectedActions.lua` and `src/integrations/RCLootCouncil.lua`.
- [X] T044 [US3] Reject Raid Leader, Raid Assistant, council, and remote claimed authority for Dibs administration in `src/modules/Permissions.lua` and `src/modules/ProtectedActions.lua`.
- [X] T045 [US3] Record the verified guild actor or local Master Looter provenance and denial reason for protected integration actions in `src/modules/ProtectedActions.lua` and `src/modules/Ledger.lua`.

**Checkpoint**: The authority matrix is enforced at the acceptance boundary and no raid or council role can expand Dibs administration.

---

## Phase 6: User Story 4 - Preserve Loot History and Player Experience (Priority: P2)

**Goal**: Add useful Dibs projections without corrupting RCLootCouncil history, leaking private
loot data, or breaking player and officer views.

**Independent Test**: Compare unrelated RCLootCouncil history before and after initialization,
inspect player/officer visibility, and process partial metadata safely.

### Tests for User Story 4

- [X] T046 [P] [US4] Add unrelated-history preservation and Dibs-provenance marker tests in `tests/integration/rclootcouncil_history_spec.lua`.
- [X] T047 [P] [US4] Add player/officer privacy and diagnostic visibility tests in `tests/integration/rclootcouncil_options_fallback_spec.lua` and existing UI privacy coverage.
- [X] T048 [P] [US4] Add partial item/winner/session metadata and read-only candidate projection tests in `tests/integration/rclootcouncil_projection_spec.lua`.

### Implementation for User Story 4

- [X] T049 [US4] Restrict history normalization and Dibs markers to records explicitly created by Dibs in `src/integrations/RCLootCouncil.lua`.
- [X] T050 [US4] Preserve original RCLootCouncil identifiers and avoid unrelated history writes in `src/integrations/RCLootCouncil.lua`.
- [X] T051 [US4] Keep candidate status and Dibs columns read-only projections with safe refresh behavior in `src/integrations/RCLootCouncil.lua`.
- [X] T052 [US4] Display integration state and rejection reasons without exposing officer-only or live-session data in `src/ui/PlayerUI.lua`, `src/ui/OfficerUI.lua`, `src/ui/DebugLogsUI.lua`, and `src/Core.lua`.
- [X] T053 [US4] Keep options and voting-frame integration usable in Standalone mode and defer protected UI refreshes during combat in `src/integrations/RCLootCouncilOptions.lua` and `src/integrations/RCLootCouncil.lua`.

**Checkpoint**: RCLootCouncil history and session projections are preserved, the local DIB
button/response projection is locked and idempotent, and each player sees only data allowed
by the Dibs visibility policy.

---

## Phase 7: Polish and Cross-Cutting Validation

**Purpose**: Complete documentation, release traceability, automated regression, and Retail
compatibility evidence.

- [X] T054 [P] Update integration architecture, protocol privacy, and options documentation in `docs/ARCHITECTURE.md`, `docs/PROTOCOL.md`, and `docs/RC_OPTIONS.md`.
- [X] T055 [P] Add the dated feature changelog entry and increment the addon version metadata in `CHANGELOG.md` and `src/RCLootCouncil_dibs.toc`.
- [X] T056 [P] Add the completed acceptance mapping and compatibility evidence template in `specs/004-rclootcouncil-integration-robust/quickstart.md`.
- [X] T057 Run the focused contract and integration suite from `specs/004-rclootcouncil-integration-robust/quickstart.md`.
- [X] T058 Run the full Lua suite and `git diff --check`, recording the result in `specs/004-rclootcouncil-integration-robust/quickstart.md`.
- [ ] T059 Perform one-client Retail validation for absent, operational, degraded, unsupported, and late-loaded RCLootCouncil states in `specs/004-rclootcouncil-integration-robust/quickstart.md`.
- [ ] T060 Perform two-client Retail validation for local ML finalization, non-ML replay rejection, duplicate delivery, and officer/player privacy in `specs/004-rclootcouncil-integration-robust/quickstart.md`.
- [X] T061 Review the implementation against `specs/004-rclootcouncil-integration-robust/spec.md`, `plan.md`, contracts, and `.specify/memory/constitution.md`, and record any limitation in `specs/004-rclootcouncil-integration-robust/quickstart.md`.

## Dependencies and Execution Order

### Phase Dependencies

- **Phase 1** has no dependencies and establishes fixtures and release metadata.
- **Phase 2** depends on Phase 1 and blocks all user stories.
- **User Stories 1, 2, and 3** depend on Phase 2 and can proceed in parallel when separate files are assigned.
- **User Story 4** depends on the adapter and award outcomes from User Stories 1 and 2.
- **Phase 7** depends on all required user stories and is the release gate.

### User Story Dependencies

- **US1 (P1)**: Depends only on the foundational capability and persistence boundary; it is the first MVP slice.
- **US2 (P1)**: Depends on the foundational identity, provenance, protected-action, and idempotency boundary.
- **US3 (P1)**: Depends on the foundational authority contract and can run alongside US1 and US2.
- **US4 (P2)**: Depends on the stable projection and award provenance decisions from US1 and US2.

### Parallel Opportunities

- T002-T006 can run in parallel because they touch separate fixtures, locale, and release files.
- T007-T009 and T018 can run in parallel as independent contract/privacy tests.
- T019-T021 can run in parallel before US1 implementation.
- T027-T031 can run in parallel before US2 implementation.
- T039-T041 can run in parallel before US3 implementation.
- T046-T048 can run in parallel before US4 implementation.
- T054-T056 can run in parallel during final polish.

### Within Each User Story

1. Write and run the story tests so the new behavior is demonstrated before implementation.
2. Implement the smallest complete path for the story.
3. Run the story's independent test and the relevant existing regression suite.
4. Stop at the checkpoint before starting the next dependent story.

## Parallel Example: MVP

```text
T019 capability transition tests
T020 Standalone persistence tests
T021 fallback options tests
```

After the tests are ready, implement T022-T026 sequentially because they share the adapter
state machine and Standalone lifecycle.

## Implementation Strategy

### MVP First

1. Complete Setup and Foundational phases.
2. Deliver US1 so Dibs remains reliable with or without RCLootCouncil.
3. Deliver US2 so a verified local ML can account for one finalized DIB exactly once.
4. Deliver US3 so the complete authority boundary is enforced.
5. Validate the three P1 stories before adding the P2 presentation/history work.

### Incremental Delivery

1. Capability and fallback boundary.
2. Finalized-award validation and idempotency.
3. Authority matrix and inbound trust checks.
4. History preservation, projections, and privacy surfaces.
5. Automated and Retail validation, changelog, and version release gate.

### Release Gate

The feature is not release-ready until the full Lua suite passes, `git diff --check` is clean,
one-client and two-client Retail scenarios are recorded, unrelated RCLootCouncil history is
preserved, and the dated changelog entry matches the incremented addon version.
