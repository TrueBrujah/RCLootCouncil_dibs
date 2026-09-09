# Quickstart: Raid Readiness and Dry-Run Center

## Automated validation

Fixtures for Ready, Degraded, Blocked, Unavailable, no group/channel, stale checks,
absent/degraded RCLootCouncil, custom aliases, dry-run replay, and privacy reports
are included in `tests/helpers/rclootcouncil_fixtures.lua`. Run:

```powershell
$files = Get-ChildItem tests -Recurse -File -Filter "*_spec.lua" | Sort-Object FullName | ForEach-Object { $_.FullName.Replace((Get-Location).Path + "\", "").Replace("\", "/") }
$env:DIBS_TEST_FILES = ($files -join ";")
npx.cmd --yes fengari tests/run.lua
git diff --check
```

## Retail acceptance

1. As GM/Officer, run readiness with valid season, response, ML, and integration. Verify
   `Ready`, timestamp, passed probes, and no ledger change.
2. Break one condition at a time: missing response, unverifiable ML, stale season, absent
   channel, no group, unavailable sync, and absent/degraded RCLootCouncil. Verify the state,
   impact, and remediation distinguish expected context from failure.
3. Run a dry-run with valid and invalid item, winner, alias, status, identity, and mode.
   Repeat it and verify deterministic results without Dibs, chat, events, or RC changes.
4. Change settings, reload, change roster, and late-load RCLootCouncil. Verify stale Ready
   is invalidated and live award handling revalidates current capability.
5. Copy safe and detailed reports. Verify safe output omits candidates, votes, balances,
   private notes, item payloads, and unrelated identities.
6. Repeat while in combat and as player/ML/council/non-officer. Verify deferral and authority.

## Release gate

Update diagnostics, migration, changelog, and version metadata after all no-mutation and
privacy tests pass.
