# Implementation Plan: Pre-Dibs Encounter Journal

**Branch**: `002-predibs-encounter-journal` | **Date**: 2026-09-05 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-predibs-encounter-journal/spec.md`

## Summary

Complete and verify the standalone Pre-Dib request lifecycle and its Adventure Guide entry point. Reuse the existing PreDibs and LootPipeline boundaries, enforce raid-only submission at the integration boundary, keep the sub-category matrix as local display policy, and route finalized awards through the protected authoritative ledger path. RCLootCouncil remains an optional event/display adapter.

## Technical Context

**Language/Version**: Lua 5.1-compatible World of Warcraft Retail addon runtime

**Primary Dependencies**: Blizzard Encounter Journal APIs, WoW chat/group APIs, existing Dibs Core modules, embedded Ace3 event/config services where adopted, optional RCLootCouncil adapter

**Storage**: Versioned Dibs SavedVariables (`RCLootCouncil_dibsDB`) for requests, settings, award references, and authoritative ledger state

**Testing**: Dependency-free Lua harness executed through Fengari (`tests/run.lua`) with deterministic WoW API doubles; manual Retail client smoke validation where available

**Target Platform**: World of Warcraft Retail client

**Project Type**: Single-addon modular Lua project

**Performance Goals**: Loot-row refresh and request submission remain responsive for normal Adventure Guide pages; duplicate requests and finalized awards remain bounded at guild-scale test sizes

**Constraints**: No protected-action automation, no Blizzard or RCLootCouncil source changes, append-only ledger authority, raid-only Adventure Guide submissions, unknown categories visible by default, optional RC operation, combat-safe UI refresh, localization-independent stable identifiers

**Scale/Scope**: One active season, guild-scale Pre-Dib requests, Adventure Guide raid loot pages, local announcements, and one optional local RC adapter event source; cross-raid live loot-session replication is excluded

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- World of Warcraft API compliance: PASS. Supported APIs are observed and protected gameplay is not automated.
- Dibs are not DKP: PASS. A request is not a spend; consumption occurs only after an explicit finalized award.
- Append-only ledger and auditability: PASS. Fulfillment uses the existing authoritative transaction path and idempotent award reference.
- Player and administrative visibility: PASS. Request state uses existing views without exposing administrative data by default.
- Two supported Dib workflows: PASS. Pre-Dib is a request/reservation and shares the seasonal ledger with Drop-Dib.
- RCLootCouncil compatibility: PASS. RC is optional and cannot own balances or history.
- Encounter Journal integration: PASS. The matrix is local display policy and stable item/category identifiers are used.
- Multi-raid and sync privacy: PASS. No live RC candidates, votes, or loot-session payloads are added.
- Authority and trust: PASS. Player requests remain proposals; protected acceptance validates fulfillment.
- Data ownership and migration safety: PASS. Dibs SavedVariables remain authoritative and existing migration behavior is preserved.

No constitution violations detected. Planning may proceed.

## Project Structure

### Documentation (this feature)

```text
specs/002-predibs-encounter-journal/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── predibs-api.md
│   └── encounter-journal-ui.md
└── tasks.md
```

### Source Code (repository root)

```text
src/
├── Core.lua
├── modules/
│   ├── PreDibs.lua
│   ├── LootPipeline.lua
│   ├── Ledger.lua
│   └── ProtectedActions.lua
├── integrations/
│   ├── EncounterJournal.lua
│   ├── RCLootCouncil.lua
│   └── RCLootCouncilOptions.lua
└── ui/
    ├── PlayerUI.lua
    └── OfficerUI.lua

tests/
├── contract/
├── integration/
└── unit/
```

**Structure Decision**: Keep the existing single-addon modular layout. Pre-Dib domain behavior stays in `src/modules/PreDibs.lua` and `src/modules/LootPipeline.lua`; Adventure Guide behavior stays in `src/integrations/EncounterJournal.lua`; finalized award authority stays in `src/modules/ProtectedActions.lua` and `src/modules/Ledger.lua`. Tests mirror the existing unit, integration, and contract structure.

**Framework Migration Note**: AceEvent/AceTimer may replace duplicate event and retry plumbing, AceConfig may host settings, and AceGUI may replace manually positioned Player/Officer windows. The Pre-Dib lifecycle, request data, ledger authority, and standalone RCLootCouncil behavior remain Dibs-owned Lua behavior.

## Phase 0 Research Outcomes

Research decisions are captured in [research.md](research.md). They resolve authority ownership, lifecycle reuse, raid-only enforcement, category policy, award idempotence, RC optionality, and combat-safe UI behavior.

## Phase 1 Design Outputs

- [data-model.md](data-model.md) defines requests, local policy, announcement settings, and finalized award references.
- [contracts/predibs-api.md](contracts/predibs-api.md) defines stable request and fulfillment behavior.
- [contracts/encounter-journal-ui.md](contracts/encounter-journal-ui.md) defines visibility, submission, and safety behavior.
- [quickstart.md](quickstart.md) defines automated and manual validation scenarios.

## Post-Design Constitution Re-check

PASS. The design preserves Dibs ledger authority, append-only history, protected acceptance, optional RCLootCouncil integration, raid-only local UI policy, stable identifiers, and combat safety. No new synchronization or authority surface is introduced.

## Complexity Tracking

No constitution violations require justification.
