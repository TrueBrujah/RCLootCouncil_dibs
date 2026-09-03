# Implementation Plan: RCLootCouncil Permission Authority

**Branch**: `003-rclootcouncil-integration` | **Date**: 2026-09-03 | **Spec**: [spec.md](spec.md)

## Summary

Route every authoritative Dibs mutation through a protected action boundary that selects one permission authority source per request. When RCLootCouncil is operational, its Master Looter decision is exclusive and fail-closed on malformed/unverifiable states. When RCLootCouncil is absent, standalone guild-master plus appointed-admin policy is used. Dibs ledger remains append-only and authoritative for balance reconstruction.

## Technical Context

**Language/Version**: World of Warcraft Retail Lua (Lua 5.1-compatible)

**Primary Dependencies**: WoW Retail API; optional RCLootCouncil APIs; optional LibStub/Ace surfaces when RC is present

**Storage**: Versioned `RCLootCouncil_dibsDB` with permissions and ledger award indexes

**Testing**: Dependency-free Lua runner (`tests/run.lua`) with WoW and RC doubles

**Target Platform**: WoW Retail with addon manifest `src/RCLootCouncil_dibs.toc`

**Project Type**: Single addon with modular domain (`src/modules`) and adapters (`src/integrations`)

**Performance Goals**: Stable permission evaluation for repeated checks and idempotent award consumption by `awardRef`

**Constraints**: No RC core mutation, no live loot session data in cross-raid sync, fail-closed degraded RC state, combat-safe officer UI toggles

**Scale/Scope**: Guild-wide accounting across many seasons with local 40-candidate loot sessions

## Constitution Check

*GATE: Passed before research and after design.*

- WoW API compliance: PASS
- Dibs are not DKP: PASS
- Append-only ledger and auditability: PASS
- Optional RC integration: PASS
- Authority and trust boundaries: PASS
- Cross-raid privacy requirements: PASS

## Source Touch Points

- `src/Core.lua`
- `src/modules/Permissions.lua`
- `src/modules/ProtectedActions.lua`
- `src/modules/Ledger.lua`
- `src/modules/PreDibs.lua`
- `src/modules/Sync.lua`
- `src/integrations/RCLootCouncil.lua`
- `src/ui/OfficerUI.lua`
- `src/locales/enUS.lua`
- `src/locales/frFR.lua`
- `src/RCLootCouncil_dibs.toc`

## Design Decisions

1. Availability model is tri-state: `absent`, `operational`, `degraded`.
2. `Permissions.Evaluate` selects RC authority exclusively when RC is present.
3. ProtectedActions is the single mutation façade for season/rank/ledger/admin/award changes.
4. Standalone admin appoint/revoke always requires verified guild master as extra business rule.
5. Award consumption is idempotent by `awardRef` and only on finalized outcomes.
6. Candidate Dibs/Pre-Dibs status is local read-only projection.
7. Sync snapshots use explicit allowlist and reject live loot session fields.

## Post-Design Constitution Re-check

PASS. The design keeps Dibs authoritative, protects privacy boundaries, and preserves standalone behavior.

## Complexity Tracking

No constitution waivers required.
