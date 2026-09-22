---

description: "Task list for B12 Release UI Stabilization"
---

# Tasks: B12 Release UI Stabilization

**Input**: Design documents from `/specs/012-release-ui-stabilization/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/release-ui.md](contracts/release-ui.md), [quickstart.md](quickstart.md)

**Tests**: Tests are included because the B12 specification requires independent story tests, focused regressions, automated release evidence, and real Retail validation before release readiness.

**Organization**: Tasks are grouped by user story and ordered so each story can be implemented and validated as an incremental slice.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish B12 evidence and deterministic test seams without changing production authority or persistence.

- [X] T001 Create the B12 focused-suite manifest and baseline notes in `docs/TEST_PLAN.md`, naming the existing B11 UI-004 baseline and the unrelated `tests/integration/rclootcouncil_buttons_spec.lua:155` failure.
- [X] T002 [P] Add B12 UI fixture builders for Player/Officer shells, grouped TreeGroup callbacks, pooled page roots, context menus, combat state, and optional RCLootCouncil capability states in `tests/helpers/b12_ui_fixtures.lua`.
- [X] T003 [P] Add B12 request and historical-candidate fixture builders with legacy, unknown, unavailable, ambiguous, stale, duplicate, and privacy-filtered values in `tests/helpers/b12_workflow_fixtures.lua`.
- [X] T004 [P] Record the B12 changed-surface ownership map and freeze constraints in `specs/012-release-ui-stabilization/contracts/release-ui.md`, including the rule that UI projections cannot write authoritative state.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Lock shared lifecycle, projection, authorization, and validation boundaries before story-specific UI work.

**Checkpoint**: The foundation is ready when B12 tests can exercise existing controllers and services through deterministic fixtures without adding a persistence or synchronization contract.

- [X] T005 Add foundational contract assertions for one content owner, separate Player/Officer state, protected mutation delegation, context-menu cleanup, and sandbox provider isolation in `tests/contract/b12_release_ui_contract_spec.lua`.
- [X] T006 [P] Add foundational projection assertions for transient request, historical candidate, context-menu, lifecycle, release-candidate, and sandbox-limitation records in `tests/unit/b12_ui_projection_spec.lua`.
- [X] T007 [P] Add the B12 test-file selection examples and known-baseline handling to `specs/012-release-ui-stabilization/quickstart.md` using the repository-supported `npx --yes fengari tests/run.lua` command.
- [X] T008 Verify the implementation branch contains no B12 `tasks.md`-driven source assumptions, new production SavedVariables fields, SyncV2 fields, or new request lifecycle states before user-story implementation begins; record the check in `docs/audits/B12_Release_UI_Hardening_Evidence.md`.

---

## Phase 3: User Story 1 - Open And Navigate Stable Windows (Priority: P1) MVP

**Goal**: Keep Player and Officer windows isolated, draggable, readable, and free of stale pooled content through repeated routes, refreshes, and open/close cycles.

**Independent Test**: Run the B12 lifecycle suite and the existing B11 UI-004 ownership suite through at least ten Player and ten Officer open/close cycles, grouped route callbacks, History-to-Debug transitions, position restoration, menu cleanup, and combat deferral; verify one page/content owner and zero new Dibs-attributable UI errors.

### Tests for User Story 1

- [X] T009 [P] [US1] Add repeated Player/Officer open-close, alternating-window isolation, one-page-root, stale-header, blank-page, and History-to-Debug assertions in `tests/integration/b12_release_ui_stabilization_spec.lua`.
- [X] T010 [P] [US1] Add grouped TreeGroup callback normalization, route alias, programmatic-selection, and canonical display/domain-value assertions in `tests/contract/b12_release_ui_contract_spec.lua`.
- [X] T011 [P] [US1] Add separate position-record, one-time restore, valid-position preservation, off-screen recovery, drag-save, and route-refresh isolation assertions in `tests/integration/b12_window_state_spec.lua`.
- [X] T012 [P] [US1] Add shared dropdown, tooltip, scrolling-table, context-menu replacement/close, pooled-widget release, and combat-refresh assertions in `tests/integration/b12_ui_ownership_spec.lua`.

### Implementation for User Story 1

- [X] T013 [US1] Preserve one permanent `contentHost`, one mounted `pageRoot`, route-boundary normalization, legacy route aliases, and exclusive route rendering in `src/ui/OfficerUI.lua` and `src/ui/PlayerUI.lua`.
- [X] T014 [US1] Preserve recursive page-root release, nested widget cleanup, dropdown/tooltip/table detachment, context-menu close behavior, and coalesced refresh behavior in `src/ui/AceGUI.lua`.
- [X] T015 [US1] Preserve separate Player/Officer position records, one-time restoration, valid on-screen coordinates, off-screen recovery, and Dibs-owned drag/save boundaries in `src/ui/WindowState.lua`.
- [X] T016 [US1] Preserve canonical enum normalization and fail-closed invalid-value handling at the visible control boundary in `src/ui/AceGUI.lua`, `src/ui/OfficerUI.lua`, and `src/integrations/RCLootCouncilOptions.lua`.
- [X] T017 [US1] Preserve safe table tooltip argument ordering, item-link handling, lib-st ownership, and raw-frame parent rejection in `src/ui/AceGUI.lua`.
- [X] T018 [US1] Preserve Player/Officer callback cleanup and shell deactivation on close in `src/ui/PlayerUI.lua` and `src/ui/OfficerUI.lua`.

**Checkpoint**: User Story 1 is independently functional when the focused lifecycle tests pass, existing UI-004 regressions remain green, and no source path writes authoritative state directly.

---

## Phase 4: User Story 2 - Repair Only Defective Pages (Priority: P1)

**Goal**: Repair only demonstrated Pre-Dibs, Settings, Loot Eligibility, Debug, RCLootCouncil, or later Retail defects while keeping stable AceConfig/AceGUI components and the shared Midnight shell.

**Independent Test**: Exercise each proven defective page at supported narrow and wide sizes, with empty/degraded/unavailable states and relevant role permissions; verify shared presentation, bounded tables, visible primary actions, contextual secondary actions, and unchanged service semantics.

### Tests for User Story 2

- [X] T019 [P] [US2] Add targeted page-shell, empty/error-state, stable-footer, bounded-table, semantic-status, and no-generic-action-column assertions in `tests/integration/b12_page_cleanup_spec.lua`.
- [X] T020 [P] [US2] Add Pre-Dibs canonical-mode, Settings enum, Loot Eligibility authorization, Debug isolation, and RCLootCouncil capability-state assertions in `tests/contract/b12_page_cleanup_contract_spec.lua`.
- [X] T021 [P] [US2] Add supported narrow/wide layout, long-label, tooltip, modal, and non-color status readability assertions in `tests/integration/b12_responsive_ui_spec.lua`.

### Implementation for User Story 2

- [X] T022 [US2] Repair only evidence-backed Pre-Dibs, Settings, Loot Eligibility, Debug, and RCLootCouncil page defects in `src/ui/OfficerUI.lua`, `src/ui/PlayerUI.lua`, and `src/ui/AceGUI.lua`, preserving existing service callbacks and permission checks.
- [X] T023 [US2] Apply shared Midnight spacing, text hierarchy, semantic states, stable footer, empty/error states, and bounded table sizing to changed pages in `src/ui/AceGUI.lua`, `src/ui/OfficerUI.lua`, and `src/ui/PlayerUI.lua`.
- [X] T024 [US2] Route page secondary row actions through the existing shared context-menu implementation and keep critical primary actions visible in `src/ui/AceGUI.lua`, `src/ui/OfficerUI.lua`, and `src/ui/PlayerUI.lua`.
- [X] T025 [US2] Preserve Pre-Dibs and Settings display-label normalization before policy/options service invocation in `src/ui/OfficerUI.lua`, `src/ui/PlayerUI.lua`, and `src/integrations/RCLootCouncilOptions.lua`.
- [X] T026 [US2] Keep Developer/Debug presentation isolated from production authority and retain fail-closed RCLootCouncil unavailable/degraded rendering in `src/ui/OfficerUI.lua` and `src/integrations/RCLootCouncil.lua`.

**Checkpoint**: User Story 2 is independently functional when only proven defects are changed, shared Midnight presentation is consistent, and page-focused tests pass without business or authority changes.

---

## Phase 5: User Story 3 - Resolve Requests As Dibs Support Tickets (Priority: P1)

**Goal**: Present existing Dibs requests as understandable support-ticket projections with safe primary workflows, privacy-aware evidence, and separately guarded advanced tools.

**Independent Test**: Review representative requests across all supported existing states and presentation categories as Player, Officer, and GM; verify submitter/item/problem/status/evidence/next-action clarity, contextual secondary actions, and protected delegation for every mutation.

### Tests for User Story 3

- [X] T027 [P] [US3] Add request-row and request-detail projection tests for submitter, player/item, presentation-only category labels, existing statuses, evidence, next action, bounded notes, and empty/unavailable states in `tests/integration/b12_requests_support_ticket_spec.lua`.
- [X] T028 [P] [US3] Add request action contract tests for Ask for information, Resolve, Reject, cancellation/privacy, advanced action visibility, reason/confirmation requirements, and no direct ledger writes in `tests/contract/b12_requests_actions_spec.lua`.
- [X] T029 [P] [US3] Add request context-menu tests for relevant object-aware actions, hidden unauthorized actions, primary-action visibility, and menu cleanup in `tests/integration/b12_requests_context_menu_spec.lua`.

### Implementation for User Story 3

- [X] T030 [US3] Add a transient support-ticket projection over existing request records in `src/ui/OfficerUI.lua`, deriving category labels, existing-state labels, explanations, next actions, safe evidence, and visibility without adding persisted fields.
- [X] T031 [US3] Expand presentation-only category mapping for missing Dib, incorrect removal, wrong player/item, wrong recipient, award-recipient mismatch, Pre-Dib problem, refund request, history problem, general Dibs question, and other in `src/ui/OfficerUI.lua` without changing `src/modules/Disputes.lua` lifecycle semantics.
- [X] T032 [US3] Keep Ask for information, Resolve, and Reject as visible applicable primary actions over existing Disputes transitions in `src/ui/OfficerUI.lua` and `src/modules/Disputes.lua`.
- [X] T033 [US3] Add relevant request row context actions for opening details, viewing permitted player/history data, and copying supported identifiers through `src/ui/OfficerUI.lua` and `src/ui/AceGUI.lua`.
- [X] T034 [US3] Keep Correct player/item, Correct balance, Refund Dib, Revoke Dib, and Historical import separately disclosed and routed through authorization, reason, confirmation, readiness, and `src/modules/ProtectedActions.lua` in `src/ui/OfficerUI.lua`.
- [X] T035 [US3] Preserve Player versus Officer/GM request disclosure and ensure unavailable advanced actions cannot execute from rows, menus, or detail views in `src/ui/PlayerUI.lua` and `src/ui/OfficerUI.lua`.

**Checkpoint**: User Story 3 is independently functional when non-technical Officers can resolve normal requests, categories/statuses remain presentation-only over existing records, and all high-risk paths remain protected and auditable.

---

## Phase 6: User Story 4 - Review Historical DIB Transfers Safely (Priority: P2)

**Goal**: Make historical DIB candidates deliberate and evidence-first to review while preserving read-only RCLootCouncil history and existing reconciliation authority.

**Independent Test**: Search bounded history, review eligible/ambiguous/unsupported/stale candidates, expand technical evidence, reject one, confirm one, retry duplicates, and verify no RCLootCouncil history mutation or unauthorized accounting.

### Tests for User Story 4

- [X] T036 [P] [US4] Add concise candidate summary, collapsed technical evidence, unknown-field, classification, duplicate, stale, and unavailable-integration assertions in `tests/integration/b12_historical_transfer_spec.lua`.
- [X] T037 [P] [US4] Add Officer/GM privacy, shared context-menu safety, confirmation/reason, protected delegation, idempotency, and no-RCLootCouncil-write assertions in `tests/contract/b12_historical_transfer_actions_spec.lua`.
- [X] T038 [P] [US4] Add bounded exact-alias, source-scan, related-winner, difficulty, stable-identity, ambiguous, and already-accounted projection assertions in `tests/unit/b12_historical_candidate_projection_spec.lua`.

### Implementation for User Story 4

- [X] T039 [US4] Refine the Search -> Review -> Confirm/Reject -> Complete presentation with Item, Winner, Difficulty, Encounter, Award date, classification, duplicate status, and concise evidence first in `src/ui/LogsUI.lua` and `src/ui/OfficerUI.lua`.
- [X] T040 [US4] Keep technical evidence collapsed by default and expandable without replacing the primary summary in `src/ui/LogsUI.lua` and `src/ui/OfficerUI.lua`.
- [X] T041 [US4] Preserve bounded paging, exact alias matching, unknown-field labels, related-winner context, stale checks, idempotency, and existing candidate classifications in `src/integrations/RCLootCouncil.lua`.
- [X] T042 [US4] Delegate Confirm as DIB and Reject actions through existing reconciliation and protected action paths with Officer/GM authorization, reason, confirmation, and combat/readiness handling in `src/ui/LogsUI.lua` and `src/modules/ProtectedActions.lua`.
- [X] T043 [US4] Add relevant non-destructive historical candidate context actions while preventing direct accounting/destructive execution from `src/ui/LogsUI.lua` and `src/ui/AceGUI.lua`.
- [X] T044 [US4] Preserve Player-safe confirmed-history projections and Officer-only technical evidence in `src/ui/PlayerUI.lua` and `src/ui/OfficerUI.lua`.

**Checkpoint**: User Story 4 is independently functional when historical review is preview-first, blocked candidates cannot be confirmed normally, protected decisions are auditable, and RCLootCouncil history remains unchanged.

---

## Phase 7: User Story 5 - Prove Retail Release Hardening (Priority: P1)

**Goal**: Produce repeatable automated and real Retail evidence for the complete B12 surface without misclassifying the known unrelated baseline failure.

**Independent Test**: Run focused B12 suites, the explicit full Fengari suite, diagnostics, whitespace checks, and the single-client Retail matrix for supported roles, routes, integrations, combat states, window sizes, and repeated lifecycle sequences.

### Tests for User Story 5

- [X] T045 [P] [US5] Add the focused B12 automated validation command, pass/fail accounting, baseline-failure handling, diagnostics, and `git diff --check` procedure to `specs/012-release-ui-stabilization/quickstart.md`.
- [X] T046 [P] [US5] Add the single-client Retail matrix checklist for ten open/close cycles, all routes, movement/restoration, context menus, Pre-Dib modes, combat transitions, RCLootCouncil states, privacy, and sandbox isolation to `docs/TEST_PLAN.md`.
- [X] T047 [P] [US5] Add conditional two-client scenarios and the explicit "not required" recording rule when no cross-client behavior changes to `docs/TEST_PLAN.md`.

### Implementation for User Story 5

- [X] T048 [US5] Run the focused B12 Fengari suites with `DIBS_TEST_FILES` and resolve every B12-attributable failure across `tests/unit/`, `tests/contract/`, and `tests/integration/`.
- [X] T049 [US5] Run the explicit full Fengari suite through the repository-supported command, preserve the known `tests/integration/rclootcouncil_buttons_spec.lua:155` baseline separately, and record counts in `docs/audits/B12_Release_UI_Hardening_Evidence.md`.
- [X] T050 [US5] Run workspace diagnostics on touched Lua/test files and `git diff --check -- specs/012-release-ui-stabilization src tests docs`, recording any unrelated baseline diagnostics separately in `docs/audits/B12_Release_UI_Hardening_Evidence.md`.
- [ ] T051 [US5] Execute and record the real single-client Retail matrix from `specs/012-release-ui-stabilization/quickstart.md`, including BugSack/diagnostic review and zero new Dibs-attributable Lua, taint, lifecycle, stale-content, or contamination findings in `docs/audits/B12_Retail_Validation_Evidence.md`.
- [X] T052 [US5] Run the conditional two-client matrix only if B12 changed cross-client behavior, otherwise record the no-cross-client-change decision in `docs/audits/B12_Retail_Validation_Evidence.md`.
- [X] T053 [US5] Validate `SANDBOX_STORE_TOO_LARGE` with bounded behavior, production isolation, default-off Developer Mode, and normal-user impact in `tests/unit/b11_sandbox_provider_spec.lua`, `tests/integration/b11_sandbox_lifecycle_spec.lua`, and `docs/audits/B12_Release_UI_Hardening_Evidence.md`.

**Checkpoint**: User Story 5 is independently functional when focused and full automated accounting is complete, real Retail evidence exists, required diagnostics are clean, and all known unrelated failures are explicitly identified.

---

## Phase 8: User Story 6 - Publish A Release Candidate (Priority: P2)

**Goal**: Produce an installable, traceable B12 release candidate with aligned version metadata, changelog, user/operator guidance, known limitations, and validation evidence.

**Independent Test**: Verify the candidate from a clean release state, inspect version and documentation alignment, install it in Retail, and complete documented Player and Officer workflows without Developer Mode.

### Tests for User Story 6

- [X] T054 [P] [US6] Add release-candidate record assertions for explicit version, automated evidence, Retail evidence, conditional two-client evidence, known limitations, changelog, and readiness gates in `tests/contract/b12_release_candidate_spec.lua`.
- [X] T055 [P] [US6] Add the final installation, supported-route, known-issues, and evidence-link checklist to `specs/012-release-ui-stabilization/quickstart.md` and `docs/TEST_PLAN.md`.

### Implementation for User Story 6

- [X] T056 [US6] Bump the explicit addon version in `src/RCLootCouncil_dibs.toc` and align the existing source version owner without changing SavedVariables or protocol versions.
- [X] T057 [US6] Add a dated B12 release-candidate entry to `CHANGELOG.md` covering scope, preserved business/security semantics, supported workflows, validation status, and known limitations.
- [X] T058 [US6] Align affected installation, Player, Officer/GM, troubleshooting, and developer-only limitation guidance in `README.md`, `docs/player/README.md`, `docs/officer/README.md`, and the relevant `docs/developer/` files.
- [X] T059 [US6] Create the final release-candidate evidence index in `docs/audits/B12_Release_Candidate_Evidence.md` linking version, changelog, automated results, Retail results, known baseline, sandbox limitation status, and publication decision.
- [ ] T060 [US6] Verify the packaged candidate with `scripts/deploy.ps1`, the documented install workflow, and the final Player/Officer route set, then mark readiness only when every required Retail gate and B12 blocker is resolved in `docs/audits/B12_Release_Candidate_Evidence.md`.

**Checkpoint**: User Story 6 is independently functional when the candidate is version-aligned, documented, installable, evidenced, and not labeled publishable before required Retail validation.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Reconcile all B12 artifacts, preserve the freeze boundary, and prepare the implementation for review and task completion.

- [X] T061 [P] Update `docs/developer/architecture.md`, `docs/developer/testing.md`, `docs/developer/saved-variables.md`, and `docs/developer/modules.md` only where B12 changes require documenting UI projection ownership, release validation, or the absence of new persistence/synchronization fields.
- [X] T062 [P] Review `specs/012-release-ui-stabilization/spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/release-ui.md`, and `quickstart.md` for contradictions, unsupported claims, stale placeholders, and missing B12 acceptance coverage.
- [X] T063 Run the complete quickstart validation, workspace diagnostics, and `git diff --check`, then confirm all task-linked evidence paths exist in `docs/audits/`.
- [X] T064 Confirm no B12 source path changes ledger/balance semantics, AWARD_COMMIT/AWARD_PROPOSAL, governance, coordinator/recovery, SyncV2, identity, production permissions, Pre-Dibs lifecycle, RCLootCouncil ownership/evidence, or sandbox provider isolation; record the result in `docs/audits/B12_Release_Candidate_Evidence.md`.
- [X] T065 Confirm release readiness is not claimed while real Retail validation or any B12-attributable blocker remains open, and leave the known unrelated RCLootCouncil baseline explicitly documented.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies; establishes B12 fixtures, baseline evidence, and ownership constraints.
- **Foundational (Phase 2)**: Depends on Setup; blocks all user-story implementation.
- **US1 (Phase 3, P1)**: Depends on Foundational and is the MVP; stabilizes the shared lifecycle and route boundary.
- **US2 (Phase 4, P1)**: Depends on US1 for the stable shell and content lifecycle; can proceed in parallel across page-specific test/source boundaries after US1's contract is fixed.
- **US3 (Phase 5, P1)**: Depends on US1 and the existing Disputes service; may proceed in parallel with US2 after shared lifecycle contracts pass.
- **US4 (Phase 6, P2)**: Depends on US1 and the existing Officer history/reconciliation surfaces; may proceed in parallel with US3 after shared lifecycle contracts pass.
- **US5 (Phase 7, P1)**: Depends on the desired US1-US4 implementation slices; its automated validation can begin as each slice lands, but the release hardening checkpoint requires all targeted stories.
- **US6 (Phase 8, P2)**: Depends on US5 and all required Retail evidence; publication tasks are blocked until the single-client matrix and any conditional two-client matrix are complete.
- **Polish (Phase 9)**: Depends on all desired stories and their evidence.

### User Story Dependencies

- **US1 (P1)**: Foundational only; MVP runtime stabilization.
- **US2 (P1)**: Depends on US1's shared Midnight shell, page ownership, and menu lifecycle.
- **US3 (P1)**: Depends on US1; uses existing `src/modules/Disputes.lua`, `src/modules/ProtectedActions.lua`, and permission services.
- **US4 (P2)**: Depends on US1; uses existing `src/integrations/RCLootCouncil.lua` and `src/modules/ProtectedActions.lua` authority.
- **US5 (P1)**: Depends on implementation slices from US1-US4; no two-client dependency unless cross-client behavior changes.
- **US6 (P2)**: Depends on US5 evidence and no unresolved B12-attributable blockers.

### Parallel Opportunities

- T002-T004 can run in parallel after the task list is accepted because they touch separate fixture/contract documentation files.
- T005-T007 can run in parallel after Setup; T008 is the boundary audit checkpoint.
- T009-T012 can run in parallel because they use separate focused test files; T013-T018 are sequenced by shared controller ownership, with T014 and T015 separable after the route contract is fixed.
- T019-T021 can run in parallel; T022-T026 should be split by page/component ownership to avoid concurrent edits to the same controller.
- T027-T029 can run in parallel; T030-T035 should follow the projection contract and be coordinated around `src/ui/OfficerUI.lua`.
- T036-T038 can run in parallel; T039-T044 should be sequenced around the shared history projection and protected delegation boundaries.
- T045-T047 can run in parallel as documentation/test procedures; T048-T053 are sequential evidence gates with independent test slices where available.
- T054-T055 can run in parallel; T056-T060 must follow the hardening gate and version alignment.
- T061-T062 can run in parallel; T063-T065 are final sequential checks.

## Parallel Example: User Story 1

```text
Task: T009 tests/integration/b12_release_ui_stabilization_spec.lua
Task: T010 tests/contract/b12_release_ui_contract_spec.lua
Task: T011 tests/integration/b12_window_state_spec.lua
Task: T012 tests/integration/b12_ui_ownership_spec.lua
```

## Parallel Example: User Story 3

```text
Task: T027 tests/integration/b12_requests_support_ticket_spec.lua
Task: T028 tests/contract/b12_requests_actions_spec.lua
Task: T029 tests/integration/b12_requests_context_menu_spec.lua
```

## Parallel Example: User Story 4

```text
Task: T036 tests/integration/b12_historical_transfer_spec.lua
Task: T037 tests/contract/b12_historical_transfer_actions_spec.lua
Task: T038 tests/unit/b12_historical_candidate_projection_spec.lua
```

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 Setup and Phase 2 Foundational tasks.
2. Complete US1 focused tests and runtime stabilization.
3. Run the US1 checkpoint, including existing B11 UI-004 regressions and the known baseline accounting.
4. Stop and validate the real Player/Officer lifecycle slice on Retail before starting page cleanup.

### Incremental Delivery

1. Add US2 targeted page cleanup only for demonstrated defects, then validate independently.
2. Add US3 support-ticket projections and protected request workflows, then validate independently.
3. Add US4 historical transfer presentation and delegation, then validate independently.
4. Run US5 hardening across the combined surface; record real Retail evidence.
5. Add US6 version, documentation, package, and publication evidence only after required Retail gates pass.
6. Finish the cross-cutting artifact and freeze-boundary review.

### Release Safety

- No task adds a new ledger, balance, award, authority, request lifecycle, synchronization, or RCLootCouncil ownership semantic.
- No task may treat Fengari, reduced clients, or simulated sandbox results as Retail certification.
- The known unrelated RCLootCouncil baseline remains visible and separately classified throughout implementation.
- Two-client validation is conditional only on a B12 cross-client behavior change.
- A remaining `SANDBOX_STORE_TOO_LARGE` limitation may be accepted only under the documented developer-only isolation conditions.

## Notes

- Every task uses the required checkbox, sequential ID, optional `[P]`, story label where applicable, and a concrete repository path.
- Story tests precede story implementation tasks.
- `tasks.md` is the output of this command; it does not claim that any task is complete.
- Commit creation is intentionally outside this task-generation workflow.
