# Implementation Plan: Canonical Ledger Operations & Idempotent Dispute Corrections

**Branch**: `dev` (current workspace branch; no branch switch) | **Date**: 2026-10-18 | **Spec**: [spec.md](./spec.md)

**Input**: RF-0012 specification, quality checklist, assessment, audit dependency map, backlog, progress record, project constitution, and current SavedVariables/SyncV2 contracts.

**Planning boundary**: This plan does not implement code, alter the feature specification, create `tasks.md`, change the TOC/XML, or touch any directory named `libs`. The Spec Kit pointer is `.specify/feature.json`; the requested `specs/026-canonical-idempotent-corrections/feature.json` is not present.

## Summary

Represent each balance-changing Dispute Center correction as one immutable `Canonical Ledger Operation`, validate every leg and reference before accepting it, and append the complete operation as one coordinator-accepted record to the ledger's existing ordered canonical history. Reuse the current per-ledger commit sequence, hash chain, `LEDGER_DIGEST` gap detection, `DETAIL_FETCH`, and coordinator validation rather than introducing another accounting journal or local correction path.

The canonical commit log is the source of truth for accepted new correction effects. Existing `AWARD_COMMIT` records remain authoritative under their unchanged contract; preserved pre-feature local transaction rows without a canonical commit remain legacy history and are counted once, but are never promoted into new canonical operations. Operation/transaction indexes, balances, histories, and correction status are projections wherever a source record exists. A pending Governance proposal is not a commit. A Lua write sequence is not a disk transaction: an operation accepted in the current session remains persistence-unconfirmed until a later reload observes and verifies it.

The first implementation gate is a test-first set of deterministic reproductions, including partial target transfer, failed second leg, stale dispute revision, missing original transaction, cross-ledger lookup, and interrupted projection recovery. Full activation remains disabled until operation/proposal validation, SyncV2 announcement and catch-up, compatibility, recovery, backup/restore/import, and separately recorded Retail/release-owner gates all pass.

## Technical Context

**Language/Version**: WoW Retail Lua; project modules use the existing Lua subset and WoW APIs.

**Primary Dependencies**: Existing `Dibs` namespace and `Dibs.CoreAPI`, Ace3 serialization/communication adapters, Identity, Permissions, Governance, SyncV2, SavedVariables, and Fengari test doubles. No new runtime dependency is planned.

**Storage**: Account-wide `RCLootCouncil_dibsDB`, partitioned by canonical guild key; each `db.ledgers[ledgerId]` has a `canonical.commits` map and existing transaction projections. Disputes are stored under `db.disputes`; the existing persisted Governance proposal store is the sole owner of pending correction intent and its stable IDs. WoW SavedVariables are in-memory state until the client saves them.

**Testing**: Existing Lua `describe`/`it` suites under `tests/`, executed with `tests/run.lua` and Fengari. Distributed tests must execute the production Ledger and SyncV2 receiver/dispatch code in isolated Lua addon environments with independent SavedVariables, not only a scenario model. Recovery tests use mixed-history fixtures and a separately calculated balance oracle. A separate in-game Retail multi-client validation remains required.

**Target Platform**: World of Warcraft Retail addon; no server process or external persistence service.

**Project Type**: Single Lua addon with domain/persistence modules, SyncV2 and framework adapters, localized Officer UI projections, and unit/integration/contract tests.

**Performance Goals**: Correction validation and replay must be bounded by operation size and the existing canonical history scan; each supported accounting correction has one or two signed entries. Sync continues to use the existing bounded transfer limits (8,192 encoded bytes, at most 16 chunks, 480 bytes per chunk, eight concurrent transfers, 300-second TTL). If real commit volume makes guild-wide operation-ID reconstruction expensive, optimize only after a measured test; do not weaken uniqueness.

