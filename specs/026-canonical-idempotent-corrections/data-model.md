# Data Model: Canonical Dispute Correction Operations

## Ownership and source of truth

| Record/view | Storage or owner | Authority |
|---|---|---|
| Canonical operation commit | `db.ledgers[ledgerId].canonical.commits[epoch:sequence]` | Sole accounting source of truth for an accepted correction |
| Operation and transaction lookup indexes | Rebuilt from each ledger's canonical commits; `canonical.transactionIndex` remains the persisted transaction-to-position projection | Derived lookup only |
| Canonical-backed transaction rows | Existing `db.ledgers[ledgerId].transactions` map | Projection of the accepted award/operation commit; never counted separately from its source commit |
| Pre-feature local transaction rows without a canonical commit | Existing `db.ledgers[ledgerId].transactions` map and retained row references | Preserved legacy accounting evidence, counted once; never promoted into canonical operation evidence |
| Player histories, cached balances, and lookup/award/evidence indexes | Existing per-ledger state | Derived projections; rebuild only when the source row/commit relationship is unambiguous |
| Pending correction proposal/intent | The existing persisted Governance proposal store; Governance is the sole durable owner of the exact operation intent and its stable proposal/operation/entry IDs | Non-accounting; retry handle only; never proves acceptance |
| Dispute correction operation state | Additive `db.disputes.operationStates[operationId]` projection | Rebuilt from accepted commits; not an authority source |
| Historical reconciliation report | Computed on demand from ledger/dispute evidence | Read-only; no SavedVariables mutation |

Guild partitioning remains the current `Dibs.GetGuildKey()` boundary. Every operation also carries a mandatory explicit `ledgerId`. The global guild operation-ID index is reconstructed across all ledger commit maps so reusing an ID in another ledger conflicts.

### Mixed-history authority and projection rules

Recovery MUST combine the existing history categories without treating two
representations of one effect as separate accounting input:

| History category | Authoritative evidence | Recovery treatment |
|---|---|---|
| New correction | Validated `LEDGER_OPERATION_COMMIT` at its contiguous canonical position | Count each ordered entry once; transaction rows and indexes linked by operation/entry IDs are projections and may be rebuilt. |
| Existing canonical award | Existing `AWARD_COMMIT` at its stored position | Preserve and apply only under the existing award contract; do not convert it to an operation or change its hash projection. |
| Pre-feature local transaction without a canonical commit | The preserved `db.ledgers[ledgerId].transactions[transactionId]` row and validated guild/ledger references | Retain and count the row once as legacy history; do not fabricate an operation ID or claim canonical acceptance. |
| Historical/partial correction without a provable accepted commit | Existing transaction and dispute evidence only | Preserve unchanged and report `partial`, `ambiguous`, `local-only`, or `unverifiable`; never infer missing legs or add compensation. |

Cached balances, player transaction lists, lookup indexes, and correction
status are projections, not independent authority. A transaction row whose ID
is already represented by an accepted canonical record is not counted a second
time. If an ID is duplicated with differing content, or the evidence cannot
unambiguously assign a row to a source category, recovery reports a conflict
and does not guess. Recovery tests calculate expected balances independently
from explicit synthetic starting allocations plus the unique accepted
canonical entries and unique retained legacy-local rows; comparing two runs of
the production replay algorithm alone is not a sufficient oracle.

## Canonical Ledger Operation v1

```lua
{
  schemaVersion = 1,
  operationId = "stable Dibs operation ID",
  operationType = "DISPUTE_BALANCE_CORRECTION",
  guildKey = "canonical guild identity",
  ledgerId = "explicit approved ledger ID",
  requestId = "dispute ID",
  requestRevision = 3, -- revision on which proposer based the correction
  evidenceId = "evidence ID or false when not applicable",
  originalTransactionId = "verified ledger transaction ID for balance changes",
  actor = {
    memberKey = "verified proposer identity",
    displayName = "roster display name",
    authority = "current GM/Officer",
  },
  reason = "required, bounded administrative reason",
  timestamp = 0,
  signedEntries = { /* ordered SignedEntry v1 rows */ },
  payloadHash = "recomputed content identity",
}
```

`false` is the serialized explicit-absence marker for an optional value; `nil`, empty strings, and inferred values are not substitutes. `originalTransactionId` must be a string for every balance-changing operation. It may be `false` only for the explicit non-accounting attribution-resolution type. The operation's immutable hash projection excludes `payloadHash`, includes every other immutable field and the ordered entry list, and uses the existing deterministic canonical serializer. The hash is not actor authentication.

