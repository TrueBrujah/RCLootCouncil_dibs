# P1 Remediation Plan

**Status:** Canonical architecture plan, revised after
[`P1_Architecture_Challenge.md`](P1_Architecture_Challenge.md).  
**Scope:** Documentation and architecture only. This plan authorizes no source
change by itself. B00 has not started.  
**Decision authority:** The binding decisions are recorded in
[`P1_Architecture_Decision_Record.md`](P1_Architecture_Decision_Record.md).

## Executive Summary

The P1 audit remains valid, but its original coordinator proposal has been
replaced. The addon will not treat an epoch number and local sequence as proof
that a partitioned coordinator was fenced. Instead, canonical multi-raid ledger
operation uses a GM-governed, single-coordinator model with two transition paths:

- a **normal handoff**, closed by the predecessor and bound to its final ledger
  root; and
- a **forced recovery takeover**, which enters `RECOVERY_PENDING`, prohibits
  canonical Dibs consumption, reconciles peer evidence, and begins a new epoch
  only from a GM-approved baseline.

This deliberately favors data integrity over availability. If the coordinator
is unavailable, Pre-Dibs and attributable award evidence may be recorded, but
no client other than an active coordinator may produce a canonical ledger debit.

The other architecture decisions are now aligned with that rule:

- `policyRevision` and `ledgerEpoch` are independent;
- GM-only governance establishes who can alter authority, the coordinator,
  cutover, and baseline;
- operational rules are separately revisioned and officer-editable only after
  governance exists;
- full Name-Realm is the wire identity, with immutable event snapshots,
  GM-reviewed aliases, and optional GUID witnesses;
- GUILD carries bounded notifications/digests, WHISPER carries authoritative
  details, and clients never skip ledger gaps;
- the first canonical epoch begins only after GM-led legacy-baseline
  reconciliation and `V2_ENFORCED` cutover;
- RCLootCouncil is optional evidence input, never the core ledger authority or
  a required liveness dependency.

## Binding Architecture Baseline

### 1. Identity and authority

`Name-Realm`, normalized only for comparison, is the only player identity used
on the addon-message wire. Every canonical transaction and history entry stores
an immutable identity snapshot: member key, display Name-Realm at event time,
and optional GUID witness when locally available through WoW or RCLootCouncil.

An optional GUID never silently replaces the wire key. Name/realm changes are
GM-reviewed alias records; an addon must never infer an alias from a matching
short name or a partial GUID. A short name that is not uniquely resolved returns
an explicit ambiguity result.

The current guild roster is revalidated immediately before every protected
command. A roster change invalidates authority caches. Sender/rank validation is
an authorization signal from WoW's transport and roster, not cryptographic proof
that a client is honest or unmodified.

### 2. Guild policy: governance versus operational policy

Guild policy is not `db.settings`. Local settings remain language, layout,
debugging, and other presentation-only choices.

**Governance policy** is GM-only and controls:

- initial policy adoption;
- officer authority and policy-writer rules;
- coordinator identity and ledger epoch;
- normal coordinator handoff and forced recovery;
- protocol cutover;
- canonical legacy/recovery baseline adoption.

Every governance record has a class, guild scope, revision, parent
revision/hash, author Name-Realm, timestamp/audit metadata, and canonical
content hash. A same-revision/different-hash record is a conflict, never a
last-write-wins update. A receiver without fresh GM roster validation does not
adopt governance.

**Operational policy** is an allowlisted, revisioned record. After governance
exists, authorized officers may change settings such as Pre-Dib mode, request
availability, debt policy, and other explicitly operational rules. Operational
policy changes increment `policyRevision` only. They never alter
`ledgerEpoch`, coordinator identity, governance authority, baseline, or
protocol mode.

New installations and upgraded legacy databases begin in `POLICY_UNINITIALIZED`.
The Guild Master must explicitly adopt the initial governance and operational
policy. No first client and no officer automatically promotes local settings to
revision 1.

