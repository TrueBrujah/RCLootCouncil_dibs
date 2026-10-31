# Feature Specification: Canonical Idempotent Dispute Corrections

**Feature Branch**: `026-canonical-idempotent-corrections`

**Created**: 2026-10-18

**Status**: Draft

**Priority**: P0 — DATA_INTEGRITY

**Input**: User requirements for RF-0012, based on the [RF-0012 assessment](../../.specify/bugs/rf-0012-ledger-integrity/assessment.md)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Apply one complete, auditable correction (Priority: P1)

As a verified Guild Master or Officer, I want a balance correction to be one
validated operation tied to its original transaction and ledger, so that an
error or retry cannot leave only one side of a transfer applied or change the
wrong ledger.

**Why this priority**: A partial or repeated correction can change balances
incorrectly and undermine trust in the append-only accounting history.

**Independent Test**: Resolve a dispute using a coordinator-authorized
correction, then compare the operation, every signed entry, the original
transaction, the balances, the dispute state, and the canonical ledger history.
Repeat with an invalid leg and verify that no accounting or resolution state
changes.

**Acceptance Scenarios**:

1. **Given** a verified GM or Officer, an approved ledger, and a verifiable
   original transaction, **when** the correction is accepted, **then** one
   canonical operation contains every validated entry, has stable identifiers,
   and produces the complete intended balance change without modifying the
   original transaction.
2. **Given** one entry is invalid, the original transaction cannot be verified,
   or the required ledger is missing or not approved, **when** the correction
   is submitted, **then** the entire correction is rejected with a specific
   reason and no balance, transaction, sequence, hash, or resolved-dispute
   change.
3. **Given** an authorized Officer is not the current coordinator, **when**
   they request a correction, **then** the request follows the existing
   authorized proposal path with the same operation identity and causes no
   local balance change before canonical acceptance.
4. **Given** a correction changes attribution only and no balance, **when**
   the Officer resolves it, **then** it is represented as an explicitly
   non-accounting resolution and is not reported as a ledger correction.

### User Story 2 - Synchronize and safely replay corrections (Priority: P1)

As a guild member, I want to receive the same accepted correction from the
verified coordinator and catch up after being offline, so that guild members
do not maintain different balances or apply a correction twice.

**Why this priority**: A local-only correction can make one member's ledger
diverge from the authoritative guild history.

**Independent Test**: Use separate SavedVariables states for a coordinator and
two members. Deliver a correction, duplicate it, interrupt one member before
projection completion, and reconnect that member after a sequence gap. Compare
the accepted operation IDs, transaction IDs, balances, epoch, sequence, and
canonical hashes.

**Acceptance Scenarios**:

1. **Given** a compatible coordinator and compatible online members, **when**
   the coordinator accepts a correction, **then** one canonical commit carries
   the complete operation and all receivers validate it before applying it.
2. **Given** an exact duplicate of an accepted operation, **when** it is
   delivered again or retried after reload, **then** it has no additional
   accounting effect and does not create another canonical sequence entry.
3. **Given** an operation ID already exists with different content, **when**
   the conflicting operation is proposed or received, **then** it is rejected
   without mutation and an explicit conflict is reported.
4. **Given** a member is offline or has missed a sequence, **when** it later
   reconnects with a compatible client and a valid coordinator source is
   available, **then** it fetches and validates the missing commits in order
   before reporting itself current.
5. **Given** a sender, epoch, sequence, previous hash, ledger, protocol
   capability, or payload is invalid, **when** a commit is received, **then**
   it is rejected and no part of its entries is applied.

### User Story 3 - Recover projections and inspect legacy corrections (Priority: P2)

As a guild administrator, I want accepted operations to be recoverable and
older correction records to be reviewable without automatic repair, so that a
restart or a historical inconsistency does not hide or compound an accounting
problem.

