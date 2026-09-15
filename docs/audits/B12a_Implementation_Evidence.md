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

## Adventure Guide metadata/default remediation

- Adventure Guide catalog projection now fails closed when raid or encounter identity is missing, non-positive, or unnamed.
- Synthetic `Current raid`, `Current boss`, and encounter ID `0` fallback rows were removed; item keys require a positive real encounter ID.
- Correction filters default to real catalog metadata only. The initial season default is resolved from an explicit game/Adventure Guide season API when available; the guild Dibs season is not used.
- Developer Debug diagnostics expose bounded expansion, game-season, raid, encounter, eligible-item, current-context, and selected-filter counts without adding metadata controls to the normal Officer workflow.
- Focused selector validation: 5 passed, 0 failed. Adjacent navigation, B12a ownership/stabilization, and dispute regressions: 44 passed, 0 failed.

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

The manual screenshot also showed the `Officer pre-dib announce channel`
control at the bottom of the Requests page after leaving Pre-Dibs. Requests
does not render the Pre-Dibs option group; the symptom was a native AceGUI
descendant frame remaining visible after the old page had been removed from the
widget tree. Cleanup now snapshots the full descendant widget set before
recursive release, then hides and detaches every owned native frame afterward.
The navigation regression explicitly verifies that the Pre-Dibs announcement
label is absent after switching to Requests.

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
64 passed, 0 failed (5 files)
```

B11 UI ownership, navigation, Midnight, and lifecycle regressions:

```text
22 passed, 0 failed (3 files)
```

The latest combined route, ownership, options, and eligibility validation is
green at `64 passed, 0 failed (5 files)`. The final focused lifecycle slice
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

## Correction dropdown placeholder remediation

The Officer correction workflow now treats the player and Adventure Guide item
placeholders as display-only text. Neither placeholder is inserted into the
choice map, and both controls start with a `nil` canonical value instead of a
first roster/catalog result. A valid selected player keeps its full Name-Realm
identity; a valid item keeps its existing catalog key and item ID/link identity.

Search refreshes rebuild the native MSA key list and retain a selection only
while it remains present in the refreshed roster/catalog. Otherwise the value
returns to `nil` and the display returns to the placeholder. Apply remains
disabled by the existing confirmation/reason gates and has an additional
fail-safe that refuses to resolve without a real replacement. Current evidence
and targets are unchanged until the explicit correction action is applied.

Focused selector validation:

```text
3 passed, 0 failed (1 file)
```

Coverage includes both placeholder labels, menu exclusion, initial `nil`
values, explicit player/item selection, selection persistence across refresh,
fail-safe Apply behavior, and preservation of current evidence. No correction
service or `ProtectedActions` semantics were changed.

## Correction item candidate projection

The Officer `Correct item` dropdown now projects candidates in this order:
relevant Adventure Guide raid scope, safe Dibs semantic classification, and
the effective RCLootCouncil Dibs type rule. The existing classifier and
`IsItemDibTypeAllowed(..., { strictWhitelist = true })` service remain the
authorities; the UI does not duplicate loot eligibility semantics.

When a request has a safe raid or encounter context it is preferred; otherwise
the active Adventure Guide raid is the default scope. Search is applied only
after projection and matches item name, item ID, or boss name. Unknown or
blocked items therefore remain hidden even for an exact ID search. Rows use
human-readable `Item Name — Boss Name` labels, never raw classifier output.
The first row is not selected, canonical item keys remain intact, and an
empty safe projection displays `No eligible raid items found.`

Focused candidate validation:

```text
4 passed, 0 failed (1 file)
```

Coverage includes raid scoping, allowed and blocked families, unknown
classification, name/ID search fail-closed behavior, non-selection of the
first result, human-readable labels, canonical item identity, unchanged
current evidence, and the intentional empty state. Protected correction
authority remains in the existing `Disputes` and `ProtectedActions` path.

## Cascading Adventure Guide filters

The correction item selector now presents compact Expansion, Season, Raid, and
Boss controls above the item dropdown. Canonical IDs are stored separately
from labels. Expansion defaults to the current Retail expansion only on the
initial open when that expansion is represented in the local Adventure Guide
data; the active season is selected only when its canonical local ID is
explicitly present. Otherwise the selector safely uses All expansions or All
seasons with the season control disabled when no expansion/season metadata is
available.

Each downstream list is rebuilt from the current upstream scope. Valid values
and selected items are preserved across changes; invalid season, raid, boss,
or item values are cleared without selecting a replacement. Raid and boss are
never auto-selected, and the item value remains `nil` until an explicit item
selection. Search matches item name, item ID, boss/encounter name and ID, raid
name, and known expansion name after all scope and eligibility filters have
already been applied.

Focused cascading selector validation:

```text
5 passed, 0 failed (1 file)
```

The regression covers all-expansion and expansion-scoped raid lists, seasonal
and raid/boss narrowing, all requested search fields, human-readable context
labels, canonical IDs, no first-result selection, fail-closed eligibility,
placeholder isolation, and invalid downstream reset behavior.
