# Installation, Initialization, and V2 Activation — Implementation Report

Status: Implemented on top of
`docs/audits/Installation_Initialization_V2_Architecture_Review.md`. This
report documents what changed, what was verified, and what remains.

A Git checkpoint (`71d297f`) was created before any of this work started,
capturing prior uncommitted session work (the Dibs Administration page and the
architecture review itself) separately from this feature's changes.

---

## 1. Files Changed

| File | Change |
|---|---|
| `src/modules/Governance.lua` | **P0 fix**: removed the hardcoded `acknowledgeIncompleteEvidence = true` in `ActivateV2`; extracted `Governance.EstablishInitialAuthority(actor, baselineHash)` from its inline authority-bootstrap logic so it can be reused without duplicating validation. `ActivateV2`'s second parameter changed from a raw `writers` array to an `options` table (`{ writers, acknowledgeIncompleteEvidence }`); its only call site was updated. |
| `src/modules/Installation.lua` | **New.** Read-only `Installation.GetStatus(actor)` projection, `Installation.GetReconciliationView()`, and the staged, idempotent `Installation.Initialize(actor, options)` orchestrator. Owns no persisted state. |
| `src/ui/OfficerUI.lua` | New "Guild Setup" nav entry (`installation`) and `renderInstallationPage`. Sync tab's "Approve baseline and enable V2" button removed and replaced with a read-only status line plus an "Open Guild Setup" link. |
| `src/RCLootCouncil_dibs.toc`, `tests/helpers/load_addon.lua` | Registered `modules/Installation.lua` in load order (after `LegacyBaseline.lua`, before `RaidRelay.lua`). |
| `src/Core.lua` | Added `Dibs.Installation = Dibs.Installation or {}` to the module namespace table. |
| `tests/integration/installation_wizard_spec.lua` | **New.** 10 tests: readiness projection, orchestrator idempotency/resume, and P0 regression coverage. |
| `docs/officer/GM_OFFICER_GUIDE_EN.md` | Documents Guild Setup as the normal installation path; no `/run` or internal API instructions. |

No changes were made to `RCLootCouncil` source, loot voting semantics, season
semantics, Pre-Dib semantics, or existing ledger/balance data.

---

## 2. P0 Remediation

**Before:** `Governance.ActivateV2` always called
`LegacyBaseline.FinalizeBaseline(actor, { acknowledgeIncompleteEvidence = true })`,
regardless of whether any evidence source was actually marked incomplete.

**After:** `ActivateV2(actor, options)` forwards
`options.acknowledgeIncompleteEvidence == true` only when the caller
explicitly sets it. Default is `false`. This is verified by two dedicated
regression tests (`tests/integration/installation_wizard_spec.lua`):
calling `ActivateV2(nil)` on a guild with an incomplete evidence source now
fails with `INCOMPLETE_EVIDENCE_ACKNOWLEDGEMENT_REQUIRED` and makes no
mutation; a truly clean guild (no evidence at all) still activates in one
call, because `incompleteSources()` is trivially false when there are no
sources.

**Clarification found during implementation:** `acknowledgeIncompleteEvidence`
only ever bypassed the "some evidence source is marked `complete = false`"
check inside `LegacyBaseline.FinalizeBaseline`. It never bypassed
per-evidence-item decision requirements — `buildBaseline` already
unconditionally requires an explicit `INCLUDE`/`EXCLUDE`/
`COMPENSATING_ADJUSTMENT` decision for every evidence item, and rejects any
`DEFER`, regardless of this flag. The audit's broader framing of this risk is
still correct in spirit (a GM should never have a partial baseline silently
approved), and the fix closes the actual gap: partial/incomplete *sources*
can no longer be silently approved.

The new `Installation.Initialize` orchestrator never sets
`acknowledgeIncompleteEvidence = true` itself; only an explicit
`options.acknowledgeIncompleteEvidence = true` passed by the caller (i.e., the
GM, after Guild Setup has shown incomplete sources) can enable it.

---

## 3. Installation State Model

No new persisted state. `Installation.GetStatus()` derives a `state` label
purely from existing subsystems on every call:

