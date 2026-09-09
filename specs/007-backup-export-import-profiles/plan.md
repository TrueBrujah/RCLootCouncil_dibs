# Implementation Plan: Dibs Backups, Data Transfer, and Configuration Profiles

**Branch**: `007-backup-export-import-profiles` | **Date**: 2026-09-09 | **Spec**: [spec.md](spec.md)

**Status**: Draft; design-ready and not implemented.

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
