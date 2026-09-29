# DIBS UI Design System Normalization Audit

**Target release:** 0.8.0 presentation hardening
**Phase:** Phase 1 audit closed; Batch 1 source implementation complete, Retail validation pending
**Verdict:** READY FOR RETAIL BATCH 1 RECHECK

## Scope and Guardrails

This audit inventories the primary Player and Officer/GM navigation routes, shared presentation primitives, related standalone windows, and visible help coverage. Phase 1 was a read-only source review. Batch 1 later made only the scoped shared-control, Officer History, and Automatic Dibs Status presentation changes documented below; no business behavior was intentionally changed. Existing worktree changes were preserved.

No presentation work in a later phase may change ledger semantics, synchronization, governance, permissions, coordinator behavior, RCLootCouncil authority, SavedVariables schema, request or Loot Rules semantics, Rank Rules, or reconciliation semantics. All normalizations must continue to use the existing protected service boundaries.

## Batch 1 Results

- Added the shared DIBS select and semantic `AttachHelp` primitive, retaining `AddTooltip` as a compatibility alias. `AddDibsSelect` now wraps the existing MSA dropdown control when available, avoiding a hidden AceGUI dropdown overlapping the visible control; its fallback preserves value/list APIs and both paths support help and release cleanup.
- Migrated Officer RCLootCouncil History results to `AddTablePage`, the shared pagination footer, and the shared fluid table. The initial search form stays in the route scroll frame with directly stacked controls; the shared results table is created after search, with an Edit Search action to return to filters. Its page size remains 40; wide, medium, compact, and narrow layouts keep candidate fields available through combined columns/tooltips and Review. The route has an explicit empty state and zero standalone `?` controls.
- Attached help to History inputs/actions and candidate column headers; migrated its season selector to `AddDibsSelect`.
- Migrated only Automatic Dibs' Status filter to `AddDibsSelect`. Its four keys, selection, filtering callback, paging reset, and table behavior are unchanged. Automatic Dibs search help remains outstanding.
- Dibs Administration needed no cleanup: it already uses the shared table-page, fluid-column, pagination, and row-action patterns, and its existing focused tests pass.
- Focused Lua tests passed for shared control ownership (14, including the MSA path), History reconciliation (12), and Automatic Dibs/Admin (22); Officer navigation lifecycle passed 27/27. The local runner is Lua 5.4; tests were invoked with `unpack=table.unpack` for the project's Lua 5.1 compatibility.
- Full suite: 794 passed, 1 failed across 144 files. The remaining failure is the unrelated Pre-Dib recovery heartbeat test (`expected 1, got 2`), reproduced in isolation; Encounter Journal tests pass 8/8 in isolation. No Sync/Pre-Dib source was changed.
- Documentation validation passed (27 concepts, 0 errors, 0 missing locale entries); 8 pre-existing orphaned Sync help keys remain warnings. Generated-doc `-Check` passed; PowerShell 5.1/7 cross-version comparison matched all 8 artifacts; `git diff --check` passed.
- Retail visuals remain **PENDING** and are not represented as passed by source tests.

No ledger, reconciliation, permission, synchronization, sorting, filtering, or RCLootCouncil source-data behavior was changed intentionally. This is not a global normalization completion claim.

## Route Inventory

There are 28 declared primary navigation entries: four Player routes and 24 Officer routes. Officer entries are subject to role, module, and developer visibility rules. Classifications are exclusive: a reference route is not also counted as already compliant.

