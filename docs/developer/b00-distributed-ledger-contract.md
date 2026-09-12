# B00 Distributed Ledger Contract Fixture

This document describes the test-only contract implemented by
`tests/helpers/distributed_ledger_fixture.lua`. It is not a production protocol
and does not enable V2 synchronization, coordinator writes, migrations, or
RCLootCouncil behavior.

## Purpose

The fixture gives B02a, B03, B04, B05a, B05b, B06, and B09 a deterministic way
to model independent clients, two raids, message delay/duplication/reordering/
loss, partitions, coordinator loss, recovery, and reconnect.

## Contract invariants

- Wire identities are complete Name-Realm keys. GUID is optional witness data;
  a short name returns `AMBIGUOUS_IDENTITY`.
- `policyRevision` is independent of `ledgerEpoch`. Operational policy cannot
  change coordinator, epoch, governance, baseline, or protocol cutover.
- Governance adoption/change requires the virtual current Guild Master.
- Ledger application requires current epoch, exact next sequence, matching
  previous hash, and deterministic content hash. Gaps and mismatches yield
  `SYNC_BEHIND`.
- A `SYNC_BEHIND` client cannot activate as coordinator or append a canonical
  debit.
- `COORDINATOR_UNAVAILABLE` and `RECOVERY_PENDING` permit only
  `AWARD_PROPOSAL` evidence with `PENDING_RECONCILIATION`, never a local balance
  reservation or canonical debit.
- Normal handoff requires `{previousEpoch, finalSeq, rootHash}`.
- Forced recovery requires GM approval, a baseline hash, non-empty peer evidence,
  and non-empty audit decisions. Late excluded old-epoch events become orphaned
  evidence.
- Legacy history is copied into immutable evidence; it is not rewritten into a
  V2 canonical event by this fixture.

## CH-01 split-brain scenario

The contract test models coordinator A and officer B in two simultaneous raids.
They agree on a shared event, partition, and A records an isolated old-epoch
event. B enters `RECOVERY_PENDING`, stores only a proposal, and the GM approves
an epoch-8 baseline excluding A's late event. When A reconnects, that event is
orphaned evidence rather than an automatic append.

This proves the intended safety property for future implementation: a forced
takeover creates no competing canonical debit while recovery is unresolved. It
does not claim that a client-only WoW addon can undo a physical award made by an
isolated former coordinator.

## Scope boundary

The fixture contains a deliberately simple deterministic `contractHash`, not a
cryptographic or production hash. B03/B04 must select and test the production
canonical serialization/hash. No code under `src/` imports this fixture.