**Constraints**:
- Validate the entire operation before any accounting projection changes.
- Keep acceptance disabled by default; one runtime readiness gate must protect every local/protected writer, coordinator acceptance route, and receiver. Unknown readiness is a visible rejection with no fallback.
- Runtime readiness can verify local recovery, authority, explicit ledger, protocol, sequence/root, and peer capability only; CI and Retail evidence remain release-owner gates and must not be claimed by the Lua runtime.
- No correction in V2 may fall back to `CommitLocalTransaction`, `AdminAdjust`, or a compensation sequence.
- Resolve the ledger from the verified original transaction, not from the active/view ledger.
- Keep historical records immutable and all data partitioned by guild and ledger.
- Reuse the existing commit sequence and hash chain; preserve existing `AWARD_COMMIT` records and their hash projection unchanged.
- Announce each accepted `LEDGER_OPERATION_COMMIT` immediately on the canonical GUILD detail route and publish the updated digest; pull/catch-up alone is not sufficient initial propagation.
- Route proposals through distinct `LEDGER_OPERATION_PROPOSAL` and `LEDGER_OPERATION_PROPOSAL_ACK` WHISPER record classes; do not reuse the award proposal receiver or its accounting semantics.
- No claim of atomic disk persistence, group receipt, or Retail certification based on Fengari.
- All `libs` directories are read-only; no general refactor or RF-0013 work.

**Scale/Scope**: Dispute Center balance correction operations and the minimum Ledger, MultiLedger, ProtectedActions, Permissions, Governance, SyncV2, recovery, backup/import, diagnostics, and UI contracts required to support them. Normal awards and unrelated manual administrative operations are not migrated.

## Constitution Check

*Gate checked before research and again after design.*

| Principle | Gate and plan result |
|---|---|
| IV — Append-Only Ledger and Auditability | **Pass**: accepted corrections add new canonical records and transaction rows; rebuilds repair projections only and never edit old transaction content. |
| X — Distributed Synchronization | **Pass**: one operation is one ordered canonical commit; duplicates are idempotent; gaps remain behind and use the existing coordinator catch-up path. |
| XI — Authority and Trust | **Pass**: `ProtectedActions` remains the mutation boundary; proposer and coordinator are verified at acceptance; receivers validate the actual sender and current authority. |
| XIII — Data Ownership and Persistence | **Pass with explicit limitation**: Dibs SavedVariables remain the source; operation schema is versioned; migration is additive; no disk-flush or atomic-save guarantee is asserted. |
| XIV — Public Repository Quality | **Pass**: wire/save compatibility impact and the intentional missing-original behavior are documented; old `AWARD_COMMIT` records remain unchanged. |
| XV and XVII — Developer Safety and Isolation | **Pass**: production guild data, Developer Mode, and Independent Raid/test contexts stay isolated; no test fixture can append to production history. |
| XVIII — Diagnostics and Visibility | **Pass**: actual validation, permission, ledger, proposal, and synchronization failures are returned as explicit states and localized; historical inspection is read-only. |
| XIX — Change Notes and Versioning | **Future implementation gate**: the implementation/release must add a dated changelog entry, update the TOC addon version and release evidence, and document SavedVariables/protocol compatibility. This planning-only change does not do so. |
| UI instructions / DIBS-RULE-008 | **Pass**: reuse the Midnight Officer/Dashboard status pattern, keep review and apply steps explicit, localize strings in `enUS.lua`/`frFR.lua`, and never make a projection a mutation authority. |
| Scope and filesystem restrictions | **Pass**: no `libs`, TOC, XML, unrelated code, RF-0013, cleanup, commit, or push is planned. |

**Pre-design gate**: No unresolved product decision was found in the approved specification. In particular, a balance correction without a verifiable original transaction is explicitly rejected; this is an intentional behavior tightening, not a new policy inferred by this plan.

**Post-design gate**: Pass. The design is additive, does not rewrite historical transactions or old commit hashes, uses the existing protected/coordinator pipeline, and treats uncertain disk durability and incompatible clients as visible states. No constitutional exception is requested.

## Project Structure

### Documentation produced by this plan

```text
specs/026-canonical-idempotent-corrections/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── traceability.md
└── contracts/
    ├── ledger-operation-v1.md
    └── syncv2-ledger-operation-commit.md
```

The plan-generation step did not create `tasks.md`; the separately generated
and now amended implementation sequence is in [tasks.md](./tasks.md).

### Future implementation surfaces (not changed in this planning task)