| Surface | Route | Classification | Audit note |
|---|---|---|---|
| Player | My Dibs | PARTIAL | Shared shell and table helper; summary, active requests, and submission form do not yet compose the complete shared page primitives. |
| Player | Requests | PARTIAL | Shared shell and table, but no table-page footer and several request fields/columns lack attached contextual help. |
| Player | History | PARTIAL | Shared table and detail workflow; no shared table-page pagination, and visible columns lack contextual tooltips. |
| Player | Diagnostics | PARTIAL | Uses the table-page layout, but the channel matrix has no per-column help and channel inputs lack attached tooltips. |
| Officer | Dashboard | REFERENCE | Status-summary hierarchy and concise operational actions; reference pattern for summaries. |
| Officer | Guided Setup | REFERENCE | Ordered workflow with explanatory copy and primary actions; reference pattern for guided setup. |
| Officer | Raid Readiness | PARTIAL | Status/dashboard surface, but still needs a complete shared status-card/section composition. |
| Officer | Automatic Dibs | REFERENCE | Dense roster workflow using fluid columns, bounded rows, search/filtering, pagination, and explicit empty state. |
| Officer | Dibs Administration | REFERENCE | Roster-grid reference with shared table page, fluid geometry, pagination, empty/loading states, and row actions. |
| Officer | History | PARTIAL | Batch 1 now uses the shared table page, fixed 40-row pager, responsive columns, direct help, and explicit empty state; Retail validation remains pending. |
| Officer | Requests | PARTIAL | Dedicated review workflow and shared table primitives; custom detail and advanced-action sections remain page-specific. |
| Officer | Pre-Dib Requests | PARTIAL | Shared paged list path, but some header/empty/help presentation is inherited from a generic log projection. |
| Officer | Pending Awards | PARTIAL | Shared table page and pagination; confirmation is a high-risk row action requiring focused interaction validation. |
| Officer | Vault Review | PARTIAL | Reuses shared list infrastructure, with a separate record/decision/reason form and missing field-level help. |
| Officer | Seasons | PARTIAL | Uses shared tables and option rendering, but does not yet consistently use the complete table-page pattern. |
| Officer | Rank Rules | PARTIAL | Custom rule editor with tooltips; layout and field composition remain specialized. |
| Officer | Loot Rules | PARTIAL | Shared sections and controls, but rule-family presentation is custom and should be normalized without changing policy behavior. |
| Officer | Announcements | PARTIAL | Canonical option rendering plus custom channel controls and inline explanations. |
| Officer | Loot Eligibility | PARTIAL | Shared tables and sections, but custom select/edit controls need contextual help and consistent field composition. |
| Officer | RCLootCouncil | PARTIAL | Canonical integration options render through AceGUI, alongside a separate reconciliation workflow and history-specific help controls. |
| Officer | Settings | PARTIAL | Canonical options use the shared renderer; native Blizzard Settings remains a second presentation host. |
| Officer | Pre-Dibs Settings | PARTIAL | Canonical options use the shared renderer; fields and controls are not uniformly described at the control itself. |
| Officer | Modules | PARTIAL | Custom draft/authorization workflow in the shared shell; preserve its existing authorization and save boundary. |
| Officer | Guild Configuration | PARTIAL | Explicit setup/reconciliation workflow with shared headings and buttons; several row summaries remain custom. |
| Officer | Synchronization | PARTIAL | Strong table-page implementation with roster scope, search, pagination, and empty states; selector/search help attachment is incomplete. |
| Officer | Diagnostics | PARTIAL | Uses shared sections/status badges and selectable reports; technical content is still composed as bespoke labels. |
| Officer | Developer | PARTIAL | Role-gated sandbox workflow in the shared shell; specialized status and sandbox presentation. |
| Officer | Debug | PARTIAL | Canonical options are rendered in the shell; detailed logs open in a separate window. |

**Primary route classification totals:** 28 total; 4 REFERENCE; 0 ALREADY_COMPLIANT; 24 PARTIAL; 0 LEGACY; 0 NEEDS_MIGRATION.

The Player UI also contains an alternate BasicFrameTemplate fallback used only when AceGUI is unavailable. Treat that fallback presentation as one additional **NEEDS_MIGRATION** implementation surface, not as a separate navigation route. `createLegacyAceWindow` is an unreferenced legacy helper and is not counted as a reachable route. The standalone Data, Debug Logs, and Logs windows are adjacent surfaces, not entries in the 28-route primary navigation count.

## Existing Primitive Inventory

The principal shared implementations are in [src/ui/AceGUI.lua](../../src/ui/AceGUI.lua) and [src/ui/Midnight.lua](../../src/ui/Midnight.lua).

| Primitive | Current state |
|---|---|
| Section | `AddSection` exists; adoption is mixed with raw InlineGroup/SimpleGroup construction. |
| Status card | Status badges and sections exist separately; no single reusable status-card composition. |
| Toolbar | Inline groups are used as toolbars; no named toolbar primitive. |
| Data grid | `AddTable`, fluid-column allocation, `AddTablePage`, and row actions exist; table and page composition are still called separately. |
| Select | `AddDibsSelect` wraps the existing visible MSA dropdown when available and has an AceGUI fallback; `AddDropdown` remains for unmigrated routes and configuration widgets. |
| Field | `AddFormRow` exists; several pages still place labels and controls independently. |
| Search field | `AddSearch` and `AddEditBox` exist; route pages often build search controls ad hoc. |
| Pagination | `AddPaginationFooter` and page-slice helpers exist; some routes still implement local Previous/Next controls. |
| Dialog | `Midnight.AddModal` wraps the shared window helper; some workflows construct windows directly. |
| Empty state | `Midnight.AddEmptyState` exists; table callers often pass `emptyText` directly instead. |
| Status badge | `Midnight.AddStatusBadge` exists and applies semantic status presentation. |
| Contextual tooltip | `AttachHelp` is the semantic attachment API; `AddTooltip` remains an alias. Table-column/cell hooks remain available. |

The requested `Dibs*` component names should be implemented as small shared compositions over these existing helpers, not as a second widget framework. Keep the established shell, tokens, layout, and context-menu ownership.

