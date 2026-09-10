# RCLootCouncil_dibs Test Plan

This document lists the remaining product decisions, manual Retail checks, and
automated regression checks required before a wider guild rollout.

## Test goals

The test campaign must demonstrate that:

- Dibs rules are the same in Standalone and RCLootCouncil modes.
- Only the verified guild GM and Officers administer Dibs policy and balances.
- The verified RCLootCouncil Master Looter can manage the RCLootCouncil loot
  session and finalize a qualifying DIB award, but cannot administer Dibs from
  that role alone.
- Finalized DIB awards consume one Dib, while ordinary, test, failed, pending,
  and duplicate awards consume none.
- Catalyst items never show a Dibs action or consume a Dib; Curios and class set
  tokens are classified separately as `TOKEN` and `TOKEN_SET`.
- Pre-Dibs, ledger history, and synchronization remain duplicate-safe and private.
- Player and Officer interfaces remain usable during normal Retail play.

## Guild decisions to record before testing

The GM and Officers should write down the answers to these questions before the
first raid test:

1. Which guild ranks are Officers for Dibs administration?
2. Which installation mode is the official guild mode: `STANDALONE`,
   `RCLootCouncil`, or `AUTO`?
3. Which seasons and rank allocations are active?
4. Which loot types and Encounter Journal sub-categories can receive a Dib?
   Record that `CATALYST` is always excluded because it is personal to the
   player; `TOKEN` (Curio) and `TOKEN_SET` (Tier Set) remain separate families.
5. Is Pre-Dib mode `WILD_OPEN` or `ENCOUNTER`?
6. Which public, Officer, and Raid Dibs announcement channels are available?
7. Are Dibs shared across Normal, Heroic, and Mythic, or tracked separately?
8. Which exceptions require an Officer/GM decision and an audit reason?
9. For the future character-eligibility feature, how are Curios, Tier Set groups,
   main/alt links, main changes, probation, and no-need declarations handled?

## Test environment

Prepare:

- one current WoW Retail client;
- the current `main` package and the current `dev` package;
- the same RCLootCouncil version used by the guild;
- one guild GM, one configured Officer, one ordinary player, and one non-admin
  Master Looter test character;
- two clients when validating synchronization and award authority;
- a test guild or a clearly identified test season so production history is not
  mixed with test data;
- access to the selected guild, Officer, and Raid Dibs channels when those tests
  are in scope.

Record the WoW build, RCLootCouncil version, Dibs version, character, guild,
rank, group role, and test date for every manual run.

## Automated checks

Run the complete Lua suite from the repository root:

```powershell
$files = Get-ChildItem tests -Recurse -File -Filter "*_spec.lua" |
  Sort-Object FullName |
  ForEach-Object { $_.FullName.Replace((Get-Location).Path + "\\", "").Replace("\\", "/") }
$env:DIBS_TEST_FILES = ($files -join ";")
node node_modules/fengari-node-cli/src/lua-cli.js tests/run.lua
git diff --check
```

Expected baseline: **205 tests pass, 0 fail, 52 files**. Run this suite after
source changes and attach the output to the test record.

## Manual test checklist

### A. Installation and first setup

- [ ] Install the stable ZIP on a clean character and confirm the addon loads.
- [ ] Install the development ZIP separately and confirm the TOC version is
      `0.3.13-dev`.
- [ ] Confirm the stable package reports the current stable version.
- [ ] Confirm SavedVariables survive `/reload`, relog, and client restart.
- [ ] Open `/dibs options` and confirm the correct Dibs options category opens.
- [ ] Create a test season, select it as active, and configure at least two rank
      allocations.
- [ ] Confirm the Overview page reports the expected season, mode, and status.

Pass criteria: the addon loads without Lua errors, the selected season and rules
survive reload, and no test changes appear in an unrelated guild's data.

### B. Authority matrix

Test each actor against each action. Record the result in chat and in the audit
history where an action is expected to succeed.

| Actor | View own data | View full history | Change settings/rules | Grant/use/refund Dibs | Finalize RCLC loot | Trigger automatic DIB debit |
| --- | --- | --- | --- | --- | --- | --- |
| Guild GM | Allow | Allow | Allow | Allow | If RCLC permits | If verified local ML and DIB award |
| Configured guild Officer | Allow | Allow | Allow | Allow | If RCLC permits | If verified local ML and DIB award |
| Verified RCLC Master Looter only | Allow | Deny | Deny | Deny | Allow through RCLC | Allow only for finalized DIB award |
| Council member only | Allow | Deny | Deny | Deny | According to RCLC | Deny unless also verified local ML |
| Raid Leader/Assistant only | Allow | Deny | Deny | Deny | According to RCLC | Deny unless also verified local ML |
| Ordinary player | Allow | Deny | Deny | Own request only | Deny unless RCLC grants it | Deny |

