# Implementation Plan: Great Vault Acquisition Tracking and Guild Sync

**Branch**: `013-great-vault-acquisition-sync` | **Date**: 2026-09-21 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/013-great-vault-acquisition-sync/spec.md`

## Summary

Add capability-aware Great Vault claim tracking to the existing Dibs acquisition
history. Automatic detection is enabled only when the Retail client supplies
sufficient claim evidence; `/dibs vault` remains the manual fallback. Records
remain outside the Dibs ledger, are evaluated through `CharacterEligibility`,
and synchronize through the existing guild-scoped `Sync`/`SyncV2` transport with
bounded digests, detail recovery, replay protection, and privacy projections.
Existing Vault records are migrated additively and never silently promoted to
confirmed evidence.

## Technical Context

**Language/Version**: Lua 5.1-compatible World of Warcraft Retail addon code.

**Primary Dependencies**: WoW Retail API when available; existing Ace3 transport,
serialization, event, timer, permission, persistence, `PreDibs`,
`CharacterEligibility`, `Sync`, and `SyncV2` services.

**Storage**: Versioned guild-scoped `RCLootCouncil_dibsDB` SavedVariables. The
current guild schema is version 6; this feature requires an additive version 7
migration for acquisition confidence, reset, evidence, and synchronization
metadata. No RCLootCouncil SavedVariables are authoritative.

**Testing**: Fengari test runner with existing WoW/Ace3/RCLootCouncil doubles;
unit tests for acquisition state and identity, contract tests for message
validation/privacy, integration tests for migration/recovery, and manual Retail
plus two-client validation for actual Great Vault signals and addon delivery.

**Target Platform**: World of Warcraft Retail, standalone or with optional
RCLootCouncil installed.

**Project Type**: Modular World of Warcraft addon with guild-scoped persistence,
optional integrations, modeless Player/Officer UI, and addon-message sync.

**Performance Goals**: Record claim events in constant local work; keep digest,
fetch, and transfer payloads within existing SyncV2 bounds; avoid full database
scans on every event; provide bounded acquisition queries and deterministic
replay handling.

**Constraints**: No live-loot synchronization, no Dibs ledger mutation, no
remote database, no GitHub data storage, no trust in claimed sender roles, no
last-write-wins for evidence conflicts, combat-safe UI, localized statuses, and
manual fallback when the Retail capability is absent or ambiguous.

**Scale/Scope**: One or more raid groups in one guild, multiple characters and
seasons, thousands of acquisition/history records, bounded sync payloads, and
guild/character isolation for every persisted record.

## Constitution Check

*GATE: Passed before Phase 0 research. Re-check after Phase 1 design.*

- **World of Warcraft API compliance**: PASS. Automatic detection is optional
  and capability-probed; no protected gameplay action is automated.
- **Dibs are not DKP**: PASS. Vault records never grant or consume Dibs.
- **Append-only ledger and auditability**: PASS. Vault evidence is separate from
  the ledger; review decisions preserve original evidence and require reasons.
- **Optional RCLootCouncil integration**: PASS. Great Vault tracking works
  standalone and does not modify RCLootCouncil source or SavedVariables.
- **Distributed synchronization**: PASS. The design reuses guild envelopes,
  bounded deltas, sender validation, replay checks, and recovery semantics.
- **Authority and trust**: PASS. Automatic evidence is capability-bound;
  manual review and full evidence access require verified GM/Officer authority.
- **Guild and character isolation**: PASS. Records carry guild scope and use a
  character-scoped fallback when unguilded; cross-guild messages are rejected.
- **Privacy and live-loot boundary**: PASS. Digests and projections exclude
  candidates, votes, responses, loot sessions, and unrelated private evidence.
- **SavedVariables and protocol compatibility**: PASS with migration gate. The
  implementation must add the version 7 migration, preserve version 6 records,
  and document any protocol/version change before release.
- **Diagnostics, localization, and documentation**: PASS with release gate.
  New statuses, commands, sync outcomes, guides, changelog, and version metadata
  must be updated before shipping.

The only unresolved external uncertainty is the exact Retail claim signal. The
research decision is capability-aware detection with manual fallback; a Retail
validation gate remains mandatory before enabling any automatic path.

## Project Structure

### Documentation (this feature)

```text
specs/013-great-vault-acquisition-sync/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── vault-acquisition.md
│   └── vault-sync.md
└── tasks.md                  # Created by /speckit.tasks
```

### Source Code (repository root)

```text
src/
├── Core.lua                         # Guild schema version 7 migration and slash lifecycle
├── Types.lua                        # Acquisition and sync annotations
├── modules/
│   ├── PreDibs.lua                  # Shared acquisition storage, manual entry, review boundary
│   ├── CharacterEligibility.lua     # Confirmed/unknown acquisition evaluation
│   ├── Sync.lua                     # Legacy transport boundary and forbidden-data checks
│   └── SyncV2.lua                   # Digest/detail recovery and protocol governance
├── integrations/
│   └── GreatVault.lua               # Capability probe and Retail claim adapter
├── ui/
│   ├── PlayerUI.lua                 # Player-safe acquisition status
│   ├── OfficerUI.lua                # Review, conflict, and evidence controls
│   └── LogsUI.lua                   # Acquisition history projection
└── locales/
   ├── enUS.lua                     # New statuses and diagnostics
   └── frFR.lua

