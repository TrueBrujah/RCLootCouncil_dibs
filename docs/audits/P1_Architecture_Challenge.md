# P1 Architecture Challenge

**Date:** 2026-09-12  
**Scope:** Read-only challenge of
[`P1_Remediation_Plan.md`](P1_Remediation_Plan.md) before implementation.  
**Out of scope:** Source-code re-audit, implementation, refactoring, and test
execution.

## Executive Result

The remediation plan has a sound direction: it correctly prefers explicit
authority, a single active coordinator, bounded synchronization, and failure
over silent divergence. However, the proposed **epoch/sequence model is not
sufficient as written to prevent split-brain ledger commits during a network
partition and forced coordinator takeover**.

The architectural problem is not a sequence-number bug. It is an unavoidable
distributed-systems boundary: in a partitioned WoW addon network, a new
coordinator cannot know whether the old coordinator is still committing. An
epoch number fences an old coordinator only after that client learns of the new
epoch. It cannot revoke the old coordinator's ability to make a local decision
while it is unreachable.

The plan therefore requires a fenced-handoff/recovery state machine and a
governance bootstrap rule before B06 may be implemented. The preferred outcome
is safety over availability: Dibs-consuming awards are unavailable while a
forced takeover is unresolved. Pre-Dibs may continue as non-ledger proposals.

## Decision Review

| Decision | Status | Challenge result | Affected batch(es) |
|---|---|---|---|
| 1. Full Name-Realm identity with optional GUID | **CONFIRM WITH CHANGES** | Correct wire identity direction, but a durable alias/rename policy and immutable historical identity record are required. | B01, B02, B05 |
| 2. Versioned GuildPolicy | **CONFIRM WITH CHANGES** | Correct separation of policy and local settings, but governance authority is circular unless GM-only bootstrap/governance actions are defined. | B02, B04, B06 |
| 3. Local ledger command/integrity boundary | **CONFIRM WITH CHANGES** | Correct boundary, but new records must be chained to a defined epoch baseline and direct legacy writes must become non-canonical after cutover. | B03, B05, B06 |
| 4. Single active guild ledger coordinator | **REJECT** as currently specified | One coordinator is the right availability trade-off, but epoch+sequence alone does not prevent split brain after forced takeover. | B02, B05, B06 |
| 5. GUILD digest + WHISPER detail synchronization | **CONFIRM WITH CHANGES** | Correct traffic shape, but needs anti-entropy, authority-specific detail sources, gap handling, and deterministic conflict behavior. | B04, B05, B06 |
| 6. AceComm/AceSerializer required transport | **CONFIRM WITH CHANGES** | Correct to reject lossy fallback, but Ace does not supply ordering, delivery, identity proof, or consensus. | B04, B06 |
| 7. SavedVariables validation/migration | **CONFIRM WITH CHANGES** | Correct recovery posture, but a canonical legacy baseline cannot be selected automatically from potentially divergent client histories. | B01, B05, B06 |
| 8. Combat-safe Dibs-owned UI | **CONFIRM WITH CHANGES** | Correct safety boundary; it must be strictly non-authoritative and cannot delay or alter coordinator decisions. | B08, B09 |
| 9. Versioned RCLootCouncil adapter/history separation | **CONFIRM WITH CHANGES** | Correct fail-closed direction, but the plan must not assume undocumented RC callbacks/projections exist. | B06, B08, B09 |

## Material Challenge Findings

### CH-01 — An authority epoch does not by itself fence a partitioned coordinator

**Status:** Material architectural problem  
**Affected batches:** B02, B05, B06  
**Preferred correction:** Add a two-path coordinator transition state machine:
normal fenced handoff and forced recovery takeover. Do not permit a new
coordinator to write production ledger events immediately after an unacknowledged
takeover.

#### Exact failure scenario

1. Guild policy declares coordinator **A** active in ledger epoch `E=7`; A is in
   Raid A with canonical sequence `7/42`.
