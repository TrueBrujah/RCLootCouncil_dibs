# B11 Retail Navigation Remediation Evidence

- `Finding: B11-RETAIL-UI-001`
- `RETAIL_NAV2_START_COMMIT=e1acb31`
- `RETAIL_NAV_START_COMMIT=5b71516d8116963f185866b170e0a3a344611671`
- `RETAIL_NAV_FIX_COMMIT=65891832fc4e79d1bb024845a7bf3eb128d15805`
- Scope: Officer UI navigation lifecycle only. No ledger, permission, sandbox authority, SyncV2, request, policy, or RCLootCouncil business logic changes.

## Root Cause

The first remediation fixed content ownership but did not normalize the value emitted by the real AceGUI `TreeGroup` callback. The tree is hierarchical, so a click on History emits the unique value `section_dibs\001history`, not the leaf value `history`. The old route boundary treated that complete value as a route, rejected it as invisible, and replaced it with `overview`. The same path affected every grouped route. A separate alias also incorrectly mapped the visible `lootTypes` route to `integration`.

Manual Retail validation then exposed a second lifecycle defect after the route fix: the selected Debug route changed correctly, but the panel still displayed History/Reconciliation controls mixed with Debug controls. The reduced test double did not model the live AceGUI release pool closely enough. `Clear` depended on the active container's child-release shape, so old page roots and their nested descendants were not reliably released or hidden in the Retail runtime.

## Remediation

- Keep the AceGUI tree as navigation only.
- Mount one permanent `contentHost` beneath the navigation tree.
- Clear `contentHost` on every refresh and mount exactly one `pageRoot`.
- Render the active route exclusively inside that page root.
- Normalize the final segment of every AceGUI hierarchical `uniquevalue` once at the callback boundary.
- Use the same hierarchical value when selecting a route programmatically, so visual selection and route state share one identifier.
- Keep the canonical visible `lootTypes` route distinct from the `integration` RCLootCouncil route.
- Track `selectedRoute`, `mountedPage`, `mountedPageHost`, and `primaryPageCount` for lifecycle verification.
- Keep legacy programmatic route names such as `reconciliation` and `developer` compatible without exposing hidden developer entries in the interactive production tree.
- Route the visible History page through the existing reconciliation renderer and provide an explicit Diagnostics renderer instead of falling through to the legacy ledger table.
- Snapshot and detach the current content children before releasing each page root through the owning AceGUI library, allowing nested containers to be recursively recycled; retain the reduced-client `ReleaseChildren` fallback.
- Verify that a History-to-Debug transition removes the old semantic content and hides the previous page root before the new page is mounted.

## Automated Validation

- Focused AceConfig and Retail navigation tests: `29 passed, 0 failed (2 files)`.
- Real TreeGroup callback test covers all 14 visible Officer routes, including Developer and Debug when enabled, across two complete round trips.
- Exact callback divergence reproduced and covered: `section_dibs\001history` normalizes to `history` and mounts History rather than Dashboard.
- Stale-content regression covers History -> Debug, confirms no History/Reconciliation text remains, and confirms the previous page root is hidden.
- B11a-g regression slice: `45 passed, 0 failed (14 files)`.
- Workspace diagnostics: no errors in touched Lua or test files.
- `git diff --check`: no whitespace errors.
- Full explicit Fengari suite: `370 passed, 1 failed (84 files)`. The only failure is the known unrelated baseline at `tests/integration/rclootcouncil_buttons_spec.lua:155` (`expected 2/2, got 1/1`).

## Manual Retail Re-validation

On Retail, open the Officer window and verify that the main content changes with each navigation selection: Dashboard, Requests, Pre-Dibs, History, Seasons, Rank Rules, Loot Rules, Announcements, RCLootCouncil, Settings, Diagnostics, Loot Eligibility, Developer, and Debug. Specifically transition History -> Debug and confirm no Winner, Item, Difficulty, Instance, Votes, or Related controls remain mixed into Debug. Repeat the complete round trip twice without recreating the window, reopen it, and confirm that only the selected page remains visible. Verify Player cannot open Officer routes and Developer/Sandbox presentation remains separate from production authority.

`B11 RETAIL NAVIGATION CLEANUP FIX READY FOR MANUAL RE-VALIDATION`
