# Implementation Plan: RCLootCouncil_dibs Core

**Branch**: `001-dibs-core` | **Date**: 2026-09-03 | **Spec**: [spec.md](spec.md)

## Summary

Implement a standalone core for seasonal, rank-based Dibs with a versioned SavedVariables schema, append-only ledger accounting, and deterministic balance reconstruction. The core must stay independent from RCLootCouncil and Encounter Journal while exposing stable module APIs for later integrations.

## Technical Context

**Language/Version**: World of Warcraft Retail Lua (Lua 5.1-compatible)

**Primary Dependencies**: WoW Retail API only; no RCLootCouncil dependency in core behavior

**Storage**: Versioned `RCLootCouncil_dibsDB` SavedVariables

**Testing**: Dependency-free Lua test runner in `tests/run.lua` with WoW doubles under `tests/helpers/`

**Target Platform**: WoW Retail using `src/RCLootCouncil_dibs.toc`

**Project Type**: Single addon with modular business domain in `src/modules/`

**Performance Goals**: O(n) balance reconstruction from transactions and idempotent transaction insert for sync replay safety

**Constraints**: No hard-coded rank allocations; append-only transaction history; idempotent transaction application; no RC-specific assumptions

**Scale/Scope**: One guild, many seasons, thousands of immutable transactions, per-player and officer views

## Constitution Check

*GATE: Passed before research and after design.*

- WoW API compliance: PASS
- Dibs are not DKP: PASS
- Seasonal and rank-based allocation: PASS
- Append-only ledger and auditability: PASS
- Optional integration: PASS (core independent from RC/EJ)
- Data ownership and persistence: PASS

## Project Structure

### Documentation

```text
specs/001-dibs-core/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── tasks.md
└── contracts/
    └── core-api.md
```

### Source Code

```text
src/
├── Core.lua
├── modules/
│   ├── Seasons.lua
│   ├── RankRules.lua
│   ├── Ledger.lua
│   ├── Permissions.lua
│   └── PreDibs.lua
└── ui/
    ├── PlayerUI.lua
    └── OfficerUI.lua
```

## Design Decisions

1. Keep the core state model fully in `RCLootCouncil_dibsDB` and migrate by schema version.
2. Store each authoritative accounting event as an immutable transaction row.
3. Compute balances from transaction history rather than mutable counters.
4. Capture player rank snapshot at transaction time for audit stability.
5. Keep rank allocation as season-scoped configuration data.
6. Ensure transaction inserts are idempotent via transaction IDs.
7. Expose business operations through modules, not direct UI writes.

See [research.md](research.md), [data-model.md](data-model.md), [contracts/core-api.md](contracts/core-api.md), and [quickstart.md](quickstart.md).

## Post-Design Constitution Re-check

PASS. The plan preserves standalone core behavior, append-only accounting, and rank/season invariants without RC coupling.

## Complexity Tracking

No constitution violations require justification.
