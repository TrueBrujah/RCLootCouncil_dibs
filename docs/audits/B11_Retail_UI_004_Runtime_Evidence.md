# B11 Retail UI-004 Runtime Evidence

- `Finding: B11-RETAIL-UI-004`
- `RETAIL_UI4_START_COMMIT=86b86deffbcc7aeb0e7f0383adb38d0d01454ee5`
- Scope: AceGUI/lib-st runtime ownership, tooltip API arguments, TreeGroup root attachment, table release, dropdown release, Player/Officer window isolation, pooled-frame lifecycle, routed-page diagnostics, window-position persistence, routed-page title ownership, and canonical Pre-Dib option values. No ledger, balance, request redesign, policy, governance, synchronization, recovery, RCLootCouncil, or sandbox authority changes were made.
- Existing UI-003 worktree changes were preserved.

## V2 Runtime Stabilization

Manual Retail validation reopened UI-004 after finding three runtime-only failures: routed pages could become empty after reload or route changes, Player/Officer reopen cycles could retain cross-window lifecycle state, and window position could jump toward the top edge after navigation or reopen. The V2 changes address the shared runtime causes without redesigning Requests.

### Lifecycle root cause and correction

AceGUI native frames are pooled. PlayerUI and OfficerUI previously added `OnShow` handlers on every shell construction, while `AceGUI.CreateWindow` added another `OnSizeChanged` handler. Retail `HookScript` accumulates those handlers, so released shells could continue refreshing or resizing after their frame was reused. The V2 path installs one dispatcher per native frame, routes it through the current active shell, and makes released shells inactive before recursive AceGUI cleanup. Controller references to page roots, controls, callbacks, and shell ownership are cleared on release.

The test WoW API now accumulates `HookScript` callbacks like Retail instead of overwriting the previous callback, so stale-hook regressions remain visible in Fengari.

### Position root cause and correction

AceGUI Frame `ApplyStatus`, explicit initial positioning, and LibWindow restoration all manipulate frame anchors. V2 gives Player and Officer separate keys (`PlayerWindowPosition` and `OfficerWindowPosition`), registers/restores once per native-frame lifecycle, unregisters on close, and leaves route refreshes outside the position path. LibWindow remains responsible for drag persistence after an actual drag stop; page content is never used as the parent anchor.

### Requests instrumentation

The Officer Requests renderer now emits bounded `[ui debug]` diagnostics for `RENDER_BEGIN`, request count, and `RENDER_END`, including route, page-root identity, content-host identity, selected request id, and child counts before/after mount. Unavailable-queue early returns also emit completion diagnostics. Navigation keeps renderer failures observable through the existing debug facility while preserving the Retail UI's resilient callback boundary.

## V3 Findings And Corrections

### UI-004J Window position still forced to top

Retail validation showed that the V2 position path still had competing movement owners: the AceGUI title region and LibWindow could both participate in drag and anchor handling, while repeated clamping could move a valid position. V3 keeps one top-level owner in `Dibs.WindowState`: it registers the per-window LibWindow record, installs the Dibs drag/save boundary, restores only during registration, and recovers only positions that are actually off-screen. Valid coordinates are not recentered during route refreshes. Position diagnostics record restore, recovery, drag start/stop, and save coordinates, scales, and keys.

The Player and Officer records remain separate (`PlayerWindowPosition` and `OfficerWindowPosition`), with legacy dotted fields migrated into the nested record when encountered. The focused regression simulates a valid title-region drag and asserts no second restore, one save, and persisted coordinates.

### UI-004K Duplicate or stale routed page headers

OfficerUI was adding a route title while the shared AceConfig renderer added the option-group title again. V3 makes the option-group renderer the title owner for options-backed routes; custom routes retain their explicit header, and every route rebuild clears the prior page host before mounting the next one. The route regression covers repeated transitions and asserts one visible title with no stale Pre-Dib title/content duplication.

### UI-004L Pre-Dib `INVALID_PREDIB_MODE` regression

The Pre-Dib policy accepts canonical keys `WILD_OPEN` and `ENCOUNTER`, while a Retail dropdown may provide the display label. V3 normalizes both AceGUI fallback and MSA dropdown callbacks from display labels to keys before invoking option setters. The Pre-Dib setter also normalizes and fails closed before `ProtectedActions`, with bounded diagnostics for display label, dropdown value, normalized value, and service value. Focused coverage verifies both supported round-trips and verifies a generic enum dropdown maps `Guild` to `GUILD`.

## Signature A: lib-st Cell Tooltip SetText

### Root cause

The generic lib-st `OnEnter` handler receives the cell value after lib-st dispatches `(rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)`. The cell text was not the problem. The adapter passed `GameTooltip:SetText(value, 1, 1, 1, true)`, placing the boolean wrap flag in argument 5. Retail expects alpha in argument 5 and wrapText in argument 6, so values such as empty text, `Unavailable`, `Tier Set`, normal text, and long text could trigger the BugSack argument-range error.

### Corrected contract

All non-item lib-st cell values now use `GameTooltip:SetText(value, 1, 1, 1, 1, true)`. Item links continue through `SetHyperlink`, preserving colored item links and their native tooltip behavior. The logic is centralized in `Dibs.AceGUI.ShowTableCellTooltip` and used by the generic table renderer.

### Focused regression

