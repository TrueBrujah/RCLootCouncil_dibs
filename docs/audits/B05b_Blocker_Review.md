# B05b Blocker Review

## Scope and current state

This is a read-only review of the current B05b working tree. It does not
continue B05b and does not modify production code.

- Branch: `dev`
- HEAD: `ccf33c2aec73ea525e5918825fa0f3584456fa70`
  (`docs(audit): record B05a implementation evidence`)
- Current B05b source/test diff: none.
- Pre-existing unrelated working-tree changes preserved and excluded from this
  review: `docs/RC_OPTIONS.md` and `RCLootCouncil_dibs.code-workspace`.

The completed implementation immediately preceding B05b is B05a:
`dc20093f77455feee3032630c8043b2a0bb2b0d7`, with its implementation evidence
recorded by the current HEAD. B05a provides a GM-finalized, audited legacy
baseline. It intentionally does not activate coordinator authority, epochs,
handoff, or distributed commits.

No B05b implementation file, B05b-focused test, checkpoint, or uncommitted
B05b diff is present. Consequently, no B05b work can be credited as completed
in the current tree.

## Comparison with the approved architecture

The following sources agree on the intended boundary:

- `P1_Architecture_Decision_Record.md` ADR-001, ADR-003, and ADR-004 require
  a fail-closed coordinator state machine. In `COORDINATOR_UNAVAILABLE` or
  `RECOVERY_PENDING`, no canonical Dib use, reservation, or debit is allowed;
  an attributable proposal may be retained for reconciliation.
- `P1_Remediation_Plan.md` assigns that state machine, normal closure,
  forced-recovery baseline binding, orphaned late evidence, and partition
  tests to B05b. It reserves actual distributed `AWARD_COMMIT` activation,
  sequence/hash-chain enforcement, and ledger-detail transport for B06.
- `P1_Architecture_Challenge.md` confirms this split is deliberate. An epoch
  number alone cannot fence a partitioned predecessor. B05b must therefore
  prevent a replacement writer until closure or GM-approved baseline recovery;
  B06 later activates canonical distributed commits.
- `B05a_Implementation_Evidence.md` records that the B05a baseline is a
  prerequisite for B05b recovery, not a substitute for B05b authority state.

The approved architecture is therefore sufficient for B05b. The current
blockage is not an architecture contradiction and does not require B06 to be
started early.

## Completed B05b work

None. The working tree contains B05a baseline work only. B00's coordinator
state-machine fixture is a contract/test model and is not production B05b
implementation.

## Blockers

### B05B-BLK-001 — No resumable B05b implementation state

- Severity: P1
- Type: DEPENDENCY MISSING / OTHER (resume-state dependency)
- Exact files: none; no B05b file or test diff exists.
- Function/module: not applicable.
- Current behavior: the branch ends at B05a evidence. Git shows no B05b
  production or test changes to inspect, repair, or complete.
- Required B05b behavior: implement the approved authority/recovery state
  machine and its focused tests, beginning from the B05a result state.
- Why work cannot safely proceed as a *resume*: there is no interrupted B05b
  implementation to distinguish from unstarted work. Treating B05a changes or
  the B00 test fixture as partial B05b would incorrectly broaden or duplicate
  scope.
- Resolution classification: **E — another dependency**. The missing item is
  a resumable B05b checkpoint/diff, not a technical runtime dependency.
- Resolution scope: can be resolved entirely inside approved B05b scope by
  starting B05b from the present B05a base using the canonical documents; it
  does not need an ADR change or B06.

This explains the prior `BLOCKED` result: the request was framed as a resume,
but the current repository has no B05b state to resume.

### B05B-BLK-002 — Governance deliberately rejects B05b authority state

- Severity: P1
- Type: IMPLEMENTATION ISSUE
- Exact files: `src/modules/Governance.lua:94-116`;
  `src/Core.lua:191,463-469`.
- Function/module: `Governance:NormalizeState`,
  `Governance:ValidateProposal` (via `inactiveFuture`), and Core SavedVariables
  validation.