**Why this priority**: Recovery must derive balances from accepted history,
while old partial corrections cannot safely be interpreted as complete
operations.

**Independent Test**: Interrupt projection creation after a canonical
operation has been accepted, restart from its SavedVariables snapshot, and
rebuild balances and indexes. Separately run a read-only report against
complete, partial, ambiguous, and local-only historical correction fixtures;
verify that none of the original records change.

**Acceptance Scenarios**:

1. **Given** a canonical operation is recorded but one or more projections are
   incomplete, **when** recovery runs, **then** the projections are rebuilt
   idempotently from accepted canonical history and no new accounting commit
   is created.
2. **Given** the operation index or a balance projection disagrees with
   accepted history, **when** consistency is checked, **then** the inconsistency
   is diagnosed and either reconstructed from validated history or left
   explicitly unrecovered; no compensation is guessed.
3. **Given** pre-feature correction records lack a verifiable operation,
   **when** the historical report is generated, **then** the records are
   classified for review without changing balances, transactions, dispute
   history, or canonical sequence.
4. **Given** a historical case is approved for repair, **when** the repair is
   later performed, **then** it is a new, separately authorized, auditable
   operation and does not rewrite the historical transactions.

### User Story 4 - Restore without applying an operation twice (Priority: P2)

As a GM or Officer, I want existing and new backups to remain usable, so that
restoring a ledger preserves its history and cannot repeat a correction's
balance effect.

**Why this priority**: A restore that treats both canonical operations and
their derived transactions as new accounting input could duplicate a
correction.

**Independent Test**: Export a ledger with both legacy transactions and
canonical corrections; restore it twice into independent fixtures and once
over a fixture that already contains one operation. Compare historical IDs,
operation hashes, balances, and restore diagnostics.

**Acceptance Scenarios**:

1. **Given** a backup contains a canonical operation already present with the
   same operation ID and payload hash, **when** it is restored or imported
   again, **then** the operation is recognized as the same accepted operation
   and its effect is not repeated.
2. **Given** a backup reuses an operation ID with a different payload hash,
   **when** it is previewed or restored, **then** it is reported as a conflict
   and no conflicting operation is applied.
3. **Given** a legacy backup contains no canonical operation journal, **when**
   it is restored, **then** all historical data remains available and is not
   silently converted into proof of idempotency.

### Edge Cases

- One entry has an invalid amount, identity, reference, action, or transaction
  ID while the other entries are valid.
- The original transaction exists, but only in a different ledger than the
  ledger named by the correction.
- The local UI's selected ledger changes between proposal and acceptance.
- The required ledger is unknown, archived, unapproved, or belongs to another
  guild namespace.
- A correction has no verifiable original transaction, request, or required
  evidence reference.
- The same operation ID is submitted with the same hash, with a different
  hash, or with a different ledger ID.
- Two authorized Officers propose conflicting resolutions for the same
  dispute revision.
- A coordinator changes or its epoch changes while a correction is pending.
- A commit is duplicated, delayed, received out of order, or received after a
  sequence gap or branch conflict.
- A receiver has an older operation schema or does not advertise the required
  protocol capability.
- A member is offline during the commit, then reconnects while the coordinator
  is unavailable or has advanced to a new valid epoch.
- The canonical operation is present but a transaction projection, balance,
  operation index, or dispute resolution projection is incomplete.
- A failure occurs before canonical acceptance, after canonical acceptance,
  or while projections are being reconstructed.
- A WoW session ends before SavedVariables are confirmed by a later reload.
- A backup contains legacy partial corrections, repeated operation records,
  or transactions that are also represented by canonical operations.
- An attribution-only resolution is retried or synchronized; it must never
  create a balance entry.

## Requirements *(mandatory)*

### Functional Requirements

#### Canonical operation and accounting rules