### 3. Canonical ledger command and records

The core service is independent of RCLootCouncil:

```text
CommitDibUse(coordinatorContext, awardEvidence)
```

Only an `ACTIVE(E)` coordinator may invoke the canonical command. It validates
the current governance record, coordinator Name-Realm, identity snapshot,
current baseline/parent, exact next sequence, previous event hash, content hash,
debt policy, balance/reservation, and idempotency before appending.

New canonical transaction identity is scoped by guild, season, epoch and
sequence. Exact duplicate content is an idempotent replay; identical ID or
sequence with different canonical content is a conflict. Legacy transaction IDs
and values are never rewritten or resequenced.

When a coordinator is unavailable, the result is
`COORDINATOR_UNAVAILABLE`. The addon may save a non-canonical `AWARD_PROPOSAL`
with attributable evidence and `PENDING_RECONCILIATION` status, but it must not
reserve a balance, create `DIB_USED`, or consume a Dib locally. Only an active
coordinator can convert verified evidence into `AWARD_COMMIT`.

### 4. Fenced coordinator transition state machine

`ledgerEpoch` changes only through a governance record. It is distinct from
`policyRevision`.

| State | Canonical ledger behavior | Entry and exit rule |
|---|---|---|
| `ACTIVE(E)` | Current coordinator may append only the exact next sequence with matching previous hash. | Enter from first approved baseline or completed handoff/recovery. |
| `HANDOFF_CLOSING(E)` | No new award commit after closure is published. | Old coordinator publishes predecessor epoch, final sequence and ledger root hash. |
| `ACTIVE(E+1)` normal | New coordinator starts only from the exact closed predecessor tuple. | GM governance record binds `{previousEpoch, finalSeq, rootHash}`. |
| `RECOVERY_PENDING` | No canonical Dibs consumption; requests/proposals may continue. | Use when predecessor closure cannot be verified. |
| `ACTIVE(E+1)` forced | Coordinator writes only from a GM-approved reconciled baseline. | Governance record binds recovery baseline hash and audit decision set. |

Normal handoff requires predecessor closure with:

- previous epoch;
- final sequence; and
- ledger root hash.

Receivers reject predecessor events beyond the closed final sequence and reject
new-epoch events whose parent does not exactly match the closure tuple.

Forced takeover is not immediate promotion. It enters `RECOVERY_PENDING`,
collects bounded peer evidence, requires GM reconciliation, records a baseline
hash and include/exclude/compensating-adjustment decisions, and then creates the
new active epoch. A late excluded old-epoch event is retained as **orphaned
evidence**; it is never appended automatically to the canonical ledger.

This design prevents two competing *future canonical* branches after takeover.
It cannot undo an irreversible award that a partitioned old coordinator made
before recovery. That award becomes reconciliation evidence rather than a reason
to accept another automatic debit.

### 5. Synchronization, ordering, and anti-entropy

GUILD messages are bounded notifications only. WHISPER carries requested,
complete, hash-checked detail. No live loot candidates, votes, or RC responses
are synchronized.

| Entity | GUILD digest | Authoritative detail source | Apply rule |
|---|---|---|---|
| Governance | revision, parent hash, content hash | Current live GM | Direct known parent only; otherwise fetch chain. |
| Operational policy | revision, parent hash, content hash | Current authorized writer or GM | Higher valid revision only; same revision/different hash conflicts. |
| Ledger | epoch, contiguous last sequence, root hash | Active coordinator; GM-approved recovery archive | Exact `nextSeq` and matching `previousHash` only. |
| Pre-Dib request | request ID, revision, terminal marker/hash | Owner for normal request detail; authorized archive for recovery | Higher revision only; same revision/different hash conflicts. |

Receivers buffer an out-of-order ledger detail only as runtime pending data and
fetch missing sequences. They never infer a balance from a digest and never
persist an unverified future event as canonical. A client with a missing ledger
gap reports `SYNC_BEHIND`; it cannot become coordinator or finalize canonical
Dib consumption.

