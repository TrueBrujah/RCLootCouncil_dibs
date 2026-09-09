---

description: "Task list for Raid Readiness and Dry-Run Center"

---

# Tasks: Raid Readiness and Dry-Run Center

**Input**: Design documents from `/specs/008-raid-readiness-dry-run/`

**Status**: Draft roadmap; implementation has not started.

## Phase 1: Setup

- [ ] T001 [P] Define readiness states, probe reason codes, freshness markers, and report scopes in `src/modules/Readiness.lua`.
- [ ] T002 [P] Add valid/degraded/blocked/unavailable fixtures in `tests/helpers/rclootcouncil_fixtures.lua`.
- [ ] T003 [P] Add diagnostic localization and changelog/version notes in `src/locales/enUS.lua`, `src/locales/frFR.lua`, and `CHANGELOG.md`.

## Phase 2: Foundational

- [ ] T004 Implement standalone versus live integration capability probes in `src/modules/Readiness.lua`.
- [ ] T005 Implement freshness/configuration fingerprint and invalidation hooks in `src/modules/Readiness.lua` and `src/Core.lua`.
- [ ] T006 Define pure award validation input/output shared by live and dry-run paths in `src/integrations/RCLootCouncil.lua`.
- [ ] T007 Add bounded readiness audit/report storage without retaining live loot state in `src/modules/Readiness.lua`.

## Phase 3: US1 - Check raid readiness (P1)

- [ ] T008 [P] [US1] Add status, probe, freshness, no-group, no-channel, and no-mutation tests in `tests/integration/raid_readiness_spec.lua`.
- [ ] T009 [US1] Implement readiness evaluation and remediation details in `src/modules/Readiness.lua`.
- [ ] T010 [US1] Expose Officer readiness action and player-safe summary in `src/integrations/RCLootCouncilOptions.lua` and `src/ui/PlayerUI.lua`.
- [ ] T011 [US1] Add authorized slash-command entry point and combat-safe deferral in `src/Core.lua` and `src/ui/OfficerUI.lua`.

## Phase 4: US2 - Test finalized Dibs safely (P1)

- [ ] T012 [P] [US2] Add valid, invalid, test-status, replay, absent-integration, and no-side-effect tests in `tests/contract/raid_dry_run_spec.lua`.
- [ ] T013 [US2] Implement bounded synthetic dry-run cases/results using pure validation in `src/modules/DryRun.lua`.
- [ ] T014 [US2] Expose dry-run form and deterministic outcome/reason display in `src/integrations/RCLootCouncilOptions.lua`.
- [ ] T015 [US2] Ensure no events, traffic, idempotency records, ledger writes, or RC SavedVariables changes in `src/modules/DryRun.lua`.

## Phase 5: US3/US4 - Explain failures and share reports (P1/P2)

- [ ] T016 [P] [US3] Add remediation, authority, and consumption-gate tests in `tests/integration/raid_readiness_spec.lua`.
- [ ] T017 [US3] Add live-award safety gate revalidation in `src/integrations/RCLootCouncil.lua`.
- [ ] T018 [US3] Render reason code, impact, remediation, and local-test availability in `src/integrations/RCLootCouncilOptions.lua`.
- [ ] T019 [P] [US4] Add safe/detailed privacy report tests in `tests/integration/raid_readiness_spec.lua`.
- [ ] T020 [US4] Implement safe and Officer report generation/copy in `src/modules/Readiness.lua` and `src/ui/DebugLogsUI.lua`.

## Phase 6: US5 - Gate unsafe live behavior (P2)

- [ ] T021 [P] [US5] Add Ready/Degraded/Blocked award-gate replay tests in `tests/integration/raid_readiness_spec.lua`.
- [ ] T022 [US5] Connect the current safety gate to protected finalized-award accounting without granting administration in `src/integrations/RCLootCouncil.lua`.
- [ ] T023 [US5] Preserve standalone authority and block only unverifiable production consumption in `src/modules/Permissions.lua` and `src/modules/ProtectedActions.lua`.

## Phase 7: Polish and release

- [ ] T024 [P] Update `docs/ARCHITECTURE.md`, `docs/RC_OPTIONS.md`, `README.md`, and `CHANGELOG.md`.
- [ ] T025 [P] Run full suite, privacy/combat checks, and one-/two-client Retail validation in `specs/008-raid-readiness-dry-run/quickstart.md`.
- [ ] T026 Review implementation against `spec.md`, `plan.md`, contracts, and `.specify/memory/constitution.md` before versioning.

## Dependencies

Phase 2 blocks all stories. US1 establishes probes and freshness; US2 reuses pure validation;
US3/US4 add explanations and reports; US5 connects the safety gate to the live award path.
Tests precede each implementation slice.