- **FR-001**: Every balance-changing Dispute Center correction MUST be
  represented by one versioned canonical ledger operation. The operation
  record MUST include `operationId`, `operationType`, `ledgerId`, `guildKey`,
  `requestId`, `requestRevision`, `evidenceId`, `originalTransactionId`,
  `actor`, `reason`, `timestamp`, `payloadHash`, `signedEntries`, and
  `schemaVersion`. A field that is not applicable to an explicitly supported
  operation type MUST have an explicit absent value; it MUST NOT be inferred
  from the active UI ledger.
- **FR-002**: `operationType` MUST identify the supported correction semantics,
  including a multi-entry target transfer and each supported balance-changing
  dispute action. Unknown operation types MUST be rejected. A set of entries
  MUST NOT permit an unrecognized action to bypass existing ledger rules.
- **FR-003**: Each signed entry MUST have a stable transaction identifier, an
  explicit ledger association, an affected member, a signed balance change,
  and the applicable action and dispute/original references. All entries
  belonging to one correction MUST share the same `operationId`.
- **FR-004**: For any balance-changing correction, `originalTransactionId`
  MUST identify a verifiable historical transaction in the same guild and
  ledger as the proposed operation. If it is missing, mismatched, or
  unverifiable, the correction MUST fail without mutation.
- **FR-005**: A target transfer MUST validate all of its signed entries as one
  set. For a pure transfer, their net balance change MUST be zero; each
  affected member's change MUST match the approved correction. Other operation
  types MUST obey their explicitly defined ledger semantics.
- **FR-006**: The payload hash MUST be calculated from a canonical,
  deterministic representation of the immutable operation fields and ordered
  entries, excluding the hash value itself. Receivers MUST recompute and
  compare it. The hash MUST be treated as content identity, not as proof of
  actor authority.
- **FR-007**: `operationId` and each entry's transaction ID MUST be created
  once for a correction intent and reused across retries, proposal delivery,
  reload, commit delivery, recovery, and import. An unaccepted proposal MUST
  retain its identity and exact payload for retry. A genuinely new, explicitly
  approved correction MUST use a new operation ID.
- **FR-008**: Operation identity MUST be unique within a guild namespace.
  Reusing an operation ID with a different payload hash, guild, or ledger MUST
  be rejected as a conflict. The identity check MUST include `ledgerId` and
  MUST NOT rely on the locally selected or active ledger.
- **FR-009**: The system MUST validate every entry, reference, authorization,
  ledger scope, and operation-level invariant before accepting any accounting
  effect. A correction MUST be accepted in full or rejected with no partial
  balance or transaction effect.
- **FR-010**: One accepted operation MUST produce one canonical commit in its
  ledger's ordered history. No correction leg may be exposed as a separate
  canonical commit or be applied through a compensation sequence.
- **FR-011**: The canonical operation history MUST be sufficient to reconstruct
  balances, transaction records, operation/transaction indexes, and the
  correction's accounting status. A failed projection update MUST NOT create a
  second canonical operation when retried.
- **FR-012**: Replaying an operation with the same ID and payload hash MUST
  return an idempotent result and MUST NOT change balances, append transaction
  IDs, or advance the canonical sequence again. Replaying the same ID with a
  different payload hash MUST return a conflict and MUST NOT mutate state.
- **FR-013**: Existing `correctionKey` values MUST remain historical metadata
  only. They MUST NOT be treated as proof that a historical correction is
  complete, unique, or safe to replay.
- **FR-014**: If an attribution-only resolution is retained, it MUST use an
  explicitly separate non-accounting resolution type with no signed ledger
  entries. It MUST NOT report a balance change or be represented as a
  successful accounting correction.
- **FR-015**: Accepted canonical operations and the original transactions they
  correct MUST remain append-only. No correction, projection rebuild, backup,
  or import may delete or silently rewrite historical transaction content.
#### Ledger scope, authority, and error handling