- [ ] Repeat the matrix in Standalone mode.
- [ ] Repeat the matrix in RCLootCouncil mode.
- [ ] Repeat after changing the guild rank of the test character.
- [ ] Repeat after changing the current Master Looter.
- [ ] Repeat with RCLootCouncil absent, disabled, degraded, and late-loaded.

Pass criteria: an unknown, stale, or unverifiable role fails closed and never
changes Dibs settings, balances, history, or mode.

### C. Standalone Dibs workflow

- [ ] GM creates a season and sets rank allocations.
- [ ] Officer changes a permitted rule and sees the change in the Officer view.
- [ ] Ordinary player views their balance and active Pre-Dibs.
- [ ] Ordinary player cannot open full Officer history or change policy.
- [ ] GM grants Dibs, the balance increases, and the transaction contains actor,
      rank, season, timestamp, quantity, and reason.
- [ ] Officer uses Dibs, the balance decreases by the configured amount.
- [ ] GM records a refund or correction as a new append-only transaction.
- [ ] Reload and rebuild the balance from the ledger.

Pass criteria: balances are deterministic, history is append-only, and a zero
allocation remains zero after reload and default setup.

### D. RCLootCouncil configuration and loot session

- [ ] Open the RCLootCouncil Master Looter options while RCLootCouncil is loaded.
- [ ] Open every RCLootCouncil tab: General, Awards, Announcements, Buttons and
      Responses, and Council.
- [ ] Confirm the DIB response appears in the default response set.
- [ ] Add and enable at least one additional response set; confirm DIB appears
      there too.
- [ ] Confirm existing responses, labels, colors, and button order are preserved.
- [ ] Fill the response list to its configured capacity; confirm DIB is not
      inserted by overwriting an active response.
- [ ] Reload the UI and reopen the options; confirm the tabs and scroll position
      remain usable.
- [ ] Open a real RCLootCouncil voting frame and confirm the Dibs column is visible.
- [ ] Confirm a candidate's current Dibs value is shown for short, realm-qualified,
      hyperlink, and GUID-backed identities.

Pass criteria: the adapter changes only the supported local response projection,
does not rewrite RCLootCouncil history, and does not create a refresh loop.

### E. Finalized award and replay tests

- [ ] Finalize a normal non-DIB award; confirm no production Dib is consumed.
- [ ] Finalize a test-mode award; confirm no production Dib is consumed.
- [ ] Send an incomplete or unverifiable award callback; confirm it is ignored.
- [ ] Finalize a qualifying DIB award as the verified local Master Looter.
- [ ] Confirm one ledger debit, one fulfilled request, the correct winner/item,
      award reference, difficulty, actor, and reason.
- [ ] Deliver the same finalized award twice; confirm no second debit.
- [ ] Reload and replay the same award; confirm the result remains idempotent.
- [ ] Change the Master Looter and replay the old callback; confirm rejection.
- [ ] Deliver an award from a non-ML client; confirm local ledger state is unchanged.

Pass criteria: only one validated finalized DIB award can consume a Dib, and the
award provenance is sufficient to audit the decision.

### F. Pre-Dibs and Encounter Journal

- [ ] Create one public Pre-Dib for a supported raid item.
- [ ] Submit the same request twice; confirm one active request and no duplicate.
- [ ] Cancel the request as its owner; confirm the state and announcement.
- [ ] Attempt to cancel another player's request; confirm rejection.
- [ ] Confirm creation and confirmation do not consume a Dib.
- [ ] Fulfill one confirmed request through a finalized qualifying award.
- [ ] Confirm a request that does not win remains active unless policy cancels it.
- [ ] Test `WILD_OPEN` outside and inside the raid.
- [ ] Test `ENCOUNTER` with a matching raid difficulty and a mismatched difficulty.
- [ ] Confirm no Dib action appears for unsupported dungeon rows.
- [ ] Confirm unknown item categories follow the configured unknown-data policy.
- [ ] Record a Great Vault acquisition and confirm it is display-only.

Pass criteria: request lifecycle, difficulty matching, announcements, and ledger
effects match the selected season policy.

### G. Synchronization and privacy

- [ ] Connect a player and an Officer in the same guild and recover an active
      request after reconnect.
- [ ] Confirm the request keeps its original creation time and current revision.
- [ ] Deliver the same recovery data twice; confirm no duplicate record.
- [ ] Attempt recovery from a non-guild character; confirm rejection.
- [ ] Attempt an acknowledgement from an ordinary player; confirm rejection.
- [ ] Confirm finalized, fulfilled, and cancelled states cannot be overwritten by
      an untrusted or stale transfer.