```text
src/
├── Core.lua                         # additive guild/dispute migration and startup recovery ordering
├── modules/
│   ├── Disputes.lua                 # original lookup, stable intent, correction projection/report
│   ├── Ledger.lua                   # operation validation, journal append, idempotence, projection recovery
│   ├── MultiLedger.lua              # verified original-ledger lookup and approved-ledger scope
│   ├── ProtectedActions.lua         # protected operation submission and explicit errors
│   ├── Permissions.lua              # current GM/Officer permission for the operation action
│   ├── Governance.lua               # typed correction proposal, coordinator acceptance, request revision
│   ├── SyncV2.lua                   # capability, proposal relay, operation transfer, gap catch-up
│   ├── Backup.lua                   # preview/restore verification of canonical operation histories
│   └── ImportExport.lua             # operation duplicate/conflict preview; no untrusted direct commit
├── ui/
│   └── OfficerUI.lua                # proposal review, correction status, read-only legacy report
└── locales/
    ├── enUS.lua
    └── frFR.lua

tests/
├── unit/
│   └── ledger_operation_spec.lua
├── integration/
│   ├── canonical_dispute_operation_spec.lua
│   ├── canonical_dispute_sync_spec.lua
│   ├── dispute_center_spec.lua
│   ├── b06_distributed_ledger_spec.lua
│   ├── multi_ledger_sync_spec.lua
│   ├── backup_sync_restore_spec.lua
│   ├── backup_import_profiles_spec.lua
│   ├── migration_spec.lua
│   ├── persistence_recovery_spec.lua
│   └── protected_actions_spec.lua
└── contract/
    └── dispute_authority_privacy_spec.lua
```

No TOC edit is expected: the change extends existing modules and load order. If implementation discovers a new module is unavoidable, load-order justification and a targeted TOC test must be added before changing the TOC.

**Structure Decision**: Extend existing domain and persistence boundaries. `Ledger` owns validation, canonical journal application, and derived accounting projections; `Disputes` owns dispute-to-operation intent and read-only historical analysis; `Governance` owns coordinator and proposal authority; `SyncV2` owns transport and catch-up; `ProtectedActions` owns authorization; UI remains a projection. No parallel “correction ledger” is introduced.

## Architecture and Decisions

### Canonical authority and projections

1. The accepted record at `ledgers[ledgerId].canonical.commits[epoch .. ":" .. sequence]` is the source of truth for an operation. It shares the ledger's existing sequence/hash chain with legacy `AWARD_COMMIT` records.
2. An accepted `LEDGER_OPERATION_COMMIT` contains the complete operation and all legs. It is appended once, after full validation. The transaction rows and player/history indexes are materialized from its signed entries using their already-fixed transaction IDs.
3. The operation ID index is derived by scanning accepted canonical operation commits across the guild's ledgers. It is a lookup projection, not independent proof. It detects cross-ledger ID reuse as well as same-ledger duplicates.
4. `canonical.transactionIndex` maps every operation entry transaction ID to the single containing commit position. A per-dispute operation projection records the accepted operation and request revision; it is rebuildable and is not the accounting authority.
5. A duplicate with the same operation ID and exact canonical payload is a no-effect replay. A different ledger, payload, entry, or request revision is a conflict even if the non-cryptographic content hash collides; compare canonical immutable content as well as the hash.
6. The log must be validated as a contiguous chain before projection repair. A gap, bad root, malformed operation, duplicate ID with different content, or conflicting existing transaction makes the affected ledger explicitly unrecoverable/behind; never invent a balancing entry.

### Operation and commit versions

- Operation `schemaVersion=1`; operation commit `protocolVersion=1`.
- The general SyncV2 envelope remains at its current major/minor unless a later compatibility test demonstrates that a general-envelope bump is required. Advertise a distinct `ledgerOperationCommit=true` capability and require that capability for accepting/sending the new record class.
- Keep the existing canonical container and legacy `AWARD_COMMIT` schema/hash projection unchanged. The new record class has its own canonical hash projection; old hashes are not recomputed.
- Every new operation explicitly includes `guildKey` and `ledgerId`, including `guild-primary`. Optional, non-applicable references use an explicit `false` absent marker; a balance-changing operation requires a real `originalTransactionId`.
- Supported balance types are the current correction actions: single-entry balance correction/refund/revoke/adjustment/historical import, and the two-entry target transfer. Attribution-only correction, if retained, has an explicit zero-entry non-accounting type.

### Ledger selection and original verification

