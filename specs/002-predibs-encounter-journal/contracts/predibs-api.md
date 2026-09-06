# Contract: Pre-Dibs and Encounter Journal API

## `CreatePublic`

Purpose: Create or reuse a public Pre-Dib request.

Request:

- player identity
- item ID and optional display metadata
- season ID
- source label

Response:

- request object on success
- structured reason code on rejection

Invariants:

- Public requests are rejected when public Pre-Dibs are disabled.
- Active duplicate identity returns the existing request.
- Creation does not append a Dib consumption transaction.

## `Confirm`, `Cancel`, `Invalidate`, `Fulfill`

Purpose: Transition one request through its lifecycle.

Request:

- request ID
- status-specific context when required

Invariants:

- Terminal requests are not reactivated implicitly.
- Fulfillment is only valid after a qualifying finalized award.
- Status timestamps are retained.

## `GetActiveRequests`, `GetRequestsForItem`, `GetHistory`

Purpose: Read request state for player, item, or audit surfaces.

Invariants:

- Reads do not mutate requests or ledger state.
- Active lookup excludes fulfilled, cancelled, and invalidated requests.

## `CanPreDib` and `SubmitPreDib`

Purpose: Gate and submit Adventure Guide requests.

Invariants:

- Invalid item IDs are rejected.
- Non-raid contexts are rejected with a stable non-raid reason.
- Blocked sub-categories are not submitted.
- The submission uses the shared loot/request pipeline when available.
- Missing RCLootCouncil does not block the standalone path.

## `FinalizeAward`

Purpose: Commit one qualifying award through the authoritative protected action boundary.

Request:

- stable award reference
- player identity
- item ID
- season context
- finalized status
- optional request/source metadata

Invariants:

- Pending, failed, cancelled, or non-final events append nothing.
- A successful final award appends one ledger transaction and fulfills the matching request.
- Replaying an award reference returns the prior result without another transaction.
- RCLootCouncil is an optional event source, not the owner of this operation.

## Adventure Guide display contract

- Raid loot may expose a localized Dib action for eligible rows.
- Dungeon loot exposes no usable Dib action.
- Known blocked categories are hidden or disabled according to local policy.
- Unknown categories remain visible by default.
- UI refreshes must tolerate missing Blizzard frames and combat restrictions.

## Error contract

Stable reason codes include:

- `INVALID_ITEM`
- `PUBLIC_PRE_DIBS_DISABLED`
- `EJ_NON_RAID_CONTEXT`
- `PREDIB_UNAVAILABLE`
- `INVALID_CONTEXT`
- `AWARD_NOT_FINAL`
- `AWARD_ALREADY_PROCESSED`

Validation failures do not create partial request or ledger state.
