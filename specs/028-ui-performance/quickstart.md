# Quickstart: UI Performance Validation

## Automated checks

Run the smallest relevant slices from the repository root:

```powershell
$env:DIBS_TEST_FILES='tests/integration/officer_dibs_admin_roster_fallback_spec.lua;tests/integration/automatic_dibs_log_spec.lua;tests/unit/ledger_recent_transactions_spec.lua'
lua tests/run.lua
```

Then run the focused Wizard, PlayerUI, Sync, and integration slices for any
files changed in those areas. Record unrelated known failures separately.

## In-game comparison

1. Deploy the same working tree to the test AddOns folder and `/reload`.
2. Keep character, location, group size, addons, and SavedVariables unchanged.
3. Run `/dibs perf clear`, then `/dibs perf enable`.
4. Open Dibs Administration, Guided Setup, Integration, and the selected
   Player pages once each; then close/reopen each page once.
5. Run `/dibs perf report` and record first-open versus reopen timings, cache
   hits/misses, and FPS separately.
6. Repeat after `/reload` under the same conditions. Do not compare runs with
   materially different roster size or addon configuration.

The `Lua heap ΔKB` field is global net change with GC noise. Do not interpret
it as bytes allocated or as addon-retained memory.