- **FR-016**: Every operation MUST be bound to the canonical `guildKey` and
  explicit approved `ledgerId` belonging to that guild. An unknown, archived,
  unapproved, or foreign-guild ledger MUST cause a fail-closed rejection.
- **FR-017**: The ledger containing the verified original transaction MUST
  determine the correction scope. The active ledger, view ledger, and a
  payload's unverified ledger claim MUST NOT replace that scope.
- **FR-018**: Existing GM/Officer authority MUST be revalidated when a
  correction is accepted. A claimed role, raid role, council role, or stale
  permission result MUST NOT grant authority. Receivers MUST verify actual
  sender identity and applicable guild authority.
- **FR-019**: No Dispute Center balance correction may bypass the existing
  protected-action authorization boundary or create a parallel unprotected
  write path. Existing public correction contracts SHOULD remain compatible;
  any required incompatibility MUST be explicitly versioned and documented.
- **FR-020**: The caller and user interface MUST receive the actual validation,
  ledger, permission, coordinator, and commit rejection reason. A compensation
  result MUST NOT mask the original error, and a rejected operation MUST NOT
  be returned as a success-shaped result.

#### Canonical coordination and SyncV2

- **FR-021**: A non-coordinator Officer MUST submit a correction through the
  existing authorized proposal mechanism. The proposal MUST preserve the
  stable proposal ID, operation ID, payload hash, request and revision,
  evidence, ledger, entries, reason, and verified proposer identity. It MUST
  use a distinct typed
  `LEDGER_OPERATION_PROPOSAL` record and a corresponding proposal
  acknowledgment; it MUST NOT be treated as the existing single-award
  `AWARD_PROPOSAL`. Retries MUST retain the same proposal ID and exact payload.
  A receipt acknowledgment MUST NOT be reported as acceptance, and a proposal
  MUST NOT alter balances before coordinator acceptance.
- **FR-022**: The canonical operation wire contract MUST be explicitly
  versioned. The operation schema MUST use `schemaVersion=1`; the SyncV2
  operation-commit capability MUST advertise and validate
  `protocolVersion=1`, independently of the existing general sync envelope.
  Existing `AWARD_COMMIT` records MUST remain readable and unchanged.
- **FR-023**: A complete logical operation MUST be transmitted as one
  `LEDGER_OPERATION_COMMIT` canonical commit containing all entries. The
  commit MUST bind the guild, ledger, current epoch, next sequence, previous
  canonical hash, operation payload hash, commit hash, verified proposer, and
  accepting coordinator.
- **FR-024**: The coordinator MUST validate the current epoch, operation and
  payload versions, approved ledger, request and original transaction, all
  entries, the verified proposer/sender, and permissions before accepting and
  announcing a commit. Acceptance MUST immediately publish the complete
  `LEDGER_OPERATION_COMMIT` through the canonical GUILD detail route and
  advertise the updated ledger digest; a later pull/fetch alone is not a
  substitute for the initial announcement.
- **FR-025**: A receiver MUST accept a commit only from the verified current
  coordinator for the correct guild and ledger, at the exact next sequence,
  with the expected epoch, previous hash, payload hash, and supported schema.
  Any failed check MUST reject the entire operation without applying an entry.
- **FR-026**: An exact duplicate of an already accepted commit MUST be
  idempotent. A reused operation ID with different content, a different
  commit at the same sequence, or a conflicting hash chain MUST be rejected
  and surfaced as a conflict.
- **FR-027**: A commit received beyond a missing sequence MUST NOT be applied
  out of order. The receiver MUST enter an explicit behind/recovery state and
  request the missing canonical commits from a valid coordinator source.
