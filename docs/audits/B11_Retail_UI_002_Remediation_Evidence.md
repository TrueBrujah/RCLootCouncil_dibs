# B11 Retail UI-002 Remediation Evidence

- `Finding: B11-RETAIL-UI-002`
- `RETAIL_UI_002_START_COMMIT=8af9f897bd0578c98f1362ac5331ab39bdf207f5`
- Scope: Retail presentation, interaction ownership, page lifecycle, and Developer sandbox activation. No ledger, permission, protected-action, synchronization, request, policy, or RCLootCouncil award semantics were changed.

## Findings And Remediation

### UI-002A: Retail page isolation

`OfficerUI` clears transient menus and tooltips, releases the previous content root through the owning AceGUI library, and mounts one active page root in the shared content host. History transfer windows are explicitly closed when leaving History/Reconciliation, preventing stale modal or page content from remaining visible on Settings, Loot Eligibility, or Debug.

### UI-002B: Readable grouped options

Nested AceConfig groups render through stacked titled sections rather than relying on inline nesting that collapses or clips in the Retail adapter. Existing option callbacks and shared settings remain unchanged.

### UI-002C: Historical transfer review

The transfer window leads with readable Item, Winner, Difficulty, Encounter, Award date, and Evidence fields. Raw field/value evidence is behind an explicit Technical Evidence disclosure. The History row action is `Review`, and route changes close the secondary window.

### UI-002D: Page-owned table interactions

History exposes only review-specific actions and suppresses generic sorting. Requests removes the permanent Request ID column, suppresses generic sorting, and provides page-specific `Open request details` and `Clear selected request` context actions.

### UI-002E: Pagination presentation

Requests, History, and reconciliation pagination controls are hidden when the current result has one page, while multi-page navigation remains available.

### UI-002F: Developer sandbox activation

The Officer Developer page button calls the existing `DeveloperSandbox` service directly. It enters or refreshes the sandbox, refreshes the page, displays the active banner, and keeps a newly entered sandbox role-neutral (`role=nil`) until a simulated role is explicitly selected. No GM or officer authority is granted automatically.

### UI-002G: Developer-only RCLootCouncil controls

RCLootCouncil dry-run inputs, execution, and result details are hidden outside Developer Mode. Normal RCLootCouncil presentation retains the operational Readiness section.

### UI-002H: Focused regression coverage

- Retail navigation and lifecycle: `8 passed, 0 failed`.
- AceConfig/options and Developer-only visibility: `24 passed, 0 failed`.
- History modal plus Retail navigation: `18 passed, 0 failed`.
- B11-named regression slice plus Developer Mode: `45 passed, 0 failed (16 files)`.
- Focused Requests/History/navigation slice after the final context-menu change: `14 passed, 0 failed (3 files)`.

Coverage includes History-to-Settings/Eligibility/Debug isolation, the actual Developer button callback, sandbox provider and role state, modal action label, and dry-run visibility.

### UI-002I: Workspace validation

- Full explicit Fengari suite: `373 passed, 1 failed (92 files)`.
- Remaining failure is the known unrelated baseline at `tests/integration/rclootcouncil_buttons_spec.lua:155` (`expected 2/2, got 1/1`).
- `git diff --check`: clean.
- Diagnostics: no errors reported in the changed OfficerUI, Midnight, DeveloperSandbox, RCLootCouncilOptions, or test files. Existing AceGUI shim diagnostics remain for the reduced WoW type model (`Frame.Button` and the simulated `GameTooltip:SetText` signature).

## Manual Retail Re-validation

This artifact does not claim manual Retail validation. On Retail, verify each Officer route renders only its own page, especially History -> Settings, Loot Eligibility, and Debug. Open History Review and confirm the readable summary, Technical Evidence disclosure, contextual actions, and modal close behavior. Open Requests and verify the simplified columns, page-specific context menu, and hidden single-page pagination. Enable Developer Mode, activate the sandbox from the Officer Developer page, confirm the active banner and role-neutral state, then explicitly select a simulated role and confirm production authority remains separate.

`B11 RETAIL UI-002 FIXES READY FOR MANUAL RE-VALIDATION`
