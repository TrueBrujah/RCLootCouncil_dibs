# DIBS Guided Setup Wizard — Architecture Audit

Status: Read-only architecture audit. No production code was modified to
produce this document.

Scope inspected: `src/ui/SetupAssistant.lua`, `src/modules/Readiness.lua`,
`src/modules/Installation.lua`, `src/ui/OfficerUI.lua` (nav tree, Guild Setup,
Modules, Sync, Seasons, Ranks tabs), `src/modules/{Seasons,RankRules,PreDibs,
Permissions,Governance,LegacyBaseline,SyncV2,Ledger,CharacterEligibility}.lua`,
`src/integrations/RCLootCouncil.lua`, `src/Core.lua` (SavedVariables schema
and migration), and `specs/014-first-installation-assistant/*`.

---

## 1. Executive Summary

Two things already exist and must not be merged or replaced:

1. **`Dibs.Readiness` + `Dibs.SetupAssistant`** — an operational validation
   engine (`Readiness.Evaluate`, probes: `season`, `policy`, `authority`,
   `installation`, `rclootcouncil`, `dib_response_projection`, `raid_context`,
   `sync_context`, `local_services`) plus a thin UI-facing wrapper
   (`SetupAssistant.Evaluate`) that reuses those probes, adds a few
   installation-framed checks (`rank_rules`, `channels`, `loot_types`), and
   exposes protected setup actions (`season.create`, `installation.mode.set`)
   plus a local dry-run. This is the "Readiness Check" the request refers to.
   It is explicitly a **transient, non-authoritative projection** — spec
   014's own research doc already rejected a persisted
   "wizard-completion flag" for exactly the reason this request repeats.
2. **`Dibs.Installation` + OfficerUI's "Guild Setup" page** (implemented in
   this repository's immediately preceding work) — a **governance/ledger
   activation orchestrator**: `GetStatus`/`Initialize` derive readiness from
   `Governance`/`LegacyBaseline`/`Sync` and drive the guild from
   `NOT_INITIALIZED` to `READY` (canonical V2 ledger active), with a
   reconciliation step for legacy data. It already links forward into
   Setup Assistant once the ledger is active.

**No stepped, multi-page, Back/Next "wizard" UI paradigm exists anywhere in
this codebase.** Every existing guided surface (Setup Assistant, Guild Setup,
Modules bootstrap) is a single Officer-nav-tab page with inline status rows
and action buttons — not a modal stepper with a persisted step index. Building
the requested 12-step navigable wizard is a genuinely new **presentation**
component; almost none of the underlying **business logic** it needs is new.

**Terminology reconciliation (must be stated explicitly to avoid inventing
parallel concepts):**
- The request's **"Raid Configuration"** has no literal 1:1 entity in this
  codebase. The closest existing configurable unit is **`Dibs.Seasons`**
  (a season = an allocation boundary, roughly one raid tier/content cycle).
  "Multi-raid" in this codebase means **multiple simultaneous in-game raid
  groups synchronizing to one guild-scoped ledger** (`SyncV2`/`Governance`
  coordinator model), not multiple configured "raid" entities. The Wizard's
  Step 4 must be re-scoped to **Season review/creation**, and its Step 10
  ("Synchronization / Multi-Raid") is the correct home for the
  simultaneous-raid-groups concept.
- The request's **"Guild Ranks / Eligibility"** (Step 5) maps to
  **`Dibs.RankRules`** (per-rank seasonal allocation), **not** to
  `Dibs.CharacterEligibility` (which governs Curio/Tier-Set alt/main sharing
  policy — a materially different concept). This must not be conflated.

**Verdict: READY FOR IMPLEMENTATION** (phased), with one required new small
API surface (an officer-count/list read helper in `Permissions`, since none
exists today) and one new Pre-Dibs-status projection helper — both purely
additive, read-only, no schema change.

---

## 2. Existing Architecture