- **FR-028**: The coordinator MUST NOT accept a new correction when the
  operation path is unavailable, the required authority cannot be verified,
  or a known online participant required for guild ledger synchronization
  cannot validate the operation format. No local-only fallback is permitted
  when SyncV2 canonical acceptance is required. Canonical correction
  acceptance MUST be disabled by default and MUST remain disabled until an
  explicitly enabled release build passes its complete runtime readiness
  gates. The same gate MUST guard every direct/protected writer, coordinator
  acceptance path, and receiving path before any accounting mutation.
  Readiness MUST include successful local recovery, an approved explicit
  ledger, verified current authority and coordinator, a contiguous validated
  sequence/root, and required online-peer capability. A failed or unknown
  gate MUST reject explicitly without a local fallback or partial effect.
- **FR-029**: Offline members MUST be able to catch up from a valid canonical
  source after reconnecting, by applying missing commits in order. A member
  running an incompatible version MUST reject the unsupported operation,
  show an update/incompatible status, and remain behind; it MUST NOT silently
  apply only the familiar entries. It can converge after it has a compatible
  version and a valid catch-up source.
- **FR-030**: A successful send, local append, or in-memory acceptance MUST NOT
  be reported as proof that every member received the commit or that WoW
  flushed it to disk.

#### Recovery, compatibility, and persistence

- **FR-031**: Recovery MUST rebuild derived balances, transaction projections,
  operation indexes, and dispute correction status from the accepted canonical
  operation history and existing accepted award commits. It MUST also preserve
  and count pre-feature local transaction history that has no canonical commit
  exactly once, without promoting it to a new canonical operation. Rebuilding
  MUST distinguish these source categories, be deterministic and idempotent,
  and stop on duplicate IDs with conflicting content. Historical correction
  rows not represented by a provable accepted commit MUST remain unchanged and
  must not be heuristically repaired.
- **FR-032**: Recovery MUST distinguish an operation not yet accepted, an
  accepted operation with incomplete projections, a missing canonical
  sequence, an index mismatch, and an unrecoverable history conflict. It MUST
  surface the exact state and MUST NOT invent a compensation.
- **FR-033**: The system MUST provide a read-only reconciliation report for
  historical corrections. The report MUST identify at least complete,
  partial, ambiguous, local-only, and unverifiable cases with their known
  ledger, request, evidence, operation/correction keys, and transaction IDs.
  Generating the report MUST NOT mutate accounting or dispute history.
- **FR-034**: Historical `correctionKey` data and old partial corrections MUST
  NOT be converted automatically into accepted canonical operations or
  automatically compensated. Any approved repair MUST be a new append-only
  operation with explicit authority, reason, references, and audit record.
- **FR-035**: Existing backups and SavedVariables without canonical operations
  MUST remain readable without fabricating operation IDs or idempotency
  evidence. New backups MUST preserve the accepted operation records and
  stable IDs. Importing or restoring an operation already present with the
  same hash MUST NOT apply it twice; a conflicting hash MUST be rejected or
  explicitly quarantined without changing the current ledger.
- **FR-036**: Restore and import MUST preserve the existing rule that a backup
  cannot silently roll back a newer or conflicting canonical ledger. When
  operation history is present, projections MUST be verified or reconstructed
  from that history rather than counted as new accounting input.
- **FR-037**: The interface MUST distinguish a correction accepted in the
  current session from a correction observed after reload. Because the addon
  cannot confirm an operating-system disk flush, it MUST NOT claim that
  in-memory SavedVariables are durably saved to disk.
- **FR-038**: All guild and ledger operation data MUST remain isolated by the
  established guild identity and explicit ledger ID. Independent Raid or
  developer/test data MUST NOT be accepted as production correction history.

#### Scope and validation

- **FR-039**: This feature MUST cover Dispute Center balance corrections and
  the minimum shared ledger, authorization, coordinator, synchronization,
  recovery, and backup contracts required for those corrections. It MUST NOT
  migrate unrelated award or administrative operations without evidence that
  they are required for this correction path.
