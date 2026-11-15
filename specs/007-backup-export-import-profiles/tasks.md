---

description: "Task list for Dibs backups, data transfer, and configuration profiles"

---

# Tasks: Dibs Backups, Data Transfer, and Configuration Profiles

**Input**: Design documents from `/specs/007-backup-export-import-profiles/`

**Status**: Local backup/configuration transfer, selected historical export and compressed portable transport implemented and automatically tested. External snapshot registration and full canonical recovery remain incomplete. Retail validation pending.

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
- [ ] T027 [P] Complete and evidence full-suite, migration/failure-injection and Retail validation in `specs/007-backup-export-import-profiles/quickstart.md`. Reopened 2026-11-15: historical checkbox combined automated work and manual Retail validation, but no current Retail evidence establishes completion.
- [x] T028 Review the implementation against `spec.md`, `plan.md`, contracts, and `.specify/memory/constitution.md` before versioning.

## Phase 8: Confirmed import-scope correction — 2026-11-15

- [x] T029 [P] Add a regression proving a member's local configuration import cannot change officer-rank policy and that a scoped replace preserves out-of-scope guild policy. **Validated 2026-11-15:** targeted merge/replace tests pass 2/2 under Fengari and independently reviewed; deep ledger/governance invariance and member permission checks are included.
- [x] T030 Correct merge/replace application to accept only the approved presentation scope while preserving guild policy outside the package scope; keep ledger, authority and remote governance state unchanged. The intended source correction was already present in the shared pending `ImportExport.lua` diff; independent QA confirms the filtered application path meets the tested contract.

## Phase 9: 0.8.12 stabilization and portable-backup gap — 2026-11-15

- [x] T031 [P] Add behavioral regressions for bounded/expired/malformed import and restore previews in `tests/integration/backup_preview_lifecycle_spec.lua`; verify no accounting mutation and no deletion of accepted history or backup snapshots. **Validated 2026-11-15:** 11/11 under Fengari, Lua 5.4.6 and native Lua 5.1.5; independent QA passed.
- [x] T032 Implement the documented 16-preview/1,800-second temporary-data policy in ImportExport/Backup service access, preserving confirmation, permissions, scope and recovery boundaries. Depends on T031. **Validated 2026-11-15:** lifecycle regressions, 92 backup/import regression cases under Lua 5.4.6 and Lua 5.1.5, and independent review; policy recorded in contract.
- [x] T033 [P] Remove duplicate payload capture in `Backup.Create` and prove a detached consistent snapshot/checksum with one source capture in `tests/performance/backup_snapshot_work_spec.lua`. Do not alter package formats or recovery semantics. **Validated 2026-11-15:** 4/4 under Fengari, Lua 5.4.6 and Lua 5.1.5; independent QA passed.
- [x] T034 Explain current-state export versus selected local snapshot restore in DataUI and guides; display the existing full-import recovery class and fail-closed limitations. Test actual UI labels and retain all current integrity/privacy restrictions. **Validated 2026-11-15:** 3/3 actual UI cases plus 29 Player/season regressions under Fengari, Lua 5.4.6 and Lua 5.1.5; independent code/documentation QA passed.
- [x] T035 Define and implement export of the selected historical snapshot, including scope/authority, size limits and provenance. **Validated 2026-11-15:** T039–T041 complete; original attested package only, 250,000-character limit unchanged, UI consent and cache binding tested. No full canonical recovery or Retail certification claimed.
- [ ] T036 Define and implement import of an external snapshot as a validated recovery point and the authorized recovery path for a fresh installation. Canonical adoption depends on Feature 026 recovery/authority contracts (including T049); unknown canonical history must remain refused by ordinary full import. No bypass through `ImportExport.Apply` is permitted.
- [x] T037 Independently review T031–T034, run focused regression/compatibility and Lua 5.1 checks, document global-suite failures separately, and update the user Retail checklist. **Validated 2026-11-15:** independent QA 93/93 Lua 5.4.6; UI 32/32 on all three runtimes; native Lua 5.1 source compilation 108/108; generated documentation check and diff-check pass. Global Lua 5.4.6 run remains red: 1,811 passed / 134 failed across 257 files (before: 1,785 / 138 across 254); four existing failures resolved, no added failure names. Retail D04–D06 prepared but not executed; manual T027 remains open.
- [x] T038 Repair single-active profile selection only after successful authorization/confirmation, preserving per-character local isolation and legacy selection fallback. **Validated 2026-11-15:** 26/26 profile/backup/independent-button regressions under Fengari, Lua 5.4.6 and Lua 5.1.5; independent QA passed. No schema migration.
- [x] T039 [P] Add selected-snapshot export service and behavioral integrity/permission/size regressions in `Backup.lua` and `tests/integration/backup_historical_export_spec.lua`; follow FR-028 and the export contract. **Validated 2026-11-15:** 19/19 final service tests under Fengari, Lua 5.4.6 and native Lua 5.1.5. QA's read-only mutation finding fixed with atypical-DB regression; exact cached-text revalidation added. Implements the service portion of T035.
- [x] T040 [P] Add localized selected-backup export and sensitive consent in DataUI; clear stale consent/text and test the real controls in `tests/integration/backup_historical_export_ui_spec.lua`. **Validated 2026-11-15:** 12 new behavioral UI tests; group with existing limits and backup tests passes 29/29 under Fengari, Lua 5.4.6 and Lua 5.1.5. Same-ID valid substitution, scope change, stale callbacks, permissions and context invalidation covered.
- [x] T041 Independently review the selected export and historical configuration round trip through existing Preview/Apply; test scopes, malformed packages, context/permission changes and unchanged canonical refusal; update docs and record executed runtimes. **Validated 2026-11-15:** independent QA 45/45 under Lua 5.4.6 and Lua 5.1.5; two concrete QA findings fixed and rechecked. All 108 source files compile under native Lua 5.1. Documentation updated, Retail D07/D08 prepared but not executed. Global 1,811/134 result is the prior baseline, not a newly executed full suite. T036 and manual T027 stay open.