- Current behavior: persisted `future.coordinator`, `future.ledgerEpoch`, and
  `future.baseline` are cleared or rejected. Any protocol other than
  `LEGACY_LOCAL` is rejected. Core validation quarantines future governance
  state. These are intentional B02a/B03/B04 safety fences.
- Required B05b behavior: add a validated, GM-governed authority transition
  model with `ACTIVE`, `HANDOFF_CLOSING`, `COORDINATOR_UNAVAILABLE`, and
  `RECOVERY_PENDING`; a normal successor must bind to its predecessor's exact
  closure tuple, while forced recovery must bind to the B05a baseline.
- Why the current implementation cannot safely proceed: no durable,
  authoritative state can express an approved closure, recovery pending, or a
  fenced successor. Removing the fence without the complete transition
  validation would permit exactly the premature takeover/split-brain case the
  ADRs prohibit.
- Resolution classification: **A — entirely inside approved B05b scope**.

### B05B-BLK-003 — Existing Dib commit path remains local and cannot fail closed

- Severity: P1
- Type: IMPLEMENTATION ISSUE
- Exact files: `src/modules/Ledger.lua:242-271`.
- Function/module: `Ledger:CommitLocalTransaction` and `Ledger:CommitDibUse`.
- Current behavior: `CommitDibUse` immediately delegates to the durable local
  transaction path. Its documented context is never a coordinator or epoch.
  There is no gate for `COORDINATOR_UNAVAILABLE` or `RECOVERY_PENDING`, and no
  proposal-only result.
- Required B05b behavior: when coordinator authority is unavailable or
  recovering, reject canonical Dib use/reservation/debit with an explicit
  unavailable/recovery result and retain only an attributable
  `AWARD_PROPOSAL`/pending-reconciliation record if the workflow needs one.
- Why the current implementation cannot safely proceed: in a partitioned
  two-raid scenario, a client could locally debit a Dib while another side is
  attempting recovery. Since neither write is fenced by a shared authority
  state, the later reconciliation cannot truthfully claim that only one
  canonical decision occurred.
- Resolution classification: **A — entirely inside approved B05b scope**.
  B05b must add the fail-closed gate and proposal path only. It must not add
  B06's active distributed `AWARD_COMMIT` semantics.

### B05B-BLK-004 — No bounded handoff/recovery transport exists

- Severity: P1
- Type: IMPLEMENTATION ISSUE
- Exact files: `src/modules/SyncV2.lua:123-125,166-168,197-205`;
  `src/modules/LegacyBaseline.lua:432-457,504-544`.
- Function/module: `SyncV2:SetProtocolState`, `SyncV2:BuildLedgerDigest`,
  SyncV2 message validation, `LegacyBaseline:FinalizeBaseline`, and recovery
  package staging/commit.
- Current behavior: SyncV2 refuses `V2_ENFORCED`, sends only a `LOCAL_ONLY`
  digest, and explicitly rejects ledger sequence/hash detail. B05a can create
  and receive a reviewed legacy baseline, but it stores that baseline locally
  and does not bind it to a coordinator transition.
- Required B05b behavior: transport and validate only the bounded governance
  evidence needed for closure, recovery-pending, GM-approved transition, and
  orphaned late evidence. It must remain distinct from B06 ledger-detail and
  `AWARD_COMMIT` transport.
- Why the current implementation cannot safely proceed: a successor cannot
  prove it follows a particular closure tuple or GM-approved baseline, and a
  late predecessor event has no authority-era context in which to be retained
  as non-canonical evidence.
- Resolution classification: **A — entirely inside approved B05b scope**.

### B05B-BLK-005 — B05b behavior has no production-focused test coverage

- Severity: P1
- Type: TEST/HARNESS ISSUE
- Exact files: no B05b test file exists. Related test-only model:
  `tests/contract/b00_architecture_contract_spec.lua`.
- Function/module: B00's fixture state machine is a contract artifact, not a
  binding to production `Governance`, `Ledger`, and `SyncV2` modules.