### 2a. `Dibs.Readiness` (`src/modules/Readiness.lua`)
The actual probe engine. `Readiness.Evaluate(options)` builds a `result`
containing `probes[]` (each `{ name, state, reasonCode, impact, remediation,
required }`), an overall `state`, and a deterministic `fingerprint`. Probes
cover: `season`, `policy` (rank rules present), `authority` (permissions),
`installation` (mode validity), `rclootcouncil`, `dib_response_projection`,
`raid_context` (is the character actually in a raid instance — **live-raid
framing**), `sync_context` (Raid Dibs channel visibility), `local_services`.
`Readiness.Run`/`GetLast`/`Invalidate`/`IsFresh`/`CanProcessLiveAward` manage
a cached, invalidated-on-event result (roster/zone/combat changes), consumed
by the live Drop-Dib path — **this module is about "is it safe to process a
live award right now,"** not primarily about first-time configuration.

### 2b. `Dibs.SetupAssistant` (`src/ui/SetupAssistant.lua` + OfficerUI "setup" tab)
`SetupAssistant.Evaluate(options)` calls `Readiness.Evaluate({allowPlayer=true})`,
re-labels a couple of reason codes for installation framing (e.g.
`RC_LOADED_NO_RAID_CONTEXT` instead of treating "not in a raid yet" as an
error during setup), and **adds** its own checks not covered by `Readiness`:
`season` (duplicate-guard against `Readiness`'s own season probe), `rank_rules`
(does the active season have any allocation entries at all),
`channels` (Raid Dibs channel visibility, duplicate of `sync_context` under a
different id for UI grouping), `loot_types` (RC options panel availability).
It exposes `ExecuteAction("season.create"|"installation.mode.set", actor,
payload)` — a thin, allowlisted pass-through to
`Dibs.ProtectedActions.Execute` — and `RunDryRun`/`GetLastDryRun` (delegates
to `Dibs.DryRun.Run`). **No persisted completion flag exists**; `report.status`
(`READY_FOR_RAID`/`NEEDS_ATTENTION`/`UNAVAILABLE`/`DENIED`) is recomputed on
every call from `report.checks`.

The OfficerUI "setup" tab (nav: OVERVIEW → Setup Assistant) renders this
report as a single table (`Check | State | Blocks | Next action | Setup`)
plus season-creation and installation-mode controls inline. **This is the
UI the request calls "Setup Assistant / Readiness Check."** It must remain
independently callable and must not become a mandatory sequential gate — it
already satisfies that constraint today.

### 2c. `Dibs.Installation` + Guild Setup (`src/modules/Installation.lua` +
OfficerUI "installation" tab, System → Guild Setup)
`Installation.GetStatus(actor)` derives (never persists) one of
`NOT_INITIALIZED | RECONCILIATION_REQUIRED | READY_TO_INITIALIZE | READY |
COORDINATOR_UNAVAILABLE | RECOVERY_REQUIRED | BLOCKED` purely from
`Governance.GetState()/GetAuthorityState()/IsV2Enforced()`,
`LegacyBaseline.GetState()/GetBaseline()/GetFindings()`,
`Sync.IsSyncBehind()/CanEnforceV2()`, `Identity.IsCurrentGuildMaster()`, and
direct ledger/Pre-Dibs data. `Installation.Initialize(actor, options)` is a
staged, idempotent, resumable orchestrator
(governance → legacy discovery → baseline → coordinator → cutover), already
covered by `tests/integration/installation_wizard_spec.lua`. Once
`state == "READY"`, the page already surfaces "Next steps" pulled directly
from `SetupAssistant.Evaluate()` and a link to open the full Setup Assistant
page — **this is the exact seam the new Wizard should extend, not
duplicate.**

