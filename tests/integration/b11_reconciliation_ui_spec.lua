local loader = require("helpers.load_addon")

local function setup(history, wow)
  local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = history })
  local _, dibs = loader.load({ rclootcouncil = rc, wow = wow or { guildLeader = true }, withAce3 = true })
  return rc, dibs
end

describe("B11f reconciliation UI", function()
  local originalTime

  after_each(function()
    if originalTime then
      _G.time = originalTime
      originalTime = nil
    end
  end)

  it("projects a guided search summary and bounded candidate review", function()
    local _, dibs = setup({
      ["Tester-Realm"] = {
        { id = "dib-1", itemID = 19019, lootWon = "item:19019", response = "DIB", status = "awarded", timestamp = 1700000100, difficultyName = "Heroic" },
        { id = "need-1", itemID = 19020, lootWon = "item:19020", response = "Need", status = "awarded", timestamp = 1700000200 },
      },
    })
    local search = dibs.LogsUI.SearchHistory({ seasonId = dibs.GetCurrentSeasonId(), aliases = { "DIB" }, limit = 20 })
    assert_true(search and search.ok)
    assert_equal("review", search.view.stage)
    assert_equal(2, search.view.summary.rowsScanned)
    assert_equal(1, search.view.summary.possibleDibs)
    assert_equal(1, search.view.summary.ignored)
    assert_equal(0, search.view.summary.ambiguous)
    assert_equal(1, #search.view.candidates)
    local candidate = search.view.candidates[1]
    assert_equal("Tester-Realm", candidate.winner)
    assert_equal("Heroic", candidate.difficulty)
    assert_equal("DIB", candidate.response)
    assert_true(candidate.evidenceSummary ~= "")
    assert_nil(candidate.technical)

    local detail = dibs.LogsUI.ReviewCandidate(search.session.sessionId, candidate.candidateId)
    assert_true(detail and detail.ok)
    assert_equal("DIB", detail.view.response)
    assert_not_nil(detail.view.technical)
    assert_equal("history:dib-1", detail.view.technical.historyRef)
  end)

  it("filters RCLootCouncil preview rows by recorded item, winner, encounter, source, and inclusive date", function()
    originalTime = _G.time
    _G.time = function(value) return os.time(value) end
    local matchTime = time({ year = 2026, month = 4, day = 12, hour = 12 })
    local otherDay = time({ year = 2026, month = 4, day = 13, hour = 12 })
    local historyDB = {
      ["Tester-Realm"] = {
        {
          id = "matching-award", playerName = "Tester-Realm", itemID = 19019,
          itemName = "Midnight Blade", lootWon = "item:19019", response = "DIB",
          status = "awarded", timestamp = matchTime, instanceName = "Nerub-ar Palace",
          encounterName = "Sarkareth", source = "Guild Archive",
        },
        {
          id = "different-boss", playerName = "Tester-Realm", itemID = 19019,
          itemName = "Midnight Blade", lootWon = "item:19019", response = "DIB",
          status = "awarded", timestamp = matchTime, instanceName = "Nerub-ar Palace",
          encounterName = "Another Boss", source = "Guild Archive",
        },
        {
          id = "outside-date", playerName = "Tester-Realm", itemID = 19019,
          itemName = "Midnight Blade", lootWon = "item:19019", response = "DIB",
          status = "awarded", timestamp = otherDay, instanceName = "Nerub-ar Palace",
          encounterName = "Sarkareth", source = "Guild Archive",
        },
        {
          id = "missing-date", playerName = "Tester-Realm", itemID = 19019,
          itemName = "Midnight Blade", lootWon = "item:19019", response = "DIB",
          status = "awarded", instanceName = "Nerub-ar Palace",
          encounterName = "Sarkareth", source = "Guild Archive",
        },
        {
          id = "missing-source", playerName = "Tester-Realm", itemID = 19019,
          itemName = "Midnight Blade", lootWon = "item:19019", response = "DIB",
          status = "awarded", timestamp = matchTime, instanceName = "Nerub-ar Palace",
          encounterName = "Sarkareth",
        },
      },
    }
    local _, dibs = setup(historyDB)
    _G.time = function(value) return os.time(value) end
    local search = dibs.LogsUI.SearchHistory({
      seasonId = dibs.GetCurrentSeasonId(), aliases = { "DIB" }, limit = 20,
      query = "Midnight", playerName = "Tester", item = "19019",
      raid = "Nerub-ar", boss = "Sarkareth", status = "awarded",
      source = "Guild Archive", fromDate = "2026-04-12", toDate = "2026-04-12",
    })
    assert_true(search.ok)
    assert_equal(1, #search.candidates)
    assert_equal("history:matching-award", search.candidates[1].candidateId)
    assert_equal(1, search.summary.rowsScanned)
    assert_equal("DIB", historyDB["Tester-Realm"][1].response)

    local missingSource = dibs.LogsUI.SearchHistory({
      seasonId = dibs.GetCurrentSeasonId(), aliases = { "DIB" }, source = "RCLootCouncil", limit = 20,
    })
    assert_true(missingSource.ok)
    assert_equal(0, #missingSource.candidates)

    local invalidDate = dibs.LogsUI.SearchHistory({
      seasonId = dibs.GetCurrentSeasonId(), aliases = { "DIB" }, fromDate = "2026-02-30",
    })
    assert_false(invalidDate.ok)
    assert_equal("HISTORY_INVALID_FROM_DATE", invalidDate.reasonCode)
  end)

  it("keeps ambiguous evidence blocked and unavailable states readable", function()
    local _, dibs = setup({
      ["Tester-Realm"] = {
        { id = "ambiguous-1", itemID = 19019, lootWon = "item:19019", response = "DIB", responseID = 1, status = "awarded" },
        { id = "ambiguous-2", itemID = 19020, lootWon = "item:19020", response = "DIB", responseID = 2, status = "awarded" },
      },
    })
    local search = dibs.LogsUI.SearchHistory({ seasonId = dibs.GetCurrentSeasonId(), aliases = { "DIB" } })
    assert_true(search and search.ok)
    assert_equal(2, search.view.summary.ambiguous)
    assert_false(search.view.candidates[1].canConfirm)
    assert_equal("Needs review", search.view.candidates[1].status.label)
    assert_true(search.view.candidates[1].evidenceSummary:find("safely", 1, true) ~= nil)

    local _, unavailableDibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local unavailable = unavailableDibs.LogsUI.GetReconciliationAvailability()
    assert_equal("Unavailable", unavailable.label)
    assert_true(unavailable.explanation:find("unavailable", 1, true) ~= nil)
  end)

  it("keeps empty and no-candidate searches explicit", function()
    local _, dibs = setup({ ["Tester-Realm"] = {} })
    local search = dibs.LogsUI.SearchHistory({ seasonId = dibs.GetCurrentSeasonId(), aliases = { "DIB" } })
    assert_true(search and search.ok)
    assert_equal("review", search.view.stage)
    assert_equal(0, #search.view.candidates)
    assert_equal("No Dibs candidates found", search.view.emptyState)
  end)
end)
