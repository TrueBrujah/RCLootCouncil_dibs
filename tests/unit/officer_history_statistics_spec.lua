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

  it("reuses season statistics until the ledger revision changes", function()
    local _, dibs = loader.load({
      wow = { guildLeader = true, guildMembers = { "Tester-Realm" } },
      withAce3 = true,
    })
    dibs.GetDB().ledger.transactions = {
      a = { transactionId = "a", seasonId = "S1", playerName = "Tester-Realm", type = "DIB_USED", amount = -1 },
    }
    local original, calls = dibs.Ledger.GetSeasonActivitySummary, 0
    dibs.Ledger.GetSeasonActivitySummary = function(...)
      calls = calls + 1
      return original(...)
    end
    local first = dibs.OfficerUI.BuildSeasonStatistics("S1")
    local second = dibs.OfficerUI.BuildSeasonStatistics("S1")
    assert_equal(1, calls)
    assert_equal(first.awards, second.awards)
    assert_equal(first.fairness.meanAwards, second.fairness.meanAwards)

    dibs.Ledger.MarkTransactionsChanged()
    dibs.OfficerUI.BuildSeasonStatistics("S1")
    assert_equal(2, calls, "ledger changes should invalidate the cached aggregate")
    dibs.Ledger.GetSeasonActivitySummary = original
  end)

  it("reuses the dashboard active Pre-Dibs count until its source revisions change", function()
    local _, dibs = loader.load({
      wow = { guildLeader = true, guildMembers = { "Tester-Realm" } },
      withAce3 = true,
    })
    local revision, reads = 1, 0
    dibs.PreDibs.GetHistoryRevisionFast = function() return revision end
    dibs.PreDibs.GetHistory = function()
      reads = reads + 1
      return {
        { seasonId = "S1", status = "pending", playerName = "Tester-Realm" },
        { seasonId = "S1", status = "fulfilled", playerName = "Tester-Realm" },
        { seasonId = "S1", status = "confirmed", playerName = "Former-Realm" },
      }
    end

    local first = dibs.OfficerUI.BuildSeasonStatistics("S1")
    local second = dibs.OfficerUI.BuildSeasonStatistics("S1")
    assert_equal(1, first.activePreDibs)
    assert_equal(first.activePreDibs, second.activePreDibs)
    assert_equal(1, reads, "unchanged request history should reuse its active count")

    revision = 2
    local updated = dibs.OfficerUI.BuildSeasonStatistics("S1")
    assert_equal(1, updated.activePreDibs)
    assert_equal(2, reads, "request history revision should invalidate the active count")
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

    local originalGetTransactions = dibs.Ledger.GetTransactions
    dibs.Ledger.GetTransactions = function()
      error("period statistics should aggregate from the ledger without copying transaction rows")
    end
    local ok, stats = pcall(dibs.OfficerUI.BuildPlayerPeriodStatistics, "S1", {
      fromDate = "2026-09-06",
      toDate = "2026-09-06",
    })
    dibs.Ledger.GetTransactions = originalGetTransactions
    assert_equal(true, ok)
    assert_equal("READY", stats.status)
    assert_equal(2, stats.count)
    assert_equal(2, #stats.rows)
    assert_equal(db, stats.database)
    assert_equal("guild-primary", stats.ledgerId)
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

    assert_equal(4, stats.seasonSummary.transactions)
    assert_equal(2, stats.seasonSummary.players)
    assert_equal(2, stats.seasonSummary.granted)
    assert_equal(3, stats.seasonSummary.used)
    assert_equal(3, stats.seasonSummary.awards)
    local originalSeasonActivitySummary = dibs.Ledger.GetSeasonActivitySummary
    dibs.Ledger.GetSeasonActivitySummary = function()
      error("Statistics page should reuse the summary from its player-activity scan")
    end
    local summaryOK, summary = pcall(dibs.OfficerUI.BuildSeasonStatistics,
      "S1", nil, false, nil, nil, nil, stats.seasonSummary)
    dibs.Ledger.GetSeasonActivitySummary = originalSeasonActivitySummary
    assert_equal(true, summaryOK)
    assert_equal(4, summary.transactions)
    assert_equal(2, summary.players)
    assert_equal(3, summary.used)
    assert_equal(3, summary.awards)
    assert_equal(2, summary.fairness.maxAwards)
    assert_equal(1, summary.fairness.minAwards)
    assert_equal(1.5, summary.fairness.meanAwards)
  end)

  it("resolves a matching season and period identity once per transaction", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    dibs.GetDB().ledger.transactions = {
      a = { transactionId = "a", seasonId = "S1", playerName = "Tester-Realm", type = "DIB_USED", amount = -1, createdAt = 10 },
    }
    local resolveCalls = 0
    local rows, count, _, _, summary = dibs.Ledger.GetSeasonPlayerActivity("S1", nil, function(name)
      resolveCalls = resolveCalls + 1
      return name
    end)
    assert_equal(1, count)
    assert_equal(1, rows["tester-realm"].awards)
    assert_equal(1, summary.awards)
    assert_equal(1, resolveCalls)
  end)

  it("returns explicit invalid-range and denied states for period statistics", function()
    local _, officerDibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local invalid = officerDibs.OfficerUI.BuildPlayerPeriodStatistics("S1", { fromDate = "2026-02-30" })
    assert_equal("INVALID_RANGE", invalid.status)

    local _, playerDibs = loader.load({
      wow = { guildLeader = false, guildRankIndices = { 3 } },
      withAce3 = true,
    })
    local denied = playerDibs.OfficerUI.BuildPlayerPeriodStatistics("S1", {})
    assert_equal("DENIED", denied.status)
    assert_equal(0, #denied.rows)
  end)
end)
