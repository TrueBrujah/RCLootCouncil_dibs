# DIBS Guided Setup Wizard: post-implementation validation

Audit date: 2026-09-25. Scope: `d5d561a..e6eb64c` and its production call paths.
This is a read-only audit of production code and tests; only this report was added.
The design reference is `DIBS_Guided_Setup_Wizard_Architecture.md`.

## 1. Executive summary

**Verdict: REMEDIATION REQUIRED.** The Wizard makes no direct ledger writes and
keeps Installation and SetupAssistant independently accessible. Nevertheless,
its prominent **Overall: Ready for raid** label can contradict the existing
readiness authority. The new integration test explicitly asserts that behavior.
The rank and Sync summaries can also say READY while their underlying services
report missing allocations or unavailable transport. These are P1 operational
readiness defects, not evidence of ledger corruption or an authority bypass.

The stated full-suite result of 645/1 is not reproducible at this commit:
an explicit run of all 139 `*_spec.lua` files produced **634 passed, 1 failed**.
The one failure is the known Pre-Dib heartbeat timer expectation.

## 2. Architecture compliance and business-logic reuse matrix

| Wizard source | Classification | Evidence / authority |
| --- | --- | --- |
| Installation and ledger | **CORRECT REUSE** | `Wizard.installationStatus` calls `Installation.GetStatus`; `stepLedger` maps its state, and `Open Ledger` routes to the existing Guild Setup page. No Wizard mutation calls `Installation.Initialize`. |
| Final readiness | **CORRECT REUSE** for the report, **ARCHITECTURAL LEAK** for the global label | `setupAssistantReport` calls `SetupAssistant.Evaluate`; `readinessStatus` maps its verdict. `Wizard.GetStatus` separately selects `READY_FOR_RAID` from `review.status` alone, then OfficerUI renders it as "Ready for raid". See F1. |
| Seasons | **ACCEPTABLE ADAPTER** | `Seasons.List(false)` counts non-archived seasons. No Raid/RaidConfig/WizardRaid entity was introduced. The existing Seasons tab owns changes. |
| RankRules | **ACCEPTABLE ADAPTER** with **DUPLICATED BUSINESS LOGIC** in status reduction | The new `GetRankConfigurationSummary` groups the existing reconciliation projection but discards its MISSING result when setting row status; see F2. No `CharacterEligibility` usage was found in the Wizard path. |
| Permissions | **CORRECT REUSE** | `GetAuthorizedOfficers` calls the existing `rankIsOfficer` on the live roster; its result only supplies a summary. It does not grant rights. |
| Pre-Dibs | **ACCEPTABLE ADAPTER** with incomplete status | `GetStatusSummary` composes existing mode/public-setting getters and request history, but its Wizard status is optimistic; see F5. |
| Dibs rules | **ACCEPTABLE ADAPTER** | Reuses SetupAssistant's `loot_types` check, including its `required=false` semantics; does not invent loot rules. |
| RCLootCouncil | **ACCEPTABLE ADAPTER** with misleading fallback | Calls `GetLocalStatus` (which obtains the existing capability snapshot), not a second detector; unsupported/disabled/unavailable states are all labeled as "not detected"; see F4. |
| Sync | **DUPLICATED BUSINESS LOGIC** | Calls only `Sync.IsSyncBehind` instead of using `Sync.GetStatus` or the existing `OfficerUI.BuildSynchronizationProjection`; see F3. |
| Review / navigation | **ACCEPTABLE ADAPTER** with missing links | Renders derived step summaries; its review rows and readiness findings do not provide per-finding navigation; see F6. |

The `STEPS` registry contains only ids and labels. `STEP_STATUS`, a separate
`dibsRules` branch, and `WIZARD_STEP_ROUTE` in OfficerUI distribute provider,
status, and destination across multiple maps. This is a maintainability risk,
not a separate authoritative configuration system (F9).

## 3. SavedVariables analysis

- **Schema migration:** none in this diff. The Core change only initializes
  `Dibs.Wizard = Dibs.Wizard or {}`; TOC/test loader add the module. No existing
  ledger, governance, or wire-schema definition was changed. Existing guild
  SavedVariables remain structurally compatible.
- **Completion persistence:** none. `Wizard.GetStatus` recomputes step status
  on each call. No `SetupComplete`, `ReadyForRaid`, cached readiness verdict,
  or persisted step-completion markers were introduced.