- **FR-040**: Every stage MUST have deterministic tests with fault injection.
  Tests MUST use independent saved-state snapshots for different simulated
  clients and compare balances, all transaction IDs, operation IDs and hashes,
  canonical epoch/sequence, dispute status, and recovery diagnostics.
  Distributed tests MUST execute the production Ledger and SyncV2 receive/
  dispatch code in independent Lua client environments; a fixture that only
  models a hypothetical ledger without invoking those modules is insufficient.
  Recovery tests MUST include mixed histories of legacy local transactions,
  old `AWARD_COMMIT` records, new operation commits, and ambiguous historical
  corrections, and compare balances to an independently calculated fixture
  oracle rather than only comparing two replays of the same implementation.
- **FR-041**: Automated test success MUST NOT be represented as Retail client
  certification. Release readiness MUST include an explicit multi-client
  validation record and a separate in-game verification status. CI and Retail
  evidence are release-owner gates, not conditions the Lua runtime can infer;
  runtime readiness MUST be based only on locally verifiable authority,
  protocol, ledger, and recovery state.
- **FR-042**: All directories named `libs`, regardless of case or location,
  MUST remain strictly read-only. This feature MUST NOT edit, annotate, add,
  delete, rename, move, reformat, or document files inside them. It MUST NOT
  include general cleanup, unrelated refactoring, or removal of RF annotations.
- **FR-043**: A correction proposal MUST identify the dispute revision on
  which it is based. The coordinator MUST reject a correction against a stale,
  already-resolved, or conflicting revision. At most one balance-changing
  correction may be accepted for a dispute revision; another correction
  requires an explicitly reopened or revised dispute and a new operation ID.

### Key Entities *(include if feature involves data)*

- **Canonical Ledger Operation**: One immutable, versioned correction intent
  scoped to a guild and ledger. It carries the operation ID and type, request
  and revision, evidence references, original transaction reference when a
  balance changes, verified actor, reason, timestamp, payload hash, schema
  version, and all signed entries.
- **Signed Entry**: One stable transaction-level effect belonging to exactly
  one operation and ledger. It identifies the affected member, signed balance
  change, action semantics, stable transaction ID, and the applicable dispute
  and original-transaction references.
- **Canonical Operation Commit**: The coordinator-accepted operation as one
  ordered ledger record. It binds the operation to the guild, ledger, epoch,
  sequence, previous canonical hash, payload hash, and commit hash.
- **Correction Proposal**: An authorized, non-accounting request awaiting the
  coordinator. It retains the operation ID and exact payload hash; proposal
  delivery or acknowledgement is not acceptance.
- **Correction Projection**: A rebuildable view of balances, transactions,
  indexes, and dispute resolution state derived from canonical accepted
  history. It is not an independent source of accounting authority.
- **Historical Reconciliation Report**: A read-only classification of legacy
  corrections and their evidence, including known gaps and conflicts. It does
  not authorize or perform repairs.

### Success Criteria *(mandatory)*

#### Measurable Outcomes

- **SC-001**: In a test of 100 retries or duplicate deliveries of one
  operation, exactly one canonical accounting effect is present, with the
  same operation ID and stable entry transaction IDs. The test MUST execute
  the real operation acceptance/replay path, assert one commit and one balance
  effect, and prove all 100 retries leave IDs, balances, and sequence unchanged
  after the first acceptance; include a reload/retry case where the test
  harness supports independent reinitialization.
- **SC-002**: In 100% of injected validation, authority, ledger-scope,
  incompatible-version, or payload-conflict failures, balances, transaction
  history, dispute resolution state, canonical sequence, and canonical hash
  remain unchanged.
- **SC-003**: After a compatible three-client recovery test, all clients that
  have caught up report identical accepted operation IDs, entry transaction
  IDs, balances, epoch, sequence, and root hash; no client reports current
  while a commit gap remains.
- **SC-004**: In 100% of projection-interruption tests after canonical
  acceptance, restart/recovery produces the same projections as uninterrupted
  application without adding a second operation or balance effect.
