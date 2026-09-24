local loader = require("helpers.load_addon")

describe("Officer history filters and fairness statistics", function()
  it("keeps roster members visible when another member already has an assignment", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Other-Realm" } }, withAce3 = true })
    local db = dibs.GetDB()
    db.ledger.transactions = {
      a = { transactionId = "a", seasonId = "S1", playerName = "Tester-Realm", type = "DIB_GRANTED", source = "automatic_rank_assignment", amount = 1 },
    }
    local details = dibs.OfficerUI.BuildAutomaticAllocationDetails("S1")
    assert_equal(2, #details.rows)
    assert_true(string.find(details.allocations[1] .. details.allocations[2], "Other-Realm", 1, true) ~= nil)
  end)

  it("filters ledger actions by structured fields", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Other-Realm" } }, withAce3 = true })
    local db = dibs.GetDB()
    db.ledger.transactions = {
      a = { transactionId = "a", seasonId = "S1", playerName = "Tester-Realm", type = "DIB_USED", source = "loot", createdAt = 10, amount = -1 },
      b = { transactionId = "b", seasonId = "S1", playerName = "Other-Realm", type = "DIB_USED", source = "loot", createdAt = 20, amount = -1 },
    }
    local page = dibs.OfficerUI.GetPagedView("actions", "S1", 1, 10, { playerName = "Tester-Realm", source = "loot" })
    assert_equal(1, page.totalCount)
    assert_true(string.find(page.lines[1], "Tester-Realm", 1, true) ~= nil)
  end)

  it("reports descriptive award distribution metrics", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Other-Realm" } }, withAce3 = true })
    local db = dibs.GetDB()
    db.ledger.transactions = {
      a = { transactionId = "a", seasonId = "S1", playerName = "Tester-Realm", type = "DIB_USED", amount = -1 },
      b = { transactionId = "b", seasonId = "S1", playerName = "Tester-Realm", type = "DIB_USED", amount = -1 },
      c = { transactionId = "c", seasonId = "S1", playerName = "Other-Realm", type = "DIB_USED", amount = -1 },
    }
    local stats = dibs.OfficerUI.BuildSeasonStatistics("S1")
    assert_equal(2, stats.fairness.maxAwards)
    assert_equal(1, stats.fairness.minAwards)
    assert_equal(1.5, stats.fairness.meanAwards)
    assert_equal(1.5, stats.fairness.medianAwards)
  end)
end)