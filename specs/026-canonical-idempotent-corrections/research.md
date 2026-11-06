# Research: Canonical Ledger Operations & Idempotent Dispute Corrections

**Status**: Planning research complete; evidence is from the current repository and approved RF-0012 specification. No implementation or external dependency research is required.

## Evidence reviewed

- [RF-0012 assessment](../../.specify/bugs/rf-0012-ledger-integrity/assessment.md)
- [Audit index](../../docs/code-audit/INDEX.md), [dependency map](../../docs/code-audit/DEPENDENCIES.md), [Spec Kit backlog](../../docs/code-audit/SPECKIT-BACKLOG.md), and [audit progress](../../docs/code-audit/PROGRESS.md)
- [Feature spec](./spec.md), [requirements checklist](./checklists/requirements.md), and [constitution](../../.specify/memory/constitution.md)
- [Architecture](../../docs/developer/architecture.md), [SavedVariables contract](../../docs/developer/saved-variables.md), and [SyncV2 contract](../../docs/developer/sync-protocol.md)
- `Ledger.lua`, `Disputes.lua`, `MultiLedger.lua`, `ProtectedActions.lua`, `Permissions.lua`, `Governance.lua`, `SyncV2.lua`, `Backup.lua`, `ImportExport.lua`, `Core.lua`, `OfficerUI.lua`, and focused existing test suites

The current worktree is already dirty on branch `dev`. Existing changes and audit annotations are outside this planning task and must be preserved. The spec-directory `feature.json` requested in the original source list is absent; the existing `.specify/feature.json` pointer selected the correct feature and was used by setup. No feature branch was created or switched to.

## Findings and decisions

### 1. Extend the existing canonical commit journal

- **Decision**: Store an accepted correction as one new `LEDGER_OPERATION_COMMIT` at one `(ledgerEpoch, sequence)` position in the target ledger's existing `canonical.commits`. Keep one shared sequence/hash chain with legacy `AWARD_COMMIT` records.
- **Evidence**: `Ledger.ApplyAwardCommit` validates sender/coordinator, ledger, epoch, sequence, previous hash, transaction hash and transaction before changing projections. `SyncV2` digests `nextSeq`/`rootHash`, batches detail fetches by sequence, marks gaps behind, and sends canonical details only from the current coordinator.
- **Rationale**: This reuses the only path that already provides sequence, previous-root checks, coordinator authority, duplicate-position detection, and catch-up. A second correction journal or per-leg commit would fork existing convergence behavior.
- **Alternatives rejected**: Keep using `CommitLocalTransaction` and add `correctionKey` dedupe; append one commit per transfer leg; create a separate correction chain. Each can expose partial effects or diverge from `LEDGER_DIGEST` catch-up.

### 2. Separate canonical acceptance from materialized projections

- **Decision**: Treat the canonical commit log as the source of truth for new corrections. Derive an operation-ID lookup across guild ledgers, transaction-to-commit lookup, balances/history indexes, and the dispute correction-status projection from accepted commit records.
- **Evidence**: `Ledger.appendValidated` writes transaction, award/evidence indexes, player transaction lists and cached allocation/balance separately. Current `ApplyAwardCommit` validates a single transaction before projection, but it does not provide a multi-entry recovery journal. `Disputes` writes correction metadata and request status after calling the ledger and can currently append two legs separately.
- **Rationale**: If execution stops after canonical acceptance, replay can repair missing projections without creating another operation. Indexes or request caches cannot be independent proof of accounting acceptance.
- **Alternatives rejected**: Make `state.corrections` or the operation index the source of truth; update balances directly; compensate a partial append. All are weaker than an accepted immutable chain record.

### 3. Preserve logical atomicity without claiming disk atomicity

