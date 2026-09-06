# Quickstart: Validate Pre-Dibs Encounter Journal

## Prerequisites

- Repository checked out with the addon source.
- Node.js available for the Fengari Lua harness.
- World of Warcraft Retail client available for manual Adventure Guide validation.

## Automated validation

From the repository root in PowerShell:

```powershell
$files = Get-ChildItem tests -Recurse -File -Filter "*_spec.lua" |
  Sort-Object FullName |
  ForEach-Object { $_.FullName.Replace((Get-Location).Path + "\\", "").Replace("\\", "/") }
$env:DIBS_TEST_FILES = ($files -join ";")
npx --yes fengari tests/run.lua
```

Expected outcome: all selected tests pass with zero failures.

## Scenario A: Create and deduplicate a Pre-Dib

1. Start with an active season and public Pre-Dibs enabled.
2. Create a request for one item.
3. Submit the same player/item/season request again.
4. Read request history and the player's balance.

Expected outcome:

- One active request exists.
- The second submission returns the existing request.
- No Dib consumption transaction is appended.

## Scenario B: Request lifecycle and finalized award

1. Create and confirm a request.
2. Verify the player's balance is unchanged.
3. Process a non-final or unsuccessful award outcome.
4. Confirm the request remains active.
5. Process one finalized award for the requesting player.
6. Replay the same award reference.

Expected outcome:

- The request is fulfilled only after the final award.
- One ledger consumption exists.
- The replay adds no transaction and does not fulfill again.

## Scenario C: Raid-only Adventure Guide behavior

1. Simulate or open a raid loot context.
2. Confirm a supported item can expose the Dib action.
3. Simulate or open a dungeon loot context.
4. Attempt both UI and direct submission paths.

Expected outcome:

- Raid rows can submit a request when policy allows.
- Dungeon rows have no usable action.
- Direct dungeon submission returns `EJ_NON_RAID_CONTEXT`.

## Scenario D: Category matrix

1. Apply the recommended policy.
2. Inspect cosmetic, decor, mount, pet, recipe, token, and unknown rows.
3. Override one category and refresh the loot view.

Expected outcome:

- Recommended non-Dib categories are blocked.
- Unknown categories remain visible.
- Overrides change local visibility only and do not alter ledger state.

## Scenario E: Standalone and optional RC operation

1. Run request and finalized-award scenarios with RCLootCouncil absent.
2. Repeat with a compatible local RC adapter.
3. Compare requests, award references, ledger transactions, and balances.

Expected outcome:

- Standalone accounting succeeds.
- RC may report or display local events.
- Dibs remains the only source of balance and history.

## Scenario F: Combat and missing UI states

1. Open or refresh the Adventure Guide while entering combat.
2. Confirm ordinary request state remains safe.
3. Leave combat and observe the queued or subsequent UI refresh.
4. Close or unload the Adventure Guide and allow retry logic to run.

Expected outcome:

- No protected UI mutation is forced during combat.
- UI work resumes after combat or safely stops when the frame is unavailable.

## Acceptance evidence

Record automated test output and manual results for Scenarios A-F. Note client version, addon availability, and any item rows whose metadata could not be resolved. Do not claim real-client certification when the WoW client was not available.

## Validation record

- 2026-09-05: focused Pre-Dib lifecycle, request, ledger-boundary, contract, matrix, and announcement tests passed.
- 2026-09-05: full Fengari suite passed with 46 tests and 0 failures across 28 files.
- 2026-09-05: editor diagnostics reported no errors in touched Lua modules, locales, or tests.
- 2026-09-05: real-client validation completed by the user: raid Dib actions, dungeon exclusion, sub-category overrides, Pre-Dib announcements, combat refresh, and standalone/optional RC operation behaved as expected.

See [data-model.md](data-model.md), [contracts/predibs-api.md](contracts/predibs-api.md), and [spec.md](spec.md) for the source requirements.
