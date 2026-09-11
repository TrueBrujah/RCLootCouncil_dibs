---

description: "Task list for Dibs backups, data transfer, and configuration profiles"

---

# Tasks: Dibs Backups, Data Transfer, and Configuration Profiles

**Input**: Design documents from `/specs/007-backup-export-import-profiles/`

**Status**: Implemented in 0.5.6-dev; Retail visual validation remains scheduled.

## Phase 1: Setup

- [x] T001 [P] Define package scopes, sensitivity labels, schema versions, and checksums in `src/modules/ImportExport.lua`.
- [x] T002 [P] Add valid, malformed, tampered, truncated, and future-version fixtures in `tests/helpers/package_fixtures.lua`.
- [x] T003 [P] Add migration/version and retention notes in `src/Core.lua` and `CHANGELOG.md`.

## Phase 2: Foundational

- [x] T004 Implement data-only package encoding/decoding and strict validation in `src/modules/ImportExport.lua`.
- [x] T005 Implement guild/character scope isolation and sensitivity filtering in `src/Core.lua` and `src/modules/ImportExport.lua`.
- [x] T006 Add checksum, size, schema, and unknown-field handling in `src/modules/ImportExport.lua`.
- [x] T007 Add pre-operation safety snapshots, bounded retention, and recovery state in `src/modules/Backup.lua`.
- [x] T008 Route policy and ledger mutation through authority and protected actions in `src/modules/ProtectedActions.lua`.

## Phase 3: US1 - Create and restore a safety backup (P1)

- [x] T009 [P] [US1] Add backup/restore preview, cancel, failure, and no-mutation tests in `tests/integration/backup_spec.lua`.
- [x] T010 [US1] Implement backup creation/listing/checksum/retention UI in `src/integrations/RCLootCouncilOptions.lua`.
- [x] T011 [US1] Implement restore preview, confirmation, and recovery-point selection in `src/modules/Backup.lua` and `src/integrations/RCLootCouncilOptions.lua`.
- [x] T012 [US1] Audit backup, restore, rejection, and failure outcomes in `src/modules/Backup.lua` and `src/modules/Ledger.lua`.

## Phase 4: US2 - Manage configuration profiles (P1)

- [x] T013 [P] [US2] Add local/guild profile isolation and ledger invariance tests in `tests/contract/profile_scope_spec.lua`.
- [x] T014 [US2] Implement named profile create/copy/rename/activate/reset/delete in `src/modules/Profiles.lua`.
- [x] T015 [US2] Separate presentation from authoritative policy fields and warn before policy activation in `src/modules/Profiles.lua`.
- [x] T016 [US2] Expose profile lifecycle and scope labels in `src/integrations/RCLootCouncilOptions.lua`.

## Phase 5: US3 - Export and import portable data (P1)

- [x] T017 [P] [US3] Add configuration/full-data export and import preview tests in `tests/integration/import_export_spec.lua`.
- [x] T018 [US3] Implement scope-aware export and redaction in `src/modules/ImportExport.lua`.
- [x] T019 [US3] Implement merge/replace configuration strategies with explicit confirmation in `src/modules/ImportExport.lua`.
- [x] T020 [US3] Validate and append/deduplicate full-data transactions in `src/modules/Ledger.lua`.
- [x] T021 [US3] Add import preview, conflict, migration, and sensitivity UI in `src/integrations/RCLootCouncilOptions.lua`.

## Phase 6: US4/US5 - Protect privacy and migrate versions (P1/P2)

- [x] T022 [P] [US4] Add player/ML/Officer/GM authority and privacy tests in `tests/integration/import_export_spec.lua`.
- [x] T023 [US4] Reject authority, identity, cross-guild, executable-looking, and unsafe package fields in `src/modules/ImportExport.lua`.
- [x] T024 [US5] Implement supported schema migrations and future-version rejection in `src/modules/ImportExport.lua` and `src/Core.lua`.
- [x] T025 [US5] Keep standalone and RCLootCouncil integration scopes independent in `src/integrations/RCLootCouncil.lua`.

## Phase 7: Polish and release

- [x] T026 [P] Update `docs/ARCHITECTURE.md`, `docs/RC_OPTIONS.md`, `README.md`, and `CHANGELOG.md`.
- [x] T027 [P] Run full suite, migration/failure-injection tests, and Retail validation in `specs/007-backup-export-import-profiles/quickstart.md`.
- [x] T028 Review the implementation against `spec.md`, `plan.md`, contracts, and `.specify/memory/constitution.md` before versioning.

## Dependencies

Phase 2 blocks every story. Backups and profile scope establish safety boundaries; export
and import depend on those boundaries; migration and privacy checks complete the release
gate. Tests should precede each implementation slice.
