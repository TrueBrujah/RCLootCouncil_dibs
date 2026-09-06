# Implementation Plan: Independent Dibs Core

**Branch**: `001-dibs-core` | **Date**: 2026-09-03 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-dibs-core/spec.md`

## Summary

Deliver a standalone Dibs Core that manages seasonal rank allocations, immutable authoritative transactions, idempotent replay handling, and deterministic player balances from a versioned SavedVariables ledger. The core is intentionally isolated from RCLootCouncil, Encounter Journal, raid-session coupling, and cross-raid synchronization so later features can integrate through stable core interfaces.

## Technical Context

**Language/Version**: Lua 5.1-compatible (World of Warcraft Retail addon runtime)

**Primary Dependencies**: World of Warcraft Retail API; embedded Ace3 services adopted selectively through `LibStub` while preserving Lua domain boundaries

**Storage**: Versioned SavedVariables (`RCLootCouncil_dibsDB`)

**Testing**: Lua test harness (`tests/run.lua`) with deterministic WoW API mocks in `tests/helpers/`

**Target Platform**: World of Warcraft Retail client

**Project Type**: Single-addon monorepo with modular domain services

**Performance Goals**: Core balance reads and transaction validation remain responsive for normal raid-scale guild rosters; duplicate transaction replay produces zero additional accounting effects

**Constraints**: Append-only transaction history, no hard-coded rank allocations, explicit compensating corrections, no dependency on RC/EJ/sync layers in this feature

**Scale/Scope**: Guild-scale seasonal accounting for player, officer, and guild-master operations, with stable APIs for later feature layers

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- World of Warcraft API compliance: PASS
- No protected gameplay automation: PASS
- Dibs are not DKP: PASS
- Seasonal rank-based allocation as configuration data: PASS
- Append-only authoritative ledger and compensating corrections: PASS
- Rank-at-transaction-time preservation: PASS
- Core independence from RCLootCouncil for accounting truth: PASS
- Data ownership in Dibs SavedVariables with versioning and migration safety: PASS
- Public repository constraints (no secrets/private logs in artifacts): PASS

No constitution violations detected. Planning may proceed.

## Project Structure

### Documentation (this feature)

```text
specs/001-dibs-core/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── core-api.md
└── tasks.md
```

### Source Code (repository root)

```text
src/
├── Core.lua
├── modules/
│   ├── Seasons.lua
│   ├── RankRules.lua
│   ├── Ledger.lua
│   ├── Permissions.lua
│   └── ProtectedActions.lua
├── ui/
│   ├── PlayerUI.lua
│   └── OfficerUI.lua
└── integrations/
    ├── EncounterJournal.lua
    └── RCLootCouncil.lua

tests/
├── unit/
├── integration/
└── contract/
```

**Structure Decision**: Use the existing single-addon modular layout. The core domain lives under `src/modules/` and is exposed through controlled actions from `src/Core.lua` and `src/modules/ProtectedActions.lua`. UI and integration layers consume core APIs but are not authoritative for accounting.

## Phase 0 Research Outcomes

Research decisions are captured in `research.md` and resolve policy questions for transaction identity, correction modeling, role foundation, and core isolation boundaries.

## Phase 1 Design Outputs

- Data model documented in `data-model.md`
- Core public contract documented in `contracts/core-api.md`
- End-to-end validation guide documented in `quickstart.md`

## Post-Design Constitution Re-check

PASS. Phase 1 artifacts preserve all MUST-level constitution requirements, especially append-only auditability, seasonal rank policy, authority boundaries, and future-safe modularity.

## Framework Migration Follow-Up

Ace3 is available under `src/libs/`. Any core migration must preserve the existing SavedVariables schema, append-only ledger, and standalone contract. The future migration adopts AceEvent for shared lifecycle plumbing and AceGUI for the player/officer windows where it removes manual frame layout; `AceDB` does not replace Dibs-owned persistence without a separately approved data migration.

## Complexity Tracking

No constitution violations require justification in this feature.
