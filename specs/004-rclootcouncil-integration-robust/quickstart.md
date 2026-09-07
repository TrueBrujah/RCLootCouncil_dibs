# Quickstart: Robust RCLootCouncil Integration

## Prerequisites

- A clean checkout on `feature/rclootcouncil-integration-robust`.
- Node.js and the repository Lua test harness.
- World of Warcraft Retail with the addon available in the test AddOns directory.
- RCLootCouncil installed for integration scenarios and absent/disabled for fallback
  scenarios.
- Two test characters when validating local ML, guild officer, and player boundaries.

## Automated Validation

Run the complete suite from the repository root:

```powershell
$files = Get-ChildItem tests -Recurse -File -Filter "*_spec.lua" |
  Sort-Object FullName |
  ForEach-Object { $_.FullName.Replace((Get-Location).Path + "\\", "").Replace("\\", "/") }
$env:DIBS_TEST_FILES = ($files -join ";")
node node_modules/fengari-node-cli/src/lua-cli.js tests/run.lua
```

Expected outcome: every contract, unit, and integration test passes with zero failures.

Focused integration validation:

```powershell
$env:DIBS_TEST_FILES = 'tests/contract/core_api_contract_spec.lua;tests/contract/core_independence_spec.lua;tests/contract/sync_privacy_spec.lua;tests/integration/finalized_award_flow_spec.lua;tests/integration/rclootcouncil_adapter_spec.lua;tests/integration/rclootcouncil_capability_spec.lua;tests/integration/rclootcouncil_award_replay_spec.lua;tests/integration/rclootcouncil_authority_matrix_spec.lua;tests/integration/rclootcouncil_options_fallback_spec.lua;tests/contract/rclootcouncil_award_contract_spec.lua;tests/contract/rclootcouncil_authority_spec.lua;tests/integration/ace3_options_spec.lua;tests/integration/guild_isolation_spec.lua;tests/unit/rclootcouncil_response_spec.lua;tests/unit/permissions_spec.lua'
node node_modules/fengari-node-cli/src/lua-cli.js tests/run.lua
git diff --check
```

Expected outcome: capability states, authority boundaries, local-ML enforcement,
finalized-award idempotency, history preservation, privacy, options, and Standalone
operation all pass.

## Scenario A: Standalone Fallback

1. Disable or remove RCLootCouncil and load Dibs.
2. As a guild GM/officer, open Dibs settings, change a policy value, and inspect the ledger.
3. As an ordinary player, inspect the player view and attempt an officer action.

Expected outcome: Dibs core and administration work for the guild GM/officer; the ordinary
player remains limited to permitted personal views; no integration error blocks the core.

## Scenario B: Operational RCLootCouncil and ML Award

1. Load RCLootCouncil with a verified Master Looter and start a loot session.
2. Confirm the integration status is operational and the DIB response is available only
   where the configured loot policy permits it.
3. Finalize one qualifying DIB award for a player with an eligible Dib balance.
4. Review the Dibs balance, ledger row, award reference, winner, item, and audit actor.

Expected outcome: RCLootCouncil manages the loot session; Dibs records one protected debit
with the local verified ML as award provenance.

## Scenario C: Duplicate, Reload, and Non-DIB Awards

1. Deliver the same finalized award callback twice.
2. Reload the client and replay the same award when the stable source identity is available.
3. Finalize a normal response, a test award, an ambiguous response, and an award with missing
   item or winner identity.

Expected outcome: the original DIB debit remains exactly once; all other cases leave the
production ledger unchanged and provide a useful reason.

## Scenario D: Non-ML Client Replay

1. Run a two-client test with one client as the current RCLootCouncil ML and one ordinary
   client or officer who is not the ML.
2. Deliver or simulate the ML callback on both clients.
3. Attempt to finalize the award from the non-ML client.

Expected outcome: only the local current ML can finalize the award; the other client ignores
or rejects the callback and appends no ledger transaction.

## Scenario E: Authority Matrix

For each actor, attempt settings, mode, season, rank, grant, removal, refund, and manual
adjustment operations, then test RCLootCouncil loot and DIB finalization separately.

Expected outcome:

- guild GM/officer: Dibs administration succeeds;
- current ML without guild authority: RCLootCouncil loot and qualifying local DIB finalization
  succeed, but Dibs administration fails;
- Raid Leader, Raid Assistant, council member, and ordinary player without guild authority:
  no Dibs administration or automatic award finalization.

## Scenario F: Degraded and Unsupported Surfaces

1. Expose an RCLootCouncil instance with a missing callback, missing ML identity, malformed
   options surface, or unknown capability shape.
2. Try to use the affected integration action.
3. Continue using Standalone Dibs settings and player views.

Expected outcome: the adapter reports degraded or unsupported, rejects the affected action,
and preserves Dibs seasons, requests, balances, and history.

## Scenario G: History and Privacy

1. Load existing RCLootCouncil history containing records unrelated to Dibs.
2. Initialize and refresh the Dibs integration repeatedly.
3. Compare unrelated RCLootCouncil identifiers and inspect player, officer, diagnostic, and
   synchronization views.

Expected outcome: unrelated RC history is byte-for-byte equivalent where the client exposes
it; only Dibs-owned accounting is added; ordinary players cannot read officer-only data or
live cross-raid loot state.

## Scenario H: Release Traceability

1. Review the change for a dated changelog entry describing what and why changed plus
   compatibility/migration impact.
2. Verify the addon version is incremented for every addon behavior/build change.
3. Record automated and Retail validation evidence without private guild identities.

Expected outcome: the release candidate satisfies the constitution's version and changelog
gate.

## Evidence Record

Record the WoW client build, RCLootCouncil build or capability surface, actor roles, scenario
result, reason codes, award references, and test counts. Do not commit private guild names,
player identities, or live loot payloads.

## Current implementation evidence

- Branch: `feature/rclootcouncil-integration-robust`
- Addon version: `0.2.2-dev` (`src/Core.lua` and `src/RCLootCouncil_dibs.toc`)
- Automated result: 149 passed, 0 failed, 43 files (2026-09-06)
- `git diff --check`: passed on 2026-09-06; no Retail client or two-client evidence is available in this environment.
- Remaining release limitation: Retail validation must confirm the exact RC 3.x callback/history surface and the visual behavior of the read-only projections before a production version is published.