- **SC-005**: The read-only historical report classifies every supplied
  complete, partial, ambiguous, local-only, and unverifiable fixture, while
  preserving every original transaction and dispute record.
- **SC-006**: In 100% of backup/restore and repeated-import tests, all legacy
  transaction IDs remain unchanged and each canonical operation contributes
  its balance effect at most once.
- **SC-007**: Every user-facing result distinguishes rejected, proposed,
  accepted in the current session, behind/incompatible, recovered after
  reload, and persistence-unconfirmed states; no result claims an unverified
  disk save or guild-wide receipt.

### Assumptions

- RF-0012 is the sole scope. Normal awards and unrelated manual administrative
  actions are not migrated unless a planning review proves a correction-path
  dependency.
- A balance correction is valid only when its original transaction is
  verifiable in the explicitly named approved ledger. An attribution-only
  decision remains available as a distinct non-accounting resolution and
  cannot imply that a balance changed.
- The existing verified guild GM/Officer policy and current coordinator
  remain the authority sources. A non-coordinator Officer proposes; the
  coordinator alone accepts the canonical guild commit.
- The operation's protocol capability is version 1 and the operation data
  schema is version 1. The existing general sync envelope and accepted
  `AWARD_COMMIT` history remain compatible; unsupported peers fail closed and
  do not use a local fallback.
- Offline peers are not assumed to have received a commit. They can catch up
  only from an available valid canonical source and a compatible client.
- SavedVariables are session memory until WoW saves them. The feature cannot
  promise an atomic disk commit or immediate disk durability; a subsequent
  reload can verify that an operation was retained.
- Existing historical transactions, old correction keys, and partial
  corrections are preserved and reported, not automatically rewritten,
  converted, or compensated.
- Tests may use the existing framework and test doubles, but separate-client
  convergence and Retail behavior require independent validation beyond a
  single shared in-memory test fixture.
- The design follows the [project constitution](../../.specify/memory/constitution.md),
  the [audit index](../../docs/code-audit/INDEX.md), the
  [dependency map](../../docs/code-audit/DEPENDENCIES.md), the
  [RF-0012 backlog entry](../../docs/code-audit/SPECKIT-BACKLOG.md), the
  [audit progress record](../../docs/code-audit/PROGRESS.md), and the existing
  [SavedVariables](../../docs/developer/saved-variables.md) and
  [sync protocol](../../docs/developer/sync-protocol.md) contracts.

### Progressive Validation Slices

Each slice below must have passing focused tests and explicit evidence before
the next slice is considered ready. This sequence defines readiness boundaries
for later planning; it does not authorize implementation in this
specification-only phase.

1. Approve accounting invariants and the correction-operation contract.
2. Add deterministic tests that reproduce partial writes, failed compensation,
   retries, and cross-ledger targeting.
3. Define the versioned operation and commit schemas.
4. Validate full operation payloads and every entry before acceptance.
5. Establish stable IDs and Ledger-level idempotence.
6. Enforce explicit MultiLedger scope and original-transaction verification.
7. Preserve ProtectedActions permissions and propagate Ledger failures.
8. Route non-coordinator requests through the authorized Governance proposal.
9. Replicate one complete operation through SyncV2 with capability/version
   checks, sequence validation, duplicate handling, and gap recovery.
10. Rebuild balances and indexes from accepted canonical history after
    projection interruption or reload.
11. Connect Dispute Center resolution and statuses to accepted operations.
12. Verify backup, restore, import, and historical compatibility.
13. Run focused and full applicable regression tests without changing unrelated
    behavior.
14. Validate independent multi-client SavedVariables convergence and record
    Retail in-game verification separately from automated test results.
15. Keep the release activation disabled until all automated, recovery,
    backup/restore, compatibility, and Retail gates have recorded evidence;
    then enable only the release-controlled flag. The runtime MUST NOT pretend
    to verify that CI or Retail checks were run.
