# Quickstart: History Reconciliation

## Automated validation

Add history fixtures for finalized Dibs, custom aliases, localized/case-varied labels,
test/pending rows, duplicate identities, ambiguous rows, and absent RCLootCouncil. Run:

```powershell
$files = Get-ChildItem tests -Recurse -File -Filter "*_spec.lua" | Sort-Object FullName | ForEach-Object { $_.FullName.Replace((Get-Location).Path + "\", "").Replace("\", "/") }
$env:DIBS_TEST_FILES = ($files -join ";")
npx.cmd --yes fengari tests/run.lua
git diff --check
```

## Retail acceptance

1. As a GM/Officer, open **Reconcile RCLootCouncil history**.
2. Select target season, bounded date/history scope, explicit response aliases, and guided
   or manual review. Confirm that opening the form does not alter balances.
3. Run the search and inspect counts plus one row in each classification.
4. Confirm one eligible row, reject one, defer one ambiguous row, and repeat the first
   confirmation. Verify exactly one Dibs consumption and an idempotent repeat result.
5. Use manual confirmation on an ambiguous row with an acknowledgement and reason; verify
   the evidence and audit entry.
6. Check Officer evidence and a player's own history. Verify privacy and explicit unknown
   fields.
7. Repeat with no group, no channel, absent/degraded RCLootCouncil, a full/old history,
   reload, and concurrent Officer refresh.

## Release gate

Run migration tests, full suite, privacy/authority checks, and update changelog/version
before implementation is shipped. Automatic load-time scanning remains a failure.
