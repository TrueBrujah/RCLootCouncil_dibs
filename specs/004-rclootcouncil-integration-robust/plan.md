# Implementation Plan: Robust RCLootCouncil Integration

**Branch**: `feature/rclootcouncil-integration-robust` | **Date**: 2026-09-06 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/004-rclootcouncil-integration-robust/spec.md`

**Note**: This plan turns the feature requirements into a capability-based adapter, a protected finalized-award path, and a repeatable validation process.

## Summary

Harden the optional RCLootCouncil adapter so that Dibs remains fully usable in
Standalone mode, integration capabilities are detected rather than assumed, and only a
verified local Master Looter can submit a qualifying finalized `DIB` award to the
protected accounting path. The design keeps guild GM/officer authority for all Dibs
administration, makes award accounting idempotent and fail-closed, preserves unrelated
RCLootCouncil history, and exposes useful degraded/unsupported diagnostics.

## Technical Context

**Language/Version**: Lua 5.1-compatible World of Warcraft Retail addon runtime

**Primary Dependencies**: WoW Retail addon APIs; optional RCLootCouncil Retail 3.x-shaped
capability surface; embedded Ace3 services through LibStub when available

**Storage**: Dibs-owned `RCLootCouncil_dibsDB` SavedVariables for ledger and audit data.
RCLootCouncil remains non-authoritative: the adapter may apply a narrow local Master Looter
button/response compatibility projection, while history, candidate/session data, and wire
state remain untouched.

**Testing**: Fengari/Lua test harness through `tests/run.lua`; focused unit, contract, and
integration fixtures; manual WoW Retail smoke tests with one and two clients

**Target Platform**: World of Warcraft Retail client, including RCLootCouncil absent,
operational, degraded, and unknown capability states

**Project Type**: Single modular World of Warcraft addon with an optional integration
adapter

**Performance Goals**: Capability checks and award validation complete synchronously without
blocking the loot UI; repeated UI callbacks install no duplicate hooks; normal raid usage
does not create unbounded timers, buffers, or broadcasts

**Constraints**: No RCLootCouncil source modification; no protected gameplay automation;
no live candidate/vote/session synchronization; all Dibs policy and manual accounting
requires verified guild GM/officer authority; automatic debit requires a verified local ML,
explicit finalized DIB response, stable identities, and a trusted integration state;
combat-sensitive UI work is deferred; release changes require a dated changelog note and
addon version increment

**Scale/Scope**: One guild with multiple concurrent raid groups, approximately 30 players
per raid, season-long Dibs history, and the currently supported RCLootCouncil integration
surfaces

## Constitution Check

*GATE: Passed before Phase 0 research and re-checked after Phase 1 design.*

- **WoW API and combat safety**: Pass. The adapter observes addon-owned events and uses
  supported hooks; any UI refresh or options operation remains combat-safe.
- **Ledger integrity**: Pass. Only a validated finalized DIB award can trigger automatic
  consumption; duplicate award identities are idempotent; non-DIB and test awards have no
  production accounting effect.
- **Authority and trust**: Pass. Guild GM/officer authority remains the only Dibs policy
  and manual-ledger authority. The ML exception is limited to a verified local finalized
  award and cannot grant, remove, refund, or configure Dibs.
- **RCLootCouncil independence**: Pass. RCLootCouncil remains optional and owns its loot
  session, candidate handling, voting, awards, and history. Dibs only consumes a validated
  event and preserves unrelated RC data.
- **Privacy and synchronization**: Pass. No live RC candidates, votes, responses, or
  session state are sent as cross-raid Dibs data. Officer-only views and diagnostics remain
  access-controlled.
- **Persistence and migrations**: Pass. Dibs SavedVariables remain authoritative and any
  new award metadata is versioned without rewriting historical transactions.
- **Release traceability**: Pass. Every shipped addon behavior/build change includes a
  dated changelog note and an addon version increment.

## Project Structure

### Documentation (this feature)

```text
specs/004-rclootcouncil-integration-robust/
|-- plan.md              # This file
|-- research.md          # Phase 0 decisions and evidence
|-- data-model.md        # Phase 1 entities and validation rules
|-- quickstart.md        # Phase 1 automated and Retail validation guide
|-- contracts/           # Phase 1 adapter, award, authority, and compatibility contracts
`-- tasks.md             # Phase 2 output from speckit-tasks
```

### Source Code (repository root)

```text
src/
|-- Core.lua
|-- RCLootCouncil_dibs.toc
|-- integrations/
|   |-- Ace3.lua
|   |-- RCLootCouncil.lua
|   |-- RCLootCouncilOptions.lua
|   `-- EncounterJournal.lua
|-- modules/
|   |-- Permissions.lua
|   |-- ProtectedActions.lua
|   |-- Ledger.lua
|   |-- LootPipeline.lua
|   `-- Sync.lua
|-- ui/
|   |-- PlayerUI.lua
|   `-- OfficerUI.lua
tests/
|-- contract/
|-- integration/
`-- unit/
```

**Structure Decision**: Keep the existing modular addon layout. The RCLootCouncil adapter
owns capability detection, guarded hooks, response projection, and award event mapping.
`ProtectedActions.lua` remains the single authoritative entry point for award accounting;
`Permissions.lua` owns the guild authority matrix; `Ledger.lua` owns immutable accounting;
`RCLootCouncilOptions.lua` owns the integration settings surface. Tests stay separated by
contract, integration, and unit scope. New compatibility and finalized-award contracts
are documentation artifacts, while implementation work changes only the existing adapter,
protected pipeline, diagnostics, and their focused tests.

