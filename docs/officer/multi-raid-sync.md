# Multi-raid operation and synchronization

Each raid may have its own active relay and encounter context. Configure one authorized relay when reminders need to be broadcast, and keep officers aware of which guild bucket is active.

Before V2 cutover, synchronization is legacy/local or non-canonical evidence only.
After the GM explicitly enables `V2_ENFORCED` and approves the baseline, the
active coordinator publishes bounded `LEDGER_DIGEST` hints and serves exact
`AWARD_COMMIT` detail over the protocol described in
[the synchronization reference](../developer/sync-protocol.md). A follower
must apply the next exact sequence and matching previous hash; it cannot infer
a balance from a digest or become coordinator while `SYNC_BEHIND`.

When the coordinator is unavailable or recovery is pending, award evidence is
recorded only as `PENDING_RECONCILIATION`; it has no local balance effect.
Normal handoff requires the predecessor epoch, final sequence, and root hash.
Forced recovery requires GM-approved baseline decisions, and late excluded
events remain orphaned evidence rather than automatic ledger commits.

Synchronization never transfers items, live RC candidates, votes, or responses
between raids. RCLootCouncil remains an optional evidence provider and cannot
grant Dibs administration or replace coordinator authority.
