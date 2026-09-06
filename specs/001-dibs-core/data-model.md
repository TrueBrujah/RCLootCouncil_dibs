# Data Model: Independent Dibs Core

## Entity: Season

- Description: Time-bounded Dib accounting context with one active season at a time.
- Fields:
  - id (string, required, unique)
  - name (string, required)
  - status (enum: active, inactive, archived)
  - createdAt (timestamp, required)
  - updatedAt (timestamp, required)
- Validation rules:
  - id must be unique.
  - Only one season may have status=active at a time.

## Entity: RankAllocationRule

- Description: Configurable Dib allocation policy per guild rank within a season.
- Fields:
  - seasonId (string, required, references Season.id)
  - rankIndex (integer, required)
  - rankName (string, optional)
  - allocation (integer, required, non-negative)
  - updatedBy (string, required)
  - updatedAt (timestamp, required)
- Validation rules:
  - (seasonId, rankIndex) must be unique.
  - allocation must be >= 0.

## Entity: PlayerSeasonState

- Description: Derived view of a player's seasonal Dib state for reporting and UX.
- Fields:
  - seasonId (string, required)
  - playerGuid (string, required)
  - playerName (string, optional)
  - currentRankIndex (integer, optional)
  - baseAllocation (integer, derived)
  - transactionDelta (integer, derived)
  - remainingBalance (integer, derived)
  - lastComputedAt (timestamp, derived)
- Validation rules:
  - remainingBalance = baseAllocation + transactionDelta.
  - Derived fields are read-only projections from season rules and transactions.

## Entity: DibTransaction

- Description: Immutable authoritative ledger row.
- Fields:
  - transactionId (string, required, unique idempotency key)
  - timestamp (timestamp, required)
  - seasonId (string, required)
  - playerGuid (string, required)
  - playerName (string, optional)
  - playerRankIndex (integer, required)
  - actionType (enum, required)
  - quantityDelta (integer, required)
  - actorIdentity (string, optional)
  - reason (string, required for administrative actions)
  - relatedItem (object, optional)
  - metadata (object, optional)
- Allowed actionType values (initial set):
  - SEASON_ALLOCATION
  - DIB_GRANTED
  - DIB_USED
  - DIB_REFUNDED
  - DIB_REVOKED
  - DIB_ADMIN_ADJUSTMENT
- Validation rules:
  - transactionId must be globally unique within the ledger.
  - seasonId must reference an existing season.
  - playerGuid must be present.
  - reason must be present when actionType=DIB_ADMIN_ADJUSTMENT.
  - Existing transactions cannot be edited or deleted.

## Entity: PermissionRoleContext

- Description: Authorization context for authoritative actions.
- Fields:
  - actorGuid (string, optional)
  - actorName (string, required)
  - role (enum: PLAYER, OFFICER, GM; legacy DIBS_ADMIN appointments are retained separately as audit history)
  - grantedAt (timestamp, optional)
  - grantedBy (string, optional)
- Validation rules:
  - Authoritative transaction acceptance must evaluate role before write.

## Relationships

- Season 1..* RankAllocationRule
- Season 1..* DibTransaction
- PlayerSeasonState is derived from Season + RankAllocationRule + DibTransaction
- PermissionRoleContext governs ability to create authoritative DibTransaction rows

## State Transitions

### Season

- inactive -> active (when selected as current season)
- active -> inactive (when another season is activated)
- inactive -> archived (historical retention)

### Transaction lifecycle

- proposed -> validated -> appended
- duplicate transactionId -> ignored (idempotent no-op)
- validation failure -> rejected (no ledger change)

### Player rank evolution

- rank update changes future transaction playerRankIndex capture only
- historical DibTransaction rows remain immutable