- **Decision**: Prepare and validate the operation and all detached transaction rows first. Canonical acceptance is the single logical boundary; projections are idempotently completed from the accepted record. Errors before acceptance leave all accounting state unchanged; errors after acceptance leave a recoverable accepted record or an explicit history conflict.
- **Evidence**: Current Lua functions mutate SavedVariables tables sequentially. WoW owns the eventual SavedVariables save; there is no durable transaction/flush API in this codebase.
- **Rationale**: This is the strongest supportable contract and matches FR030/FR037. “Append all Lua tables successfully” must not be described as an atomic durable disk commit.
- **Alternatives rejected**: Claim a multi-table Lua mutation is a disk transaction; attempt automatic reversal after a failed later assignment; report success from an in-memory append as saved.

### 4. Use stable IDs plus exact content checks

- **Decision**: Create operation and leg transaction IDs once at intent confirmation, store the exact operation with its pending proposal/intent, and reuse it on retry, relay, reload, commit delivery, recovery and backup. Hash canonical immutable fields and ordered entries; compare exact canonical content as well as hash on replay.
- **Evidence**: `Ledger` already has deterministic type-tagged/key-sorted serialization and a 31-bit content hash, explicitly documented as content identity and not authentication. `correctionKey` is only transaction metadata; current corrections do not pass fixed transaction IDs to the ledger.
- **Rationale**: Stable IDs make retries meaningful. Exact content comparison avoids treating a 31-bit hash collision as proof of identity. Authority still comes from verified sender and roster checks, not the hash.
- **Alternatives rejected**: Recompute random transaction IDs per retry; rely on `correctionKey`; use the content hash as a signature.

### 5. Resolve and pin the original ledger; never use the selected ledger

- **Decision**: Resolve the referenced original transaction across the guild's ledger partitions, then bind the operation to the one approved ledger that actually contains it. A stored request ledger hint must be verified; the active/view ledger is never a fallback. Ambiguous, unapproved, archived, foreign or missing originals fail closed.
- **Evidence**: `Disputes.findTransaction` currently calls award lookup without a ledger ID under `pcall`, then searches `Ledger.GetAllTransactions()` without a target ledger. `Ledger.CommitLocalTransaction` and canonical manual adjustment default to the active ledger. `MultiLedger` keeps `db.ledger` as an active-ledger compatibility pointer.
- **Rationale**: The transaction being corrected, not a UI selector or unverified payload claim, determines scope.
- **Alternatives rejected**: Add `ledgerId` from `GetActiveLedgerId()`; trust a proposal's unverified ledger; search only the currently selected ledger.

### 6. Treat missing-original corrections as explicitly rejected

- **Decision**: Any balance-changing operation requires a verifiable original transaction in the approved operation ledger. The historical “missing debit” path with no original row is rejected without mutation; do not infer that an award reference is a Dibs transaction.
- **Evidence**: The feature spec's FR004, user scenarios, assumptions, and prior user decision all require failure when the original transaction cannot be verified. Existing `dispute_center_spec.lua` contains a missing-debit correction with no linked transaction, so that test's expected result must change.
- **Rationale**: The approved business rule is explicit; implementing the old local append would violate the new accounting invariant.
- **Alternatives rejected**: Treat `evidenceId`, `awardRef`, or `correctionKey` as substitute proof; ask the coordinator to guess an entry; silently retain a local-only path.

### 7. Keep ProtectedActions and distinguish proposer from accepter

- **Decision**: Add a single protected operation submission action under the existing GM/Officer policy. Record a non-coordinator Officer's full operation as a typed proposal; the coordinator separately revalidates proposer identity/rank, current request revision, original transaction and its own coordinator authority before acceptance. The accepted commit identifies both proposer and accepting coordinator.
- **Evidence**: `ProtectedActions.Execute` is the existing mutation boundary. Existing `Governance.RecordAwardProposal` and `ReceiveRelayedProposal` provide persisted pending proposals, targeted relay, actual roster-role checks and duplicate proposal checks, but their current payload is award-shaped and commits a single `DIB_USED`.
- **Rationale**: Reuse the authorized relay/retry/ack boundary and sender validation without routing corrections through award-specific accounting or leaking a dispute dossier into governance records.
- **Alternatives rejected**: Have an Officer directly append locally; use two protected `ledger.adjust` calls; reuse `AWARD_PROPOSAL`'s single-award commit semantics unchanged; treat proposal receipt as acceptance.