`NOT_INITIALIZED` → `RECONCILIATION_REQUIRED` → `READY_TO_INITIALIZE` →
`READY`, with `COORDINATOR_UNAVAILABLE` / `RECOVERY_REQUIRED` / `BLOCKED`
overlaid once the guild ledger is active. This matches the audit's §13
simplified state machine. `LEGACY_LOCAL`, `CUTOVER_PREPARED`, and
`V2_ENFORCED` are never returned as the primary `state`; they remain in
`status.technical` only.

---

## 4. Readiness Projection

`Dibs.Installation.GetStatus(actor)` derives from `Governance.GetState()`,
`Governance.GetAuthorityState()`, `Governance.IsV2Enforced()`,
`LegacyBaseline.GetState()`/`GetBaseline()`/`GetFindings()`,
`Sync.IsSyncBehind()`/`CanEnforceV2()`, `Identity.IsCurrentGuildMaster()`, and
direct ledger/Pre-Dibs data (see §5). It persists nothing and cannot drift
from the authoritative subsystems, since every call recomputes from scratch.

Returned shape (fields used by the current UI in bold):

```
{
  **state**, installType, actor = { isGM, displayName },
  **governance** = { ready },
  **legacy** = { evidenceCount, openFindings, incompleteSources, hasUncollectedEvidence, reconciliationRequired },
  **baseline** = { ready, type },        -- type: "GENESIS" | "RECONCILED"
  **coordinator** = { ready, candidate },
  **compatibility** = { ready, reasonCode },
  **sync** = { ready, behind },
  **protocol** = { active },
  blockers, warnings,
  **technical** = { protocolState, authorityState, ledgerEpoch, baselineHash, coordinatorMemberKey },
}
```

---

## 5. Clean-Install Path

**Critical finding during implementation:** `Dibs.Initialize()` (`Core.lua`)
already creates a default season and automatic rank allocations
(`SEASON_ALLOCATION` transactions) for every guild the moment the addon
loads. An initial "any ledger transaction exists" heuristic for
clean-vs-upgrade detection therefore misclassified **every** guild as an
upgrade, including a genuinely fresh one — caught by the first test run
(4 failures) and fixed before proceeding.

`detectRealLegacyData()` now excludes `SEASON_ALLOCATION` transactions
specifically, since they are deterministic and automatically reproduced by
the rank-rule engine, not evidence of prior manual Dibs usage. Real evidence
is: any non-allocation ledger transaction (`DIB_GRANTED`, `DIB_USED`,
`DIB_REFUNDED`, `DIB_ADMIN_ADJUSTMENT`) or any Pre-Dibs request.

For a guild with zero real legacy data: `Installation.Initialize` adopts
governance (if needed), skips legacy discovery (`NO_ACTION_REQUIRED`),
finalizes a deterministic empty/`GENESIS` baseline, establishes the acting GM
as coordinator, and enables V2 with `writers = { coordinator }` — one call,
one GM confirmation in the UI.

---

## 6. Legacy/Upgrade Path

When real legacy data exists but has not yet been imported as evidence,
`Installation.GetStatus` reports `RECONCILIATION_REQUIRED` with blocker
`LEGACY_EVIDENCE_SCAN_REQUIRED`. The GM-facing UI shows a "Scan existing Dibs
data" action, which calls `Installation.Initialize` — its `stageLegacyDiscovery`
step calls the existing `LegacyBaseline.CollectLocalEvidence` (no new
collection logic). Once evidence exists, any item lacking a decision
surfaces in the reconciliation table; `stageBaseline` refuses to finalize
while any finding is `OPEN`. Findings and decisions are 100% delegated to
`LegacyBaseline` (`GetFindings`, `RecordDecision`) — no second reconciliation
engine was created.

**Known limitation:** `CollectLocalEvidence` always creates both a `:ledger`
and a `:predibs` evidence source, even when Pre-Dibs requests are empty. Its
existing `PEER_EVIDENCE_DIVERGENCE` finding heuristic can flag single-client
evidence as "divergent" purely because two source records exist with
different evidence counts. This does not block correctness — resolving the
evidence item's decision still clears the finding — but the finding's label
can read as more alarming than warranted for a single-client scan. Fixing
this heuristic lives inside `LegacyBaseline.lua` (B05a) and was left
unchanged, per the instruction to reuse existing reconciliation machinery
without modifying its semantics; flagged here as a documentation/UX follow-up.

