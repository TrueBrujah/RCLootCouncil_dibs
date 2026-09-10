# Implementation Plan: Character Loot Eligibility and Main/Alt Governance

**Branch**: `005-character-loot-eligibility` | **Date**: 2026-09-10 | **Spec**: [spec.md](spec.md)

**Status**: Implementation in progress on `dev`; automated validation will run before
the remaining Retail and two-client checks.

## Summary

Add a guild-scoped, season-aware protected-loot service for Curio (`TOKEN`) and class
Tier Set (`TOKEN_SET`) progress. The service records only finalized or officer-confirmed
acquisitions, evaluates linked-character and round policy before Dibs consumption, and
keeps player declarations separate from officer-approved relationships and main changes.

## Technical Context

**Language/Version**: Lua 5.1-compatible World of Warcraft Retail addon code.

**Dependencies**: Existing Dibs ledger, permissions/protected actions, RCLootCouncil
semantic item mapping, Pre-Dibs, Ace3 UI, localization, and guild isolation.

**Storage**: Additive guild SavedVariables namespace with versioned policies,
acquisitions, relationship history, main changes, probation exceptions, and decisions.
Existing ledger transactions remain authoritative and unchanged.

**Testing**: Fengari unit/integration tests for policy, rounds, identity, authority,
idempotency, privacy, and live-award gating; manual Retail checks for item metadata and
the player/officer screens.

**Constraints**: Catalyst is permanently excluded; no Battle.net identity inference;
only verified GM/Officer actions can mutate policy or history; pending votes and test
events never count; all corrections are append-only.

## Constitution Check

- **Authority and ledger**: all administrative mutations use protected actions and
  append-only audit records; eligibility itself never rewrites balances.
- **RCLootCouncil boundary**: the adapter supplies semantic family and finalized-award
  evidence; Dibs remains authoritative for protected-loot eligibility and accounting.
- **Isolation and privacy**: records use the active guild bucket; players see only their
  own status and approved relationship labels.
- **Interface quality**: player/officer controls use modeless windows, bounded tables,
  explicit dates and decisions, and responsive selectors per Principle XXI.
- **Combat/release**: non-critical UI work is deferred during combat; changelog and
  addon version updates are required when behavior ships.

## Project Structure

```text
src/modules/CharacterEligibility.lua       policy, acquisitions, relationships, rounds
src/modules/ProtectedActions.lua            protected handlers for policy and approvals
src/modules/Ledger.lua                      finalized-award acquisition hook
src/integrations/RCLootCouncil.lua           semantic family and eligibility projection
src/ui/PlayerUI.lua                         player status and declarations
src/ui/OfficerUI.lua                         policy, relationship, and probation review
tests/unit/character_eligibility_spec.lua   policy and round behavior
tests/integration/character_eligibility_spec.lua  authority and award integration
```

## Delivery Phases

### Phase 0: Versioned state and policy

Create the additive SavedVariables namespace, default per-season policies, migration,
canonical family/difficulty helpers, and deterministic policy evaluation.

### Phase 1: Acquisition and round accounting

Record idempotent finalized acquisitions, Curio completion, Tier Set lowest-progress
rounds, higher-track behavior, unknown-data review, and explainable decisions.

### Phase 2: Relationships and probation

Add player declarations, officer approval/rejection/suspension, main changes, default
14-day probation, bounded exceptions, and append-only audit metadata.

### Phase 3: Loot and UI integration

Gate Dibs candidate status and finalized awards through the service, expose player and
officer views, and preserve standalone operation when RCLootCouncil is unavailable.

### Phase 4: Verification and release

Run the automated suite, update documentation and changelog, then perform Retail and
two-client checks for item classification, privacy, and visual usability.

## Complexity Assessment

No exception is requested. The feature adds a guild-scoped policy service while keeping
the existing ledger, authority model, and RCLootCouncil adapter boundaries intact.
