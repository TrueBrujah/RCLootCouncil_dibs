# Tasks: First Installation Assistant

**Input**: Design documents from `/specs/014-first-installation-assistant/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/setup-assistant.md`, `quickstart.md`

## Phase 1: Setup

- [X] T001 Add the assistant module to `src/RCLootCouncil_dibs.toc` and `tests/helpers/load_addon.lua` without changing existing load order semantics.
- [X] T002 [P] Add focused assistant test registration notes to `specs/014-first-installation-assistant/quickstart.md` and `docs/TEST_PLAN.md`.

## Phase 2: Foundational

- [X] T003 [P] Add localized assistant labels, statuses, reason text, and remediation fallbacks to `src/locales/enUS.lua` and `src/locales/frFR.lua`.
- [X] T004 Define the bounded transient report and action normalization contract in `src/ui/SetupAssistant.lua` without adding SavedVariables or SyncV2 fields.

## Phase 3: User Story 1 - Inspect installation readiness (Priority: P1)

**Independent Test**: `tests/contract/setup_assistant_contract_spec.lua` returns all required checks and safe denial behavior for a player.

- [X] T005 [P] Add checklist projection contract coverage in `tests/contract/setup_assistant_contract_spec.lua`.
- [X] T006 Implement readiness, authority, season, policy, channel, loot-type, and RCLootCouncil check projection in `src/ui/SetupAssistant.lua`.
- [X] T007 Add a bounded assistant report surface to the Officer navigation in `src/ui/OfficerUI.lua` using existing Midnight/AceGUI lifecycle helpers.

## Phase 4: User Story 2 - Apply guided configuration safely (Priority: P1)

**Independent Test**: `tests/integration/setup_assistant_spec.lua` proves supported setup actions delegate to `ProtectedActions` and reject unauthorized or invalid input.

- [X] T008 [P] Add protected setup action delegation and rejection coverage in `tests/contract/setup_assistant_contract_spec.lua`.
- [X] T009 Implement canonical setup action validation and delegation in `src/ui/SetupAssistant.lua`.
- [X] T010 Connect supported action controls to existing Officer callbacks in `src/ui/OfficerUI.lua` without direct service mutation.

## Phase 5: User Story 3 - Run a local pre-raid test (Priority: P1)

**Independent Test**: The assistant dry-run leaves production state and addon transport unchanged.

- [X] T011 [P] Add dry-run isolation coverage in `tests/integration/setup_assistant_spec.lua`.
- [X] T012 Delegate assistant dry-run execution to `Dibs.DryRun` and expose bounded outcome text in `src/ui/SetupAssistant.lua`.

## Phase 6: Polish and validation

- [X] T013 [P] Add English/French player and Officer guide references in `docs/player/`, `docs/officer/`, and `docs/developer/testing.md`.
- [X] T014 Run focused and full Fengari suites, `get_errors`, and `git diff --check`; record evidence in `docs/audits/B14_Implementation_Evidence.md`.
- [ ] T015 Perform one-client Retail validation for protected UI, combat safety, RCLootCouncil absence/degradation, and local dry-run behavior in `docs/audits/B14_Retail_Validation_Checklist.md`.

## Dependencies & Execution Order

- Setup and Foundational precede all user stories.
- User Story 1 provides the report consumed by User Stories 2 and 3.
- User Stories 2 and 3 can proceed in parallel after the report contract is stable.
- Retail validation remains a release gate and cannot be replaced by Fengari evidence.

## MVP Scope

T001-T007: a read-only assistant report with explicit readiness checks and safe role filtering. Add T008-T012 for the first usable configuration and dry-run workflow.