## Phase 10: Compressed portable transport — 2026-11-15

- [x] T042 [P] Implement bounded BackupTransport envelope/codec and real DEFLATE/Base64 interoperability/corruption/expansion tests. **Validated 2026-11-15:** 11 codec tests, independent Node stored/fixed/dynamic fixtures, expansion-before-decoder spy and exact 250,000-character boundary; complete group 84/84 on Fengari, Lua 5.4.6 and Lua 5.1.5. Existing LibDeflate unchanged, checked native API adapter distinct from real Retail.
- [x] T043 [P] Integrate compressed current-state/historical export, retained compressed originals and automatic compressed import; preserve raw compatibility, attestations, scope, canonical refusal and Sync quota. **Validated 2026-11-15:** 9 service tests plus existing historical/isolation/canonical regressions in the 84/84 group on all three runtimes. QA-found codec dependency of local restore removed and tested with absent codec/corrupt optional transport. Loading/optional-field compatibility documented; no inner schema/hash change.
- [x] T044 [P] Prefer compressed export in DataUI when available, localize format/size/unavailable feedback, preserve consent/cache binding and test actual controls. **Validated 2026-11-15:** 4 new real-control tests plus prior historical UI regressions in the 84/84 group on all three runtimes. Native Retail rendering remains unexecuted.
- [x] T045 Independently review codec/service/UI, run focused tests across available runtimes and compilation/documentation checks, record measured representative sizes and missing Retail validation. **Validated 2026-11-15:** independent QA 66/66 under Lua 5.4.6 and Lua 5.1.5; three additional malformed distance/reserved-symbol probes refused before decompression. Root 84/84 on all three runtimes, 109/109 source compilation under Lua 5.1; doc generation passes with zero errors/10 inherited warnings and diff-check passes. Synthetic 2,000-row package measured 288,412 raw bytes → 30,412 encoded characters. D09/D10 prepared, not executed; T027/T036 stay open. Previous 1,811/134 global result remains baseline, not a full-suite rerun.

## Dependencies

Phase 2 blocks every story. Backups and profile scope establish safety boundaries; export
and import depend on those boundaries; migration and privacy checks complete the release
gate. Tests should precede each implementation slice.
