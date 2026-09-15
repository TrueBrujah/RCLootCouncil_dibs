# B11 Retail UI-003 Remediation Evidence

- `Finding: B11-RETAIL-UI-003`
- Scope: Officer request review UX, dangerous-action disclosure, Debug presentation, and related Retail route cleanup. Request lifecycle, eligibility semantics, permissions, protected actions, synchronization, and RCLootCouncil business behavior remain authoritative in their existing services.
- Starting point: UI-002 committed at `86b86deffbcc7aeb0e7f0383adb38d0d01454ee5`.

## Findings And Remediation

### UI-003A: Request review starts with a human-readable summary

The Requests table now presents Date, Player, Item / Request, and Status. The permanent Action column was removed. A left-click on a row opens the selected request, while the existing safe right-click menu retains `Open request details` and `Clear selected request`. Technical evidence, raw integration fields, advanced corrections, and audit history are disclosed only from the selected request page.

### UI-003B: Progressive disclosure of request evidence

The selected request leads with the request category, player, item, current status, explanation, and next action. `Show technical details` reveals integration, transaction, award/history, and unavailable-field evidence only when needed. Audit history is collapsed by default and can be expanded explicitly.

### UI-003C: Advanced actions are visibly separated and gated

Balance corrections, historical imports, refunds, revokes, target corrections, and GM-only administrative adjustment remain in `Advanced officer tools`. Their controls are disabled until the user provides a reason and confirms the explicit data-change acknowledgement. The controls update their disabled state as the reason and confirmation change. Final authorization and mutation still occur through the existing permission and Disputes service boundaries.

`Admin adjustment` is constructed only when the existing permission decision identifies an allowed GM role. Normal Officers therefore do not see the control, while the UI does not create a second authorization model.

### UI-003D: Debug has one presentation owner

The shared AceConfig renderer no longer intercepts the `debug` route. The dedicated Debug renderer owns the page and tracks its controls, logs action, and report action. Route transitions from Requests and Loot Eligibility are covered to ensure stale request or eligibility content is not mounted into Debug.

### UI-003E: Eligibility presentation remains semantic

The existing Recommended eligibility preset remains the first view. Advanced policy controls remain behind Customize, with category state and semantic reasons preserved. No eligibility decision or policy mutation semantics were changed.

### UI-003F: Sandbox storage blocker remains bounded and explicit

The developer sandbox store validates persisted payloads against `MAX_NODES = 20000` and returns `SANDBOX_STORE_TOO_LARGE` when a payload exceeds that bound. UI-003 does not raise the limit, clone unrestricted production data, or change SavedVariables behavior. A separate bounded sandbox-storage remediation is required before this blocker can be considered resolved: `B11-RETAIL-SANDBOX-001`.

## Focused Regression Coverage

- UI-003 focused suite: `4 passed, 0 failed`.
- UI-003 plus request/eligibility projection suite: `8 passed, 0 failed`.
- UI-003 plus navigation and reconciliation slice: `15 passed, 0 failed`.
- Officer target-selector regression: `1 passed, 0 failed`.

Coverage includes simple Request presentation, safe context actions, confirmation gating, GM-only action construction, Debug route ownership, route transitions, and Recommended eligibility presentation.

## Workspace Validation

- Manual Retail validation: not performed in this environment.
- Full explicit Fengari suite: `377 passed, 1 failed (93 files)`.
- Remaining failure is the known unrelated baseline at `tests/integration/rclootcouncil_buttons_spec.lua:155` (`expected 2/2, got 1/1`).
- Diagnostics: no errors reported in the changed OfficerUI, UI-003, or target-selector files.
- `git diff --check`: clean.

`B11 RETAIL UI-003 FIXES READY FOR MANUAL RE-VALIDATION`