At intent creation, resolve the request's evidence reference to an actual transaction by searching the guild's ledger partitions, not the active pointer. The matching transaction's ledger determines scope. If the request carries a ledger hint, verify that the transaction is actually in that ledger; the hint is not authority. If there is no unique verifiable original transaction, if the transaction is only in an unapproved/archived ledger, or if multiple ledgers contain an ambiguous match, fail closed. A no-original “missing debit” correction is not applied under this feature, per the explicit requirement.

### Permission and coordinator path

All balance-changing submissions pass through `ProtectedActions.Execute` using a dedicated protected ledger-operation action evaluated under existing GM/Officer policy. A non-coordinator Officer may create and relay a typed proposal only; the proposal stores the operation ID, exact payload/hash, request revision, ledger, and proposer identity. The coordinator rechecks the actual proposer's current guild rank, its own current coordinator authority, permissions, original transaction, operation version, and current dispute revision before commit. A proposal acknowledgement means receipt only.

At most one balance-changing operation can be accepted for a given `(guildKey, requestId, requestRevision)`. A replay of that same operation remains idempotent. Another correction requires a reopened/revised request and a new operation ID. Do not reuse the award commit handler's single-transaction business semantics for a multi-leg correction.

### SyncV2 transport, compatibility, and recovery

Use the current guild ledger digest (epoch, last sequence, root hash) and bounded sequence batch catch-up. Add `LEDGER_OPERATION_COMMIT` as a GUILD detail entity. A sequence fetch remains keyed by epoch/sequence; the coordinator responds with the record class actually stored at that position, so existing `AWARD_COMMIT` records remain byte-for-byte readable and new clients can catch up across mixed histories.

Accepted operation commits are sent only by the verified current coordinator and are accepted only for the current guild, approved explicit ledger, current epoch, exact next sequence, matching previous root, recomputed operation and commit hashes, verified coordinator, and supported operation/protocol versions. A duplicate commit does not advance sequence or append another entry. A later sequence marks `LEDGER_GAP`/behind and requests the missing positions. Add an explicit incompatible-operation status; an older client must reject the unknown record without applying familiar legs.

Before a new correction is accepted, the coordinator checks all **known online Dibs peers** (roster-online peers with recent addon presence) for `ledgerOperationCommit=true`. Members with no detected Dibs addon are not treated as protocol participants; missing capability evidence is not a positive compatibility claim for an already-known peer. Offline members are not assumed to have received the commit and catch up only after they return with a compatible client and valid coordinator source.

### Persistence, import, and recovery

No `canonical.schema` reset or rewrite is allowed. Preserve all existing commits, positions, transaction indexes, sequence and root. Add the dispute correction projection additively (guild migration from schema 7 to 8; dispute projection version 3) without converting old `correctionKey` entries. The runtime operation index is reconstructed from the canonical logs.

Recovery runs after the validated DB and domain stores are available, before readiness/UI can report a correction current. If an accepted commit exists but projections are incomplete, rebuild entry transactions, indexes, balances, and the correction accounting projection idempotently. If later dispute revisions exist, do not overwrite them: repair only a provable operation link and surface uncertainty otherwise.

Backups preserve the whole canonical history. Restore uses the existing newer/conflicting-ledger retention rule and validates/rebuilds projections from the restored journal. Full ImportExport remains preview-first and must not become a second canonical writer: identical operation ID/hash is a no-op; conflicting identity is reported/rejected; an unseen commit in a package may enter only through full canonical restore or the normal coordinator-validated SyncV2 chain, never by appending imported transaction rows.

### Behavior and compatibility changes

- Public `Disputes.Resolve`/correction facade signatures remain stable; result data is extended with explicit proposed/accepted/replayed/behind/recovered/persistence-unconfirmed states.
- Balance corrections without a verifiable original transaction now fail; the existing missing-debit test without an original must be changed to assert the documented rejection.
- Correction balance changes require the V2 canonical coordinator path. Before authority/capability is ready, fail with an explicit blocked state rather than writing locally.
- Existing legacy transactions and `correctionKey` values stay unchanged and are only classified by a read-only report.
- Existing `AWARD_COMMIT` records stay readable and are not migrated into operation records. Old clients cannot validate the new record type; known online incompatible Dibs peers block a new correction, while an offline old client remains behind until updated.

## Progressive Implementation Lots

Every lot requires passing focused tests before the next lot is activated. Implement the regression tests first and keep new commit acceptance disabled until the protocol, replay, recovery, and compatibility gates are complete.

