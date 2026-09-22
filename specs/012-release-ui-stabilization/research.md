# B12 Research Decisions

## Scope and Authority

B12 is a stabilization and presentation increment over the B11 implementation. The existing Dibs-owned UI controllers remain responsible for route selection, projection, and user interaction. Domain services remain responsible for request, Pre-Dib, ledger, permission, readiness, backup, and profile semantics. `src/modules/ProtectedActions.lua` remains the only authoritative mutation boundary for dangerous or historical actions.

The implementation must preserve the following B11 decisions:

- `WindowState.lua` owns Player and Officer window positions separately and restores each position once at registration.
- `AceGUI.lua` owns shared widgets, tables, dropdowns, context menus, refresh coalescing, and pooled-widget cleanup.
- `OfficerUI.lua` owns Officer navigation and page projections, including route alias normalization and one active page/content host.
- `PlayerUI.lua` owns player-scoped presentation and delegates request actions to existing services.
- `LogsUI.lua` owns the UI-facing history reconciliation workflow and delegates every decision to `RCLootCouncil` and protected actions.

B12 must not introduce a second UI framework, a second context-menu implementation, a new mutation owner, or a parallel persistence model.

## Requests / Dibs Support Tickets

The support-ticket language is a presentation projection over existing request records. Categories such as balance, award, history, eligibility, or other operator-facing groupings are derived labels only. They are not new persisted request fields, synchronization fields, permission fields, or ledger semantics.

Statuses use the existing request states and their established meanings. B12 may improve labels, explanations, next-action text, and evidence grouping, but it may not add a ticket lifecycle, invent a state transition, or bypass the existing Disputes service. The category and status projection must remain safe when older or partially populated records are displayed.

Primary applicable actions stay visible in the page: ask for information, resolve, and reject. Corrections, refunds, revokes, imports, and other high-impact operations remain separately disclosed and continue through authorization, readiness, reason, confirmation, and protected delegation as applicable.

## Historical DIB Transfer

Historical transfer remains a preview-first reconciliation workflow over the existing RCLootCouncil adapter. Search is read-only and bounded. Review exposes the concise item, winner, difficulty, encounter, date, duplicate, and evidence summary before technical details. Confirmation and rejection delegate to the existing reconciliation and protected-action paths.

The existing rules remain normative: exact alias filtering, bounded date/history scanning, stable identity, duplicate detection, stale checks, idempotent confirmation, unknown-field labeling, and Officer/GM privacy. Dibs must not rewrite RCLootCouncil history or treat an incomplete external record as verified without the existing evidence rules.

## Shared Midnight Shell and Interaction

The B12 design rules define one dark translucent Midnight shell with left navigation, one primary content host, and a stable footer. Shared tables, dropdowns, tooltips, and context menus remain in `AceGUI.lua`. Left-click is the primary selection/detail action; right-click opens the shared object-aware menu. Critical primary actions remain visible, menus close when their page or window closes, and status meaning must not depend on color alone.

No page-specific theme, animation, gradient, elaborate nested card system, or competing layout framework is justified by B12.

## Sandbox Boundary

Developer sandbox state remains isolated through separate provider/store boundaries and cannot grant production authority. `SANDBOX_STORE_TOO_LARGE` may be addressed only through bounded validated behavior. If the limitation remains, it may be documented as developer-only when Developer Mode is hidden or off by default, production storage is isolated, and normal users are unaffected. B12 must not silently enlarge storage limits or weaken fail-closed mixed-provider behavior.

## Validation Decision

Automated validation uses focused UI, lifecycle, navigation, projection, authority, and reconciliation suites followed by the explicit full Fengari suite. The known unrelated baseline failure at `tests/integration/rclootcouncil_buttons_spec.lua:155` must remain separately recorded if present.

Real Retail validation is mandatory before release readiness. The default matrix is single-client because B12 is not expected to change cross-client behavior. Two-client validation is added only when implementation changes synchronization, cross-client state propagation, or another cross-client contract.

Validation must cover RCLootCouncil absent, late-loaded, degraded, operational, and unsupported states; combat deferral; repeated open/close and route transitions; narrow and wide windows; Player/Officer privacy; context-menu cleanup; and bounded sandbox behavior.

## Release Evidence

A release candidate requires an explicit version bump in `src/RCLootCouncil_dibs.toc` and its source version owner, a dated `CHANGELOG.md` entry, updated affected operator/player documentation, automated test output, diagnostics, whitespace validation, and documented Retail evidence. B12 evidence artifacts record implementation progress but do not claim release readiness or Retail certification before the real-client matrix is complete.
