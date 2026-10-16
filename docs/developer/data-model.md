# Data model and state machines

The active database is a guild bucket returned by `Dibs.GetDB()`. The guild key uses the guild's home realm from `GetGuildInfo("player")` when available, falling back to the character realm. Members of one cross-realm guild therefore share a bucket. The root SavedVariables wrapper is described in [saved-variables.md](saved-variables.md).

## Core records

- **Season:** `id`, `name`, status, and timestamps. One season may be current; archived seasons remain queryable.
- **Rank rule:** rank index/name, enabled state, and allocation for a season. A
  disabled rank receives no starting allocation and its members are excluded from
  allocation-reconciliation warnings; existing ledger allocations are preserved.
- **Ledger:** guild catalog entry with approval/lifecycle metadata and separate
  transactions/player balances. `guild-primary` is the default; the active
  `ledger` is a projection of `ledgers[activeLedgerId]`.
- **Transaction:** immutable transaction ID, ledger, player, season, signed amount, reason/source, timestamp, and optional rank/award/evidence references. Balance is the sum of valid transactions in that ledger and season.
- **Pre-Dib request:** player, item, season, optional normalized difficulty/mode, status, timestamps, and monotonic revision. Terminal requests are not silently reactivated.
- **Vault acquisition:** player/item/difficulty/timestamp display record. It does not create a ledger transaction (DIBS-RULE-011).
- **Eligibility policy:** family, slot/duplicate outcome, difficulty/matching scope, and enforcement mode.
- **Dispute:** permission-filtered report, evidence, replies, revision, assignment,
  follow-up, pinned delivery authority, lifecycle audit, and correction links.
- **Private delivery:** per-character/per-guild pending operations, receipt/error
  states, retries, and reminder/snooze metadata; not a guild snapshot.
- **Reconciliation session/candidate:** RC history evidence awaiting an explicit officer decision.
- **Backup/profile:** bounded snapshot or named configuration projection.

## Lifecycle states

Pre-Dibs requests move through `pending -> confirmed -> fulfilled`, with `cancelled` or `invalidated` terminal branches. Sync revisions are monotonic and idempotent.
Disputes move through open, under-review, and need-information states to
resolved/rejected. A reasoned explicit close can then be archived; reopening
never reapplies an existing compensation. Dossiers and timelines are retained,
with explicit capacity failures rather than silent pruning. Shared mutations
require the verified pinned coordinator; a delivery receipt is not a resolution.
Reconciliation candidates remain ambiguous until confirmed or rejected;
confirmation is the only path that records a historical ledger award.

## Rank allocation reconciliation

`SEASON_ALLOCATION` is a positive assigned-allocation event, distinct from a balance adjustment. Manual reconciliation stores its target and requester identity snapshots, current rank, expected and assigned-before values, season catalog revision/hash, governance and operational-policy revisions, coordinator epoch, and deterministic operation key in the transaction content covered by the canonical hash. Non-coordinator requests remain `AWARD_PROPOSAL` records until the coordinator revalidates the live basis and emits the canonical `AWARD_COMMIT`. A negative difference is informational only: assigned allocation is retained and no transaction is written.

## Database tree

```text
guild
├── version
├── currentSeasonId, seasons
├── rankRules
├── ledgers[ledgerId]: transactions, playerStates, awardTransactions, evidenceTransactions
├── activeLedgerId, ledger (active-ledger compatibility projection)
├── governance, operationalPolicy, guildConfiguration
├── permissions: adminEvents, activeStandaloneAdmins
├── preDibs: requests, modePolicies, acquisitions
├── disputes: requests, order, corrections
├── reconciliation: sessions, aliases, decisions, evidence, evidenceIndex
├── characterEligibility: policies, acquisitions, relationships, mainChanges, exceptions, decisions
├── profiles: local character buckets, guild profiles, active markers
├── backups, backupRetention, pendingRestores, pendingImports, auditLog
├── sync: seenTransactions, peerStates
└── settings
```

All writes pass through the owning service. UI tables are projections and must never be treated as storage. Corrections append evidence and a new transaction rather than mutating an old accounting entry (DIBS-RULE-007 and DIBS-RULE-008).