Anti-entropy is pull-based and bounded: on login, guild-roster availability,
coordinator activation, and low-frequency heartbeat, a client announces or
requests high-water digests. Failure to obtain an authoritative chain leaves the
client degraded rather than silently current.

AceComm/AceSerializer is required for state synchronization. A missing library
or prefix registration is `SYNC_UNAVAILABLE`, not compact best-effort success.
Ace transport does not provide ordering, delivery, consensus, or cryptographic
identity; the envelopes and state rules above provide deterministic handling.

### 6. Protocol and legacy-client cutover

The protocol has three visible migration states:

| State | Meaning |
|---|---|
| `LEGACY_LOCAL` | Existing local behavior; no canonical distributed ledger claim. |
| `CUTOVER_PREPARED` | New clients can exchange non-canonical/read-only digests and baseline evidence; coordinator writes remain disabled. |
| `V2_ENFORCED` | GM-approved baseline, active coordinator epoch, and minimum compatible protocol are enforced. |

Canonical distributed ledger operation begins only when the GM enables
`V2_ENFORCED`, the canonical baseline is approved, and every active
policy/award writer advertises the required protocol. Ordinary players may
remain legacy clients, but their legacy Pre-Dibs are local evidence until they
are re-submitted/confirmed through the new protocol.

New clients reject legacy policy and ledger writes after cutover. A later
legacy-client local record is preserved as `legacyPostCutoverEvidence` and
requires explicit reconciliation; it is never merged automatically.

### 7. Legacy baseline and data preservation

Before the first canonical epoch, the GM performs legacy baseline
reconciliation:

1. compare available legacy ledger/history evidence from participating peers;
2. preserve every original record unchanged;
3. identify duplicate and divergent histories;
4. choose include, exclude, or compensating-adjustment decisions explicitly;
5. produce a sorted `legacyBaselineHash`, source summary, and audit decision
   list; and
6. bind the first `ACTIVE(E)` governance record to that baseline hash.

No client database is automatically selected as canonical. Historical Pre-Dibs
are preserved; only an owner-reconfirmed active legacy request becomes an active
new-protocol request. This avoids reviving a stale cancellation or fulfillment.

All SavedVariables migration is additive, validated, backed up before mutation,
and idempotent. Invalid subtrees are quarantined; future unsupported schemas are
read-only with an actionable diagnostic. Existing Dibs history and
RCLootCouncil history are never deleted or rewritten.

### 8. RCLootCouncil and combat-safe integration

RCLootCouncil may provide verified `awardEvidence` only through a declared,
tested adapter capability. The canonical ledger command and recovery workflow do
not require RCLootCouncil. If the installed RC version is absent, degraded, or
unsupported, automatic consumption fails closed but Standalone ledger, policy,
and reconciliation remain available.

Dibs does not write synthetic Pre-Dibs into RCLootCouncil history. Existing
`dibsOrigin` rows remain display-only legacy data and cannot qualify as award
evidence.

UI projection is non-authoritative. Dibs owns and scripts only Dibs-created
controls, never replaces an RC-owned script, and defers all frame creation,
reparenting, script assignment, positioning, and enable/disable mutation during
combat. A coalesced Dibs-owned refresh runs after `PLAYER_REGEN_ENABLED`.

## P1 Traceability

The original validation findings remain the evidence base. The batches below
cover them without changing their severity.

| P1 finding group | Canonical remediation location |
|---|---|
| C-001, A-001, TEST-001 | B02a/B02b governance and operational policy. |
| C-002, C-003, TEST-002 | B05b/B06 fenced handoff and coordinator activation. |
| C-004, SYNC-001, SYNC-002, SYNC-006, TEST-003 | B04 transport, request index, anti-entropy. |
| C-005, REL-003, TEST-004, TEST-007 | B02a identity, roster freshness, governance validation. |
| S-001, S-002, S-003, TEST-005 | B03 protected ledger command and invariants. |
| S-004, SYNC-003, SYNC-004 | B05a verified recovery/baseline staging. |
| REL-001, TEST-006 | B01 SavedVariables validation and recovery. |
| REL-002 | B07 capability-isolated initialization. |
| WOW-001, WOW-002, TEST-008 | B08 combat-safe Dibs-owned UI. |
| A-002, RC-001, RC-002, TEST-009 | B09 optional, versioned RC adapter/history separation. |
| QUAL-003 | B10 documentation parity and production gate. |

