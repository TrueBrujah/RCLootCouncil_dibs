# Quickstart: Backups, Export, Import, and Profiles

## Automated validation

Add fixtures for valid/current/old/future packages, checksum tampering, truncation,
executable-looking text, duplicate transactions, cross-guild scope, and profile isolation.
Run:

```powershell
$files = Get-ChildItem tests -Recurse -File -Filter "*_spec.lua" | Sort-Object FullName | ForEach-Object { $_.FullName.Replace((Get-Location).Path + "\", "").Replace("\", "/") }
$env:DIBS_TEST_FILES = ($files -join ";")
npx.cmd --yes fengari tests/run.lua
git diff --check
```

## Retail acceptance

1. Create a local backup and verify scope, schema, checksum, size, and retention status.
2. Change a test profile, preview restore, cancel, and confirm that balances and history do
   not change. Restore it and verify the pre-operation snapshot remains available.
3. Create local and guild profiles. Switch, copy, reset, and delete them; verify no ledger
   transaction, permission, season, or guild identity changes.
4. Export configuration-only, guild policy, and full-data packages. Confirm sensitivity
   warnings and that redacted output omits private fields.
5. Import into an empty test scope. Review merge/replace/append preview and confirm only
   the selected scope changes; repeat the import to verify idempotency.
6. Try malformed, truncated, tampered, future-version, cross-guild, and executable-looking
   packages as player, ML, Officer, and GM; verify authority and rejection messages.
7. Simulate reload, combat, failed apply, changed realm/guild, and RCLootCouncil absent or
   degraded. Verify active data and restore recovery remain usable.

## Release gate

Add migration, retention, privacy, and package-format documentation plus a dated changelog
and version increment before shipping.
