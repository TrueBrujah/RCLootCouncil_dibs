---

description: "Task list for RCLootCouncil history reconciliation"

---

# Tasks: RCLootCouncil History Reconciliation and Dibs Evidence

**Input**: Design documents from `/specs/006-rclootcouncil-history-reconciliation/`

**Status**: Draft roadmap; implementation has not started.

## Phase 1: Setup

- [ ] T001 [P] Add history-row, alias, finalization, and absent-integration fixtures in `tests/helpers/wow_api.lua`.
- [ ] T002 [P] Define reconciliation reason codes and localized labels in `src/locales/enUS.lua` and `src/locales/frFR.lua`.
- [ ] T003 [P] Add the reconciliation schema/version migration notes in `src/Core.lua` and `specs/006-rclootcouncil-history-reconciliation/quickstart.md`.

## Phase 2: Foundational

- [ ] T004 Define guild/season-scoped alias normalization and history candidate states in `src/integrations/RCLootCouncil.lua`.
- [ ] T005 Add immutable evidence and decision schema helpers in `src/modules/Ledger.lua` and `src/Core.lua`.
- [ ] T006 Route every historical debit through protected GM/Officer authority and append-only accounting in `src/modules/ProtectedActions.lua`.
- [ ] T007 Add stable identity/evidence-link deduplication across reloads and concurrent confirmation in `src/modules/Ledger.lua`.

## Phase 3: US1 - Start a controlled historical search (P1)

- [ ] T008 [P] [US1] Add preview-count and no-mutation tests in `tests/integration/rclootcouncil_history_reconciliation_spec.lua`.
- [ ] T009 [US1] Add the Officer reconciliation form with season, scope, aliases, and review mode in `src/integrations/RCLootCouncilOptions.lua` and `src/ui/OfficerUI.lua`.
- [ ] T010 [US1] Implement bounded, read-only history discovery and preview state in `src/integrations/RCLootCouncil.lua`.
- [ ] T011 [US1] Hide/reject the action for non-GM/Officer actors and explain unavailable integration states in `src/modules/Permissions.lua` and `src/ui/OfficerUI.lua`.

## Phase 4: US2 - Find candidates with custom labels (P1)

- [ ] T012 [P] [US2] Add alias normalization, localized, test, pending, and ambiguous-row tests in `tests/contract/rclootcouncil_reconciliation_spec.lua`.
- [ ] T013 [US2] Implement explicit alias matching while preserving original response text and identity in `src/integrations/RCLootCouncil.lua`.
- [ ] T014 [US2] Classify final status, item, winner, stable identity, duplicate, and unsupported evidence in `src/integrations/RCLootCouncil.lua`.
- [ ] T015 [US2] Add candidate filters, bounded paging, and row reasons in `src/ui/OfficerUI.lua`.

## Phase 5: US3 - Review and confirm historical awards (P1)

- [ ] T016 [P] [US3] Add guided/manual confirmation, duplicate, and partial-batch tests in `tests/integration/rclootcouncil_history_reconciliation_spec.lua`.
- [ ] T017 [US3] Implement guided confirmation through `ProtectedActions.FinalizeAward` or its historical equivalent in `src/modules/ProtectedActions.lua`.
- [ ] T018 [US3] Implement manual acknowledgement/reason validation in `src/ui/OfficerUI.lua` and `src/integrations/RCLootCouncilOptions.lua`.
- [ ] T019 [US3] Persist historical evidence and audit decisions without rewriting existing transactions in `src/modules/Ledger.lua`.

## Phase 6: US4/US5 - Evidence, privacy, and seasons (P1/P2)

- [ ] T020 [P] [US4] Add Officer/player privacy and evidence completeness tests in `tests/integration/rclootcouncil_history_reconciliation_spec.lua`.
- [ ] T021 [US4] Render complete Officer evidence and concise player-safe summaries in `src/ui/OfficerUI.lua` and `src/ui/PlayerUI.lua`.
- [ ] T022 [US5] Add target-season/date-range validation and original/import timestamp handling in `src/integrations/RCLootCouncil.lua` and `src/modules/Ledger.lua`.
- [ ] T023 [US5] Keep guild and character scopes isolated during preview and confirmation in `src/Core.lua`.

## Phase 7: Polish and release

- [ ] T024 [P] Update `docs/ARCHITECTURE.md`, `docs/RC_OPTIONS.md`, `README.md`, and `CHANGELOG.md`.
- [ ] T025 [P] Run the full suite, `git diff --check`, migration tests, and the Retail workflow in `specs/006-rclootcouncil-history-reconciliation/quickstart.md`.
- [ ] T026 Review the implementation against `spec.md`, `plan.md`, contracts, and `.specify/memory/constitution.md` before versioning.

## Dependencies

Phase 2 blocks all user stories. US1 establishes the preview, US2 supplies candidate
classification, US3 consumes only confirmed candidates, and US4/US5 add privacy and
cross-season evidence. Tests should be written before each implementation slice.
