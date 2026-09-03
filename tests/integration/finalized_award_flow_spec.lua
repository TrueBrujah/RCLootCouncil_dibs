local loader = require("helpers.load_addon")

describe("Finalize award flow", function()
  it("does not consume on non-final status", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local before = #dibs.Ledger.GetAllTransactions()

    local result = dibs.ProtectedActions.FinalizeAward(nil, {
      awardRef = "r1",
      playerName = "Tester-Realm",
      itemID = 19019,
      sourceStatus = "pending",
    })

    assert_false(result.ok)
    local after = #dibs.Ledger.GetAllTransactions()
    assert_equal(before, after)
  end)

  it("consumes once and fulfills confirmed predib", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local request = dibs.PreDibs.Create("Tester-Realm", 19019, "Item", dibs.GetCurrentSeasonId())
    dibs.PreDibs.Confirm(request.requestId)

    local first = dibs.ProtectedActions.FinalizeAward(nil, {
      awardRef = "award-1",
      playerName = "Tester-Realm",
      itemID = 19019,
      sourceStatus = "awarded",
      finalized = true,
    })
    assert_true(first.ok)

    local second = dibs.ProtectedActions.FinalizeAward(nil, {
      awardRef = "award-1",
      playerName = "Tester-Realm",
      itemID = 19019,
      sourceStatus = "awarded",
      finalized = true,
    })
    assert_true(second.ok)
    assert_equal(first.value.transactionId, second.value.transactionId)

    local fulfilled = dibs.PreDibs.GetHistory()[1]
    assert_equal("fulfilled", fulfilled.status)
  end)
end)