## Dependency Graph and Exact Order

```text
B00  Decision contract + partition/two-client fixtures
  |
B01  SavedVariables validation and recovery
  |
B02a Governance bootstrap + identity + GM policy adoption
  |\
  | +-- B03 Local ledger command/invariants
  |
  +---- B04 Transport + anti-entropy + protocol cutover
          |\
          | +-- B02b Operational policy
          |
          +---- B05a Legacy baseline reconciliation + staged recovery
                  |
                  B05b Fenced coordinator handoff/recovery
                          |
                          B06 Coordinator distributed ledger activation

B07 Optional-startup capability isolation (after B00; independent of B01-B06)
B08 Combat-safe RCLootCouncil UI ownership (after B00)
B09 Versioned optional RCLootCouncil adapter (after B06, B07, B08)
B10 Documentation, Retail validation, and production gate (after B01-B09)
```

The required implementation order is:

1. B00
2. B01
3. B02a
4. B03 and B04 (independent only after B02a; do not merge their commits)
5. B02b
6. B05a
7. B05b
8. B06
9. B07 and B08 (may run independently once B00 is complete)
10. B09
11. B10

`B09` is not a prerequisite for core B06 correctness. It is required only
before enabling automatic RCLootCouncil award evidence/consumption.

## Mandatory Git Safety Protocol

This protocol is mandatory for **every** implementation batch below. It is a
future implementation requirement; no checkpoint or batch work is performed by
this document update.

Before modifying source, tests, or migration scripts in a batch:

1. Run `git status` and record the full starting commit hash.
2. Identify and preserve all user/unrelated changes; do not stage, discard,
   reset, checkout, or overwrite them.
3. Require a checkpoint commit for the batch starting state. If unrelated dirty
   work prevents a safe checkpoint, stop and obtain direction rather than hiding
   or deleting changes.

After the batch's scoped validation succeeds:

4. Create one separate commit for that batch only.
5. Record the resulting commit hash in the batch evidence/release record.
6. Keep the batch independently revertible; never use destructive Git commands
   unless the user explicitly authorizes them.

## Implementation Batches

Every batch below includes the Mandatory Git Safety Protocol above. Future work
must record the start and resulting commit hashes in its implementation evidence.

### B00 — Decision contract and partition fixtures

- **Objective:** Encode the binding decision record into focused architecture and
  two-client/partition test fixtures without enabling production behavior.
- **P1 findings:** Enables TEST-001 through TEST-009; resolves none alone.
- **Architecture:** Governance classes, transition-state vocabulary, protocol
  state vocabulary, and canonical fixture contracts.
- **Likely files:** Test helpers/fixtures, architecture/protocol documentation.
- **Must not modify:** Production ledger, sync, RC adapter, SavedVariables
  migration behavior.
- **Migration/compatibility:** None; no protocol activation.
- **Required tests:** Fixture proves delayed, duplicate, out-of-order, and
  partitioned message delivery can be expressed deterministically.
- **Acceptance criteria:** The fixture represents the CH-01 split-brain scenario
  and corrected `RECOVERY_PENDING` path; no production feature is enabled.
- **Git safety:** Mandatory Git Safety Protocol; B00 receives its own checkpoint
  and commit.
- **Complexity / dependency:** Medium; none.

### B01 — SavedVariables validation and recovery

- **Objective:** Validate, back up, quarantine, and migrate SavedVariables
  before any policy or coordinator state is introduced.
