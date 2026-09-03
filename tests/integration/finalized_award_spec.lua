local loader = require("helpers.load_addon")

describe("Finalized award basic", function()
  it("creates one ledger transaction on finalized award", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local result = dibs.ProtectedActions.FinalizeAward(nil, {
      awardRef = "basic-award",
      playerName = "Tester-Realm",
      itemID = 17182,
      finalized = true,
    })
    assert_true(result.ok)
    assert_not_nil(dibs.Ledger.GetTransactionForAward("basic-award"))
  end)
end)
