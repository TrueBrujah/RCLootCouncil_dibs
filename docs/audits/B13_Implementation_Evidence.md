# B13 Great Vault Implementation Evidence

## Scope

This evidence covers Great Vault acquisition tracking, guild-safe synchronization,
recovery, ownership isolation, migration/import behavior, and UI acceptance
coverage for specification `013-great-vault-acquisition-sync`.

Evidence captured under development build `0.6.3-dev`; current development build
is `0.6.4-dev`.

## Implemented behavior

- Automatic Retail records require complete claim evidence; Vault-open and reward-choice observations do not confirm an acquisition.
- `/dibs vault <itemID> [difficulty]` remains available as the manual fallback and records an explicit verification state.
- Vault records are evidence-only and do not append, consume, grant, or fulfill Dibs ledger state.
- `VAULT_DIGEST`, `VAULT_FETCH`, `VAULT_DETAIL`, and `VAULT_ACK` use bounded guild-scoped transport with replay, stale, conflict, privacy, sender, and transfer-expiry checks.
- Player projections omit Officer-only evidence. Officer review preserves immutable identity conflicts and requires an audited decision reason.
- Guild changes preserve prior guild ownership. Unguilded records are character-scoped, including records migrated from flat legacy storage.
- Schema 7 migration and full-data import preserve legacy evidence, classify missing evidence safely, deduplicate stable identities, and preserve local review decisions.

## Focused automated evidence

Command:

```powershell
$env:DIBS_TEST_FILES = 'tests/unit/great_vault_acquisition_spec.lua;tests/integration/great_vault_isolation_spec.lua;tests/integration/great_vault_migration_spec.lua'
npx.cmd --yes fengari tests/run.lua
```

Result:

```text
15 passed, 0 failed (3 files)
```

UI acceptance command:

```powershell
$env:DIBS_TEST_FILES = 'tests/integration/great_vault_ui_spec.lua'
npx.cmd --yes fengari tests/run.lua
```

Result:

```text
4 passed, 0 failed (1 file)
```

Full regression command:

```powershell
$env:DIBS_TEST_FILES = (Get-ChildItem -Path tests -Recurse -Filter '*_spec.lua' | ForEach-Object { $_.FullName.Substring((Get-Location).Path.Length + 1).Replace('\\','/') }) -join ';'
npx.cmd --yes fengari tests/run.lua | Select-Object -Last 5
```

Result:

```text
496 passed, 0 failed (104 files)
```

## Covered files

- `src/Core.lua`
- `src/modules/PreDibs.lua`
- `src/modules/SyncV2.lua`
- `src/modules/ImportExport.lua`
- `src/integrations/GreatVault.lua`
- `src/ui/PlayerUI.lua`
- `src/ui/OfficerUI.lua`
- `src/ui/LogsUI.lua`
- `tests/integration/great_vault_ui_spec.lua`

## Remaining manual gates

Fengari cannot prove Blizzard Retail claim callbacks, protected-window timing,
real addon-message delivery, or two live clients. Those remain in
`B13_Retail_Validation_Checklist.md` and `B13_Guild_Sync_Validation_Evidence.md`.
