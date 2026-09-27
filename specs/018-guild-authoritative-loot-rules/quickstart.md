# Quickstart: Guild-Authoritative Loot Rules

## Prerequisites

- Use two test clients loaded with the same `0.8.x` addon family and a guild roster where the test GM and Officer resolve through existing identity/governance helpers.
- Keep intentionally conflicting local legacy settings on the Officer client.
- Use the standard Fengari test harness; no external package is introduced.

## Focused Automated Validation

```powershell
$env:DIBS_TEST_FILES = 'tests/unit/guild_loot_rules_spec.lua;tests/integration/guild_loot_rules_spec.lua;tests/integration/guild_loot_rules_ui_spec.lua;tests/integration/season_catalog_sync_spec.lua;tests/integration/ace3_options_spec.lua;tests/integration/setup_assistant_spec.lua;tests/integration/setup_assistant_ui_spec.lua;tests/integration/sync_status_spec.lua'
npx --yes fengari tests/run.lua
```

Expected: every focused spec passes, including the named LRA01-LRA22 scenarios, unit normalization, adoption/publication failure, migration preservation, catalog recovery, effective-value precedence, RCLootCouncil refresh, readiness states, old-peer rejection, and prior UI regressions.

## Documentation Validation

```powershell
.\scripts\Generate-DibsDocs.ps1 -Validate
```

Expected: no missing English/French documentation concepts, duplicate IDs, errors, or warnings.

## Full Regression Suite

```powershell
$env:DIBS_TEST_FILES = (Get-ChildItem tests -Recurse -Filter '*_spec.lua' | ForEach-Object { $_.FullName.Substring((Get-Location).Path.Length + 1).Replace('\','/') }) -join ';'
npx --yes fengari tests/run.lua
```

Expected: all feature and existing tests pass. Any baseline failure must be reported separately and must not be hidden as feature success.

## Manual Two-Client Scenarios

1. With no adopted record, open Loot Rules as GM and review every option-source type and both controls. Confirm no record is published merely by opening/editing.
2. Adopt as GM. Verify a new catalog revision, writer/audit metadata, and identical effective rules on the Officer client after bounded transfer.
3. Change the Officer's preserved local legacy maps before applying the record. Confirm they remain intact while effective behavior follows the adopted record.
4. Edit a GM draft after adoption. Confirm effective values remain unchanged until explicit Publish Changes; then confirm a new catalog revision and refresh on both clients.
5. Deny or break publication. Confirm the local draft remains, the prior effective revision remains, and the UI reports publication failure.
6. Test duplicate/stale/missing-parent records, offline reconnection, and 0.6.x peers. Confirm idempotent replay/recovery and update-required/incompatible status without local fallback over active authority.
7. Deliver an update during a raid. Confirm only a fully validated catalog revision becomes effective, the existing DIBS projection refreshes, and known lag remains visible.
8. Compare RCLootCouncil SavedVariables before/after. Confirm no unrelated RCLootCouncil state was directly rewritten.
