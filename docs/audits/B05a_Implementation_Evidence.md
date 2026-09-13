# B05a Implementation Evidence

## Git record

- Branch: `dev`
- `B05A_START_COMMIT`: `1517f09491381bdbc8b0e3d35a43d5fd75cc29aa`
- `B05A_CHECKPOINT_COMMIT`: `1517f09491381bdbc8b0e3d35a43d5fd75cc29aa`
- `B05A_RESULT_COMMIT`: `dc20093f77455feee3032630c8043b2a0bb2b0d7`

The checkpoint is the safe committed source state before B05a. The modified
`docs/RC_OPTIONS.md` and untracked `RCLootCouncil_dibs.code-workspace` were
preserved, never staged, and excluded from the result commit.

## Files changed

- `src/modules/LegacyBaseline.lua`: reconciliation, baseline, recovery staging,
  and recovery-review service.
- `src/Core.lua`: additive `legacyBaseline` persistence subtree and validation.
- `src/modules/SyncV2.lua`: bounded WHISPER-only recovery package staging.
- `src/modules/ImportExport.lua`: classifies full legacy packages as
  `LEGACY_DIAGNOSTIC_ONLY`, not authoritative recovery.
- TOC/test loader and `tests/integration/legacy_baseline_recovery_spec.lua`.

No RCLootCouncil source, coordinator transition, ledger epoch, `AWARD_COMMIT`,
canonical distributed ledger write, or automatic award behavior was changed.

## Evidence and normalization model

`db.legacyBaseline` is an additive schema-1 subtree with bounded source,
evidence, finding, decision, recovery, and audit collections. Evidence retains
an immutable source-record copy alongside source/client/type/version/provenance,
original transaction or request ID, original identity, action/amount/season,
timestamp when present, source-record hash, and deterministic comparison hashes.

Only Dibs-owned ledger, Pre-Dib, migration/history, and Dibs reconciliation
sources are accepted. `CollectLocalEvidence` explicitly excludes RCLootCouncil
history. Source records are evidence only: no legacy transaction ID, value,
player-name evidence, Pre-Dib, season, timestamp, or metadata is rewritten,
resequenced, merged, or deleted.

The service reuses B03/B04 `SyncV2.CalculateContentHash` canonicalization. It
detects exact duplicates, same-ID content conflicts, identity conflicts, likely
same-award/different-ID duplicates, peer-only records, and unresolved identity.
Full Name-Realm is used when deterministically present; short/missing identities
remain unresolved and are never silently attributed from a short name or GUID.
No first client, GM client, newest/largest history, or automatic union is chosen
as canonical.

## Reconciliation and baseline

Each evidence entry needs an explicit active `INCLUDE`, `EXCLUDE`,
`COMPENSATING_ADJUSTMENT`, or blocking `DEFER` decision before baseline preview
or finalization. Decisions contain evidence/hash, actor snapshot, reason,
timestamp, adjustment, and explicit supersession. A replacement requires the
previous decision ID; there is no hidden last-write-wins behavior.

Officers/GM may record attributable reconciliation work. Finalization requires
already-adopted B02a governance, a fresh local current-GM roster check, and an
explicit GM acknowledgement if any evidence source is marked incomplete. Local
settings/rank SavedVariables do not establish authority.

The deterministic baseline projection contains schema, guild scope, sorted source
summary, included/excluded evidence, adjustments, active decisions,
per-player/per-season effects, unresolved effects, and historical Pre-Dib
reconfirmation markers. Volatile approval metadata is outside its hash. Equal
evidence and decisions produce the same `legacyBaselineHash` regardless of
source order; every decision change changes it. Historical active-looking
Pre-Dibs are marked `HISTORICAL_RECONFIRMATION_REQUIRED` and never revived.

## Staged recovery and transport

The authoritative B05a package is schema-1 `LEGACY_RECOVERY_PACKAGE`: guild
scope, source/author provenance, expected context, recovery/baseline relation,
complete evidence sources, audit metadata, and canonical content hash are
required. `StageRecoveryPackage` fully validates and normalizes into detached
state with no persistent mutation. `CommitRecoveryPackage` revalidates, creates
a B01 guild safety backup, then atomically replaces only `db.legacyBaseline`.
It never writes `db.ledger` or `db.preDibs`; repeat packages are idempotent.

`Sync.SendLegacyRecoveryPackage` uses B04's bounded WHISPER transfer. Receipt is
fully hash-checked then stored only as bounded runtime
`RECOVERY_PENDING_REVIEW` evidence. It requires an explicit local assistant
commit afterwards. Recovery audits distinguish `MANUAL_LOCAL_IMPORT` from
`REMOTE_B04_WHISPER`, preserving sender, actor, package hash, provenance, and
safety backup. Existing ImportExport full packages remain compatibility imports
but are visibly diagnostic-only, never the B05a recovery schema.

## Validation

Focused B05a test:

```powershell
$env:DIBS_TEST_FILES = 'tests/integration/legacy_baseline_recovery_spec.lua'
.\node_modules\.bin\fengari.cmd tests/run.lua
```

Result: **10 passed, 0 failed**. Coverage includes duplicate/divergent history,
identity ambiguity, all decision types, reproducible hashes, GM approval,
Pre-Dib preservation, staged recovery rollback/idempotency, and B04 receipt
staging.

Targeted B00-B04/B02b regression selection: **73 passed, 0 failed**.
After the final provenance-only receipt-metadata addition, the B05a/B01/B02b/
B03/B04 focused selection reported **46 passed, 0 failed**.

The full suite was executed once during final B05a validation: **287 passed,
1 failed (61 files)**. Its sole failure is the documented, unchanged
RCLootCouncil projection baseline:

```text
FAIL RCLootCouncil DIB response projection / renders the voting Dibs value from a normalized RCLootCouncil row identity
tests/integration/rclootcouncil_buttons_spec.lua:155: expected 2/2, got 1/1
```

This is outside B05a and no new failure was introduced.

## Deferred scope

B05b fenced handoff/recovery state transitions, coordinator activation/takeover,
orphan handling, B06 epochs/sequences/hash chains/canonical `AWARD_COMMIT`,
`V2_ENFORCED`, and all RCLootCouncil adapter behavior remain unimplemented.
The approved baseline is not bound into governance and cannot activate protocol
or coordinator behavior by itself. WoW roster/sender validation remains
attribution, not cryptographic proof of client truth.
