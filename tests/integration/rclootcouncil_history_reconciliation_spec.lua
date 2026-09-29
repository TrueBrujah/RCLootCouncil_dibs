local loader = require("helpers.load_addon")

local function enableV2(dibs)
  assert_true(dibs.Governance.AdoptInitial(nil, { reason = "history reconciliation test" }))
  local baseline = assert(dibs.LegacyBaseline.FinalizeBaseline(nil))
  local coordinator = assert(dibs.Identity.CreateSnapshot("Tester-Realm"))
  assert_true(dibs.Governance.Change(nil, { future = { authority = {
    schema = 1, state = "ACTIVE", coordinator = coordinator, ledgerEpoch = 9,
    transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash },
  } } }))
  assert_true(dibs.Governance.EnableV2(nil, { "Tester-Realm" }))
  assert_not_nil(dibs.Seasons.Create("History V2"))
  assert_not_nil(dibs.Ledger.Grant("Tester-Realm", 1, "history setup", "test", dibs.GetCurrentSeasonId()))
end

describe("RCLootCouncil history reconciliation", function()
  local originalCalendarTime
  after_each(function()
    if originalCalendarTime then
      _G.time = originalCalendarTime
      originalCalendarTime = nil
    end
  end)

  it("builds a read-only preview with exact aliases and classifies duplicates", function()
    local history = {
      ["Tester-Realm"] = {
        { id = "old-1", itemID = 19019, lootWon = "item:19019", response = "  dib  ", status = "awarded", timestamp = 1700000100 },
        { id = "old-2", itemID = 19020, lootWon = "item:19020", response = "Need", status = "awarded", timestamp = 1700000200 },
      },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = history })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    local session, reason = dibs.RCLootCouncil.CreateReconciliationSession({
      seasonId = seasonId, aliases = "DIB", mode = "guided", limit = 20,
    }, nil)
    assert_true(session ~= nil, reason)
    assert_equal(1, session.counts.scanned)
    assert_equal(2, session.counts.sourceScanned)
    assert_equal(1, session.counts.hiddenNonDib)
    assert_equal(1, session.counts.eligible)
    assert_equal(0, session.counts.rejected)
    assert_equal(1, #session.candidates)
    assert_equal("DIB", session.candidates[1].aliasUsed)
    assert_equal(1, #dibs.Ledger.GetAllTransactions()) -- season allocation only
  end)

  it("confirms an eligible row once and keeps immutable evidence", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { id = "old-1", itemID = 19019, lootWon = "item:19019", response = "Dib", status = "success", timestamp = 1700000100 },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local session = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" } }, nil)
    local candidate = session.candidates[1]
    local first = dibs.RCLootCouncil.ConfirmReconciliationCandidate(session.sessionId, candidate.candidateId, {
      mode = "guided", reason = "Guild history import", confirmation = true,
    }, nil)
    assert_true(first and first.ok)
    assert_equal("already_accounted", candidate.classification)
    local view = dibs.LogsUI.BuildReconciliationView(session.sessionId)
    assert_equal("Already accounted", view.candidates[1].status.label)
    assert_false(view.candidates[1].canConfirm)
    local second = dibs.RCLootCouncil.ConfirmReconciliationCandidate(session.sessionId, candidate.candidateId, {
      mode = "guided", reason = "Repeated click", confirmation = true,
    }, nil)
    assert_true(second and second.ok)
    assert_true(second.duplicate)
    assert_equal(2, #dibs.Ledger.GetAllTransactions()) -- season allocation + historical debit
    local evidence = dibs.GetDB().reconciliation.evidence[candidate.evidenceId]
    assert_true(evidence and evidence.immutable)
    assert_equal("Dib", evidence.responseText)
    assert_equal("RCMLAwardSuccess", evidence.sourceEvent)
    assert_equal("FinalizeAward", evidence.accountingAction)
    assert_equal("old-1", tostring(evidence.historyRef):gsub("^history:", ""))
  end)

  it("commits a confirmed historical award through the V2 canonical ledger", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { id = "old-v2", itemID = 19019, lootWon = "item:19019", response = "DIB", status = "success", timestamp = 1700000100 },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    enableV2(dibs)
    local before = dibs.Ledger.GetBalance("Tester-Realm")
    local session = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" } }, nil)
    local candidate = session.candidates[1]
    local result = dibs.RCLootCouncil.ConfirmReconciliationCandidate(session.sessionId, candidate.candidateId, {
      mode = "manual", reason = "Verified historical award", confirmation = true, manualAcknowledgement = true,
    }, nil)

    assert_true(result and result.ok, result and result.reasonCode)
    assert_equal(before - 1, dibs.Ledger.GetBalance("Tester-Realm"))
    assert_equal(1, dibs.Ledger.GetCanonicalState().commitCount)
  end)

  it("resolves a pending V2 proposal created by an earlier failed history confirmation", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { id = "old-v2-pending", itemID = 19019, lootWon = "item:19019", response = "DIB", status = "success", timestamp = 1700000150 },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    enableV2(dibs)
    local historyRef, evidenceId = "history:old-v2-pending", "reconciliation:history:old-v2-pending"
    local _, proposalReason = dibs.Ledger.Use("Tester-Realm", 1, "Old confirmation", "rclootcouncil_history", dibs.GetCurrentSeasonId(), {
      awardRef = historyRef, evidenceId = evidenceId, itemID = 19019,
    })
    assert_equal("DISTRIBUTED_COMMIT_REQUIRED", proposalReason)
    local proposals = dibs.Governance.GetAwardProposals()
    assert_equal(1, #proposals)
    assert_equal("PENDING_RECONCILIATION", proposals[1].status)

    local session = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" } }, nil)
    local candidate = session.candidates[1]
    local result = dibs.RCLootCouncil.ConfirmReconciliationCandidate(session.sessionId, candidate.candidateId, {
      mode = "manual", reason = "Verified historical award", confirmation = true, manualAcknowledgement = true,
    }, nil)

    assert_true(result and result.ok, result and result.reasonCode)
    assert_equal(1, dibs.Ledger.GetCanonicalState().commitCount)
    assert_equal("COMMITTED", dibs.Governance.GetAwardProposals()[1].status)
  end)

  it("reports the ledger rejection reason when a V2 historical award cannot be debited", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { id = "old-v2-empty", itemID = 19019, lootWon = "item:19019", response = "DIB", status = "success", timestamp = 1700000200 },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    enableV2(dibs)
    local consumed = dibs.Ledger.CommitDibUse({ actor = "Tester-Realm", action = "ledger.use" }, {
      playerName = "Tester-Realm", seasonId = dibs.GetCurrentSeasonId(), amount = 1,
      awardRef = "history:prior-use", evidenceId = "reconciliation:prior-use", itemID = 19019,
      reason = "Use starting Dib",
    })
    assert_true(consumed and consumed.accepted)
    local balance = dibs.Ledger.GetBalance("Tester-Realm")
    local session = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" } }, nil)
    local candidate = session.candidates[1]
    local result = dibs.RCLootCouncil.ConfirmReconciliationCandidate(session.sessionId, candidate.candidateId, {
      mode = "manual", reason = "Verified historical award", confirmation = true, manualAcknowledgement = true,
    }, nil)

    assert_false(result and result.ok)
    assert_equal("INSUFFICIENT_BALANCE", result.reasonCode)
    assert_equal(balance, dibs.Ledger.GetBalance("Tester-Realm"))
    assert_equal(1, dibs.Ledger.GetCanonicalState().commitCount)
  end)

  it("uses the history bucket player as winner instead of the original loot owner", function()
    local history = {
      ["Meatyfajita-Ysera"] = {
        {
          id = "1788395568-7",
          itemID = 270167,
          lootWon = "item:270167",
          response = "Dibs",
          status = "success",
          owner = "Leetah-Durotan",
          timestamp = 1788395568,
        },
      },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = history })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local rows = dibs.RCLootCouncil.GetHistoryRows({ limit = 10 })
    assert_equal(1, #rows)
    assert_equal("Meatyfajita-Ysera", rows[1].winner)
    assert_equal("Meatyfajita-Ysera", rows[1].playerName)
    assert_equal("Leetah-Durotan", rows[1].originalOwner)
  end)

  it("normalizes compact item tokens into selectable rich links", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Meatyfajita-Ysera"] = {
        {
          id = "1788395568-8",
          itemID = 270167,
          lootWon = "item:270167::::::::::::",
          itemName = "Wavecaller's Seastone",
          response = "Dibs",
          status = "success",
        },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local rows = dibs.RCLootCouncil.GetHistoryRows({ limit = 10 })
    assert_true(rows[1].itemLink:find("|Hitem:270167", 1, true) ~= nil)
    assert_true(rows[1].itemLink:find("[Wavecaller's Seastone]", 1, true) ~= nil)
    rows[1].itemName = "changed by the preview"
    local secondRows = dibs.RCLootCouncil.GetHistoryRows({ limit = 10 })
    assert_equal("Wavecaller's Seastone", secondRows[1].itemName)
  end)

  it("keeps zero award timestamps unavailable", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { id = "zero-time", itemID = 19019, lootWon = "item:19019", response = "DIB", status = "success", timestamp = 0, date = "0" },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local rows = dibs.RCLootCouncil.GetHistoryRows({ limit = 10 })
    assert_nil(rows[1].originalAwardTime)
    assert_nil(rows[1].originalAwardTimeText)
  end)

  it("formats numeric history timestamps with date and seconds", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { id = "precise-time", itemID = 19019, lootWon = "item:19019", response = "DIB", status = "awarded", timestamp = 1788395568 },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local rows = dibs.RCLootCouncil.GetHistoryRows({ limit = 10 })
    assert_equal("2026-09-06 12:00:00", rows[1].originalAwardTimeText)
  end)

  it("infers a reviewable final state from dated history and keeps difficulty variants separate", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Heroic-Winner"] = {
        { id = "heroic-1", itemID = 19019, lootWon = "item:19019", response = "DIB", reason = "Dibs", date = "2026/09/09", time = "22:14", difficultyName = "Heroic", votes = 3 },
      },
      ["Normal-Winner"] = {
        { id = "normal-1", itemID = 19019, lootWon = "item:19019", response = "DIB", date = "2026/09/02", time = "21:05", difficultyName = "Normal", votes = 2 },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local session = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" } }, nil)
    assert_equal(2, session.counts.eligible)
    assert_true(session.candidates[1].finalStatusInferred)
    assert_equal("HISTORY_FINAL_STATUS_INFERRED", session.candidates[1].reasonCode)
    assert_equal(1, session.candidates[1].relatedHistoryCount)
    assert_true(session.candidates[1].relatedWinners:find("Heroic-Winner", 1, true) ~= nil)
    assert_true(session.candidates[1].relatedWinners:find("Normal-Winner", 1, true) ~= nil)
    assert_true(session.candidates[1].relatedDifficulties:find("Heroic", 1, true) ~= nil)
    assert_true(session.candidates[1].relatedDifficulties:find("Normal", 1, true) ~= nil)
    assert_equal("Dibs", session.candidates[1].awardReason)
    assert_equal(3, session.candidates[1].voteCount)
    assert_equal("2026/09/09 22:14", session.candidates[1].originalAwardTimeText)
    assert_equal("2026/09/02 21:05", session.candidates[2].originalAwardTimeText)
    local strictSession = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" }, inferFinalStatus = false }, nil)
    assert_equal("ambiguous", strictSession.candidates[1].classification)
  end)

  it("requires acknowledgement and a reason for ambiguous manual rows", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { itemID = 19019, lootWon = "item:19019", response = "DIB", status = "awarded" },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true } })
    local session = dibs.RCLootCouncil.CreateReconciliationSession({ aliases = { "DIB" }, mode = "manual" }, nil)
    local candidate = session.candidates[1]
    assert_equal("ambiguous", candidate.classification)
    local denied = dibs.RCLootCouncil.ConfirmReconciliationCandidate(session.sessionId, candidate.candidateId, {
      mode = "manual", confirmation = true, manualAcknowledgement = false,
    }, nil)
    assert_false(denied and denied.ok)
    local accepted = dibs.RCLootCouncil.ConfirmReconciliationCandidate(session.sessionId, candidate.candidateId, {
      mode = "manual", confirmation = true, manualAcknowledgement = true, reason = "Verified against guild archive",
    }, nil)
    assert_true(accepted and accepted.ok)
  end)

  it("renders the Officer reconciliation page without exposing it to players", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { id = "help-copy", itemID = 19019, lootWon = "item:19019", response = "DIB", status = "awarded", date = "2026/09/09", time = "22:14" },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true }, withAce3 = true })
    local frame = dibs.OfficerUI.CreateWindow()
    assert_true(frame ~= nil)
    local originalAddTable = dibs.AceGUI.AddTable
    local historyTableOptions
    local historyTableColumns
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, options)
      if columns and columns[1] and (columns[1].title == "Date / time" or columns[1].title == "Candidate") then
        historyTableOptions, historyTableColumns = options, columns
      end
      return originalAddTable(shell, parent, columns, rows, height, rowActions, options)
    end
    frame.SelectTab("reconciliation")
    assert_equal("reconciliation", frame.activeTab)
    local function findWidget(widget, kind, text)
      if widget and widget.kind == kind and ((widget.text and widget.text:find(text, 1, true)) or (widget.label and widget.label:find(text, 1, true))) then return widget end
      for _, child in ipairs(widget and widget.children or {}) do
        local found = findWidget(child, kind, text)
        if found then return found end
      end
    end
    local function findSelect(widget, label)
      if widget and widget._dibsSelectLabel == label then return widget end
      for _, child in ipairs(widget and widget.children or {}) do
        local found = findSelect(child, label)
        if found then return found end
      end
    end
    local function hasAncestorKind(widget, kind)
      while widget do
        if widget.kind == kind then return true end
        widget = widget.parent
      end
      return false
    end
    local seasonSelect = findSelect(frame.aceTabs, "Target season")
    assert_not_nil(seasonSelect)
    assert_not_nil(seasonSelect._dibsTooltipAttachment)
    local aliasesControl = findWidget(frame.aceTabs, "EditBox", "DIB response aliases (comma separated)")
    local searchButton = findWidget(frame.aceTabs, "Button", "Search history (preview)")
    assert_not_nil(aliasesControl)
    assert_not_nil(searchButton)
    assert_true(hasAncestorKind(aliasesControl, "ScrollFrame"))
    assert_true(hasAncestorKind(searchButton, "ScrollFrame"))
    assert_nil(findWidget(frame.aceTabs, "Button", "?"))
    assert_nil(findWidget(frame.aceTabs, "Label", "Preview matching RCLootCouncil awards"))
    assert_not_nil(searchButton._dibsTooltipAttachment)
    searchButton.callbacks.OnClick()
    assert_true(historyTableOptions and historyTableOptions.hideScrollbarWhenFits)
    assert_true(historyTableOptions.fluidColumns)
    assert_true(historyTableOptions.noScrolling)
    frame:ReflowHistoryTable(true, 1000)
    assert_equal(9, #historyTableColumns)
    for _, column in ipairs(historyTableColumns) do assert_true(column.tooltip and column.tooltip ~= "") end
    frame:ReflowHistoryTable(true, 700)
    assert_equal(8, #historyTableColumns)
    for _, column in ipairs(historyTableColumns) do assert_true(column.tooltip and column.tooltip ~= "") end
    frame:ReflowHistoryTable(true, 600)
    assert_equal(6, #historyTableColumns)
    for _, column in ipairs(historyTableColumns) do assert_true(column.tooltip and column.tooltip ~= "") end
    frame:ReflowHistoryTable(true, 450)
    assert_equal(3, #historyTableColumns)
    for _, column in ipairs(historyTableColumns) do assert_true(column.tooltip and column.tooltip ~= "") end
    local tableRootFrame = frame.reconciliationTablePage.root.frame
    local originalGetWidth = tableRootFrame.GetWidth
    tableRootFrame.GetWidth = function() return 700 end
    frame:ReflowHistoryTable(false, 1000)
    assert_equal("MEDIUM", frame.historyLayoutMode)
    assert_equal(8, #historyTableColumns)
    tableRootFrame.GetWidth = originalGetWidth
    local editSearch = findWidget(frame.aceTabs, "Button", "Edit Search")
    assert_not_nil(editSearch)
    editSearch.callbacks.OnClick()
    assert_nil(frame.reconciliationTablePage)
    assert_not_nil(findWidget(frame.aceTabs, "Button", "Search history (preview)"))
  end)

  it("uses an explicit empty state and keeps the fixed 40-row shared pager", function()
    local nonDibHistory = {
      { id = "not-dib", itemID = 19019, lootWon = "item:19019", response = "NEED", status = "awarded", date = "2026/09/09", time = "22:14" },
    }
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = { ["Tester-Realm"] = nonDibHistory } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true }, withAce3 = true })
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("reconciliation")
    local function findWidget(widget, kind, text)
      if widget and widget.kind == kind and ((widget.text and widget.text:find(text, 1, true)) or (widget.label and widget.label:find(text, 1, true))) then return widget end
      for _, child in ipairs(widget and widget.children or {}) do
        local found = findWidget(child, kind, text)
        if found then return found end
      end
    end
    findWidget(frame.aceTabs, "Button", "Search history (preview)").callbacks.OnClick()
    assert_not_nil(findWidget(frame.aceTabs, "Label", "No matching history candidates."))
    assert_nil(frame.reconciliationPagination.pageSize)
    assert_true(frame.reconciliationPagination.previous.disabled)
    assert_true(frame.reconciliationPagination.next.disabled)

    local manyRows = {}
    for index = 1, 41 do
      local itemID = 19019 + index
      manyRows[index] = {
        id = "page-" .. tostring(index), itemID = itemID, lootWon = "item:" .. tostring(itemID),
        response = "DIB", status = "awarded", date = "2026/09/09", time = "22:14",
      }
    end
    rc = loader.makeRCLootCouncil({ enabled = true, historyDB = { ["Tester-Realm"] = manyRows } })
    local _, pagedDibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true }, withAce3 = true })
    local pagedFrame = pagedDibs.OfficerUI.CreateWindow()
    local originalAddTable = pagedDibs.AceGUI.AddTable
    local renderedRows
    pagedDibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, options)
      if columns and columns[1] and (columns[1].title == "Date / time" or columns[1].title == "Candidate") then
        renderedRows = rows
      end
      return originalAddTable(shell, parent, columns, rows, height, rowActions, options)
    end
    pagedFrame.SelectTab("reconciliation")
    findWidget(pagedFrame.aceTabs, "Button", "Search history (preview)").callbacks.OnClick()
    assert_equal(40, #renderedRows)
    assert_equal("Page 1 / 2", pagedFrame.reconciliationPagination.page.text)
    local firstCandidateId = renderedRows[1].candidate.candidateId
    pagedFrame.reconciliationPagination.next.callbacks.OnClick()
    assert_equal(2, pagedFrame.reconPage)
    assert_equal(1, #renderedRows)
    assert_true(renderedRows[1].candidate.candidateId ~= firstCandidateId)
    assert_equal("Page 2 / 2", pagedFrame.reconciliationPagination.page.text)
    pagedFrame.reconciliationPagination.previous.callbacks.OnClick()
    assert_equal(1, pagedFrame.reconPage)
    assert_equal(40, #renderedRows)
  end)

  it("opens the historical transfer review in a separate window", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { id = "transfer-1", itemID = 19019, lootWon = "item:19019", response = "DIB", status = "awarded", date = "2026/09/09", time = "22:14" },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true }, withAce3 = true })
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("reconciliation")

    local function findWidget(widget, kind, text)
      if widget and widget.kind == kind and (widget.text == text or widget.label == text) then return widget end
      for _, child in ipairs(widget and widget.children or {}) do
        local found = findWidget(child, kind, text)
        if found then return found end
      end
    end

    local function findWidgetContaining(widget, kind, text)
      if widget and widget.kind == kind and ((widget.text and widget.text:find(text, 1, true)) or (widget.label and widget.label:find(text, 1, true))) then return widget end
      for _, child in ipairs(widget and widget.children or {}) do
        local found = findWidgetContaining(child, kind, text)
        if found then return found end
      end
    end

    local tree = frame.aceTabs
    local search = findWidget(tree, "Button", "Search history (preview)")
    assert_not_nil(search)
    search.callbacks.OnClick()
    local transfer = findWidget(tree, "Button", "Review")
    assert_not_nil(transfer)
    transfer.callbacks.OnClick()
    local transferWindow
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Frame" and widget.title == "RCLootCouncil - Dibs | Transfer" then transferWindow = widget break end
    end
    assert_not_nil(transferWindow)
    assert_true(transferWindow.frame._shown)
    local transferViewport = transferWindow.children[1]
    assert_not_nil(transferViewport)
    assert_equal("ScrollFrame", transferViewport.kind)
    assert_equal(transferWindow, transferViewport.parent)
    local summary = findWidgetContaining(transferWindow, "Label", "Item:")
    local technicalToggle = findWidget(transferWindow, "Button", "Show technical evidence")
    assert_not_nil(summary)
    assert_not_nil(technicalToggle)
    assert_nil(findWidget(transferWindow, "Label", "Technical evidence"))
    technicalToggle.callbacks.OnClick()
    assert_not_nil(findWidget(transferWindow, "Label", "Technical evidence"))
    assert_not_nil(findWidgetContaining(transferWindow, "Label", "Item:"))

    local confirm = findWidget(transferWindow, "Button", "Confirm as DIB")
    assert_not_nil(confirm)
    assert_true(confirm.disabled)
    local note = findWidget(transferWindow, "EditBox", "Transfer note (required)")
    assert_not_nil(note)
    note.callbacks.OnTextChanged(nil, nil, "Verified against the RC vote record")
    assert_false(confirm.disabled)
  end)

  it("selects an inclusive date range from the calendar", function()
    local rc = loader.makeRCLootCouncil({ enabled = true, historyDB = {
      ["Tester-Realm"] = {
        { id = "calendar-date", itemID = 19019, lootWon = "item:19019", response = "DIB", status = "awarded", date = "2026/09/09", time = "22:14" },
      },
    } })
    local _, dibs = loader.load({ rclootcouncil = rc, wow = { guildLeader = true }, withAce3 = true })
    originalCalendarTime = _G.time
    local fakeTime = _G.time
    _G.time = function(value)
      if type(value) == "table" then return os.time(value) end
      return fakeTime()
    end
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("reconciliation")

    local function findWidget(widget, kind, text)
      if widget and widget.kind == kind and (widget.text == text or widget.label == text) then return widget end
      for _, child in ipairs(widget and widget.children or {}) do
        local found = findWidget(child, kind, text)
        if found then return found end
      end
    end

    findWidget(frame.aceTabs, "Button", "Start: Choose date").callbacks.OnClick()
    findWidget(frame.aceTabs, "Button", "9").callbacks.OnClick()
    findWidget(frame.aceTabs, "Button", "End: Choose date").callbacks.OnClick()
    findWidget(frame.aceTabs, "Button", "10").callbacks.OnClick()
    findWidget(frame.aceTabs, "Button", "Search history (preview)").callbacks.OnClick()

    local session = dibs.RCLootCouncil.GetReconciliationSession(frame.reconSessionId, nil)
    assert_equal(os.time({ year = 2026, month = 9, day = 9, hour = 0, min = 0, sec = 0 }), session.fromTime)
    assert_equal(os.time({ year = 2026, month = 9, day = 11, hour = 0, min = 0, sec = 0 }) - 1, session.toTime)
  end)
end)
