# Quickstart: Validate Independent Dibs Core

This guide validates the feature end-to-end at behavior level using local addon flows and the repository test harness.

## Prerequisites

- Repository checked out and addon source present.
- Node.js available to run the Lua harness wrapper.
- World of Warcraft Retail client available for manual smoke validation.

## 1) Automated Validation

From repository root (PowerShell):

```powershell
$files = Get-ChildItem tests -Recurse -File -Filter "*_spec.lua" |
  Sort-Object FullName |
  ForEach-Object { $_.FullName.Replace((Get-Location).Path + "\\", "").Replace("\\", "/") }
$env:DIBS_TEST_FILES = ($files -join ";")
npx --yes fengari tests/run.lua
```

Expected outcome:

- All selected tests pass.
- Transaction replay tests demonstrate idempotent no-op on duplicate transaction identifiers.

## 2) Manual Core Scenario Validation

## Scenario A: Season + rank allocations

1. Create a season.
2. Set the season as active.
3. Configure at least two different rank allocations.
4. Confirm stored values are retrievable and unchanged.

Expected outcome:

- One active season exists.
- Rank allocation values are configuration data, not fixed defaults.

## Scenario B: Derived balance from immutable ledger

1. Record seasonal allocation for a player.
2. Record grant/use/refund events for that same player.
3. Read player seasonal state.

Expected outcome:

- Remaining balance equals allocation plus ledger transaction deltas.
- Transaction history shows append-only authoritative rows.

## Scenario C: Compensating correction workflow

1. Record an intentional mistaken authoritative transaction.
2. Record a correcting compensating transaction.
3. Inspect history.

Expected outcome:

- Original row remains unchanged.
- Correction appears as a new row with actor and reason metadata.

## Scenario D: Rank-change history preservation

1. Create transactions for a player at initial rank.
2. Change the player's rank.
3. Create another transaction.
4. Inspect history.

Expected outcome:

- Historical rows preserve original rank-at-transaction-time values.
- New rows reflect updated rank context only.

## 3) Independence Validation

Confirm this feature's core workflows execute without requiring:

- RCLootCouncil
- Encounter Journal actions
- loot-session candidate/vote context
- cross-raid synchronization context

Expected outcome:

- Core seasonal accounting remains functional in standalone mode.

## 4) Artifact Cross-Checks

- Specification: [spec.md](spec.md)
- Plan: [plan.md](plan.md)
- Data model: [data-model.md](data-model.md)
- Core contract: [contracts/core-api.md](contracts/core-api.md)

## 5) Success Criteria Validation Matrix

Map each success criterion to concrete validation evidence:

- SC-001 (derived balance parity):
  - Compare each sampled player `remainingBalance` with `baseAllocation + sum(non-allocation quantity deltas)`.
  - Record sampled players and computed totals.
- SC-002 (idempotent replay):
  - Replay the same `transactionId` at least once.
  - Confirm transaction count and derived balance stay unchanged.
- SC-003 (compensating correction):
  - Preserve original mistaken row and append correction row.
  - Confirm actor and reason metadata on correction.
- SC-004 (rank-history preservation):
  - Perform rank change after historical activity.
  - Confirm old rows retain original `playerRankIndex` and new rows carry updated rank.
- SC-005 (core independence):
  - Execute core workflows with RCLootCouncil unavailable and without Encounter Journal or sync context.
  - Confirm season/rank/ledger actions still succeed.

## 6) Independence Evidence Record

When validating SC-005, capture:

1. Runtime state showing RCLootCouncil availability is `absent`.
2. Successful protected actions for `season.create`, `rank.set`, and a ledger mutation.
3. Confirmation that no cross-raid synchronization context was required.

## Validation Record

- Record date, tester, and pass/fail notes for each scenario.
- Any failure should reference the scenario label (A/B/C/D) and observed mismatch.
- Include SC-001 through SC-005 evidence links or transcript snippets.