tests/
├── unit/great_vault_acquisition_spec.lua
├── contract/great_vault_sync_contract_spec.lua
├── integration/great_vault_migration_spec.lua
├── integration/great_vault_sync_recovery_spec.lua
├── integration/great_vault_privacy_spec.lua
└── integration/great_vault_retail_capability_spec.lua
```

**Structure Decision**: Keep acquisition business rules in `PreDibs` and
`CharacterEligibility`, add only the Great Vault integration adapter needed to
translate Retail observations into validated acquisition evidence, and extend
the existing synchronization modules rather than creating parallel state or
transport. UI remains a projection layer and cannot write authoritative state
directly.

## Phase 0: Research and contract decisions

1. Confirm the current Retail client's exposed Great Vault signals, item identity
  availability, reset metadata, protected-frame restrictions, and duplicate
  update behavior. Record the result as a capability matrix; do not assume an
  undocumented event is a claim proof.
2. Confirm the existing `PreDibs` acquisition storage and
  `CharacterEligibility` evidence boundary can accept the new verification and
  reset fields without a second collection.
3. Confirm the existing `SyncV2` digest/detail and `AWARD_COMMIT` restrictions
  can carry a bounded Vault entity without exposing live loot or enabling a
  canonical ledger write.
4. Use [research.md](research.md), [data-model.md](data-model.md),
  [contracts/vault-acquisition.md](contracts/vault-acquisition.md), and
  [contracts/vault-sync.md](contracts/vault-sync.md) as the resolved decisions.

## Phase 1: Persistence and acquisition evidence

1. Extend the guild migration additively from version 6 to version 7. Preserve
  all existing acquisition fields and classify missing confidence/reset data
  as legacy/manual rather than upgrading it.
2. Extend the shared acquisition model with stable identity, reset context,
  source, verification state, evidence state, revision, content hash, and
  sync state. Keep Vault records outside the ledger.
3. Refactor manual `/dibs vault` recording to use the shared identity and
  idempotence rules while preserving its command and user-facing fallback.
4. Add the capability-aware Great Vault adapter. It must initialize safely when
  the Retail capability is unavailable and must create no confirmed record from
  a reward choice or ordinary Vault update.
5. Add Officer review transitions for manual, legacy, and ambiguous records.
  Confirmation, rejection, and reference-only decisions require reason,
  authority, audit metadata, and immutable original evidence.
6. Feed verification-aware records into `CharacterEligibility` without
  duplicating policy. Confirmed records may count; uncertain records follow
  the existing unknown-data policy.

## Phase 2: Guild synchronization and recovery

1. Add bounded Vault digest projections to the existing lifecycle/anti-entropy
  path without broadcasting full acquisition evidence.
2. Add Vault fetch/detail handling through existing `SyncV2` validation and
  transfer envelopes. Enforce guild scope, sender identity, projection
  visibility, revision, content hash, and forbidden live-loot checks.
3. Apply detail records atomically through the shared acquisition boundary.
  Return idempotent, stale, conflict, rejected, and applied results without
  changing the Dibs ledger.
4. Reuse existing heartbeat, roster, reconnect, chunk expiry, and sync-behind
  states. Do not add a separate transport or a ledger commit path.
5. Add normal-player and Officer projections and ensure full evidence is never
  exposed to unauthorized clients.

## Phase 3: UI, diagnostics, localization, and documentation

1. Add Player acquisition status text for source, verification, reset context,
  sync state, and eligibility explanation.
2. Add Officer review/filter controls for unresolved, conflicting, stale, and
  manually recorded acquisitions with required reasons and confirmations.
3. Add capability and sync diagnostics using the existing diagnostic policy;
  never emit live loot details in debug output.
4. Add English/French labels, slash-command help, protocol documentation,
  player/GM guides, README/roadmap references, changelog entry, and version
  update required by the constitution.

## Phase 4: Validation and release gates

1. Run focused unit, contract, migration, privacy, and recovery tests using the
  command in [quickstart.md](quickstart.md).
2. Run the full Fengari suite and verify no existing Pre-Dibs, eligibility,
  sync, migration, ledger, or UI contract regresses.
3. Perform one-client Retail validation for claim detection, manual fallback,
  reset context, reload/reconnect replay, combat safety, and unavailable API
  behavior.
4. Perform two-client same-guild validation for digest, fetch, detail,
  idempotence, bounded recovery, privacy projection, stale revision, and
  conflict handling.
5. Perform cross-guild, unguilded-character, malformed-message, and legacy
  migration validation. Record evidence before release publication.

## Data Flow

```text
Retail capability probe or /dibs vault
  -> Great Vault adapter / manual command
  -> PreDibs acquisition validation and persistence
  -> CharacterEligibility verification-aware evaluation
  -> Player/Officer projection

Guild lifecycle
  -> SyncV2 VAULT_DIGEST
  -> bounded VAULT_FETCH
  -> validated VAULT_DETAIL
  -> atomic acquisition apply
  -> VAULT_ACK / sync status
```

At no point does this flow enter the Dibs ledger or transfer live RCLootCouncil
session state.

## Complexity Tracking

No constitution violations require justification. The feature adds one adapter
and extends existing acquisition/protocol boundaries because a separate Vault
database or transport would duplicate authority, privacy, migration, and replay
rules.
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
