# Implementation Plan: Dibs Backups, Data Transfer, and Configuration Profiles

**Branch**: `007-backup-export-import-profiles` | **Date**: 2026-09-09 | **Spec**: [spec.md](spec.md)

**Status**: Local backup/configuration transfer, selected historical export and compressed portable transport implemented; external snapshot registration and full canonical recovery incomplete; Retail validation pending.

## Summary

Introduce local safety snapshots, versioned export/import packages, and named local or
guild profiles. All operations are preview-first, scope-labeled, checksum-validated, and
authority-checked. Configuration profiles remain separate from the append-only ledger;
full data imports append and deduplicate valid transactions and never rewrite history.

## Technical Context

**Language/Version**: Lua 5.1-compatible World of Warcraft Retail addon code.

**Dependencies**: Existing SavedVariables schema/migrations, Ace3 UI, permissions,
`Ledger`, `ProtectedActions`, profiles, guild isolation, serializer, and diagnostics.

**Storage**: Versioned local SavedVariables snapshots and bounded retention; portable text
packages with explicit scope and integrity metadata.

**Testing**: Fengari contract/integration tests, malformed/truncated package fixtures, and
manual two-profile/two-guild Retail validation.

**Constraints**: Data-only import, no executable payloads, no deletion or rewriting of
ledger transactions, explicit sensitive-data warning, bounded package/backups, and no
cloud or external identity service.

## Constitution Check

- **Authority**: local presentation profiles may be character-managed; guild policy,
  restore, and full-data operations require verified GM/Officer authority.
- **Ledger**: full imports append and deduplicate through protected actions; profile
  switching and configuration-only imports never change balances.
- **Privacy/isolation**: package scope, guild identity, character scope, and sensitivity
  are visible before export/import; private history is never merged across guilds.
- **Integrity**: schema, checksum, size, required fields, and compatibility are validated
  before mutation; pre-operation snapshots protect recovery.
- **Safety/release**: no code execution, no protected action during combat, migration and
  changelog/version notes are required.

## Project Structure

```text
src/modules/Backup.lua              snapshots, retention, checksum, restore
src/modules/Profiles.lua            local/guild profile lifecycle and scope
src/modules/ImportExport.lua        package encode/decode, validation, preview
src/modules/Ledger.lua              append/deduplicate transaction import
src/modules/ProtectedActions.lua    authority and confirmed apply boundary
src/integrations/RCLootCouncilOptions.lua settings UI and warnings
tests/integration/backup_spec.lua
tests/integration/import_export_spec.lua
tests/contract/profile_scope_spec.lua
```

## Delivery Phases

### 0.8.12 stabilization follow-up — 2026-11-15

1. Capture the current full automated-suite result before source edits; do not represent focused successes as a global pass.
2. Bound temporary import/restore previews to 16 per store and 30 minutes, with deterministic oldest-first eviction and cleanup at service access. Invalid/expired IDs fail closed and require a fresh preview. Keep accepted history, backup retention and T049 recovery contracts unchanged.
3. Capture backup content once through Export and derive the stored snapshot/checksums from the returned payload. Verify detachment, source work count, integrity, replay and tombstone regressions.
4. Explain in DataUI and guides that transfer exports current state, local restore uses an existing snapshot, and full compatibility import cannot recover unknown canonical history. Expose the existing recoveryClass in previews.
5. Track selected-snapshot export and external-snapshot import as unfinished work. Before implementing canonical recovery on a fresh installation, finalize provenance/authority/adoption constraints with the existing Feature 026 recovery boundary; do not widen ImportExport.Apply as a shortcut.
6. Independently review the safe stabilization changes, run focused suites under Fengari/Lua 5.4.6/Lua 5.1.5, and retain unexecuted Retail gates.

### Historical export slice — 2026-11-15

1. Add `Backup.ExportSnapshot(snapshotId, options)` with retained-text validation,
   snapshot/package/payload attestations, current permissions/context, local ownership,
   strict portable limit and full-scope `confirmedSensitive == true`. Return the original
   text and decoded metadata without recapturing live state or changing package schema.
2. Add localized selected-snapshot controls to DataUI. Sensitive consent and generated
   text are bound to the selection and cleared on selection change, refresh/context
   invalidation or permission failure. Current-state export stays in its own workspace.
3. Prove historical local/guild configuration round trips via existing Preview/Apply,
   permission rechecks, tampering/size refusals, scope filtering and canonical refusal.
   Raw external-snapshot registration remains T036: it would bypass Apply's scope
   filters, and full recovery also depends on Feature 026/T049. No such shortcut is added.
4. Independent QA and focused tests on Fengari, Lua 5.4.6 and native Lua 5.1.5;
   source compilation/documentation checks; preserve all manual gates.

### Compressed transport slice — 2026-11-15

Implement BackupTransport (native preferred, existing LibDeflate fallback) with
bounded DEFLATE preflight, standard Base64 and unchanged inner-package bytes.
Integrate opt-in compression and auto-detect import in ImportExport, historical
export/cache revalidation and optional retained compressed originals in Backup.
Update DataUI and locales for preferred compressed export and explicit codec absence.
Parallel ownership: codec module/tests; service/loading integration/tests; UI/locales
and UI tests. Independent QA follows source stabilization. Verify actual DEFLATE
using the unchanged vendored codec and cross-codec fixtures, not identity mocks;
run Fengari/Lua 5.4.6/native Lua 5.1.5 and compile source. Retail native execution
and full canonical recovery remain unvalidated; no global-suite pass is inferred.

### Phase 0: Package and schema contract

Define scope, sensitivity, schema/version, checksum, allowed fields, migration policy,
conflict strategies, retention, and privacy boundaries.

### Phase 1: Snapshots and profiles

Add bounded backup creation/list/restore preview and named local/guild profile lifecycle,
with authoritative settings separated from presentation settings.

### Phase 2: Export/import pipeline

Encode data-only packages, validate before decode/application, display additions/conflicts/
migrations/omissions, and support explicit merge or replace for allowed configuration.

### Phase 3: Ledger-safe full data

Validate and append new transactions, deduplicate award references and audit events, block
cross-guild sensitive imports, and retain a pre-operation restore point on failure.

### Phase 4: Verification and release

Run corruption, future-version, truncation, privacy, authority, combat, migration, and
replay tests; update schema migration, docs, changelog, and addon version.

## Complexity Assessment

No exception is requested. The package pipeline extends existing SavedVariables and protected
ledger boundaries without introducing cloud storage or a second authority model.
