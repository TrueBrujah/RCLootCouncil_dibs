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
end)
