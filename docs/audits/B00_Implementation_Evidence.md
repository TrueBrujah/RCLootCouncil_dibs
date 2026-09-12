# B00 Implementation Evidence

## Scope and commits

- Starting branch: `dev`
- `B00_START_COMMIT`: `f768b46935897b8605904cdf6387a776089d6eb5`
- `B00_CHECKPOINT_COMMIT`: `db1ef680a003a5f0cb2a113fdff97c7f6371af1c`
- `B00_RESULT_COMMIT`: `44eb1eb5147c72387c27b6561860e0a636d4a8d3`

The checkpoint contains the approved architecture material before B00. The B00
implementation commit contains only test-only fixtures, contract tests, and
developer documentation. Existing uncommitted user files were not staged or
changed.

## Files added

- `tests/helpers/distributed_ledger_fixture.lua` — deterministic, production-
  independent scenario fixture for clients, raids, transport faults, authority
  states, handoff, recovery, and inspection.
- `tests/contract/b00_architecture_contract_spec.lua` — reusable architecture
  contracts, including the corrected CH-01 partition/recovery scenario.
- `docs/developer/b00-distributed-ledger-contract.md` — fixture boundary and
  protocol-contract documentation for later batches.

## Files modified

None. In particular, no file under `src/` was changed and no production
RCLootCouncil integration file was changed.

## Validation executed

Targeted B00 plus inexpensive independence regression, once after the final
fixture correction:

```powershell
$env:DIBS_TEST_FILES = 'tests/contract/b00_architecture_contract_spec.lua;tests/contract/core_independence_spec.lua'
.\node_modules\.bin\fengari.cmd tests/run.lua
```

Result: **9 passed, 0 failed (2 files)**.

`git diff --check` completed with no reported whitespace error before staging.
The staged implementation diff named only the three files listed above.

## Architecture invariants represented

The B00 contracts cover the approved decision boundary:

- independent client state and two simultaneous raids;
- deterministic delay, duplicate, reorder, dropped packet, partition, heal,
  disconnect, and reconnect operations;
- complete Name-Realm wire identity, optional GUID witness, and rejection of an
  ambiguous short name;
- distinct `policyRevision` and `ledgerEpoch`; GM-only governance; and officer
  operational-policy authority that cannot alter coordinator, epoch,
  governance authority, baseline, or protocol state;
- exact ledger epoch/sequence/previous-hash/content-hash rules, idempotent
  replay, gap handling, and `SYNC_BEHIND` restrictions;
- `COORDINATOR_UNAVAILABLE` and `RECOVERY_PENDING`, where only
  `AWARD_PROPOSAL` evidence is permitted and no balance debit/reservation or
  canonical append occurs;
- normal handoff fencing with predecessor epoch, final sequence, and root hash;
- GM-only forced recovery requiring recovery state, a non-empty peer-evidence
  set, an approved baseline hash, and non-empty audit decisions;
- immutable legacy evidence alongside virtual LEGACY/V2 client compatibility.

## CH-01 and recovery coverage

The contract test starts coordinator A at epoch 7 and officer B in a second
raid. Both accept sequence 1, communication partitions, and A appends an
isolated sequence-2 old-epoch event. When A disconnects, B enters
`RECOVERY_PENDING`; B can create only a `PENDING_RECONCILIATION` proposal and
its balance remains unchanged. The GM selects a peer-evidenced baseline rooted
at shared sequence 1 and activates B at epoch 8. When A reconnects and sends
the old sequence-2 event late, B records it as `ORPHANED_EVIDENCE` and does not
append it to the epoch-8 canonical event list.

This is a test contract for the preferred architecture, not a claim that the
current production addon has implemented distributed coordination.

## Boundaries and follow-up

B00 deliberately uses a deterministic non-cryptographic `contractHash`. B03/
B04 must choose production serialization and hashing, B01/B02a must implement
the persistence/governance foundation, and B05/B06 must implement real WoW
transport and RCLootCouncil integration. No SavedVariables migration, production
V2 protocol activation, canonical coordinator write, synchronization behavior,
or RCLootCouncil behavior was enabled or modified by B00.

The evidence document is committed separately from the B00 implementation
because a Git commit cannot contain its own resulting hash. The implementation
hash above is the exact B00-only commit.