### Lot 0 — Invariants, test harness, and reproductions

- **Goal/dependencies**: Freeze the approved operation and wire contracts from the spec; no implementation dependency.
- **Files**: New `tests/unit/ledger_operation_spec.lua`, `tests/integration/canonical_dispute_operation_spec.lua`, `tests/integration/canonical_dispute_sync_spec.lua`; extend `dispute_center_spec.lua`, `b06_distributed_ledger_spec.lua`, and `multi_ledger_sync_spec.lua`.
- **Interfaces**: Test-only scenarios for atomic logical validation, independent SavedVariables clients, result-state shape, and projection cut points. Keep fault injection in the test loader/adapters; do not add a production toggle or mutate `libs`.
- **Prerequisite tests**: Existing dispute, local-ledger, B06, MultiLedger, ProtectedActions, restore, import, migration, and persistence-recovery suites as baseline.
- **Validation/acceptance**: Reproduce the two-write target transfer, failed second leg, ignored compensation result, lost Ledger reason, active-ledger mismatch, duplicate ID, wrong hash, stale request revision, and a canonical commit with missing projections. Assert all relevant balances, transaction IDs, dispute revisions, sequence, root, and statuses.
- **Risk/rollback**: Test-only changes can be reverted independently; no runtime or SavedVariables change.

### Lot 1 — Versioned operation model and pure validation

- **Goal/dependencies**: Define operation-v1, entry rules, explicit absent values, exact canonical serialization, IDs, and supported operation types. Depends on Lot 0.
- **Files**: `Ledger.lua` (private builder/validators and hash helpers), `Disputes.lua` (intent construction only), `tests/unit/ledger_operation_spec.lua`, `contracts/ledger-operation-v1.md`.
- **Interfaces**: Stable operation and entry IDs generated once and persisted with the pending proposal/intent; deterministic ordered entries; schema/version validation; payload hash; no mutation in validation.
- **Prerequisite tests**: Lot 0 payload-schema and action matrix.
- **Validation/acceptance**: Reject unsupported types, malformed or duplicate entry IDs, invalid amount/sign, non-contiguous entries, wrong references, bad hash, empty reason, foreign guild, and invalid absent markers. Verify target transfers have two distinct members and net zero. Compare canonical bytes across insertion/key order.
- **Risk/rollback**: No accepted state yet; remove builder code if tests reveal the contract cannot be represented without changing the approved spec.

### Lot 2 — Ledger journal, idempotence, and projection recovery

- **Goal/dependencies**: Append one complete multi-leg commit and make retries/reconstruction idempotent. Depends on Lot 1.
- **Files**: `Ledger.lua`, `tests/unit/ledger_operation_spec.lua`, `tests/integration/canonical_dispute_operation_spec.lua`.
- **Interfaces**: Explicit-ledger `CommitDisputeOperation`/apply boundary; typed `LEDGER_OPERATION_COMMIT`; guild-wide derived operation-ID index; each entry ID indexes to its one commit; canonical commit hash branch that leaves old `AWARD_COMMIT` hash content unchanged.
- **Prerequisite tests**: All Lot 1 tests and existing B03/B06 commit tests.
- **Validation/acceptance**: One accepted sequence per operation; exact replay produces no new transaction, balance change, or sequence; reused operation ID with changed payload/ledger conflicts. Validate every leg before append. Simulate interruption after journal acceptance and after each projection stage; rebuild to the same balances/indexes without another commit.
- **Risk/rollback**: Before any new operation is accepted, source can be reverted. Once an operation record exists, no downgrade may erase it; only forward recovery is allowed.

### Lot 3 — Original lookup, MultiLedger scope, and migration

- **Goal/dependencies**: Resolve the authoritative ledger from the original transaction and preserve existing SavedVariables. Depends on Lot 2.
- **Files**: `Disputes.lua`, `Ledger.lua`, `MultiLedger.lua`, `Core.lua`, `tests/integration/multi_ledger_sync_spec.lua`, `migration_spec.lua`, `persistence_recovery_spec.lua`, `docs/developer/saved-variables.md`.
- **Interfaces**: Ledger transaction lookup by explicit ledger; safe unique lookup across guild ledgers; `disputes.operationStates` as an additive version-3 projection; guild migration v7→v8 initializes new projection fields but preserves all old correction keys and canonical commits.
- **Prerequisite tests**: Lot 2 plus fixtures with active/view ledger different from the original ledger and malformed/ambiguous original references.
- **Validation/acceptance**: Verified original in a different active ledger succeeds against its own approved ledger; missing, ambiguous, foreign, archived, or unapproved original fails with no mutation. Old SavedVariables migrate without rewriting transactions, old commits, or `correctionKey`.
- **Risk/rollback**: Migration must be staged and backed up by the existing startup mechanism. Any failure leaves the original root intact and read-only/recoverable per existing behavior.

