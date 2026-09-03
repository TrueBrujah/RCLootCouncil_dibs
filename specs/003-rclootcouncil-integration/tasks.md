# Tasks: RCLootCouncil Permission Authority

**Input**: Design documents from specs/003-rclootcouncil-integration/

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup (Shared Infrastructure)

- [x] T001 Create dependency-free test runner in tests/run.lua
- [x] T002 [P] Implement resettable WoW API doubles in tests/helpers/wow_api.lua
- [x] T003 [P] Implement TOC-order addon loading and LibStub/Ace/RC doubles in tests/helpers/load_addon.lua
- [x] T004 Register modules/ProtectedActions.lua in addon load order in src/RCLootCouncil_dibs.toc

## Phase 2: Foundational

- [x] T005 Add versioned SavedVariables defaults and migration for permissions/award indexes in src/Core.lua
- [x] T006 [P] Add canonical identity helpers in src/modules/Permissions.lua
- [x] T007 [P] Define protected action identifiers and validation in src/modules/ProtectedActions.lua
- [x] T008 Implement AuthorityDecision and safe Evaluate/Can entry points in src/modules/Permissions.lua
- [x] T009 Implement authorization-before-business-validation pipeline in src/modules/ProtectedActions.lua
- [x] T010 Route slash mutations through ProtectedActions in src/Core.lua
- [x] T011 Route officer-window mutations through ProtectedActions in src/ui/OfficerUI.lua
- [x] T012 Add foundational authorization/audit tests in tests/unit/permissions_spec.lua

## Phase 3: User Story 1 - Respect RCLootCouncil Authority

- [x] T013 [P] [US1] Adapter contract tests in tests/contract/rclootcouncil_contract_spec.lua
- [x] T014 [P] [US1] Integration tests for allow/deny/no-fallback/degraded cases in tests/integration/rclootcouncil_adapter_spec.lua
- [x] T015 [P] [US1] Authorization matrix and performance tests in tests/integration/protected_actions_spec.lua
- [x] T016 [US1] Capability probing + late-load idempotence in src/integrations/RCLootCouncil.lua
- [x] T017 [US1] Fresh Master Looter authority evaluation with fail-closed codes in src/integrations/RCLootCouncil.lua
- [x] T018 [US1] Permissions.Evaluate RC-exclusive selection when present in src/modules/Permissions.lua
- [x] T019 [US1] Remove unsafe RC registry writes and monkey-patching in src/integrations/RCLootCouncil.lua
- [x] T020 [US1] Register idempotent local observers and refresh logic in src/integrations/RCLootCouncil.lua

## Phase 4: User Story 2 - Preserve Standalone Operation

- [x] T021 [P] [US2] Standalone authorization unit tests in tests/unit/standalone_admins_spec.lua
- [x] T022 [P] [US2] Standalone admin contract tests in tests/contract/standalone_admin_contract_spec.lua
- [x] T023 [US2] Standalone evaluation for GM + appointed admins in src/modules/Permissions.lua
- [x] T024 [US2] GM-only appoint/revoke invariants with immutable events in src/modules/Permissions.lua
- [x] T025 [US2] Protected standalone-admin command handlers in src/modules/ProtectedActions.lua
- [x] T026 [US2] Slash commands for admin list/appoint/revoke in src/Core.lua
- [x] T027 [US2] Officer UI admin controls and audit summary in src/ui/OfficerUI.lua

## Phase 5: User Story 3 - Keep Dibs Accounting Authoritative

- [x] T028 [P] [US3] Finalized-award idempotency tests in tests/integration/finalized_award_spec.lua
- [x] T029 [P] [US3] Ledger reconstruction + migration tests in tests/unit/ledger_award_spec.lua
- [x] T030 [US3] awardRef validation/index metadata in src/modules/Ledger.lua
- [x] T031 [US3] ProtectedActions.FinalizeAward idempotent ordering in src/modules/ProtectedActions.lua
- [x] T032 [US3] Pre-Dib fulfillment only after successful append in src/modules/PreDibs.lua
- [x] T033 [US3] RC award-success translation to FinalizeAward in src/integrations/RCLootCouncil.lua

## Phase 6: User Story 4 - Expose Dib Status Locally

- [x] T034 [P] [US4] Candidate projection and DIB eligibility tests in tests/unit/candidate_status_spec.lua
- [x] T035 [P] [US4] Privacy contract tests for sync payload exclusions in tests/contract/sync_privacy_spec.lua
- [x] T036 [US4] Read-only candidate projection and eligibility in src/integrations/RCLootCouncil.lua
- [x] T037 [US4] Capability-detected status exposure + Dibs UI fallback in src/integrations/RCLootCouncil.lua
- [x] T038 [US4] Sync allowlist excluding ephemeral session data in src/modules/Sync.lua
- [x] T039 [US4] Officer UI fallback status + unavailable diagnostics in src/ui/OfficerUI.lua

## Phase 7: Polish & Cross-Cutting

- [x] T040 [P] Localize authority/denial/admin/award/fallback strings in src/locales/enUS.lua and src/locales/frFR.lua
- [x] T041 Load locales from packaged addon root and remove hard-coded diagnostics in src/RCLootCouncil_dibs.toc
- [x] T042 Add combat-lockdown deferral tests in tests/integration/combat_safety_spec.lua
- [x] T043 Implement protected UI deferral until PLAYER_REGEN_ENABLED in src/ui/OfficerUI.lua
- [x] T044 [P] Document implemented vs planned behavior and compatibility in README.md and docs/ARCHITECTURE.md
- [x] T045 Run automated + in-client quickstart scenarios and record compatibility limitations in specs/003-rclootcouncil-integration/quickstart.md
- [x] T046 Verify migration preserves seasons/pre-dibs/ledger via fixtures in tests/integration/migration_spec.lua

## Status Summary

- Remaining unchecked tasks: 1
- Notes: In-client smoke remains environment-blocked here, and limitation is explicitly recorded in quickstart validation notes.

## Phase 8: Convergence

- [x] T047 Recreate missing 003 design artifacts plan.md, research.md, data-model.md, and contracts/*.md in specs/003-rclootcouncil-integration per spec requirements (missing)
- [x] T048 Restore automated test suites referenced by phases 1-7 under tests/unit, tests/integration, and tests/contract for 003 acceptance coverage (missing)
- [x] T049 Add a regression test ensuring src/RCLootCouncil_dibs.toc fails fast when any referenced Lua file is missing, covering locales and ProtectedActions paths in tests/integration/toc_load_spec.lua (missing)
- [x] T050 Add integration tests for ProtectedActions.Execute action matrix and denial diagnostics for season/rank/ledger/admin paths in tests/integration/protected_actions_matrix_spec.lua (missing)
- [x] T051 Add integration tests for award finalization semantics (non-final no-op, duplicate awardRef idempotency, Pre-Dib fulfillment ordering) in tests/integration/finalized_award_flow_spec.lua (partial)
- [ ] T052 Validate and record current in-client smoke outcomes on a real WoW client for RC-authority, standalone-admin governance, and combat UI deferral in specs/003-rclootcouncil-integration/quickstart.md (partial)
