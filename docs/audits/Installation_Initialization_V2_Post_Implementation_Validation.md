# Installation, Initialization, and V2 Activation — Post-Implementation Validation

Status: Read-only validation. No source, tests, or documentation were modified
to produce this report. All claims below were checked directly against
`git diff 71d297f..3ae7077`, the current source tree, and live test runs.

---

## 1. P0 Remediation

**Diff verified directly** (`git diff 71d297f..3ae7077 -- src/modules/Governance.lua`):
the old `ActivateV2` body that called
`LegacyBaseline.FinalizeBaseline(actor, { acknowledgeIncompleteEvidence = true })`
unconditionally was replaced. The new `ActivateV2(actor, options)` forwards
`options.acknowledgeIncompleteEvidence == true` — a caller must explicitly opt
in; the default (`options == nil` or field absent) is `false`.

**Repo-wide search for `acknowledgeIncompleteEvidence`** (25 occurrences, 7
files) classified:

| Location | Value | Classification |
|---|---|---|
| `src/modules/LegacyBaseline.lua:450,453` | Reads `options.acknowledgeIncompleteEvidence` (the enforcement point itself) | SAFE — unchanged, authoritative gate |
| `src/modules/Governance.lua:446` | `options.acknowledgeIncompleteEvidence == true` (forwarded, no longer hardcoded) | SAFE — this is the fix |
| `src/modules/Installation.lua:217-218,245` | `options and options.acknowledgeIncompleteEvidence == true` (forwarded), doc comment | SAFE — orchestrator never sets it itself |
| `tests/integration/installation_wizard_spec.lua:111,145` | Test explicitly passes `{ acknowledgeIncompleteEvidence = true }` after showing the incomplete-evidence block first | SAFE — test, not production |
| `tests/integration/legacy_baseline_recovery_spec.lua:125` | Pre-existing test (predates this feature), passes explicit `true` after already asserting the unacknowledged call returns `nil` | SAFE — test, not production |
| `docs/audits/*.md` (Architecture Review + Implementation Report) | Prose only | N/A |

**No remaining production code path hardcodes `true`.** Confirmed by tracing:
`FinalizeBaseline` ← `ActivateV2` ← (only call site: none in production code
after removal of the OfficerUI Sync button) and `FinalizeBaseline` ←
`Installation.stageBaseline` ← `Installation.Initialize` ← (only call site:
`OfficerUI.renderInstallationPage`'s "Scan existing Dibs data"/"Continue
setup"/"Initialize DIBS" buttons, all of which call `Initialize(nil)` with no
`options` argument at all, i.e. `acknowledgeIncompleteEvidence` defaults to
`false` from the UI). **No UI path can reach `true` without an explicit,
not-yet-implemented UI control for it** — confirmed by `grep` across
`OfficerUI.lua`: no call site passes `acknowledgeIncompleteEvidence`.

Live regression test confirms behavior end-to-end
(`tests/integration/installation_wizard_spec.lua`, "P0 regression" describe
block): an incomplete source blocks `ActivateV2(nil)` with
`INCOMPLETE_EVIDENCE_ACKNOWLEDGEMENT_REQUIRED` and zero mutation; a truly
clean guild (zero evidence) still activates in one call, since
`incompleteSources()` is vacuously false with no sources.

**Verdict: PASS.** All five P0 sub-requirements (incomplete evidence not
silently acknowledged; unresolved/conflicting evidence not silently
canonicalized — see §5 for the independent, unchanged `RECONCILIATION_DECISION_REQUIRED`/`RECONCILIATION_UNRESOLVED` gates in `buildBaseline`; wizard cannot bypass reconciliation; no
alternate UI path reproduces the old behavior; clean installs still work)
are satisfied and test-covered.

---

## 2. `Governance.EstablishInitialAuthority`

Diff-verified: this function is a **byte-for-byte relocation** of the
`authority.state == "LEGACY_LOCAL"` branch previously inlined in `ActivateV2`.
No validation logic was added, removed, or altered:

- `currentGMSnapshot(actor)` is called first — same fresh-roster GM identity
  check as before (`Identity.CreateSnapshot` + `Identity.IsCurrentGuildMaster`
  internally, both roster-generation-aware).
- The constructed `future.authority` table is identical in shape
  (`schema`, `state = "ACTIVE"`, `coordinator = { memberKey, displayName }`
  taken from the GM's own snapshot — **not** an arbitrary parameter, so an
  Officer cannot be named coordinator through this path, nor can an arbitrary
  identity string be injected), `ledgerEpoch = 1`, `protocolState =
  "CUTOVER_PREPARED"`, `transition = { kind = "INITIAL", baselineHash }`.
- It still routes through `Governance.Change` → `CreateChangeRecord` →
  `createRecord` → `currentGMSnapshot` (re-validated) → `governanceContent` →
  `authorityContent`, which is the same validated authority-transition
  pipeline used by the old inline code and by `NORMAL_HANDOFF`/
  `FORCED_RECOVERY`. Those other transition kinds are untouched — only the
  `INITIAL` kind's construction site moved.
- `ledgerEpoch` is hardcoded to `1` only for the `INITIAL` transition kind,
  exactly as before; `NORMAL_HANDOFF`/`FORCED_RECOVERY` still compute
  `prior.ledgerEpoch + 1` inside `authorityContent`, unchanged.