2. Raid B is active with officer **B**. The player in Raid B has one Dib left.
3. Addon traffic partitions: B no longer receives A's messages, but A remains
   online in Raid A and does not know a partition exists.
4. A awards a DIB response in Raid A and appends `7/43`: it consumes the
   player's final Dib according to A's local ledger.
5. Raid B considers A lost. An officer performs the proposed takeover and starts
   epoch `E=8` from a last digest known to B, `7/42`.
6. B awards a DIB response to the same player and appends `8/1`, also consuming
   that final Dib according to B's local ledger.
7. When the partition heals, both events have valid sender identities, valid
   epoch/sequence-shaped IDs, valid hashes, and locally valid balance checks.

If clients accept both epochs, the ledger contains two consumptions. If clients
discard all epoch-7 events after seeing epoch 8, A's physical loot decision and
its local audit no longer have a canonical ledger entry. The epoch/sequence
format prevents a duplicate identifier; it does **not** establish which side was
authorized at the time of the irreversible in-game award.

#### Why the proposed model cannot prove split-brain prevention

The current plan says that a GM/officer takes over in a higher policy epoch and
that the coordinator emits ordered records. This is sufficient only when the
old coordinator receives the new epoch before it commits. During a partition it
does not receive it, so both of these predicates can be true at once:

```text
A believes: currentEpoch == 7, I am coordinator, next sequence == 43
B believes: currentEpoch == 8, I am coordinator, next sequence == 1
```

No timestamp, message ID, heartbeat timeout, or `lastSeen` field can make this
safe in an asynchronous partition: it can distinguish neither a delayed message
from a disconnected coordinator nor a slow client from a failed one. Automatic
leader election was correctly rejected; an officer-initiated immediate takeover
has the same split-brain issue unless it is fenced.

#### Preferred correction: fenced transition state machine

Separate `policyRevision` from `ledgerEpoch`. A normal Pre-Dib-mode change may
advance `policyRevision`; it must never advance `ledgerEpoch`. Only a governance
transition changes `ledgerEpoch`.

Use these states:

| State | Permitted ledger action | Required proof/context |
|---|---|---|
| `ACTIVE(E)` | Coordinator may commit exact next sequence only. | Current governance record, `previousHash`, exact `nextSeq`. |
| `HANDOFF_CLOSING(E)` | Old coordinator may finish no new award after publishing closure. | Closure declares `lastSeq` and epoch ledger root. |
| `ACTIVE(E+1)` normal handoff | New coordinator may commit only after validating the closed predecessor root. | Parent `{epoch: E, lastSeq, rootHash}` bound into the governance record. |
| `RECOVERY_PENDING` | No production Dib consumption. Requests/proposals may be queued. | Previous coordinator is unavailable or closure cannot be verified. |
| `ACTIVE(E+1)` forced recovery | New coordinator may commit only after a GM-approved reconciled baseline is adopted. | Baseline hash, included event range(s), excluded/orphan policy, recovery audit. |

For a normal handoff, the old coordinator first emits a closure containing the
last sequence and ledger root, then permanently marks its local epoch closed.
The GM publishes the new governance record with that exact predecessor tuple.
Clients reject any `E` event above the closed `lastSeq` and any `E+1` event that
does not name the same parent root.

For a forced takeover, the new coordinator must begin in `RECOVERY_PENDING`.
It gathers bounded ledger evidence from known peers, and the GM explicitly
adopts a reconciled baseline. Late old-epoch events absent from that baseline
are **orphaned evidence**, not automatically appended canonical events. They
require an officer reconciliation decision. This preserves one canonical future
ledger even though it cannot undo a physical award already made by a partitioned
old coordinator.

#### Migration implications

The first post-migration coordinator epoch must be based on an explicit legacy
baseline manifest, not whichever client loads first. Existing records are
preserved as legacy evidence. They are not rewritten, resequenced, or silently
merged into a new event chain.

#### Backward-compatibility implications