---

## 7. Reconciliation UI

Added to the new "Guild Setup" Officer page (`renderInstallationPage` in
`OfficerUI.lua`), GM-only. Shows, per unresolved evidence item: source
identity, action type, amount, and current decision state, with **Include**
and **Exclude** actions calling `LegacyBaseline.RecordDecision` directly with
an attributable reason string. **Defer** and **Compensating Adjustment** are
intentionally not exposed in this pass (they exist in `LegacyBaseline` but
need richer inputs — target player/season/amount for adjustments); scoped as
follow-up, noted in §18.

---

## 8. Coordinator Selection

Unchanged from the audit's findings: `Governance.EstablishInitialAuthority`
always assigns the acting GM as the initial coordinator (this is
architecturally required — only the live GM can author the record — but the
*named* coordinator does not have to be the GM). Choosing a different Officer
as initial coordinator was explicitly scoped out of this pass per the
audit's own recommendation (§7, §19 item 5); the readiness projection surfaces
the GM as the only candidate today.

---

## 9. Initialization Stages

| Stage | Prerequisite | Action | Already-complete behavior | Failure behavior |
|---|---|---|---|---|
| `stageGovernance` | none | `Governance.AdoptInitial` | No-op (`ALREADY_ADOPTED`) if `GOVERNANCE_ADOPTED` | Returns `Governance`'s reason (e.g. `CURRENT_GUILD_MASTER_REQUIRED`) |
| `stageLegacyDiscovery` | governance adopted | `LegacyBaseline.CollectLocalEvidence` | No-op (`NO_ACTION_REQUIRED`) if no real data or evidence already collected | Returns `LegacyBaseline`'s reason |
| `stageBaseline` | evidence findings all decided | `LegacyBaseline.FinalizeBaseline` | No-op (`ALREADY_APPROVED`) if a baseline exists | `LEGACY_RECONCILIATION_REQUIRED` / `INCOMPLETE_EVIDENCE_ACKNOWLEDGEMENT_REQUIRED` / `RECONCILIATION_UNRESOLVED` |
| `stageCoordinator` | approved baseline | `Governance.EstablishInitialAuthority` | No-op (`ALREADY_ACTIVE`) if authority is `ACTIVE` | Authority state (`HANDOFF_CLOSING`/etc.) if not `LEGACY_LOCAL`; `BASELINE_REQUIRED` |
| `stageCutover` | authority `ACTIVE` | `Governance.EnableV2` | No-op (`ALREADY_ENFORCED`) if V2 already enforced | `AUTHORITY_ACTIVE_REQUIRED` / `WRITER_COMPATIBILITY_REQUIRED` / `SYNC_BEHIND` |

`Installation.Initialize` runs these in order, stopping at (and reporting) the
first stage that cannot proceed, and returning the fresh
`Installation.GetStatus()` alongside every result for the caller to display.

---

## 10. Idempotency Guarantees

Verified by test:
- Re-running `Initialize` on an already-`READY` guild returns
  `ALREADY_INITIALIZED` and performs no mutation (governance revision
  unchanged).
- Re-running after a partial stop (e.g., blocked at `baseline`) resumes
  exactly at that stage; earlier stages' no-op checks prevent
  re-adoption/re-collection.
- No stage ever mutates `db.governance`, `db.ledger`, `db.sync.v2`, or
  baseline SavedVariables directly — all mutation flows through
  `Governance`/`LegacyBaseline` public functions, which already provide
  hash-chained idempotent-replay semantics.

---

## 11. Failure/Resume Behavior

Because every stage is a fresh read of authoritative state, a UI reload or
addon reload at any point resumes correctly with no explicit "resume" logic —
`Installation.GetStatus()`/`Initialize()` simply re-derive from whatever was
actually persisted. No rollback of immutable governance/baseline/authority
records was implemented or needed.

---

## 12. SavedVariables Impact

**None.** No new fields, no schema version change. `Installation.lua`
persists nothing.

---

## 13. Protocol Changes