- [ ] Confirm live candidates, votes, responses, and loot-session fields are not
      present in sync payloads.
- [ ] Run two raid groups with separate loot sessions and confirm their Dibs state
      remains guild-scoped without sharing live RCLootCouncil data.

Pass criteria: recovery is bounded, revision-aware, duplicate-safe, and does not
disclose another player's stored requests to an ordinary member.

### H. UI, combat safety, and performance

- [ ] Open Player and Officer windows from Overview and return through their links.
- [ ] Visit every Officer page and confirm controls render in the content panel.
- [ ] Open a wrong-item/player request and confirm **Correct player** only lists
      guild-roster characters; search a short or realm-qualified name.
- [ ] Confirm **Correct item** only lists Adventure Guide raid loot. Search by
      item name, item ID, raid, boss, Dibs category, and equipment metadata;
      verify the selected link is the one submitted for correction.
- [ ] Temporarily make the Adventure Guide API unavailable, reopen the request,
      and confirm the form explains the unavailable catalogue and offers a
      refresh instead of accepting arbitrary item text.
- [ ] Change a setting in RCLootCouncil options and confirm the Officer view reads
      the same value, then repeat in the other direction.
- [ ] Scroll every long options page from top to bottom and confirm it does not
      snap back to the top.
- [ ] Open options during combat; confirm protected UI work is deferred and opens
      after combat ends.
- [ ] Open and close the voting frame repeatedly; confirm no duplicate Dibs buttons,
      columns, or frames appear.
- [ ] Observe memory usage while repeatedly opening, refreshing, and closing the
      options and voting windows.
- [ ] Run `/dibs debug report` and `/dibs debug rc`; confirm they produce output
      both with diagnostics disabled and enabled.
- [ ] Confirm debug output does not include candidate lists, votes, or responses.

Pass criteria: no visible Lua errors, no scroll reset loop, no duplicate widgets,
no unbounded memory growth during the test cycle, and no protected UI taint.

### I. Developer Mode and test isolation

- [ ] Confirm Developer Mode is disabled by default.
- [ ] Enable `/dibs dev on`, inject a valid item, and submit a DEV request.
- [ ] Confirm the request is marked as a test and is not announced publicly.
- [ ] Confirm it does not change the production ledger or SavedVariables history.
- [ ] Test invalid item IDs, item links, and uncached items.
- [ ] Disable Developer Mode and confirm test commands are rejected again.

Pass criteria: Developer Mode cannot impersonate a Master Looter, send fake
RCLootCouncil traffic, or pollute production accounting.

### J. Migration, guild isolation, and release package

- [ ] Load a SavedVariables database from the previous supported schema.
- [ ] Confirm seasons, balances, requests, and history migrate without loss.
- [ ] Switch between two guilds on one account; confirm settings and history stay
      isolated.
- [ ] Install the generated ZIP on a clean AddOns directory and verify the folder
      structure and TOC metadata.
- [ ] Verify the SHA-256 checksum before distributing the ZIP to testers.
- [ ] Test both the stable release and the development release link.

Pass criteria: migrations preserve immutable history, guild data never crosses
contexts, and the packaged addon loads from a clean installation.

## Future feature 005 tests

The Character Loot Eligibility and Main/Alt Governance feature is still a draft.
It must not be enabled for production guild decisions until these tests pass:

- [ ] Curio history is tracked across linked characters and configured difficulties.
- [ ] A character at 4/4 Curios is marked complete according to policy.
- [ ] A higher-track Mythic Curio can reopen eligibility when the policy allows it.
- [ ] Tier Set progress is evaluated per configured class/token group.
- [ ] A new low-progress member receives priority until the group reaches the next
      round.
- [ ] A finalized award counts as acquired; a proposal, vote, display, or rejected
      award does not.
- [ ] An alt declaration remains pending until GM/Officer approval.
- [ ] Approved main/alt characters share protected-loot history according to policy.
- [ ] A main change starts the configured probation period and displays its expiry.
- [ ] Unlinked characters are not blocked by name or class similarity alone.
- [ ] Guild changes, character renames, and realm transfers require re-verification.
- [ ] Every override, historical import, no-need status, and policy change is audited.

## Evidence record

For each failed or passed manual check, record:

- test ID and date;
- WoW build, Dibs version, and RCLootCouncil version;
- character, guild, rank, and raid role;
- exact steps and command/chat output;
- expected result and observed result;
- screenshot or debug report when relevant;
- whether the issue is reproducible after `/reload` and relog.

The feature is ready for wider guild testing only when the automated suite passes,
the P0 manual scenarios are complete, and every remaining failure has an owner and
an explicit decision.