### Lot 4 — ProtectedActions, permission revalidation, and error propagation

- **Goal/dependencies**: Keep a single protected mutation boundary and preserve true rejection causes. Depends on Lots 1–3.
- **Files**: `ProtectedActions.lua`, `Permissions.lua`, `Ledger.lua`, `tests/integration/protected_actions_spec.lua`, `protected_actions_matrix_spec.lua`.
- **Interfaces**: New protected ledger-operation action mapped to the existing GM/Officer administrative policy; all legs reach the same operation command; operation result explicitly distinguishes a recorded proposal from an accepted commit.
- **Prerequisite tests**: Lot 0 unauthorized actor/failure cases and Lot 2 operation validation.
- **Validation/acceptance**: GM/Officer succeeds only through `ProtectedActions`; non-admin, stale/unknown actor, sandbox, unavailable Ledger, and malformed operation are rejected. The actual Ledger reason is returned unchanged; no success-shaped transaction is returned on rejection.
- **Risk/rollback**: No direct caller migration until the protected action has complete tests. Existing public adjustment actions retain their prior behavior outside this feature.

### Lot 5 — Governance proposal, current coordinator, and dispute revision

- **Goal/dependencies**: Preserve non-coordinator Officer work without any local accounting mutation. Depends on Lots 1–4.
- **Files**: `Governance.lua`, `Disputes.lua`, `ProtectedActions.lua`, `OfficerUI.lua`, `tests/integration/award_proposal_relay_spec.lua` (regression), `canonical_dispute_operation_spec.lua`.
- **Interfaces**: Typed operation proposal over the existing targeted route using distinct `LEDGER_OPERATION_PROPOSAL` and `LEDGER_OPERATION_PROPOSAL_ACK` record classes, with proposal ID, full operation, exact hash, request revision, ledger, entries, and verified proposer. Governance alone persists the pending intent and allocates stable IDs; retries/reload resume that record. Coordinator-only acceptance and review action; receipt acknowledgment is not acceptance.
- **Prerequisite tests**: Independent coordinator/officer DB states; proposer loses Officer rank; stale/reopened request; two distinct proposals at one request revision.
- **Validation/acceptance**: Non-coordinator proposal changes no ledger balance or sequence and retains identical proposal/operation/entry IDs and payload across retry/reload. Coordinator revalidates proposer role, authority epoch, own role, request revision, and original transaction. Preserve the existing 100-record Governance capacity and five relay attempts; capacity/retry exhaustion is explicit and never evicts a proposal. Only one operation per request revision is accepted. No wall-clock TTL or automatic terminal-record deletion is introduced.
- **Risk/rollback**: Unaccepted proposals are non-accounting state and may remain pending after a rollback. Do not remove them silently; expose a blocked/update-required reason.

### Lot 6 — SyncV2 commit transport, capability gate, and gap recovery

- **Goal/dependencies**: Replicate the entire operation as one canonical commit while preserving old award history. Depends on Lots 1–5.
- **Files**: `SyncV2.lua`, `Ledger.lua`, `Governance.lua`, `tests/integration/canonical_dispute_sync_spec.lua`, `b06_distributed_ledger_spec.lua`, `multi_ledger_sync_spec.lua`, `docs/developer/sync-protocol.md`, `contracts/syncv2-ledger-operation-commit.md`.
- **Interfaces**: New `ledgerOperationCommit=true` capability; distinct targeted WHISPER proposal/ack entities and coordinator dispatch; new GUILD commit detail entity and receiver. Immediately after accepting one canonical position, the coordinator announces the complete `LEDGER_OPERATION_COMMIT` and the updated ordinary ledger digest. Sequence fetch returns the record class actually stored at that position. Existing `AWARD_PROPOSAL`/`AWARD_COMMIT` records and handlers remain unchanged.
- **Prerequisite tests**: Lot 5; existing ordered commit, duplicate, gap, alternate-ledger, epoch, and wrong-root tests.
- **Validation/acceptance**: Three independent production-code clients converge on operation/entry IDs, balances, epoch, sequence and root. Initial announcement and subsequent digest/fetch are tested separately. Duplicate and out-of-order delivery is harmless/behind. Wrong sender, epoch, ledger, payload, hash, capability, or chain root makes no accounting or dispute mutation. No local fallback occurs.
- **Risk/rollback**: Do not enable operation acceptance before this lot and recovery pass together. Old offline clients remain behind; no downgrade is allowed after a new commit.