### 8. Add a typed SyncV2 record and capability, keep old commits intact

- **Decision**: Add `ledgerOperationCommit=true` to SyncV2 capabilities and `LEDGER_OPERATION_COMMIT` to the GUILD detail allowlist. Use the existing `LEDGER_DIGEST` epoch/sequence/root and sequence-based detail fetch. The coordinator returns the type actually stored at a requested position. Keep legacy `AWARD_COMMIT` records and hash projection unchanged.
- **Evidence**: Current `SyncV2` has bounded GUILD details, a 4-commit catch-up batch, explicit peer capability tracking, current-coordinator checks, and `LEDGER_GAP`/root-conflict state. `sync-protocol.md` states canonical commits are not member-relayed.
- **Rationale**: The new entity is explicit and versioned as required, while the request sequence path remains useful for mixed historical chains.
- **Alternatives rejected**: Change the general envelope major version for an additive feature schema; make every old `AWARD_COMMIT` look like an operation; permit member relays; local fallback on a client without the new capability.

### 9. Gate known online clients; let offline compatible clients catch up

- **Decision**: Before coordinator acceptance, require every known online Dibs peer required for guild ledger synchronization to advertise the operation capability. Keep a new/old or unsupported peer visibly incompatible. Offline peers are not credited with receipt; they catch up after reconnect only when the source and client are compatible.
- **Evidence**: `Sync.GetPeerStatuses` joins roster-online state with recent add-on presence and protocol capability. Existing addon family compatibility accepts same major/minor versions, so family compatibility alone does not prove operation support.
- **Rationale**: A separate feature capability is necessary to avoid silent same-family partial acceptance. Unknown add-on presence is not treated as a compatible claim.
- **Alternatives rejected**: Assume every 0.8.x client understands the new record; broadcast and report success; count offline members as synchronized.

### 10. Rebuild accepted operations, never heuristically repair old partials

- **Decision**: Verify the contiguous canonical chain and idempotently rebuild missing operation transaction rows, transaction indexes, balances, and operation status. Keep later dispute revisions intact. Generate a read-only historical report by correlating available transactions, IDs, references and dispute metadata; do not promote `correctionKey` into evidence of acceptance.
- **Evidence**: The RF-0012 audit records ignored compensation results and absent stable IDs; no current recovery function can distinguish a partial target transfer from a completed multi-step effect.
- **Rationale**: Accepted operation data can be deterministically replayed; pre-feature partials lack a canonical operation and can only be classified, not repaired safely.
- **Alternatives rejected**: Append a guessed balancing transaction; rewrite old entries into a new operation; mark all matching `correctionKey` pairs complete.

### 11. Use additive SavedVariables and conservative package import

- **Decision**: Bump guild schema 7→8 and dispute projection schema 2→3 only to initialize new operation-status projection fields; preserve all existing `canonical.commits`, positions, transaction indexes, sequence/root, corrections, and transaction records. Keep the canonical container schema and portable envelope unchanged. Backups carry the new journal. Import recognizes exact duplicates and conflicts but does not directly append unseen canonical history.
- **Evidence**: `Core.lua` uses staged guild migration and backs up before migration; `Backup.Restore` keeps a newer/equal-conflicting local canonical ledger; full `ImportExport.Apply` currently refuses a new `LOCAL_CANONICAL` transaction as a second durable write path.
- **Rationale**: A migration that preserves canonical entries is necessary for the new projection; using the existing import path as an authority bypass would undermine the coordinator chain.
- **Alternatives rejected**: Reset or rewrite the canonical container; infer operation IDs for legacy transactions; import canonical transactions as local writes; downgrade a newer chain.

