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

The additive reconciliation schema is stored under each guild bucket as
`reconciliation.version = 1` (sessions, aliases, decisions, evidence and an
evidence index). Existing Dibs schema version 6 remains readable; loading the
addon only initializes these empty tables and never scans or imports history.

## Retail acceptance

1. As a GM/Officer, open **RC History** in the Officer window (or use `/dibs reconcile`).
2. Select target season, bounded date/history scope, and explicit response aliases. Keep
   the history-final-status rule enabled when older rows contain a stable id/date but no
   final-status field. Confirm that opening the form does not alter balances.
3. Run the search and inspect counts plus one row in each classification.
4. Use **Transfer** on one row, enter a transfer note, confirm it as DIB, and repeat the
   confirmation. Verify exactly one Dibs consumption and an idempotent repeat result.
5. Disable the history-final-status rule and verify that a row without a final status stays
   ambiguous until it is reviewed; verify the evidence and audit entry.
6. Check Officer evidence and a player's own history. Verify privacy and explicit unknown
   fields.
7. Repeat with no group, no channel, absent/degraded RCLootCouncil, a full/old history,
   reload, and concurrent Officer refresh.

## Release gate

Run migration tests, full suite, privacy/authority checks, and update changelog/version
before implementation is shipped. Automatic load-time scanning remains a failure.
