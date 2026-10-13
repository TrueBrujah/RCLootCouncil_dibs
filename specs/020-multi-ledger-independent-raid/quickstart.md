# Quickstart: Multi-Ledger Management and Independent Raid Sessions

**Feature**: `020-multi-ledger-independent-raid`
**Date**: 2026-10-12
**Status**: Draft

This quickstart guides developers through verifying the three core workflows introduced in feature 020:
1. Multi-Ledger creation, GM approval, and active ledger switching.
2. Officer empowerment during guided setup without GM blockers.
3. Independent local raid session operation with zero network sync and vanilla RCLootCouncil voting.

---

## Prerequisites

1. PowerShell 7+ on Windows.
2. Node.js environment with `npx` available for Fengari CLI execution.
3. Working directory set to repository root: `c:\Users\yc58\OneDrive\Documents\GitHub\RCLootCouncil_dibs`.

---

## Scenario 1: Multi-Ledger Creation & Active Ledger Switching

### Objective
Verify that an Officer can propose a second guild ledger, the GM can approve it, and switching between ledgers displays distinct balances without data bleed.

### Automated Test Execution
Run the dedicated multi-ledger integration suite:

```powershell
$previousTestFiles = $env:DIBS_TEST_FILES
try {
    $env:DIBS_TEST_FILES = 'tests\unit\multi_ledger_spec.lua;tests\integration\multi_ledger_sync_spec.lua'
    npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua
} finally {
    $env:DIBS_TEST_FILES = $previousTestFiles
}
```

### Expected Outcome
- Test 1: `Dibs.MultiLedger.ProposeLedger` creates `LDR-...` in `PROPOSED` state.
- Test 2: Non-GM attempt to `ApproveLedger` fails with `GUILD_MASTER_REQUIRED`.
- Test 3: GM `ApproveLedger` succeeds, records governance record, and transitions state to `APPROVED`.
- Test 4: Appending transaction to `LDR-...` does not modify balances in `guild-primary`.
- Test 5: `SetActiveLedger` updates `GetActiveLedgerId()` and emits `DIBS_ACTIVE_LEDGER_CHANGED`.

---

## Scenario 2: Officer Setup and Guided Workflow

### Objective
Verify that an Officer can execute setup workflows, configure rank rules, and prepare raid settings without encountering `GUILD_MASTER_REQUIRED` blockers.

### Automated Test Execution
Run the installation and permissions suite:

```powershell
$previousTestFiles = $env:DIBS_TEST_FILES
try {
    $env:DIBS_TEST_FILES = 'tests\unit\installation_spec.lua;tests\unit\permissions_spec.lua'
    npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua
} finally {
    $env:DIBS_TEST_FILES = $previousTestFiles
}
```

### Expected Outcome
- `Installation.GetStatus(officerActor)` reports no fatal `GUILD_MASTER_REQUIRED` blocker in `blockers`.
- `Installation.Initialize(officerActor)` succeeds with `reasonCode = "PROPOSAL_CREATED"`.
- `Dibs.Permissions.Can("season.create", officerActor)` returns `true`.

---

## Scenario 3: Independent Raid Session (Zero Network Traffic & Local Loot)

### Objective
Verify that an ad-hoc Master Looter can run a local session, award an item when a raider votes "DIB", consume session points, and verify that 0 messages are sent to guild chat.

### Automated Test Execution
Run the independent raid test suite:

```powershell
$previousTestFiles = $env:DIBS_TEST_FILES
try {
    $env:DIBS_TEST_FILES = 'tests\unit\independent_raid_spec.lua;tests\integration\rc_independent_award_spec.lua'
    npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua
} finally {
    $env:DIBS_TEST_FILES = $previousTestFiles
}
```

### Expected Outcome
- `Dibs.IndependentRaid.StartSession("Pug Raid", 1)` initializes `db.independentSessions`.
- `RCMLAwardSuccess` with response `"DIB"` reduces attendee balance from 1 to 0.
- `Sync.Send` spy records 0 calls to channel `"GUILD"` or `"OFFICER"`.
- Official guild ledger balances remain identical before and after the session.
