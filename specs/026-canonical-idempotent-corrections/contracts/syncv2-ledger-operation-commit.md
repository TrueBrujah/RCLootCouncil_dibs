# Contract: SyncV2 `LEDGER_OPERATION_COMMIT`

This is the future protocol contract for one complete RF-0012 correction. It extends the existing per-ledger sequence and detail-fetch protocol. It does not change old `AWARD_COMMIT` records.

## Version negotiation

- Capability: `ledgerOperationCommit=true`.
- Operation schema: `schemaVersion=1`.
- Commit protocol: `protocolVersion=1`.
- Keep these versions distinct from the general SyncV2 envelope version.
- A client that does not advertise or validate this capability must not accept the new entity.
- The coordinator must not accept a new correction while a known online Dibs participant required for ledger synchronization lacks the capability.
- Offline clients are not counted as having received a commit; compatible clients can recover the missing sequence after reconnect. An incompatible client remains explicitly behind until updated.

## Default-off activation and readiness

Canonical correction acceptance is disabled by default in the release source.
The feature flag is release-controlled; it is not a user-facing setting or a
SavedVariables toggle. Capability advertisement and every local/protected
writer, coordinator acceptance route, and receiver must use the same gate.

Before accepting or projecting an operation, the runtime gate requires the
release flag to be enabled, successful local ledger recovery, an approved
explicit ledger, verified current coordinator/authority, a contiguous
validated epoch/sequence/root, and the required known-online peer capability.
Unknown or failed readiness blocks the whole operation with an explicit
diagnostic and no local fallback. A receiver whose gate is off must reject the
new record and remain visibly incompatible/behind; it must not apply familiar
entries.

This gate cannot establish whether CI suites or Retail validation were run.
Those are external release-owner checks. Keep the source default off until the
release owner has recorded evidence for the full test, recovery,
backup/restore, compatibility, and Retail gates; do not encode a false runtime
claim that those checks were verified by Lua.

## Canonical commit envelope

```lua
{
  recordClass = "LEDGER_OPERATION_COMMIT",
  protocolVersion = 1,
  guildKey = "...",
  ledgerId = "...",
  ledgerEpoch = 0,
  sequence = 0,
  previousHash = "...",
  payloadHash = "...",
  proposer = { memberKey = "...", displayName = "...", authority = "..." },
  coordinator = { memberKey = "...", displayName = "..." },
  operation = { /* complete Canonical Ledger Operation v1 */ },
  commitHash = "...",
}
```

The commit hash covers the record class and versions, guild and ledger, epoch and sequence, previous hash, operation payload hash, proposer, coordinator, and complete operation identity. Receivers recompute the payload and commit hashes and independently validate the actual sender. Hashes establish content identity, not cryptographic authentication.

## Acceptance requirements

The coordinator validates, before append:

1. Actual proposer identity and current GM/Officer authority.
2. Its own current coordinator authority and applicable permission.
3. Current guild, approved explicit ledger, epoch, next sequence, and previous root.
4. Capability, operation schema and protocol version.
5. Current dispute ID/revision, original transaction, and evidence scope.
6. Every signed entry and all operation invariants.
7. Guild-wide operation-ID and entry-transaction-ID uniqueness.
8. Known online participant capability gate.

The receiver validates the actual sender as current coordinator for the correct guild; explicit ledger approval; schema/capability; epoch; exact next sequence; previous hash; payload and commit hashes; and complete operation validity. Any failure rejects the whole operation and makes no balance, transaction, sequence, or dispute-state change.

## Sequence, duplicate, and gap behavior

- One operation maps to one canonical sequence position. All leg transaction IDs reference that position.
- Repeated exact operation or commit is a no-op; it does not increment the sequence or append transaction IDs again.
- Same operation ID with different content, another record at the same position, or conflicting chain hash reports a conflict and does not apply any leg.
- A sequence greater than the next expected sequence is held unapplied, marks the ledger explicitly behind, and requests missing commits from a valid current coordinator.
- The detail response for a requested position returns the actual stored record class. Mixed histories can therefore include existing `AWARD_COMMIT` and new operation records without rewriting old records.
- A legacy `AWARD_COMMIT` is validated and applied by its existing contract. The new operation handler does not reinterpret it.
- Never construct per-entry commits or fall back to local transaction/adjustment writes if the canonical path is unavailable.

## Proposal path

A non-coordinator Officer submits the exact operation payload through a
targeted SyncV2 WHISPER record with the distinct
`LEDGER_OPERATION_PROPOSAL` record class. Add this record to the narrow
proposal allowlist and dispatch it to Governance's operation-proposal receiver;
do not route it through the `AWARD_PROPOSAL` accounting handler. The proposal
includes its stable proposal ID, operation and entry IDs, payload hash, request
and revision, explicit ledger, original/evidence references, reason, and
verified proposer identity.

The coordinator acknowledges receipt with a distinct
`LEDGER_OPERATION_PROPOSAL_ACK` status (`RECEIVED`, `DUPLICATE`,
`REJECTED`, `STALE`, or `INCOMPATIBLE`). The acknowledgment is not a canonical
commit and is never reported as accounting acceptance. Retry uses the same
proposal ID and byte-equivalent immutable payload, is deduplicated by
Governance, and respects its existing limit of five relay attempts and 100
persisted proposals; exhausted retries/full capacity fail explicitly without
eviction. The coordinator revalidates the proposer and all current operation
conditions at acceptance. A stale revision or lost authority is explicitly
rejected; it is not silently rebased.

The accepted operation is announced immediately as one
`LEDGER_OPERATION_COMMIT` on the existing canonical GUILD detail route after
the journal position/root are accepted. The coordinator also advertises the
updated `LEDGER_DIGEST`; sequence fetch must return the record class actually
stored at the requested position. The initial announcement is required and
cannot be replaced by a future pull-only mechanism. Exact duplicate
announcements are idempotent; followers validate through the same receiver as
catch-up before projecting any entry.

## Catch-up and incompatible clients

`LEDGER_DIGEST` remains authoritative for the ledger epoch, last sequence, and root. A client behind the coordinator fetches missing sequence positions in existing bounded batches and validates them in order. A temporarily offline member can converge once it reconnects with a supported implementation and valid source.

When a client sees an unsupported record class/version, it rejects the whole operation, makes no familiar-leg partial application, reports an incompatible/behind state, and requests an update or compatible source. The system does not downgrade or invent a local commit.

## Result semantics

| State | Meaning |
|---|---|
| `PROPOSED` | Proposal persisted/relayed; no accounting effect. |
| `ACCEPTED_IN_SESSION` | Current client accepted the canonical record and completed or can deterministically recover projections; not proof of disk flush or all-member receipt. |
| `BEHIND` | A sequence gap exists; later record is not applied. |
| `INCOMPATIBLE` | Peer cannot validate the operation schema/record class; no partial apply. |
| `REJECTED` | Validation, authority, permission, or chain failed. |
| `RECOVERED_AFTER_RELOAD` | On later load, the accepted canonical operation was observed and verified. |
| `PERSISTENCE_UNCONFIRMED` | The operation exists in current memory but no later reload has confirmed SavedVariables retention. |
