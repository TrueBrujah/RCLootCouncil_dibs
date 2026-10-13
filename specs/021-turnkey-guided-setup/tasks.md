---

description: "Implementation tasks for the turnkey Guided Setup workflow"
---

# Tasks: Turnkey Guided Setup

**Input**: Design documents from `/specs/021-turnkey-guided-setup/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Focused contract and integration tests are required because the feature changes authorization-sensitive setup orchestration and Officer UI behavior.

**Organization**: Tasks are grouped by user story so each user journey remains independently testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because it affects different files and has no incomplete dependency
- **[Story]**: User story from `spec.md`
- Every task names its affected path

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish localization and test surfaces without adding new dependencies.

- [X] T001 Add English and French turnkey setup locale keys for stages, profiles, guidance, severity, effects, and correction actions in `src/locales/enUS.lua` and `src/locales/frFR.lua`
- [X] T002 [P] Create the Guided Setup contract test scaffold in `tests/contract/turnkey_guided_setup_contract_spec.lua`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Define shared profile, preview, stage, and verification projections used by every story.

**⚠️ CRITICAL**: No story UI can be implemented until these projections exist.

- [X] T003 Add static profile definitions and defensive-copy access through `Dibs.Wizard.GetProfiles` in `src/modules/Wizard.lua`
- [X] T004 Add per-character three-stage and selected-profile state accessors in `src/modules/Wizard.lua`
- [X] T005 Add deterministic profile preview projection with preservation, authority, and deferred-action details in `src/modules/Wizard.lua`
- [X] T006 Add grouped verification projection that maps existing checks to blocking, warning, ready, or optional results with correction routes in `src/modules/Wizard.lua`

**Checkpoint**: Profiles and fresh authoritative verification are available without changing guild state.

---

## Phase 3: User Story 1 - Complete a Turnkey Setup (Priority: P1) 🎯 MVP

**Goal**: An authorized administrator can choose, review, apply, and verify a recommended setup through three primary stages.

**Independent Test**: A fresh guild-leader fixture selects Progression, previews and applies it twice, sees no duplicate revisions, and reaches Verify without navigating fourteen pages.

### Tests for User Story 1

- [X] T007 [US1] Add failing contract tests for profile enumeration, preview shape, unknown/custom profiles, partial failures, and idempotent apply behavior in `tests/contract/turnkey_guided_setup_contract_spec.lua`
- [X] T008 [US1] Add failing three-stage first-install and repeated-apply integration tests in `tests/integration/guided_setup_wizard_spec.lua`

### Implementation for User Story 1

- [X] T009 [US1] Implement explicit idempotent `Dibs.Wizard.ApplyProfile` orchestration over existing installation and loot-rule preset services in `src/modules/Wizard.lua`
- [X] T010 [US1] Replace fourteen primary step buttons with Choose, Configure, and Verify stage rendering in `src/ui/OfficerUI.lua`
- [X] T011 [US1] Add profile selection, reviewed change summary, explicit apply confirmation, and per-action result rendering in `src/ui/OfficerUI.lua`

**Checkpoint**: The recommended first-time flow is functional and independently testable.

---

## Phase 4: User Story 2 - Understand Every Setup Decision (Priority: P1)

**Goal**: Users understand purpose, effects, preserved data, authority, and expected outcome without external documentation.

**Independent Test**: A tester can identify what each profile changes and preserves from the Choose and Configure stages alone.

### Tests for User Story 2

- [X] T012 [US2] Add failing documentation-content and English-fallback assertions to `tests/contract/turnkey_guided_setup_contract_spec.lua`

### Implementation for User Story 2

- [X] T013 [US2] Render concise stage guidance plus structured profile benefits, changes, preserved data, and deferred work in `src/ui/OfficerUI.lua`
- [X] T014 [US2] Wire all new setup text through localized English and French strings in `src/ui/OfficerUI.lua`, `src/locales/enUS.lua`, and `src/locales/frFR.lua`

**Checkpoint**: The workflow is self-documenting without obscuring its primary actions.

---

## Phase 5: User Story 3 - Find and Correct Missing Work (Priority: P1)

**Goal**: True blockers are red, explained, prioritized, and linked directly to correction; warnings remain non-red.

**Independent Test**: A missing required rank rule appears as a red Blocking result with an Open Rank Rules action while absent RCLootCouncil and inactive raid context remain warning/optional.

### Tests for User Story 3

- [X] T015 [US3] Add failing severity, primary-blocker precedence, warning classification, and correction-route contract tests in `tests/contract/turnkey_guided_setup_contract_spec.lua`
- [X] T016 [US3] Add failing Officer UI tests for red blocker badges, non-red warnings, correction navigation, and preserved setup progress in `tests/integration/guided_setup_wizard_spec.lua`

### Implementation for User Story 3

- [X] T017 [US3] Render verification results with Midnight semantic badges, explicit severity text, cause, impact, next action, and direct correction buttons in `src/ui/OfficerUI.lua`
- [X] T018 [US3] Implement primary unresolved-issue navigation and return-state preservation in `src/ui/OfficerUI.lua` and `src/modules/Wizard.lua`

**Checkpoint**: Every true blocker is visible and actionable without misclassifying optional context.

---

## Phase 6: User Story 4 - Retain Advanced Control (Priority: P2)

**Goal**: Experienced administrators retain access to authoritative advanced configuration without automatic overwrite.

**Independent Test**: Custom mode performs no mutation, opens advanced pages, and reflects subsequent authoritative changes on return.

### Tests for User Story 4

- [X] T019 [US4] Add failing custom-mode no-mutation and advanced-route refresh tests in `tests/integration/guided_setup_wizard_spec.lua`

### Implementation for User Story 4

- [X] T020 [US4] Add custom-profile advanced configuration actions and fresh-state return behavior in `src/ui/OfficerUI.lua`

**Checkpoint**: Simplification coexists with existing specialized pages.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Validate compatibility, documentation, performance, and release notes.

- [X] T021 Update the Unreleased changelog and officer setup guides in `CHANGELOG.md`, `docs/officer/GM_OFFICER_GUIDE_EN.md`, and `docs/officer/MODE_EMPLOI_GM_OFFICER.md`
- [X] T022 Run the focused suites from `specs/021-turnkey-guided-setup/quickstart.md` and fix regressions in affected source/test files
- [X] T023 Run existing Officer navigation, readiness, policy, and UI cleanup suites covering `src/modules/Wizard.lua` and `src/ui/OfficerUI.lua`
- [X] T024 Run `git diff --check` and verify serialized identifiers, ledger transactions, and unrelated worktree changes remain untouched

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1** has no dependency.
- **Phase 2** depends on Phase 1 locale/test scaffolding and blocks all stories.
- **US1** depends on Phase 2 and provides the MVP workflow.
- **US2** depends on the US1 stage UI.
- **US3** depends on the foundational verification projection and US1 Verify stage.
- **US4** depends on US1 navigation but not on US2 copy completion.
- **Polish** depends on all selected stories.

### User Story Dependencies

- **US1**: Foundational only.
- **US2**: US1 UI structure.
- **US3**: Foundational verification plus US1 Verify stage.
- **US4**: US1 stage navigation.

### Parallel Opportunities

- T002 can run in parallel with T001.
- Contract-test additions and integration-test additions for the same story can be prepared in parallel when they touch separate files.
- US2 localization review can run in parallel with US3 verification rendering after the shared stage UI is stable.
- Documentation updates can be prepared independently after behavior is final.

---

## Parallel Example: User Story 3

```text
Task: "Add severity and route contract tests in tests/contract/turnkey_guided_setup_contract_spec.lua"
Task: "Add semantic UI and correction-navigation tests in tests/integration/guided_setup_wizard_spec.lua"
```

---

## Implementation Strategy

### MVP First

1. Complete locale/test scaffolding.
2. Build profiles, previews, stage state, and grouped verification.
3. Add failing US1 tests.
4. Implement idempotent apply orchestration.
5. Replace fourteen primary steps with the three-stage UI.
6. Validate first-time and existing-guild behavior.

### Incremental Delivery

1. **MVP**: Choose → Configure → Verify works safely.
2. **Documentation**: Effects and preserved state are understandable in context.
3. **Correction UX**: True blockers are red and directly actionable.
4. **Advanced mode**: Existing specialized controls remain reachable.
5. **Polish**: Guides, compatibility suites, and Retail checklist.
