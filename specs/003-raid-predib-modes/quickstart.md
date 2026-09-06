# Quickstart: Validate Raid Pre-Dib Modes

## Prerequisites

- Node.js for the Fengari test harness.
- World of Warcraft Retail for manual validation of raid events, addon messaging, and Adventure Guide navigation.
- At least one player client and one authorized officer client for recovery-sync validation.

## Automated Validation

```powershell
$files = Get-ChildItem tests -Recurse -File -Filter "*_spec.lua" |
  Sort-Object FullName |
  ForEach-Object { $_.FullName.Replace((Get-Location).Path + "\\", "").Replace("\\", "/") }
$env:DIBS_TEST_FILES = ($files -join ";")
npx --yes fengari tests/run.lua
```

Expected outcome: all tests pass with zero failures.

### Ace3 Migration Focused Validation

```powershell
$env:DIBS_TEST_FILES = 'tests/contract/sync_privacy_spec.lua;tests/integration/raid_prompt_spec.lua;tests/integration/predibs_sync_recovery_spec.lua;tests/integration/ace3_options_spec.lua;tests/integration/predibs_migration_spec.lua;tests/contract/core_independence_spec.lua'
npx --yes fengari tests/run.lua
git diff --check
```

Expected outcome: AceComm/AceSerializer is used when provided through `LibStub`; the standalone compact transport still works without Ace3; AceEvent/AceTimer covers prompt, roster, and retry dispatch; AceConfig registers the existing Dibs settings table; and Dibs SavedVariables retain their versioned layout without AceDB.

Automated evidence recorded 2026-09-05: focused Ace3 migration validation passed 13 tests in 6 files. Full Fengari validation passed 76 tests in 31 files, and `git diff --check` passed. Retail validation remains pending.

## Scenario A: Wild Open and Encounter Modes

1. As an authorized officer, select Wild Open for the active season.
2. Request a supported raid item while outside that raid.
3. Select Encounter mode.
4. Repeat outside the raid, in a dungeon, and in the raid that owns the item.

Expected outcome: Wild Open accepts the supported raid item; Encounter accepts only verified current-raid loot and explains each rejection.

## Scenario B: Officer-Offline Request Recovery

1. Ensure no authorized officer client is connected.
2. A player creates a confirmed Pre-Dib and disconnects/reconnects with the request retained.
3. Connect an authorized officer and the requesting player in the same guild raid.
4. Reconnect or trigger recovery again.

Expected outcome: the officer receives one request with the original timestamp; repeated recovery does not duplicate it; the player sees an acknowledgement only after receipt.

## Scenario C: Reminder Authority

1. In a raid, send a reminder as an authorized guild GM/officer, Raid Leader, or verified RCLootCouncil Master Looter; verify that Raid Assistant and council status alone are rejected and the ledger is unchanged.
2. Attempt the same action as an ordinary raid member.
3. Inspect the request and ledger histories.

Expected outcome: authorized reminders arrive once, unauthorized attempts are rejected, and no reminder changes request or ledger state.

## Scenario D: Opt-In Raid Prompt

1. Enable the player-local raid-entry prompt setting.
2. Enter a supported raid out of combat and accept the prompt.
3. Repeat by declining, then with the setting disabled.
4. Start a boss encounter and accept a deferred prompt after combat.

Expected outcome: acceptance opens the relevant raid or boss in the Adventure Guide when supplied by the client; decline/opt-out never opens it; combat deferral causes no UI error.

## Scenario E: Difficulty and Vault Acquisition

1. In Wild Open mode, select Normal, Heroic, then Mythic in the Adventure Guide and create a request for the same eligible item in each difficulty.
2. In Encounter mode, enter a Normal raid, select Mythic in the Adventure Guide, and create a request for eligible current-raid loot.
3. Record a Great Vault acquisition for an item and difficulty.
4. Review Player, Pre-Dibs, and Officer views and compare the ledger before and after.

Expected outcome: Wild Open requests retain the selected difficulty; Encounter requests retain the real raid difficulty; difficulty variants stay separate; the Vault item is marked acquired with source and difficulty; no Vault action changes a Dib balance, request status, or ledger transaction count.

The player may explicitly record an acquisition with `/dibs vault <itemID> [Normal|Heroic|Mythic]`. Omit the difficulty when it cannot be established; the record remains informational as `UNKNOWN`.

## Scenario F: Ace3 and Standalone Regression

1. Load Dibs with embedded Ace3 and with RCLootCouncil present; verify mode, Pre-Dib, reminder, and prompt settings appear under the RCLootCouncil options tree.
2. Trigger roster recovery and a raid-entry prompt; verify recovery and combat deferral continue to work.
3. Reload with RCLootCouncil absent; verify the Dibs core initializes and uses its own SavedVariables.
4. Reload with RCLootCouncil present but Ace3 supplied externally through `LibStub`; verify the same settings and recovery behavior.

Expected outcome: Ace3 is optional at runtime, Dibs retains ownership of `RCLootCouncil_dibsDB`, and no AceDB profile or live loot data is created or transmitted.

## Evidence Record

Record the client version, sender/receiver roles, active season mode, request IDs and acknowledgement states, and any Adventure Guide mapping unavailable in the client. Do not record private guild identities in committed artifacts.

## Acceptance Mapping

FR-001 through FR-006 are covered by Pre-Dib mode/revision contract and unit tests. FR-007 through FR-009 are covered by recovery sync integration tests. FR-010 and FR-014 are covered by reminder integration tests. FR-011 through FR-013 and FR-017 are covered by raid prompt integration tests. FR-015 is covered by officer display/migration tests. FR-016 is covered by ledger-boundary and finalized-award regression tests.