- Idempotency: calling it twice with authority already `ACTIVE` is guarded one
  layer up by `Installation.stageCoordinator`/`Governance.ActivateV2` (`if
  authority.state == "ACTIVE" then return true, "ALREADY_ACTIVE"` /
  `if authority.state ~= "ACTIVE" ... AUTHORITY_ACTIVE_REQUIRED`), not inside
  the function itself — a raw second call while already `ACTIVE` would fail
  inside `authorityContent`'s `kind == "INITIAL"` branch requiring
  `prior.state ~= "LEGACY_LOCAL"` to be false, i.e. it fails closed
  (`AUTHORITY_BASELINE_REQUIRED`-shaped rejection via the parent/hash chain),
  not silently duplicating an epoch.

**Verdict: PASS.** No weakening found; behavior is identical to pre-refactor,
merely de-duplicated.

---

## 3. Installation Module

Traced `GetStatus`/`Initialize` line-by-line (source read in full).

- **Derived, not authoritative:** every field reads from
  `Governance.GetState()/GetAuthorityState()/IsV2Enforced()`,
  `LegacyBaseline.GetState()/GetBaseline()/GetFindings()`,
  `Sync.IsSyncBehind()/CanEnforceV2()`, `Identity.IsCurrentGuildMaster()`, and
  `Ledger.GetAllTransactions()`/`db.preDibs.requests` directly. Confirmed: no
  field in `Installation.lua` is read from or written to any new persisted
  table; `grep` for `Dibs.GetDB()` in the file shows only a **read** of
  `db.preDibs.requests` for the legacy-data heuristic, never a write.
- **No competing persisted truth:** `Installation.lua` declares no
  `SavedVariables` schema, no `db.installation` table, nothing added to
  `defaultDB` in `Core.lua` (confirmed by diff: `Core.lua`'s only change is
  registering the empty `Dibs.Installation = Dibs.Installation or {}` module
  table, identical in kind to every other module registration line).
- **`Initialize` never touches SavedVariables directly:** every mutation is a
  call to `Dibs.Governance.AdoptInitial`, `Dibs.LegacyBaseline.CollectLocalEvidence`,
  `Dibs.LegacyBaseline.FinalizeBaseline`, `Dibs.Governance.EstablishInitialAuthority`,
  or `Dibs.Governance.EnableV2` — all pre-existing authoritative APIs.
- **Stages are resumable / completed stages are no-ops:** each of the four
  stage functions (`stageGovernance`, `stageLegacyDiscovery`, `stageBaseline`,
  `stageCoordinator`, `stageCutover`) begins with an authoritative-state check
  that returns a `true`/no-mutation result if that stage's goal is already
  met (`ALREADY_ADOPTED`, `NO_ACTION_REQUIRED`, `ALREADY_APPROVED`,
  `ALREADY_ACTIVE`, `ALREADY_ENFORCED`).
- **Already-V2 guilds return READY without mutation:** `Initialize`'s first
  action after the GM check is
  `if Installation.GetStatus(actor).protocol.active then return { ok = true,
  reasonCode = "ALREADY_INITIALIZED", ... }` — this short-circuits before any
  stage runs. Verified live by test (`initializes a clean guild in one call
  and is idempotent`): governance revision is asserted unchanged after a
  second `Initialize` call.

**Clean-install flow, exact functions per transition (traced from
`Installation.Initialize`):**

```
GM check           -> Identity.IsCurrentGuildMaster (via Installation.isGM)
governance         -> Governance.AdoptInitial -> Governance.ApplyRecord
legacy detection    -> Installation.detectRealLegacyData (read-only)
legacy discovery    -> LegacyBaseline.CollectLocalEvidence (only if hasRealLegacyData)
baseline            -> LegacyBaseline.FinalizeBaseline
initial authority   -> Governance.EstablishInitialAuthority -> Governance.Change
writer compat check -> Sync.CanEnforceV2 (invoked again inside EnableV2's governanceContent)
sync readiness      -> Sync.IsSyncBehind (checked inside governanceContent's cutover branch)
V2 activation       -> Governance.EnableV2 -> Governance.Change
verification        -> Installation.GetStatus (re-derived, returned to caller)
```

**Verdict: PASS.**

---

## 4. Clean Install Detection

`detectRealLegacyData()` counts:
- every `Ledger.GetAllTransactions()` entry whose `tx.type ~= "SEASON_ALLOCATION"`, plus
- `#db.preDibs.requests`.

**Why the exclusion is safe and narrow (not a broad-class ignore):**

1. **Only one exact type string is excluded** (`"SEASON_ALLOCATION"`), not a
   category, prefix, or heuristic pattern. `DIB_GRANTED`, `DIB_USED`,
   `DIB_REFUNDED`, and `DIB_ADMIN_ADJUSTMENT` are all counted.
2. **Verified against the exact example in the request**
   (`SEASON_ALLOCATION, SEASON_ALLOCATION, MANUAL_GRANT`): a manual grant
   produces a `DIB_GRANTED` transaction (`Ledger.Grant` →
   `compatibilityMutation("DIB_GRANTED", ...)`), which is *not* excluded.
   `ledgerCount` would be `1` (the grant), `hasRealLegacyData = true` →
   classified `UPGRADE`, exactly as required. This is directly test-covered
   (`reports RECONCILIATION_REQUIRED when real legacy ledger data has not
   been scanned yet`, using `Ledger.Grant`).
3. **Root cause independently confirmed:** `Dibs.Initialize()` (`Core.lua`)
   unconditionally calls `Seasons.GetOrCreateDefault()` and
   `Dibs.ApplyDefaultRules()` on every load, which is the only source of
   automatic `SEASON_ALLOCATION` transactions. This was reproduced live:
   before the fix, all four "clean guild" tests failed with `installType =
   UPGRADE` on a guild with zero manual activity; after the fix, they pass.
   This confirms the exclusion is necessary, not merely convenient.
