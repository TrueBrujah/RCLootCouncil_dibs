# Implementation Plan: Multi-Ledger Management and Independent Raid Sessions

**Branch**: `020-multi-ledger-independent-raid` | **Date**: 2026-10-12 | **Spec**: [specs/020-multi-ledger-independent-raid/spec.md](specs/020-multi-ledger-independent-raid/spec.md)

**Input**: Feature specification from `specs/020-multi-ledger-independent-raid/spec.md`

## Summary

This feature introduces three core capabilities to RCLootCouncil_dibs:
1. **Multi-Ledger Architecture**: Support for multiple co-existing, completely isolated ledgers within a single guild namespace (e.g., Mythic team, weekend alts), with unique ledger identifiers (`LedgerID`), continuous background synchronization of all approved ledgers across guild members, and seamless active-ledger switching in the UI.
2. **Officer Setup Empowerment with GM Approval**: Removal of Guild Master blockers for routine configuration (seasons, rank allocations, Guided Setup) so verified Officers can configure raids independently, while maintaining the non-negotiable security invariant that any newly proposed guild ledger requires explicit Guild Master approval to become an official, guild-synchronized ledger.
3. **Independent / Standalone Raid Session**: A local session mode for Master Looters running ad-hoc, alt, or community raids. It operates with zero guild network traffic, interfaces with vanilla RCLootCouncil voting buttons (no addon installation needed for attendees), maintains read-only Great Vault visibility, and offers post-raid award reconciliation for guild officers.

## Technical Context

**Language/Version**: Lua 5.1 / WoW Retail 11.x client environment; unit/integration tests run via Fengari (Lua 5.3 runtime with 5.1 compatibility).

**Primary Dependencies**: Ace3 (AceComm-3.0, AceSerializer-3.0, AceGUI-3.0, AceConfig-3.0, MSA-DropDownMenu-1.0), LibStub, CallbackHandler-1.0; optional integration with RCLootCouncil Retail release.

**Storage**: SavedVariables (`DibsDB`) partitioned strictly by realm and guild name for guild members, and by character for unguilded players. Ledgers stored in `DibsDB[guildKey].ledgers = { [ledgerId] = ledgerObject }` with `activeLedgerId` local pointer. Independent sessions stored in `DibsDB[guildKey].independentSessions = { [sessionId] = sessionObject }`.

**Testing**: Fengari CLI (`tests/run.lua`) executing `*_spec.lua` test suites with WoW API and Ace3 doubles; targeted execution configured via `$env:DIBS_TEST_FILES`.

**Target Platform**: World of Warcraft Retail (The War Within / Midnight).

**Project Type**: World of Warcraft Lua Addon with optional RCLootCouncil adapter.

**Performance Goals**: UI active ledger switch in < 500ms; background sync without UI frame hitching (< 16ms budget per frame); 0 broadcast messages emitted during independent raid sessions.

**Constraints**: WoW Lua sandbox (single-threaded, cooperative execution, no OS access); strict combat lockdown rules (UI mutations deferred during combat); append-only immutable accounting for active ledgers, with only the approved GM-confirmed deletion lifecycle for archived non-default ledgers; verified sender authority (no last-write-wins).

**Scale/Scope**: Up to 10 concurrent approved guild ledgers per guild; up to 1000 transactions per ledger; up to 40 players in an independent raid session.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evaluation & Design Alignment |
|---|---|---|
| **I. WoW API Compliance** | PASS | Uses standard WoW Addon communication and events. No protected UI or gameplay automation. UI changes respect combat lockdown. |
| **II. Dibs Are Not DKP** | PASS | Balances derived from explicit Dib rules and allocations; not boss-kill currencies. |
| **III. Seasonal & Rank Allocation** | PASS | Each ledger maintains its own seasonal rank-based point rules and history. |
| **IV. Append-Only Ledger** | PASS | All ledgers remain strictly append-only. No historical rewriting. |
| **V. Player & Admin Visibility** | PASS | Players view their balances and history for any approved ledger; officers/GM view all ledgers. |
| **VI. Two Dib Workflows** | PASS | Pre-Dib and Drop-Dib workflows are supported within each ledger. |
| **VII. RCLootCouncil Compatibility** | PASS | Optional integration preserved. Independent raids allow attendees with only vanilla RCLootCouncil to use the DIB response button. |
| **IX. Multi-Raid Operation** | PASS | Independent and multi-ledger operations are explicitly designed for concurrent multi-raid environments without cross-raid session leak. |
| **X. Distributed Sync** | PASS | Multi-ledger background sync uses deduplicated, idempotent digests with `ledgerId` scoping. |
| **XI. Authority & Trust** | PASS | Verified Officer rights expanded for routine setup per Principle XI; GM approval remains mandatory for official guild ledger cutover/approval. |
| **XIII. Data Ownership** | PASS | Dibs SavedVariables own all ledger data; RCLootCouncil DB is never required to reconstruct state. |
| **XVII. Multi-Character & Guild Isolation** | PASS | Guild isolation key (`realm-guildName`) strictly maintained. Ledgers remain partitioned inside the active guild namespace. |
| **XXIII. Evidence-Based Development** | PASS | Bounded exploration, targeted test execution slices via Fengari, concise handoff notes. |

## Project Structure

### Documentation (this feature)

```text
specs/020-multi-ledger-independent-raid/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Technical research & architectural decisions
├── data-model.md        # Entities, relationships, and validation rules
├── quickstart.md        # End-to-end validation scenarios
├── contracts/           # API and protocol contracts
│   ├── multi-ledger-api.md
│   ├── officer-governance-api.md
│   ├── independent-raid-api.md
│   └── sync-catalog-protocol.md
└── checklists/
    └── requirements.md  # Specification quality checklist
```

### Source Code (repository root)

```text
src/
├── RCLootCouncil_dibs.toc       # Addon manifest and load order
├── Core.lua                     # Facade and namespace initialization
├── modules/
│   ├── Permissions.lua          # Officer authority reclassification
│   ├── Installation.lua         # Guided setup allowing officer initialization
│   ├── Governance.lua           # Ledger proposal and GM approval records
│   ├── Ledger.lua               # Multi-ledger store delegation & backward compatibility
│   ├── MultiLedger.lua          # New multi-ledger management facade
│   ├── IndependentRaid.lua      # New local independent raid session module
│   └── SyncV2.lua               # Multi-ledger catalog digest and background sync
├── integrations/
│   └── RCLootCouncil.lua        # Independent raid award interception & DIB mapping
└── ui/
    ├── OfficerUI.lua            # Ledger selector & GM approval panel
    └── PlayerUI.lua             # Active ledger display selector

tests/
├── unit/
│   ├── permissions_spec.lua     # Officer capability tests
│   ├── installation_spec.lua    # Officer setup workflow tests
│   ├── multi_ledger_spec.lua    # Multi-ledger isolation tests
│   └── independent_raid_spec.lua# Independent raid local accounting tests
└── integration/
    ├── multi_ledger_sync_spec.lua # Background catalog sync tests
    └── rc_independent_award_spec.lua # RCLootCouncil independent award tests
```

**Structure Decision**: Monolithic Lua Addon structure following the established load order defined in `src/RCLootCouncil_dibs.toc`. New modules `MultiLedger.lua` and `IndependentRaid.lua` are placed under `src/modules/` and registered in the TOC in their proper layer.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| None | All designs strictly adhere to constitution principles I through XXIII. | N/A |
