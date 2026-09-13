# Implementation Plan: Midnight UI and Safe Developer Sandbox

**Branch**: `011-midnight-ui-developer-sandbox` | **Date**: 2026-09-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/011-midnight-ui-developer-sandbox/spec.md`

## Summary

Deliver a Dibs-owned Midnight UI foundation and an explicitly entered, provider-isolated
developer sandbox. Reuse existing AceGUI controllers, AceConfig projection,
MSA-DropDownMenu, LibSharedMedia, and LibWindow boundaries. Add local presentation
adapters and a versioned developer store without changing production ledger, permissions,
governance, coordinator, SyncV2, RCLootCouncil evidence, or combat-safety semantics.

## Technical Context

**Language/Version**: Lua 5.1-compatible World of Warcraft Retail addon runtime.

**Primary Dependencies**: WoW Retail API; AceAddon-3.0, AceConfig-3.0, AceGUI-3.0,
AceEvent-3.0, AceHook-3.0, LibSharedMedia-3.0, LibWindow-1.1,
MSA-DropDownMenu-1.0, LibDialog-1.0, and optional external UI presentation probes.

**Storage**: Existing versioned `RCLootCouncil_dibsDB` for production; separate,
versioned developer root such as `RCLootCouncilDibsDevDB` for sandbox data; local
presentation profile and window-position state only.

**Testing**: Fengari Lua harness through `tests/run.lua`, focused unit/contract/integration
fixtures, static `git diff --check`, and manual one/two-client Retail validation.

**Target Platform**: World of Warcraft Retail client, standalone and with optional
RCLootCouncil or external UI environments absent, late-loaded, degraded, or unsupported.

**Project Type**: Single modular World of Warcraft addon with Dibs-owned UI controllers,
optional integration adapters, and deterministic test doubles.

**Performance Goals**: Coalesce bursts of UI invalidations into one bounded refresh;
avoid full-screen rebuilds on every event; keep sandbox scenarios and list projections
bounded for normal guild and reconciliation sizes; avoid unbounded timers, buffers, or
addon traffic.

**Constraints**: No protected automation; no production authority from Developer Mode;
no sandbox-to-production write path; no production SavedVariables migration; no
RCLootCouncil source/history/candidate/vote writes; no SyncV2/governance/ledger changes;
combat-sensitive UI remains deferred through B08 readiness and post-combat paths.

**Scale/Scope**: Seven B11 batches across existing player, Officer/GM, request, eligibility,
history reconciliation, and diagnostic windows; guild-scale data with bounded tables and
local sandbox scenarios.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **WoW API and combat safety**: PASS. UI creation, movement, visibility, refresh, and
  protected controls preserve existing B08 deferral and readiness checks.
- **Authority and trust**: PASS. Production GM/Officer authority remains verified by
  existing services; sandbox roles are provider-scoped and cannot authorize production.
- **Ledger and Dibs semantics**: PASS. B11 reads/projections only; no balance, season,
  allocation, transaction, or award-cost semantics change.
- **RCLootCouncil ownership**: PASS. RC remains optional and owns history, candidates,
  votes, sessions, and awards; B11 consumes normalized state only.
- **Persistence and synchronization**: PASS. Production SavedVariables and SyncV2 remain
  unchanged; sandbox and presentation data are local, separate, versioned, and unsynced.
- **Privacy and public repository quality**: PASS. Player/officer scopes remain enforced;
  no private identifiers or logs are added to planning artifacts.

No constitution violations are identified. Planning may proceed.

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file ($speckit-plan command output)
├── research.md          # Phase 0 output ($speckit-plan command)
├── data-model.md        # Phase 1 output ($speckit-plan command)
├── quickstart.md        # Phase 1 output ($speckit-plan command)
├── contracts/           # Phase 1 output ($speckit-plan command)
└── tasks.md             # Phase 2 output ($speckit-tasks command - NOT created by $speckit-plan)
```

