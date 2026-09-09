# Implementation Plan: RCLootCouncil History Reconciliation and Dibs Evidence

**Branch**: `006-rclootcouncil-history-reconciliation` | **Date**: 2026-09-09 | **Spec**: [spec.md](spec.md)

**Status**: Draft; design-ready and not implemented.

## Summary

Add a deliberate, GM/Officer-only reconciliation workflow that searches existing
RCLootCouncil history, classifies records using explicit response aliases, presents a
read-only preview, and appends only individually confirmed Dibs transactions. Every
imported transaction keeps immutable evidence, original award time, import actor, and
reason. No scan or import occurs automatically.

## Technical Context

**Language/Version**: Lua 5.1-compatible World of Warcraft Retail addon code.

**Dependencies**: Existing Ace3 UI/services, optional RCLootCouncil history and award
interfaces, Dibs `ProtectedActions`, `Ledger`, permissions, seasons, and audit modules.

**Storage**: Versioned guild-scoped SavedVariables; append-only evidence and correction
records linked to existing ledger transactions.

**Testing**: Fengari contract/integration tests plus one-client Retail history fixtures and
manual Officer/player privacy checks.

**Constraints**: Preview-first, no RCLootCouncil writes, no automatic history scan, no
fuzzy response matching, no cross-guild data, and no direct ledger writes outside the
protected accounting path.

## Constitution Check

- **Authority**: GM/Officer verification is required at search, alias change, and confirm.
- **Ledger**: Confirmations use the existing append-only protected award path and stable
  deduplication; existing transactions remain immutable.
- **RCLootCouncil ownership**: History, candidates, votes, sessions, and identifiers are
  read-only; `RCMLAwardSuccess` and `FinalizeAward` are evidence labels only.
- **Privacy**: Officer evidence is separated from player-safe summaries and remains
  guild-scoped.
- **Combat safety**: UI and protected work defer in combat; a cancelled preview mutates
  nothing.
- **Diagnostics/release**: Every decision is attributable and versioned before shipping.

## Project Structure

```text
src/integrations/RCLootCouncil.lua   history discovery, normalization, deduplication
src/modules/Ledger.lua               append-only historical transaction linkage
src/modules/ProtectedActions.lua     confirmation and authority boundary
src/integrations/RCLootCouncilOptions.lua Officer workflow and preview
src/ui/OfficerUI.lua                 queue, filters, evidence, decisions
src/ui/PlayerUI.lua                  safe own-history summary
tests/integration/rclootcouncil_history_reconciliation_spec.lua
tests/contract/rclootcouncil_reconciliation_spec.lua
```

## Delivery Phases

### Phase 0: Research and contract

Define explicit alias normalization, candidate statuses, evidence fields, season choice,
bounded paging, and the manual-confirmation contract.

### Phase 1: Read-only search

Discover compatible history without scanning during load. Normalize labels and finalization
status, retain original values, classify eligible/already-accounted/ambiguous/rejected,
and expose a preview with counts.

### Phase 2: Review and confirmation

Add guided and manual review. Validate identity, item, winner, status, alias, season, and
authority at confirmation time. Route accepted rows through protected append-only accounting.

### Phase 3: Evidence, privacy, and recovery

Persist immutable evidence and an audit trail, provide bounded Officer search and player-safe
summaries, and make repeated searches/confirmation idempotent after reload or concurrency.

### Phase 4: Verification and release

Run the full Lua suite, history fixtures, authority/privacy checks, and Retail workflow.
Add migration, changelog, and version metadata before release.

## Complexity Assessment

No exception is requested. The feature is a read-only adapter plus a protected, explicit
historical accounting path; it does not create a second loot authority or a live history
database.