### Supported operation types

| Type | Entry count | Semantics |
|---|---:|---|
| `DISPUTE_BALANCE_CORRECTION` | 1 | One supported signed balance correction, including the explicitly selected refund/revoke/adjustment/historical-import semantics |
| `DISPUTE_TARGET_TRANSFER` | 2 | Reverse the original member's signed effect and apply the same net effect to the corrected member; total signed change is zero |
| `DISPUTE_ATTRIBUTION_RESOLUTION` | 0 | Optional item/player attribution-only resolution; never reports or creates a balance change |

`NO_CORRECTION`, request status changes, and unrelated awards are not accounting operation types. Unknown operation types or ledger action types are rejected.

## SignedEntry v1

Each row is immutable and belongs to one operation:

```lua
{
  operationId = "parent operation ID",
  entryIndex = 1, -- contiguous, one-based order
  transactionId = "stable transaction ID reused on every retry",
  ledgerId = "same explicit ledger as operation",
  memberKey = "affected canonical guild member",
  seasonId = "validated season",
  actionType = "DIB_ADMIN_ADJUSTMENT",
  quantityDelta = -1, -- signed integer; action sign checked by Ledger
  evidenceId = "evidence ID or false",
  originalTransactionId = "same verified original ID",
  requestId = "same dispute ID",
  requestRevision = 3,
}
```

The row is validated and converted to an existing ledger transaction representation before acceptance. New projected transaction rows retain the existing transaction schema/classification and add explicit `operationId` and `entryIndex` links. Their existing transaction IDs remain stable. Do not update old transaction hashes or legacy rows.

Validation rules:

- Entry IDs are unique within the operation and guild ledger, have the repository's existing transaction-ID bounds, and are generated once.
- Entries are a contiguous ordered Lua array of exactly one or two rows for balance-changing types.
- Every entry's operation, ledger, request and original-transaction IDs match the parent operation.
- Every member and season resolves under current guild/ledger context.
- Each action and signed amount satisfies existing `Ledger` type/sign/range and accounting rules.
- A pure target transfer has exactly two distinct member identities and a zero sum; each amount is derived from and validated against the original transaction and approved target correction.
- The original transaction exists, is immutable, and is in the operation's approved ledger.
- Validate the entire operation and its permission/authority before changing the commit chain or any accounting projection.

## LEDGER_OPERATION_COMMIT

One coordinator commit carries exactly one complete operation:

```lua
{
  schema = 1, -- existing canonical record envelope version
  recordClass = "LEDGER_OPERATION_COMMIT",
  protocolVersion = 1,
  guildKey = "canonical guild identity",
  ledgerId = "explicit approved ledger ID",
  ledgerEpoch = 7,
  sequence = 12,
  previousHash = "previous canonical root",
  payloadHash = "operation.payloadHash",
  proposer = { memberKey = "...", displayName = "...", authority = "..." },
  coordinator = { memberKey = "...", displayName = "..." },
  operation = { /* complete Canonical Ledger Operation v1 */ },
  commitHash = "hash of canonical commit projection",
}
```

The operation payload is included whole. `commitHash` binds the record class, protocol/schema versions, guild, ledger, epoch, sequence, previous hash, payload hash, proposer and accepting coordinator. Receiver recomputes both operation payload and commit hashes. It independently authenticates the actual sender through current roster identity/coordinator authority. Neither hash is a signature.

The commit occupies one position in the existing `canonical.commits` sequence. All entry transaction IDs point to that one position. Existing `AWARD_COMMIT` projection/hash calculation and stored entries are unchanged.

## Operation lookup and replay

At startup or before a correction command, build an in-memory guild-wide lookup by scanning approved and retained ledger commit maps:

```text
operationId -> guildKey, ledgerId, epoch, sequence, payloadHash, commitHash, exact canonical operation
```

- Exact same ID, guild, ledger, hash **and** canonical content: idempotent replay; complete any missing projections; do not advance sequence.
- Same ID but another guild, ledger, payload/hash, request, or entry: `OPERATION_ID_CONFLICT`; no mutation.
- A repeated request revision with a different operation ID after one accepted operation: `DISPUTE_REVISION_ALREADY_CORRECTED`; no mutation.
- Exact duplicate position/commit: no effect.
- Different commit at the same position, reused transaction ID with different content, sequence gap, or broken chain: explicit conflict/behind state; no projection of any leg.

## Intent identity and persistence

