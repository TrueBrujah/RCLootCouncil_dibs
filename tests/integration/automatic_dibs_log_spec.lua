local loader = require("helpers.load_addon")

describe("Automatic Dibs Officer log", function()
  it("shows automatic rank allocations and roster reconciliation", function()
    local _, dibs = loader.load({
      wow = {
        guildLeader = true,
        guildMembers = { "Tester-Realm", "Alice-Realm" },
        guildRankIndices = { [1] = 0, [2] = 3 },
      },
    })
    local seasonId = dibs.GetCurrentSeasonId()

    local automatic = dibs.Ledger.RegisterSeasonAllocation("Alice-Realm", seasonId, 1, "Promotion to Member", {
      action = "rank.reconcile", actor = "Tester-Realm", source = "automatic_rank_assignment",
      rankIndex = 3, rankName = "Member",
    })
    assert_not_nil(automatic)
    local manual = dibs.Ledger.RegisterSeasonAllocation("Alice-Realm", seasonId, 1, "Officer correction", {
      action = "rank.reconcile", actor = "Tester-Realm", source = "rank_reconciliation",
    })
    assert_not_nil(manual)

    local details = dibs.OfficerUI.BuildAutomaticAllocationDetails(seasonId)
    assert_equal(3, #details.allocations)
    assert_true(string.find(details.allocations[1], "Alice-Realm", 1, true) ~= nil)
    assert_true(string.find(details.allocations[1], "Member", 1, true) ~= nil)
    assert_true(string.find(details.allocations[1], "+1", 1, true) ~= nil)

    local page = dibs.OfficerUI.GetPagedView("automaticDibs", seasonId, 1, 8)
    assert_equal("Automatic Dibs", page.title)
    assert_equal(3, page.totalCount)
    assert_equal(3, #page.rows)
    assert_true(page.rows[1].playerName ~= nil)
  end)

  it("keeps the current page across a same-tab refresh instead of resetting to page 1", function()
    local members, ranks = { "Tester-Realm" }, { [1] = 0 }
    for i = 1, 10 do
      members[#members + 1] = "Member" .. i .. "-Realm"
      ranks[#members] = 3
    end
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true, guildMembers = members, guildRankIndices = ranks } })
    local frame = dibs.OfficerUI.CreateWindow("automaticDibs")
    assert_equal(1, frame.ledgerPage)

    frame.ledgerPage = 2
    frame:Refresh()
    assert_equal(2, frame.ledgerPage)

    frame:ActivateRoute("history")
    assert_equal(1, frame.ledgerPage)
  end)
end)