- **New write:** `Wizard.SetCurrentStepIndex` writes only
  `Dibs.GetLocalSettings().wizardStepIndex`. Invalid/missing/out-of-range
  persisted indices return step 1; Next/Back clamp to the first/last step.
  This cannot override the derived readiness result.
- **Scope caveat:** `GetLocalSettings` returns the single root
  `RCLootCouncil_dibsLocalDB.settings`, not a character-keyed store. The
  step index is local rather than guild-authoritative, but the claimed
  **per-character** resume behavior is not implemented (F8).
- **Read-path caveat:** `Wizard.GetStatus` invokes existing getters that can
  initialize/normalize data: `RankRules.GetRulesForSeason` creates a missing
  season rule table, `PreDibs.GetStatusSummary` calls `ensureState`, which
  fills/normalizes settings and request subtrees, and
  `Dibs.GetCurrentSeasonId` can create a default season if the guild has none.
  These pre-existing getters do not reset ledger history, but opening this
  ostensibly read-only page is not guaranteed to be byte-for-byte neutral
  on an incomplete/older guild database (F7). Routine startup already invokes
  some of these paths; the additional Wizard path should not be advertised as
  strictly mutation-free.

## 4. Ledger safety and Installation integration

`renderWizardPage` reads `Wizard.GetStatus`, constructs AceGUI labels/buttons,
and stores only a step index on navigation. The only step action is
`frame:ActivateRoute(route)`. The Ledger and Installation steps route to
Guild Setup; a separate, explicit GM click there is required to call
`Installation.Initialize`. Existing GM, baseline, evidence-decision and V2
cutover checks remain untouched by this commit. No Wizard callback directly
calls `Ledger`, `FinalizeBaseline`, `RecordDecision`, or an acknowledgement
option. Opening, refreshing, stepping, and closing do not themselves append
transactions, change allocation/balances, or discard history.

`Installation.GetStatus().state == READY` maps to a healthy Ledger row without
an Initialize button in the Wizard. A pre-V2 installation maps to
`ACTION_REQUIRED` or `WARNING` and links to Guild Setup. The Installation
step itself only checks governance plus some exception states; it does not
check Core's persistence-recovery status or schema/version, despite the
architecture audit's proposed Installation/Environment step (F9). The Ledger
row still detects an uninitialized guild, so this does not bypass activation.

## 5. Authorization analysis

`getOfficerNavigationTree` hides Officer pages from players;
`renderWizardPage` independently calls `canViewOfficerData` before adding
step/action buttons. GM and authorized Officers see the Wizard. The new
officer enumeration uses the existing configured rank threshold on current
roster data; it does not modify permissions. `Open ...` goes through existing
Officer routes, whose write actions retain their normal authorization;
Guild Setup restricts initialization to a roster-verified GM, and
Installation/Governance recheck this at the business boundary. No direct
Wizard callback changes guild configuration, so no elevation was found.

The helper returns an empty list if the roster API errors or is unavailable;
the Administration step shows a warning, not an invented GM. Roster changes
are reflected on the next `Wizard.GetStatus` invocation, but the Wizard page
has no automatic roster-event refresh (F6).

## 6. Seasons and RankRules domain validation

Seasons are the only configured content boundary used in this implementation;
multiple non-archived seasons remain listed and unchanged. No new raid domain
object or season mutation was added. Rank configuration uses only
`Dibs.RankRules`, not the separate alt/main `CharacterEligibility` subsystem.
`GetRankConfigurationSummary` groups guild-roster members by rank and calls
`GetAllocationReconciliation`, but it ignores `missingByRank` when choosing
`status`. Thus an explicitly configured positive allocation with
`pendingReconciliation > 0` is marked `READY`. It also omits ranks with no
current members. The caller shows only the aggregate status/summary and
does not render the returned rows. See F2 for the resulting false confidence.

## 7. Pre-Dibs, RCLootCouncil and Sync validation

`PreDibs.GetStatusSummary` creates no request, clears no declaration and
publishes no Sync message. It counts history across every season and counts
all statuses other than fulfilled/cancelled/invalidated as active, reusing the
existing `isRequestActive`. The Wizard reports READY whenever
`publicEnabled ~= false`, even if the mode getter is missing/throws (the
fallback becomes `WILD_OPEN`), or a Pre-Dibs module has been disabled. These
are diagnostics gaps (F5), not evidence of lost Pre-Dibs data.