## Phase 0: Research Decisions

Research is recorded in [research.md](research.md). The decisions resolve the integration
unknowns before implementation:

1. Detect capabilities and operational state instead of trusting an addon version label.
2. Install hooks idempotently and revalidate state for every protected action.
3. Require the callback client to be the current local Master Looter; never trust a remote
   actor object or a generic raid role.
4. Require a stable award identity and fail closed when RCLootCouncil cannot provide one.
5. Normalize only explicit DIB responses and keep test/non-DIB awards out of accounting.
6. Treat RCLootCouncil history as read-only and mark only Dibs-originated records.
7. Keep Standalone operation and Dibs-owned persistence independent of the adapter.

## Phase 1: Design Summary

The data model and contracts define runtime integration state, verified ML identity, award
provenance, idempotent accounting, compatibility capabilities, and diagnostics. The design
uses a strict boundary:

```text
RCLootCouncil event
        |
        v
capability + local-ML + response + identity validation
        |
        +-- ignored/rejected with diagnostic
        `-- ProtectedActions.FinalizeAward
                    |
                    +-- existing awardRef -> idempotent result
                    `-- new awardRef -> one validated ledger debit
```

Manual Dibs policy and ledger changes continue to use the guild GM/officer path. No adapter
callback can bypass that path or become a new source of authority.

## Implementation Approach

### Phase 2A: Adapter boundary and compatibility

- Introduce a single capability snapshot and reason-code vocabulary for absent,
  operational, degraded, and unsupported states.
- Centralize RCLootCouncil discovery and capability checks so options, voting UI, and award
  callbacks do not each infer compatibility differently.
- Make lifecycle hooks idempotent, bounded, and safe when RCLootCouncil loads late, reloads,
  disables, or rebuilds its frames.
- Keep all RCLootCouncil reads side-effect-free and never write its registries or history
  except for Dibs-owned markers explicitly documented by the contract.

### Phase 2B: Award validation and accounting

- Normalize callback fields into the finalized-award contract.
- Re-read the current Master Looter and require the local actor identity to match it.
- Accept only an explicit DIB response, a real finalized award, trusted integration state,
  stable winner/item/session identity, and a valid Dibs eligibility result.
- Prefer an immutable RCLootCouncil history identity; use a deterministic session identity
  only when it is unique and persisted; reject ambiguous events instead of guessing.
- Route all accepted events through the existing protected finalization action and preserve
  append-only ledger behavior.
- Add regression coverage for duplicate events, reconnect/reload replay, ML changes, and
  malformed or incomplete callbacks.

### Phase 2C: UI, options, and diagnostics

- Keep candidate/status projections read-only from RCLootCouncil's perspective. The only
  local configuration mutation is the locked indexed DIB button/response projection; it must
  preserve existing active responses and never rewrite RCLootCouncil history or session data.
- Expose capability state, supported assumptions, and rejection reasons without exposing
  live candidate, vote, or session data to ordinary players.
- Preserve the same options in Standalone mode, hide officer controls from unauthorized
  players, and avoid opening or refreshing protected windows during combat.
- Add a release-note/version check to the implementation checklist for every shipped
  change.

### Phase 2D: Validation and rollout

- Run focused contract and integration tests, then the full Lua suite with RCLootCouncil
  present, absent, disabled, and supplied through external LibStub services.
- Perform Retail smoke tests with one client and a two-client ML/officer/player matrix.
- Record results, client/build information, and any unsupported capability surface in
  [quickstart.md](quickstart.md) without committing private guild identities.
- Ship only after the changelog entry and addon version increment are present together.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| RCLootCouncil changes an internal surface without a stable public contract | Capability probing, explicit compatibility record, degraded state, fail-closed award path |
| A callback is replayed or delivered after reload | Stable award identity, persisted accounting reference, idempotent protected action |
| A non-ML client tries to replay a remote ML event | Local actor identity check plus current Master Looter revalidation |
| Missing item/winner/session metadata causes an incorrect debit | Reject ambiguous awards and expose a reason code |
| Hook installation loops or duplicates UI controls | Per-owner installation markers, bounded retry, no self-triggered update loop |
| Integration settings accidentally become Dibs administration | All policy and manual accounting callbacks remain behind GM/officer checks |
| A compatibility fix breaks Standalone mode | Run absent/degraded regression tests and keep adapter optional |
| Release behavior changes without traceability | Require dated changelog note and addon version increment in the release gate |

## Constitution Re-check After Phase 1 Design

All design gates remain passed:

- The adapter adds no new Dibs administrator role and does not promote Raid Leader,
  Raid Assistant, council, or ML status into guild administration.
- The ML exception is an event provenance check limited to one finalized DIB debit.
- Award records remain append-only and replay-safe; ambiguous input is rejected.
- Dibs SavedVariables remain the accounting authority; the narrow local DIB button/response
  projection is compatibility configuration, while RCLootCouncil history and session state
  remain read-only.
- Cross-raid payloads contain no live RCLootCouncil session data.
- Standalone initialization, optional Ace3 services, combat safety, and player privacy are
  covered by explicit implementation and validation work.
- The plan includes the constitution's dated changelog and addon-version requirement.

No constitution violation requires a complexity exception.

## Complexity Tracking

No violations. The design stays within the existing addon, adapter, protected-action,
ledger, options, diagnostics, and test modules.
