local loader = require("helpers.load_addon")

local function setup(history, wow)
  local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = history })
  local _, dibs = loader.load({ rclootcouncil = rc, wow = wow or { guildLeader = true }, withAce3 = true })
  return rc, dibs
end

describe("B11f reconciliation UI", function()
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