- **P1 findings:** REL-001, TEST-006.
- **Architecture:** Additive validated migration with valid, recoverable-invalid,
  and future-unsupported outcomes.
- **Likely files:** Core persistence/migration code, migration fixtures,
  SavedVariables documentation.
- **Must not modify:** Ledger consensus rules, sync protocol, RC UI.
- **Migration/compatibility:** Preserve all valid legacy ledger, season and
  request data; future schemas become read-only rather than downgraded.
- **Required tests:** Wrong root/subtree type, truncation, future schema,
  idempotent migration, backup/quarantine, no valid data loss.
- **Acceptance criteria:** No unvalidated nested value is indexed during startup;
  no migration rewrites historical transaction identity.
- **Git safety:** Mandatory Git Safety Protocol; record start/end hashes.
- **Complexity / dependency:** High; B00.

### B02a — Governance bootstrap, identity, and GM policy adoption

- **Objective:** Establish Name-Realm identity, roster freshness, GM-only
  governance records, and explicit `POLICY_UNINITIALIZED` adoption.
- **P1 findings:** C-005, REL-003, TEST-004 (authority), TEST-007; foundation
  for C-001/A-001.
- **Architecture:** Governance records have parent/hash/audit rules; only current
  live GM can adopt or change authority, coordinator, epoch, baseline, or
  protocol cutover.
- **Likely files:** Core event routing, identity/permissions modules, policy
  store/migrator, officer adoption UI, focused tests.
- **Must not modify:** RC frame hooks, award callback mapping, live ledger sync.
- **Migration/compatibility:** Preserve local legacy settings; no auto-adoption.
  Short-name callers receive an explicit ambiguity outcome when necessary.
- **Required tests:** Same short name across realms, optional GUID mismatch,
  alias review, roster-change invalidation, GM-only governance, same-revision
  different-hash conflict, uninitialized behavior.
- **Acceptance criteria:** No officer/local setting can self-authorize a
  governance change; no `ledgerEpoch` exists until GM adoption.
- **Git safety:** Mandatory Git Safety Protocol; record start/end hashes.
- **Complexity / dependency:** High; B00, B01.

### B03 — Local canonical ledger command and invariants

- **Objective:** Replace direct durable mutations with one protected ledger
  command path, without yet enabling distributed activation.
- **P1 findings:** S-001, S-002, S-003, TEST-005.
- **Architecture:** `CommitDibUse`/domain commands validate balance/debt,
  idempotency and canonical content; legacy direct writes become non-canonical
  compatibility evidence after cutover.
- **Likely files:** Ledger, protected action boundary, direct mutation callers,
  ledger tests.
- **Must not modify:** Transport/WHISPER codec, RC frame UI, coordinator election
  or takeover behavior.
- **Migration/compatibility:** Add fields without changing old transaction IDs;
  retain reject-only/deprecation path for old public mutators.
- **Required tests:** Insufficient balance, explicit allowed debt, duplicate
  content replay, same ID/different content conflict, legacy record reading.
- **Acceptance criteria:** Rejected command changes neither transaction store nor
  balance; no public direct mutation can create a canonical post-cutover debit.
- **Git safety:** Mandatory Git Safety Protocol; record start/end hashes.
- **Complexity / dependency:** High; B02a.

### B04 — Transport, anti-entropy, and protocol cutover

- **Objective:** Implement bounded GUILD digest/WHISPER detail behavior,
  authority-specific source rules, gap handling, and migration states.
- **P1 findings:** C-004, SYNC-001, SYNC-002, SYNC-006, TEST-003, TEST-004
  (transport).
- **Architecture:** AceComm/AceSerializer required; `LEGACY_LOCAL`,
  `CUTOVER_PREPARED`, `V2_ENFORCED`; GUILD notifications are never state proofs.
- **Likely files:** Sync/transport module, Ace adapter, request lifecycle module,
  protocol documentation and two-client tests.