## Legacy and Shared-Control Counts

Counts below are literal source callsites in `src/ui` and `src/integrations`, excluding helper definitions in `AceGUI.lua`; they are not runtime widget-instance counts.

- `AddDropdown`: 33 callsites outside the shared adapter (35 before Batch 1). These use the shared adapter, which selects MSA when available and otherwise uses AceGUI Dropdown; they are not independent dropdown implementations. The new `AddDibsSelect` currently has 2 Officer route callsites.
- Direct `AddMSADropdown`: 1 callsite in DataUI's `addChoice` helper, with a shared `AddDropdown` fallback.
- `AddScrollableList`: 8 callsites outside `AceGUI.lua` (9 before Batch 1), used as independent scroll containers rather than the complete table-page contract.
- `AddTable`: 26 direct callsites; `AddTablePage`: 8 callsites (7 before Batch 1); `AddPaginationFooter`: 7 callsites (6 before Batch 1). The History route now uses the shared page and pager; other list routes remain candidates.
- `AddTabs`: 4 callsites. One is inside the unreachable legacy Player helper; standalone log windows also use tabs.
- AceConfig option declarations in `RCLootCouncilOptions.lua`: 42 controls in total: 11 select, 2 multiselect, 4 toggle, 13 input, and 12 range. The Officer shell renders these through `RenderOptionsGroup`; Blizzard Settings remains a separate host for the same options.
- Direct `AddScrollingTable` outside the shared adapter: 0 callsites. Table rendering is centralized behind `AddTable`/`AddScrollingTable`.

## Help and Tooltip Audit

The active RCLootCouncil History page had **9 standalone `?` help buttons before Batch 1 and has 0 now**. Help is attached to its controls, section/route headings, and result columns. The generic `AddHelpButton` helper remains for compatibility but has no production UI callsites. The `?` token used as a semantic status marker is not a help control and is excluded.

At least **17 active Player grid columns** have no column tooltip:

- Requests: 4 columns.
- History: 5 columns.
- Diagnostics channel matrix: 8 columns, including Player and seven channel columns.

Other confirmed controls without attached contextual help include the Player Diagnostics channel selector and conditional target/channel-name fields; the Officer Synchronization roster selector and search; Automatic Dibs search (the Status filter now has attached help); Vault Review record/decision/reason controls; and Loot Eligibility difficulty/outcome/threshold controls. Some have nearby explanatory text, but the explanation is not attached to the relevant control. Canonical AceConfig fields inherit descriptions only where their option has a useful `desc`.

## Remaining Normalization Work

1. Keep the remaining 24 PARTIAL primary routes and the Player BasicFrameTemplate fallback in scope for separately authorized batches; the current 28-route inventory is not globally normalized.
2. Continue with Player History/Requests, Officer Requests, Pending Awards, Vault Review, Seasons, Synchronization, Settings, Modules, Guild Configuration, Diagnostics, and other identified surfaces only in their own authorized batches.
3. Preserve the explicit Batch 1 exclusions: Seasons, Requests, Pending Awards, Vault Review, Synchronization, Settings, Modules, Guild Configuration, and Diagnostics were not migrated here. Validate destructive or permission-sensitive workflows in their own focused batches.

## Risks and Validation Gates

- The same canonical AceConfig options have two hosts (Blizzard Settings and the Officer window); a shell-only fix must not silently alter option callbacks or policy behavior.
- The MSA dropdown backend and AceGUI fallback have different widget lifecycles; keep selection state and tooltip behavior consistent across both.
- Officer/GM visibility, module gating, and Developer Mode affect which routes and actions are available. Presentation selectors must not change these rules.
- Row actions and confirmation workflows can affect ledger or protected state. Keep route normalization separate from service semantics and validate dangerous actions through existing permission/protected boundaries.
- Existing user worktree changes in `src/libs/lib-st/Core.lua`, both locale files, `src/ui/AceGUI.lua`, `src/ui/OfficerUI.lua`, and integration tests were preserved. Batch 1 changes are limited to the documented shared primitives, History, Automatic Dibs Status, tests, and this report.
- Retail visual/layout behavior has not been verified in-game. Recheck Automatic Dibs Status and Officer History target-season selects, table/help tooltips, empty state, and 40-row Previous/Next paging at content widths near 1000 (wide), 700 (medium), and 450 (narrow). Exercise route switching, menu open/close/selection, resizing across layout thresholds, and cleanup; reopen Dibs Administration at those widths as a regression check. Retail status remains **PENDING**.

**Audit disposition:** Phase 1 inventory remains valid. Batch 1 source changes and focused tests are complete; one unrelated Pre-Dib recovery test still fails in the full suite, and the listed Retail matrix is pending. Other routes and controls remain out of scope. **READY FOR RETAIL BATCH 1 RECHECK.**