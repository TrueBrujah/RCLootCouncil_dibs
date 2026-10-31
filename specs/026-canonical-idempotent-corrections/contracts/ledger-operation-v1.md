# Contract: Canonical Ledger Operation v1

This is the operation-schema contract for RF-0012. It describes a future implementation; it does not introduce executable behavior.

## Version and scope

- `schemaVersion` is exactly `1`.
- A balance-changing operation is bound to one canonical `guildKey` and one explicit, approved `ledgerId`.
- A balance-changing operation must identify a verifiable `originalTransactionId` in that same guild and ledger.
- A complete multi-leg correction is one immutable operation and one canonical ledger commit, never a sequence of independently accepted legs.
- Existing transactions, `correctionKey` values, and `AWARD_COMMIT` records are not rewritten or promoted.

## Intent owner and stable identity

The existing persisted Governance proposal store is the sole owner of an
unaccepted correction intent, including corrections initiated by the current
coordinator. Governance allocates `proposalId`, `operationId`, and every entry
`transactionId` once, stores the complete immutable operation before relay or
acceptance, and returns the same stored record for an exact retry or explicit
resume after reload. Ledger receives the operation as input and MUST NOT create
a parallel pending-intent store; Disputes MUST NOT persist a second copy of the
unaccepted payload.

An identical create request for the same request revision and immutable intent
reuses the stored proposal and its IDs. A materially different intent has a
different proposal identity, but the coordinator still accepts at most one
balance-changing operation for that request revision. Startup MUST NOT
auto-accept a pending proposal.

No time-based expiration is defined. A proposal becomes `STALE` or
`REJECTED` only when a current revision, authority, epoch, protocol, or other
acceptance precondition no longer holds, and the stored terminal result is
retained. Do not silently delete, rebase, or reuse it for a reopened revision.
Preserve the existing Governance cap of 100 persisted proposals and five relay
attempts; a full store or exhausted retries returns an explicit failure and
does not evict another record.

## Required operation fields

| Field | Type/constraint | Rule |
|---|---|---|
| `schemaVersion` | integer, exactly `1` | Reject unsupported versions. |
| `operationId` | stable non-empty ID | Generated once; unique in the guild namespace across its ledgers. |
| `operationType` | enumerated string | Only explicitly supported correction semantics are accepted. |
| `guildKey` | canonical guild identity | Must match the local guild and authority context. |
| `ledgerId` | explicit approved ledger ID | Must be the ledger that contains the verified original; never infer from active/view ledger. |
| `requestId` | stable dispute ID | Must resolve in this guild. |
| `requestRevision` | positive revision value | Must match the current open/correctable dispute revision at coordinator acceptance. |
| `evidenceId` | ID or explicit `false` | If present, must be valid in the scoped dispute context. |
| `originalTransactionId` | ID or explicit `false` | Required transaction ID for all balance-changing operations; `false` is allowed only for an explicitly non-accounting operation. |
| `actor` | verified proposer identity | Identifies the proposer; does not establish authorization by itself. |
| `reason` | non-empty bounded text | Required for review and audit. |
| `timestamp` | finite timestamp | Captured when the stable intent is created; retries must preserve it. |
| `signedEntries` | ordered array | Entire set validated before any effect; see entry contract. |
| `payloadHash` | deterministic content identity | Recomputed by coordinator and receiver; not an authentication signature. |

For non-applicable optional fields, use the contract's explicit absent value (`false`). Do not use `nil`, empty strings, the active ledger, or guessed references as a semantic default.

## Supported operation semantics

| `operationType` | Entries | Acceptance rule |
|---|---:|---|
| `DISPUTE_BALANCE_CORRECTION` | One | Must match the approved dispute action and original transaction semantics. |
| `DISPUTE_TARGET_TRANSFER` | Two | Must validate both affected members together; a pure transfer has a net signed delta of zero. |
| `DISPUTE_ATTRIBUTION_RESOLUTION` | Zero | Explicitly non-accounting; cannot be reported as a balance correction or create a transaction. |

The concrete action-type allowlist must be derived from existing Ledger and Disputes behavior during implementation and tested as an exhaustive table. Unknown action or operation types fail closed.

