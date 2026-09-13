# B06 Implementation Evidence

## Scope and commits

- Branch: `dev`
- `B06_START_COMMIT=e7c97eaa8ffc3c7780b48c7cdad58711b41f9864`
- `B06_CHECKPOINT_COMMIT=e7c97eaa8ffc3c7780b48c7cdad58711b41f9864`
- `B06_RESULT_COMMIT=0fc780b`

The start/checkpoint is the completed B05b evidence commit. The working tree
already contained unrelated user changes to `docs/RC_OPTIONS.md` and
`RCLootCouncil_dibs.code-workspace`; neither file is included in B06.

## Files in the B06 result commit

- `src/Core.lua`
- `src/modules/Governance.lua`
- `src/modules/Ledger.lua`
- `src/modules/SyncV2.lua`
- `tests/integration/b06_distributed_ledger_spec.lua`

## Implemented architecture

### Explicit V2 cutover

`Governance.EnableV2` is an explicit governance record. It requires an ACTIVE
B05b authority, an approved B05a baseline, a non-`SYNC_BEHIND` client, and a
writer list that includes the coordinator and is compatible with SyncV2
capabilities. Applying the adopted record persists `V2_ENFORCED` in governance
and SyncV2. Normal handoff retains V2 only when its predecessor already used
V2; it cannot silently activate V2.

### Canonical coordinator commits

`Ledger.CommitDibUse` retains B03 local behavior before V2 cutover. After
cutover, it permits only the actual local B05b ACTIVE coordinator to originate
an `AWARD_COMMIT`. It requires a stable award identifier, derives a
deterministic transaction identity, builds and validates the immutable B03
transaction before mutation, verifies balance/debt policy, then atomically
persists the transaction and canonical cursor.

Each commit contains the guild, protocol major, authority epoch, exact
sequence, previous root, immutable transaction/content hash, coordinator
snapshot, and deterministic commit hash. Positions and transaction IDs are
idempotent; a duplicate is accepted without mutation, while conflicts, gaps,
stale sequence, wrong roots, wrong epochs, invalid sender identities, and
transaction conflicts are rejected before ledger mutation.

`Ledger.CommitLocalTransaction` rejects post-cutover `DIB_USED` bypasses with
`DISTRIBUTED_COMMIT_REQUIRED`. Non-coordinator attempts produce B05b
zero-effect `AWARD_PROPOSAL` evidence and never debit a balance. The B05b
authority gates continue to fail closed for handoff closing, coordinator loss,
recovery, and `SYNC_BEHIND`.

### Transport and recovery

The coordinator emits bounded GUILD `LEDGER_DIGEST` hints only after its local
commit has persisted. A follower accepts V2 ledger digests only from the active
coordinator, fetches the next exact `AWARD_COMMIT` by WHISPER, and applies
details only through `Ledger.ApplyAwardCommit` after sender, epoch, sequence,
root, hash, and B03 invariant validation.

The digest target is retained while a follower is behind. After one verified
commit, SyncV2 fetches the next missing sequence and clears `SYNC_BEHIND` only
when the advertised final sequence and root are both reached. Delayed or
duplicate detail is idempotent; an incompatible branch remains fenced as a
conflict rather than being selected automatically. Only the active coordinator
serves award-commit detail.

### Persistence and compatibility

The additive `ledger.canonical` SavedVariables subtree stores the current
epoch, next sequence, root hash, commits, positions, and transaction index.
Malformed canonical state is quarantined through the existing recovery path.
Legacy B03 ledger/history records, B05a baseline evidence, Pre-Dibs, guild
policy, and RCLootCouncil data are not rewritten. GUID remains witness metadata;
Name-Realm remains the canonical player identity.

## Validation

Focused B06/B03/B04/B05b validation after the final synchronization correction:

```text
30 passed, 0 failed (4 files)
```

The B06 integration coverage exercises: explicit V2 state, active coordinator
commit, non-coordinator zero-effect proposal, deterministic identifier
requirement, duplicate commit idempotency, exact gap rejection, root conflict,
atomic follower application, balance serialization of competing requests,
local bypass fencing, and normal handoff fencing of the old coordinator.

Targeted B00-B05b regression selection completed successfully:

```text
69 passed, 0 failed (8 files)
```

The complete suite was then run against the final B06 state:

```text
300 passed, 1 failed (63 files)
FAIL RCLootCouncil DIB response projection /
  renders the voting Dibs value from a normalized RCLootCouncil row identity
tests/integration/rclootcouncil_buttons_spec.lua:155: expected 2/2, got 1/1
```

This is the known B05a baseline RCLootCouncil projection failure. It is
unchanged and was not introduced by B06; no RCLootCouncil source file is in the
B06 result commit.

## Known limitations and intentional exclusions

- Transport hashes and roster validation provide integrity/attribution signals,
  not cryptographic signatures.
- Award commits are exposed only through the new ledger/synchronization path;
  B06 does not wire production RCLootCouncil award callbacks to
  `AWARD_COMMIT`.
- B07 and later work is not implemented. In particular, no additional
  reconciliation UI, RCLootCouncil behavior, policy feature, or unrelated
  refactor is included.
