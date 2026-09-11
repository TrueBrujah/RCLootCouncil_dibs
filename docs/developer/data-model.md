# Data model and state machines

The active database is a guild bucket returned by `Dibs.GetDB()`. The current guild key is derived from guild identity, and the root SavedVariables wrapper is described in [saved-variables.md](saved-variables.md).

## Core records

- **Season:** `id`, `name`, status, and timestamps. One season may be current; archived seasons remain queryable.
- **Rank rule:** rank index/name plus an allocation for a season.
- **Transaction:** immutable transaction ID, player, season, signed amount, reason/source, timestamp, and optional rank/award/evidence references. Balance is the sum of valid transactions.
- **Pre-Dib request:** player, item, season, optional normalized difficulty/mode, status, timestamps, and monotonic revision. Terminal requests are not silently reactivated.
- **Vault acquisition:** player/item/difficulty/timestamp display record. It does not create a ledger transaction (DIBS-RULE-011).
- **Eligibility policy:** family, slot/duplicate outcome, difficulty/matching scope, and enforcement mode.
- **Dispute:** permission-filtered report, evidence, replies, status transitions, and correction links.
- **Reconciliation session/candidate:** RC history evidence awaiting an explicit officer decision.
- **Backup/profile:** bounded snapshot or named configuration projection.

## Lifecycle states

Pre-Dibs requests move through `pending -> confirmed -> fulfilled`, with `cancelled` or `invalidated` terminal branches. Sync revisions are monotonic and idempotent. Disputes move through open, review/waiting, resolved, and reopened states. Reconciliation candidates remain ambiguous until confirmed or rejected; confirmation is the only path that records a historical ledger award.

## Database tree

```text
guild
├── version
├── currentSeasonId, seasons
├── rankRules
├── ledger: transactions, playerStates, awardTransactions, evidenceTransactions
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
