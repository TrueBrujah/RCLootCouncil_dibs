local loader = require("helpers.load_addon")

describe("Pre-Dib feature acceptance", function()
  it("covers request, policy, authority, and standalone boundaries", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local before = #dibs.Ledger.GetAllTransactions()
    local request = dibs.PreDibs.CreatePublic("Tester-Realm", 21051, "Item 21051", seasonId, "acceptance")

    assert_not_nil(request)
    assert_equal(1, #dibs.PreDibs.GetRequestsForItem(21051))
    assert_true(dibs.EncounterJournal.IsSubCategoryAllowed("UNKNOWN"))
    assert_false(dibs.EncounterJournal.IsSubCategoryAllowed("RECIPE"))
    assert_false(dibs.EncounterJournal.IsSubCategoryAllowed("CATALYST"))
    assert_equal("absent", dibs.RCLootCouncil.GetAvailability())
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)

  it("keeps finalized award accounting idempotent", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local request = dibs.PreDibs.Create("Tester-Realm", 21052, "Item 21052", dibs.GetCurrentSeasonId())
    dibs.PreDibs.Confirm(request.requestId)

    local first = dibs.ProtectedActions.FinalizeAward(nil, {
      awardRef = "acceptance-award-1",
      playerName = "Tester-Realm",
      itemID = 21052,
      sourceStatus = "awarded",
      finalized = true,
    })
    local second = dibs.ProtectedActions.FinalizeAward(nil, {
      awardRef = "acceptance-award-1",
      playerName = "Tester-Realm",
      itemID = 21052,
      sourceStatus = "awarded",
      finalized = true,
    })

    assert_true(first.ok)
    assert_true(second.ok)
    assert_equal(first.value.transactionId, second.value.transactionId)
    assert_equal("fulfilled", request.status)
  end)
end)
