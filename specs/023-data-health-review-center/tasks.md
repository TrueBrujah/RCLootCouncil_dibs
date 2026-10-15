# Tasks: Data Health Review Center

**Input**: Design documents from `/specs/023-data-health-review-center/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/health-review-contract.md`, and `quickstart.md`

**Organization**: Tasks are grouped by user story so review discovery, safe routing, and privacy-preserving export can be implemented and tested incrementally.

## Phase 1: Setup

**Purpose**: Confirm the current Diagnostics route and focused test selection before extending the existing health functionality.

- [X] T001 Review the Diagnostics route and current anomaly contract in `src/ui/OfficerUI.lua`, `src/ui/HealthUI.lua`, `tests/contract/health_anomaly_contract_spec.lua`, and `tests/integration/health_dashboard_ui_spec.lua`

## Phase 2: Foundational

**Purpose**: Establish a safe finding projection and explicit status contract shared by all stories.

- [X] T002 [P] Add reusable synthetic transaction, acquisition, and Vault conflict cases to `tests/contract/health_anomaly_contract_spec.lua`
- [X] T003 Define stable finding categories and explicit source availability in `src/ui/HealthUI.lua`

## Phase 3: User Story 1 - Review guild data health (Priority: P1)

**Goal**: Show authorized Officers a grouped, guild-scoped list of verifiable data findings.

**Independent Test**: Create synthetic invalid season references, malformed or duplicate acquisitions, and unresolved Vault conflicts; verify stable categories, explicit unavailable/empty states, deterministic ordering, and no cross-guild findings.

### Tests

- [X] T004 [P] [US1] Extend scan contract tests for malformed, duplicate, incomplete, conflicting, unavailable-source, and denied-authority cases in `tests/contract/health_anomaly_contract_spec.lua`
- [X] T005 [P] [US1] Extend Diagnostics UI tests for grouped finding rows, empty state, unavailable state, and authorized-only visibility in `tests/integration/health_dashboard_ui_spec.lua`

### Implementation

- [X] T006 [US1] Expand `HealthUI.ScanAnomalies` to project invalid ledger references, malformed/incomplete and duplicate acquisitions, unresolved Vault conflicts, and explicit source availability without returning source records in `src/ui/HealthUI.lua`
- [X] T007 [US1] Add a localized findings section and bounded table to the existing Officer Diagnostics page while preserving the operational health dashboard in `src/ui/OfficerUI.lua`, `src/locales/enUS.lua`, and `src/locales/frFR.lua`

## Phase 4: User Story 2 - Preview and route a controlled review (Priority: P1)

**Goal**: Give Officers a read-only preview and route supported Vault findings into the existing audited review workflow.

**Independent Test**: Preview findings and verify `mutation = "NONE"`; confirm Vault findings open the Vault route and unsupported corrections remain investigation-only.

### Tests

- [X] T008 [P] [US2] Extend contract coverage for read-only previews, unknown findings, permission changes, and safe next-action values in `tests/contract/health_anomaly_contract_spec.lua`
- [X] T009 [P] [US2] Add UI interaction coverage for preview display and navigation to the existing Vault review page in `tests/integration/health_dashboard_ui_spec.lua`

### Implementation

- [X] T010 [US2] Make `HealthUI.BuildCorrectionPreview` recheck authority and return only safe finding details, `mutation = "NONE"`, and an existing-workflow hint in `src/ui/HealthUI.lua`
- [X] T011 [US2] Add preview and authorized Vault-review navigation actions without duplicating Vault resolution logic in `src/ui/OfficerUI.lua`

## Phase 5: User Story 3 - Export findings for investigation (Priority: P2)

**Goal**: Export bounded category/count diagnostics that cannot disclose identities or be imported as transactions.

**Independent Test**: Encode synthetic findings containing identifiable names and private payload sentinels; assert neither those values nor record IDs are present, the health prefix is distinct from import packages, and source data is unchanged.

### Tests

- [X] T012 [P] [US3] Extend export contract tests for aggregate-only shape, identity/private-payload redaction, bounds, denied authority, encoder failure, and non-importability in `tests/contract/health_anomaly_contract_spec.lua`
- [X] T013 [P] [US3] Add UI export interaction and explicit failure-state coverage in `tests/integration/health_dashboard_ui_spec.lua`

### Implementation

- [X] T014 [US3] Project only bounded version/schema metadata, timestamp, total count, source status, and sorted category counts in `HealthUI.ExportAnomalies` in `src/ui/HealthUI.lua`
- [X] T015 [US3] Add a localized export action to Diagnostics using the existing report-copy interaction pattern and surface encoding/permission failures in `src/ui/OfficerUI.lua`, `src/locales/enUS.lua`, and `src/locales/frFR.lua`

## Phase 6: Polish and cross-cutting validation

**Purpose**: Verify bounded behavior, documentation, regression safety, and manual Retail gates.

- [X] T016 [P] Add a large synthetic fixture and scan-time assertion for 5,000 ledger transactions and 1,000 acquisitions in `tests/contract/health_anomaly_contract_spec.lua`
- [X] T017 Update the health-center contract and Retail checklist in `specs/023-data-health-review-center/quickstart.md` and `specs/023-data-health-review-center/contracts/health-review-contract.md`
- [X] T018 Run focused Fengari suites (100 tests passed across 22 files) and `git diff --check`; record one-client Great Vault Retail validation as pending (see T051/T052 in `specs/013-great-vault-acquisition-sync/tasks.md`)

## Dependencies

- T001 precedes all implementation.
- T002 and T003 are foundational prerequisites for the user stories.
- User Story 1 (T004-T007) precedes User Story 2 (T008-T011) and User Story 3 (T012-T015), because previews and exports consume the finding projection.
- User Story 2 and User Story 3 are otherwise independent after User Story 1.
- T016-T018 are final validation and documentation tasks.

## Parallel Execution Examples

- After T001, T002 and initial UI contract inspection may be prepared in parallel; T003 must be complete before story behavior is implemented.
- Within User Story 1, T004 and T005 can be authored in parallel; T006 must precede T007.
- Within User Story 2, T008 and T009 can be authored in parallel; T010 must precede T011.
- Within User Story 3, T012 and T013 can be authored in parallel; T014 must precede T015.
- T016 and T017 can run in parallel after the stories are complete.

## Implementation Strategy

1. Deliver the P1 findings list first, keeping existing Diagnostics and Vault behavior intact.
2. Add the preview/navigation slice using the existing audited Vault review workflow.
3. Add safe aggregate-only export as a separately testable P2 slice.
4. Complete automated and documentation checks; leave Retail-only validation explicitly pending if no test client is available.