During `RECOVERY_PENDING`, a DIB response must be disabled or converted to a
non-Dib response. Allowing automatic local consumption would recreate the same
split-brain condition. This is a visible workflow restriction, but it is the
only safe behavior without a central service or a live fenced handoff.

### CH-02 — GuildPolicy governance is circular without a bootstrap authority

**Status:** Material architectural problem  
**Affected batches:** B02, B04, B06  
**Preferred correction:** Split policy into governance and operational classes.
Only the current live Guild Master can create/change governance records;
officers may change allowlisted operational policy according to the last valid
governance record.

#### Exact failure scenario

1. An officer policy says ranks 1-2 are officers.
2. A client receives a policy change that expands the officer set, changes the
   coordinator, or changes who may write policy.
3. The receiver must decide whether the sender is authorized using the policy
   whose validity is being changed.

If any currently authorized officer can modify `officerRankRule` or
`coordinator`, a locally altered or stale policy can become self-authorizing. If
two officers concurrently make governance changes, matching revisions with
different hashes have no single authority rule in the plan.

#### Preferred correction

Define two immutable policy classes:

- **Governance records:** officer-rank rule, policy writers, coordinator,
  ledger epoch, protocol cutover, forced recovery baseline. Receiver accepts
  them only when the sender resolves to the *current Guild Master* from a fresh
  guild roster. A receiver with no roster confirmation does not adopt them.
- **Operational policy records:** Pre-Dib mode, public request availability,
  debt setting and other allowlisted guild rules. Receiver accepts them only
  from a live roster member permitted by the last valid governance record.

Every policy record includes `policyRevision`, parent revision/hash, class,
author Name-Realm, and a canonical content hash. Same revision/different hash is
a conflict requiring a new GM governance record; it is never last-write-wins.

This does not make WoW messages cryptographically signed. The author field is
an attributed guild-message sender validated against the live roster; it must
not be described as a signature or proof of an unmodified client.

#### Migration implications

Do not auto-create `guildPolicy` revision 1 from an arbitrary officer's local
settings at first load. Start `POLICY_UNINITIALIZED`; preserve current local
settings and require a GM-driven adoption wizard to select the initial
governance and operational policy. The resulting baseline is auditable and
gives all upgraded clients one identity/hash to converge upon.

#### Backward-compatibility implications

Before GM adoption, existing settings continue as local legacy behavior and no
shared-policy claim is made. After adoption, officer workflows may change only
operational fields allowed by the governance record. A GM being offline blocks
governance changes by design; it must not be bypassed by a timeout.

### CH-03 — Coordinator loss must favor unavailable consumption over queued local commits

**Status:** Material architectural problem  
**Affected batches:** B04, B05, B06, B09  
**Preferred correction:** Define `COORDINATOR_UNAVAILABLE` as a first-class
award eligibility outcome. A non-coordinator may submit an unsigned-in-the-
cryptographic-sense but attributable **award proposal**; it may not reserve,
consume, or locally finalize a Dib.

#### Exact failure scenario

Raid B sends an award request to coordinator A. A disconnects after the game
loot is awarded but before it returns an ordered ledger commit. If Raid B queues
a local `DIB_USED` and later retries, A may have committed before disconnecting.
If B appends its queued write after takeover, the same award can consume twice.

#### Preferred correction

During normal connectivity, a non-coordinator sends an `AWARD_PROPOSAL` to the
coordinator. Only the coordinator returns an `AWARD_COMMIT` with the next
sequence. The RCLootCouncil adapter must not treat callback receipt as a ledger
commit.

When no current coordinator is reachable:

- Dibs-consuming award finalization returns `COORDINATOR_UNAVAILABLE`;
- UI disables/labels the DIB path before the irreversible award where possible;
- an officer may retain a proposal as `PENDING_RECONCILIATION`, containing the
  item and award evidence, but it has no balance effect;
- forced takeover follows CH-01 recovery and may later accept or reject the
  proposal as an audited correction.

The preferred default is not to block non-Dib RCLootCouncil loot distribution;
only the Dibs accounting privilege is unavailable. A guild can make a stricter
policy that blocks the DIB response entirely, but it should not secretly create
debt or a local ledger event.

