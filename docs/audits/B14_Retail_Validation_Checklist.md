# B14 First Installation Assistant Retail Validation Checklist

Status: `PENDING_MANUAL_RETAIL_VALIDATION`

Record the WoW Retail build, Dibs version, RCLootCouncil version, character,
guild, rank, date, and BugSack result for each run.

## One-client setup

- [ ] Install the clean development package on a test character.
- [ ] Open **Overview > Setup Assistant** as a verified guild GM.
- [ ] Confirm RCLootCouncil, authority, season, rank-rule, channel, and loot-type
      checks are visible and reflect the current client state.
- [ ] Confirm a normal player cannot open the administrative checklist details.
- [ ] Create a season through the assistant and confirm the change uses the
      existing protected workflow.
- [ ] Apply each supported installation mode and confirm the displayed state
      refreshes from current configuration.

## Safety and degradation

- [ ] Run the local dry-run outside combat and confirm the explicit local result.
- [ ] Confirm the dry-run does not create a ledger transaction, loot award,
      chat announcement, addon-message transfer, or RCLootCouncil mutation.
- [ ] Repeat the dry-run during combat and confirm the UI remains safe and
      reports the bounded unavailable/deferred result.
- [ ] Repeat with RCLootCouncil absent, disabled, and degraded; confirm
      standalone readiness remains distinct from live integration readiness.
- [ ] Refresh, reload, and reopen the assistant; confirm completion is derived
      from current state and does not require a new persisted wizard flag.
- [ ] Review BugSack and the default chat frame for new Dibs-attributable errors.

## Exit rule

Do not mark this checklist complete from Fengari results alone. Attach the
Retail observations and screenshots/log references before closing feature 014
T015.
