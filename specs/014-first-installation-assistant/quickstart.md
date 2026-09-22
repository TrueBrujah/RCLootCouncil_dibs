# Quickstart: First Installation Assistant

## Automated validation

Run the focused assistant tests:

```powershell
$env:DIBS_TEST_FILES = "tests/contract/setup_assistant_contract_spec.lua;tests/integration/setup_assistant_spec.lua;tests/integration/setup_assistant_ui_spec.lua"
npx.cmd --yes fengari tests/run.lua
Remove-Item Env:DIBS_TEST_FILES -ErrorAction SilentlyContinue
```

Run the full explicit suite:

```powershell
$files = Get-ChildItem tests -Recurse -Filter *.lua | Where-Object { $_.Name -ne "run.lua" } | ForEach-Object { $_.FullName.Substring((Get-Location).Path.Length + 1) }
$env:DIBS_TEST_FILES = ($files -join ";")
npx.cmd --yes fengari tests/run.lua
Remove-Item Env:DIBS_TEST_FILES -ErrorAction SilentlyContinue
```

## Manual validation

1. Open the assistant as a GM with a new guild fixture.
2. Confirm RCLootCouncil, authority, season, rank rules, channel, and loot-type checks are visible.
3. Create or activate the missing season through the supported control.
4. Configure rank rules and installation mode through the existing protected controls.
5. Run the local dry-run and confirm the result is explicitly local.
6. Reopen or refresh the assistant and confirm the status is derived from current state.
7. Repeat as a normal player and confirm administrative details are not exposed.
8. Repeat without RCLootCouncil and confirm standalone readiness remains distinct from live integration readiness.

## Release boundary

Automated Fengari checks do not replace Retail validation for protected frames, RCLootCouncil callbacks, channel visibility, combat lockdown, or real addon-message delivery.
