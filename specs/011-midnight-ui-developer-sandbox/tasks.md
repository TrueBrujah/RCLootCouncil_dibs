---

description: "Task list for Midnight UI and Safe Developer Sandbox"
---

# Tasks: Midnight UI and Safe Developer Sandbox

**Input**: Design documents from `/specs/011-midnight-ui-developer-sandbox/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/midnight-ui-sandbox.md](contracts/midnight-ui-sandbox.md), [quickstart.md](quickstart.md)

**Tests**: B11 success criteria explicitly require automated isolation, authority, UI, reconciliation, combat, refresh, fallback, and responsive validation. Focused tests are included before story implementation tasks.

**Organization**: Tasks are grouped by user story so each story can be implemented and validated as an incremental slice.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Register B11 modules and establish deterministic fixture seams without changing production behavior.

- [X] T001 Add the planned B11 module and UI file load order to `src/RCLootCouncil_dibs.toc` and `src/embeds.xml` without changing existing module order semantics.
- [X] T002 [P] Add B11 fixture reset helpers and production-state snapshot utilities to `tests/helpers/load_addon.lua` for comparing production state before and after sandbox operations.
- [X] T003 [P] Add test doubles for LibSharedMedia, LibWindow, MSA-DropDownMenu, and optional external UI environments to `tests/helpers/`.
- [ ] T004 [P] Add B11 test file registration and focused-suite selection documentation to `tests/run.lua` and `docs/TEST_PLAN.md`.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish shared presentation, provider, persistence, and refresh boundaries before any user story consumes them.

**Checkpoint**: The foundation is ready when production and sandbox providers cannot be mixed, local presentation state is separate, and a shared window can defer/coalesce refreshes safely.

- [X] T005 Define the Midnight token and local presentation profile defaults in `src/ui/Midnight.lua`, including semantic states, typography, spacing, density, scale, contrast, and native fallbacks.
- [X] T006 [P] Add optional external UI environment probes and hint validation in `src/ui/EnvironmentAdapters.lua` for ElvUI, Tukui, EllesmereUI, and BenikUI-family environments.
- [X] T007 Add shared LibSharedMedia and LibWindow adapters with native media fallback and local position/scale restoration in `src/ui/Midnight.lua` and `src/ui/WindowState.lua`.
- [X] T008 Define provider selection, authority origin, active mode, and fail-closed mixed-provider guards in `src/integrations/DeveloperSandbox.lua`.
- [X] T009 Define the versioned separate developer store, deep-copy clone validation, future-schema rejection, and reload cleanup in `src/integrations/DeveloperSandboxStore.lua` and `src/Core.lua`.
- [X] T010 Add dirty-state/coalesced refresh scheduling and post-combat retry integration to `src/ui/AceGUI.lua` without rebuilding complex windows for every event.
- [ ] T011 Add foundational provider, persistence, presentation fallback, refresh, and combat contract tests in `tests/contract/b11_foundation_spec.lua`.
- [X] T012 Add foundational developer-store migration and production-state noninterference tests in `tests/integration/b11_sandbox_lifecycle_spec.lua`.

---

## Phase 3: User Story 1 - Consistent Midnight Presentation (Priority: P1) MVP

**Goal**: Provide one readable Midnight visual system with optional presentation hints, reusable Dibs-owned components, context menus, local window persistence, and native fallback.

**Independent Test**: Open player and Officer windows with no adapter, each supported adapter, invalid media, and high-contrast/local-scale settings; verify stable layout, fallback, local-only state, and visible primary actions.

### Tests for User Story 1

- [X] T013 [P] [US1] Add Midnight token, semantic-state, high-contrast, and local-scale tests in `tests/unit/midnight_ui_spec.lua`.
- [X] T014 [P] [US1] Add external environment adapter success, unsupported, failure, invalid-hint, and native-fallback tests in `tests/unit/ui_environment_adapters_spec.lua`.
- [X] T015 [P] [US1] Add shared component sizing, context-menu secondary-action, tooltip, and LibWindow restoration tests in `tests/integration/midnight_components_spec.lua`.

### Implementation for User Story 1

- [X] T016 [US1] Implement Midnight shared windows, panels, navigation, buttons, fields, status badges, tables, modals, tooltips, and empty states in `src/ui/Midnight.lua` and `src/ui/AceGUI.lua`.
- [X] T017 [US1] Implement presentation-hint application and native fallback in `src/ui/EnvironmentAdapters.lua` without exposing policy or authority values to adapters.
- [X] T018 [US1] Add shared context-menu registration through `src/ui/AceGUI.lua` and `src/libs/MSA-DropDownMenu-1.0/` integration points, keeping critical actions visible outside menus.
- [X] T019 [US1] Add local presentation profile and window position/scale persistence through `src/ui/WindowState.lua` without writing guild policy or sync state.
- [ ] T020 [US1] Integrate Midnight component lifecycle and coalesced refresh behavior into `src/ui/PlayerUI.lua`, `src/ui/OfficerUI.lua`, `src/ui/LogsUI.lua`, and `src/ui/DataUI.lua`.

**Checkpoint**: User Story 1 is independently functional when all complex Dibs windows share Midnight tokens, survive adapter failure, preserve local position/scale, and pass the focused UI tests.

---

## Phase 4: User Story 2 - Isolated Developer Sandbox (Priority: P1)

**Goal**: Enable safe local simulation of roles, coordinator/recovery states, and fault scenarios with no production write path or surviving simulated authority after reload.

**Independent Test**: Enable developer mode, clone or enter sandbox state, exercise every simulated role and required scenario, attempt mixed-provider/protected operations, exit, reload, and compare production snapshots.

### Tests for User Story 2

- [X] T021 [P] [US2] Add `/dibs dev on`, `/dibs dev off`, `/dibs dev status`, inactive-sandbox, and default-hidden navigation tests in `tests/unit/developer_mode_spec.lua`.
- [X] T022 [P] [US2] Add sandbox lifecycle, role/coordinator simulation, retained-data-after-reload, and no-write-back tests in `tests/integration/b11_sandbox_lifecycle_spec.lua`.
- [X] T023 [P] [US2] Add invalid/future/malformed/oversized store and mixed-provider fail-closed contract tests in `tests/unit/b11_sandbox_provider_spec.lua`.
- [X] T024 [P] [US2] Add scenario/fault coverage proving no production addon messages, fake global events, live loot events, or RC evidence writes in `tests/integration/b11_sandbox_scenarios_spec.lua`.

### Implementation for User Story 2

- [X] T025 [US2] Implement separate developer SavedVariables initialization, schema validation, production-to-sandbox clone, refresh, reset, and explicit re-entry in `src/integrations/DeveloperSandboxStore.lua`.
- [X] T026 [US2] Implement sandbox provider selection, simulated PLAYER/OFFICER/GUILD_MASTER roles, coordinator state, authority origin, and mixed-provider rejection in `src/integrations/DeveloperSandbox.lua`.
- [X] T027 [US2] Implement required named scenarios and bounded fault injection in `src/integrations/DeveloperSandboxScenarios.lua` without calling production transport, live loot, RC evidence, or protected accounting.
- [X] T028 [US2] Extend DeveloperMode commands and status reporting in `src/integrations/DeveloperMode.lua` while keeping Developer Mode alone unable to grant production authority.
- [X] T029 [US2] Add sandbox enter/refresh/reset/exit controls, persistent warning, simulated-role display, and reload/inactive handling to `src/ui/DeveloperUI.lua` and `src/ui/OfficerUI.lua`.
- [X] T030 [US2] Add explicit provider-origin checks to `src/modules/ProtectedActions.lua`, `src/modules/Permissions.lua`, `src/modules/Governance.lua`, and `src/modules/RaidRelay.lua` so simulated sandbox authority is never accepted by production paths.

**Checkpoint**: User Story 2 is independently functional when all sandbox isolation tests pass, production snapshots remain unchanged, reload clears active simulation, and explicit re-entry restores only sandbox data.

---

## Phase 5: User Story 3 - Player UI Redesign (Priority: P1)

**Goal**: Make My Dibs, Requests, and History immediately useful to players while preserving privacy and existing domain-service mutation boundaries.

**Independent Test**: Use player fixtures with normal, zero, empty, degraded, unavailable-RC, active-Pre-Dib, and large-history states to complete a request/cancellation and inspect own history.

### Tests for User Story 3

- [x] T031 [P] [US3] Add player summary visibility, empty-state, readiness, and technical-detail disclosure tests in `tests/integration/b11_player_ui_spec.lua`.
- [x] T032 [P] [US3] Add player request/cancellation delegation and privacy-boundary tests in `tests/contract/b11_player_actions_spec.lua`.

### Implementation for User Story 3

- [x] T033 [US3] Redesign My Dibs summary and first-viewport information hierarchy in `src/ui/PlayerUI.lua` for balance, active Pre-Dibs, pending requests, current season, and simple readiness.
- [x] T034 [US3] Redesign player Requests and request/cancellation controls in `src/ui/PlayerUI.lua` using existing `src/modules/PreDibs.lua` and eligibility services.
- [x] T035 [US3] Redesign player History projection in `src/ui/LogsUI.lua` and `src/ui/PlayerUI.lua` to expose only permitted own-player data with expandable technical details.
- [x] T036 [US3] Add player-safe normalized status and unavailable/degraded explanations through `src/integrations/RCLootCouncil.lua` and `src/modules/Readiness.lua` projections without exposing raw internals.

**Checkpoint**: User Story 3 is independently functional when a normal player can identify the three primary summaries and complete request/cancellation/history flows without direct UI accounting writes.

---

## Phase 6: User Story 4 - Officer and GM Dashboard (Priority: P1)

**Goal**: Provide grouped administrative navigation and a concise operational dashboard while retaining verified GM/Officer permissions and hidden Developer/Debug groups.

**Independent Test**: Open fixtures as player, Officer, and GM; verify page visibility, dashboard summaries, grouped navigation, technical disclosure, and mutation permission outcomes.

### Tests for User Story 4

- [x] T037 [P] [US4] Add player/Officer/GM navigation visibility and GM-versus-Officer action tests in `tests/contract/b11_officer_navigation_spec.lua`.
- [x] T038 [P] [US4] Add dashboard summary, degraded-status, and expandable-diagnostics tests in `tests/integration/b11_officer_dashboard_spec.lua`.

### Implementation for User Story 4

- [x] T039 [US4] Implement grouped Officer navigation for Dashboard, Requests, Pre-Dibs, History, Seasons, Rank Rules, Loot Rules, Announcements, RCLootCouncil, Settings, and Diagnostics in `src/ui/OfficerUI.lua`.
- [x] T040 [US4] Implement the Officer/GM dashboard projection and human-readable operational status cards in `src/ui/OfficerUI.lua` using normalized services only.
- [x] T041 [US4] Apply role-scoped visibility and existing protected-action delegation to Officer dashboard context menus and administrative controls in `src/ui/OfficerUI.lua`.
- [x] T042 [US4] Hide Developer and Debug groups unless Developer Mode is enabled, and show sandbox warning/provider status only in the developer-aware surface in `src/ui/OfficerUI.lua` and `src/ui/DeveloperUI.lua`.

**Checkpoint**: User Story 4 is independently functional when player privacy, Officer/GM visibility, grouped navigation, dashboard summaries, and protected administrative actions pass focused tests.

---

## Phase 7: User Story 5 - Requests, Pre-Dibs, and Eligibility UX (Priority: P2)

**Goal**: Present common request and loot-eligibility decisions first, with safe advanced disclosure and no changes to authoritative policy semantics.

**Independent Test**: Review normal, blocked, exceptional, pending, and unavailable request/eligibility fixtures; verify Recommended categories, customization disclosure, and explicit authorized save behavior.

### Tests for User Story 5

- [x] T043 [P] [US5] Add progressive-disclosure, Recommended preset, Catalyst block, and advanced-policy visibility tests in `tests/integration/b11_request_eligibility_ui_spec.lua`.
- [x] T044 [P] [US5] Add request/eligibility mutation delegation and unsaved-policy-change tests in `tests/contract/b11_request_eligibility_actions_spec.lua`.

### Implementation for User Story 5

- [x] T045 [US5] Redesign request review and Pre-Dib presentation in `src/ui/OfficerUI.lua` and `src/ui/PlayerUI.lua` with status, next action, safe explanations, and bounded private data.
- [x] T046 [US5] Add Recommended and Customize eligibility projections in `src/ui/OfficerUI.lua` using semantic categories from `src/modules/CharacterEligibility.lua` and existing loot policy services.
- [x] T047 [US5] Add expandable semantic category, reason, current-state, and authorized-save controls without direct policy writes in `src/ui/OfficerUI.lua` and `src/modules/ProtectedActions.lua`.

**Checkpoint**: User Story 5 is independently functional when common choices are visible first, Catalyst remains blocked, and advanced changes use existing authorized policy paths only.

---

## Phase 8: User Story 6 - RCLootCouncil History Reconciliation UX (Priority: P2)

**Goal**: Turn existing normalized history reconciliation into a guided Search -> Review -> Confirm/Reject -> Complete workflow without changing B09 evidence semantics.

**Independent Test**: Search bounded history, inspect eligible/ambiguous/ignored candidates, reject one, confirm one, retry stale/duplicate actions, and verify immutable evidence and protected accounting behavior.

### Tests for User Story 6

- [x] T048 [P] [US6] Add guided reconciliation stage, counts, candidate detail, ambiguous-state, and stale-review tests in `tests/integration/b11_reconciliation_ui_spec.lua`.
- [x] T049 [P] [US6] Add confirmation/rejection delegation, Officer authority, no-RC-write, and immutable-evidence contract tests in `tests/contract/b11_reconciliation_actions_spec.lua`.

### Implementation for User Story 6

- [x] T050 [US6] Implement Search, Review Candidates, Confirm/Reject, and Complete workflow state in `src/ui/LogsUI.lua` and `src/ui/OfficerUI.lua`.
- [x] T051 [US6] Project bounded scan counts, candidate summaries, item/winner/date/response fields, and expandable technical evidence from `src/integrations/RCLootCouncil.lua`.
- [x] T052 [US6] Delegate confirm/reject actions through existing `ProtectedActions.history.confirm` and rejection paths, with stale candidate and duplicate handling in `src/ui/LogsUI.lua`.
- [x] T053 [US6] Preserve player-safe confirmed-history projections and Officer-only evidence details in `src/ui/PlayerUI.lua` and `src/ui/OfficerUI.lua`.

**Checkpoint**: User Story 6 is independently functional when reconciliation remains read-only until protected confirmation/rejection, ambiguous rows cannot appear confirmed, and B09 evidence remains immutable.

---

## Phase 9: User Story 7 - Responsive Layout, Accessibility, and Polish (Priority: P2)

**Goal**: Make every B11 screen readable at supported sizes and resilient to long content, scale changes, high contrast, frequent events, and combat lockdown.

**Independent Test**: Render all B11 screens at minimum, typical, and wide sizes with long localized values, empty states, tables, menus, modals, high contrast, rapid invalidations, and combat transitions.

### Tests for User Story 7

- [X] T054 [P] [US7] Add supported-size, minimum-column, long-text, tooltip, modal, and scroll-owner tests in `tests/integration/b11_responsive_ui_spec.lua`.
- [X] T055 [P] [US7] Add semantic-state, high-contrast, text-scaling, and non-color state-distinction tests in `tests/unit/b11_accessibility_spec.lua`.
- [X] T056 [P] [US7] Add rapid-invalidation/coalesced-refresh and combat-lockdown lifecycle tests in `tests/contract/b11_refresh_combat_spec.lua`.

### Implementation for User Story 7

- [X] T057 [US7] Define and apply supported minimum dimensions, row/column sizing, modal sizing, spacing, and scroll ownership across `src/ui/AceGUI.lua`, `src/ui/PlayerUI.lua`, `src/ui/OfficerUI.lua`, and `src/ui/LogsUI.lua`.
- [X] T058 [US7] Add long-value truncation, tooltip/expansion, semantic status labels, selected-state treatment, and high-contrast Midnight adjustments in `src/ui/Midnight.lua` and shared UI components.
- [X] T059 [US7] Tune coalesced invalidation, deferred creation/movement/refresh, and post-combat retry behavior in `src/ui/AceGUI.lua` and `src/Core.lua`.

**Checkpoint**: User Story 7 is independently functional when the layout corpus has no overlap or clipped primary actions, state remains distinguishable without color, refreshes are coalesced, and B08 combat safety passes.

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Verify the complete B11 increment, preserve B00-B10 behavior, and document release boundaries.

- [ ] T060 [P] Add full B11 regression coverage and update `docs/TEST_PLAN.md` with automated, Retail, one-client, and two-client scenarios from `specs/011-midnight-ui-developer-sandbox/quickstart.md`.
- [ ] T061 [P] Update `docs/developer/architecture.md`, `docs/developer/testing.md`, `docs/developer/saved-variables.md`, and `docs/developer/modules.md` to document Midnight, provider isolation, local persistence, and sandbox lifecycle.
- [ ] T062 Run the complete Fengari suite from `specs/011-midnight-ui-developer-sandbox/quickstart.md`, record known pre-B11 baseline failures separately, and run `git diff --check`.
- [ ] T063 Run Retail one-client and two-client validation for UI fallback, combat safety, sandbox isolation, provider restoration, player privacy, Officer authority, and reconciliation behavior using `docs/TEST_PLAN.md` and `specs/011-midnight-ui-developer-sandbox/quickstart.md`.
- [ ] T064 Confirm no production SavedVariables migration, SyncV2 change, ledger semantic change, RCLootCouncil write, or sandbox-to-production path exists; record the B11 release note in `CHANGELOG.md` only when implementation is complete.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 Setup**: No dependencies; establishes load order and deterministic test seams.
- **Phase 2 Foundational**: Depends on Setup; blocks all user-story implementation.
- **Phase 3 US1**: Depends on Foundational; establishes the shared Midnight presentation layer.
- **Phase 4 US2**: Depends on Foundational; can proceed in parallel with US1 at the service boundary, but sandbox UI warning uses US1 components.
- **Phase 5 US3**: Depends on US1 and Foundational; player projections may proceed before Officer redesign.
- **Phase 6 US4**: Depends on US1, US2 visibility contracts, and Foundational.
- **Phase 7 US5**: Depends on US3/US4 navigation surfaces and existing domain services.
- **Phase 8 US6**: Depends on US1 and US4 Officer workflow shell; existing B09 adapter remains the authority.
- **Phase 9 US7**: Depends on all screens targeted for polish; its tests may begin with US1 components.
- **Phase 10 Polish**: Depends on every desired user story and all focused validations.

### User Story Dependencies

- **US1 (P1)**: Foundational only; MVP presentation slice.
- **US2 (P1)**: Foundational only for provider/store behavior; optional US1 dependency for sandbox UI.
- **US3 (P1)**: Depends on US1 shared components and existing Pre-Dibs/history services.
- **US4 (P1)**: Depends on US1; consumes US2 Developer/Debug visibility state.
- **US5 (P2)**: Depends on US3/US4 navigation and existing eligibility/request services.
- **US6 (P2)**: Depends on US1 and US4 Officer workflow shell; does not depend on new accounting behavior.
- **US7 (P2)**: Cross-cutting; depends on each screen it validates.

### Parallel Opportunities

- After T004, T005-T009 can proceed in parallel by boundary: Midnight tokens/adapters, window state, provider/store, and fixture contracts.
- Within US1, T013-T015 can run in parallel; T016-T019 can be split by token, adapter, menu, and persistence files before T020 integration.
- Within US2, T021-T024 can run in parallel; T025-T027 are separable store/provider/scenario work before T028-T030 integration.
- US1 and the service portion of US2 can proceed in parallel after Foundational; US3 and US4 can begin once their shared UI prerequisites are stable.
- Within US3-US7, focused tests marked `[P]` can be authored in parallel with separate implementation files, then run before integration tasks.

## Parallel Example: User Story 1

```text
T013 tests/unit/midnight_ui_spec.lua
T014 tests/unit/ui_environment_adapters_spec.lua
T015 tests/integration/midnight_components_spec.lua

