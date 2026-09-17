# Player Guide

This guide covers everyday use of RCLootCouncil_dibs for guild players.

## Purpose and limits

Dibs is a guild-controlled, seasonal loot-priority ledger. It displays your
balance, stores Pre-Dib requests, and records a debit when an eligible finalized
award passes the configured checks.

Dibs does not replace RCLootCouncil voting, guarantee an item win, spend a Dib
when a request is created, or let players change the ledger or guild policy.
Live candidates, votes, and responses are not shared between raid groups.

> **Authority warning:** an RCLootCouncil Master Looter is not automatically a
> Dibs administrator. Guild Master and verified Officer permissions control
> policy and corrections.

![Player window showing balance and active season](../assets/guides/screenshots/en/player/player-overview.png)

_Screenshot placeholder: `docs/assets/guides/screenshots/en/player/player-overview.png`_

## Installation and first launch

1. Install the `RCLootCouncil_dibs` folder under `Interface/AddOns/`.
2. Enable it on the character-selection AddOns screen.
3. Run `/reload` after installing or updating.
4. Ask a GM or Officer which season and loot policy are active.
5. Run `/dibs ui` and check the season, balance, requests, and integration status.

RCLootCouncil is optional. Standalone mode manages Dibs balances and requests
without a live RCLootCouncil session. RCLootCouncil mode uses RCLootCouncil for
loot voting and award finalization.

## Slash commands

```text
/dibs help        Show command help
/dibs ui          Open the Player window
/dibs balance     Show your balance
/dibs requests    Show your Pre-Dib requests
/dibs pre <itemID> [item name]  Create a Pre-Dib request
/dibs options     Open configuration and launch controls
```

## Balance and history

Your balance is calculated from ledger transactions for the active season. The
history can include grants, uses, refunds, adjustments, reasons, timestamps,
and award references. A rank change does not rewrite older transactions.

A correction never silently deletes the original event. It appends a new,
audited transaction linked to the original one.

## Pre-Dib workflow

A Pre-Dib is a request, not an award and not a debit.

1. Open the Adventure Guide or an eligible RCLootCouncil loot row.
2. Select an eligible item.
3. Choose the Dibs or Pre-Dib action.
4. Check the item, difficulty, season, and request mode.
5. Confirm the request.

The same active request for the same player, item, season, and difficulty is not
duplicated. In `ENCOUNTER` mode, the matching raid context is required. In
`WILD_OPEN` mode, requests may be allowed outside the raid according to policy.

![Player Pre-Dib action](../assets/guides/screenshots/en/player/player-loot-action.png)

_Screenshot placeholder: `docs/assets/guides/screenshots/en/player/player-loot-action.png`_

### Request statuses

- `pending`: created but not confirmed;
- `confirmed`: active and confirmed;
- `invalidated`: rejected by policy or invalid data;
- `fulfilled`: linked to a finalized qualifying award;
- `cancelled`: cancelled by the owner or policy.

You can cancel your own active request. You cannot cancel another player's
request. A request that did not win may remain active until you cancel it or the
policy closes it.

## Drop-Dib workflow

A Drop-Dib is the debit associated with a finalized eligible award.

1. The item appears in the loot session.
2. The configured voting workflow is used.
3. The verified Master Looter finalizes the award in RCLootCouncil, when enabled.
4. Dibs validates the item, winner, response, authority, and session evidence.
5. One ledger debit is recorded if all checks pass.

A request, a vote, a test award, an incomplete callback, a duplicate callback,
a personal item, or an excluded category must not reduce production balance.

## Errors and troubleshooting

- **No active season:** ask a GM or Officer to activate a season.
- **Item not eligible:** the item category is excluded by policy.
- **Pre-Dibs disabled:** the GM disabled the feature.
- **Raid context required:** `ENCOUNTER` mode requires the matching raid.
- **Integration unavailable:** RCLootCouncil is absent, disabled, or not ready;
  local Dibs views may still work.
- **Permission denied:** administration is restricted to GM and verified Officers.
- **Award not finalized:** a proposal or vote is not enough for a debit.
- **In combat:** protected windows may open after combat ends.

If a balance looks wrong, record the item, player, timestamp, difficulty, and
RCLootCouncil reference, then contact an Officer. Do not edit SavedVariables.

## FAQ

### Why is my request missing?

Check the active season, item category, difficulty, request mode, and whether
`ENCOUNTER` mode requires you to be inside the matching raid.

### Why did my balance not decrease?

The award may be pending, test, invalid, duplicated, or excluded. Ask an Officer
to inspect the award evidence and ledger history.

### Can I change my own balance?

No. Use the guild's Officer review process for a correction.

### What happens without RCLootCouncil?

Standalone Dibs can continue to display balances and manage requests. Features
that require RCLootCouncil award evidence remain unavailable.

### What do `Unavailable` and `Blocked` mean?

`Unavailable` usually means optional context is missing. `Blocked` means a
security or configuration condition prevents the action. Do not bypass either
state; ask a GM or Officer to verify the setup.
