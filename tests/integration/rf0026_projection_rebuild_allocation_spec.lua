local clients = require("helpers.canonical_operation_clients")

-- RF-0026 regression suite.
--
-- RF-0026 - "Ledger : la reconstruction des projections diverge du chemin
-- incremental sur les allocations de saison"
-- (docs/code-audit/INDEX.md#rf-0026).
--
-- The incremental path (`appendValidated`) treats a `SEASON_ALLOCATION`
-- transaction specially: it adds `tx.amount` to `state.allocation` and
-- `getCurrentBalance` excludes `SEASON_ALLOCATION` rows from the balance
-- sum, so a season allocation raises the allocation and the balance by
-- the same amount exactly once.
--
-- The rebuild path (`RebuildLedgerProjections` -> `applyRow`) did not:
--   memberState.allocation = memberState.allocation + (tonumber(transaction.allocation) or 0)
--   memberState.balance    = memberState.balance + amount
-- A transaction carries no `allocation` field, so the allocation stayed at
-- 0 and the allocation amount was added to the balance a second time.
--
-- Consequence: rebuilding the projections of a ledger that holds a
-- season allocation produced a different allocation and a different
-- balance than the incremental path, so a reload or a recovery could
-- change a player's Dib balance.

local function setup()
  local world = clients.new()
  local coordinator = world:Load("Coordinator-Realm")
  world:ActivateV2()
  return world, coordinator
end

describe("RF-0026 rebuilding projections matches the incremental path", function()
  it("keeps the allocation and the balance identical after a rebuild", function()
    local world, coordinator = setup()
    local dibs = coordinator.dibs
    local seasonId = dibs.GetCurrentSeasonId()
    local playerName = world.names[2]

    -- Record a season allocation through the ordinary service path.
    local allocation = dibs.Ledger.RegisterSeasonAllocation(playerName, seasonId, 4, "RF-0026 test allocation")
    assert_not_nil(allocation, "the season allocation was not recorded")

    local balanceBefore = dibs.Ledger.GetBalance(playerName, seasonId, "guild-primary")
    local stateBefore = dibs.Ledger.GetPlayerState(playerName, seasonId, "guild-primary")
    local allocationBefore = tonumber(stateBefore.allocation) or 0
    assert_equal(4, allocationBefore, "the allocation was not stored in the player state")
    -- The balance carries the allocation plus the Dib granted during the
    -- V2 activation.
    assert_true(balanceBefore >= 4, "the balance did not reflect the season allocation")

    local rebuilt = dibs.Ledger.RebuildLedgerProjections("guild-primary")
    assert_true(rebuilt.rebuilt, tostring(rebuilt.reasonCode))

    local balanceAfter = dibs.Ledger.GetBalance(playerName, seasonId, "guild-primary")
    local stateAfter = dibs.Ledger.GetPlayerState(playerName, seasonId, "guild-primary")

    assert_equal(allocationBefore, tonumber(stateAfter.allocation) or 0,
      "the rebuild changed the season allocation")
    assert_equal(balanceBefore, balanceAfter,
      "the rebuild changed the balance")
  end)

  it("keeps a grant unchanged after a rebuild", function()
    local world, coordinator = setup()
    local dibs = coordinator.dibs
    local seasonId = dibs.GetCurrentSeasonId()
    local playerName = world.names[2]

    -- `ActivateV2` already grants one Dib to this player.
    local balanceBefore = dibs.Ledger.GetBalance(playerName, seasonId, "guild-primary")
    local stateBefore = dibs.Ledger.GetPlayerState(playerName, seasonId, "guild-primary")
    local allocationBefore = tonumber(stateBefore.allocation) or 0

    local rebuilt = dibs.Ledger.RebuildLedgerProjections("guild-primary")
    assert_true(rebuilt.rebuilt, tostring(rebuilt.reasonCode))

    assert_equal(allocationBefore, tonumber(dibs.Ledger.GetPlayerState(playerName, seasonId, "guild-primary").allocation) or 0,
      "the rebuild changed the allocation")
    assert_equal(balanceBefore, dibs.Ledger.GetBalance(playerName, seasonId, "guild-primary"),
      "the rebuild changed the balance")
  end)

  it("does not double count a season allocation across repeated rebuilds", function()
    local world, coordinator = setup()
    local dibs = coordinator.dibs
    local seasonId = dibs.GetCurrentSeasonId()
    local playerName = world.names[2]

    dibs.Ledger.RegisterSeasonAllocation(playerName, seasonId, 4, "RF-0026 test allocation")
    local balanceBefore = dibs.Ledger.GetBalance(playerName, seasonId, "guild-primary")

    dibs.Ledger.RebuildLedgerProjections("guild-primary")
    dibs.Ledger.RebuildLedgerProjections("guild-primary")

    assert_equal(balanceBefore, dibs.Ledger.GetBalance(playerName, seasonId, "guild-primary"),
      "repeated rebuilds changed the balance")
  end)
end)
