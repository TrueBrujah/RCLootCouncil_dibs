# Implementation Plan: B12 Release UI Stabilization

**Branch**: `012-release-ui-stabilization` | **Date**: 2026-09-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/012-release-ui-stabilization/spec.md`

**Status**: Implementation evidence is recorded; real Retail validation and release publication are not complete.

## Summary

B12 prepares the existing RCLootCouncil_Dibs UI for a publishable Retail release by stabilizing the B11 runtime ownership model, repairing only demonstrated page defects, making Requests and historical DIB transfer easier to review, and producing repeatable release evidence. The implementation remains a bounded presentation and workflow increment over the existing Dibs-owned controllers, normalized integration adapters, and protected service boundaries.

The central approach is projection-first: `PlayerUI.lua`, `OfficerUI.lua`, `LogsUI.lua`, and shared `AceGUI.lua` behavior present existing domain state; `ProtectedActions.lua`, `Disputes.lua`, `PreDibs.lua`, `Ledger.lua`, and the RCLootCouncil reconciliation services remain authoritative. B12c categories are labels over existing request semantics, B12c statuses are existing request states, and B12d remains a review/confirmation projection over existing RCLootCouncil history evidence. No new authority, protocol, ledger, or request lifecycle is introduced.

## Technical Context

**Language/Version**: Lua 5.1-compatible World of Warcraft Retail addon runtime.

**Primary Dependencies**: WoW Retail UI APIs; embedded AceAddon/AceEvent/AceTimer/AceGUI/AceConfig services; MSA-DropDownMenu-1.0; lib-st; LibWindow-1.1; optional RCLootCouncil capability/history surfaces; existing Dibs modules and deterministic Fengari test doubles.

**Storage**: Existing versioned Dibs SavedVariables and local presentation/window-position state. B12c presentation categories are not persisted request fields. B12 does not add a new authoritative store or synchronization payload. Any implementation-time metadata change requires the existing migration, changelog, and version gates.

**Testing**: Explicit Fengari runs through `tests/run.lua` with `DIBS_TEST_FILES`, focused unit/contract/integration UI and workflow suites, workspace diagnostics, `git diff --check`, and manual single-client Retail validation. Two-client validation is conditional on a change to cross-client behavior; it is not a default B12 requirement.

**Target Platform**: World of Warcraft Retail, standalone and with optional RCLootCouncil absent, late-loaded, operational, degraded, or unsupported.

**Project Type**: Single modular WoW addon with Dibs-owned UI controllers, domain services, protected application actions, optional integration adapters, and deterministic test doubles.

**Performance Goals**: Keep page projections bounded for normal guild and history sizes; retain coalesced refreshes, bounded history paging, stable table geometry, and pooled widget cleanup. Do not introduce unbounded timers, retained page trees, diagnostic history, or full-window rebuilds for every invalidation.

**Constraints**: Preserve all B00-B11 business, security, authority, synchronization, RCLootCouncil, combat-safety, and sandbox semantics. Do not modify Blizzard or RCLootCouncil source, add protected automation, write authoritative state from UI code, or solve `SANDBOX_STORE_TOO_LARGE` by blindly increasing limits. Keep the shared Midnight shell and one context-menu implementation. Release candidates require an explicit addon version bump and dated changelog alignment.

**Scale/Scope**: Player and Officer windows, all currently exposed routes, bounded guild request/review lists, existing RCLootCouncil history reconciliation, local sandbox diagnostics, and the documented Retail release matrix.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **WoW API and combat safety**: PASS. B12 keeps frame creation, visibility, movement, refresh, and protected controls behind the existing combat deferral/readiness paths.
- **Authority and trust**: PASS. Existing verified GM/Officer checks and protected actions remain authoritative; UI projections and sandbox roles cannot grant production authority.
- **Ledger and Dibs semantics**: PASS. Requests, balances, awards, corrections, and history retain existing lifecycle and append-only behavior; no UI path writes the ledger directly.
- **RCLootCouncil ownership**: PASS. RCLootCouncil history, candidates, votes, sessions, and awards remain read-only to Dibs except for documented Dibs-owned projections.
- **Persistence and synchronization**: PASS. B12c categories are presentation-only and no new SyncV2 or production SavedVariables contract is planned.
- **Privacy and release traceability**: PASS. Player/Officer scopes remain enforced and release work requires documented automated/Retail evidence, changelog, and version data.

No constitution violation is identified. Planning may proceed.

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
|- Core.lua                              # composition, lifecycle, slash/version state
|- Types.lua                             # shared type vocabulary
|- modules/
|  |- ProtectedActions.lua               # authorization and mutation boundary
|  |- Disputes.lua                       # existing request/report lifecycle
|  |- PreDibs.lua                        # existing Pre-Dib lifecycle
|  |- Ledger.lua                         # append-only accounting authority
|  |- Permissions.lua                    # verified production roles
|  `- Readiness.lua                      # combat/readiness gate
|- integrations/
|  |- RCLootCouncil.lua                  # normalized history/evidence adapter
|  `- RCLootCouncilOptions.lua            # options projection and enum normalization
`- ui/
   |- AceGUI.lua                         # shared shell, tables, menus, refresh, cleanup
   |- WindowState.lua                    # local Player/Officer position ownership
   |- PlayerUI.lua                       # player projections and request actions
   |- OfficerUI.lua                      # Officer routes, requests, admin projections
   `- LogsUI.lua                          # history/reconciliation workflow projection

tests/
|- helpers/                              # loader, WoW/Ace/RCLootCouncil doubles
|- contract/                             # authority, navigation, privacy, UI contracts
|- integration/                          # workflow and Retail-shaped UI regressions
`- unit/                                 # projections, normalization, lifecycle helpers