## Signed entry contract

Every entry has a stable transaction ID; parent `operationId`; contiguous one-based `entryIndex`; same explicit `ledgerId`, `guildKey`, `requestId`, `requestRevision`, `originalTransactionId`, and applicable `evidenceId`; affected canonical member; validated season; an allowlisted action; and a signed integer balance change.

- Entry transaction IDs are allocated once with the operation and retained through proposal retry, reload, commit, replay, and recovery.
- Entries form a dense ordered array. Duplicate transaction IDs, gaps in `entryIndex`, mismatched parent references, invalid members/seasons, or invalid action/sign combinations reject the whole operation.
- The complete set is validated before appending the canonical record.
- Existing ledger transaction validation remains authoritative for action-specific semantics.

## Canonical payload and idempotency

1. Serialize immutable operation fields using the repository's deterministic type-tagged/key-sorted serializer.
2. Include the ordered entry sequence and all identity, scope, reference, actor, reason, and timestamp values.
3. Exclude only the `payloadHash` field itself.
4. Recompute and compare the hash at proposal acceptance, canonical commit creation, receive, recovery, and restore.
5. On duplicate `operationId`, compare guild, ledger, hash **and exact canonical immutable content**.

| Existing identity | Submitted content | Result |
|---|---|---|
| No operation ID found | Valid and authorized | Candidate may proceed to one canonical commit. |
| Same ID and exact same content | Replay | No new balance, transaction, sequence, or correction effect; complete only missing derived projections. |
| Same ID with another hash/content/guild/ledger | Conflict | Reject without mutation and surface `OPERATION_ID_CONFLICT`. |
| Different ID, same already-accepted request revision | Second correction | Reject with `DISPUTE_REVISION_ALREADY_CORRECTED`. |

The content hash is not a signature. Actual sender identity, current guild rank, coordinator authority, and permissions are independently validated.

## Atomic logical acceptance and projection order

0. Check the default-off feature gate and completed recovery/readiness state before any writer, coordinator acceptance, or receiver can mutate accounting state.
1. Resolve the original transaction from canonical guild/ledger data and confirm the approved ledger.
2. Validate current dispute revision, actor authority, operation schema/hash, all entries, and guild-wide operation/transaction ID uniqueness without mutation.
3. Construct the complete canonical commit at the exact next ledger sequence, with current epoch and previous root.
4. Accept one `LEDGER_OPERATION_COMMIT` at the canonical boundary.
5. Materialize every transaction and rebuildable index/balance/correction projection idempotently from that record.
6. On interruption after step 4, recovery repeats step 5. It must not append another commit or compensate automatically.

The gate is runtime-only: it can verify this client's configuration, current
authority, approved ledger, protocol compatibility, sequence/root, and local
recovery status. CI and Retail test completion are release-owner checks and
MUST NOT be represented as runtime facts. If the feature gate is off or any
runtime precondition is unknown, return an explicit blocked result with zero
accounting effect; never fall back to a local transaction or per-leg write.

These rules guarantee logical all-or-reject acceptance and deterministic reconstruction. They do not guarantee an atomic SavedVariables disk write, OS flush, or retention after a crash before WoW saves state.

## Failure result contract

Failures return a non-success result with an explicit stable diagnostic code, including where applicable: `INVALID_OPERATION`, `UNSUPPORTED_OPERATION_VERSION`, `INVALID_ENTRY`, `ORIGINAL_TRANSACTION_MISSING`, `ORIGINAL_TRANSACTION_MISMATCH`, `LEDGER_NOT_APPROVED`, `LEDGER_NOT_FOUND`, `PERMISSION_DENIED`, `PROPOSER_NOT_AUTHORIZED`, `COORDINATOR_UNAVAILABLE`, `INCOMPATIBLE_PEER`, `STALE_DISPUTE_REVISION`, `OPERATION_ID_CONFLICT`, `TRANSACTION_ID_CONFLICT`, `LEDGER_GAP`, `HASH_MISMATCH`, `PROJECTION_INCOMPLETE`, or `HISTORY_CONFLICT`.

Do not mask a Ledger failure with a compensation result, return a success-shaped transaction on rejection, or report proposal receipt as commit acceptance.
