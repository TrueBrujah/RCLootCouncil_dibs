# Quickstart: Validate RCLootCouncil Permission Authority

## Automated validation

From the repository root with a Lua 5.1-compatible interpreter:

```powershell
lua tests/run.lua
```

If `lua` is unavailable on Windows PowerShell, run the reference harness through Fengari and explicitly provide test files:

```powershell
$files = Get-ChildItem tests -Recurse -File -Filter "*_spec.lua" |
  Sort-Object FullName |
  ForEach-Object { $_.FullName.Replace((Get-Location).Path + "\\", "").Replace("\\", "/") }
$env:DIBS_TEST_FILES = ($files -join ";")
npx --yes fengari tests/run.lua
```

Expected: all tests pass; any failure produces a nonzero exit code.

## Required scenarios

1. RCLootCouncil absent: guild master and appointed admin allowed; ordinary/officer/raid roles denied.
2. Operational and actor is Master Looter: every protected action reaches business validation.
3. Operational with another Master Looter: every action denied; standalone evaluator never called.
4. Loaded but incomplete, incompatible, throwing, or changing mid-call: fail closed with stable reason.
5. Exercise every action ID in contracts/authorization.md through ProtectedActions; UI and adapters have no direct mutation path.
6. Pending/failed/cancelled/malformed awards change nothing; one final award appends once; ten replays append nothing further.
7. Inspect every cross-raid snapshot/message while local candidates, votes, and responses exist; none may appear.
8. With an applicable Pre-Dib priority, verify an ineligible candidate cannot submit or have accepted the DIB response but can still use permitted non-Dib responses.
9. Inspect every accepted authoritative transaction type and verify all required actor, player-rank, action, season, timestamp, amount/item, and reason fields.
10. Run 1,000 authorization evaluations and a 40-candidate projection in the reference harness and verify thresholds in plan.md.

## In-client smoke test

Back up test SavedVariables. Test standalone appointment/revocation, then load both addons and confirm only the current Master Looter controls protected Dibs actions. Change leader/reconnect to confirm fresh evaluation. Finalize one qualifying award, reload, and rebuild balance without RCLootCouncil history. During combat, verify accounting continues while protected UI changes wait for combat end.

## Validation record

- 2026-09-03: automated reference harness passed 33 tests under Fengari (33 passed, 0 failed).
- 2026-09-03: reran automated scenarios from Windows PowerShell using `npx --yes fengari tests/run.lua` with `DIBS_TEST_FILES`; result remained 33 passed, 0 failed.
- 2026-09-03: after restoring missing 003 test suites and helpers, automated validation passed 18 tests under Fengari (18 passed, 0 failed), including TOC load integrity, ProtectedActions matrix, finalized award flow, RC authority deny/no-fallback, migration baseline, and sync privacy checks.
- In-client World of Warcraft smoke remains required because this repository environment cannot launch the game client. Compatibility limitations are documented and no live-client certification is claimed.