### Source Code (repository root)
```text
src/
├── Core.lua                         composition, SavedVariables, slash routing
├── modules/
│   ├── ProtectedActions.lua          production mutation boundary
│   ├── Permissions.lua               verified production authority
│   ├── Readiness.lua                 combat/integration readiness
│   └── ...                           existing domain and distributed modules
├── integrations/
│   ├── DeveloperMode.lua             local developer gate and commands
│   ├── RCLootCouncil.lua             normalized capability/history state
│   ├── RCLootCouncilOptions.lua      simple options projection
│   └── ...                           optional adapters/media
└── ui/
    ├── AceGUI.lua                    Dibs-owned component/window adapter
    ├── PlayerUI.lua                  player projections
    ├── OfficerUI.lua                 grouped dashboard/workflows
    ├── LogsUI.lua                    history/reconciliation projections
    ├── DataUI.lua                    data/persistence presentation
    └── ...                           diagnostics and shared Midnight components

tests/
├── unit/                            tokens, adapters, refresh, sandbox state
├── contract/                         provider, authority, combat, UI contracts
└── integration/                      sandbox isolation and workflow projections
```

**Structure Decision**: Extend the existing single-addon modular structure. New B11
services remain adjacent to the current DeveloperMode, UI, persistence, readiness, and
integration boundaries. Tests use the existing loader and deterministic doubles; no new
application or storage project is introduced.

## Delivery Phases

### Phase 0: Research and boundary contracts

Complete the decisions recorded in [research.md](research.md), document entity ownership
in [data-model.md](data-model.md), and treat [contracts/midnight-ui-sandbox.md](contracts/midnight-ui-sandbox.md)
as the provider, command, UI projection, reconciliation, and refresh boundary.

### Phase 1: Midnight foundation and local persistence

Add shared Midnight tokens/components, optional presentation probes, native media fallback,
LibWindow restoration, local presentation persistence, and dirty/coalesced refresh behavior.
Keep AceConfig simple and route complex views through Dibs-owned components.

### Phase 2: Provider-isolated sandbox

Add the separate versioned developer store, lifecycle state machine, provider selection,
clone/refresh/reset/exit operations, role/coordinator simulation, scenario fixtures,
fault injection, persistent warning, reload cleanup, and fail-closed mixed-provider guards.
Update DeveloperMode command routing without changing production permission services.

### Phase 3: Player and Officer/GM projections

Rework PlayerUI and OfficerUI information architecture around My Dibs, Requests, History,
Dashboard, grouped administrative workflows, normalized status summaries, privacy scopes,
and secondary context-menu actions. Preserve all existing mutation delegation.

### Phase 4: Request, eligibility, and reconciliation workflows

Apply progressive disclosure to requests/Pre-Dibs/eligibility. Project RCLootCouncil
history through Search -> Review -> Confirm/Reject -> Complete using existing protected
confirmation and immutable evidence contracts.

### Phase 5: Responsive/accessibility verification

Define supported dimensions, column/row sizing, tooltips, semantic states, high-contrast
Midnight adjustments, scroll ownership, long-content behavior, and combat deferral checks.
Run focused tests, full regression, and one/two-client Retail validation.

### Phase 6: Release traceability

Confirm no production migration or protocol change, update developer/operator documentation
as needed, record a dated changelog entry, increment addon version only at implementation
release, and retain the B00-B10 regression baseline.

## Complexity Tracking

No constitution violations or complexity exceptions are required. The separate sandbox
provider/store is a deliberate safety boundary, not a new application or authority
system; it prevents production/sandbox mixing and keeps all existing production services
unchanged.

## Post-Design Constitution Check

- **WoW API and combat safety**: PASS. The contract requires existing protected-frame
  deferral and does not introduce automation.
- **Authority and trust**: PASS. Simulated roles are valid only for sandbox projections;
  production protected actions reject simulated authority and mixed providers.
- **Ledger, governance, and synchronization**: PASS. No B11 contract writes ledger,
  governance, coordinator, recovery, or SyncV2 state.
- **RCLootCouncil ownership**: PASS. Reconciliation confirmation delegates to existing
  protected services and never writes RC history, candidates, votes, or sessions.
- **Persistence and privacy**: PASS. Production and developer roots are separate and
  versioned; local presentation state is not synchronized; role-scoped projections remain.
- **Release quality**: PASS. Quickstart includes automated, Retail, isolation, and
  regression gates; implementation will require documentation and changelog/version work.
