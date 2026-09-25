# Installation, Initialization, and V2 Activation — Architecture Review

Status: Read-only architecture review. No source code, SavedVariables, or protocol
semantics were changed to produce this document.

Scope: `src/modules/Governance.lua`, `src/modules/LegacyBaseline.lua`,
`src/modules/SyncV2.lua`, `src/modules/Ledger.lua`, `src/modules/Permissions.lua`,
`src/modules/Identity.lua`, `src/modules/OperationalPolicy.lua`, `src/Core.lua`,
`src/ui/OfficerUI.lua`, and the B00–B12 audit trail under `docs/audits/`.

---

## 1. Executive Summary

The current activation path is not one lifecycle — it is **three independent
GM-gated subsystems** that happen to be wired together only at the point of
`Governance.ActivateV2`:

1. **Governance** (`db.governance`): `POLICY_UNINITIALIZED` → `GOVERNANCE_ADOPTED`.
2. **Legacy baseline** (`db.legacyBaseline`): `LEGACY_PREPARED` → `BASELINE_APPROVED`.
3. **Authority/protocol** (`db.governance.authority` + `db.sync.v2.protocolState`):
   `LEGACY_LOCAL` → `ACTIVE`/`CUTOVER_PREPARED` → `V2_ENFORCED`.

A fourth subsystem, **Operational Policy** (`db.operationalPolicy`), is a
sibling of Governance (same adopt/idempotent-record pattern) but is **not** a
V2 prerequisite; it only gates Pre-Dibs settings and module management.

None of this is orchestrated. There is no first-run detection, no wizard, and
no single readiness projection. The two entry points a GM must find on their
own are buried inside two different Officer UI tabs (Modules, Sync) and use
none of the same vocabulary. This is exactly what the user in this session
just experienced: `GOVERNANCE_REQUIRED` was surfaced from `ActivateV2` calling
`FinalizeBaseline`, which internally requires `governanceReady()` — a
dependency that is real but invisible until it fails.

**The complexity is real, not accidental** — it exists because of a
correctness constraint uncovered in `P1_Architecture_Challenge.md` (CH-01: an
epoch alone does not fence a partitioned coordinator). But almost all of that
complexity belongs in the *coordinator handoff/recovery/multi-raid* domain,
not in the *first-run, single-coordinator, no-history* case. The three states
are necessary as **internal** representations; they do not need to be
**GM vocabulary**, and for a clean guild the GM-facing path can collapse to
one confirmation.

---

## 2. Current Activation Flow (exact call path today)

For a **brand-new guild install** (no legacy data, single client):

```
GM opens Officer UI → Modules tab
  └─ governanceReady() == false (state.status ~= "GOVERNANCE_ADOPTED")
     └─ Dibs.Governance.CanAdoptInitial(nil)        -- gates button visibility
     └─ [Initialize Guild Governance] → [Initialize]
        └─ Dibs.Governance.AdoptInitial(nil, {...}) 
           = CreateInitialRecord + ApplyRecord
           -- db.governance.status = "GOVERNANCE_ADOPTED", revision = 1
           -- db.governance.future.protocolState stays "LEGACY_LOCAL"
           -- db.governance.authority.state stays "LEGACY_LOCAL"

GM opens Officer UI → Sync tab
  └─ IsGM() && ActivateV2 exists && !IsV2Enforced()
     └─ [Approve baseline and enable V2]
        └─ Dibs.Governance.ActivateV2(nil)
           1. Dibs.LegacyBaseline.GetBaseline() -- nil on clean guild
           2. Dibs.LegacyBaseline.FinalizeBaseline(actor, {acknowledgeIncompleteEvidence=true})
              -- requires governanceReady() == true  (else "GOVERNANCE_REQUIRED")
              -- requires a fresh local-GM roster snapshot
              -- builds an (possibly empty) baseline projection, hashes it,
              --   stamps gmApproval, sets legacyBaseline.status="BASELINE_APPROVED"
           3. authority.state == "LEGACY_LOCAL"
              → Governance.Change(actor, { future = { authority = {
                    state="ACTIVE", coordinator=<local GM>, ledgerEpoch=1,
                    protocolState="CUTOVER_PREPARED",
                    transition={kind="INITIAL", baselineHash=<from step 2>} } } })
              -- persists ACTIVE authority, coordinator = the GM who clicked it
           4. authority.state == "ACTIVE" (now true)
           5. Governance.EnableV2(actor, writers)
              → Governance.Change(actor, { future = { cutover = {
                    state="V2_ENFORCED", writers = writers or {coordinator} } } })
              -- governanceContent() requires: authority.state=="ACTIVE",
              --   an approved baseline hash bound to that authority,
              --   not SYNC_BEHIND, and the coordinator listed among
              --   compatible writers (Sync.CanEnforceV2)
              -- ApplyRecord sets db.governance.future.protocolState="V2_ENFORCED"
              --   and calls Sync.SetProtocolState("V2_ENFORCED", true)
```

Two separate manual UI actions, on two separate pages, with two different
mental models (“Modules” vs. “Guild synchronization”), chain through 5
internal state transitions the GM never sees named. This matches this
session's real support conversation: the GM clicked the V2 button first,
got `GOVERNANCE_REQUIRED`, went and initialized governance, came back, and
still needed to understand that "Protocol" (not "Transport") is the field
that proves success.

For an **upgrade / existing-data guild**, the same two clicks are only safe
*after* an out-of-band, currently UI-less step: calling
`LegacyBaseline.CollectLocalEvidence` (or receiving/staging a recovery
package) and resolving every `OPEN` finding with an explicit decision per
evidence item (`INCLUDE`/`EXCLUDE`/`COMPENSATING_ADJUSTMENT`/`DEFER`). There
is **no OfficerUI surface for this today** — `FinalizeBaseline` will happily
auto-acknowledge incomplete evidence (`acknowledgeIncompleteEvidence = true`
is hardcoded in `ActivateV2`) rather than forcing the GM through reconciliation.
This is the single most dangerous gap found in this review (see §21, P0-1).

