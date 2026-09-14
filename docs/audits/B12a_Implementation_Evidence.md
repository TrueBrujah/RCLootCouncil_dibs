# B12a Runtime UI Stabilization Evidence

## Scope and commits

- Branch: `dev`
- `B12A_START_COMMIT=b24798787892af490126e4f0ec9616fbf45da42d`
- `B12A_RESULT_COMMIT=HEAD (focused B12a result commit)`
- Scope: US1 runtime UI stabilization only. US2-US6, Requests redesign, Historical DIB Transfer redesign, general AceGUI/AceConfig rewrite, and B12f publication work were not started.
- Existing B11 V3 runtime ownership changes in `4193307` remain the production implementation for T013-T018; this B12a increment adds dedicated regression coverage and evidence without changing business authority, persistence, synchronization, or RCLootCouncil behavior.
- Unrelated worktree changes were preserved and excluded: `RCLootCouncil_dibs.code-workspace`, `docs/developer/README.md`, `tests/integration/officer_target_selector_spec.lua`, `docs/audits/B11_Retail_UI_003_Remediation_Evidence.md`, and `tests/integration/b11_retail_ui003_spec.lua`.

## US1 coverage

- T009: ten alternating Player/Officer open-close cycles, separate widget trees, one Officer page root, stale History cleanup, and nonblank repeated refreshes.
- T010: grouped TreeGroup callback normalization, programmatic `requests` alias routing, and canonical Pre-Dib values from visible labels.
- T011: separate Player/Officer position records, one-time restore, valid drag-save, off-screen recovery, and route-refresh isolation.
- T012: reusable context-menu replacement/close, tooltip argument ordering and item-link handling, raw-frame rejection, lib-st ownership/release, and combat refresh deferral.
- T013-T018: existing B11 V3 implementation verified by the focused regressions for permanent content ownership, recursive cleanup, window state, enum normalization, safe tooltip/table ownership, and callback/shell cleanup.

## Guild Rules / Seasons orphaned UI remediation

The manual blocker was reproduced by repeatedly switching through Seasons and
other Guild Rules routes, then reopening the Officer window. The stale content
was caused by routed page widgets and native lib-st/MSA controls outliving the
previous route during pooled AceGUI cleanup; the visible symptom was Seasons
content remaining after the route changed or reappeared after reopen.

The remediation keeps one permanent navigation TreeGroup, one content host, and
one tagged routed page root. `Adapter.Clear()` now uses native recursive
`ReleaseChildren()` ownership where available, explicitly releases native table
and dropdown state, and preserves pooled AceGUI frame ownership instead of
detaching arbitrary child frames. Fallback table rendering reuses an existing
page ScrollFrame, preventing nested page scrolling. The route regression now
repeats the full route sequence and asserts that the Seasons-owned page is
fully released outside Seasons; the ownership regression asserts exactly one
current routed header.

The Seasons Officer projection is a compact selectable list/detail workflow.
Loot Eligibility Customize now follows the same pattern: one category list,
one selected-category detail, and protected policy saves carrying the existing
`seasonId`, `family`, `difficultyScope`, `enforcementOutcome`, and
`completionThreshold` fields. No business authority or protected action
semantics were changed.

## Requests initial-mount remediation

The Retail blocker was isolated to route activation ownership. The addon
initializer creates a hidden default Officer frame on startup. The previous
opening path then relied on TreeGroup selection callbacks to mount the requested
page; that left a valid Requests selection capable of showing an empty content
surface when the selected value was already held by TreeGroup or when a control
initialization callback caused a refresh during the first render.

The initialization order is now explicit:

1. Create the AceGUI TreeGroup.
2. Assign grouped tree data and register `OnGroupSelected`.
3. Create `contentHost` and the routed page root.
4. Define the single `ActivateRoute(route, syncTree)` dispatcher.
5. Programmatically synchronize the TreeGroup selection with a recursion guard.
6. Clear and mount the requested page root directly.
7. Record `selectedRoute`, `mountedPage`, and the synchronized tree route.

Initial construction, public `CreateWindow(initialRoute)`, `SelectTab`, TreeGroup
clicks, and refreshes all use that dispatcher. The first render no longer relies
on an AceGUI callback side effect. Tree selection is synchronized only when the
route changes, and refresh requests emitted while controls initialize are
ignored until the page render completes. No delayed timers, artificial route
switches, second refreshes, layout workarounds, or business-logic changes were
introduced.

## Officer Pre-Dibs follow-up

The Officer `Pre-Dibs` route now renders the canonical `groups.preDibs` AceConfig
group instead of falling through to the read-only history table. The shared
AceGUI options renderer also now invokes setters with the standard AceConfig
`(info, value)` signature; previously the extra key argument caused Officer
controls to receive `nil` and silently leave options unchanged.

The contract regression opens Officer > Pre-Dibs, finds `Active season request
mode`, selects `Encounter`, and verifies the protected `predib.mode.set` action
receives canonical `ENCOUNTER`.

## Automated validation

Focused B12a suites:

```text
62 passed, 0 failed (5 files)
```

B11 UI ownership, navigation, Midnight, and lifecycle regressions:

```text
22 passed, 0 failed (3 files)
```

The latest combined route, ownership, options, and eligibility validation is
green at `62 passed, 0 failed (5 files)`. The final focused lifecycle slice
after the scroll ownership adjustment is `22 passed, 0 failed (3 files)`.

Requests initial-mount regression file:

```text
19 passed, 0 failed (1 file)
```

It covers direct Dashboard, Requests, and Pre-Dibs opens; selected-route and
mounted-page alignment; no second navigation requirement; Requests/Pre-Dibs
round trips; close/reopen; fresh-load Requests; duplicate-dispatch prevention;
and nonblank valid route roots.

Full explicit Fengari suite (all `tests/**/*_spec.lua` files):

```text
398 passed, 1 failed (90 files)
```

The sole full-suite failure is the known unrelated baseline:

```text
FAIL RCLootCouncil DIB response projection /
  renders the voting Dibs value from a normalized RCLootCouncil row identity
tests/integration/rclootcouncil_buttons_spec.lua:155: expected 2/2, got 1/1
```

The B12a suites and B11 UI regression slice are green. The plain `npx --yes fengari tests/run.lua` form cannot discover tests in this Windows Fengari environment, so the full result used the repository-supported `DIBS_TEST_FILES` selection path. New B12a test files report no workspace diagnostics, and `git diff --check` passes.

## Retail validation

Automated mocks cannot establish zero live Retail BugSack errors. Manual Retail validation remains required for ten open-close cycles, every exposed Player/Officer route, grouped navigation callbacks, drag and reopen behavior, context-menu replacement/close, tooltip variants, combat deferral, and confirmation that no stale page content remains.

`B12a automated validation complete; manual Retail validation required.`

`B12a REQUEST INITIAL MOUNT FIX READY FOR RETAIL RE-VALIDATION`
