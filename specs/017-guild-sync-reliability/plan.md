# Implementation Plan: Guild Sync Reliability

**Branch**: `017-guild-sync-reliability` | **Date**: 2026-09-22 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/017-guild-sync-reliability/spec.md`

## Summary

Guild members reported that seasons created by the GM, Pre-Dibs mode changes, and
award evidence created by a non-coordinator Master Looter never reach the rest of
the guild. Investigation found three concrete, independent gaps in the existing
distributed-ledger/sync architecture (Constitution Principles IX, X, XI):
`Governance.RecordAwardProposal` never transmits a non-coordinator's award evidence
to the current coordinator; `Dibs.Seasons` never calls `Dibs.Sync`/`Dibs.SyncV2` at
all; and there is no visible signal when guild-wide policy has never been adopted or
when two clients' protocol/version cannot interoperate. This plan closes all three
gaps using the same patterns already proven in the codebase (`OPERATIONAL_POLICY`
and `GOVERNANCE` DIGEST + WHISPER-detail entities in `SyncV2.lua`), without changing
the existing single-coordinator/epoch authority model.

## Technical Context

**Language/Version**: Lua 5.1 (WoW Retail client runtime), executed under Fengari for automated tests.

**Primary Dependencies**: Embedded AceComm-3.0/AceSerializer-3.0 (via `Dibs.Ace3`), existing `Dibs.Sync`/`Dibs.SyncV2`, `Dibs.Governance`, `Dibs.Identity`, `Dibs.Permissions`, `Dibs.Seasons`, `Dibs.ProtectedActions`, `Dibs.DebugLogs`/diagnostic scopes.

**Storage**: WoW SavedVariables (`RCLootCouncil_dibsDB`), guild-scoped per Constitution Principle XVII. No external storage.

**Testing**: Fengari-based Lua test suite (`tests/run.lua`, `DIBS_TEST_FILES`), including the multi-client fixture `tests/helpers/distributed_ledger_fixture.lua` for cross-client sync scenarios.

**Target Platform**: World of Warcraft Retail client addon (in-game Lua sandbox), no network access outside the game's addon-message channel.

**Project Type**: Single WoW addon (existing `src/` module layout; no frontend/backend split).

**Performance Goals**: Sync messages stay within the existing bounded envelope sizes already enforced by SyncV2 (`MAX_BYTES`/`MAX_CHUNKS`); no new unbounded broadcasts. Award-proposal relay and catch-up must complete within the same reconnect/heartbeat cadence already used by `Sync.OnLifecycle` (heartbeat interval `HEARTBEAT`).

**Constraints**: Must not introduce a second ledger-writing authority (Constitution XI); must not use last-write-wins for ledger transactions (Constitution X); must not leak live loot candidates/votes/session data (Constitution IX, XVIII); must keep all new debug output behind the existing `/dibs debug <scope> 0-5` diagnostic policy (Constitution XVIII), not solely Developer Mode.

**Scale/Scope**: One guild's roster (bounded by existing `MAX_INDEX`/`MAX_MESSAGES`/`MAX_TRANSFERS` limits already in `SyncV2.lua`); two or more simultaneous raid groups within that guild.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Principle IX (Multi-Raid Operation)** — PASS. Cross-raid delivery of award proposals and season data only carries Dib accounting/season metadata, never live loot candidates, votes, or session state (see FR-001–FR-007, data-model.md entities).
- **Principle X (Distributed Synchronization)** — PASS. Award proposals get a stable identifier (`proposalId`) and are applied exactly once (idempotent/deduplicatable) by reusing the existing replay-key mechanism in `SyncV2.lua`. No last-write-wins is introduced; the single coordinator still decides commit order.
- **Principle XI (Authority and Trust)** — PASS. This feature does not grant new authority: a non-coordinator's proposal remains non-authoritative until the verified coordinator explicitly confirms it (`Ledger.CommitAwardProposal`), matching the existing rule that only the coordinator commits. Season catalog writes still require the existing `season.*` ProtectedActions authorization; sync merely replicates an already-authorized change, and receivers still re-verify sender identity/authority rather than trusting a payload claim.
- **Principle XII (Raid Relay)** — PASS (informational only): duplicate relay of the same proposal must not produce duplicate ledger transactions; covered by the same idempotency requirement as Principle X.
- **Principle XVII (Multi-Guild Isolation)** — PASS. Season catalog and proposal relay reuse `Dibs.GetGuildKey()`-scoped envelopes already required by `SyncV2.lua`'s `validateEnvelope`.
- **Principle XVIII (Diagnostics)** — PASS, with an adjustment: new synchronization status/diagnostic output must go through the existing named diagnostic-scope/level system (`/dibs debug sync 0-5`), not be gated on Developer Mode alone.

No violations requiring the Complexity Tracking table.

## Project Structure

### Documentation (this feature)

```text
specs/017-guild-sync-reliability/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md         # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── sync-messages.md # Phase 1 output
└── tasks.md             # Phase 2 output ($speckit-tasks)
```

### Source Code (repository root)

```text
src/
├── modules/
│   ├── Governance.lua        # RecordAwardProposal gains relay trigger + inbound apply
│   ├── Seasons.lua            # gains catalog snapshot/apply + revision bump on mutation
│   ├── SyncV2.lua             # gains AWARD_PROPOSAL and SEASON_CATALOG entity types
│   ├── ProtectedActions.lua   # season.* actions call Sync.AnnounceSeasonCatalog after success
│   └── OperationalPolicy.lua  # unchanged; reused as the reference pattern
├── ui/
│   └── OfficerUI.lua          # pending-proposal list + policy/version status banners
└── Core.lua                   # /dibs debug report gains sync/version status lines

tests/
├── unit/
│   └── season_catalog_spec.lua
├── integration/
│   ├── award_proposal_relay_spec.lua
│   └── season_catalog_sync_spec.lua
└── helpers/
    └── distributed_ledger_fixture.lua  # reused, not modified unless a gap is found
```

**Structure Decision**: Single existing WoW-addon project layout (`src/modules`,
`src/ui`, `tests/{unit,integration}`). No new top-level projects; this feature only
adds modules/functions inside the existing `Dibs.Governance`, `Dibs.Seasons`, and
`Dibs.SyncV2` namespaces and extends existing UI surfaces, consistent with
Constitution XVI (framework reuse) and the project's established module boundaries.

## Complexity Tracking

*No Constitution Check violations — table intentionally empty.*