---

## 3. Current State Machine

### 3a. Governance status (`db.governance.status`)
| State | Meaning | Transition |
|---|---|---|
| `POLICY_UNINITIALIZED` | Default for every guild, forever, until a GM acts | `AdoptInitial` (GM only, live-roster-verified) |
| `GOVERNANCE_ADOPTED` | Revision ≥ 1, hash-chained, append-only | `Change` (GM only) for any further edit |

### 3b. Legacy baseline status (`db.legacyBaseline.status`)
| State | Meaning | Transition |
|---|---|---|
| `LEGACY_PREPARED` | Evidence may be collected/decided; no baseline yet | `FinalizeBaseline` once every finding is `DECIDED` (or there is no evidence at all) |
| `BASELINE_APPROVED` | `legacyBaselineHash` frozen, GM-stamped | Re-enters `LEGACY_PREPARED` only if a *new* decision is recorded (`RecordDecision` resets `state.baseline = nil`) |

Key fact confirmed by code: with **zero evidence sources**, `baselineProjection`
iterates an empty `state.evidence` table, requires no decisions, and produces
a deterministic, hashable, empty baseline. **An empty/genesis baseline is
already mechanically automatic** — the only manual part is the GM's
`FinalizeBaseline` call itself (identity + freshness check), not per-item
review, because there is nothing to review.

### 3c. Authority state (`db.governance.authority.state`)
| State | Meaning | Entered by |
|---|---|---|
| `LEGACY_LOCAL` | No coordinator, no epoch — B03 local-only ledger writes | Default; also `authorityState()` self-heals here on any structurally invalid data |
| `ACTIVE(E)` | Exactly one coordinator may write epoch `E` | `INITIAL` transition (requires approved baseline) or `NORMAL_HANDOFF`/`FORCED_RECOVERY` |
| `HANDOFF_CLOSING` | Old coordinator has published `finalSeq`/`rootHash`, may not write further | `BeginHandoff` by current coordinator |
| `COORDINATOR_UNAVAILABLE` | GM has explicitly declared the coordinator unreachable | `MarkCoordinatorUnavailable` (GM only) |
| `RECOVERY_PENDING` | GM has explicitly requested forced recovery | `EnterRecoveryPending` (GM only) |

### 3d. Protocol state (`db.governance.future.protocolState`, mirrored into `db.sync.v2.protocolState`)
| State | Meaning |
|---|---|
| `LEGACY_LOCAL` | No distributed sequencing; `Ledger.CommitDibUse`/`CommitSeasonAllocation` fall back to `CommitLocalTransaction` for everyone |
| `CUTOVER_PREPARED` | Authority is `ACTIVE`, but cutover not yet approved — an intermediate value that only exists between step 3 and step 5 of §2; not independently reachable as a stable rest state through the UI today |
| `V2_ENFORCED` | Only the current `ACTIVE` coordinator may create `AWARD_COMMIT`s; everyone else is fenced to `PENDING_RECONCILIATION` proposals |