**None.** No wire message types, capability flags, or protocol constants were
added or renamed. `LEGACY_LOCAL`, `CUTOVER_PREPARED`, and `V2_ENFORCED`
persisted values are unchanged; they are simply not the primary label shown
to normal users anymore (see §14).

---

## 14. UI Changes

- New Officer nav entry: **System → Guild Setup**.
- Guild Setup page: GM-only readiness summary (Governance / Existing DIBS
  Data / Coordinator / Guild Compatibility / Synchronization / Guild Ledger),
  reconciliation table when required, single **Initialize DIBS** action when
  ready, and a **Show/Hide technical details** disclosure exposing the raw
  protocol/authority/baseline/coordinator values.
- Non-GM viewers see a read-only line (either "Guild Ledger: Active | ..." or
  "DIBS has not yet been initialized for this guild. The Guild Master must
  complete the initial setup."), no buttons.
- Synchronization page: the "Approve baseline and enable V2" button was
  **REMOVED** (classification: superseded) and replaced with a read-only
  "Guild Ledger: Not enabled" line and an "Open Guild Setup" link when V2 is
  not yet enforced. Once enforced, that line/button no longer renders.
- Modules page's existing "Initialize Guild Governance" bootstrap block was
  **KEPT** unchanged (classification: KEEP) — it is independently tested
  (`module_management_spec.lua`), serves module-policy management (which only
  needs governance, not V2), and Guild Setup's own governance stage is
  idempotent against it (whichever runs first, the other becomes a no-op).

---

## 15. Tests Added

`tests/integration/installation_wizard_spec.lua` (10 tests):
readiness projection (`NOT_INITIALIZED`/non-GM hidden, `READY_TO_INITIALIZE`
on a clean guild, `RECONCILIATION_REQUIRED` on unscanned real data);
orchestrator (non-GM rejected without mutation, clean one-call
initialization + idempotent re-run, blocked-then-resumed reconciliation,
incomplete-evidence-not-silently-acknowledged, resume from the authority
stage); and two P0 regression tests directly against
`Governance.ActivateV2`.

---

## 16. Test Results

- Targeted: `installation_wizard_spec.lua` — **10 passed, 0 failed**.
- Governance/LegacyBaseline/SyncV2/module-management/relay/B09 regression
  batch (8 files) — **80 passed, 0 failed**.
- Full suite (138 files) — **622 passed, 1 failed**. The single failure is
  the pre-existing, unrelated `tests/integration/predibs_sync_recovery_spec.lua:50`
  heartbeat-timer-count baseline (`expected 1, got 2`), present before this
  work began and outside this feature's scope.

---

## 17. Compatibility Results

- Existing SavedVariables schema, ledger data, balances, Pre-Dibs, seasons,
  rank rules, governance records, operational policy, and RCLootCouncil
  integration are unaffected — confirmed by the unchanged pass rate of every
  pre-existing suite covering them.
- An existing guild that already reached `V2_ENFORCED` before this change
  reports `Installation.GetStatus().state == "READY"` immediately, with no
  migration step, since the projection is purely derived.
- An existing guild still in `LEGACY_LOCAL` is unaffected until a GM opens
  Guild Setup; nothing runs automatically on load.

---

## 18. Remaining Risks / Follow-Ups

| Risk | Note |
|---|---|
| `PEER_EVIDENCE_DIVERGENCE` false-positive on single-client scans | Cosmetic/labeling only (§6); underlying decision-based unblocking still works correctly. |
| No coordinator-candidate alternative to the acting GM | Scoped out per audit §7/§19; `EstablishInitialAuthority` always names the caller. |
| `Defer` and `Compensating Adjustment` decisions not exposed in the reconciliation UI | `RecordDecision` supports them; only `Include`/`Exclude` are wired today. |
| Sync tab's removed button has no direct test coverage of its removal (only the new Guild Setup path is tested) | Manual visual check recommended; behavior is additive (a label + a route-changing button), low risk. |
| French officer guide (`MODE_EMPLOI_GM_OFFICER.md`) not updated | English guide only, given scope; flagged for translation follow-up. |

No commits or pushes beyond the pre-implementation checkpoint were made
without this being an explicit, reviewable change set; nothing here has been
pushed to a remote.