### 2d. Domain modules relevant to the requested Wizard steps
| Concept | Module | Key APIs |
|---|---|---|
| Guild identity | `Dibs.GetGuildKey`, `GetGuildInfo` (WoW API) | read-only |
| Administration/permissions | `Dibs.Permissions` | `IsGM`, `IsOfficer`, `GetGuildRole`, `Evaluate`; officer threshold via `settings.officerRankIndices`/`officerMaxRankIndex` (rank-based, not a stored name list) |
| Seasons ("raids") | `Dibs.Seasons` | `Create`, `GetById`, list/current, `GetCatalogState`, guild configuration import/export |
| Rank allocation ("eligibility") | `Dibs.RankRules` | `GetRulesForSeason`, `SetAllocation`/`SetRankAllocation`, `GetAllocationForPlayer`, `GetAllocationReconciliation` (existing per-rank MISSING/SURPLUS/ALIGNED status — this is the exact data the requested rank table needs) |
| Dibs rules (loot types) | `Dibs.RCOptions` (options panel) | existing Officer Loot Rules tab; `SetupAssistant`'s `loot_types` check already probes its availability |
| Pre-Dibs | `Dibs.PreDibs` | `GetModePolicy`/`SetModePolicy` (per season), `GetAnnouncementSettings`, `GetActiveRequests`/`GetHistory` — **no existing single "Pre-Dibs status" summary projection** |
| Ledger | `Dibs.Ledger`, `Dibs.Governance`, `Dibs.LegacyBaseline` | fully covered by `Dibs.Installation.GetStatus` already |
| RCLootCouncil | `Dibs.RCLootCouncil` | `GetCapabilities()`, `GetLocalStatus()`, `GetAwardAdapterStatus()` — exact capability/compatibility snapshot the requested Step 9 needs |
| Synchronization/multi-raid | `Dibs.Sync`, `Dibs.OfficerUI.BuildSynchronizationProjection` | existing Sync tab projection (protocol state, peers, baseline status) |
| Combat lockdown | `InCombatLockdown()` guards already used in `AceGUI.lua`, `OfficerUI.lua`, `RaidPrompts.lua`, `RCLootCouncil.lua` | established, reusable pattern (defer/queue rather than fail) |

---

## 3. Proposed Wizard Responsibilities

The Wizard is a **navigation and composition layer**: it orchestrates
existing read-only projections and existing protected mutation entry points
in a guided order, with a persisted **position** (not persisted
**correctness**). It introduces no new authority model, no new ledger
mutation, no new SavedVariables schema, and no new reconciliation engine.

Concretely, the Wizard is a new Officer nav entry (e.g. `System → Guided
Setup`, or `Overview → Guided Setup` alongside the existing `Setup Assistant`
entry) that renders a left-hand step list (reusing the existing tree/section
rendering pattern already used for the main Officer nav) and a right-hand
content pane per step, where each pane is a **thin composition of already
existing projections/actions**, not new business logic.

---

## 4. Mapping Every Requested Step to Existing Code