`RCLootCouncil.GetLocalStatus` is the existing capability API. The Wizard
does not mutate RC or grant RC authority. However `absent`, `disabled`,
`unsupported`, and failures to obtain a snapshot all fall into the same
OPTIONAL / "not detected" branch. An intentionally absent optional RC is
fine; a loaded but unsupported RC is not the same condition (F4). The
SetupAssistant report retains its own RC check separately.

The Sync step only reads `Sync.IsSyncBehind`; it emits no broadcasts or
repairs and does not change authoritative state. If Ace3 transport is absent
or unregistered, `Sync.GetStatus().state == SYNC_UNAVAILABLE` but
`IsSyncBehind() == false`, so the step says "Synchronization is ready".
This is a demonstrable false READY state (F3).

## 8. Readiness authority and final-state mapping

`SetupAssistant.Evaluate` remains independently callable and its report is
passed into the Wizard's `readiness` step. The mapping is:

| SetupAssistant status | Wizard readiness step | Global Wizard state |
| --- | --- | --- |
| `READY_FOR_RAID` | READY | Can be `READY_FOR_RAID` if Review is READY |
| `NEEDS_ATTENTION` | WARNING | **Still `READY_FOR_RAID`** if Review is READY |
| `UNAVAILABLE` | BLOCKED | **Still `READY_FOR_RAID`** if Review is READY |
| `DENIED` | BLOCKED | Typically inaccessible via OfficerUI; `Wizard.GetStatus` itself ignores its actor parameter |

The global state is selected from `review.status` without using the readiness
status. OfficerUI maps it to **"Overall: Ready for raid"** on every step.
The existing test explicitly asserts the contradiction when
`SetupAssistant.Evaluate().status ~= READY_FOR_RAID`. The review step also
excludes the readiness step from `reviewStatus`, so Review can be READY at
the same time as the final step is BLOCKED. This violates the requested rule
that SetupAssistant/readiness evidence wins (F1). Calling this state
"configuration complete" would be distinct; displaying it as raid readiness
is not. The final UI never renders the report's `checks`/`blockingCount` or
maps individual findings to destinations; it displays only the status and a
button to the standalone Setup Assistant (F6).

## 9. Combat-lockdown validation

Normal opening through `OfficerUI.Toggle` defers the whole Officer window
while `InCombatLockdown()` is true. Wizard buttons only switch step index,
call `frame:Refresh`, or route to an existing Officer page. They do not
invoke protected actions. `AceGUI.RequestRefresh` and the existing Officer
page paths supply their own combat controls; the Wizard creates no new event
handler or scheduled timer. Direct `CreateWindow("wizard")`/refresh and
widget construction are not separately guarded by `InCombatLockdown`, and
there is **no in-game Retail combat test** in the new suite. Treat normal
navigation as low-risk, not as proven safe for every direct/API path (F10).

## 10. UI lifecycle, navigation and Review mapping

`OfficerUI.CreateWindow` reuses the existing frame, whose route renderer
clears/rebuilds the page. The Wizard registers no events, timers, or frame
hooks. Each navigation click reruns `Wizard.GetStatus` through `frame:Refresh`;
Back/Next clamp at the endpoints. A saved index greater than 12, missing or
non-numeric resolves to 1. Direct clicks allow visiting any step without
fabricating completion. Closing/reopening the same frame and reload can
restore a valid last-viewed index; no duplicate listener is introduced.

No automatic refresh is registered for the Wizard when roster, guild,
governance or configuration changes arrive externally. While the page stays
open and idle, its labels can remain stale; clicking a step, refreshing via
the existing route, or reopening recomputes them (F6). The locally persisted
index is global across characters/guilds rather than per-character (F8).

Review rows map as follows (all are displayed by iterating the same
`status.steps` returned by `Wizard.GetStatus`; Review itself is omitted):

