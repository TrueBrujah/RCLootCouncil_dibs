# Data Model: Pre-Dibs Encounter Journal

## Entity: PreDibRequest

- Description: A player's advance request for a specific item in a season.
- Fields:
  - requestId (string, required, unique)
  - playerGuid (string, preferred identity when available)
  - playerName (string, required for display/compatibility)
  - itemID (integer, required, positive)
  - itemName (string, optional display metadata)
  - itemLink (string, optional display metadata)
  - seasonId (string, required)
  - status (enum: pending, confirmed, cancelled, invalidated, fulfilled)
  - source (enum/string, required for diagnostics)
  - createdAt (timestamp, required)
  - updatedAt (timestamp, required)
  - confirmedAt (timestamp, optional)
  - cancelledAt (timestamp, optional)
  - fulfilledAt (timestamp, optional)
  - awardRef (string, optional, set after qualifying award)
  - metadata (object, optional)
- Validation rules:
  - itemID must be positive.
  - seasonId must identify the active/requested season.
  - Active duplicate identity is `(player, itemID, seasonId)`.
  - Terminal statuses are not active for duplicate lookup.
  - Creating or confirming a request does not change Dib balance.
  - Fulfillment requires a successful authoritative award acceptance.

## Entity: AdventureGuidePolicy

- Description: Local display policy for whether the Dib action appears for an item sub-category.
- Fields:
  - categoryKey (string, normalized stable key)
  - allowed (boolean)
  - known (boolean)
  - recommendationNote (string, optional)
  - updatedAt (timestamp, optional)
- Validation rules:
  - Keys are normalized independently of localized labels.
  - Unknown categories are allowed unless explicitly blocked by the user.
  - Policy changes do not modify requests, transactions, balances, or history.

## Entity: AnnouncementSettings

- Description: Local destinations for Pre-Dib notifications.
- Fields:
  - publicChannel (enum/string)
  - officerChannel (enum/string)
- Validation rules:
  - Unsupported channels normalize to a safe fallback.
  - Unavailable channels are skipped without failing request persistence.
  - Duplicate configured destinations are sent at most once per announcement.

## Entity: FinalizedAwardReference

- Description: Stable identity for one completed item award.
- Fields:
  - awardRef (string, required, unique)
  - playerName/playerGuid (required identity)
  - itemID (integer, required)
  - seasonId (string, required)
  - sourceStatus (string, required)
  - finalized (boolean, required)
  - ledgerTransactionId (string, set after append)
  - processedAt (timestamp, required after processing)
- Validation rules:
  - Non-final statuses produce no consumption.
  - Repeated awardRef processing is an idempotent no-op.
  - The reference links request fulfillment to the resulting ledger transaction.

## Relationships

- One Season has many PreDibRequests.
- One PreDibRequest may resolve to zero or one FinalizedAwardReference.
- One FinalizedAwardReference may append at most one authoritative ledger transaction.
- AdventureGuidePolicy and AnnouncementSettings are local settings and do not own accounting state.

## State Transitions

```text
pending -> confirmed -> fulfilled
pending -> cancelled
pending -> invalidated
confirmed -> cancelled
confirmed -> invalidated
confirmed -> fulfilled
```

A request that does not win an item remains `confirmed` unless an explicit cancellation or invalidation occurs. A fulfilled request is terminal and cannot create another consumption.
