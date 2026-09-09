# Quickstart: RCLootCouncil Item Mapping and Installation Assistant

## Automated verification

From the repository root, run:

```powershell
$files = Get-ChildItem tests -Recurse -File -Filter "*_spec.lua" |
  Sort-Object FullName |
  ForEach-Object { $_.FullName.Replace((Get-Location).Path + "\", "").Replace("\", "/") }
$env:DIBS_TEST_FILES = ($files -join ";")
npx.cmd --yes fengari tests/run.lua
git diff --check
```

Expected release baseline: **168 passed, 0 failed (44 files)**.

## Retail validation

1. Open Dibs Officer settings and select **RCLootCouncil**.
2. Confirm the mapping guide lists semantic families, blocked Catalyst/Cosmetic groups,
   collection groups, `OTHER`, and slot-only groups.
3. Run **Curio + Tier Set** and confirm only Curio and Tier Set policies are enabled.
4. Run **Standard loot + collections** and confirm Curio, Tier Set, Mounts, Pets, Recipes,
   and Other are enabled while Decor remains disabled.
5. Select **Refresh Dibs buttons** and confirm the Dibs response is present in the default
   and already-enabled additional sets.
6. Repeat the preset and refresh. Existing response text, colors, ordering, and slot
   selections must remain unchanged and no duplicate Dibs response may appear.
7. Inspect representative loot: Context Token, Armor/Tier Token, Catalyst, Cosmetic,
   ordinary equipment, Mount, Pet, Recipe, and Decor. Check the documented family and
   Dibs eligibility.
8. Fill a response set to capacity and confirm no existing response is overwritten; the
   assistant reports that the Dibs response could not be inserted.
9. Repeat with RCLootCouncil absent or loaded after Dibs. Standalone Dibs remains usable,
   and refresh succeeds after the integration becomes available.

## Safety checks

- A normal player cannot apply presets or refresh the projection.
- Assistant actions do not change seasons, balances, Pre-Dibs, transactions, history,
  candidates, votes, or live awards.
- Disabled additional RCLootCouncil sets are not silently enabled.
- Late-load and malformed metadata paths fail conservatively for personal categories.