- **Must not modify:** Canonical ledger activation or RCLootCouncil award logic.
- **Migration/compatibility:** Legacy messages may be read as non-canonical
  evidence during transition; no legacy message writes policy or canonical
  ledger after enforcement.
- **Required tests:** Missing/reordered/duplicate/altered detail, hash conflict,
  gap fetch, `SYNC_BEHIND`, unavailable Ace transport, login/heartbeat pull,
  legacy/new client coexistence.
- **Acceptance criteria:** A gap cannot be skipped; `SYNC_BEHIND` cannot become
  coordinator or finalize a canonical debit; compact fallback never claims
  successful state transfer.
- **Git safety:** Mandatory Git Safety Protocol; record start/end hashes.
- **Complexity / dependency:** High; B02a.

### B02b — Operational policy

- **Objective:** Add officer-editable, allowlisted operational policy after the
  governance and transport trust foundations exist.
- **P1 findings:** C-001, A-001, TEST-001.
- **Architecture:** Operational `policyRevision` chain separated from governance
  and `ledgerEpoch`.
- **Likely files:** Policy service, Pre-Dib mode/settings readers, profiles,
  officer UI, policy synchronization tests.
- **Must not modify:** Governance writer rules, coordinator transition logic, RC
  integration.
- **Migration/compatibility:** Legacy local policy remains read-only fallback
  until GM adoption; profiles must preview rather than silently overwrite
  governance values.
- **Required tests:** Authorized officer revision, unauthorized sender,
  same-revision hash conflict, reconnect, mode change not altering ledger epoch.
- **Acceptance criteria:** Operational policy converges across raids while no
  operational edit can alter governance, baseline, coordinator, or epoch.
- **Git safety:** Mandatory Git Safety Protocol; record start/end hashes.
- **Complexity / dependency:** High; B02a, B04.

### B05a — Legacy baseline reconciliation and staged recovery

- **Objective:** Create the GM-reviewed canonical baseline required before any
  coordinator activation; make recovery validation all-or-nothing.
- **P1 findings:** S-004, SYNC-003, SYNC-004; prerequisite for C-002/C-003.
- **Architecture:** Comparison, include/exclude/compensation decisions,
  `legacyBaselineHash`, recovery schema and atomic staging.
- **Likely files:** Recovery/import service, ledger/history projections,
  officer reconciliation UI, Sync recovery codec, migration and recovery tests.
- **Must not modify:** Active coordinator commit behavior, RC frame hooks.
- **Migration/compatibility:** Preserve every original record; choose no client
  automatically; active legacy Pre-Dibs require owner reconfirmation.
- **Required tests:** Divergent histories, duplicate legacy evidence, baseline
  hash reproducibility, invalid mixed payload rollback, explicit compensation,
  unresolved identity.
- **Acceptance criteria:** A GM-approved baseline is reproducible from its audit
  set; a failed recovery modifies no canonical data; no first-client database is
  selected automatically.
- **Git safety:** Mandatory Git Safety Protocol; record start/end hashes.
- **Complexity / dependency:** High; B02a, B03, B04.

### B05b — Fenced coordinator handoff and forced recovery

- **Objective:** Implement the state machine that makes coordinator transition
  safe before distributed ledger activation.
- **P1 findings:** C-002/C-003 safety prerequisite, TEST-002.
- **Architecture:** `ACTIVE`, `HANDOFF_CLOSING`, `RECOVERY_PENDING`, normal
  closure parent tuple, forced baseline, orphaned evidence, proposal behavior.
- **Likely files:** Governance policy service, coordinator state service, sync
  state, protected award eligibility, officer takeover/recovery UI, partition
  tests.
- **Must not modify:** Automatic RCLootCouncil callback assumptions or RC-owned
  UI controls.
- **Migration/compatibility:** No automatic epoch starts. Existing/offline
  history stays evidence; forced-recovery exclusions are retained as orphaned,
  reviewable records.