#### Migration implications

Add a new non-canonical proposal collection separate from ledger transactions.
Never convert historical local transactions into proposals; preserve them as
legacy events. New pending proposals require explicit officer reconciliation.

#### Backward-compatibility implications

This changes the existing immediate award workflow during coordinator loss. It
is intentionally visible: Raid B must know that Dibs cannot be consumed until
the coordinator is available or a GM completes recovery.

### CH-04 — GUILD digest plus WHISPER details needs anti-entropy and entity-specific authority

**Status:** Material architectural problem  
**Affected batches:** B04, B05, B06  
**Preferred correction:** Treat GUILD notifications as hints and define a pull
anti-entropy protocol with gap buffering and source rules per entity.

#### Exact failure scenario

1. Coordinator A emits digest `ledger E=7, lastSeq=43, root=H43` to GUILD.
2. Raid B misses it while zoning.
3. A disconnects before B can request the missing event by WHISPER.
4. B's next digest is stale. A later digest `lastSeq=45` arrives before `43-44`.

A message-ID replay cache rejects exact duplicates, but it does not explain how
to apply `45` without `43-44`, or where to obtain details when the original
sender is gone. Accepting the newest digest without the gap can make the client
display a balance it cannot reproduce. Accepting arbitrary peer detail lets a
non-coordinator present a valid-looking but non-canonical ledger branch.

#### Preferred correction

For each entity, specify a separate acceptance and source rule:

| Entity | GUILD notification | Authoritative WHISPER detail source | Out-of-order rule |
|---|---|---|---|
| Governance policy | revision/hash/parent | Current GM for governance records | Accept only direct child of known parent; otherwise fetch chain. |
| Operational policy | revision/hash/parent | Current authorized policy writer or GM | Same revision + different hash is conflict; no overwrite. |
| Ledger | epoch, contiguous `lastSeq`, root hash | Active coordinator; recovery baseline archive only after GM adoption | Apply only exact `nextSeq` and matching previous hash. Buffer/fetch gaps; never infer balance from a digest. |
| Pre-Dib request | request ID, revision, terminal marker/hash | Request owner for owner-created detail; coordinator/authorized archive for recovery | Higher revision only; same revision + different hash is conflict. |

Add low-frequency anti-entropy, not periodic full replication: on login, guild
roster availability, coordinator activation, and a bounded heartbeat, a client
announces/requests the highest known digest. A receiver fetches missing chains
from the authoritative source. If it cannot, it reports `SYNC_BEHIND` and must
not become coordinator or finalize Dibs from an unreconciled state.

#### Migration implications

New indexes need stored high-water marks and terminal tombstones. Pending gaps
are runtime-only until their detail is verified; do not persist an unverified
future ledger event as canonical state.

#### Backward-compatibility implications

GUILD traffic remains bounded. Old clients can ignore the new messages but are
not eligible to participate in canonical policy/ledger writes after cutover.

### CH-05 — Legacy coexistence requires a cutover fence, not only a read-only protocol decoder

**Status:** Material architectural problem  
**Affected batches:** B02, B04, B05, B06, B10  
**Preferred correction:** Add a GM-adopted protocol/canonical-ledger cutover
record. Do not activate coordinator mode until all players who can write policy
or finalize Dibs awards are on the supported protocol.

#### Exact failure scenario

An officer uses an older addon during the transition. It can still append a
local legacy ledger transaction when it receives an RCLootCouncil award. The new
coordinator never sees that transaction as a canonical event. When the officer
upgrades later, importing it automatically may double-spend an award already
represented by the coordinator ledger; ignoring it silently hides a real prior
award.

#### Preferred correction

Use three policy-visible stages:

1. `LEGACY_LOCAL`: current behavior; no claim of multi-raid canonical ledger.
2. `CUTOVER_PREPARED`: new clients can exchange read-only/new-protocol digests,
   but coordinator ledger writes remain disabled. GM checks that all active
   officers/MLs have the required protocol.
