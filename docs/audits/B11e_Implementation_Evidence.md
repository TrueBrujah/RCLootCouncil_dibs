# B11e Implementation Evidence

## Scope

This pass implements US5 / B11e, the Requests, Pre-Dibs, and Eligibility UX
slice. US6 and US7 remain untouched.

## Implementation evidence

- `src/ui/OfficerUI.lua` now exposes bounded Officer request rows with readable
  status, next action, explanation, and bounded player/category/item/note data.
  Timeline, vote, candidate, and other technical evidence remains outside the
  projection.
- `src/ui/PlayerUI.lua` now exposes owner-scoped request rows through
  `Dibs.Disputes.ListForPlayer`. Player rows include only bounded category,
  item, note, status, and next-action information. Unavailable states such as
  `SYNC_BEHIND` have readable recovery guidance.
- Officer Pre-Dib tables use the bounded Pre-Dib projection for status, item,
  difficulty, mode, and delivery presentation.
- Eligibility opens on a Recommended preset. Curio, Tier Set, and Token are
  allowed by default; Mount, Pet, Cosmetic, and Catalyst are blocked. Catalyst
  remains permanently blocked with reason code `CATALYST_PERSONAL`.
- Customize reveals semantic family, reason, current state, and authorized
  policy controls. Draft changes stay in projection state until an explicit
  save.
- `Dibs.OfficerUI.SaveEligibilityPolicy` and
  `Dibs.OfficerUI.SavePreDibMode` delegate exclusively to
  `Dibs.ProtectedActions.Execute`; the UI does not call domain policy setters
  directly.
- Existing domain services remain authoritative for request lifecycle,
  eligibility semantics, permissions, ledger behavior, and synchronization.

## Tests

Focused B11e tests:

```text
7 passed, 0 failed (2 files)
```
  Full Fengari regression:

  ```text
  349 passed, 1 failed (86 files)
  ```

  The one failure is the unchanged baseline in
  `tests/integration/rclootcouncil_buttons_spec.lua:155`:

  ```text
  expected 2/2, got 1/1
  ```

  `git diff --check` passed.
```text
25 passed, 0 failed (9 files)
```

Static diagnostics reported no errors for the touched Lua files. Full Fengari
regression and `git diff --check` are run as the final validation for this
slice.

## Result

`B11e COMPLETE - READY FOR REVIEW`.