### 12. Expose operational state, not false durability

- **Decision**: Extend Officer UI results with explicit rejected, proposal-pending, accepted-in-session, behind/incompatible, recovered-after-reload and persistence-unconfirmed states. Add a read-only historical reconciliation view and localized English/French messages.
- **Evidence**: `OfficerUI` currently displays correction success by transaction reference and already has pending coordinator proposal rows; the UI rules require explicit empty/error states and Midnight patterns. WoW offers no disk flush confirmation.
- **Rationale**: A proposal is not a correction, and an in-memory SavedVariables update is not proof of disk persistence or guild-wide receipt.
- **Alternatives rejected**: Treat any `result.ok` as final accounting success; display “saved” immediately; hide legacy ambiguity.

## Decisions and clarification status

No `/speckit-clarify` blocker remains: the missing-original behavior, coordinator-only acceptance, protocol capability, online compatibility gate, legacy handling, and persistence limitation are explicit in the approved spec.

Two conservative implementation interpretations must remain visible in the plan and tests:

1. **Full ImportExport** may report an exact existing operation as a no-op and a conflicting ID/hash as a conflict, but an unseen operation cannot be appended directly from a package; it must be restored as a validated whole canonical history or arrive through SyncV2.
2. **Known online participant** means an actually roster-online Dibs peer with recent protocol presence. A player with no detected Dibs addon is not a protocol participant, and an already-known peer with missing capability is not assumed compatible.

Neither interpretation changes an explicit functional requirement; both preserve the repository's existing authority and import boundaries.

## Design corrections from A1–A9 review

The following evidence and decisions refine the earlier design and supersede
any less-specific wording above. They are planning constraints, not claims
that implementation or release gates have passed.

### A1 — Runtime activation is separate from release evidence

- **Decision**: Keep canonical correction writes disabled by default in the
  release source. A single readiness check must guard every direct/protected
  writer, Governance acceptance, and SyncV2 receiver before accounting state
  changes. It verifies only runtime-observable state: explicit approved
  ledger, local recovery completion, current verified authority/coordinator,
  a contiguous valid epoch/sequence/root, and required online-peer capability.
- **Release boundary**: CI results and Retail validation are evidence for the
  release owner, not facts the Lua client can inspect. A build remains
  disabled until those gates are recorded; test-only enablement must be
  fixture-scoped and cannot be a production SavedVariables or UI setting.
- **Failure behavior**: Disabled, unknown, or incomplete readiness returns a
  diagnostic and changes no accounting projection. There is no local fallback.

### A2–A3 — Complete SyncV2 proposal and commit lifecycle

- **Evidence**: The existing `SyncV2` GUILD detail allowlist carries
  `AWARD_COMMIT`; Governance's relayed proposal receiver requires
  `recordClass == "AWARD_PROPOSAL"`. The current allowlist/dispatcher therefore
  does not transport an operation proposal or commit by merely adding the
  payload schema.
- **Decision — proposal**: Add distinct targeted WHISPER record classes
  `LEDGER_OPERATION_PROPOSAL` and `LEDGER_OPERATION_PROPOSAL_ACK`, their
  allowlist/dispatch paths, stable proposal ID, exact payload replay, explicit
  receipt/rejection statuses, and Governance deduplication. Keep
  `AWARD_PROPOSAL` unchanged. Preserve the existing Governance limits of 100
  persisted proposal records and five relay attempts; do not invent time-based
  expiry or silently evict records.
- **Evidence — commit**: `Ledger` currently announces `AWARD_COMMIT`; SyncV2
  digest and detail fetch have existing sequence-oriented behavior but
  record-class handling is award-specific.
- **Decision — commit**: Immediately announce the accepted full
  `LEDGER_OPERATION_COMMIT` on the GUILD detail route, publish the updated
  `LEDGER_DIGEST`, validate exact duplicates through the production receiver,
  and make sequence fetch return the actual record class stored at that
  position. Catch-up is recovery, not a substitute for the required initial
  announcement.