3. `V2_ENFORCED`: governance record names the canonical baseline, coordinator
   epoch and minimum protocol. New clients reject legacy ledger/policy writes;
   legacy post-cutover local records are imported only as reconciliation evidence.

Ordinary players may remain on an older client, but their old Pre-Dibs are local
and non-authoritative until re-submitted/confirmed through the new protocol.

#### Migration implications

Tag legacy records discovered after cutover as `legacyPostCutoverEvidence` with
their source client/version when available. Preserve them, show them to officers,
and require an explicit reconciliation decision before any canonical adjustment.

#### Backward-compatibility implications

This is stricter than one release of passive coexistence, but avoids silently
mixing two ledger authorities. Release notes and the UI must identify exactly
which clients need to update before a GM enables `V2_ENFORCED`.

### CH-06 — Legacy ledger preservation needs canonical baseline adoption

**Status:** Material architectural problem  
**Affected batches:** B01, B05, B06  
**Preferred correction:** Make baseline adoption a GM-confirmed reconciliation
step that precedes the first coordinator epoch.

#### Exact failure scenario

Because the current addon has no distributed ledger commit path, Alice's
SavedVariables can contain a transaction that Bob's SavedVariables do not. If
the first upgraded coordinator derives its baseline from Alice automatically,
Bob's legitimate historical transaction disappears from the new canonical
balance. If the system unions both histories automatically, the same award may
be duplicated under different legacy IDs.

#### Preferred correction

Before `ACTIVE(E=1)`, generate a read-only comparison of available legacy
ledger/history evidence. A GM chooses one of these explicit outcomes per
conflict: include, exclude, or create a compensating canonical adjustment. The
chosen sorted legacy evidence set has a `legacyBaselineHash`, a source summary,
and an audit decision list. The first epoch governance record binds to that
hash. No client may independently select a different baseline later.

Pre-Dibs need a parallel but lighter rule: preserve all historical requests;
only active legacy requests explicitly re-confirmed by their owner become active
new-protocol requests. This avoids a stale cancellation/fulfillment becoming a
new active reservation.

#### Migration implications

This adds a manual migration phase. It is a required safety cost, not an
optional convenience. Original data stays untouched and remains exportable.

#### Backward-compatibility implications

Guilds not ready to reconcile can remain `LEGACY_LOCAL`. They should not enable
multi-raid canonical ledger mode yet.

### CH-07 — Name-Realm is the correct wire key, but identity history requires aliases

**Status:** Important architectural refinement  
**Affected batches:** B01, B02, B05  
**Preferred correction:** Keep full Name-Realm as the wire key, but add
GM-reviewed identity aliases and preserve immutable identity snapshots on every
ledger/history event.

#### Exact failure scenario

A character changes name or realm, or an old record exists only as a short
name. The plan's permanent Name-Realm key either splits one person's history
into two accounts or forces an unsafe automatic merge. A GUID may prove local/RC
continuity on one client but is unavailable in ordinary addon sender strings.

#### Preferred correction

Use an identity record:

```text
memberKey       = normalized current Name-Realm for wire routing
displayName     = last observed Name-Realm
guidWitness     = optional, local/RC corroboration only
aliases         = GM-reviewed former Name-Realm keys
```

Each ledger/history event stores an immutable identity snapshot (`memberKey` and
display name at event time). An alias is a governance/reconciliation record;
never infer one automatically from a matching short name or optional GUID.

#### Migration implications

Existing names remain historic strings. The migration creates no aliases unless
the GM explicitly reviews them. Unresolved values remain visible but cannot be
used for an automated balance merge.

#### Backward-compatibility implications

Existing short-name APIs retain a lookup mode only when resolution is unique;
otherwise they return an ambiguity result. This is safer than silently mapping a
new character to an old ledger.

### CH-08 — RCLootCouncil must not be an unstated liveness dependency

