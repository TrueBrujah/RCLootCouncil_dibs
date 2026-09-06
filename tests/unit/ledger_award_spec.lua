local loader = require("helpers.load_addon")

describe("Ledger award index", function()
  it("stores and resolves award reference", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local tx = dibs.Ledger.AddTransaction({
      transactionId = "tx-award-1",
      type = "DIB_USED",
      playerName = "Tester-Realm",
      seasonId = dibs.GetCurrentSeasonId(),
      amount = -1,
      awardRef = "award-ref-1",
    })
    assert_not_nil(tx)
    local resolved = dibs.Ledger.GetTransactionForAward("award-ref-1")
    assert_equal("tx-award-1", resolved.transactionId)
  end)

  it("rejects invalid quantity signs and keeps the two balance projections identical", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local before = dibs.Ledger.GetBalance("Tester-Realm", seasonId)
    assert_nil(dibs.Ledger.Use("Tester-Realm", -2, "invalid", "test", seasonId))
    assert_equal(before, dibs.Ledger.GetBalance("Tester-Realm", seasonId))

    local state = dibs.Ledger.GetPlayerSeasonState(seasonId, "Tester-Realm")
    assert_equal(dibs.Ledger.GetBalance("Tester-Realm", seasonId), state.remainingBalance)
  end)

  it("preserves an explicit zero rank allocation during default setup", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.RankRules.SetAllocation(seasonId, 0, "Guild Master", 0)
    dibs.ApplyDefaultRules()
    assert_equal(0, dibs.RankRules.GetAllocation(seasonId, 0))
  end)
end)