### Lot 7 — Recovery diagnostics and read-only historical report

- **Goal/dependencies**: Make post-acceptance interruption and pre-feature ambiguity observable without compensation. Depends on Lots 2, 3, and 6.
- **Files**: `Ledger.lua`, `Disputes.lua`, `SyncV2.lua`, `OfficerUI.lua`, `enUS.lua`, `frFR.lua`, `canonical_dispute_operation_spec.lua`, `canonical_dispute_sync_spec.lua`, `dispute_center_spec.lua`.
- **Interfaces**: Deterministic recovery scan over explicitly categorized sources: new operation commits, unchanged historical award commits, and preserved legacy-local transaction rows with no canonical record. Canonical-backed transaction rows, balances, histories, indexes, and correction status are projections and are not counted again. Surface specific incomplete-projection, gap, index mismatch, ID conflict, and unrecoverable-history states; keep read-only legacy report categories `complete`, `partial`, `ambiguous`, `local-only`, `unverifiable`.
- **Prerequisite tests**: Saved snapshots for each interruption boundary; mixed history containing legacy local rows, old `AWARD_COMMIT`, new operation commits, and old partial/ambiguous corrections; independent state for more than one ledger; expected balances calculated without the production replay helper.
- **Validation/acceptance**: Recovery changes only rebuildable projections and does not append commits or modify historical transactions; each unique legacy-local row contributes once, canonical-backed rows are not double-counted, and conflicting duplicate IDs stop recovery. The independent oracle agrees with recovered balances. Report generation leaves byte-equivalent SavedVariables and disputes; later dossier revisions are never overwritten.
- **Risk/rollback**: When evidence cannot establish a safe projection, keep the source records, mark unresolved, and require an explicit separately audited repair operation.

### Lot 8 — Backup, restore, import, and compatibility

- **Goal/dependencies**: Preserve operation journals across snapshots without creating a second canonical writer. Depends on Lots 2, 3, and 7.
- **Files**: `Backup.lua`, `ImportExport.lua`, `Core.lua`, `backup_sync_restore_spec.lua`, `backup_import_profiles_spec.lua`, `migration_spec.lua`, `persistence_recovery_spec.lua`, `docs/developer/saved-variables.md`.
- **Interfaces**: Preview reports same-ID/same-hash no-op, conflicting ID/hash/ledger conflict, missing operation history, or a valid whole-history restore. Full import cannot directly append unseen canonical operation transactions.
- **Prerequisite tests**: Old backup without operations; backup with operations; projection-missing backup; same ID/same hash; conflicting ID/hash; old/newer ledger sequence and root.
- **Validation/acceptance**: Restore twice, repeated import, and restore over a newer/conflicting local chain never double-apply. Legacy transaction IDs/content remain unchanged. Unseen operations become accepted only through a verified complete restore or the coordinator-validated SyncV2 chain.
- **Risk/rollback**: A conflicting or incomplete snapshot is blocked/quarantined with preview diagnostics; preserve the safety snapshot and current ledger.

### Lot 9 — Dispute Center/UI integration, end-to-end regression, and activation