**Status:** Important architectural refinement  
**Affected batches:** B06, B08, B09  
**Preferred correction:** Define the ledger coordinator command as independent
of RCLootCouncil, and make automatic RC award consumption an optional adapter
capability with a manual officer fallback.

#### Exact failure scenario

The coordinator is reachable and a sequential ledger commit is possible, but
the installed RC version does not expose the assumed final-award callback or
its UI frame is unsafe in combat. If B06 depends on B09's undocumented
`subscribeFinalAward`/projection capability, multi-raid ledger correctness is
blocked by an optional integration. If it instead consumes from an unverified
status, it can debit a non-final award.

#### Preferred correction

Define one integration-independent command:

`CommitDibUse(coordinatorContext, awardEvidence)`.

The RC adapter may produce `awardEvidence` only when its declared versioned
capability contract is operational. If it is absent/degraded/unknown, automatic
consumption is unavailable; an authorized officer may later create a manual,
explicitly evidenced correction through the same coordinator command. UI
projection is read-only and must never establish authority or mutate a ledger.

#### Migration implications

None for core ledger records beyond preserving `evidenceSource` and RC version
metadata on new commits. Existing synthetic RC history remains display-only.

#### Backward-compatibility implications

Standalone mode stays functional. Unsupported RC versions fail closed for
automatic award integration but do not disable the guild policy, ledger view, or
manual reconciliation workflow.

## Scenario Proof: Raid A, Raid B, Coordinator Loss, and Late Messages

### Proposed-plan model: result is not safe

| Time | Raid A / coordinator A | Raid B / officer B | Result |
|---|---|---|---|
| T0 | A is active in epoch 7 at sequence 42. | B has replicated sequence 42. | Consistent. |
| T1 | Network partitions. | Network partitions. | Neither side can distinguish delay from failure. |
| T2 | A commits `7/43` for Player P. | B sees no response and starts epoch 8 from sequence 42. | Both have locally valid state. |
| T3 | A continues with epoch 7. | B commits `8/1` for Player P. | Same remaining Dib can be used twice in game. |
| T4 | A reconnects and sends delayed `7/43`. | B receives it after `8/1`. | Accepting it double-spends; rejecting it leaves an irreversible award outside canonical history. |

**Conclusion:** The proposed epoch/sequence model does not prevent split-brain
ledger commits. It only gives each branch distinct identifiers.

### Corrected model: what it prevents and what it cannot prevent

| Time | Corrected behavior | Canonical result |
|---|---|---|
| T0 | A is `ACTIVE(7)` at 42. | Consistent. |
| T1 | Partition begins. | A may continue only until a governance handoff is observed; B cannot know whether A did. |
| T2 | B detects loss. | B enters `RECOVERY_PENDING`; no Dibs consumption is permitted. |
| T3 | A may have committed `7/43`; B records only a non-canonical award proposal. | No new competing canonical event is created by B. |
| T4 | GM conducts forced recovery and adopts a baseline containing or excluding `7/43`. | The chosen baseline becomes parent of `ACTIVE(8)`. |
| T5 | A reconnects with any late epoch-7 event. | Events already in baseline are idempotent evidence; events absent from it are orphaned and require manual reconciliation, never automatic append. |

This corrected model prevents two competing **canonical future** commits after
takeover. It cannot guarantee that a partitioned old coordinator did not already
cause an in-game award. That limitation is inherent without a server or a
consensus quorum. The required safety rule is that the new side makes no
competing automated Dibs consumption until recovery chooses one canonical
baseline.

## Required Batch and Dependency Changes

The original foundation order is close but incomplete. B03 and B04 may still be
parallel after their shared prerequisites; B06 must not begin after B05 unless
B05 includes canonical baseline adoption and the transition state machine.

### Revised foundation dependency

```text
B00  Decision record + two-client partition fixtures
  │
B01  SavedVariables validation and recovery backup
  │
B02a Governance bootstrap, identity, GM policy adoption
  ├───────────────┐
  │               │
B03  Local command/ledger chain rules     B04  Transport, anti-entropy, protocol cutover
  │               │                         │
  └───────────────┴───────────┐             │
                              │             │
                     B05a Legacy baseline reconciliation
                              │             │
                     B05b Fenced handoff/recovery state machine
                              │             │
                              └───────> B06 Coordinator ledger activation
```

