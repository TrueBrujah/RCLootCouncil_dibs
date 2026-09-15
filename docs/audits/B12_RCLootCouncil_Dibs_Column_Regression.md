# B12 RCLootCouncil Dibs Column Regression

## Root cause

The Dibs Voting Frame projection was initialized while the RCLootCouncil voting module existed but before its `scrollCols` table had been created. The adapter selected the native `AddColumn` path solely because the method existed. On that early call, RCLootCouncil could not resolve or insert into an uninitialized column list, so the Dibs column was not registered. The previous retry path also did not verify that `AddColumn` actually inserted the requested column.

The issue was presentation-only. The former `GetDibsColumnValue` fallback used
`RankRules.GetAllocationForPlayer` and rendered allocation/allocation (for
example `1/1`) as if it were current balance. That fallback is removed.
`Ledger.GetCanonicalPlayerDibsState` is now the single balance projection used
by both PlayerUI and RCLootCouncil. It returns the active Dibs guild season,
the roster-confirmed full Name-Realm identity, and the canonical ledger balance.

Retail can initialize `RCVotingFrame` after Dibs has first attempted its
projection, resetting `scrollCols` to the native layout. It also recreates the
lib-st instance from `RCVotingFrame:GetFrame()` and
`frame.UpdateSt()`. The adapter now reapplies the projection after those
lifecycle points and after `RCVotingFrame:Show()`. Core also directly reprobes
the idempotent integration at login, RCLootCouncil load, and world entry;
capability retry alone intentionally skips entries already marked `AVAILABLE`.
This covers the late module initialization path observed on Retail, so an item
change, candidate refresh, response refresh, or reopen cannot leave the visible
table without the column.

## Registration path

The adapter discovers the RCLootCouncil `RCVotingFrame`, waits for an initialized `scrollCols` table, and uses the supported `AddColumn(spec, target, position)` API when available. It inserts `dibsRemaining` after `response` and `dibsConvert` after `dibsRemaining`. Older compatible surfaces retain the existing `scrollCols`/lib-st fallback. Each insertion is verified by `colName`, and repeated initialization is idempotent.

The existing B08 combat boundary remains in force: projection requests during combat are queued and flushed from `PLAYER_REGEN_ENABLED`. B09 capability state remains separate. `RC_MASTER_LOOTER_UNVERIFIABLE` degrades award automation but does not suppress the read-only Voting Frame column. Unsupported award versions remain fail-closed for award evidence.

## Canonical balance contract

PlayerUI calls `Ledger.GetCanonicalPlayerDibsState(season.id, playerName)`
through `PlayerUI.GetSummary`. RCLootCouncil calls the same service from
`GetDibsColumnValue`. A unique short RCLootCouncil row name is resolved by
`Identity.ResolveRosterMember`; ambiguous, missing, or roster-unconfirmed
identities fail closed. The cell displays `balance / rank maximum` (`0/1`,
`2/3`, `5/5`). Either side can independently display `-`, and both
unavailable sides display `-`. Rank allocation is never used as a balance
substitute. The tooltip labels current balance, rank maximum, season, and
canonical player identity explicitly.

## Validation

- Focused Voting Frame regression: the late-initialization, refresh/reopen, and duplicate-prevention test passes.
- B08 UI ownership/combat tests: 3 passed, 0 failed.
- B09 capability and versioned adapter tests: 17 passed, 0 failed.
- Combined focused UI/projection tests: the new column lifecycle cases pass.
- The former baseline at `tests/integration/rclootcouncil_buttons_spec.lua:155`
	expected `2/2` after a single season allocation. That value was the known
	incorrect rank-allocation fallback, so the expectation is now the canonical
	balance `1`; the related no-history case now expects `0`.
- Focused canonical-balance, identity, PlayerUI, B08, and B09 run: 28 passed,
	0 failed.
- Static diagnostics report no errors in the changed source or test files.

## Retail revalidation

1. Deploy the addon and `/reload` with RCLootCouncil 3.23.3 Retail enabled.
2. Open the RCLootCouncil Voting Frame and confirm one `Dibs` column appears after `Response`.
3. Change loot items, refresh candidates, change responses, close/reopen the frame, and confirm the column remains present exactly once.
4. Confirm the displayed balance changes with the authoritative Dibs state and does not alter votes, responses, awards, or ledger state.
5. Repeat the open/refresh checks during combat; confirm projection is deferred until combat ends.
6. Confirm a player with canonical balance `0` shows `0/1`, and independent
   unavailable sides show `-/3` or `2/-`, never rank allocation as balance.

RCLC DIBS CANONICAL BALANCE FIX READY FOR RETAIL VALIDATION