| Review row | Source API | Wizard transformation | Authority |
| --- | --- | --- | --- |
| Installation / Ledger | `Installation.GetStatus` | State-to-label/status maps | Installation/Governance |
| Guild | `GetGuildInfo("player")` | Name-present check | WoW guild API |
| Administration | `Permissions.GetAuthorizedOfficers` | GM/officer count | Permissions + live roster |
| Seasons | `Seasons.List(false)` | Count > 0 | Seasons |
| Rank Rules | `RankRules.GetRankConfigurationSummary` | Counts `ACTION_REQUIRED`/`WARNING` | RankRules (but F2 discards MISSING) |
| Dibs Rules | `SetupAssistant.Evaluate().checks[loot_types]` | Non-required unavailability -> OPTIONAL | SetupAssistant |
| Pre-Dibs | `PreDibs.GetStatusSummary` | public disabled -> OPTIONAL, else READY | PreDibs (F5) |
| RCLootCouncil | `RCLootCouncil.GetLocalStatus` | operational -> READY; degraded -> WARNING; other -> OPTIONAL | RC capability service (F4) |
| Sync | `Sync.IsSyncBehind` | true -> WARNING, false -> READY | Partial Sync state (F3) |
| Readiness | `SetupAssistant.Evaluate` | Verdict-to-step status | SetupAssistant (F1/F6 for global/UI) |

Review rows are labels, not clickable links back to their step; only the
global "Jump to first issue" and top step buttons provide navigation.

## 11. Test coverage review and regression analysis

The new spec uses the real addon loader and exercises fresh setup, a granted
legacy transaction, rank 7 without a rule, GM Wizard navigation, direct step
clicks, local index clamping and non-officer UI denial. It confirms the
readiness report is reused, but **asserts the incorrect global READY verdict
when that same report is not ready**. The rank fixture only tests a missing
rule, not a configured rank whose allocation is MISSING; it does not catch
F2. The CharacterEligibility test instruments table indexing; the production
Wizard source also contains no CharacterEligibility reference.

High-value tests missing: snapshots of ledger, Pre-Dibs, seasons and rank
rules before/after opening and navigation; an existing V2 guild after reload;
configured-but-unallocated rank; unsupported RC with RC-required mode;
unregistered transport and SYNC_BEHIND; blocked readiness mapping and
per-finding links; rank/permissions changes while open; guild/character
switch with a saved step; invalid local index types; combat; repeated
close/reopen; and ensuring no new listeners. No test demonstrates actual
Retail canvas/layout or combat behavior. The 11 passing tests are real paths,
but insufficient proof of the completion-report safety claims.

At `e6eb64c`, the 11 Wizard tests pass. The full suite, enumerated using
`DIBS_TEST_FILES`, yielded **634 passed, 1 failed (139 files)**; thus the
reported **645 passed, 1 failed** count is inaccurate. The sole failing test
is `predibs_sync_recovery_spec.lua:50` (`expected 1, got 2` scheduled
timers), reproduced when run alone. Its file and the Sync, Readiness and
SetupAssistant modules are unchanged in `d5d561a..e6eb64c`; Wizard.lua
only defines functions at module load and registers no heartbeat timer. The
same failure was observed on earlier pre-Wizard runs in this session.
Classification: **CONFIRMED PRE-EXISTING** from prior run evidence plus
unchanged owning code; no fresh pre-commit checkout was executed during
this pass. Do not count it as a new Wizard regression or conceal it.

## 12. Findings by severity