- **Required tests:** Normal closure, late old-epoch event, old coordinator
  reconnect, missing closure, partitioned A/B scenario, forced recovery,
  proposal without debit, GM-only takeover.
- **Acceptance criteria:** During `RECOVERY_PENDING` no path produces canonical
  `DIB_USED`; an `ACTIVE(E+1)` event must name the approved closure or recovery
  baseline; late excluded events are never auto-appended.
- **Git safety:** Mandatory Git Safety Protocol; record start/end hashes.
- **Complexity / dependency:** High; B05a.

### B06 — Coordinator distributed ledger activation

- **Objective:** Enable canonical multi-raid ledger commits only after policy
  cutover, baseline and fenced recovery are in place.
- **P1 findings:** C-002, C-003, TEST-002.
- **Architecture:** Active coordinator assigns exact sequence/previous hash and
  emits `AWARD_COMMIT`; non-coordinators issue proposals only.
- **Likely files:** Ledger command, coordinator service, sync ledger digest/detail
  path, protected actions, status UI, multi-client tests.
- **Must not modify:** RCLootCouncil adapter internals as a requirement for core
  correctness; RC may be disabled/degraded while core activation works.
- **Migration/compatibility:** Activate only in GM-enabled `V2_ENFORCED` after
  compatible active writers and baseline are confirmed. Post-cutover legacy
  records remain reconciliation evidence.
- **Required tests:** Two raids, same final Dib, duplicate/out-of-order commits,
  old coordinator reconnect, normal handoff, forced recovery, reload/reconnect,
  `SYNC_BEHIND`, unavailable coordinator.
- **Acceptance criteria:** No two active canonical branches can be created after
  takeover; a non-coordinator never appends canonical consumption; an unknown
  or stale epoch cannot debit the ledger.
- **Git safety:** Mandatory Git Safety Protocol; record start/end hashes.
- **Complexity / dependency:** High; B05b and `V2_ENFORCED` preconditions.

### B07 — Optional-startup capability isolation

- **Objective:** Keep Dibs core available if optional UI, RC, or Encounter
  Journal initialization fails.
- **P1 findings:** REL-002.
- **Architecture:** Capability registry and scoped retry, not broad startup
  failure.
- **Likely files:** Core bootstrap, capability diagnostics, lifecycle tests.
- **Must not modify:** Ledger/policy state, sync schema, RC history.
- **Migration/compatibility:** None; optional functionality becomes visibly
  degraded rather than preventing core startup.
- **Required tests:** Failure injection for each optional initializer and scoped
  retry behavior.
- **Acceptance criteria:** Core database/commands remain available when any
  optional capability fails.
- **Git safety:** Mandatory Git Safety Protocol; record start/end hashes.
- **Complexity / dependency:** Medium; B00.

### B08 — Combat-safe RCLootCouncil UI ownership

- **Objective:** Keep UI projection non-authoritative and prevent Dibs from
  mutating RC-owned controls during combat.
- **P1 findings:** WOW-001, WOW-002, TEST-008.
- **Architecture:** Dibs-owned UI scheduler, combat queue, and no replacement of
  RC scripts.
- **Likely files:** RC integration UI layer, combat lifecycle routing, queue
  tests, Retail validation checklist.
- **Must not modify:** Core coordinator ordering, policy authority, baseline.
- **Migration/compatibility:** None; stale visual state during combat is allowed.
- **Required tests:** Queue/idempotence simulation plus Retail combat, late-load,
  reload and post-combat validation.
- **Acceptance criteria:** No Dibs mutation of RC-owned `OnClick`; no unsafe UI
  mutation during lockdown; no Dibs-attributable taint/forbidden action in the
  required Retail matrix.
- **Git safety:** Mandatory Git Safety Protocol; record start/end hashes.
- **Complexity / dependency:** High; B00.

### B09 — Optional versioned RCLootCouncil award adapter and history separation

- **Objective:** Consume verified RC award evidence only through an explicit
  supported adapter capability; remove Dibs writes into RC history.
