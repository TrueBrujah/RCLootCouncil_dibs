# Contract: Dibs Core API Surface

This contract defines stable core capabilities for seasonal Dib accounting. It describes expected requests/responses and invariants, without implementation coupling.

## 1) Season Management

### createSeason

- Purpose: Create a new season context.
- Request fields:
  - name (required)
- Response fields:
  - seasonId
  - status
- Invariants:
  - Newly created season is addressable by seasonId.

### setActiveSeason

- Purpose: Set current authoritative season.
- Request fields:
  - seasonId (required)
- Response fields:
  - activeSeasonId
- Invariants:
  - Exactly one active season exists after success.

### listSeasons

- Purpose: Enumerate known seasons.
- Authorization: GM/Officer scope is required because season metadata is administrative.
- Response fields:
  - seasons[] with id, name, status

## 2) Rank Allocation Policy

### setRankAllocation

- Purpose: Configure per-rank Dib allocation for a season.
- Request fields:
  - seasonId (required)
  - rankIndex (required)
  - allocation (required)
  - rankName (optional)
- Response fields:
  - seasonId
  - rankIndex
  - allocation
- Invariants:
  - Allocation policy is data-driven and never hard-coded.

### getRankAllocation

- Purpose: Read configured allocation for a rank in a season.
- Authorization: GM/Officer scope is required; players receive their derived personal allocation through player state instead.
- Request fields:
  - seasonId (required)
  - rankIndex (required)
- Response fields:
  - allocation
  - rankName (optional)

## 3) Authoritative Transactions

### appendTransaction

- Purpose: Validate and append one authoritative transaction.
- Request fields:
  - transactionId, timestamp, seasonId, playerGuid, actionType, quantityDelta (required)
  - playerName, playerRankIndex, actorIdentity, reason, relatedItem (conditional/optional)
- Response fields:
  - accepted (boolean)
  - idempotentReplay (boolean)
  - reasonCode (on rejection)
- Invariants:
  - Duplicate transactionId must not create a second accounting effect.
  - Existing rows are immutable and cannot be modified/deleted.
  - Administrative adjustment requires reason.

### getTransactions

- Purpose: Query immutable transaction history.
- Request fields:
  - seasonId (required)
  - playerGuid (optional)
- Response fields:
  - transactions[]

## 4) Balance and Player State

### getPlayerSeasonState

- Purpose: Return derived seasonal state for a player.
- Request fields:
  - seasonId (required)
  - playerGuid (required)
- Response fields:
  - baseAllocation
  - transactionDelta
  - remainingBalance
  - historySummary
- Invariants:
  - remainingBalance is derived from allocation plus ledger deltas.

## 5) Permission Foundation

### canExecuteAuthoritativeAction

- Purpose: Evaluate authorization before accepting authoritative changes.
- Request fields:
  - actor identity context
  - action identifier
- Response fields:
  - allowed (boolean)
  - authoritySource
  - reasonCode
- Invariants:
  - Player, Officer, and GM contexts are supported.
  - Authoritative Dibs actions require a verified guild Officer or GM in every installation mode.
  - Legacy DIBS_ADMIN appointment records are historical only and do not authorize a non-officer.

## Error Contract

- All mutating endpoints return structured failures with reasonCode.
- Validation failures do not partially write.
- Idempotent replay is treated as successful no-op with explicit replay signal.

## Out of Scope for This Core Contract

- RCLootCouncil adapter behaviors
- Encounter Journal interactions
- Loot-session candidate/vote state
- Cross-raid synchronization payloads

## Core API Stability Checklist

This checklist defines the compatibility bar for future features consuming the core:

- Keep function names and required fields stable for:
  - `createSeason`, `setActiveSeason`, `listSeasons`
  - `setRankAllocation`, `getRankAllocation`
  - `appendTransaction`, `getTransactions`, `getPlayerSeasonState`
  - `canExecuteAuthoritativeAction`
- Additive request/response fields are allowed when existing behavior remains unchanged.
- Existing `reasonCode` values must remain valid or map deterministically to successor values.
- Idempotent replay semantics for `transactionId` must remain no-op for accounting effects.
- Historical ledger immutability must remain enforced for all correction workflows.
- Standalone operation without RCLootCouncil, Encounter Journal, or sync context must remain supported.
