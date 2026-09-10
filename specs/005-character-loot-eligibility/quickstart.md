# Feature 005 Quickstart

## Automated validation

From the repository root:

```powershell
$env:DIBS_TEST_FILES = ((Get-ChildItem tests -Recurse -Filter '*_spec.lua' |
  ForEach-Object { $_.FullName }) -join ';')
npx.cmd --yes fengari tests/run.lua
```

The feature tests cover Curio and Tier Set family separation, cross-difficulty policy,
lowest-progress rounds, 4/4 completion, linked-character privacy, probation, authority,
Catalyst exclusion, finalized-award idempotency, and standalone operation.

Automated evidence recorded 2026-09-10: the full Fengari suite passed 219 tests in
54 files with 0 failures. Retail visual and two-client validation remains pending.

## Retail checks

1. Enable the feature on `dev`, create two test seasons, and configure different Curio
   and Tier Set policies.
2. Declare a main and alt as a player, approve the relationship as an Officer, and
   confirm that an unapproved declaration does not block the alt.
3. Finalize one Curio on the main, inspect the alt's candidate status, and verify the
   explanation shows the family, difficulty, and active rule.
4. Add a Tier Set token group with two classes, verify the lowest-progress member is
   prioritized, and advance the round only after all active members catch up.
5. Approve a main change and verify the 14-day probation label and protected-loot block;
   apply a bounded exception and confirm its reason appears in audit history.
6. Inspect the Player and Officer modeless windows at narrow and wide sizes. Confirm
   dates, aligned columns, sorting, dropdowns, main/alt request actions, and no freeze
   during history filtering.