docs/
|- developer/b12-ui-design-rules.md      # normative B12 presentation contract
`- audits/                               # B11 and later Retail evidence records
```

**Structure Decision**: Extend the existing single-addon modular layout. B12 implementation changes stay at the current UI/controller, integration projection, and focused test boundaries. Existing domain services and `ProtectedActions.lua` remain the owners of mutations. New design artifacts are documentation only; `tasks.md` is intentionally left for the separate `$speckit-tasks` phase.

## Phase 0: Research and Boundary Contracts

Record the decisions in [research.md](research.md), define the UI/projection entities in [data-model.md](data-model.md), and specify the shared ownership and release gates in [contracts/release-ui.md](contracts/release-ui.md). Phase 0 must resolve:

1. Which B11 runtime ownership regressions require focused coverage before any page cleanup.
2. Which pages have a demonstrated Retail defect and can be repaired without a rewrite.
3. How request categories and statuses project onto existing request records without new persisted fields or lifecycle states.
4. How historical review delegates to the existing reconciliation service and protected confirmation/rejection path.
5. How the sandbox size limitation is bounded, tested, and documented if it remains.
6. Which automated and single-client Retail evidence is required before a release candidate.

## Phase 1: Design Outputs

- [research.md](research.md): architectural, workflow, sandbox, and release decisions.
- [data-model.md](data-model.md): UI-only projections and bounded release records, with explicit non-ownership of authoritative state.
- [contracts/release-ui.md](contracts/release-ui.md): shell, lifecycle, menu, request, history, authorization, combat, and validation boundaries.
- [quickstart.md](quickstart.md): focused and full Fengari commands, known baseline handling, Retail matrix, and release-candidate evidence checklist.

## Delivery Phases

### Phase 2: B12a Runtime UI Stabilization

Preserve and extend the B11 ownership corrections: one active page/content host, recursive pooled-widget cleanup, Player/Officer isolation, separate WindowState records, one title owner, canonical option-value normalization, safe tooltips, and shared context-menu cleanup. Add only focused regressions for any remaining observed lifecycle or Retail failure.

### Phase 3: B12b Targeted Page Cleanup

Use the existing Midnight shell to repair only pages identified by evidence, prioritizing Pre-Dibs, Settings, Loot Eligibility, Debug, and RCLootCouncil surfaces. Keep information tables bounded and readable, keep primary actions visible, move only secondary actions to the shared context menu, and preserve current service callbacks and permission checks.

### Phase 4: B12c Requests / Dibs Support Tickets

Project existing request records into plain-language category, status, next-action, and evidence views. Reuse the current request state machine and Disputes service. Keep `Ask for information`, `Resolve`, and `Reject` as visible applicable primary actions; keep corrections, refunds, revokes, and imports separately disclosed and confirmation-gated. Do not add persisted category fields, ticket states, sync data, or direct ledger writes.

### Phase 5: B12d Historical DIB Transfer

Refine the existing Search -> Review -> Confirm/Reject -> Complete projection in `LogsUI` and `RCLootCouncil.lua`. Show concise item/winner/difficulty/encounter/date/evidence first, keep technical evidence expandable, and retain bounded paging, exact alias matching, unknown-field labeling, stale checks, idempotency, and Officer-only privacy. All decisions delegate to existing reconciliation and protected services; RCLootCouncil history remains untouched.

### Phase 6: B12e Release Hardening

Run focused UI/workflow regressions, the explicit full Fengari suite, diagnostics, and whitespace checks. Exercise absent/degraded/late RCLootCouncil, combat deferral, narrow and wide layout, repeated open/close and route transitions, authorization/privacy, and bounded sandbox behavior. Record any unrelated baseline failure separately and do not weaken it. Use single-client Retail validation as the default; add two-client checks only when B12 changes cross-client behavior.

### Phase 7: B12f Release Candidate and Publication

Align the explicit addon version in `src/RCLootCouncil_dibs.toc` and its source version owner, add a dated `CHANGELOG.md` entry, update affected player/Officer/operator guidance, record Retail evidence and known limitations, and verify the package from the resulting release-candidate state. Do not label the candidate Retail-certified until the real-client matrix is complete.

## Complexity Tracking

No constitution violations or complexity exceptions are required. B12 reuses the existing single-addon structure, Midnight shell, context-menu adapter, request service, history adapter, protected actions, and test harness. The only planned release metadata change is the explicit version/changelog alignment required by the constitution and B12f.

## Post-Design Constitution Re-check

- **Authority and accounting**: PASS. Request and history controls remain projections over existing protected services; no new mutation boundary or accounting source is created.
- **RCLootCouncil and synchronization**: PASS. History and live loot state remain owned by RCLootCouncil, and B12 adds no cross-client payload or synchronization semantics.
- **Combat, privacy, and sandbox safety**: PASS. Existing deferral, role scopes, provider isolation, and bounded-store behavior remain required by the contract and quickstart.
- **Release quality**: PASS. Phase 6 and Phase 7 require focused tests, full regression accounting, real Retail evidence, a dated changelog entry, and an explicit version bump.

The implementation evidence is recorded in the B12 audit artifacts, but this plan
does not claim Retail validation or release publication. The candidate remains
blocked until the real-client matrix and every required release gate are complete.
