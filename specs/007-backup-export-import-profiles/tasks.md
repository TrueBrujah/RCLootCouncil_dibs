---

description: "Task list for Dibs backups, data transfer, and configuration profiles"

---

# Tasks: Dibs Backups, Data Transfer, and Configuration Profiles

**Input**: Design documents from `/specs/007-backup-export-import-profiles/`

**Status**: Draft roadmap; implementation has not started.

## Phase 1: Setup

- [ ] T001 [P] Define package scopes, sensitivity labels, schema versions, and checksums in `src/modules/ImportExport.lua`.
- [ ] T002 [P] Add valid, malformed, tampered, truncated, and future-version fixtures in `tests/helpers/package_fixtures.lua`.
- [ ] T003 [P] Add migration/version and retention notes in `src/Core.lua` and `CHANGELOG.md`.

## Phase 2: Foundational

- [ ] T004 Implement data-only package encoding/decoding and strict validation in `src/modules/ImportExport.lua`.
- [ ] T005 Implement guild/character scope isolation and sensitivity filtering in `src/Core.lua` and `src/modules/ImportExport.lua`.
- [ ] T006 Add checksum, size, schema, and unknown-field handling in `src/modules/ImportExport.lua`.
- [ ] T007 Add pre-operation safety snapshots, bounded retention, and recovery state in `src/modules/Backup.lua`.
- [ ] T008 Route policy and ledger mutation through authority and protected actions in `src/modules/ProtectedActions.lua`.

## Phase 3: US1 - Create and restore a safety backup (P1)

- [ ] T009 [P] [US1] Add backup/restore preview, cancel, failure, and no-mutation tests in `tests/integration/backup_spec.lua`.
- [ ] T010 [US1] Implement backup creation/listing/checksum/retention UI in `src/integrations/RCLootCouncilOptions.lua`.
- [ ] T011 [US1] Implement restore preview, confirmation, and recovery-point selection in `src/modules/Backup.lua` and `src/integrations/RCLootCouncilOptions.lua`.
- [ ] T012 [US1] Audit backup, restore, rejection, and failure outcomes in `src/modules/Backup.lua` and `src/modules/Ledger.lua`.

## Phase 4: US2 - Manage configuration profiles (P1)

- [ ] T013 [P] [US2] Add local/guild profile isolation and ledger invariance tests in `tests/contract/profile_scope_spec.lua`.
- [ ] T014 [US2] Implement named profile create/copy/rename/activate/reset/delete in `src/modules/Profiles.lua`.
- [ ] T015 [US2] Separate presentation from authoritative policy fields and warn before policy activation in `src/modules/Profiles.lua`.
- [ ] T016 [US2] Expose profile lifecycle and scope labels in `src/integrations/RCLootCouncilOptions.lua`.

## Phase 5: US3 - Export and import portable data (P1)

- [ ] T017 [P] [US3] Add configuration/full-data export and import preview tests in `tests/integration/import_export_spec.lua`.
- [ ] T018 [US3] Implement scope-aware export and redaction in `src/modules/ImportExport.lua`.
- [ ] T019 [US3] Implement merge/replace configuration strategies with explicit confirmation in `src/modules/ImportExport.lua`.
- [ ] T020 [US3] Validate and append/deduplicate full-data transactions in `src/modules/Ledger.lua`.
- [ ] T021 [US3] Add import preview, conflict, migration, and sensitivity UI in `src/integrations/RCLootCouncilOptions.lua`.

## Phase 6: US4/US5 - Protect privacy and migrate versions (P1/P2)

- [ ] T022 [P] [US4] Add player/ML/Officer/GM authority and privacy tests in `tests/integration/import_export_spec.lua`.
- [ ] T023 [US4] Reject authority, identity, cross-guild, executable-looking, and unsafe package fields in `src/modules/ImportExport.lua`.
- [ ] T024 [US5] Implement supported schema migrations and future-version rejection in `src/modules/ImportExport.lua` and `src/Core.lua`.
- [ ] T025 [US5] Keep standalone and RCLootCouncil integration scopes independent in `src/integrations/RCLootCouncil.lua`.

## Phase 7: Polish and release

- [ ] T026 [P] Update `docs/ARCHITECTURE.md`, `docs/RC_OPTIONS.md`, `README.md`, and `CHANGELOG.md`.
- [ ] T027 [P] Run full suite, migration/failure-injection tests, and Retail validation in `specs/007-backup-export-import-profiles/quickstart.md`.
- [ ] T028 Review the implementation against `spec.md`, `plan.md`, contracts, and `.specify/memory/constitution.md` before versioning.

## Dependencies

Phase 2 blocks every story. Backups and profile scope establish safety boundaries; export
and import depend on those boundaries; migration and privacy checks complete the release
gate. Tests should precede each implementation slice.