- **P1 findings:** A-002, RC-001, RC-002, TEST-009.
- **Architecture:** Optional `awardEvidence` adapter feeding the already-safe
  core command; unsupported RC is fail-closed for automation, not core Dibs.
- **Likely files:** RC adapter/options, reconciliation/history projection,
  capability fixtures, version-matrix documentation.
- **Must not modify:** Coordinator algorithm, policy migration, canonical
  baseline semantics.
- **Migration/compatibility:** Keep existing `dibsOrigin` rows display-only and
  exclude them from award evidence; do not alter RC-owned history.
- **Required tests:** Supported/unsupported RC matrix, callback/status mapping,
  absent/late/degraded behavior, history separation, Retail verification.
- **Acceptance criteria:** Unknown RC callback/status cannot auto-consume a Dib;
  Standalone reconciliation and B06 core ledger stay available without RC.
- **Git safety:** Mandatory Git Safety Protocol; record start/end hashes.
- **Complexity / dependency:** High; B06, B07, B08.

### B10 — Documentation parity, Retail validation, and release gate

- **Objective:** Publish only proven capabilities and collect the final
  production evidence.
- **P1 findings:** QUAL-003 and final gates for TEST-001 through TEST-009.
- **Architecture:** Capability-gated release documentation and evidence record.
- **Likely files:** README, developer protocol docs, release checklist, Retail
  matrix/evidence files.
- **Must not modify:** Production behavior or historic data.
- **Migration/compatibility:** Document `LEGACY_LOCAL`, `CUTOVER_PREPARED`,
  `V2_ENFORCED`, coordinator-unavailable behavior and supported RC versions.
- **Required tests:** Completed evidence for every prior batch; one-client and
  two-client Retail matrix including partition/reconnect/handoff/recovery.
- **Acceptance criteria:** Documentation never claims shared policy or canonical
  multi-raid ledger until B02b-B06 gates pass; release notes contain exact
  migration, cutover and rollback guidance.
- **Git safety:** Mandatory Git Safety Protocol; record start/end hashes.
- **Complexity / dependency:** Medium; B01-B09.

## Release Gates

Production use requires all gates below, in order:

1. **Data integrity:** Validated SavedVariables, backups/quarantine, immutable
   legacy records, explicit baseline, all-or-nothing recovery.
2. **Deterministic behavior:** Canonical hashes, exact sequence/previous-hash
   application, no skipped gaps, audited conflicts/orphaned evidence.
3. **Authority correctness:** GM-only governance, current roster validation,
   operational-policy allowlist, no direct canonical mutation APIs.
4. **Synchronization correctness:** Bounded GUILD/WHISPER anti-entropy,
   `SYNC_BEHIND` restrictions, reconnect/reload/two-raid/partition recovery.
5. **Coordinator safety:** Normal closure, forced `RECOVERY_PENDING`, GM baseline
   adoption, no automatic consumption while unavailable, late old epoch handling.
6. **Backward compatibility:** Explicit cutover, compatible active writers,
   legacy evidence preservation, no silent protocol success or data rewrite.
7. **WoW/RC safety:** Retail combat matrix passes; RC remains optional and fails
   closed for automation; RC history is not written by Dibs.
8. **Documentation and release:** README/protocol docs match enabled behavior and
   batch commit/evidence records are complete.

## Internal Consistency Review

The Architecture Decision Record, state machine, batch dependencies, migration
rules, compatibility rules and release gates agree on the following invariants:

- forced takeover is `RECOVERY_PENDING`, never an immediate second writer;
- only the GM changes governance and enables canonical cutover;
- the first and every forced epoch is tied to an explicit baseline hash;
- `SYNC_BEHIND`, legacy writers, and unavailable coordinators cannot create a
  canonical debit;
- B06 core correctness does not depend on RCLootCouncil; and
- each implementation batch requires independent Git checkpoint/commit evidence.

REMEDIATION PLAN READY FOR B00
