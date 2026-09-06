# Implementation Plan: Raid Pre-Dib Modes

**Branch**: `003-raid-predib-modes` | **Date**: 2026-09-05 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-raid-predib-modes/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Add per-season Wild Open and Encounter Pre-Dib modes, recover player-persisted Pre-Dibs after an officer reconnects, and provide authorized reminders and player-opt-in raid prompts. The implementation extends the existing request pipeline with mode/context validation, a compact revisioned addon-message protocol for active request recovery, and separated non-authoritative reminder/prompt flows. Ledger mutations and finalized awards remain within the current protected-action boundary.

## Technical Context

<!--
  ACTION REQUIRED: Replace the content in this section with the technical details
  for the project. The structure here is presented in advisory capacity to guide
  the iteration process.
-->

**Language/Version**: Lua for World of Warcraft Retail addon runtime

**Primary Dependencies**: World of Warcraft Retail addon APIs; embedded Ace3 via `LibStub` (AceComm, AceSerializer, AceEvent, AceTimer, AceConfig); optional RCLootCouncil adapter

**Storage**: Account SavedVariables owned by `RCLootCouncil_dibsDB`; runtime-only transfer buffers

**Testing**: Fengari Lua harness via `npx --yes fengari tests/run.lua`; manual Retail client smoke scenarios

**Target Platform**: World of Warcraft Retail client

**Project Type**: Single modular World of Warcraft addon

**Performance Goals**: Recover active requests without blocking UI; render and filter officer state for a 30-player raid and a full season without unbounded broadcasts

**Constraints**: Offline request persistence; compact bounded addon messages; no live loot/vote/candidate synchronization; non-critical UI deferred during combat; no automatic loot awards; Dib spending is limited to a validated finalized RCLootCouncil `DIB` event; preserve Dibs SavedVariables without an AceDB rewrite

**Scale/Scope**: One guild, multiple concurrent raid groups, roughly 30 players, season-long request and ledger history

## Constitution Check

*GATE: Passed before Phase 0 research and re-checked after Phase 1 design.*

- **WoW API and combat safety**: Pass. The design uses supported addon communication and event observation; prompts, Journal navigation, and refreshes defer in combat.
- **Ledger integrity**: Pass. Modes, reminders, delivery acknowledgements, and prompts never create ledger entries. Finalized awards remain the only Pre-Dib consumption path.
- **Authority**: Pass. Mode changes remain protected authorized actions. Reminder eligibility is explicitly separate and grants no accounting authority. Inbound player messages are request proposals only.
- **Sync and privacy**: Pass. Recovery uses revisioned request deltas and acknowledgements, excludes live loot/vote/candidate/session content, and supports reconnect recovery without last-write-wins.
- **RCLootCouncil independence**: Pass. The adapter remains optional and never owns request, ledger, or synchronization authority.
- **Multi-raid operation**: Pass. Direct acknowledged player-to-officer request delivery avoids a single raid source of truth; relay use is limited to routine fan-out.

## Project Structure

### Documentation (this feature)

```text
specs/003-raid-predib-modes/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   ├── sync-protocol.md
│   └── raid-mode-ui.md
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)
<!--
  ACTION REQUIRED: Replace the placeholder tree below with the concrete layout
  for this feature. Delete unused options and expand the chosen structure with
  real paths (e.g., apps/admin, packages/something). The delivered plan must
  not include Option labels.
-->

```text
src/
├── Core.lua
├── modules/
│   ├── PreDibs.lua
│   ├── Sync.lua
│   ├── Permissions.lua
│   ├── ProtectedActions.lua
│   └── RaidRelay.lua
├── integrations/
│   ├── EncounterJournal.lua
│   └── RCLootCouncil.lua
└── ui/
  ├── PlayerUI.lua
  └── OfficerUI.lua

tests/
├── contract/
├── integration/
└── unit/
```

**Structure Decision**: Keep the existing single-addon modular structure. Request policy and lifecycle live in `modules/PreDibs.lua`; compact transport and recovery live in `modules/Sync.lua`; raid coordination stays in `modules/RaidRelay.lua`; Adventure Guide navigation remains in `integrations/EncounterJournal.lua`; player/officer controls use the existing UI modules. AceComm/AceSerializer replace only transport encoding and fragmentation, AceEvent/AceTimer replace event/retry infrastructure, and AceConfig hosts settings. Tests remain split by contract, integration, and unit scope.