| Wizard step (request) | Existing code reused | Missing piece |
|---|---|---|
| 1. Installation/Environment | `Dibs.VERSION`, `Core.lua` schema constants (`ROOT_SCHEMA_VERSION`, `GUILD_SCHEMA_VERSION`), `Dibs.Capabilities` (module load/retry state), `Readiness` `local_services`/`installation` probes | None — pure read of existing state |
| 2. Guild | `Dibs.GetGuildKey`, `GetGuildInfo`, `Identity.RefreshRoster`/roster-generation freshness | None |
| 3. Administration/Permissions | `Permissions.IsGM/IsOfficer/GetGuildRole`, `officerRankIndices`/`officerMaxRankIndex` settings | **New (small):** a read-only "list/count guild members currently at officer rank" helper — today `rankIsOfficer` is `local` to `Permissions.lua`; no existing API enumerates current officers by name. Add `Permissions.GetAuthorizedOfficers()` (roster scan + existing threshold logic), not a new authorization model |
| 4. "Raid Configuration" | **Re-scoped to `Dibs.Seasons`**: `Seasons.Create`, list/current/`GetCatalogState`. Per-season Dibs rules via `RankRules`. | None — this step is Season review/creation, already fully supported; do not invent a new "raid" entity |
| 5. Guild Ranks/Eligibility | `RankRules.GetRulesForSeason`, `RankRules.GetAllocationReconciliation` (already computes MISSING/SURPLUS/ALIGNED per rank/player) | Wizard-level: a **per-rank** (not per-player) rollup — group `GetAllocationReconciliation` rows by `rankIndex`/`rankName` and reduce to one status per rank (`READY` if every rule for that rank is set, `ACTION REQUIRED` if the rank has members with no configured rule). This is a small aggregation over an existing projection, not new domain logic |
| 6. Dibs Rules | `Dibs.RCOptions` loot-type panel (already surfaced via `SetupAssistant`'s `loot_types` check); `RankRules.SetAllocation` | None beyond linking to the existing panel |
| 7. Pre-Dibs | `PreDibs.GetModePolicy(seasonId)`, `PreDibs.GetAnnouncementSettings()`, `PreDibs.GetActiveRequests`/`GetHistory` (existing-data detection) | **New (small):** a summary projection `{ enabled, mode, activeRequestCount, historyCount }` composing the above three read calls — no new persisted state, no new mutation |
| 8. Ledger | `Dibs.Installation.GetStatus()` — already returns exactly the requested state set (mapped: `READY`→`EXISTING — HEALTHY`, `RECONCILIATION_REQUIRED`→`EXISTING — MIGRATION REQUIRED`/`WARNING` depending on cause, `NOT_INITIALIZED`/`READY_TO_INITIALIZE`→`NOT INITIALIZED`, `COORDINATOR_UNAVAILABLE`/`RECOVERY_REQUIRED`/`BLOCKED`→`INVALID/BLOCKED`) | None — this step **is** the existing Guild Setup page, embedded as a Wizard step, not reimplemented. The request's explicit safety requirement ("never hardcode acknowledgement of incomplete evidence") is **already satisfied** by the P0 fix validated in `Installation_Initialization_V2_Post_Implementation_Validation.md` |
| 9. RCLootCouncil | `RCLootCouncil.GetCapabilities()`, `GetLocalStatus()` | None — direct read |
| 10. Synchronization/Multi-raid | `OfficerUI.BuildSynchronizationProjection()`, `Sync.GetPeerStatuses()`, `Sync.IsSyncBehind()` | None — reuse the existing Sync tab's projection function directly; do not re-derive |
| 11. Review | Composition of all of the above projections into one read-only summary | New (composition only — a pure aggregation function, no new source of truth) |
| 12. Final Readiness Check | `Dibs.SetupAssistant.Evaluate()` (which itself composes `Dibs.Readiness.Evaluate`) | None — call verbatim, per the request's own explicit instruction not to build a second readiness engine |

**Combat lockdown:** the Wizard must defer only its own write actions
(season creation, rank allocation writes, mode changes) using the same
`InCombatLockdown()` guard pattern already used in `AceGUI.lua`/`OfficerUI.lua`
(defer/queue, never fail silently); read-only steps (1, 2, 8, 9, 10, 11, 12)
have no combat-safety concern since they perform no mutation.

---

## 5. Existing Components to Reuse (do not duplicate)

- `Dibs.SetupAssistant.Evaluate` / `Dibs.Readiness.Evaluate` — final
  readiness step, verbatim.
- `Dibs.Installation.GetStatus` / `Initialize` — ledger step, embedded, not
  reimplemented.
- `Dibs.OfficerUI.BuildSynchronizationProjection` — sync step.
- `Dibs.RCLootCouncil.GetCapabilities`/`GetLocalStatus` — RC step.
- `Dibs.RankRules.GetAllocationReconciliation` — rank table, aggregated per
  rank for the Wizard's rollup view.
- `Dibs.ProtectedActions.Execute` — the **only** mutation entry point the
  Wizard should call for `season.create`, `installation.mode.set`,
  `rank.set`, `predib.mode.set`; never a direct SavedVariables write.
- OfficerUI's existing nav-tree/section rendering pattern
  (`OFFICER_NAV_TREE`, `buildOfficerTree`, `getOfficerNavigationTree`) — reuse
  the same data shape for the Wizard's own step list, rather than inventing a
  parallel navigation component.
- The existing `governanceBootstrapPending`-style "pending → confirm/cancel"
  UI pattern already used in the Modules tab and Guild Setup's action
  buttons — the correct shape for any Wizard step that requires an explicit
  confirmation before a write.
- The existing `INSTALLATION_STATE_LABEL`-style presentation-label mapping
  pattern in `OfficerUI.lua` — reuse the same approach (map technical
  states to `READY`/`ACTION REQUIRED`/`WARNING`/`BLOCKED`/`NOT CONFIGURED`/
  `OPTIONAL` labels) for every Wizard step status, for consistency with
  Guild Setup's existing vocabulary.

---

## 6. Required New Components (all additive, all read-only except explicit writes routed through `ProtectedActions`)

1. **`Permissions.GetAuthorizedOfficers()`** (or similarly named) — enumerate
   current guild roster members whose rank passes the existing
   `officerRankIndices`/`officerMaxRankIndex` threshold. Read-only; reuses
   existing threshold logic (currently `local rankIsOfficer`), does not
   introduce a second authorization model.
2. **A Pre-Dibs status summary** composing `PreDibs.GetModePolicy`,
   `GetAnnouncementSettings`, and active/history counts into one small
   table for the Wizard's Step 7 — no new persisted state.
3. **A per-rank rollup** over `RankRules.GetAllocationReconciliation`'s
   existing per-player rows, grouped by rank, for the Wizard's Step 5 table
   — pure aggregation.
4. **The Wizard shell itself**: a new OfficerUI nav entry + step-list
   rendering + a small `Dibs.Wizard`-or-similar module holding **only**:
   - the step registry (id, label, render function reference, "is this step
     relevant/skippable" predicate);
   - the derived overall Wizard state (`NEW_INSTALLATION` /
     `EXISTING_CONFIGURATION` / `PARTIALLY_CONFIGURED` /
     `CONFIGURATION_REQUIRES_ATTENTION` / `READY_FOR_RAID` /
     `UPGRADE_MIGRATION_REQUIRED`), derived the same way
     `Installation.GetStatus` derives its state — from live evidence
     (`Installation.GetStatus()` + `SetupAssistant.Evaluate()` + presence of
     existing ledger/Pre-Dibs/season data), **never** a single boolean flag;
   - the currently-selected step index, persisted the same way
     `WindowState`/`OfficerWindowPosition` already persists **UI position**
     (per-character local UI state, not guild-authoritative data) — matching
     this codebase's existing local-vs-guild persistence split
     (`Dibs.GetLocalDB()` vs `Dibs.GetDB()`).

No SavedVariables schema change is required for any of the above; item 4's
"currently-selected step index" is the only new persisted field, and it
belongs in the existing per-character local UI-state store
(`Dibs.GetLocalDB().settings`-adjacent), exactly like existing UI-only
preferences (`developerModeEnabled`), **not** in guild-scoped `db`.

---

## 7. State / Data-Flow Diagram

```
                        ┌─────────────────────────────┐
                        │   Dibs.Wizard.GetStatus()    │  (new, thin, derived)
                        └──────────────┬───────────────┘
                                       │ reads (no writes)
        ┌────────────────┬────────────┼────────────┬─────────────────┬───────────────┐
        ▼                ▼            ▼            ▼                 ▼               ▼
 Identity/Permissions  Seasons    RankRules    PreDibs (new       Installation    RCLootCouncil /
 (Guild, Admin steps)  (Raid      (Ranks       summary helper)    .GetStatus()    Sync projection
                       step)      step)        (Pre-Dibs step)    (Ledger step)   (RC/Sync steps)
        │                │            │            │                 │               │
        └────────────────┴────────────┴────────────┴─────────────────┴───────────────┘
                                       │
                                       ▼
                        ┌─────────────────────────────┐
                        │   Review step (pure compose) │
                        └──────────────┬───────────────┘
                                       │
                                       ▼
                        ┌─────────────────────────────┐
                        │ Dibs.SetupAssistant.Evaluate │  (existing, reused verbatim)
                        │        = Final Readiness      │
                        └─────────────────────────────┘

Writes only via: Dibs.ProtectedActions.Execute(actionId, actor, payload)
  → season.create / installation.mode.set / rank.set / predib.mode.set
  → Governance/LegacyBaseline/Ledger APIs (Ledger step only, via
    Dibs.Installation.Initialize — already staged/idempotent/resumable)
```

---

## 8. SavedVariables Impact

**None to guild-scoped `db`.** One small addition to the existing
per-character local UI-state store (`Dibs.GetLocalDB()`), analogous to
`developerModeEnabled`, to remember the Wizard's last-viewed step for
resume-later UX. This is presentation-only, matches the pattern this
codebase already uses for UI position (`WindowState`), and — per the
request's own "Completion semantics" requirement — **must never be treated
as a source of truth for whether configuration is actually complete**; the
Wizard's step "done" glyphs are always recomputed from live evidence on
every open, exactly like `Installation.GetStatus`.

---

## 9. Compatibility / Risk Assessment

| Risk area | Assessment |
|---|---|
| Ledger destruction/reset | **No risk** — Step 8 embeds `Dibs.Installation`, which is already validated (P0-fixed, test-covered) to never bypass reconciliation and never mutate SavedVariables directly. |
| Historical Pre-Dibs loss | **No risk** — Step 7 is read + existing `ProtectedActions`-routed mode-policy change only; no delete/clear action is in scope. |
| Silent guild/rank/raid settings reset | **No risk if step 4/5/6 writes are routed exclusively through existing protected actions** (`season.create`, `rank.set`) exactly as `SetupAssistant` already does — the Wizard must not gain any direct `Dibs.GetDB()` write access. |
| Multi-raid/sync corruption | **No risk** — Step 10 is read-only (`BuildSynchronizationProjection`); any coordinator/authority mutation remains exclusively in Guild Setup's already-validated `Installation.Initialize`. |
| RCLootCouncil integration breakage | **No risk** — Step 9 is read-only capability display; no RC configuration write is in scope for the Wizard itself (RC configuration remains in its existing options panel). |
| Combat lockdown | **Low risk, established pattern** — apply the existing `InCombatLockdown()` defer/queue pattern to any write action triggered from within the Wizard; no new combat-safety design needed. |
| Duplicate readiness engine | **No risk if Step 12 calls `SetupAssistant.Evaluate()` directly** — this must be enforced in implementation review, since it is the single most explicit instruction in the request. |
| Persisted completion flag anti-pattern | **No risk** — spec 014 already established and tested the "derive, don't persist" precedent; the Wizard's own state derivation (§6 item 4) must follow it identically. |
| New officer-enumeration helper duplicating authorization logic | **Low risk** — must be implemented as a thin wrapper calling the *existing* rank-threshold check, not a re-derivation of officer status. |

**No blockers identified.**

---

## 10. Implementation Phases (recommended, not mandatory sequencing)

1. **Phase 0 — Git checkpoint.** Confirm working tree is clean before any
   code change (per repository convention already followed in this session's
   prior work: commit-before-implement, no destructive git operations).
2. **Phase 1 — Read-only aggregations.** Add `Permissions.GetAuthorizedOfficers()`,
   the Pre-Dibs summary helper, and the per-rank rollup over
   `RankRules.GetAllocationReconciliation`. No UI yet. Unit-testable in
   isolation.
3. **Phase 2 — Wizard shell + status derivation.** Add the new module
   (step registry + derived overall state), no UI yet, test-covered against
   the six overall states using real fixtures (clean guild, existing guild,
   partial config, RC present/absent, etc.).
4. **Phase 3 — OfficerUI integration.** New nav entry, step-list rendering
   reusing existing patterns, each step embedding the already-existing
   projections/pages (Guild Setup, Setup Assistant panels, Sync projection,
   RC capability display) rather than re-rendering them from scratch where
   feasible.
5. **Phase 4 — Final Readiness Check wiring + Review step composition.**
6. **Phase 5 — Documentation.** GM/Officer guide section distinguishing
   Wizard (configures) vs. Setup Assistant (validates) vs. Diagnostics
   (troubleshoots), per the request's explicit documentation requirement.

---

## 11. Test Strategy (mapped to the 25 requested scenarios)

All tests should use the real `helpers.load_addon` loader against genuine
`Governance`/`LegacyBaseline`/`Seasons`/`RankRules`/`PreDibs`/`Permissions`
modules (no mocking), matching this repository's existing
`installation_wizard_spec.lua` convention.

| # | Scenario | Primary assertion |
|---|---|---|
| 1 | Completely new installation | Wizard state = `NEW_INSTALLATION`; every step shows `NOT CONFIGURED`/`ACTION REQUIRED` as appropriate |
| 2 | Existing healthy installation | Wizard state = `READY_FOR_RAID`; Step 8 shows `EXISTING — HEALTHY`, no destructive action offered |
| 3 | Partially configured installation | Wizard state = `PARTIALLY_CONFIGURED`; only the genuinely incomplete steps flagged |
| 4 | Existing ledger | Ledger step embeds `Installation.GetStatus()` unchanged; balances/history untouched after opening the Wizard |
| 5 | Existing Pre-Dibs | Pre-Dibs step shows existing request/history counts; no clear action available |
| 6 | Existing multi-raid/sync configuration | Sync step reflects live `BuildSynchronizationProjection()`; no mutation |
| 7 | RCLootCouncil installed | RC step shows `Detected: Yes`, capability snapshot matches `GetCapabilities()` |
| 8 | RCLootCouncil missing | RC step shows detected=false without blocking the rest of the Wizard (RC is optional, per project rules) |
| 9 | Missing rank configuration | Rank step shows `ACTION REQUIRED` for the specific rank(s) with no `RankRules` entry |
| 10 | Unauthorized player opens Wizard | Read-only/denied view, no write action reachable, matching `SetupAssistant`'s `DENIED`/`GUILD_ADMIN_REQUIRED` precedent |
| 11 | GM opens Wizard | Full read/write access to every step |
| 12 | Officer opens Wizard | Access matching existing `ADMIN_ACTIONS`/officer-permitted subset; GM-only actions correctly blocked |
| 13 | Configuration edited after previous READY state | Re-deriving `GetStatus()` reflects the edit immediately, no stale cached state |
| 14 | Readiness becomes BLOCKED after a configuration change | Final Readiness step (`SetupAssistant.Evaluate`) reflects the change without Wizard-side caching |
| 15 | Existing ledger is never reset | Assert `Ledger.GetAllTransactions()` count/content unchanged after opening/closing the Wizard on an existing guild |
| 16 | Existing history survives Wizard completion | Same assertion after a full Wizard "completion" pass |
| 17 | Direct navigation | Jumping to step N directly renders that step without forcing 1..N-1 |
| 18 | Back/Next behavior | Sequential navigation preserves already-entered per-step UI state |
| 19 | Resume configuration | Reopening the Wizard resumes at the last-viewed step (local UI state) but re-validates every step's status live |
| 20 | Combat lockdown | A write action attempted in combat is deferred/queued, not silently dropped or force-executed |
| 21 | Sync-behind condition | Sync step surfaces `SYNC_BEHIND` as a warning without blocking read-only steps |
| 22 | Migration-required installation | Ledger step shows `EXISTING — MIGRATION REQUIRED` (maps to `Installation.GetStatus().state == "RECONCILIATION_REQUIRED"`) and routes to the existing reconciliation UI, not a new one |
| 23 | Invalid SavedVariables state | Wizard surfaces the existing `Core.lua` quarantine/recovery diagnostics rather than attempting its own repair |
| 24 | Readiness Check reuse | Assert the Wizard's final step literally calls `Dibs.SetupAssistant.Evaluate` (or `Dibs.Readiness.Evaluate`) — no divergent computation |
| 25 | No duplicate readiness engine introduced | Static/code-review assertion: the new Wizard module contains no re-implementation of any `Readiness`/`SetupAssistant` probe logic |

---

## 12. Blockers

**None.** Every requested capability maps to an existing, already-validated
API or a small, clearly-scoped additive read-only helper. The only design
decision requiring explicit sign-off before implementation is the
**terminology re-scoping** in §1/§4 (Raid Configuration → Seasons; Guild
Ranks/Eligibility → RankRules, not CharacterEligibility) — implementing
literally against the request's raw wording without this correction would
risk inventing a parallel "Raid" entity that does not match the existing
domain model.

---

## Final Verdict

**READY FOR IMPLEMENTATION**