### A4 — Mixed-history recovery has explicit source categories

- **Decision**: A new correction is authoritative only in its verified
  `LEDGER_OPERATION_COMMIT`; an old award remains authoritative only under its
  unchanged `AWARD_COMMIT` contract; a pre-feature local transaction with no
  canonical record remains preserved legacy evidence and is counted once. For
  canonical-backed effects, transaction rows, balances, histories, and indexes
  are projections and must not be counted again. Old corrections without a
  provable accepted commit remain read-only report cases; no missing leg or
  intent is inferred.
- **Test oracle**: Mixed-history fixtures specify starting allocations and
  expected effects independently as the unique accepted commit entries plus
  unique retained legacy-local rows. A comparison of two replays using the
  same production algorithm is not an independent correctness oracle. Conflicting
  duplicate transaction IDs stop recovery.

### A5–A6 — Tests must execute production code and the stated retry threshold

- **Evidence**: `tests/helpers/distributed_ledger_fixture.lua` models a
  distributed ledger but does not execute the Dibs production commit/receive
  path. The existing `tests/helpers/load_addon.lua` also uses shared Lua global
  loading behavior and must be verified/adapted before it can prove separate
  addon environments.
- **Decision**: The client harness must instantiate the real Ledger and
  SyncV2 dispatch/receiver code in isolated Lua environments with distinct
  SavedVariables and a serialized message bridge. If the present loader cannot
  do this, adapting the loader is an explicit foundational task. Tests compare
  each client's saved state and independently computed expected balances.
- **Acceptance threshold**: SC-001 requires exactly 100 retries/duplicate
  deliveries through the real production acceptance/replay route; assert one
  canonical commit, stable operation/entry IDs, and unchanged balance/sequence
  after the first acceptance. Include a reinitialized client retry where the
  loader can support it.

### A7–A8 — Task order and existing library integrity guard

- **Task dependency**: T039 depends on T038 as declared in its task metadata.
  They must not be shown as parallel; T038 and T040 may proceed independently
  after T035, then T039 follows T038 and T030. The dependency graph and
  parallel examples must agree with the task metadata.
- **Evidence**: The repository already has
  `.github/skills/lua-code-audit/scripts/audit_guard.py` and
  `docs/code-audit/BASELINE.json` at schema version 2. Its `verify` command
  checks both the whole Lua file baseline and `protected_libraries.files`;
  output distinguishes `LUA` content changes from `PROTÉGÉ` library changes.
- **Decision**: Use the existing non-mutating
  `python .github/skills/lua-code-audit/scripts/audit_guard.py verify` before
  and after each future implementation phase and at final review. Never call
  `capture`/`capture-libraries`, replace the active baseline, create a
  temporary `libs` manifest, or auto-restore files for this feature. Any
  `PROTÉGÉ` delta is a hard stop. Expected `LUA` deltas must be limited to the
  current task's declared source paths; the guard's nonzero exit must not be
  called a pass or ignored. Preserve initial `git status --short` so pre-existing
  dirty files are distinguishable; unresolved/unattributed differences block
  the phase.

### A9 — One persisted owner for proposal identity and retry

- **Decision**: Governance is the only persisted owner of an unaccepted
  intent, including coordinator-originated corrections. It allocates all
  stable IDs and stores the exact operation before relay/acceptance. Ledger
  validates caller-supplied operations and Disputes projects only accepted
  status; neither stores a second pending copy. Exact retries/resume use the
  persisted proposal ID and payload. Startup never auto-accepts.
- **Lifecycle**: There is no time-based TTL in the current proposal behavior,
  so none is introduced. Revision/authority/epoch/capability changes make a
  proposal explicitly `STALE` or `REJECTED`; terminal records remain retained.
  A reopened revision needs a new identity. Preserve the current 100-record
  capacity and five relay-attempt limits with explicit capacity/exhaustion
  errors, never silent eviction.
