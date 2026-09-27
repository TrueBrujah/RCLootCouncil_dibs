# Rank Allocation Reconciliation Implementation

- Date: 2026-09-25
- Version family: 0.8.x
- Decision: **READY FOR RETAIL TEST**

## Scope and Decision

This implementation adds a current-roster Automatic Dibs reconciliation flow
for published seasonal Rank Rules. It implements the positive-only manual
policy from the Rank Rules and Guild Policy/Dibs Reconciliation architecture
audits. It does not introduce the future Guild Policy Framework or expand
OperationalPolicy ownership.

`READY FOR RETAIL TEST` means the focused behavior gates and implementation
checks pass and the feature can proceed to the disposable-guild Retail test
matrix below. It is not a claim of Retail certification. The complete Fengari
run has one known, unrelated Pre-Dib timer-count failure documented in the
repository's test baseline.

## Implemented Workflow

- Automatic Dibs projects current, unambiguous roster members against the
  selected season's published catalog rule and assigned allocation. It no
  longer treats historical allocation events as current-state rows.
- Positive differences require an explicit Reconcile action and a nonblank
  reason. A successful write is one canonical `SEASON_ALLOCATION` transaction;
  it is not `ledger.adjust` and changes assigned allocation rather than
  rewriting history.
- Non-coordinator actions are recorded as `AWARD_PROPOSAL` and shown as pending.
  The coordinator re-resolves the target and requester and validates season,
  rank, expected/assigned values, catalog revision/hash, governance and policy
  revisions, epoch, coordinator identity, and operation key before commit.
- Reconciliation basis is included in the proposal/transaction content covered
  by canonical hashes. Repeated operation keys reuse the proposal; canonical
  commit replay is idempotent.
- A negative difference is informational. Previously assigned Dibs remain
  granted even if spent; no clawback, negative adjustment, or debt is created.
- Reconcile All processes rows independently and reports successful, pending,
  stale, skipped, and failed outcomes. It is not an atomic batch.
- Guided Setup presents Rank Rules and Allocation Reconciliation as separate
  steps. The latter opens Automatic Dibs. Rank Rules status describes the
  published rule configuration, not member allocation differences.
- The legacy Assignments surface remains available and routes through the
  protected reconciliation service with a required reason.
- Sync compatibility is fenced to the 0.8.x family so older peers fail closed
  before they apply the reconciliation contract.

## Safety Matrix

| Condition | Result |
|---|---|
| Positive difference; fresh snapshot; local coordinator | One canonical positive `SEASON_ALLOCATION` commit |
| Positive difference; authorized remote officer | Pending proposal until coordinator validation and commit |
| Changed preview, rank, assignment, season, or catalog | Reject as stale; no stale top-up |
| Requester is no longer a guild GM/Officer | Reject proposal at coordinator |
| Zero difference | Ready/aligned; no write |
| Negative difference or demotion | Keep granted; no write, clawback, adjustment, or debt |
| Missing reason, invalid target/delta, unavailable coordinator, V2 not enforced, or sync behind | Fail closed |
| Reconcile All has mixed outcomes | Continue independent rows and report each result; do not claim atomic success |
| Incompatible pre-0.8.x peer | Reject before applying synchronized payload |

## Verification

- `rank_reconciliation_workflow_spec.lua`: **27 passed**. Covers signed delta,
  reason enforcement, exact positive commit, stale preview and coordinator
  checks, remote-officer role revalidation, proposal idempotency, audit hashing,
  spent-Dib demotion, sync/V2 fail-closed behavior, and partial bulk outcomes.
- `guided_setup_wizard_spec.lua`: **21 passed**, including status separation and
  navigation from Allocation Reconciliation to Automatic Dibs.
- `automatic_dibs_log_spec.lua`: **8 passed**, including current-state-only
  roster projection and preserved legacy administration behavior.
- Complete Fengari suite: **730 passed, 1 failed (144 files)**. The remaining
  failure is `tests/integration/predibs_sync_recovery_spec.lua:50`, where one
  bounded heartbeat expects one scheduled timer but observes two. This is the
  pre-existing timer-count baseline and is outside rank reconciliation.
- Source-driven documentation validation: **27 concepts, 0 errors, 0 warnings,
  0 missing locale values, 0 duplicate IDs**. Generated outputs were refreshed.
- Focused earlier slices for rank reconciliation, award relay, B06 ledger,
  synchronization, protected actions, and legacy Assignments also passed.

No live Retail client or two-client guild session was available in this
workspace. The feature is not Retail-certified.

## Retail Test Gate

Use a disposable guild/season and verify:

1. Current roster, rank, published catalog, and assigned allocation agree with
   the Automatic Dibs rows; historical entries remain in History.
2. Positive top-up requires a reason and yields exactly one canonical commit;
   a remote officer sees pending until the coordinator commits.
3. Change rank, rule, active season, or assigned allocation after preview and
   verify the old confirmation cannot commit.
4. Demote a member who has both unused and spent Dibs; verify the allocation is
   retained and no debt or negative transaction appears.
5. Run Reconcile All with aligned, positive, stale, and unavailable rows; verify
   the per-row report and that successful rows are not rolled back.
6. Verify an older peer is reported incompatible and cannot apply reconciliation
   proposal/commit data.
7. Confirm the Rank Rules page reports catalog state, not a generic
   OperationalPolicy banner, and the legacy Assignments reason/action still
   reaches the same protected service.

## Follow-up Boundaries

Keep the legacy Assignments option until Retail confirms parity and the
compatibility surface has no remaining callers. Its assignment log duplicates
the current Automatic Dibs projection; after adoption, retire that log and
bulk action together rather than maintaining a second writer. Rank Rules remain
owned by the season catalog. Any future Guild Policy Framework must define an
explicit migration/authority boundary before it can own rank allocation.