`tests/integration/b11_retail_ui004_ownership_spec.lua` covers empty, unavailable, Tier Set, normal, long, nil/missing, plain item link, and colored item link values. It asserts the exact argument positions and that item links use `SetHyperlink`.

## Signature B: TreeGroup Cyclic SetPoint

### Root cause and ownership correction

`AddTree` previously created a TreeGroup directly and attached it through a second `shell.window:AddChild` path. Root helpers now use the single `Adapter.Create` ownership path, so the new TreeGroup has exactly one AceGUI owner: the window widget. `Adapter.Create` rejects self-ownership and detects an owner frame already contained by the prospective child frame before calling `AddChild`.

The intended graph is:

`Window widget -> TreeGroup widget -> TreeGroup content frame -> page/content widgets`

The TreeGroup's native tree frame, border, and buttons remain owned by the TreeGroup implementation. No page widget is anchored to a descendant of its owner.

### Focused regression

The UI-004 lifecycle test opens Player and Officer windows independently, routes pages, closes each window, and repeats the sequence three times. The existing Retail navigation lifecycle tests cover repeated route transitions and assert one Officer page root after every route change.

## Signature C: Self-Parenting in Table Creation

### Root cause and ownership correction

`Adapter.Create` previously interpreted any parent with `AddChild` as an AceGUI owner and otherwise silently fell back to the shell window. That made widget, content-frame, and raw-frame arguments ambiguous. The corrected contract is:

- Owner widget: an AceGUI container with `AddChild` and `frame`.
- Owner content frame: selected internally by the owner's `AddChild` implementation.
- New child widget: returned by `shell.gui:Create`.
- New child frame: owned by the new child widget.
- Raw Blizzard frame: not accepted by `Adapter.Create`; use the explicit `Adapter.CreateInFrame` boundary when a raw frame is intentionally required.

The helper rejects self-parenting, same-frame ownership, and detectable ancestor/descendant cycles before attachment. `AddTabs`, `AddTree`, `AddSearch`, and `AddPagination` now use the same explicit owner path instead of direct or unattached creation.

### Scrolling table release

Each lib-st instance is created with one wrapper host owned by its page/window. On release or rebuild, the adapter unregisters lib-st events, hides and detaches the native table frame, restores the wrapper width handler, clears Dibs-owned `_dibs*` state, and releases the surrounding AceGUI widget. MSA dropdown controls are similarly hidden, unanchored, detached, and returned to their pool. Window close invokes this cleanup before AceGUI pooling.

### Focused regression

The UI-004 ownership test injects a lib-st-compatible table stub, asserts that the native table receives exactly the wrapper frame as parent, verifies `OnEnter` registration, and confirms the table reference is cleared after `Adapter.Clear`. It also asserts raw-frame parents are rejected by `Adapter.Create`.

## Player/Officer Isolation

Player and Officer windows each create their own TreeGroup and content hierarchy. The focused lifecycle regression confirms their tree and window instances differ, routes each window independently, closes and reopens both three times, and verifies stable page ownership with no cross-window instance reuse.

## Manual Retail Reproduction Procedure

Manual validation remains required on Retail. With BugSack enabled:

1. Clear BugSack, then open Player UI and exercise My Dibs -> Requests -> History -> My Dibs. Close and reopen the Player window three times.
2. Clear BugSack, then exercise every Officer route: Dashboard, Requests, Pre-Dibs, History, Seasons, Rank Rules, Loot Rules, Announcements, RCLootCouncil, Settings, Diagnostics, Loot Eligibility, Developer, and Debug. Test route -> another route -> back, close -> reopen -> route, and reload-like addon initialization.
3. Open Officer, open and close Player, navigate Officer, then reopen and close Player again. Confirm no old Player controls appear in Officer and no Officer controls appear in Player.
4. Hover empty, unavailable, Tier Set, normal, long, plain item-link, and colored item-link cells.
5. Inspect BugSack after each sequence. Confirm zero `AceGUI.lua` SetText argument errors, cyclic SetPoint errors, self-parent SetParent errors, AddScrollingTable ownership errors, AddDropdown/MSA self-parent errors, and empty-page exceptions.
6. Drag each window from its title region, move it down from the top half of the screen, navigate several routes, close/reopen, and confirm the saved window remains draggable and does not jump toward the top edge.
7. Confirm each routed page has one title and optional description, visible content after reload and route transitions, no stale controls from the previous page, and Requests logs contain matching `RENDER_BEGIN`/`RENDER_END` entries.

Automated Lua mocks cannot claim zero Retail BugSack errors; this artifact records the exact code paths and focused checks ready for manual reproduction.

## Validation

- UI-004 focused ownership suite: `8 passed, 0 failed`.
- UI-004 plus navigation and Midnight lifecycle slice: `20 passed, 0 failed` across 3 files.
- Focused B11 Retail/UI regression slice: `20 passed, 0 failed` across the UI-004, navigation, and Midnight lifecycle files.
- Full explicit Fengari suite: `385 passed, 1 failed` across 86 files. The single failure is the pre-existing RCLootCouncil baseline at `tests/integration/rclootcouncil_buttons_spec.lua:155` (`expected 2/2, got 1/1`); no UI-004 test failed.
- AceGUI and UI-004 test diagnostics: no errors.
- `git diff --check`: passed; only Git's existing LF-to-CRLF conversion warnings were emitted.

`B11 RETAIL UI-004 V3 AUTOMATED VALIDATION COMPLETE; MANUAL RETAIL VALIDATION REQUIRED`
