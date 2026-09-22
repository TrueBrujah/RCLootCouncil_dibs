local loader = require("helpers.load_addon")
local mocks = require("helpers.b11_ui_mocks")

local function findMenuEntry(entries, text)
  for _, entry in ipairs(entries or {}) do
    if entry.text == text then return entry end
  end
  return nil
end

describe("B12 historical transfer actions", function()
  after_each(function() mocks.clear() end)

  it("keeps historical actions Officer-only and exposes only safe candidate context actions", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { id = "b12-action-private", itemID = 19019, itemName = "Midnight Blade", lootWon = "item:19019", response = "DIB", status = "success" },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = {
      guildLeader = false, guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 3 }, withAce3 = true,
    } })
    assert_false(dibs.LogsUI.CanViewReconciliation())
    local denied = dibs.LogsUI.SearchHistory({ aliases = { "DIB" } })
    assert_false(denied.ok)
    assert_equal("GUILD_ADMIN_REQUIRED", denied.reasonCode)

    local _, officerDibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true, withAce3 = true } })
      local menuState = mocks.installMSA()
    local entries = {
      { text = "Review transfer", callback = function() end },
      { text = "Show technical evidence", callback = function() end },
    }
    assert_true(officerDibs.AceGUI.ShowContextMenu(entries))
      assert_equal(1, menuState.initialized)
    assert_nil(findMenuEntry(entries, "Confirm as DIB"))
    assert_nil(findMenuEntry(entries, "Reject row"))
    officerDibs.AceGUI.HideContextMenu()
  end)

  it("requires a reason and explicit confirmation before protected history confirmation", function()
    local history = {
      ["Tester-Realm"] = {
        { id = "b12-action-confirm", itemID = 19019, lootWon = "item:19019", response = "DIB", status = "awarded" },
      },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = history })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local search = dibs.LogsUI.SearchHistory({ aliases = { "DIB" } })
    local candidate = search.view.candidates[1]
    local originalExecute = dibs.ProtectedActions.Execute
    local protectedCalls = {}
    dibs.ProtectedActions.Execute = function(actionId, actor, payload)
      protectedCalls[#protectedCalls + 1] = { actionId = actionId, actor = actor, payload = payload }
      return originalExecute(actionId, actor, payload)
    end

    local missingReason = dibs.LogsUI.ConfirmCandidate(search.sessionId, candidate.candidateId, "", { confirmation = true })
    assert_false(missingReason.ok)
    assert_equal("HISTORY_REASON_REQUIRED", missingReason.reasonCode)
    local missingConfirmation = dibs.RCLootCouncil.ConfirmReconciliationCandidate(search.sessionId, candidate.candidateId, {
      mode = "manual", reason = "Verified archive", confirmation = false, manualAcknowledgement = true,
    }, "Tester-Realm")
    assert_false(missingConfirmation and missingConfirmation.ok)
    assert_true(missingConfirmation and missingConfirmation.value == nil)
    assert_not_nil(missingConfirmation and missingConfirmation.diagnostic)

    local confirmed = dibs.LogsUI.ConfirmCandidate(search.sessionId, candidate.candidateId, "Verified archive", {
      mode = "manual", confirmation = true, manualAcknowledgement = true,
    })
    dibs.ProtectedActions.Execute = originalExecute
    assert_true(confirmed.ok, confirmed.reasonCode)
    assert_equal("history.confirm", protectedCalls[1].actionId)
    assert_equal("Verified archive", protectedCalls[1].payload.reason)
    assert_equal("DIB", history["Tester-Realm"][1].response)
  end)

  it("keeps confirmation idempotent and routes rejection through the protected action", function()
    local history = {
      ["Tester-Realm"] = {
        { id = "b12-action-replay", itemID = 19019, lootWon = "item:19019", response = "DIB", status = "awarded" },
      },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = history })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local search = dibs.LogsUI.SearchHistory({ aliases = { "DIB" } })
    local candidate = search.view.candidates[1]
    local first = dibs.LogsUI.ConfirmCandidate(search.sessionId, candidate.candidateId, "Initial import", {
      mode = "manual", confirmation = true, manualAcknowledgement = true,
    })
    local second = dibs.LogsUI.ConfirmCandidate(search.sessionId, candidate.candidateId, "Retry import", {
      mode = "manual", confirmation = true, manualAcknowledgement = true,
    })
    assert_true(first.ok)
    assert_true(second.ok)
    assert_true(second.result and second.result.duplicate)
    assert_equal(2, #dibs.Ledger.GetAllTransactions())
    assert_equal("DIB", history["Tester-Realm"][1].response)

    local rejectedSearch = dibs.LogsUI.SearchHistory({ aliases = { "DIB" } })
    local rejectedCandidate = rejectedSearch.view.candidates[1]
    local missingReason = dibs.LogsUI.RejectCandidate(rejectedSearch.sessionId, rejectedCandidate.candidateId, "")
    assert_false(missingReason.ok)
    assert_equal("HISTORY_REASON_REQUIRED", missingReason.reasonCode)
    local rejected = dibs.LogsUI.RejectCandidate(rejectedSearch.sessionId, rejectedCandidate.candidateId, "Already imported elsewhere")
    assert_true(rejected.ok)
    assert_equal("rejected", rejected.result.value.outcome)
  end)

  it("keeps historical confirmation data-only during combat without invoking live readiness", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { id = "b12-action-combat", itemID = 19019, lootWon = "item:19019", response = "DIB", status = "awarded" },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true, inCombat = true } })
    local readinessCalls = 0
    local originalEvaluate = dibs.Readiness.Evaluate
    dibs.Readiness.Evaluate = function(...)
      readinessCalls = readinessCalls + 1
      return originalEvaluate(...)
    end
    local search = dibs.LogsUI.SearchHistory({ aliases = { "DIB" } })
    local candidate = search.view.candidates[1]
    local confirmed = dibs.LogsUI.ConfirmCandidate(search.sessionId, candidate.candidateId, "Combat-safe historical import", {
      mode = "manual", confirmation = true, manualAcknowledgement = true,
    })
    dibs.Readiness.Evaluate = originalEvaluate

    assert_true(confirmed.ok, confirmed.reasonCode)
    assert_equal(0, readinessCalls)
    assert_equal(2, #dibs.Ledger.GetAllTransactions())
    assert_equal("DIB", rc:GetHistoryDB()["Tester-Realm"][1].response)
  end)

  it("exposes only non-destructive historical context actions", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { id = "b12-context-safe", itemID = 19019, itemName = "Midnight Blade", lootWon = "item:19019", response = "DIB", status = "success" },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true }, withAce3 = true })
    local capturedOptions, capturedRows
    local originalAddTable = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, options)
      if options and options.contextMenu then
        capturedOptions, capturedRows = options, rows
      end
      return originalAddTable(shell, parent, columns, rows, height, rowActions, options)
    end
    local protectedCalls = 0
    local originalExecute = dibs.ProtectedActions.Execute
    dibs.ProtectedActions.Execute = function(...)
      protectedCalls = protectedCalls + 1
      return originalExecute(...)
    end

    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("reconciliation")
    local search = dibs.LogsUI.SearchHistory({ aliases = { "DIB" }, mode = "guided" })
    frame.reconSessionId = search.sessionId
    frame:Refresh()
    local menu = capturedOptions.contextMenu(capturedRows[1])
    local review = findMenuEntry(menu, "Review transfer")
    local technical = findMenuEntry(menu, "Show technical evidence")
    assert_not_nil(review)
    assert_not_nil(technical)
    assert_nil(findMenuEntry(menu, "Confirm as DIB"))
    assert_nil(findMenuEntry(menu, "Reject row"))
    review.callback()
    technical.callback()

    dibs.ProtectedActions.Execute = originalExecute
    dibs.AceGUI.AddTable = originalAddTable
    assert_equal(0, protectedCalls)
  end)
end)
