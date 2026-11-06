# Quickstart: Validating RF-0012 Design

This guide is for the future implementation and its review. It provides validation scenarios; it does not implement or certify the feature.

## Prerequisites

- Work from repository root on the implementation branch.
- Keep each simulated client's SavedVariables independent.
- Use only synthetic guild, player, dispute, transaction, and evidence fixtures.
- Ensure the test loader executes the production Ledger and SyncV2 dispatch/receiver code in isolated Lua environments and cannot write production accounting. A scenario-only distributed fixture is not sufficient.
- Never edit any directory named `libs`.
- Keep the release activation flag disabled by default. Test opt-in must be fixture-scoped, never a production SavedVariables or user setting.
- Read [the operation contract](./contracts/ledger-operation-v1.md), [the SyncV2 contract](./contracts/syncv2-ledger-operation-commit.md), and [the test traceability matrix](./traceability.md).

## Focused deterministic validation

When the implementation test files exist, run the focused operation and sync scenarios together from PowerShell:

```powershell
$previousTestFiles = $env:DIBS_TEST_FILES
try {
    $env:DIBS_TEST_FILES = 'tests\unit\ledger_operation_spec.lua;tests\integration\canonical_dispute_operation_spec.lua;tests\integration\canonical_dispute_sync_spec.lua;tests\integration\dispute_center_spec.lua'
    npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua
    if ($LASTEXITCODE -ne 0) { throw "Fengari failed (exit $LASTEXITCODE)." }
} finally {
    $env:DIBS_TEST_FILES = $previousTestFiles
}
git diff --check
```

At planning time, the new operation and SyncV2 test files do not exist, so this exact focused command is a future validation recipe, not a current passing test. Before the code work, capture the existing relevant suite baseline using currently present test paths.

## Required scenarios and observable assertions

### 1. Logical operation/idempotency

1. Create a synthetic dispute linked to a verified original transaction.
2. Submit a valid one-leg correction and a valid two-member target transfer through the real protected/coordinator operation path.
3. Re-submit the identical operation and then reuse its ID with a changed payload/hash.
4. Deliver/retry the accepted operation exactly 100 times; where supported, reinitialize the client from a saved snapshot before a retry.
5. Inject validation failure into each leg in turn.

**Expected**: one canonical sequence per accepted operation; all valid legs appear exactly once with stable transaction IDs; the 100 retries preserve the same operation/entry IDs and leave one commit, the same balances, and the same sequence; conflicting payload is rejected; a failed leg leaves every accounting projection unchanged.

### 2. Ledger selection and evidence

Create separate approved ledgers, put the source transaction in one, and select the other as active/view ledger. Also test missing, foreign, archived, unapproved, and ambiguous original references.

**Expected**: a valid correction is attached only to the ledger containing the verified original; all invalid source cases fail without mutation; no active-ledger fallback occurs.

### 3. Protected authority, proposal and revision

Run as GM, Officer coordinator, Officer non-coordinator, non-Officer, stale proposer, and unknown sender. Create an unresolved proposal, change the dispute revision, and retry it.

**Expected**: all mutations go through `ProtectedActions`; the non-coordinator changes no balance; proposal IDs/payload survive retries; the coordinator revalidates current authority and revision; stale or unauthorized attempts return explicit failures.

### 4. Distributed ordering and compatibility

Run coordinator and at least two followers with independent SavedVariables and independently loaded production modules. Relay a typed `LEDGER_OPERATION_PROPOSAL` and its explicit acknowledgment, then verify the initial complete `LEDGER_OPERATION_COMMIT` announcement and updated `LEDGER_DIGEST`. Deliver a duplicate, an out-of-order sequence, a wrong previous hash, an old epoch, a wrong-ledger record, an incompatible record, and a missing sequence followed by catch-up. Include a temporarily offline member.

**Expected**: production allowlist/dispatch/receiver code handles the messages; all compatible online members converge to matching operation IDs, entry IDs, balances, epochs, sequences and roots; duplicate is a no-op; gap does not apply early; invalid/incompatible commit has zero accounting effect; offline compatible member catches up in order after reconnect.

### 5. Fault injection and reload recovery

Capture separate client snapshots after: before acceptance; canonical record acceptance; each transaction projection; transaction index; balance rebuild; dispute-status projection; and before a later reload. Reinitialize the addon independently from each snapshot.

**Expected**: pre-acceptance failure has no accounting effect; accepted journal with partial projections rebuilds deterministically without a second commit; invalid chains and irreconcilable ID conflicts surface explicit unrecoverable states; no automatic compensation is created. A later reload verifies retained state but no runtime claims to force disk flush.

### 6. Historical data and backup/import

Use synthetic mixed histories of legacy local transactions, old `AWARD_COMMIT` records, new operation commits, and complete, partial, ambiguous, local-only and unverifiable corrections; old backup without operations; valid new backup; duplicate restore; conflicting sequence/root; and import package containing an unseen operation. Calculate expected balances independently from explicit fixture allocations plus uniquely sourced accepted effects.

**Expected**: read-only report classifies evidence without changing the snapshot; old transaction content and `correctionKey` remain identical; each accepted canonical or legacy-local source contributes once; commit-backed transaction rows are not counted twice; results match the independent oracle; conflicting/unassignable history is rejected or quarantined; unseen operation is not directly appended by import.

### 7. Activation and per-phase integrity gate

Exercise the runtime gate with the release flag disabled, local recovery incomplete,
an unknown coordinator, an unsupported online peer, an invalid chain root, and
then with all supported runtime conditions satisfied. Test direct/protected
submission, coordinator acceptance, capability advertisement, and receiving
paths separately.

**Expected**: the disabled or not-ready gate returns a specific blocked result
with zero journal, balance, transaction, index, sequence, root, or dispute
effects; no path falls back to local writes. Once the release flag is enabled
after the external release evidence is recorded, every entry point enforces
the same readiness conditions. Lua does not claim to know whether CI or Retail
validation occurred.

Before and after every implementation phase, run the existing
`python .github/skills/lua-code-audit/scripts/audit_guard.py verify` against
`docs/code-audit/BASELINE.json`. The baseline is read-only: do not run
`capture`/`capture-libraries`, create a temporary `libs` manifest, or
auto-restore a path. Any `PROTÉGÉ` delta blocks the phase. `LUA` differences
must be attributable either to the recorded pre-existing worktree or to the
phase's declared source paths. Preserve pre-existing changes; stop for explicit
integration guidance if a phase touches one. A nonzero guard exit is never
reported as a pass.

## Manual World of Warcraft Retail validation

Fengari proves only the behavior represented by its Lua doubles. Before release, record a separate Retail multi-client validation using at least one coordinator, one non-coordinator Officer, one compatible follower, and one offline/reconnecting member. Verify actual roster identity/rank, message ordering/limits, independent account SavedVariables, reload recovery, visible error states, and addon startup behavior. Do not report Retail certification until that record exists.