T016 src/ui/Midnight.lua and src/ui/AceGUI.lua
T017 src/ui/EnvironmentAdapters.lua
T018 src/ui/AceGUI.lua context-menu integration
T019 src/ui/WindowState.lua
```

## Implementation Strategy

### MVP First (User Story 1 and the safety foundation)

1. Complete Phase 1 Setup and Phase 2 Foundational.
2. Complete Phase 3 User Story 1 and validate native Midnight, adapter fallback, local persistence, and coalesced refresh.
3. Complete the service portion of Phase 4 User Story 2 before exposing sandbox UI, then validate no-write-back and reload restoration.
4. Stop and review the safety boundary before adding player or administrative redesigns.

### Incremental Delivery

1. Add US1 shared presentation and validate independently.
2. Add US2 isolated sandbox and validate production noninterference independently.
3. Add US3 player workflows, then US4 Officer/GM dashboard.
4. Add US5 requests/eligibility and US6 reconciliation as separate workflow increments.
5. Add US7 responsive/accessibility polish and run the complete cross-cutting gates.

### Parallel Team Strategy

1. One developer owns foundational Midnight/UI boundaries; one owns sandbox provider/store; tests can be written in parallel.
2. After the foundation, player UI and Officer dashboard can proceed in separate controllers.
3. Request/eligibility and reconciliation can proceed in parallel once their navigation shells exist.
4. Responsive polish should follow each screen's first functional slice but complete as one final validation phase.

## Notes

- Every implementation task includes an exact repository path and all task lines use the required checkbox, sequential ID, optional `[P]`, and story-label format.
- Tests are written before each story's implementation tasks and map to the independent test criteria in the specification.
- No task changes B00-B10 production semantics; any conflict with ledger, governance, SyncV2, RC evidence, or combat-safety contracts must stop implementation for review.
