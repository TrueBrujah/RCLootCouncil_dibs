# B11c Implementation Evidence

## Scope

This pass implements only US3, the Player UI redesign. It keeps the existing
domain services, protected mutation boundaries, RCLootCouncil adapter, and
developer sandbox authority unchanged. The normal Player surface now presents
only My Dibs, Requests, and History.

Start checkpoint: `40836c0b6696dabe38872099075b88ba3741d330`.

## Completed task IDs

- T031-T036

US4-US7 remain untouched.

## Implementation evidence

- `src/ui/PlayerUI.lua` exposes the three-view navigation and a Player-safe
  view model sourced from `GetSummary`, `PreDibs`, `Ledger`, and `Readiness`.
- My Dibs presents balance, season, active Pre-Dibs, pending request count,
  and a concise readiness explanation with an item request action.
- Requests list only the local player's Pre-Dib request history and exposes
  cancellation only for active requests. Submission continues through
  `LootPipeline.RequestDibFromContext`; cancellation continues through
  `PreDibs.CancelForPlayer`.
- History projects date, item, action, result, and balance impact. Transaction
  hashes, epochs, roots, evidence identifiers, RC diagnostics, Officer
  options, eligibility administration, and Developer controls are not part of
  the normal Player projection. The existing B11a table context-menu path
  provides an expandable Player-safe detail view with the same fields.
- Readiness reason codes are mapped to Player-safe explanations for temporary
  unavailability, sync catch-up, and recovery. No new authority or accounting
  logic was added.
- Sandbox role simulation renders the same Player-scoped surface and leaves
  the production snapshot unchanged.

## Validation

Focused B11c suites:

```text
7 passed, 0 failed (2 files)
```

Adjacent AceGUI, dispute, Midnight, and B11b validation:

```text
45 passed, 0 failed (7 files)
```

Full Fengari regression:

```text
336 passed, 1 failed (74 files)
```

The one failure is the unchanged baseline in
`tests/integration/rclootcouncil_buttons_spec.lua:155`:

```text
expected 2/2, got 1/1
```

Static diagnostics reported no errors for the touched Lua files, and
`git diff --check` passed.

## Result

`B11c COMPLETE - READY FOR REVIEW`.

The result commit is the commit containing this evidence file.