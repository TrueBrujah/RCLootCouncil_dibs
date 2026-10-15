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

After login, left-click the Dibs minimap icon to open/close the Officer view
if authorized, otherwise the Player view. Right-click opens/closes the Player view.
Show or hide it from **Player > Preferences**, or use `/dibs minimap show`
and `/dibs minimap hide`. This preference is saved per character and defaults
to shown.
It is only a shortcut: it does not grant Officer or GM permissions.

RCLootCouncil is optional. Standalone mode manages Dibs balances and requests
without a live RCLootCouncil session. RCLootCouncil mode uses RCLootCouncil for
loot voting and award finalization.

## Guild Loot Rules

On DIBS 0.8.x, the Guild Master explicitly adopts the guild's Loot Rules and
publishes later changes. Verified Officers can edit a local draft and apply the
Dibs preset, but only the GM can adopt or publish guild-wide rules. Local legacy
values are not guild authority. Raid Readiness reports one of these states:

- `GUILD_LOOT_RULES_READY`: this client has a valid published snapshot;
- `LOCAL_LEGACY_ONLY`: local rules remain a pre-adoption fallback, not a shared
  guild decision;
- `GUILD_LOOT_RULES_NOT_CONFIGURED`: the GM has not adopted the rules;
- `GUILD_LOOT_RULES_SYNC_BEHIND`: keep the last received guild snapshot active
  and allow synchronization to recover;
- `GUILD_LOOT_RULES_INCOMPATIBLE`: update DIBS before relying on shared rules;
- `UNAVAILABLE`: supported loot types could not be loaded.

Guild synchronization requires the 0.8.x family on both sides. Clients on
0.7.x must update to 0.8.x before they can synchronize with the guild.

## Rank allocations

Your starting allocation is recorded for the season. If your guild rank changes,
an Officer may explicitly top up a positive difference after review. A lower
expected allocation never removes Dibs already assigned to you, creates debt,
or changes your balance through a negative adjustment. Ask an Officer if your
starting allocation appears out of date.

## Slash commands

```text
/dibs help        Show command help
/dibs ui          Open the Player window
/dibs balance     Show your balance
/dibs requests    Open your problem reports (Reports page)
/dibs vault <link|[Name]|itemID> <LFR|Normal|Heroic|Mythic>  Record a Great Vault item manually
/dibs pre <itemID> [item name]  Create a Pre-Dib request
/dibs options     Open configuration and launch controls
```

## Balance and history

Your balance reflects recorded Dibs changes for the current guild and active
season. If your guild operates multiple teams or split raids, you can switch
between approved ledgers using the dropdown at the top of the Season Summary
table in the Player window (`/dibs`).

Dibs history can show grants, uses, refunds, adjustments, reasons,
timestamps, and award references. A rank change does not rewrite older history.

The Player window is read-only for balances and guild rules. You can submit or
cancel your own Pre-Dib requests, but a GM or authorized Officer must handle a
balance correction.

A correction never silently deletes the original event. It appends a new,
audited transaction linked to the original one.

Use the history search and filters to narrow recorded items and encounter
details, source, status, and dates. Enter dates as `YYYY-MM-DD`; start and end
dates are inclusive. Search only matches metadata that the record actually
contains, so older records without a raid or boss value will not match a
placeholder. Clearing one filter preserves the others; clearing all filters
restores the page's original scope. Search is read-only and does not expose
other players' or private Officer data.

### Independent and PUG Raids

If you participate in an independent raid run by a Master Looter using Dibs:
- You only need standard RCLootCouncil installed; the Dibs addon is not required.
- Selecting the "DIB" button in RCLootCouncil will consume one of your ephemeral session points allocated for that raid.
- Independent raids do not affect your guild ledger balance unless an officer later reconciles an award.

## Great Vault acquisitions

Open `/dibs ui` and select **Great Vault**. This read-only page shows your
recorded items across seasons in the current guild scope, newest first, with
10 entries per page. Columns show date, item, difficulty, and verification;
hover a row for its source, weekly reset, synchronization state, and evidence
explanation. Private Officer review evidence is not displayed.

The Player window can show Great Vault acquisitions with their item, source,
weekly reset, verification state, eligibility explanation, and sync state.
Use the Great Vault history filters for recorded item/source/status/date
details; dates use the inclusive `YYYY-MM-DD` format. Missing metadata does
not match a placeholder, and clearing a filter preserves the others. Results
remain limited to your current guild/character scope and never include private
Officer evidence.
Opening the Vault or viewing a reward choice is not a completed claim.
Automatic detection requires the selected claim, receipt of the same item by
your character, and the end of reward availability. Dibs must be active before
the claim; it does not reconstruct past claims from chat or bag contents.
Real-client validation remains pending. When Retail does not expose all the
required evidence, use:

```text
/dibs vault <item link | [Item Name] | itemID> <LFR | Normal | Heroic | Mythic>
```

With a shift-clicked link alone, Dibs reads that exact item's tooltip:

- **Raid** items keep their origin **Raid Finder (LFR)**, **Normal**, **Heroic** or **Mythic**, even when
  the upgrade track is higher: **Heroic** with **Myth 5/6** stays **Heroic**.
  **Raid Finder** on the **Veteran** track is recorded as **LFR**.
- **Dungeon** items (labelled **Mythic+**, or **Mythic** on the Champion track for
  Mythic 0, or **Heroic** on the Veteran track) follow their upgrade track:
  a **Heroic** dungeon reward on **Veteran** remains **Heroic**;
  **Champion** = Normal, **Hero** = Heroic,
  **Myth** = Mythic. **Mythic+** with **Hero 6/6** is Heroic.
- Tracks below **Veteran**, conflicting lines or an unexpected origin/track
  combination are not classified automatically.

Item level and Vault activity level are not used. When the client exposes no
readable classification through `C_TooltipInfo.GetHyperlink`, the difficulty is required (`Hero`
and `Myth` are accepted); without a valid
difficulty nothing is recorded and the usage is shown. `LFR` and `Raid Finder`
are accepted for manual LFR classification. A typed bracketed name,
such as `[Item Name] Heroic`, must be known to the client; otherwise use the
shift-clicked link or the item ID.

Manual records are marked `MANUAL_RECORDED` until an authorized Officer reviews
them. Vault records are evidence only and never spend, grant, or change a Dib.
History is scoped to the current guild, or to the character while unguilded.
For an exact variant, type `/dibs vault `, shift-click the item in your bags or
equipment to insert its full link. Add ` LFR`, ` Mythic`, ` Heroic`, or ` Normal` only
for an explicit manual classification; an explicitly supplied tier takes priority.
The full link preserves the item's level and bonus information.
Automatic claims use the same detection and still require completed-claim
evidence. If no difficulty can be classified (for example an Adventurer dungeon
reward), nothing is recorded automatically; use the manual command with an
explicit difficulty for review. Missing difficulty never defaults to Normal.
Existing recorded classifications are not rewritten.
The table gives item names most of the available space; long names and verification
text wrap rather than being shortened. Hover over an item to see its tooltip, or
click its name to open the item link. Dates are compact, with full timestamps in row help.
An ID-only entry loads its name but cannot establish the acquired variant. Its
clickable base-item link is marked **item reference**, not the acquired variant.
If exactly one variant with that ID is equipped or carried, an **owned preview**
shows its tooltip without changing the saved record or proving Vault origin.
Multiple different owned variants leave the exact variant unavailable.
An existing acquisition is not replaced by entering the command again.
An Officer can reject an incorrect manual entry in
Vault Review with a reason. The record and review trail are retained; this
is not permanent deletion or unrestricted player cancellation.

![Player Great Vault acquisition status](../assets/guides/screenshots/en/player/player-vault-history.png)

_Screenshot placeholder: `docs/assets/guides/screenshots/en/player/player-vault-history.png`_

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

## Review reports and follow-up (0.8.8)

The **Reports** page (`/dibs requests`) is separate from Pre-Dib
reservations, which stay on **My Dibs** (active, won, and past Pre-Dibs).
Report only your own issue and evidence. In the Player window,
open **Reports**: **Report a problem** lets you pick
a problem type (for example a wrong debit or wrong item/player), optionally the
related ledger entry, and a note. History details also offer **Report a problem
with this entry**, which preselects that entry. A report never changes your
balance; an officer reviews it and records any correction. Saving a report is not
proof that an officer received it: details show **Queued**, **Sent; awaiting
receipt**, **Received**, or **Delivery error**. Receipt never means resolved.
Offline or older clients do not receive whispers; work stays saved across reload.
Delivery requires a current verified capable coordinator and both clients online.

Officer questions allow an owner reply. Public officer replies and conclusions
appear in the same thread, without internal administrative evidence. **Retry
delivery** retries pending work; for a stale requested reply it uses the latest
received revision. Changed authority is blocked rather than silently reassigning
a possibly accepted request.

An optional follow-up can produce a local reminder while WoW is running.
Snooze postpones only this character's reminder; notifications respect your local
notification preference. Nothing runs while the client is closed.
Resolved or rejected reports may subsequently be Closed and Archived; these
stages retain the dossier and do not spend/refund a Dib.

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