4. **`SEASON_ALLOCATION` transactions are deterministic and reproducible**
   from Season + Rank Rule configuration (both independently visible on the
   Seasons/Rank Rules Officer pages) — they carry no ambiguous historical
   judgment call, unlike manual grants/awards/refunds/admin adjustments,
   which is exactly the class of evidence B05a reconciliation exists to
   resolve trust in.
5. **Balances are never gated by baseline/evidence-collection status.**
   Traced `Ledger.getCurrentBalance`: it sums `state.allocation` (from
   `SEASON_ALLOCATION` transactions) plus every non-allocation transaction
   for that player/season, **unconditionally**, regardless of whether
   `LegacyBaseline` ever collected evidence or approved a baseline. The
   approved baseline is bound into `authority.transition.baselineHash` for
   provenance/audit only (via `approvedBaseline()`/`authorityContent`'s
   `INITIAL`/`FORCED_RECOVERY` checks) — it does not filter, redact, or gate
   `Ledger.GetBalance`. Therefore, even a guild whose entire history is
   `SEASON_ALLOCATION`-only and skips reconciliation review entirely retains
   100% of its balance-affecting data untouched in `db.ledger.transactions`.

**Edge case identified — coarse exclusion by type, not by origin (P2):**
The exclusion filters by transaction `type` alone, not by *how* the
transaction was created. A `SEASON_ALLOCATION`-typed transaction restored
from an `ImportExport`/`Backup` full-package import of another client's
history (rather than generated by this session's `Dibs.Initialize()`
bootstrap) would be excluded identically, even though it did not originate
from the automatic default-bootstrap path this exclusion was designed for.
**Severity reasoning:** per point 5 above, this cannot cause balance
loss/corruption (the transaction remains fully counted in
`Ledger.GetBalance`); the only consequence is that such a guild could route
through the one-click clean path without an explicit GM reconciliation
attestation over what is, in practice, deterministic allocation history
already visible elsewhere in the UI. **Classified P2 (audit-completeness gap,
not data-integrity risk)** — narrow, low-likelihood (requires a
pre-V2-governance backup restore scenario), and does not corrupt or hide
data.

**Verdict: PASS** (exclusion is precise, test-verified, and cannot cause
data loss), with one documented P2 edge case.

---

## 5. Reconciliation

