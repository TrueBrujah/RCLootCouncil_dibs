# Quickstart: Validate Turnkey Guided Setup

## Prerequisites

- Run from the repository root.
- Use the existing Node/Fengari test command.
- Do not use live guild or player data in fixtures.

## Scenario 1: First-time progression setup

1. Load a fresh guild-leader fixture.
2. Open Guided Setup.
3. Confirm only Choose, Configure, and Verify are primary stages.
4. Select Progression raid.
5. Verify the preview explains changes, preserved ledger/history data, and any deferred
   GM-only work.
6. Apply once, then apply again.

Expected:

- The first apply delegates to existing installation and preset operations.
- The second apply reports ready/already-applied outcomes without duplicate records or
  unnecessary revisions.
- Verification is freshly derived from authoritative modules.

## Scenario 2: Officer with pending GM action

1. Load an Officer fixture with the GM absent.
2. Select and apply a recommended profile.

Expected:

- Officer-authorized work completes.
- GM-restricted adoption is documented as deferred.
- The result does not claim the GM action succeeded.
- The direct action identifies the appropriate Guild Configuration destination.

## Scenario 3: Blocking versus warning presentation

1. Configure a required rank without a published rule.
2. Keep RCLootCouncil unavailable and remain outside a raid.
3. Open Verify.

Expected:

- Missing required rank configuration is red and labeled Blocking.
- It includes cause, impact, guidance, and an Open Rank Rules action.
- Optional RCLootCouncil and inactive-raid context are not red.
- Selecting the primary correction opens the rank page and preserves setup progress.

## Scenario 4: Existing configured guild

1. Load an already configured guild with historical transactions.
2. Open Guided Setup and select a profile.

Expected:

- The workflow behaves as review/repair rather than destructive first-time setup.
- Existing valid configuration is identified as preserved or already ready.
- Ledger transactions and historical evidence remain unchanged.

## Focused automated validation

```powershell
$previousTestFiles = $env:DIBS_TEST_FILES
try {
    $env:DIBS_TEST_FILES = 'tests\contract\turnkey_guided_setup_contract_spec.lua;tests\integration\guided_setup_wizard_spec.lua;tests\integration\installation_wizard_spec.lua;tests\integration\setup_assistant_ui_spec.lua'
    npx.cmd --yes --package=fengari-node-cli fengari tests\run.lua
    if ($LASTEXITCODE -ne 0) { throw "Fengari failed (exit $LASTEXITCODE)." }
} finally {
    $env:DIBS_TEST_FILES = $previousTestFiles
}
git diff --check
```

## Retail checks

- Confirm the shared Midnight shell remains stable at narrow and wide window sizes.
- Confirm red, warning, success, and optional states remain distinguishable without
  relying only on color.
- Confirm long English and French guidance wraps without overlapping actions.
- Confirm correction routes return to the preserved setup stage.
