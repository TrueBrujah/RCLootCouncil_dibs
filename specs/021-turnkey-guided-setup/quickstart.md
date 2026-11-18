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

Progressive setup validation on 2026-11-15: **262/262 tests on 16 integration
suites** under Fengari, Lua 5.4.6 and native Lua 5.1.5. Independent review of the
four new suites: **30/30 under all three runtimes**, plus an independent **15/15**
contextual-help regression check under each (45 distinct QA cases). Full source compilation:
**111/111 Lua 5.1.5**. Documentation Generate/Check and addon load-file preflight
pass. These are targeted results, not a new full-repository test run or Retail
certification. The earlier global red baseline remains historical evidence.

- New progressive setup scenarios are recorded in
  [N01–N07](../../docs/audits/0.8.12-TESTS-RETAIL-FR.md): N01 is partially observed
  in user screenshots; remaining checks are **NON TESTÉ**. Fresh startup only Guided
  Setup, safe member waiting, custom foundation initialization, gradual route
  availability, guild-neutral text and named schedule controls. Existing history
  and correction access must remain available on upgrades.
- Focused new coverage: `guided_setup_navigation_access_spec.lua`,
  `guided_setup_officer_navigation_spec.lua`, `seasonal_roster_guild_language_spec.lua`
  and `seasonal_roster_schedule_editor_spec.lua`, in `tests/integration/`.
  Existing Wizard, installation, PlayerUI and Officer navigation suites remain
  relevant, with explicit configured-guild fixtures for isolated page tests.

Inline season preparation follow-up: **290/290 on 18 integration suites under
each runtime**, adding `guided_setup_season_draft_spec.lua` (18 cases) and
`guided_setup_season_draft_ui_spec.lua` (10 cases) to the prior selection.
Independent QA: **80/80 per runtime**, including those 28 new cases, eight
additional temporary QA scenarios and 44 Wizard/navigation regressions. Source
compilation stays **111/111 Lua 5.1.5**, documentation has zero errors (ten legacy
orphan help warnings), and addon load preflight covers 120 required files.
Test the optional form, real calendar, narrow scrolling and repeat application
under N07 after redeployment; no Retail certification or full-suite claim.

- Confirm the shared Midnight shell remains stable at narrow and wide window sizes.
- Confirm red, warning, success, and optional states remain distinguishable without
  relying only on color.
- Confirm long English and French guidance wraps without overlapping actions.
- Confirm correction routes return to the preserved setup stage.