Governance alone owns the persisted pending proposal/intent, including a
coordinator's own correction. Ledger builds and validates supplied immutable
operations but does not persist a second pending-intent copy; Disputes stores
only the accepted-state projection. On initial submission, Governance allocates
the proposal ID, operation ID, and entry transaction IDs once and stores the
complete operation before relay or coordinator acceptance is attempted.

An exact retry after an in-session failure or reload resumes the stored
proposal by its stable proposal ID and reuses the exact payload, IDs, timestamp,
and hash. Repeating a create request for an identical immutable intent at the
same dispute revision reuses its existing proposal rather than minting new
accounting identities. A materially different intent is a distinct proposal;
the coordinator still enforces at most one accepted balance-changing operation
for that request revision. Startup recovery never auto-accepts a pending
proposal.

There is no wall-clock TTL or automatic deletion. A proposal whose dispute
revision, proposer authority, coordinator epoch, or required peer capability is
no longer valid is retained with an explicit `STALE`/`REJECTED` result; it is
not silently rebased or reused for a new revision. Retries of a terminal
proposal return its terminal result. A revised/reopened request requires a new
proposal and new operation identity. Preserve the existing Governance limits
of 100 persisted proposals and at most five relay attempts; reaching a limit
fails explicitly and never evicts an unresolved record to make room.

## Dispute state and transition

The proposal keeps the original operation and identity; it is not the accepted record. A coordinator acceptance applies the complete operation commit, then projects correction status:

```text
INTENT_CREATED
  -> PROPOSED (non-coordinator; no balance effect)
  -> ACCEPTED_IN_SESSION (one canonical commit, projections complete)
  -> RECOVERED_AFTER_RELOAD (accepted record observed and verified on later load)
```

Terminal/exception observations include `REJECTED`, `STALE_REVISION`, `BEHIND`, `INCOMPATIBLE`, `PROJECTION_INCOMPLETE`, `HISTORY_CONFLICT`, and `PERSISTENCE_UNCONFIRMED`. No status is named or presented as “saved to disk” based on an in-session assignment.

`db.disputes.operationStates[operationId]` is a derived projection containing the operation ID, request and source revision, ledger, commit position/hash, entry transaction IDs, current projection/recovery state, and safe diagnostic code. Rebuild it from canonical commits. Update the dossier's correction link only when the stored request revision is still the source revision or the matching operation link can be proven; never overwrite a later resolution/reopen/archive event.

One balance-changing operation is accepted per `(guildKey, requestId, requestRevision)`. A reopened or revised request uses a new revision and new operation ID.

## Historical reconciliation report

The report reads across every retained guild ledger and existing dispute correction metadata. It reports evidence and known IDs, not a guess:

| Classification | Evidence rule |
|---|---|
| `complete` | All explicitly referenced historical transaction IDs are present, references/amounts reconcile, and the complete observed effect can be described. This is observational completeness, not proof of a canonical operation. |
| `partial` | Available request/transaction evidence identifies an expected effect or transfer with one or more missing legs. |
| `ambiguous` | Multiple plausible matching transactions/ledgers or contradictory references prevent a unique interpretation. |
| `local-only` | Correction transaction(s) exist but have no corresponding accepted canonical operation commit. |
| `unverifiable` | Required original, request, ledger, or transaction evidence cannot be located or validated. |

Legacy `correctionKey` is only a search/correlation field. Report generation never writes status, IDs, balances, transaction rows, or compensation entries. Any approved repair is a new operation with current authority, reason, explicit references and audit trail.

## Migration, backup, and import data

- Existing root schema is 6 and guild schema is 7. Implementation increments guild schema to 8 and dispute projection version to 3 with a staged additive migration. It initializes only the new operation-state projection structure.
- Preserve `canonical.schema`, existing canonical commit records/hashes, `nextSeq`, `rootHash`, `positions`, transaction indexes, `db.ledger` active pointer, all ledgers, transactions, balances and existing dispute corrections.
- Existing transactions and `correctionKey` values do not receive fabricated operation IDs.
- New full backups carry the canonical commits and exact stable IDs. Restore validates the chain and uses the existing newer/conflicting ledger retention rule before projection recovery.
- Repeated import of an operation already present with exact content is a no-op; a conflicting ID/hash/ledger is rejected or quarantined in preview. General full import does not directly append unseen canonical operations or projected `LOCAL_CANONICAL` rows. Use whole-history restore or normal coordinator-approved SyncV2 catch-up.
- Existing package envelope stays version 1 while its payload remains the existing saved-state snapshot. Unknown operation record classes are explicitly rejected by old/new validators rather than partially applied.