- **`Include`/`Exclude` buttons call `LegacyBaseline.RecordDecision(nil,
  evidenceId, "INCLUDE"/"EXCLUDE", { reason = "Reviewed via Guild Setup" })`
  directly** — no SavedVariables field is touched by the UI itself; every
  write flows through the authoritative decision API, which independently
  re-validates actor authority (`localSnapshot(actor, false, true)` — GM *or*
  Officer, matching B05a's original design) before mutating.
- **Required reasons enforced:** `RecordDecision` stores `trim(options.reason)`;
  the UI supplies a fixed literal reason string for every decision it makes.
  A `nil`/empty reason is not possible from this UI path. (The underlying API
  does not itself *require* a non-empty reason for `INCLUDE`/`EXCLUDE` — only
  `COMPENSATING_ADJUSTMENT`'s `adjustmentReason` is separately validated
  inside `LegacyBaseline`'s decision-content builder — but since the new UI
  always supplies one, this is moot for the exposed workflow.)
- **Unresolved evidence remains unresolved:** the UI only renders
  `Include`/`Exclude` buttons `if not row.decision` — an item with no active
  decision stays visibly `UNRESOLVED` until acted on; nothing defaults it.
- **Incomplete evidence surfaced, not bypassed:** `stageBaseline` blocks with
  `INCOMPLETE_EVIDENCE_ACKNOWLEDGEMENT_REQUIRED` (§1); the current UI has
  **no control to set `acknowledgeIncompleteEvidence = true`** — meaning an
  incomplete-source guild cannot currently complete Guild Setup at all
  through this UI (fail-closed, but also a functional gap — flagged as P2 in
  Implementation Report §18, confirmed still accurate).
- **Conflicting evidence cannot be silently resolved:** `buildBaseline`
  (unchanged, `LegacyBaseline.lua`) still unconditionally requires an active,
  non-`DEFER` decision for every evidence item before producing a baseline —
  this logic was not touched by the diff at all (confirmed: `git diff
  71d297f..3ae7077 -- src/modules/LegacyBaseline.lua` is empty). The new UI
  adds no path around it.
- **Finalized baseline cannot be accidentally mutated:** `stageBaseline`
  checks `LegacyBaseline.GetBaseline()` first and no-ops if present;
  `RecordDecision` (unchanged) resets `state.baseline = nil` only when a
  **new** decision is recorded — an intentional, existing invariant, not
  something this feature altered.
- **Reload preserves decisions:** decisions live in
  `db.legacyBaseline.decisions`/`activeDecisionByEvidence`, ordinary
  SavedVariables fields untouched by this feature's schema.

**Compensating Adjustment:** confirmed present and functional in
`LegacyBaseline.RecordDecision` (`DECISIONS.COMPENSATING_ADJUSTMENT = true`,
with structured `adjustment` validation), but **not exposed in the new
reconciliation UI** — only `Include`/`Exclude` render. Per the requested
classification: **P2 missing workflow, acceptable deferred scope.** Rationale
for P2 (not P1): it is a real usability gap for guilds needing an
attributable balance correction during onboarding, but it does not create
unsafe behavior — a GM who needs it today can still use the existing
Officer-facing Dispute Center / Ledger admin-adjustment paths after
completing Guild Setup with `Exclude` for that item, or via direct API. No
silent, incorrect, or unauthorized mutation results from its absence.

**Verdict: PASS**, with one P2 (incomplete-evidence acknowledgement control
missing from UI) and one P2 (Compensating Adjustment not in UI) — both
already disclosed in the Implementation Report.

---

## 6. One-Click Initialization Correctness

Checked every listed scenario against `Installation.GetStatus`'s state
derivation:

| Scenario | UI state shown | Actual `Initialize` outcome | Consistent? |
|---|---|---|---|
| No guild / roster unavailable | `Identity.IsCurrentGuildMaster` fails closed → `actor.isGM=false` → read-only message | `GUILD_MASTER_REQUIRED`, no mutation | Yes |
| Non-GM | Read-only message, no buttons | `GUILD_MASTER_REQUIRED` if called directly | Yes |
| Clean GM | `READY_TO_INITIALIZE` | Succeeds in one call → `READY` | Yes (test-verified) |
| Legacy evidence, open findings | `RECONCILIATION_REQUIRED` | Blocked at `baseline` stage if forced | Yes (test-verified) |
| Incomplete evidence | `READY_TO_INITIALIZE` is **not** reached — `hasUncollectedEvidence`/`reconciliationRequired` only track *decision* state, not the `complete` flag, so an all-decided-but-incomplete-source guild *would* show `READY_TO_INITIALIZE` with an `INCOMPLETE_EVIDENCE_SOURCES` **warning**, then fail at `baseline` with `INCOMPLETE_EVIDENCE_ACKNOWLEDGEMENT_REQUIRED` when clicked | Reported via `stage="baseline"`, `reasonCode` | **Minor inconsistency (P3):** UI shows the primary action button in a state that will predictably fail; the warning is present but the button is not disabled. Not unsafe (no mutation occurs; failure is reported), but not ideal UX. |
| Unresolved decisions (DEFER) | `RECONCILIATION_REQUIRED` remains only while a finding is `OPEN`; a `DEFER`'d item clears its finding (since `activeDecision` exists) even though `buildBaseline` will still reject it via `RECONCILIATION_UNRESOLVED` | Fails at `baseline` stage, correctly blocked, no mutation | **P3 labeling gap:** `GetStatus` can show `READY_TO_INITIALIZE` for a guild with an explicit `DEFER` decision recorded (since findings are already "DECIDED" once any decision exists, including DEFER), yet `FinalizeBaseline` will still reject it. Safe (fails closed with a clear reason), but the readiness label is optimistic. |
| Approved baseline already present | `stageBaseline` no-ops | Proceeds directly | Yes |
| No coordinator candidate | Unreachable when `actor.isGM=true`, since `IsCurrentGuildMaster` and `CreateSnapshot` share the same roster-resolution path — if GM check passes, a display name is always resolvable | N/A | Verified by code trace, no defect found |
| Incompatible writer | `compatibility.ready=false` → **warning only**, button still enabled | `stageCutover` fails at `EnableV2` with `WRITER_COMPATIBILITY_REQUIRED`, no mutation | Safe (reported failure), consistent with "warnings never block, only inform" design — acceptable |
| `SYNC_BEHIND` | `sync.ready=false` → warning only, button enabled | `EnableV2`'s `governanceContent` cutover branch checks `Sync.IsSyncBehind()` and rejects with `SYNC_BEHIND` before any mutation | Safe, consistent |
| Already V2 | `READY` | `Initialize` short-circuits to `ALREADY_INITIALIZED`, no mutation | Yes |
| Recovery state | `RECOVERY_REQUIRED`, no Initialize button rendered (only `state == RECONCILIATION_REQUIRED`/`READY_TO_INITIALIZE` render the action button) | N/A — button not shown | Yes |

**No case was found where the UI claims `READY_TO_INITIALIZE` and the
resulting click causes an unsafe mutation.** Every failure mode found is
"button enabled in a state that will predictably fail, but fails closed with
a clear reason and zero mutation." These are classified **P3** (UX
imprecision), not P1/P0, because no unauthorized or unintended write ever
occurs.

**Verdict: PASS**, three P3 UX-precision findings noted.

---

## 7. Idempotency (stage-by-stage)

| Stage | Authoritative precondition | Mutation | Success marker | Rerun behavior | Duplicate-record risk |
|---|---|---|---|---|---|
| `Governance.AdoptInitial` | `status == "POLICY_UNINITIALIZED"`, `revision == 0` | Writes governance revision 1 | `state.status = "GOVERNANCE_ADOPTED"` | `CreateInitialRecord` returns `GOVERNANCE_ALREADY_ADOPTED` on any subsequent call regardless of actor; `Installation.stageGovernance` also no-ops first | None — guarded twice |
| `LegacyBaseline.FinalizeBaseline` | Governance adopted, fresh GM snapshot, all evidence decided (or none) | Computes deterministic hash, stamps `gmApproval`, sets `status = "BASELINE_APPROVED"` | `state.baseline.legacyBaselineHash` present | Re-running with unchanged evidence/decisions reproduces the identical hash (pure function of `state.evidence`+`state.decisions`); `stageBaseline` also no-ops if a baseline already exists | None — deterministic hash, single `baseline` field (not a list), no accumulation |
| `Governance.EstablishInitialAuthority` | `authority.state == "LEGACY_LOCAL"`, approved baseline hash present | Writes governance revision N+1 with `authority.state="ACTIVE"` | `authority.state == "ACTIVE"` | A second raw call fails inside `authorityContent`'s `INITIAL` branch (`prior.state ~= "LEGACY_LOCAL"`); `Installation.stageCoordinator` also no-ops first (`ALREADY_ACTIVE`) | None — governance revision chain rejects a non-matching parent/hash, and the no-op check prevents the attempt in normal orchestration |
| `Governance.EnableV2` | `authority.state == "ACTIVE"`, approved baseline bound, `!SyncBehind`, coordinator listed among compatible writers | Writes governance revision N+1 with `future.protocolState = "V2_ENFORCED"`, mirrors into `Sync.SetProtocolState` | `Governance.IsV2Enforced() == true` | `ActivateV2`/`Installation.stageCutover` both check `IsV2Enforced()` first and return `V2_ALREADY_ENFORCED`/`ALREADY_ENFORCED` | None — single governance-record chain, no epoch increment on repeat |