### Prerequisites to reach `V2_ENFORCED` (from `governanceContent`'s `cutover` branch)
- `current.state == "ACTIVE"` (authority already transitioned once)
- `current.transition.baselineHash` is set **and** matches `LegacyBaseline.GetBaseline().legacyBaselineHash`
- `not Sync.IsSyncBehind()`
- The current coordinator's `memberKey` is present in the `writers` list
- `Sync.CanEnforceV2(writers)` — every *other* listed writer must be a **guild
  member who has already sent at least one V2 envelope** with
  `protocol.major == 2` and `capabilities.authoritySignals == true` (this
  version always sets that capability true, so in practice it means "has been
  online and communicated at least once since this client loaded")

---

## 4. Why `LEGACY_LOCAL` Exists

| Reason found in code | Classification |
|---|---|
| Default rest state for every guild that has never run `AdoptInitial`/`ActivateV2` — the vast majority of small guilds who never need multi-raid ordering | **REQUIRED** (compatibility + default-safe) |
| `authorityState()` self-heals to `LEGACY_LOCAL` on any structurally invalid `db.governance.authority` (corruption, foreign schema, unknown state string) | **REQUIRED** (fail-closed recovery) |
| `Ledger.CommitLocalTransaction`/`CommitDibUse`/`CommitSeasonAllocation` all branch on `not v2Enforced()` to preserve pre-B06 single-client semantics exactly | **MIGRATION_ONLY** for existing guilds; **REQUIRED** as the fallback for any guild that chooses not to enforce V2 (solo player, small guild, no multi-raid) |
| `SyncV2.ensure()` defaults `protocolState = "LEGACY_LOCAL"` for a brand-new `db.sync.v2` | **REQUIRED** default |
| Tests assert `LEGACY_LOCAL` behavior explicitly as its own contract (`B00 distributed-ledger architecture contracts / keeps legacy single-client behavior as immutable evidence`) | **REQUIRED** (regression contract) |
| GM never *has* to move past `LEGACY_LOCAL` — no code forces cutover; it is fully opt-in, forever | **REQUIRED** for guilds that use one active client at a time (a real, supported, common operating mode — not merely a transitional state) |

**Conclusion:** `LEGACY_LOCAL` is not historical technical debt. It is the
correct rest state for single-writer guilds and the correct fail-closed
target for corrupted authority data. It is not, however, a state the GM
should ever have to *name* or understand — see §11 and Q1.

---

## 5. Clean Installation Analysis

"Clean" is defined precisely by: `db.legacyBaseline.evidence` is empty (no
`CollectEvidence`/`CollectLocalEvidence`/staged recovery has ever run) **and**
`db.ledger.transactions` / `db.preDibs.requests` are empty at the time
evidence would be collected.

What is actually required for a clean guild to reach `V2_ENFORCED`:
1. Confirm actor is the live-roster GM (`Identity.IsCurrentGuildMaster`).
2. `Governance.AdoptInitial` — one hash-chained record, revision 1.
3. `LegacyBaseline.FinalizeBaseline` over **zero evidence** — mechanically
   produces a deterministic `GENESIS`-equivalent baseline; no per-item
   decisions exist to make. `acknowledgeIncompleteEvidence` should not even
   be relevant here because `incompleteSources()` iterates
   `state.sources`, which is also empty.
4. `Governance.Change` with `future.authority = {state="ACTIVE", ledgerEpoch=1,
   transition={kind="INITIAL", baselineHash=<step 3>}}` — coordinator becomes
   the GM who is running the wizard (or an explicit choice, see §7).
5. `Governance.EnableV2` with a writer list — for a first-run wizard, the
   correct default is **`{ coordinator }` only** (a "solo GM" or "single
   raid team" bootstrap needs no other compatible writer yet); more writers
   can be added the moment they're needed (see §8 compatibility model).

**Nothing above requires the GM to understand ledger epochs, hashes, or
protocol constants.** It requires exactly one identity check (already
enforced) and one GM confirmation click, because steps 2–5 have no
GM-meaningful decision content when there is no legacy data. This directly
answers Q3/Q4 as YES/CONDITIONAL below.

---

## 6. Upgrade Installation Analysis

"Upgrade" = evidence exists (`db.ledger.transactions` and/or
`db.preDibs.requests` are non-empty) at the time of first governance/baseline
consideration. Required, and **not safely automatable**:

1. `LegacyBaseline.CollectLocalEvidence(actor)` — pulls existing ledger +
   Pre-Dibs into evidence (already implemented, but not exposed anywhere in
   OfficerUI — a gap, see §10).
2. `rebuildFindings` will surface `UNRESOLVED_IDENTITY`,
   `EXACT_DUPLICATE_EVIDENCE`, `LEGACY_ID_CONTENT_CONFLICT`,
   `LEGACY_IDENTITY_CONFLICT`, `LIKELY_DUPLICATE_AWARD`, or
   `PEER_EVIDENCE_DIVERGENCE` findings whenever there is more than one
   client/source of legacy data (multi-alt accounts, prior manual edits,
   divergent SavedVariables between officers).
3. Each `OPEN` finding requires an explicit
   `INCLUDE`/`EXCLUDE`/`COMPENSATING_ADJUSTMENT`/`DEFER` decision
   (`LegacyBaseline.RecordDecision`) before `FinalizeBaseline` can succeed
   without acknowledgement bypass.
4. Only then should `FinalizeBaseline` be called — and
   **`acknowledgeIncompleteEvidence` must not be silently hardcoded `true`**
   the way `ActivateV2` does today, because that flag exists specifically to
   let a GM knowingly proceed with partial evidence; auto-setting it defeats
   the entire B05a safety design.

This is real, necessary complexity that **must remain a distinct flow** from
clean install. Collapsing it into "click Initialize DIBS" without surfacing
findings would silently launder unresolved legacy conflicts into an approved,
immutable baseline hash — a direct P0 risk (see §21).

---

## 7. Coordinator Bootstrap Analysis

- **Who can be coordinator:** any live-roster member whose `Identity.CreateSnapshot`
  succeeds; the *initial* transition (`INITIAL`) requires the actor to be
  `currentGMSnapshot` (i.e., the GM performs the bootstrap), but the
  `coordinator` field placed into authority is **not required to equal the
  actor** in `authorityContent` validation itself — `ActivateV2`'s current
  implementation *always* assigns the acting GM as coordinator
  (`current.memberKey, current.displayName` in the `CUTOVER_PREPARED` prepare
  step). There is no UI path today to bootstrap with an Officer as initial
  coordinator, even though the underlying `Governance.Change` API would
  accept it if a GM explicitly authored that content.
- **Can the GM be coordinator?** Yes — and is, by default, today.
- **Can an Officer be coordinator?** Architecturally yes (authority record only
  requires *any* resolvable roster identity + a live GM as author of the
  governance record establishing it); operationally, no first-run affordance
  exists to choose one.
- **Must the coordinator remain online?** No for correctness — `LEGACY_LOCAL`-adjacent
  fallback does not exist while `V2_ENFORCED`; instead, absence is handled by
  explicit GM action: `MarkCoordinatorUnavailable` → `COORDINATOR_UNAVAILABLE`,
  during which all awards become `PENDING_RECONCILIATION` (zero ledger effect,
  by design — ADR-001). There is no automatic timeout/heartbeat-based
  demotion; a GM must notice and explicitly declare unavailability.
- **Handoff:** `BeginHandoff` (current coordinator only) → `HANDOFF_CLOSING`
  with a signed closure (`finalSeq`, `rootHash`) → a `NORMAL_HANDOFF` governance
  record naming the new coordinator and binding the exact parent closure.
- **Recovery:** GM-only `EnterRecoveryPending` → `FORCED_RECOVERY` transition
  bound to a **newly GM-approved baseline** (not the original one), with
  `recoveryAudit.reason` mandatory. Late/excluded evidence remains permanently
  `ORPHANED_EVIDENCE`, never silently replayed.

**Conclusion for the wizard:** "This character is eligible to act as the
initial coordinator" → "[Use this character] [Choose another Officer]" is
architecturally sound (Officer coordinators are permitted), but the second
option requires new orchestration code (today `ActivateV2` hardcodes the
actor as coordinator) and must still be authored by the live GM
(`currentGMSnapshot` remains the create-record gate regardless of who the
`coordinator` field names). This is a legitimate **new** capability to add,
not merely UI polish — flag it as scoped future work rather than in-scope for
the first pass (§19).

A coordinator **is** a single point of failure by design (ADR-001 explicitly
trades availability for integrity while the coordinator is unreachable). The
wizard must say this plainly — see §12 UI copy.

---

## 8. V2 Compatibility Requirements — who actually needs it

`Sync.CanEnforceV2(writers)` is checked once, at `EnableV2` time, against an
explicit `writers` list (defaults to `{ coordinator }` if omitted). It does
**not** require the entire guild roster, all officers, or all raid members to
be compatible. It requires only:

- the coordinator itself (always includes local player by construction), and
- any other Name-Realm explicitly added to the `writers` list by the GM.

**"Writer" here means: someone whose local client is allowed to originate
canonical ledger commits** — i.e., another potential coordinator/officer who
might take over via handoff, not every guild member and not every raid
participant. Ordinary players and even most officers never need to be
"V2 compatible" — they only ever *read* synced state or submit
`PENDING_RECONCILIATION` proposals that the coordinator reconciles.

Old (pre-B04/B06) clients are simply never in the `writers` list; V2
activation does not block on them, and they continue to operate in
whatever legacy/local mode their own client understands, without being
forced to update, because sync only announces `V2_ENFORCED` records to
peers who already speak the V2 envelope.

**Recommendation:** the wizard's "Guild Compatibility" step should default to
zero required peers (`writers = {coordinator}`) unless the GM explicitly adds
backup coordinators, and should label the concept "Backup coordinators" (or
"who can take over sequencing"), not "guild compatibility," to avoid implying
a whole-roster requirement that does not exist in the code.

---

## 9. Existing APIs to Reuse (do not duplicate)

| Capability | Existing API | Notes |
|---|---|---|
| GM identity/authority check | `Dibs.Identity.IsCurrentGuildMaster`, `Dibs.Identity.CreateSnapshot` | Already the single source of truth; do not re-derive from `IsGuildLeader()` directly in wizard code |
| Governance readiness | `Dibs.Governance.GetState()`, `Governance.CanAdoptInitial`, `Governance.AdoptInitial` | Reuse verbatim |
| Authority/coordinator state | `Dibs.Governance.GetAuthorityState()`, `Governance.BeginHandoff`, `Governance.EnterRecoveryPending`, `Governance.MarkCoordinatorUnavailable` | Reuse verbatim; do not re-implement handoff/recovery in the wizard |
| Baseline state | `Dibs.LegacyBaseline.GetState()`, `GetBaseline()`, `PreviewBaseline()`, `CollectLocalEvidence`, `RecordDecision`, `FinalizeBaseline` | `CollectLocalEvidence` + `RecordDecision` currently have **no UI**; the wizard/upgrade flow should be the first consumer, not a duplicate importer |
| Cutover | `Dibs.Governance.ActivateV2`, `Governance.EnableV2` | `ActivateV2` is already close to a one-call orchestrator; its main flaw is silently hardcoding `acknowledgeIncompleteEvidence = true` — see §21 P0-1 |
| Compatibility | `Dibs.Sync.CanEnforceV2`, `Sync.GetPeerStatuses()` | Reuse for the "Guild Compatibility"/backup-coordinator step |
| Protected mutation boundary | `Dibs.ProtectedActions.Execute`, `Dibs.Permissions.Evaluate` | `installation.mode.set` already exists as a protected action id; the same pattern (`ADMIN_ACTIONS`/`GM_ONLY_ACTIONS` in `Permissions.lua`) is the correct place to add any new installation actions, not a parallel authorization system |
| Sync visibility | `Dibs.Sync.GetStatus()`, `GetSynchronizationStatus()`, `GetProtocolState()` | Reuse for diagnostics/technical-details panel |
| Module gating UI pattern | `src/ui/OfficerUI.lua` "Modules" tab governance-bootstrap block (`self.governanceBootstrapPending`) | This exact pending/confirm/cancel UI pattern (already tested, already GM-gated) is the right shape to extend into a full wizard, not a new component |

---

## 10. Existing APIs That Create Unnecessary Complexity (for the GM-facing surface only)

- **Two disconnected buttons** (`Modules` tab "Initialize Guild Governance",
  `Sync` tab "Approve baseline and enable V2") force the GM to discover two
  unrelated screens and manually sequence them. The *underlying* dependency
  (`ActivateV2` requires governance) is correct; the *lack of a single entry
  point that enforces the sequence itself* is the actual complexity.
- **`ActivateV2`'s implicit auto-baseline** silently creates and approves a
  baseline over whatever evidence happens to exist (empty or not) with
  `acknowledgeIncompleteEvidence = true` hardcoded. On a clean guild this is
  harmless (there is nothing to acknowledge). On an upgrade guild with
  unresolved findings, this is a correctness hazard dressed up as
  convenience — it is complexity in the wrong place (hidden) instead of the
  right place (an explicit reconciliation screen).
- **`CollectLocalEvidence`/`RecordDecision` have zero UI** — the *only* fully
  built, tested reconciliation machinery in the codebase (B05a) is
  unreachable by a normal GM today except via `/run` or a future officer
  screen. This is precisely the kind of internal-API-only surface the review
  brief warns against normalizing.
- **`CUTOVER_PREPARED` is a transient value with no stable UI representation**
  — it exists for one internal step inside `ActivateV2` and is never shown,
  named, or made resumable/observable to the GM. It should remain internal
  (per Design B/C in §16) but the *installation manager* should be able to
  detect and resume from it (a partial `ActivateV2` failure could leave
  authority in `CUTOVER_PREPARED` without V2 enforced — see §14).
- **Sync page's "Transport" vs. "Protocol" fields have overlapping names**
  (`LOCAL`/`LEGACY_LOCAL` appear in both, from different subsystems:
  `Sync.GetStatus().state` vs. `Sync.GetProtocolState()`), which is exactly
  the confusion in this session's prior turn. This is a presentation-layer
  defect, not a protocol one — see §18.

---

## 11. Installation State Proposal

**Do not persist a competing installation state.** Derive it, every time, from
the four authoritative subsystems already listed. A minimal derivation
function (illustrative, not a mandated schema) reads only existing state:

```
Installation.GetStatus()
  isGM = Identity.IsCurrentGuildMaster(currentPlayer)
  governance = Governance.GetState()               -- POLICY_UNINITIALIZED | GOVERNANCE_ADOPTED
  authority  = Governance.GetAuthorityState()       -- LEGACY_LOCAL | ACTIVE | HANDOFF_CLOSING | ...
  baseline   = LegacyBaseline.GetState()            -- LEGACY_PREPARED | BASELINE_APPROVED
  findings   = LegacyBaseline.GetFindings()         -- for "OPEN" count
  protocol   = Governance.IsV2Enforced()
  syncBehind = Sync.IsSyncBehind()
```

The smallest *presentation* state machine that can be derived (not stored)
from the above, using existing names only where they already exist and new
names only for GM-facing labels:

| Derived label | Condition (from existing state) |
|---|---|
| `NOT_INITIALIZED` | `governance.status == "POLICY_UNINITIALIZED"` |
| `GOVERNANCE_READY` | governance adopted, `authority.state == "LEGACY_LOCAL"` |
| `LEGACY_RECONCILIATION_REQUIRED` | governance adopted, evidence exists, any finding is `OPEN` |
| `READY_FOR_CANONICAL_LEDGER` | governance adopted, no `OPEN` findings (including zero-evidence case), `authority.state == "LEGACY_LOCAL"` |
| `CANONICAL_LEDGER_ACTIVE` | `Governance.IsV2Enforced() == true` |
| `COORDINATOR_UNAVAILABLE` / `RECOVERY_REQUIRED` | pass through `authority.state` verbatim (already GM-actionable via existing screens) |
| `SYNC_BEHIND` | `Sync.IsSyncBehind() == true` — orthogonal to installation, surfaced as a blocker/warning, not a state |

This is intentionally **not** a stored enum. Storing a sixth, independent copy
of "installation state" is precisely the anti-pattern the review brief warns
against (a static/duplicated truth that can drift from the four real
subsystems). Compute it on demand in the projection described in §13/§17.

---

## 12. First-Run Wizard Proposal

Trigger condition (see §15 for the exact event):

```
if Identity.IsCurrentGuildMaster(local player)
   and derived label in { NOT_INITIALIZED, GOVERNANCE_READY, LEGACY_RECONCILIATION_REQUIRED, READY_FOR_CANONICAL_LEDGER }
   and GM has not dismissed/"remind later" this session
then offer the wizard entry point (not a forced modal)
```

Screen sequence, each step reading only existing derived state and calling
only existing (or minimally extended) authoritative APIs:

1. **Guild Governance** — Ready / Needs initialization → calls
   `Governance.AdoptInitial` (existing).
2. **Existing DIBS Data** — "None detected" (zero evidence) vs. "Historical
   data detected" → if the latter, this step becomes a distinct sub-flow
   (§6), reusing `CollectLocalEvidence` + a **new** findings-review screen
   (the one genuinely missing UI piece) before it can show "Ready."
3. **Coordinator** — shows the GM's own Name-Realm as the default candidate
   (per §7); "Choose another Officer" is scoped as future work, not blocking
   this pass.
4. **Backup coordinators / compatibility** — defaults to none required
   (`writers = {coordinator}`); optionally add other online, already-seen
   (`Sync.GetPeerStatuses()`) Officers.
5. **Synchronization** — read-only confirmation that transport is available
   (`Sync.GetStatus()`), not a decision point.
6. **Canonical Ledger** — final confirm screen; on confirmation, runs the
   staged sequence in §14, one step at a time, each idempotent and resumable.

Final action label: **[Initialize DIBS]**. Internally this still calls
`Governance.AdoptInitial` (if needed) → `LegacyBaseline.FinalizeBaseline`
(only after findings are resolved, never with the hardcoded bypass) →
`Governance.Change` (authority ACTIVE) → `Governance.EnableV2`. This is the
same sequence as today's `ActivateV2`, restructured to (a) never hide an
`OPEN` finding, and (b) be resumable (§14).

Non-GM view, whenever `governance.status ~= "GOVERNANCE_ADOPTED"` or
`authority.state == "LEGACY_LOCAL"` and the viewer is not the live GM:

> "DIBS has not yet been initialized for this guild. The Guild Master must
> complete the initial setup."

No buttons. This matches the existing Officer navigation gating pattern
(`B11d Officer navigation / keeps the Officer navigation hidden from a normal
Player`) — reuse it, do not build a new visibility system.

---

## 13. Proposed Simplified State Machine

For the **GM-facing wizard only** (internal subsystems keep their exact
existing states — nothing here replaces §3):

```
NOT_INITIALIZED
   │  (GM: Initialize Guild Governance)
   ▼
GOVERNANCE_READY ──────────────┐
   │ (no legacy evidence)      │ (legacy evidence found)
   ▼                           ▼
READY_FOR_CANONICAL_LEDGER   LEGACY_RECONCILIATION_REQUIRED
   │                           │ (GM resolves every OPEN finding)
   │◄──────────────────────────┘
   │  (GM: Initialize DIBS)
   ▼
CANONICAL_LEDGER_ACTIVE  (== V2_ENFORCED internally)
```

`COORDINATOR_UNAVAILABLE`, `RECOVERY_REQUIRED`, and `SYNC_BEHIND` are
orthogonal overlays on top of `CANONICAL_LEDGER_ACTIVE`, not additional
linear stages — they are already correctly modeled as authority states and
should stay that way (§3c), just labeled for humans in the officer dashboard
(§17), not folded into the installation wizard's linear flow.

---

## 14. Idempotency and Resume Model

| Stage | Prerequisite | Mutation | Idempotency today | Failure/resume behavior |
|---|---|---|---|---|
| Governance adoption | `status == POLICY_UNINITIALIZED`, live GM | `AdoptInitial` writes revision 1 | `ApplyRecord` treats same-revision/same-hash as `IDEMPOTENT_REPLAY`; a second click after success returns `GOVERNANCE_ALREADY_ADOPTED` from `CreateInitialRecord`'s guard — **safe to retry** |
| Evidence collection | none (additive) | `CollectEvidence`/`CollectLocalEvidence` | Existing evidence with matching `sourceRecordHash` is a no-op; conflicting hash for the same `evidenceId` is rejected (`EVIDENCE_ID_CONFLICT`) rather than silently overwritten — **safe to retry** |
| Decision recording | evidence exists, live officer/GM | `RecordDecision` | A duplicate decision (same computed `decisionId`) returns `IDEMPOTENT_REPLAY`; changing a decision requires explicit `supersedes` (no silent overwrite) — **safe to retry, not silently mutable** |
| Baseline finalize | governance adopted, fresh GM, (findings resolved) | `FinalizeBaseline` | Recomputes deterministically from current evidence/decisions; re-running with unchanged inputs reproduces the same hash and simply re-stamps `gmApproval` — **safe to retry**, though re-approval timestamp changes (acceptable, it's an approval act, not ledger content) |
| Authority `INITIAL` transition | `LEGACY_LOCAL`, approved baseline, live GM | `Governance.Change` (authority) | **Not idempotent across different baselines**: if baseline hash changed between attempts, a stale in-flight wizard would bind a different `transition.baselineHash`. Resume logic must re-read `LegacyBaseline.GetBaseline()` immediately before this step, not cache it from step 2 of the wizard. |
| Cutover (`EnableV2`) | `ACTIVE`, approved baseline bound to authority, `!SyncBehind`, compatible writers | `Governance.Change` (cutover) | If authority is `ACTIVE` but cutover was never applied (client closed mid-flow), state is stable at `CUTOVER_PREPARED`/`LEGACY_LOCAL`-protocol with `ACTIVE` authority — **the wizard can detect this exact partial state** (`authority.state=="ACTIVE" and protocolState~="V2_ENFORCED"`) and resume directly at step 5 without repeating steps 1–4. `Governance.IsV2Enforced()` already short-circuits a second `ActivateV2` call to `V2_ALREADY_ENFORCED`. |

**No stage rolls back an already-applied governance/authority/baseline
record.** This matches the append-only, hash-chained design intentionally —
"resume" means "detect the next unmet prerequisite and continue," never
"undo." A wizard implementation must re-derive its current step from
`Installation.GetStatus()` on every open, not from its own remembered
progress, to avoid drift from the authoritative subsystems (this is the same
principle as §11).

---

## 15. Failure / Recovery Model

- If the client disconnects/reloads mid-wizard, the derived state in §11 is
  exact and resumable — there is nothing to "clean up," because each
  subsystem either fully committed or made no change (all validation happens
  before any mutation in `buildDetachedTransaction`/`createRecord` style
  functions throughout the codebase).
- If a *second* GM candidate (e.g., after a GM transfer) opens the wizard
  after `GOVERNANCE_ADOPTED` already exists, `CreateInitialRecord`/`Change`
  both re-validate `currentGMSnapshot` fresh from the live roster — an old
  session cannot replay a stale authorization.
- If legacy reconciliation is abandoned partway (some findings decided, some
  not), `FinalizeBaseline` simply keeps failing with
  `RECONCILIATION_DECISION_REQUIRED`/`RECONCILIATION_UNRESOLVED` — this is
  correct fail-closed behavior and needs no new recovery path, only a UI that
  shows *which* findings remain (currently invisible to any GM).
- Existing `COORDINATOR_UNAVAILABLE`/`RECOVERY_PENDING`/`FORCED_RECOVERY`
  paths are unaffected by this proposal and must not be re-implemented inside
  the installation wizard; the wizard should link out to the existing
  officer recovery surface once `CANONICAL_LEDGER_ACTIVE` overlays into one
  of those states.

---

## 16. SavedVariables Impact

**None required.** Every field this review recommends surfacing already
exists in `defaultDB` (`governance`, `legacyBaseline`, `sync.v2`,
`operationalPolicy`) at schema versions already migrated by `Core.lua`
(`ROOT_SCHEMA_VERSION = 6`, `GUILD_SCHEMA_VERSION = 7`). If a persisted
"onboarding dismissed / remind later" flag is wanted (§15/§12's "do not annoy
every login"), it should be a small **additive, non-guild-authoritative**
field — most naturally under `Dibs.GetLocalDB()` (already used for
per-character UI/local preferences such as `developerModeEnabled`), **not**
under guild-scoped `db`, because "I dismissed the wizard" is a per-character
UI preference, not a guild governance fact. This avoids ever conflating
"wizard dismissed" with "guild initialized," directly answering the
TAG=READY/TAG=INSTALLED question in Q5.

---

## 17. Security / Authority Impact

- Every mutating step already flows through `currentGMSnapshot`/
  `Identity.IsCurrentGuildMaster`, freshly re-validated against the live
  roster on each call — a wizard adds no new authority surface, it only
  needs to *call* these existing gates in the right order and *hide* buttons
  a non-GM cannot use (reusing the existing Officer navigation
  visibility pattern, §12).
- `installation.mode.set` already exists in `ADMIN_ACTIONS`/`GM_ONLY_ACTIONS`
  in `Permissions.lua` — if any new orchestration-level action ID is added
  (e.g., a single "installation.initialize" wrapper for audit/telemetry), it
  should sit beside it in the same tables, and its `Execute` implementation
  should be a thin orchestrator that calls the existing Governance/
  LegacyBaseline APIs — never a second copy of their validation logic.
- No new attack surface: the wizard cannot let an Officer or Player implicitly
  become coordinator or bootstrap governance; every code path that could do
  so already independently re-checks `currentGMSnapshot` server-independent
  (client-authoritative, single-writer-per-command, hash-chained) — consistent
  with the rest of the addon's trust model (no server, so the "authority" is
  procedural: GM-only actions validated against the live roster).

---

## 18. UI Proposal

Normal GM-facing labels (persisted/wire identifiers stay exactly as-is):

| Persisted/protocol term | GM-facing label |
|---|---|
| `V2_ENFORCED` | "Canonical Ledger: Active" (status) / "Enable canonical ledger" (action) |
| `LEGACY_LOCAL` (protocol) | "Canonical Ledger: Not enabled" |
| `CUTOVER_PREPARED` | (never shown; internal-only, per §10) |
| `legacyBaselineHash` | "Historical data reference" (technical details only) |
| `ledgerEpoch` | "Sequence generation" (technical details only) |
| authority `ACTIVE`/`coordinator` | "Coordinator: <Name-Realm>" |
| `COORDINATOR_UNAVAILABLE` | "Coordinator unreachable — awards are being queued for review" |
| `RECOVERY_PENDING` | "Recovery in progress — no awards will be recorded until resolved" |
| Sync `Transport` (`Sync.GetStatus().state`) | "Connection: Ready / Unavailable" |
| Sync `Protocol` (`Sync.GetProtocolState()`) | "Ledger mode: Canonical / Legacy" |

A single **"Technical Details / Diagnostics"** disclosure (collapsed by
default) on both the wizard's final screen and the officer dashboard should
show the raw values from `Governance.GetState()`, `GetAuthorityState()`,
`LegacyBaseline.GetState()`, and `Sync.GetStatus()` verbatim, for support and
debugging — this satisfies the audit trail without inventing a second
vocabulary for logs/support.

---

## 19. Migration Plan

This review recommends, but does not implement:

1. Add a findings-review screen backed by
   `LegacyBaseline.GetFindings()`/`RecordDecision` (currently missing UI,
   §10) — required before any wizard can safely handle upgrade guilds.
2. Replace `ActivateV2`'s hardcoded
   `acknowledgeIncompleteEvidence = true` with a caller-supplied flag that
   the wizard only sets `true` after the GM has seen and explicitly
   acknowledged remaining `OPEN`/incomplete sources (upgrade path), and never
   sets it at all for the zero-evidence clean path (irrelevant there).
3. Add the derived-status projection (§11) as a read-only function consumed
   by (a) the wizard, (b) the officer Sync/Modules tabs (replacing their
   independent ad hoc checks), and (c) a support/diagnostics dump.
4. Build the wizard screens on top of #1–#3 using only existing mutation
   APIs (§9); do not add new persisted state.
5. (Optional, later) Add explicit coordinator-candidate selection
   (§7 second bullet), which requires a small `Governance.ActivateV2`
   extension to accept a `coordinator` override actor rather than hardcoding
   the caller — scope as a follow-up, not part of this pass.
6. Existing SavedVariables, ledger, Pre-Dibs, seasons, rank rules, governance
   records, operational policy, audit history, and RCLootCouncil integration
   are all read, never rewritten, by every step above — no destructive
   migration, no implicit reset, consistent with the existing migration
   contract in `Core.lua`.

---

## 20. Test Strategy

Existing coverage already proves the mutation primitives this proposal
reuses (`governance_bootstrap_spec.lua`, `legacy_baseline_recovery_spec.lua`,
`b05b_authority_recovery_spec.lua`, `b06_distributed_ledger_spec.lua`). New
tests needed are for the **orchestration layer only**:

- Derived-status projection reflects each of the states in §11 correctly for
  a scripted sequence of subsystem states (no new mutation to test, only
  projection correctness).
- Wizard "Initialize DIBS" on a zero-evidence guild reaches
  `CANONICAL_LEDGER_ACTIVE` in one confirmation and is idempotent on a
  second click (`V2_ALREADY_ENFORCED`).
- Wizard blocks the final confirmation while any finding is `OPEN`, and the
  confirmation becomes available only after all decisions are recorded.
- Resuming after a simulated reload with authority `ACTIVE` but protocol not
  yet `V2_ENFORCED` completes at the cutover step only, without re-creating
  governance or re-approving a different baseline.
- Non-GM viewer sees the read-only explanatory message and no actionable
  buttons, for each of `NOT_INITIALIZED`/`GOVERNANCE_READY`/
  `LEGACY_RECONCILIATION_REQUIRED`.
- `acknowledgeIncompleteEvidence` is never implicitly `true` when reachable
  through the wizard on an upgrade guild with `OPEN` findings (regression
  test guarding against reintroducing the current hazard).

---

## 21. Risk Register

| ID | Severity | Description | Mitigation |
|---|---|---|---|
| P0-1 | P0 | `Governance.ActivateV2` hardcodes `acknowledgeIncompleteEvidence = true`, so any GM who clicks "Approve baseline and enable V2" on a guild with unresolved legacy findings silently freezes an incomplete/possibly-wrong baseline into the immutable authority chain | Remove the hardcoded bypass; require the wizard/UI to obtain explicit GM acknowledgement only after showing the actual `OPEN` findings (§19 item 2) |
| P0-2 | P0 | No UI exists for `CollectLocalEvidence`/`RecordDecision`, so today the *only* way to avoid P0-1 on an upgrade guild is undocumented `/run` usage — the exact anti-pattern the review brief warns about | Build the findings-review screen (§19 item 1) before enabling any "one click" wizard for guilds with existing data |
| P1-1 | P1 | Sync page's "Transport" and "Protocol" labels overlap in meaning (`LOCAL`) across two different subsystems, causing exactly the GM confusion observed in this session | Apply the label mapping in §18 |
| P1-2 | P1 | `ActivateV2` always assigns the acting GM as coordinator; no path exists to bootstrap with an Officer as initial coordinator despite the architecture permitting it | Scope as explicit follow-up (§7, §19 item 5); do not block the main wizard on it |
| P1-3 | P1 | `Sync.CanEnforceV2` requires listed writers to have been *seen* communicating with `authoritySignals` at least once; a wizard run immediately after guild creation (no peer has logged in yet) will correctly default to `writers={coordinator}`, but if a GM manually adds an offline/never-seen Officer, cutover will fail with `WRITER_COMPATIBILITY_REQUIRED` with no explanation of *why* in the current UI | Wizard step 4 (§12) should only offer already-detected (`Sync.GetPeerStatuses()`), already-online peers as selectable writer candidates, never a free-text name |
| P2-1 | P2 | No first-run event triggers the wizard at all today; a GM must discover both existing screens unaided | Add the derived-condition trigger from §12/§15 |
| P2-2 | P2 | `CUTOVER_PREPARED` is reachable as a rest state on partial failure (§14) but is never shown to the GM if the wizard is abandoned there | Ensure the derived-status projection (§11) treats "authority ACTIVE, protocol not yet V2_ENFORCED" as `READY_FOR_CANONICAL_LEDGER`-with-a-resume-hint, not as a dead end |
| P3-1 | P3 | Technical terms (`V2_ENFORCED`, `legacyBaselineHash`, `ledgerEpoch`) are the only vocabulary currently exposed anywhere in the UI | Apply §18 presentation layer; keep raw terms in a diagnostics disclosure only |

---

## Decision Section

**Q1. Is `LEGACY_LOCAL` still necessary for clean installations?**
**ONLY INTERNALLY.** It remains the correct default rest state and fail-closed
recovery target (§4), and it is the correct steady state for any guild that
never opts into multi-raid canonical sequencing. It should never be a term a
GM has to read or choose; the wizard should offer "Enable canonical ledger"
as an action, not "leave LEGACY_LOCAL" as a state to understand.

**Q2. Can a clean installation safely bootstrap directly toward `V2_ENFORCED`?**
**CONDITIONAL — YES, with one condition:** the guild has zero legacy evidence
(§5) and the GM completes one confirmation that internally performs
governance adoption, an automatic empty-baseline finalize, authority
activation naming the GM as coordinator, and cutover with `writers =
{coordinator}`. All four internal steps are individually already safe and
idempotent (§14); none require a GM decision when there is no evidence.

**Q3. Can an empty/genesis baseline be automatically created for a truly clean guild?**
**YES, conditionally on "truly clean" being verified first.** `buildBaseline`
already produces a deterministic hash over zero evidence with no required
decisions (§3b, §5). The only manual part that must remain is one GM
confirmation act (`FinalizeBaseline`'s `localSnapshot`/live-roster GM check),
because baseline approval is an authority act, not merely a data computation.

**Q4. Can V2 activation be reduced to one GM-facing "Initialize DIBS" workflow?**
**CONDITIONAL — YES for clean guilds; NO (must stay multi-screen) for guilds
with legacy evidence**, because §6/§21 P0-1/P0-2 show that collapsing
reconciliation into a single click is a genuine data-integrity hazard, not
merely a UX inconvenience. The wizard should present as one flow with a
built-in branch, not force upgrade guilds through a second, undiscoverable
screen.

**Q5. Should `TAG=READY` / `TAG=INSTALLED` exist?**
**ONLY AS BUILD METADATA**, and only if genuinely useful for
package/build identification (already served by `Dibs.VERSION` in
`Core.lua`) — never as the source of truth for guild initialization or V2
state. The authoritative installation state must always be derived live from
`Governance`, `LegacyBaseline`, `Sync`, and `Ledger` (§11), never from a
static Lua constant, because a constant cannot reflect per-guild governance
history and would immediately drift from the real hash-chained state the
first time two guilds on the same account diverge.

**Q6. What state should trigger the installation wizard?**
`Identity.IsCurrentGuildMaster(local player) == true` **and** the derived
label (§11) is one of `NOT_INITIALIZED`, `GOVERNANCE_READY`,
`LEGACY_RECONCILIATION_REQUIRED`, or `READY_FOR_CANONICAL_LEDGER` **and** the
event is `PLAYER_ENTERING_WORLD` or `GUILD_ROSTER_UPDATE` (whichever first
gives `Identity.ResolveRosterMember` a `RESOLVED`/fresh roster generation) —
never `ADDON_LOADED`/`PLAYER_LOGIN` directly, because guild/roster identity
is not yet reliably resolvable that early (`Identity.RefreshRoster`'s
freshness model already requires a settled roster, matching the existing
`GUILD_ROSTER_UPDATE` invalidation wiring in `Core.lua`).

**Q7. Should `V2_ENFORCED` remain visible to normal users or become an internal technical state?**
**Internal technical state.** Normal GMs/Officers should see "Canonical
Ledger: Active/Not enabled" (§18); `V2_ENFORCED` itself should only appear in
the Technical Details/Diagnostics disclosure, exactly as the review brief's
target UX specifies.

**Q8. What is the minimum number of explicit GM confirmations actually necessary?**
**One**, for a clean guild (the final "Initialize DIBS" click, after
reviewing the four read-only summary rows). **Two or more**, for an upgrade
guild: one to acknowledge/resolve legacy findings (which may itself require
several per-item decisions, irreducible per §6/§21 P0-1/P0-2), and one final
confirmation to activate canonical sequencing.

**Q9. Which current manual steps can safely disappear?**
- Manually discovering and opening two separate Officer UI tabs in the
  correct order.
- Manually understanding that "Protocol" (not "Transport") is the field to
  watch.
- Manually re-deriving "is governance ready" from raw `GetState()` calls in
  each screen independently (replaced by the single projection, §11).
- For clean guilds only: manually thinking about baseline/evidence at all —
  there is nothing to decide.

**Q10. Which current manual steps MUST remain for integrity/security reasons?**
- The live-roster GM identity check at every mutating step (§17) — never
  automatable or skippable.
- Per-finding reconciliation decisions on any guild with existing legacy
  evidence (§6, §21 P0-1) — must never be defaulted to `INCLUDE`/acknowledged
  automatically.
- The final, explicit "enable canonical ledger" confirmation — this is an
  authority-establishing act (naming a coordinator, freezing a baseline into
  the hash chain) and must remain an explicit GM action, not something that
  happens merely because the addon loaded (as the review brief itself
  requires).
- Explicit GM action for `COORDINATOR_UNAVAILABLE`/`RECOVERY_PENDING`/
  `FORCED_RECOVERY` — these must never be automatic, matching ADR-001's
  availability-vs-integrity trade-off.
