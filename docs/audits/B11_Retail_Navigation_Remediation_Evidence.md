# B11 Retail Navigation Remediation Evidence

- `Finding: B11-RETAIL-UI-001`
- `RETAIL_NAV_START_COMMIT=5b71516d8116963f185866b170e0a3a344611671`
- `RETAIL_NAV_FIX_COMMIT=8153af054633bd02b2e87c8c8dc27fa31e0387b0`
- Scope: Officer UI navigation lifecycle only. No ledger, permission, sandbox authority, SyncV2, request, policy, or RCLootCouncil business logic changes.

## Root Cause

`OfficerUI.Refresh()` used the AceGUI `TreeGroup` as both the navigation owner and the page-content owner. On Retail, nested AceConfig and scroll containers could survive a route transition or remain visually mounted after the selected tree route changed. This allowed the selected Officer route and the visible main content to diverge.

## Remediation

- Keep the AceGUI tree as navigation only.
- Mount one permanent `contentHost` beneath the navigation tree.
- Clear `contentHost` on every refresh and mount exactly one `pageRoot`.
- Render the active route exclusively inside that page root.
- Track `selectedRoute`, `mountedPage`, `mountedPageHost`, and `primaryPageCount` for lifecycle verification.
- Keep legacy programmatic route names such as `reconciliation` and `developer` compatible without exposing hidden developer entries in the interactive production tree.
- Route the visible History page through the existing reconciliation renderer and provide an explicit Diagnostics renderer instead of falling through to the legacy ledger table.

## Automated Validation

- Focused AceConfig and Retail navigation tests: `27 passed, 0 failed (2 files)`.
- B11a-g regression slice: `40 passed, 0 failed (14 files)`.
- Workspace diagnostics: no errors in touched Lua or test files.
- `git diff --check`: no whitespace errors.
- Full explicit Fengari suite: `368 passed, 1 failed (84 files)`. The only failure is the known unchanged baseline at `tests/integration/rclootcouncil_buttons_spec.lua:155` (`expected 2/2, got 1/1`). The additional file is the focused Retail navigation lifecycle spec.

## Manual Retail Re-validation

On Retail, open the Officer window and verify that the main content changes with each navigation selection: Dashboard, Requests, Pre-Dibs, History, Seasons, Rank Rules, Loot Rules, Announcements, RCLootCouncil, Settings, Diagnostics, and Loot Eligibility. Repeat route switches, reopen the window, and confirm that only the selected page remains visible. Verify Player cannot open Officer routes and Developer/Sandbox presentation remains separate from production authority.

`B11 RETAIL NAVIGATION FIX READY FOR MANUAL RE-VALIDATION`