- **Goal/dependencies**: Connect the user flow to accepted operations and prepare a staged release. Depends on Lots 0–8.
- **Files**: `Disputes.lua`, `OfficerUI.lua`, `enUS.lua`, `frFR.lua`, `dispute_center_spec.lua`, `canonical_dispute_operation_spec.lua`, `canonical_dispute_sync_spec.lua`, focused integration suites, `docs/developer/architecture.md`, `docs/developer/sync-protocol.md`, `docs/developer/saved-variables.md`, changelog and TOC version during the later implementation/release.
- **Interfaces**: Keep public correction facade signatures; show `proposed`, `accepted in this session`, `rejected`, `behind/incompatible`, `recovered after reload`, and `persistence unconfirmed` distinctly. Add a read-only historical report projection. Never label send/receipt as guild-wide acceptance or disk durability.
- **Prerequisite tests**: All focused suites, legacy behavior tests updated for the explicit missing-original rejection, and no unresolved operation recovery status.
- **Validation/acceptance**: All 43 FR rows in [traceability.md](./traceability.md) pass their mapped test/acceptance evidence. Existing awards, MultiLedger views, backup guards, permissions, dispute privacy, and old `AWARD_COMMIT` test vectors remain green.
- **Risk/rollback**: Before any operation commit, feature acceptance may be disabled and code reverted. After the first commit, rollback is forward-only: keep the journal, do not downgrade to code that cannot validate it, and publish a compatible recovery/update path.

## Activation Gates, Non-Independent Steps, and Residual Risks

### Runtime and release activation gates

1. Release-source default is disabled. A release owner enables the feature only after the evidence gates below; CI/Retail completion is never represented as a runtime-checkable condition.
2. One runtime readiness gate protects every direct/protected writer, coordinator acceptance route, and SyncV2 receiver before accounting mutation. It checks the explicit approved ledger, verified current coordinator/authority, completed local recovery, contiguous validated sequence/root, supported protocol, and required online-peer capability.
3. No user action can submit a balance-changing operation until all legs, payload hash, original transaction and ledger, request revision, current permissions, and operation/entry ID conflict checks pass.
4. Unknown/false runtime readiness rejects with an explicit reason and no accounting effect, local write fallback, or familiar-leg projection. Capability advertisement must not claim support while the release gate is disabled.
5. The release owner records focused/full tests, backup/restore and compatibility checks, and separate Retail multi-client evidence before enabling the release flag. Tests may use an isolated test-only opt-in; it must not be a production SavedVariables/UI switch.
6. A completed send or acknowledgment is never evidence of all-member convergence or SavedVariables disk durability.

### Steps that cannot be activated independently

- The canonical operation validator, idempotence index, and projection recovery must ship together; otherwise accepted records may be unreplayable or double-applied.
- The new proposal type and coordinator UI must ship with the receiver's sender/role/revision checks; otherwise a proposal can be misrepresented as a commit.
- The SyncV2 capability gate and operation commit receiver must ship together; otherwise old clients can silently diverge or new clients can accept unvalidated records.
- The default-off runtime gate must cover sender, coordinator, and receiver paths and ship with recovery readiness; adding a test-only or release flag without wiring every entry point is not a safe partial release.
- Backup/import preview rules must ship before enabling import of packages containing the new record class; no direct import writer is permitted.
- The user-facing result states and diagnostic reason propagation must ship with the commit path; otherwise a proposal, rejection, or persistence-unknown result can be reported as a completed correction.

### Residual risks

- The existing canonical hash is a deterministic content identity, not cryptographic authentication. Sender/coordinator authority is validated separately, and exact canonical content is compared on idempotent replay to detect hash collisions.
- WoW does not expose a durable flush acknowledgment. A crash can lose an in-session accepted SavedVariables write; only a subsequent reload can verify retention.
- An offline incompatible client cannot converge until updated. Its expected state is explicitly behind, not silently partial.
- Old partial corrections may remain inherently ambiguous. The report will classify evidence but will never infer that a `correctionKey` alone proves completion.
- Mixed-history balances can only be reconstructed when every row has one unambiguous source category. Conflicting duplicate transaction IDs or an unassignable historical row require an explicit unrecoverable state, not a heuristic repair.
- A corrupt or missing accepted journal/chain cannot be repaired by balancing heuristic; it needs an explicit audited operation or administrator recovery decision.
- The feature intentionally blocks corrections with no verifiable original ledger transaction. This can prevent the old “missing debit” workflow from applying when no original transaction exists; the UI must explain the reason and preserve the request for review.

## Complexity Tracking

No constitution violation or new architectural project is proposed. The typed operation record, runtime ID index, recovery scan, and one SyncV2 entity are necessary to meet the specified atomic-logical-operation, retry, cross-ledger, and offline-convergence requirements; reusing independent transaction appends or a local `correctionKey` was rejected because it cannot satisfy those requirements.
