# Validation: Development Catch-up

Run from the repository root in PowerShell:

```powershell
$previousTestFiles = $env:DIBS_TEST_FILES
try {
    $env:DIBS_TEST_FILES = 'tests\integration\minimap_button_spec.lua;tests\integration\great_vault_ui_spec.lua;tests\unit\great_vault_acquisition_spec.lua;tests\integration\great_vault_retail_capability_spec.lua;tests\integration\unified_history_search_spec.lua'
    npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua
    if ($LASTEXITCODE -ne 0) { throw "Fengari failed." }
} finally {
    $env:DIBS_TEST_FILES = $previousTestFiles
}
git diff --check
```

Observed before this retrospective record: 40 passed, 0 failed across these
five suites. Earlier dispute verification: 21 passed across four suites.
The full pre-ticket run is recorded separately when completed.

First full run: 965 passed, 1 failed across 155 suites. The dashboard assertion
still expected unknown coordinator presence although the corrected shared
roster fixture now explicitly supplies online status. Align that assertion to
the fixture; keep the separate live-presence transition test unchanged.

After that assertion correction: 72 passed, 0 failed across seven selected
suites covering the dashboard, transport, sync status, anonymous export and
period statistics. `git diff --check` passed. This is a full run followed by a
targeted successful rerun, not a claim of a second all-green full run.

## Manual gates still open

- Actual Retail selected Vault claim and local loot payload correlation.
- Full link inserted from bags/equipment, including a Myth-track reward.
- Real minimap toggling for normal member and Officer, including combat.
- Same-guild two-client recovery and privacy, including offline recipients.
- Visual scale/layout checks for history, health, statistics and export.

Original feature 013 tasks T051/T052 and feature 022 T022 remain unchecked.
