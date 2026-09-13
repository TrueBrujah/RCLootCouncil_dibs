# B05b Implementation Evidence

## Result

- Branch: `dev`
- `B05B_START_COMMIT=ccf33c2aec73ea525e5918825fa0f3584456fa70`
- `B05B_CHECKPOINT_COMMIT=ccf33c2aec73ea525e5918825fa0f3584456fa70`
- `B05B_RESULT_COMMIT=d9446695590fcabb9ad051df52294108d9fb9353`

The existing B05a evidence commit was verified as the B05b start/checkpoint.
No second checkpoint was created after the quota interruption. Local unrelated
changes were preserved and excluded from the result commit.

## Files in the result commit

- `src/Core.lua`
- `src/modules/Governance.lua`
- `src/modules/Ledger.lua`
- `src/modules/SyncV2.lua`
- `tests/integration/b05b_authority_recovery_spec.lua`

## Authority state machine

`db.governance.authority` is an additive, schema-versioned durable record with
bounded proposal, orphan, and audit collections. The accepted states are:

- `LEGACY_LOCAL`
- `ACTIVE`
- `HANDOFF_CLOSING`
- `COORDINATOR_UNAVAILABLE`
- `RECOVERY_PENDING`

Legacy data does not infer a coordinator or epoch. An `ACTIVE` authority state
is created only by a current-roster GM governance record and contains the
Name-Realm coordinator snapshot, epoch, transition metadata, and transition
hash. SavedVariables validation keeps this structure additive and quarantines
unsupported authority state.

## Normal handoff and forced recovery

- The current coordinator alone can publish a `HANDOFF_CLOSING` closure.
  The closure binds guild, predecessor epoch, coordinator, final sequence,
  root hash, timestamp, and deterministic closure hash.
- A successor `ACTIVE(E+1)` normal transition requires the exact persisted
  predecessor closure and parent closure hash in a current-GM governance
  record. Conflicting or stale closure signals are rejected.
- Coordinator loss is explicit; there is no timeout, election, or automatic
  replacement. Entering `RECOVERY_PENDING` requires the current GM.
- Forced recovery to `ACTIVE(E+1)` requires the current GM, a B05a-approved
  `legacyBaselineHash`, explicit recovery audit metadata, and a new governance
  transition.

## Fail-closed Dib use and evidence

`Ledger:CommitLocalTransaction` checks B05b authority before any `DIB_USED`
append. In `HANDOFF_CLOSING`, `COORDINATOR_UNAVAILABLE`, and
`RECOVERY_PENDING`, it returns the authority state as its reason and does not
append a canonical transaction, debit a balance, or reserve a Dib.

The blocked command may record a durable `AWARD_PROPOSAL` with status
`PENDING_RECONCILIATION`. Proposal identity is deterministic for identical
evidence and has zero canonical balance effect.

After forced recovery, late evidence present in the approved B05a baseline is
treated as known idempotent evidence. Excluded late predecessor evidence is
stored as `ORPHANED_EVIDENCE`; it cannot append to the ledger, debit a balance,
reopen predecessor authority, or alter the baseline.

`RECOVERY_PENDING_REVIEW` remains exclusively the B05a received-package review
status. It is separate from B05b's durable authority state
`RECOVERY_PENDING` in storage, validation, and tests.

## SyncV2 integration

SyncV2 now sends a bounded GUILD authority digest and WHISPER detail for
authority signals. It validates guild scope, Name-Realm sender identity,
message replay, hashes, current coordinator/GM authority, and stale authority
epoch/coordinator combinations. It can also transport orphaned-evidence
details without transporting ledger commits.

`SYNC_BEHIND` blocks an authority activation. A sync-behind client therefore
cannot become coordinator. No B06 ledger-detail synchronization, sequence/hash
chain activation, or distributed commit transport was introduced.

## Persistence and reload

The B05b test reloads SavedVariables while `HANDOFF_CLOSING` and verifies that
the coordinator and fencing state persist; no replacement coordinator is
inferred. Existing ledger IDs, B05a baseline evidence, Pre-Dibs, and
RCLootCouncil history are not rewritten.

## Validation

Focused B05b validation passed:

```text
7 passed, 0 failed (tests/integration/b05b_authority_recovery_spec.lua)
```

Targeted B00-B05a regression validation passed after the final B05b transport
change:

```text
36 passed, 0 failed
```

This included B04 transport, B05a legacy-baseline recovery, and governance
bootstrap coverage. The earlier targeted B00-B05a set also passed:

```text
56 passed, 0 failed (7 files)
```

The complete suite was executed once during this batch before the final,
targeted B05b transport correction. It reproduced the known B05a baseline
failure and did not identify a B05b regression:

```text
FAIL RCLootCouncil DIB response projection /
  renders the voting Dibs value from a normalized RCLootCouncil row identity
tests/integration/rclootcouncil_buttons_spec.lua:155: expected 2/2, got 1/1
```

This is pre-existing, matches the B05a baseline, and was not introduced by
B05b. The suite was not rerun after the final correction because that change
was confined to B05b SyncV2 authority/orphan transport and its affected B04,
B05a, governance, and B05b regressions passed.

## Scope confirmation and known limitations

- No production `AWARD_COMMIT` behavior exists.
- B06 distributed ledger activation, per-epoch sequence/hash-chain enforcement,
  and ledger-detail synchronization were not started.
- RCLootCouncil source and behavior were not modified.
- WoW protected UI APIs were not introduced; B05b changes only persisted-domain
  validation and addon-message handling.
- Addon-message hashes remain integrity/attribution checks, not server-backed
  cryptographic authentication; current-roster authority remains the WoW-addon
  trust boundary.
