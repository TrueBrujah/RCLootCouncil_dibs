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

  it("summarizes player activity inside an inclusive period without ranking players", function()
    local _, dibs = loader.load({
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Other-Realm" } },
      withAce3 = true,
    })
    _G.time = function(dateParts)
      if dateParts then
        return ((dateParts.year * 400) + (dateParts.month * 32) + dateParts.day) * 86400
      end
      return 1700000000
    end
    local dayStart = _G.time({ year = 2026, month = 9, day = 6 })
    local db = dibs.GetDB()
    db.ledger.transactions = {
      a = { transactionId = "a", seasonId = "S1", playerName = "Tester-Realm", type = "DIB_USED", amount = -1, createdAt = dayStart + 100 },
      b = { transactionId = "b", seasonId = "S1", playerName = "Tester-Realm", type = "DIB_GRANTED", amount = 2, createdAt = dayStart + 200 },
      c = { transactionId = "c", seasonId = "S1", playerName = "Other-Realm", type = "DIB_USED", amount = -1, createdAt = dayStart + 86400 + 100 },
      d = { transactionId = "d", seasonId = "S1", playerName = "Other-Realm", type = "DIB_USED", amount = -1 },
    }

    local stats = dibs.OfficerUI.BuildPlayerPeriodStatistics("S1", {
      fromDate = "2026-09-06",
      toDate = "2026-09-06",
    })
    assert_equal("READY", stats.status)
    assert_equal(2, #stats.rows)
    local testerStats, otherStats
    for _, row in ipairs(stats.rows) do
      if row.playerName == "Tester-Realm" then testerStats = row end
      if row.playerName == "Other-Realm" then otherStats = row end
    end
    assert_not_nil(testerStats)
    assert_not_nil(otherStats)
    assert_equal(2, testerStats.transactions)
    assert_equal(1, testerStats.awards)
    assert_equal(2, testerStats.grantedDibs)
    assert_equal(1, testerStats.usedDibs)
    assert_equal(true, otherStats.partial)
    assert_equal(0, otherStats.awards)
    assert_equal(1, stats.undatedExcluded)
    assert_nil(stats.fairnessScore)
    assert_nil(stats.ranking)
  end)

  it("returns explicit invalid-range and denied states for period statistics", function()
    local _, officerDibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local invalid = officerDibs.OfficerUI.BuildPlayerPeriodStatistics("S1", { fromDate = "2026-02-30" })
    assert_equal("INVALID_RANGE", invalid.status)

    local _, playerDibs = loader.load({ wow = { guildLeader = false }, withAce3 = true })
    local denied = playerDibs.OfficerUI.BuildPlayerPeriodStatistics("S1", {})
    assert_equal("DENIED", denied.status)
    assert_equal(0, #denied.rows)
  end)
end)