| ID | Severity | Location / exact behavior | Impact and recommended remediation | Regression risk |
| --- | --- | --- | --- | --- |
| F1 | **P1** | `Wizard.GetStatus` / `reviewStatus` and `OfficerUI.renderWizardPage`: `review.status == READY` sets global `READY_FOR_RAID` even when `SetupAssistant.Evaluate` reports `UNAVAILABLE` or `NEEDS_ATTENTION`; the test codifies this. | False "Ready for raid" signal. Keep a distinct configuration-complete label, or make the global raid-ready verdict subordinate to SetupAssistant; test all final statuses. | Medium: change only derived label/step semantics, not readiness service or ledger. |
| F2 | **P1** | `RankRules.GetRankConfigurationSummary`: records `pendingReconciliation` but returns `READY` whenever a positive rule exists, even if `GetAllocationReconciliation` reports `MISSING`. | GM may conclude rank allocation is complete when members lack their assigned Dibs. Surface the outstanding count/status and validate the reduction against the existing projection. | Medium: projection-only, but may change displayed completion. |
| F3 | **P1** | `Wizard.stepSync`: `IsSyncBehind() == false` maps to READY even when `Sync.GetStatus().state == SYNC_UNAVAILABLE`. | Misleading synchronization readiness in a multi-raid workflow. Reuse the existing Sync status/projection and distinguish unavailable from caught-up. | Low: read-only mapping. |
| F4 | **P2** | `Wizard.stepRCLootCouncil`: `unsupported`, disabled, failed/absent status all become OPTIONAL "not detected". | Hides a loaded but unusable integration; respect the existing installation mode/capability reason code in the summary. | Low: display-only, preserve RC optionality. |
| F5 | **P2** | `PreDibs.GetStatusSummary` / `Wizard.stepPreDibs`: no module-health or invalid-mode check; mode fallback `WILD_OPEN` and all-season request counts can mask missing/disabled configuration. | Inaccurate Pre-Dibs step without lost requests. Use existing mode/module diagnostics, scope counts where labeled, and fail visibly on unavailable status. | Low: additive read-only projection. |
| F6 | **P2** | `OfficerUI.renderWizardPage`: readiness checks/details and rank/Pre-Dibs row details are never rendered; Review warnings are labels without step links; no Wizard-specific refresh on external state changes. | A GM cannot see the implicated rank or readiness reason within the Wizard and can see stale results until navigating. Render existing `detail` and per-finding routes; reuse coalesced refresh mechanisms. | Medium: widget lifecycle must be tested in Retail. |
| F7 | **P2** | `Wizard.GetStatus` -> existing `PreDibs.ensureState`, `RankRules.GetRulesForSeason`, `Dibs.GetCurrentSeasonId`: getters can fill/normalize settings or create missing season/rules. | Contradicts a literal "opening the Wizard does not mutate unrelated data" guarantee for incomplete databases; no evidence of lost ledger history. Use non-mutating projections or explicitly treat these as pre-existing initialization effects and test snapshots. | Medium: changing core getters globally would be risky; prefer a local read strategy. |
| F8 | **P3** | `Wizard.GetCurrentStepIndex` / `SetCurrentStepIndex` write one root `RCLootCouncil_dibsLocalDB.settings.wizardStepIndex` for all local characters/guilds. | Does not meet the reported per-character resume scope; harmless navigation surprise after switching characters. Key UI preference by character/guild, never use it as completion truth. | Low: additive local preference migration. |
| F9 | **P2** | `Wizard.stepInstallation` only checks governance/authority; no persistence recovery/schema/module diagnostic, and provider/route logic is split between `STEP_STATUS` and OfficerUI. | The architecture audit's Installation/Environment diagnostic step is incomplete; support may miss recoverable SavedVariables faults. Compose existing Core persistence diagnostics, keep step metadata near its provider/route. | Low-medium: presentation only, but don't bypass existing fail-closed persistence controls. |
| F10 | **P3** | Combat handling in `OfficerUI.Toggle` protects normal opening, but direct Wizard route/render in combat and repeated close/reopen have no dedicated tests. | No new protected action found; safety beyond the normal Toggle path remains unverified in Retail. Add an in-combat UI lifecycle test before claiming unconditional combat safety. | Low: tests/verification only. |

No P0 data-loss or unauthorized-write finding was found. F1-F3 block a
production-readiness claim because they can materially misstate operational
state. Missing detailed rank/Pre-Dibs tables (F6) are P2 because the
underlying configuration pages remain reachable; their absence alone is not
a ledger-integrity issue. The prior report's optimistic assertion that
"readiness evidence wins" is contradicted by F1.

## 13. Required remediation

1. Resolve F1 before production: derive any **raid-ready** label from
   `SetupAssistant.Evaluate`, or rename the independent configuration label
   and make it impossible to confuse the two. Replace the test asserting
   `READY_FOR_RAID` while readiness is unavailable with tests for READY,
   warning and blocked outcomes.
2. Resolve F2/F3 before using Wizard step statuses for go/no-go decisions:
   retain allocation reconciliation signals and consult transport status.
3. Address F4-F9 as focused follow-ups; verify side-effect boundaries with
   snapshot tests rather than changing persistence modules speculatively.
4. Run in-game Retail smoke checks for opening/navigating during combat and
   for reuse/reopen/refresh. Keep the legacy heartbeat failure separately
   tracked; it was not introduced by this Wizard commit.

## 14. Production readiness verdict

**REMEDIATION REQUIRED**