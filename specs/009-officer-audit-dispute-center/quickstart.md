# Quickstart: Officer Audit and Dispute Center

## Automated validation

Fixtures cover own/other-player scope, duplicate requests, evidence gaps, all statuses,
replies, protected corrections, UI rendering, reload, and absent RCLootCouncil. Run:

```powershell
$files = Get-ChildItem tests -Recurse -File -Filter "*_spec.lua" | Sort-Object FullName | ForEach-Object { $_.FullName.Replace((Get-Location).Path + "\", "").Replace("\", "/") }
$env:DIBS_TEST_FILES = ($files -join ";")
npx.cmd --yes fengari tests/run.lua
git diff --check
```

The automated suite currently passes 192 tests with zero failures, including the
Dispute Center integration, privacy, replay, reload, and scope tests. Retail UI
and in-raid delivery checks remain manual.

## Retail acceptance

1. From a player's own Dibs history, open **Report a problem**, verify prefilled context,
   choose a category, add a bounded note, and submit. Confirm no balance change.
2. Submit the same report again and verify it links/reopens the active request.
3. As GM/Officer, open **Review Requests**. Verify newest-first queue, filters, evidence,
   unknown fields, and privacy boundaries.
4. Resolve one case with **No correction**, one with **Ask for information**, one as
   duplicate, and one with **Correct balance**. Confirm only the authorized correction adds
   a linked compensating transaction; repeat it to verify idempotency.
5. Reply as the player, reload, change guild rank, and test concurrent Officer decisions.
6. Try player, ML, raid leader, assistant, council, Officer, and GM access; verify only
   verified guild GM/Officer can resolve or view the complete queue.
7. Repeat during combat and with RCLootCouncil absent/degraded. Verify safe deferral and
   Dibs-owned evidence remain available.

## Release gate

Run privacy, migration, bounded-text, replay, and append-only checks, then update docs,
changelog, and addon version before shipping.