- Current behavior: the fixture demonstrates expected outcomes, but no test
  can fail if production incorrectly permits a local debit during recovery,
  accepts a stale predecessor, or mishandles a forced recovery baseline.
- Required B05b behavior: focused production tests for normal closure,
  late old-epoch evidence, reconnect, missing closure, partitioned raids,
  forced recovery, proposal-without-debit, and GM-only takeover.
- Why the current implementation cannot safely proceed: the most important
  B05b safety rule is behavioral across modules. A standalone fixture cannot
  establish that the actual Dib path is fenced.
- Resolution classification: **D — correct the test/fixture assumption** by
  adding B05b production-focused tests within B05b; the existing harness does
  not need a redesign.

## Architecture failure scenario and disposition

Consider the challenge scenario: Raid A's coordinator owns the current
authority epoch. Raid B is active but partitioned. Raid A's coordinator
disconnects, an officer in Raid B attempts takeover, and the prior coordinator
later reconnects while messages from the previous epoch arrive late.

The current code has no coordinator epoch at all, so `Ledger:CommitDibUse`
cannot tell that either actor is no longer safe to make a canonical Dib
decision. A naïve B05b change that simply lets the officer choose a larger
epoch would create two locally durable decisions during the partition.

The preferred correction is already approved: B05b first records
`COORDINATOR_UNAVAILABLE`, then requires either (1) the predecessor's exact
normal closure tuple or (2) a current-roster-GM-approved B05a recovery
baseline before authority can move. While recovery is pending, Dib use is
fail-closed and only proposals are retained. Delayed prior-authority messages
are stored, if needed, as orphaned review evidence and never auto-append to
the canonical ledger.

Alternatives rejected:

- Immediate GM/officer promotion after a timeout: cannot distinguish a network
  partition from coordinator loss and permits split-brain.
- Higher epoch alone: an integer cannot prove the prior authority stopped
  writing.
- Treating B05a's `RECOVERY_PENDING_REVIEW` receipt status as the B05b
  authority state: it describes receipt review, not durable writer fencing.
- Implementing B06 early: would enlarge the problem with active distributed
  commits before B05b establishes safe authority transitions.

The preferred correction affects B05b only. B06 remains responsible for
canonical distributed commit activation, strict per-epoch sequence/hash-chain
validation, and ledger-detail synchronization.

## Migration and compatibility

No architecture-document or ADR change is required. The current documents
already require the preferred correction.

B05b implementation must nevertheless preserve these constraints:

- SavedVariables migration is additive; no automatic epoch/coordinator must
  be inferred from legacy state.
- Existing ledger/history remains immutable evidence. Excluded late events are
  reviewable orphaned evidence, not rewritten canonical entries.
- Existing `LEGACY_LOCAL` clients remain local-only and must not be silently
  treated as authority-capable.
- B05a `legacyBaseline` remains a prerequisite reference; its stored data must
  not be mistaken for a live coordinator lease.
- Existing Pre-Dibs, guild policy, multi-raid workflows, and RCLootCouncil
  behavior must keep their legacy behavior until an explicit, validated B05b
  governance transition permits the new safety state.
- The state/transport work must remain combat-safe and avoid protected WoW API
  actions; it changes validation and persisted data, not protected UI actions.

## Safety of the partial working tree

There is no partial B05b code to remove, repair, or preserve. The existing
B05a code is internally consistent with its documented boundary and should
remain in place. In particular, the B05a receipt status
`RECOVERY_PENDING_REVIEW` is not unsafe, but B05b must avoid conflating it
with the authority state named `RECOVERY_PENDING`.

## Conclusion

The earlier block was caused by the absence of any resumable B05b state, not
by an approved-architecture gap, a B06 dependency, or a WoW API limitation.
All technical work identified above belongs to the already approved B05b
boundary. B05b can be started from the B05a result commit when implementation
is authorized, without modifying the ADR/remediation documents first.

B05b BLOCKER IS IMPLEMENTATION-LOCAL