### Missing prerequisite changes

1. **Split B02 into B02a governance bootstrap and B02b operational policy.**
   B02a establishes GM-only governance records, policy parent/hash rules,
   identity and explicit GM adoption. B02b may then add officer-editable
   operational policy. This prevents a circular officer-rank/coordinator rule.

2. **Add B05a: legacy baseline reconciliation.** It must finish before the
   first coordinator epoch. A safe snapshot codec alone does not choose which
   previously divergent client history is canonical.

3. **Add B05b: fenced coordinator handoff/recovery.** It defines closure,
   `RECOVERY_PENDING`, forced recovery baseline, orphaned late events, and
   coordinator-unavailable award behavior. B06 cannot define these ad hoc.

4. **Make B04 include anti-entropy and protocol cutover state.** Message IDs and
   a GUILD digest alone are insufficient for missed/gapped details or legacy
   writers.

5. **Make B06 depend on B09 only for automatic RC consumption, not for core
   ledger correctness.** B06 must expose coordinator-unavailable and
   manual-evidence paths so Standalone and degraded RC clients remain safe.

## Decision-Specific Compatibility and Migration Summary

| Area | Required compatibility rule | Required migration rule |
|---|---|---|
| Coordinator change | Existing officer may not silently write while disconnected from new coordinator. | Never resequence old events; bind a chosen legacy/recovery baseline hash to the new epoch. |
| Coordinator loss | DIB use becomes unavailable/pending; ordinary loot need not be blocked. | Persist pending proposals separately from transactions. |
| Late/duplicate/out-of-order traffic | Exact duplicate is idempotent; same ID/revision with different hash conflicts; ledger gaps cannot be applied. | Store verified high-water marks/tombstones only; pending gaps stay non-canonical. |
| Guild policy | Governance comes only from current GM; operations follow last valid governance. | GM explicitly adopts policy revision 1; no first-client auto-promotion. |
| Player identity | Full Name-Realm routes messages; aliases are reviewed. | Preserve historical display names and unresolved identities unchanged. |
| Legacy clients | No canonical policy/ledger writes after `V2_ENFORCED`; legacy activity becomes evidence. | Preserve and reconcile post-cutover legacy records manually. |
| Existing history | Do not rewrite Dibs or RC history. | Create Dibs-side provenance/baseline indexes only. |
| RCLootCouncil | Automatic integration is optional and fail-closed. | Keep legacy synthetic rows display-only; never use them as award evidence. |
| WoW limitation | Sender/rank checks are authorization signals, not cryptographic proof. | No migration can convert client-reported data into trusted proof; retain audit source/confidence. |

## Required Decisions Before B00 Is Closed

The following preferred choices should be explicitly adopted before code work:

1. **Safety choice:** No automatic Dibs consumption during
   `COORDINATOR_UNAVAILABLE` or `RECOVERY_PENDING`; queue evidence only.
2. **Governance choice:** Current Guild Master alone can create governance
   changes, including coordinator epoch, officer rank rule, forced recovery,
   protocol cutover, and initial policy adoption.
3. **Handoff choice:** Normal handoff requires predecessor closure/root.
   Unacknowledged loss uses GM-led forced recovery, not immediate promotion.
4. **Legacy choice:** Enable canonical coordinator mode only after a GM-led
   `V2_ENFORCED` cutover and all active policy/award writers are updated.
5. **Baseline choice:** First canonical epoch requires GM-confirmed legacy
   reconciliation baseline; there is no automatic winner among divergent client
   histories.
6. **RC choice:** RCLootCouncil automatic award handling remains optional; lack
   of a verified adapter results in manual evidence/reconciliation, not guessed
   consumption.

ARCHITECTURE REQUIRES CHANGES