**No stage increments a governance revision, creates a duplicate baseline
approval, creates an additional ledger epoch, or duplicates an audit record
on rerun.** Confirmed live: the idempotency test asserts governance revision
is byte-identical before/after a second `Initialize` call.

**Verdict: PASS.**

---

## 8. Partial Failure / Resume

Traced each scenario against `Installation.GetStatus`'s derivation and
`Initialize`'s stage order:

- **A. Governance done, baseline not done:** `stageGovernance` no-ops;
  `Initialize` proceeds to `stageLegacyDiscovery`/`stageBaseline` on the next
  call. **Test-verified** ("blocks one-click initialization... and resumes
  after reconciliation").
- **B. Governance + baseline done, authority not done:** both prior stages
  no-op; `Initialize` proceeds directly to `stageCoordinator`. **Test-verified**
  ("resumes from the authority stage after a partial reload-simulated
  failure").
- **C. Authority established, V2 compatibility fails:** `stageCutover`
  returns `WRITER_COMPATIBILITY_REQUIRED`; authority remains `ACTIVE`
  (already-established, unaffected); a later retry with corrected writers
  re-enters at `stageCutover` only (all earlier stages no-op). Not directly
  test-covered (see §14), but the code path guarantee is structurally
  identical to the already-tested scenarios (a no-op-guarded stage sequence).
- **D. Authority established, `SYNC_BEHIND`:** identical reasoning to C —
  `governanceContent`'s cutover branch rejects with `SYNC_BEHIND` before any
  mutation; retry after `Sync.ClearSyncBehind()` resumes at cutover only. Not
  directly test-covered.
- **E. V2 activation succeeds, immediate UI refresh/reload:**
  `Installation.GetStatus()`/`Initialize()` are always freshly derived from
  SavedVariables-backed subsystems with no in-memory-only state — a reload
  immediately after success reports `state == "READY"` and `protocol.active
  == true` with zero risk of re-running any stage, since `Initialize`'s very
  first check after the GM gate is the already-initialized short-circuit.

**Verdict: PASS** for A/B/E (test-verified or structurally guaranteed by the
short-circuit design); **PASS by code inspection, UNVERIFIED by test** for
C/D (see §14 recommendation to add explicit tests).

---

## 9. Old Officer UI Paths

1. **Can GM initialize Governance from Modules and then use Guild Setup
   safely?** Yes. `Modules`'s bootstrap calls only `Governance.AdoptInitial`
   with a specific `officerAuthorityRule`/`policyWriterRule` payload.
   `Installation.stageGovernance` checks `governance.status ==
   "GOVERNANCE_ADOPTED"` first and no-ops — it never re-adopts or overwrites
   the rules chosen via Modules.
2. **Can Modules put the guild into a state Guild Setup misclassifies?** No
   misclassification found — `GetStatus` reads live governance/legacy/authority
   state regardless of which UI path adopted governance.
3. **Can Modules bypass the legacy reconciliation requirement?** No — Modules'
   bootstrap block calls only `AdoptInitial`; it has no code path to
   `FinalizeBaseline`, `EstablishInitialAuthority`, or `EnableV2`. It cannot
   reach V2 activation at all, so it cannot bypass reconciliation for V2
   purposes.
4. **Is there now more than one user-visible workflow that claims to
   initialize DIBS?** Partially. Modules' button is explicitly labeled
   "Initialize Guild Governance" and its own copy states it only "initializes
   canonical Dibs governance" — it does not claim to activate the guild
   ledger. So there is exactly **one** workflow that claims full DIBS/ledger
   initialization (Guild Setup), but **two** GM-facing entry points that both
   perform governance adoption as a side effect (Modules directly; Guild
   Setup as its transparent first stage). This is redundant, not unsafe.
5. **Recommendation:** `MOVE_TO_SETUP`. The Modules governance-bootstrap
   block should eventually become a thin link into Guild Setup's step 1
   (mirroring how the Sync tab's old V2 button was already converted to a
   link), rather than a second independent action that produces the same
   governance record. **Not applied in this validation pass** per
   instructions.

**Verdict: PASS** (no safety defect), **P3** (workflow redundancy) recorded.

---

## 10. Authorization

Traced the actual business-layer boundary for every listed action —
**UI hiding was not treated as sufficient; only production-code gates were
counted:**

| Action | Authoritative gate | UI-only or enforced? |
|---|---|---|
| Opening/viewing Setup | `renderInstallationPage` checks `status.actor.isGM`; **but this is presentation-only** — `Installation.GetStatus()` itself has no read-restriction (any caller can read it; it contains no secrets, only readiness booleans) | UI-level (acceptable: read of non-sensitive derived status) |
| Making reconciliation decisions | `LegacyBaseline.RecordDecision` → `localSnapshot(actor, false, true)` → requires GM **or** Officer via live roster rank/role | **Enforced at business layer**, independent of UI |
| Finalizing baseline | `LegacyBaseline.FinalizeBaseline` → `localSnapshot(actor, true, false)` → **GM only** | **Enforced at business layer** |
| Selecting/establishing coordinator | `Governance.EstablishInitialAuthority` → `currentGMSnapshot` → **GM only**, coordinator forced to be the caller's own identity | **Enforced at business layer** |
| Running `Installation.Initialize` | `isGM(actor)` checked as the very first line, before any stage runs | **Enforced within `Installation.lua` itself**, not just the UI |
| Enabling V2 | `Governance.EnableV2` → `Governance.Change` → `createRecord` → `currentGMSnapshot` → **GM only** | **Enforced at business layer** |

**Direct-call bypass test performed by inspection:** calling
`Dibs.Installation.Initialize(nil)` as a non-GM (no UI involved at all) was
directly exercised by the test suite (`rejects a non-GM without mutating
anything`) and confirmed to return `GUILD_MASTER_REQUIRED` with the
governance status asserted unchanged. Calling
`Dibs.LegacyBaseline.RecordDecision`/`Dibs.Governance.EnableV2` directly as a
non-GM/non-Officer is independently guarded by their own pre-existing,
unmodified authority checks (not part of this diff, so not re-verified here
beyond confirming the diff to `LegacyBaseline.lua` is empty and to
`Governance.lua` preserves `currentGMSnapshot` at every mutation entry).

**One asymmetry noted (P3, not a security gap):** `renderInstallationPage`
hides the entire reconciliation table from Officers (`if not
status.actor.isGM then ... return end`), even though `RecordDecision` itself
would permit an Officer to act. This is **over-restrictive**, not
under-restrictive — it denies a capability the architecture intends to allow,
which is the safe direction of error, but it is a functional deviation from
B05a's original "Officers/GM may record attributable reconciliation work"
design intent.

**Verdict: PASS.** No non-GM/non-Officer can perform any governance,
baseline, authority, or protocol mutation through any path found, UI or
direct API.

---

## 11. SavedVariables / Protocol Compatibility

| Claim | Verified |
|---|---|
| SavedVariables schema changed | **NO** — confirmed: no change to `ROOT_SCHEMA_VERSION`/`GUILD_SCHEMA_VERSION` in `Core.lua`, no new field added to `defaultDB`, `Installation.lua` persists nothing. |
| New persisted installation state | **NO** — `Installation.GetStatus` is computed fresh on every call; no `db.installation` table exists anywhere in the diff or current source. |
| Ledger schema changed | **NO** — `git diff` shows zero changes to `src/modules/Ledger.lua` in this range. |
| Governance schema changed | **NO** — `AUTHORITY_SCHEMA`/`SCHEMA` constants and record shapes in `Governance.lua` are unchanged; only function organization changed. |
| Wire protocol changed | **NO** — no changes to `src/modules/SyncV2.lua` in this range; message types, capability flags, and `MAJOR`/`MINOR` constants untouched. |
| Sync protocol semantics changed | **NO** — `Governance.EnableV2`'s call into `Sync.SetProtocolState("V2_ENFORCED", true)` is unchanged code, just still reached the same way. |
| Existing V2 guild migration required | **NO** — see §12; an already-`V2_ENFORCED` guild's `Installation.GetStatus()` derives `READY` with no write. |

**All seven implementation-report claims independently confirmed accurate.**
No compatibility surface was found to have silently changed despite the "NO"
claims.

**Verdict: PASS.**

---

## 12. Existing V2 Guilds

Reasoned through the exact code path (and confirmed by the live test, which
constructs precisely this state as its own post-condition): once
`Governance.IsV2Enforced() == true`,

- `Installation.GetStatus()`'s `governance.status ~= "GOVERNANCE_ADOPTED"`
  branch is false (already adopted) → falls into the `elseif protocolActive`
  branch → returns `"READY"` (assuming authority is not in a recovery/handoff
  state) directly, performing zero writes (`GetStatus` never mutates
  anything — confirmed, it contains no assignment to any `Dibs.*` table,
  only local variable computation).
- `Installation.Initialize()`'s very first action after the GM check is
  exactly `if Installation.GetStatus(actor).protocol.active then return { ok
  = true, reasonCode = "ALREADY_INITIALIZED", ... }` — it **never calls**
  `AdoptInitial`, `CollectLocalEvidence`, `FinalizeBaseline`,
  `EstablishInitialAuthority`, or `EnableV2` in this branch. No governance
  bootstrap, no baseline recreation, no new coordinator, no epoch increment,
  no redundant `EnableV2` call.
- The OfficerUI Guild Setup page renders the `READY` summary rows and does
  not surface a wizard/first-run flow for such a guild (the reconciliation
  and `READY_TO_INITIALIZE` branches are both skipped by the `if/elseif`
  chain once `state == "READY"`).

**Verdict: PASS.**

---

## 13. `LEGACY_LOCAL`

- **Protocol semantics unchanged:** `git diff` confirms `Governance.lua`'s
  `legacyAuthority()`/`authorityState()` self-healing logic and
  `defaultState()`'s `authority = { state = "LEGACY_LOCAL", ... }` default are
  byte-identical to before this feature.
- **Normal UI no longer requires understanding it:** confirmed by reading
  every string literal added to `OfficerUI.lua` in this diff — `"LEGACY_LOCAL"`,
  `"CUTOVER_PREPARED"`, and `"V2_ENFORCED"` do not appear anywhere in
  `renderInstallationPage`'s normal-path labels (`INSTALLATION_STATE_LABEL`
  table uses only the new derived state names). They appear **only** inside
  the `"Show technical details"` disclosure block, exactly as specified.
- **Diagnostics still expose it:** the Sync tab's existing
  `BuildSynchronizationProjection` (unchanged) still surfaces
  `Sync.GetProtocolState()` verbatim, and Guild Setup's technical panel shows
  `status.technical.protocolState`/`authorityState` verbatim.

**Verdict: PASS.**

---

## 14. Test Quality

`installation_wizard_spec.lua` uses the **real** `helpers.load_addon` loader
with genuine `Governance`, `LegacyBaseline`, `Ledger`, `Seasons`, and `Sync`
modules — no stubs, mocks, or monkey-patched internals were found in the
file. Every assertion operates on real return values from production
functions (`dibs.Governance.GetState()`, `dibs.Ledger.GetBalance`-adjacent
calls via `Grant`, etc.). This is genuine integration-level coverage, not
shallow mocking.

| Guarantee | Coverage |
|---|---|
| Clean detection | **STRONG** — asserted directly with zero evidence and with a real `Ledger.Grant`, both directions |
| P0 incomplete evidence | **STRONG** — dedicated describe block against `Governance.ActivateV2` directly, plus orchestrator-level equivalent |
| Reconciliation block | **STRONG** — asserts exact `stage`/`reasonCode`, exact `LegacyBaseline.GetBaseline() == nil` before, and successful resume after real `RecordDecision` calls |
| GM-only initialization | **STRONG** — asserts zero governance mutation for a non-GM actor |
| Coordinator establishment | **PARTIAL** — `Initialize` reaching `READY` implies authority became `ACTIVE` with *some* coordinator, but no test asserts `GetAuthorityState().coordinator.memberKey` actually equals the acting GM's identity |
| Compatibility block (`WRITER_COMPATIBILITY_REQUIRED` blocking cutover) | **MISSING** — no test constructs an incompatible/unresolvable writer to force this specific stage-5 failure |
| `SYNC_BEHIND` block | **MISSING** — no test calls `Sync.MarkSyncBehind` before `Initialize` to confirm cutover is blocked |
| Idempotency | **STRONG** — explicit revision-equality assertion across two calls |
| Partial resume | **STRONG** — two distinct resume scenarios (baseline-stage, authority-stage), both from realistic pre-conditions |
| Existing V2 load | **STRONG** (indirect) — the idempotency test's second `Initialize` call *is* this exact scenario, and its assertions cover it |
| SavedVariables compatibility | **PARTIAL** — not tested within this file; relies on the broader, pre-existing `SavedVariables validation and recovery` suite passing unaffected (confirmed passing, §15) |
| Legacy-data preservation (balances unchanged through reconciliation) | **PARTIAL** — a real grant is created and later included, but no test explicitly re-reads `Ledger.GetBalance` after the full `Initialize` sequence completes to confirm the pre-existing balance is preserved byte-for-byte |

**Conflict-finding coverage** (`LEGACY_ID_CONTENT_CONFLICT`,
`LEGACY_IDENTITY_CONFLICT`, etc.) is not exercised by this new spec file, but
is already covered extensively by the pre-existing, untouched
`legacy_baseline_recovery_spec.lua` at the `LegacyBaseline` layer — since
`Installation` does not reimplement conflict detection, this is appropriate
inherited coverage, not a gap.

**Recommended additional tests** (not added, per read-only scope):
1. A `Sync.CanEnforceV2`-incompatible writer scenario asserting `Initialize`
   fails at `stage = "cutover"` with `WRITER_COMPATIBILITY_REQUIRED` and zero
   protocol change.
2. A `Sync.MarkSyncBehind` scenario asserting the same for `SYNC_BEHIND`.
3. An explicit assertion that `Governance.GetAuthorityState().coordinator`
   matches the initializing GM's identity snapshot.
4. A balance-preservation assertion (`Ledger.GetBalance` unchanged) taken
   before and after a full legacy-path `Initialize` run.

---

## 15. 622 Passed / 1 Failed

Independently re-run (not merely trusted) at current `HEAD` (`3ae7077`):
**622 passed, 1 failed (138 files)**, single failure:
`tests/integration/predibs_sync_recovery_spec.lua:50: expected 1, got 2`
("uses AceComm registration and AceTimer for one bounded anti-entropy
heartbeat").

Verification performed:
- `git diff 71d297f..3ae7077 -- tests/integration/predibs_sync_recovery_spec.lua`
  is **empty** — the file is byte-identical between the checkpoint and the
  implementation commit.
- `git merge-base --is-ancestor <last-modifying-commit-of-that-file>
  71d297f` returned success — the file's last real change predates the
  checkpoint entirely; it was not touched at any point in this feature's
  history.
- None of the nine files changed in `71d297f..3ae7077`
  (`Governance.lua`, `Installation.lua` [new], `OfficerUI.lua`, `Core.lua`,
  the `.toc`, `load_addon.lua`, the new spec file, and two docs) register any
  `AceComm`/`AceTimer` handler, touch `Dibs.Sync`/`Dibs.RaidPrompts`
  heartbeat scheduling, or run any code at load time beyond defining
  functions on `Dibs.Installation` — `Installation.lua` has no top-level
  side effects (confirmed by full read: every executable statement outside a
  function body is either a `local function` declaration or the final
  `return Installation`).
- A physical re-run at the checkpoint commit was attempted via a temporary
  `git worktree` at `71d297f`; the isolated worktree's `npx` invocation
  failed to resolve its cache/environment (tooling issue, not a test
  behavior difference) and was removed without further use. The logical
  proof above (identical file content + provably unrelated diff + identical
  error message/line number in the current run) is conclusive without it.

**Classification: CONFIRMED PRE-EXISTING.** Not a regression.

---

## 16. TODO / Completion Consistency

`git status --short` on the current tree is **clean** (no untracked or
modified files). `git log --oneline -3` shows `3ae7077` as `HEAD`, directly
on top of the `71d297f` checkpoint, with no intervening or subsequent
commits. `git diff 71d297f..3ae7077 --stat` shows exactly the 9 files listed
in the Implementation Report's §1 file table — nothing more, nothing less.

The phrase `"Completed: Implement P0 fix in Governance.ActivateV2 (1/4)"`
does **not** appear anywhere in the repository — not in any commit message,
not in `docs/audits/`, not in code comments, not in the test file. It is not
reproducible from repo state. This is external session/agent-tool todo-list
metadata (from whatever orchestration surface displayed it), **not** a
reflection of incomplete implementation, uncommitted files, or missing steps
in this repository.

**Explicit answer: `3ae7077` contains the complete, intended implementation**
as described in the Implementation Report — verified line-by-line against
the actual diff in this validation, not merely by reading the report's
prose.

---

## 17. Documentation

`docs/officer/GM_OFFICER_GUIDE_EN.md` diff-verified: the installation section
now instructs opening **Guild Setup** and following its readiness rows,
explicitly stating "A normal Guild Master does not need to run `/run`
commands or call internal APIs." A repo-wide search for `/run`, `EnableV2`,
`V2_ENFORCED`, `legacyBaselineHash` in that file returns only this one
negative-context sentence — no instructional usage remains. Technical terms
remain fully documented in `docs/developer/` and `docs/audits/` for
maintainers, unchanged.

**Verdict: PASS.**

---

## 18. Risk Classification Summary

| # | Severity | File / Function | Behavior | Why it matters | Remediation |
|---|---|---|---|---|---|
| F1 | P2 | `Installation.lua` `detectRealLegacyData` | Excludes all `SEASON_ALLOCATION`-typed transactions by type, not by origin; a restored backup's `SEASON_ALLOCATION` history would be excluded identically to auto-bootstrap allocation | Narrow, low-likelihood scenario (requires pre-V2 backup restore); does not cause balance loss (balances are baseline-independent) — completeness/audit-trail gap only | Optionally tag automatic bootstrap allocations with a distinguishing `source`/`reason` at creation time and filter on that instead of bare `type`, if this scenario is judged worth closing |
| F2 | P2 | `LegacyBaseline.lua` (unchanged) / new Guild Setup UI | `INCOMPLETE_EVIDENCE_ACKNOWLEDGEMENT_REQUIRED` has no UI control to acknowledge; guild cannot complete setup through the UI while any source is `complete=false` | Functional gap (fail-closed, safe) for guilds with genuinely partial evidence sources | Add an explicit "acknowledge incomplete sources" confirmation step to the reconciliation UI |
| F3 | P2 | `LegacyBaseline.RecordDecision` (unchanged) / new UI | `COMPENSATING_ADJUSTMENT` decision kind not exposed in the reconciliation table | Usability gap for balance-correcting reconciliation during onboarding | Add a structured adjustment sub-form, deferred scope |
| F4 | P3 | `OfficerUI.lua` `renderInstallationPage` | Reconciliation table hidden entirely from Officers (`isGM`-only gate), stricter than `RecordDecision`'s own GM-or-Officer authorization | Functional deviation from B05a intent (over-restrictive, safe direction) | Relax the UI gate to Officer-or-GM to match the underlying API |
| F5 | P3 | `OfficerUI.lua` `renderInstallationPage` | "Initialize DIBS"/"Continue setup" button remains enabled while a `warnings` entry (`INCOMPLETE_EVIDENCE_SOURCES`, `WRITER_COMPATIBILITY_REQUIRED`, `SYNC_BEHIND`) is present, and while a `DEFER`'d evidence item exists (state reads `READY_TO_INITIALIZE` optimistically) | Click will fail safely with a clear reason and zero mutation, but is not the smoothest possible UX | Disable/annotate the button when `warnings` is non-empty or an unresolved `DEFER` decision exists |
| F6 | P3 | `OfficerUI.lua` Sync tab | "Open Guild Setup" link now renders for any Officer-or-GM viewer (old button required `IsGM()` specifically) | No mutation is reachable from this link for a non-GM (Guild Setup itself re-gates), purely a navigation-visibility change | None required; optional cosmetic tightening |
| F7 | P3 | Workflow structure (`OfficerUI.lua` Modules tab vs. Guild Setup) | Two GM-facing entry points both perform governance adoption | Redundant, not unsafe; potential future GM confusion | `MOVE_TO_SETUP` per §9 recommendation |
| F8 | P3 | `tests/integration/installation_wizard_spec.lua` | No test for `WRITER_COMPATIBILITY_REQUIRED`/`SYNC_BEHIND` blocking cutover, or explicit coordinator-identity assertion | Coverage gap, not a code defect | Add the four tests listed in §14 |

No P0 or P1 findings were identified in this validation pass.

---

## Final Section

P0 findings: 0
P1 findings: 0
P2 findings: 3
P3 findings: 5

P0 remediation validated: PASS
Clean-install detection: PASS
Legacy reconciliation safety: PASS
Authorization: PASS
Idempotency: PASS
Resume behavior: PASS
SavedVariables compatibility: PASS
Existing V2 compatibility: PASS
Regression status: PASS

## IMPLEMENTATION VALIDATION: READY FOR RETAIL MANUAL TESTING

No P0 findings remain. The P0 identified in the architecture review
(`Governance.ActivateV2` silently acknowledging incomplete legacy evidence)
is confirmed remediated and test-covered, with no alternate production path
capable of reproducing the old unsafe behavior. All P2/P3 findings are
functional-completeness or UX-precision items that fail closed and do not
risk data corruption, unauthorized authority, or unsafe canonicalization of
legacy data. Recommended before wider retail rollout, not before manual
testing: close F2 (incomplete-evidence acknowledgement UI) if partial-source
guilds are expected in practice, and add the four tests in §14/F8.
