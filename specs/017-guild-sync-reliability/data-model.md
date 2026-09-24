# Phase 1 Data Model: Guild Sync Reliability

## AwardProposal

Represents a loot award finalized by a guild member who is not the current
ledger coordinator. Already exists locally as `Governance.RecordAwardProposal`'s
`recordClass = "AWARD_PROPOSAL"` record; this feature adds delivery/relay state
on top of the existing fields.

| Field | Type | Notes |
|---|---|---|
| `proposalId` | string | Existing stable identifier (`Dibs.NewId`-based). Used as the sync entity id and replay-dedup key. |
| `status` | enum | Existing: `PENDING_RECONCILIATION` (not yet committed). New: `RELAY_PENDING` (not yet acknowledged by coordinator), `RELAY_ACKED` (coordinator has the detail but has not committed), `COMMITTED` (applied to the ledger — mirrors an `AWARD_COMMIT` the submitter later observes). |
| `playerSnapshot` | Identity snapshot | Existing. Player the award is for. |
| `itemID` / `itemLink` / `awardRef` / `evidenceId` | existing | Award evidence fields, unchanged. |
| `submitterSnapshot` | Identity snapshot | New. The non-coordinator officer who recorded the proposal (needed so the coordinator's pending list can show "submitted by"). |
| `raidContext` | string/nil | New, optional. Free-form label (e.g., group name) purely for the coordinator's pending-list UI; never used for authorization. |
| `relayAttempts` | integer | New. Bounded retry counter for the local delivery queue (caps to avoid unbounded retry loops). |
| `createdAt` | timestamp | Existing. |

**Validation rules**:
- `proposalId` MUST be present and unique; the receiver (coordinator) MUST
  treat re-delivery of the same `proposalId` as idempotent (no duplicate
  ledger effect), satisfying Constitution X.
- Only the coordinator resolved via the current, verified `Governance`
  authority state may transition a proposal to `COMMITTED`
  (`Ledger.CommitAwardProposal`), never the submitter's own client.
- `relayAttempts` is capped (bounded, matching existing `MAX_MESSAGES`-style
  caps elsewhere in `SyncV2.lua`) to prevent an unreachable coordinator from
  causing unbounded local queue growth.

**State transitions**: `PENDING_RECONCILIATION` (local only) → `RELAY_PENDING`
(WHISPER sent) → `RELAY_ACKED` (coordinator confirms receipt of the detail,
independent of whether it has been committed yet) → `COMMITTED` (coordinator
calls `Ledger.CommitAwardProposal`, then broadcasts the resulting
`AWARD_COMMIT` through the existing, unchanged commit-broadcast path).

## SeasonCatalogRecord

A guild-wide, revisioned snapshot of `Dibs.Seasons`' local state, replicated
from the Guild Master/authorized officer's client to every other member.

| Field | Type | Notes |
|---|---|---|
| `schema` | integer | Versioned, same convention as `OperationalPolicy`/`Governance` records. |
| `policyRevision` | integer | Monotonically increasing; bumped on every `Create`/`Rename`/`Archive`/`SetCurrent`. |
| `parentHash` / `contentHash` | string | Hash-chain fields, computed via the existing `Dibs.Sync.CalculateContentHash`, same as `OperationalPolicy`. |
| `authorMemberKey` / `authorNameRealm` | identity | Who made the change, for audit and authorization re-verification on receipt. |
| `currentSeasonId` | string | Mirrors `db.currentSeasonId`. |
| `seasons` | map of `seasonId -> SeasonEntry` | Full catalog (active + archived), so a newly joined/reconnected client can fully catch up in one transfer. |

### SeasonEntry (nested)

| Field | Type | Notes |
|---|---|---|
| `id` | string | Existing `season.id`. |
| `name` | string | Existing `season.name`. |
| `createdAt` / `updatedAt` / `archivedAt` | timestamp/nil | Existing fields from `Seasons.lua`. |
| `isActive` / `isArchived` | boolean | Existing fields. |

**Validation rules**:
- Receivers MUST re-verify the sender's writer authority using the same rule
  already used for `OperationalPolicy` (`GM`, or configured
  `policyWriterRule` rank) before applying a `SeasonCatalogRecord` — never
  trust a payload claim (Constitution XI).
- Applying a record MUST be a full replace of the local `seasons` map keyed by
  `id` (never delete an season the receiver already knows about that is
  simply absent from an older/partial record) to avoid data loss from a
  stale or partial digest.
- `currentSeasonId` on the receiver is only updated if the referenced season
  exists (post-merge) and is not archived; otherwise the receiver keeps its
  own previously-resolved current season (matches existing
  `Seasons.GetCurrent()` fallback behavior).

**State transitions**: Local mutation (`Create`/`Rename`/`Archive`/`SetCurrent`
via `ProtectedActions`) → local `policyRevision` bump → `AnnounceSeasonCatalog`
DIGEST broadcast → receiver's `DETAIL_FETCH`/`TRANSFER_*` catch-up if behind.

## SynchronizationStatus (presentation-only, not persisted as its own record)

A read-only projection combining existing state for User Story 3:

| Field | Source |
|---|---|
| `governanceAdopted` | `Dibs.Governance.GetState().status == "GOVERNANCE_ADOPTED"` |
| `operationalPolicyAdopted` | `Dibs.OperationalPolicy.IsAdopted()` |
| `seasonCatalogRevision` | local `db.seasonCatalog.policyRevision` |
| `pendingAwardProposals` | count of local `AwardProposal` records not yet `COMMITTED` |
| `lastProtocolMismatch` | most recent `UNSUPPORTED_PROTOCOL_MAJOR` observation (sender + local/remote major), if any, bounded/expiring |

This entity has no independent lifecycle; it is computed on demand for
Officer UI and `/dibs debug report`.
