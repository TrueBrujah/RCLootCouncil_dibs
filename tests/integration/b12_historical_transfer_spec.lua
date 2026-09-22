local loader = require("helpers.load_addon")

local function findWidget(widget, kind, text)
  if type(widget) ~= "table" then return nil end
  if widget.kind == kind and (widget.text == text or widget.label == text or widget.title == text) then return widget end
  for _, child in ipairs(widget.children or {}) do
    local found = findWidget(child, kind, text)
    if found then return found end
  end
  return nil
end

describe("B12 historical transfer workflow", function()
  it("projects a concise candidate summary with collapsed technical evidence", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Winner-Realm"] = {
        {
          id = "b12-transfer-eligible", itemID = 19019, itemName = "Midnight Blade",
          lootWon = "item:19019", response = "DIB", status = "success",
          difficultyName = "Heroic", instanceName = "The Midnight Citadel", encounterName = "First Boss",
          date = "2026/09/09", time = "22:14", votes = 3,
        },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true, withAce3 = true } })
    local search = dibs.LogsUI.SearchHistory({ aliases = { "DIB" }, mode = "guided", limit = 20 })
    assert_true(search.ok)
    assert_equal("review", search.view.stage)
    assert_equal(1, #search.view.candidates)
    local candidate = search.view.candidates[1]
    assert_equal("Midnight Blade", candidate.item:match("%[(.-)%]") or candidate.item)
    assert_equal("Winner-Realm", candidate.winner)
    assert_equal("Heroic", candidate.difficulty)
    assert_equal("The Midnight Citadel - First Boss", candidate.encounter)
    assert_equal("eligible", candidate.classification)
    assert_false(candidate.duplicate)
    assert_equal("Not previously accounted", candidate.duplicateStatus)
    assert_true(candidate.canConfirm)
    assert_nil(candidate.technical)

    local reviewed = dibs.LogsUI.ReviewCandidate(search.sessionId, candidate.candidateId)
    assert_true(reviewed.ok)
    assert_not_nil(reviewed.technical)
    assert_equal(candidate.candidateId, reviewed.candidateId)
    assert_equal("Midnight Blade", reviewed.item:match("%[(.-)%]") or reviewed.item)
    assert_equal("The Midnight Citadel - First Boss", reviewed.encounter)
    assert_equal("eligible", reviewed.classification)
    assert_false(reviewed.duplicate)
    assert_equal("Not previously accounted", reviewed.duplicateStatus)
  end)

  it("keeps ambiguous, duplicate, stale, and unknown evidence non-confirmable", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Winner-Realm"] = {
        { id = "b12-ambiguous", itemID = 19019, lootWon = "item:19019", response = "DIB", responseID = 1, status = "awarded" },
        { id = "b12-ambiguous-other", itemID = 19020, lootWon = "item:19020", response = "DIB", responseID = 2, status = "awarded" },
        { id = "b12-unknown", response = "DIB", status = "awarded" },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local session = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" }, mode = "manual" }, nil)
    assert_true(session ~= nil)
    local byId = {}
    for _, candidate in ipairs(session.candidates or {}) do byId[candidate.historyRef] = candidate end
    assert_equal("ambiguous", byId["history:b12-ambiguous"].classification)
    assert_equal("unsupported", byId["history:b12-unknown"].classification)
    local view = dibs.LogsUI.BuildReconciliationView(session.sessionId)
    assert_true(view.summary.ambiguous >= 1)
    for _, candidate in ipairs(view.candidates) do
      if candidate.status.label ~= "Ready to review" then assert_false(candidate.canConfirm) end
    end
    local rejected = dibs.LogsUI.RejectCandidate(session.sessionId, byId["history:b12-ambiguous"].candidateId, "Evidence is incomplete")
    assert_true(rejected.ok)
    local blockedAfterReject = dibs.LogsUI.ConfirmCandidate(session.sessionId, byId["history:b12-ambiguous"].candidateId, "Repeated review", { confirmation = true })
    assert_false(blockedAfterReject.ok)
    assert_equal("HISTORY_CANDIDATE_NOT_CONFIRMABLE", blockedAfterReject.reasonCode)
  end)

  it("keeps confirmed history player-safe while retaining technical evidence for Officers", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        {
          id = "b12-player-safe-history", itemID = 19019, itemName = "Midnight Blade",
          lootWon = "item:19019", response = "DIB", status = "success",
          difficultyName = "Heroic", instanceName = "The Midnight Citadel", encounterName = "First Boss",
        },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local search = dibs.LogsUI.SearchHistory({ aliases = { "DIB" }, mode = "guided" })
    local candidate = search.view.candidates[1]
    local sourceCandidate = search.session.candidates[1]
    local confirmed = dibs.LogsUI.ConfirmCandidate(search.sessionId, candidate.candidateId, "Verified historical award", {
      mode = "guided", confirmation = true,
    })
    assert_true(confirmed.ok, confirmed.reasonCode)

    local playerView = dibs.PlayerUI.BuildHistoryView({ playerName = "Tester-Realm" })
    local historicalEntry
    for _, entry in ipairs(playerView.entries) do
      if entry.result == "Verified historical award" then historicalEntry = entry break end
    end
    assert_not_nil(historicalEntry)
    assert_true(historicalEntry.item:find("[Midnight Blade]", 1, true) ~= nil)
    assert_not_nil(historicalEntry.date)
    assert_not_nil(historicalEntry.action)
    assert_not_nil(historicalEntry.balanceImpact)
    assert_nil(historicalEntry.historyRef)
    assert_nil(historicalEntry.evidenceId)
    assert_nil(historicalEntry.responseIdentity)
    assert_nil(playerView.technical)

    local officerReview = dibs.LogsUI.ReviewCandidate(search.sessionId, candidate.candidateId)
    assert_true(officerReview.ok)
    assert_not_nil(officerReview.technical)
    assert_equal(sourceCandidate.historyRef, officerReview.technical.historyRef)
    assert_equal(sourceCandidate.evidenceId, officerReview.technical.evidenceId)
  end)

  it("renders the unavailable integration state without creating a review session", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local availability = dibs.LogsUI.GetReconciliationAvailability()
    assert_true(availability.availability ~= "operational")
    local search = dibs.LogsUI.SearchHistory({ aliases = { "DIB" } })
    assert_false(search.ok)
    assert_equal("HISTORY_UNAVAILABLE", search.reasonCode)
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("reconciliation")
    assert_true(frame.activeTab == "reconciliation")
  end)
end)
