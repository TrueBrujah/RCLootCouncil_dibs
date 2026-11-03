local loader = require("helpers.load_addon")

local function setup(options)
  options = options or {}
  options.withAce3 = true
  return loader.load(options)
end

local function containsForbiddenValue(value, forbidden)
  if type(value) == "string" then
    for _, text in ipairs(forbidden) do
      if value:find(text, 1, true) then return true end
    end
    return false
  end
  if type(value) ~= "table" then return false end
  for key, item in pairs(value) do
    if containsForbiddenValue(key, forbidden) or containsForbiddenValue(item, forbidden) then return true end
  end
  return false
end

describe("B11c Player UI", function()
  it("keeps the balance in the Player window instead of echoing it to chat", function()
    local _, dibs = setup()
    for index = #(_G.__dibsMessages or {}), 1, -1 do _G.__dibsMessages[index] = nil end
    local original, summaryCalls = dibs.PlayerUI.GetSummary, 0
    dibs.PlayerUI.GetSummary = function(...)
      summaryCalls = summaryCalls + 1
      return original(...)
    end

    local frame = dibs.PlayerUI.Show()

    assert_equal(_G.DibsPlayerFrame, frame)
    assert_equal(1, summaryCalls, "opening should render the initial player summary only once")
    assert_equal(0, #(_G.__dibsMessages or {}))
    dibs.PlayerUI.GetSummary = original
  end)

  it("exposes the player views and a diagnostics entry", function()
    local _, dibs = setup()
    local navigation = dibs.PlayerUI.GetNavigation()
    assert_equal(6, #navigation)
    assert_equal("My Dibs", navigation[1].text)
    assert_equal("Reports", navigation[2].text)
    assert_equal("History", navigation[3].text)
    assert_equal("Great Vault", navigation[4].text)
    assert_equal("Preferences", navigation[5].text)
    assert_equal("Diagnostics", navigation[6].text)
    assert_equal("my-dibs", navigation[1].value)
    assert_equal("requests", navigation[2].value)
    assert_equal("history", navigation[3].value)
    assert_equal("vault", navigation[4].value)
    assert_equal("preferences", navigation[5].value)
    assert_equal("diagnostics", navigation[6].value)
  end)

  it("skips unused Vault and eligibility projections when building the My Dibs view", function()
    local _, dibs = setup()
    local originalAcquisitions = dibs.PreDibs.GetAcquisitionsForPlayer
    local originalEligibility = dibs.CharacterEligibility.GetSummary
    local originalModePolicy = dibs.PreDibs.GetModePolicy
    local acquisitionsCalls, eligibilityCalls, modePolicyCalls = 0, 0, 0
    dibs.PreDibs.GetAcquisitionsForPlayer = function(...)
      acquisitionsCalls = acquisitionsCalls + 1
      return originalAcquisitions(...)
    end
    dibs.CharacterEligibility.GetSummary = function(...)
      eligibilityCalls = eligibilityCalls + 1
      return originalEligibility(...)
    end
    dibs.PreDibs.GetModePolicy = function(...)
      modePolicyCalls = modePolicyCalls + 1
      return originalModePolicy(...)
    end

    local completeSummary = dibs.PlayerUI.GetSummary()
    assert_true(acquisitionsCalls > 0, "other summary consumers should retain full Vault data by default")
    assert_true(eligibilityCalls > 0, "other summary consumers should retain eligibility data by default")
    assert_true(modePolicyCalls > 0, "other summary consumers should retain mode policy by default")

    acquisitionsCalls, eligibilityCalls, modePolicyCalls = 0, 0, 0
    local view = dibs.PlayerUI.GetViewModel(nil, nil, nil, { includeHistory = false })
    assert_true(type(view) == "table")
    assert_equal(0, acquisitionsCalls, "My Dibs must not project Great Vault acquisitions it does not display")
    assert_equal(0, eligibilityCalls, "My Dibs must not build character eligibility data it does not display")
    assert_equal(0, modePolicyCalls, "My Dibs must not build mode-policy details it does not display")

    dibs.PreDibs.GetAcquisitionsForPlayer = originalAcquisitions
    dibs.CharacterEligibility.GetSummary = originalEligibility
    dibs.PreDibs.GetModePolicy = originalModePolicy
  end)

  it("skips unrelated request, Vault, eligibility, and policy projections for report/history summaries", function()
    local _, dibs = setup()
    local preDibs = dibs.PreDibs
    local original = {
      requestSummary = preDibs.GetPlayerSeasonRequestSummary,
      activeRequests = preDibs.GetActiveRequests,
      requestHistory = preDibs.GetRequestsForPlayer,
      acquisitions = preDibs.GetAcquisitionsForPlayer,
      eligibility = dibs.CharacterEligibility.GetSummary,
      modePolicy = preDibs.GetModePolicy,
    }
    local function unexpected() error("unused Player summary projection was requested") end
    preDibs.GetPlayerSeasonRequestSummary = unexpected
    preDibs.GetActiveRequests = unexpected
    preDibs.GetRequestsForPlayer = unexpected
    preDibs.GetAcquisitionsForPlayer = unexpected
    dibs.CharacterEligibility.GetSummary = unexpected
    preDibs.GetModePolicy = unexpected

    local summary = dibs.PlayerUI.GetSummary(nil, nil, {
      includeRequests = false, includeAcquisitions = false,
      includeEligibility = false, includeModePolicy = false,
    })
    assert_equal(0, #summary.activePreDibs)
    assert_equal(0, #summary.wonPreDibs)

    preDibs.GetPlayerSeasonRequestSummary = original.requestSummary
    preDibs.GetActiveRequests = original.activeRequests
    preDibs.GetRequestsForPlayer = original.requestHistory
    preDibs.GetAcquisitionsForPlayer = original.acquisitions
    dibs.CharacterEligibility.GetSummary = original.eligibility
    preDibs.GetModePolicy = original.modePolicy
  end)

  it("does not pump request delivery during redraw and pumps after a successful report action", function()
    local _, dibs = setup({
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Officer-Realm" } },
    })
    local frame = dibs.PlayerUI.Show()
    local originalPump, pumpCalls = dibs.RequestDelivery.Pump, 0
    dibs.RequestDelivery.Pump = function() pumpCalls = pumpCalls + 1; return true end

    frame.SelectTab("requests")
    assert_equal(0, pumpCalls, "page rendering must not process the delivery outbox")
    frame.disputeNote = "UI delivery scheduling test"
    assert_not_nil(frame.disputeSubmitButton)
    frame.disputeSubmitButton.callbacks.OnClick(frame.disputeSubmitButton, "OnClick")

    dibs.RequestDelivery.Pump = originalPump
    assert_equal(1, pumpCalls, "an explicit successful report action should request immediate delivery")
  end)

  it("reuses the revisioned Pre-Dibs player index and invalidates it after a history change", function()
    local _, dibs = setup()
    local history = dibs.PreDibs.GetHistory()
    history[#history + 1] = { requestId = "player-index-1", playerName = "Tester-Realm", status = "pending", createdAt = 10 }
    dibs.PreDibs.MarkHistoryChanged()
    local first = dibs.PreDibs.GetRequestsForPlayer("Tester-Realm")
    assert_equal(1, #first)
    assert_equal("player-index-1", first[1].requestId)
    assert_equal(first, dibs.PreDibs.GetRequestsForPlayer("tester-realm"),
      "same-identity player history reads should share the revisioned index")
    local firstSummary = dibs.PreDibs.GetPlayerSeasonRequestSummary("Tester-Realm", nil)
    assert_equal(1, #firstSummary.active)
    assert_equal(0, #firstSummary.fulfilled)
    assert_equal(firstSummary, dibs.PreDibs.GetPlayerSeasonRequestSummary("tester-realm", nil),
      "season request projections should reuse the revisioned summary")

    history[#history + 1] = { requestId = "player-index-2", playerName = "Tester-Realm", status = "fulfilled", createdAt = 20 }
    dibs.PreDibs.MarkHistoryChanged()
    local updated = dibs.PreDibs.GetRequestsForPlayer("Tester-Realm")
    assert_equal(2, #updated)
    assert_equal("player-index-2", updated[2].requestId)
    local recent = dibs.PreDibs.GetRecentRequestsForPlayer("Tester-Realm")
    assert_equal("player-index-2", recent[1].requestId,
      "the UI index should return the newest request first")
    assert_equal("player-index-1", recent[2].requestId)
    assert_equal(recent, dibs.PreDibs.GetRecentRequestsForPlayer("tester-realm"),
      "recent history ordering should be shared from the revisioned cache")
    local updatedSummary = dibs.PreDibs.GetPlayerSeasonRequestSummary("Tester-Realm", nil)
    assert_equal(1, #updatedSummary.active)
    assert_equal(1, #updatedSummary.fulfilled)
    local originalSeasonSummary, summaryReads = dibs.PreDibs.GetPlayerSeasonRequestSummary, 0
    dibs.PreDibs.GetPlayerSeasonRequestSummary = function(...)
      summaryReads = summaryReads + 1
      return originalSeasonSummary(...)
    end
    local firstPlayerSummary, secondPlayerSummary = dibs.PlayerUI.GetSummary(), dibs.PlayerUI.GetSummary()
    assert_equal(1, summaryReads, "unchanged Player renders should reuse the revision-keyed Pre-Dibs summary")
    assert_equal(firstPlayerSummary.activePreDibs, secondPlayerSummary.activePreDibs,
      "Player summary should retain the revisioned active-list identity for page-cache reuse")
    assert_equal(firstPlayerSummary.wonPreDibs, secondPlayerSummary.wonPreDibs,
      "Player summary should retain the revisioned fulfilled-list identity for page-cache reuse")
    history[#history + 1] = { requestId = "player-index-3", playerName = "Tester-Realm", status = "cancelled", createdAt = 30 }
    dibs.PreDibs.MarkHistoryChanged()
    dibs.PlayerUI.GetSummary()
    assert_equal(2, summaryReads, "a history revision should invalidate the Player summary cache")
    local revisedRequestSummary = originalSeasonSummary("Tester-Realm", nil)
    assert_equal(1, #revisedRequestSummary.pastRequests)
    assert_equal("player-index-3", revisedRequestSummary.pastRequests[1].requestId)
    dibs.PreDibs.GetPlayerSeasonRequestSummary = originalSeasonSummary
  end)

  it("builds only the requested past Pre-Dibs page while preserving the total", function()
    local _, dibs = setup()
    local originalSummary = dibs.PlayerUI.GetSummary
    local originalRecent = dibs.PreDibs.GetRecentRequestsForPlayer
    local summaryFixture = {
      player = "Tester-Realm", season = { id = "season-current", name = "Season" },
      activePreDibs = { { requestId = "past-page-1", seasonId = "season-current" } },
      wonPreDibs = { { requestId = "past-page-2", seasonId = "season-current" } },
      balance = 0, seasonAllocation = 0, seasonUsed = 0,
    }
    dibs.PlayerUI.GetSummary = function() return summaryFixture end
    local requests = {}
    for index = 25, 1, -1 do
      requests[#requests + 1] = {
        requestId = "past-page-" .. index, playerName = "Tester-Realm", createdAt = index,
        itemName = "Item " .. index, status = index == 1 and "pending" or index == 2 and "fulfilled" or "cancelled",
      }
    end
    dibs.PreDibs.GetRecentRequestsForPlayer = function() return requests end

    local view = dibs.PlayerUI.GetViewModel(nil, nil, nil, {
      includeHistory = false, pagePreDibHistory = 2,
    })
    assert_equal(23, view.pastPreDibPage.count)
    assert_equal(3, view.pastPreDibPage.pages)
    assert_equal(2, view.pastPreDibPage.page)
    assert_equal(10, #view.pastPreDibPage.rows)
    assert_equal(15, view.pastPreDibPage.rows[1].createdAt)
    assert_equal(6, view.pastPreDibPage.rows[10].createdAt)
    assert_equal(0, #view.requests, "paged UI should not materialize the complete request projection")
    local repeated = dibs.PlayerUI.GetViewModel(nil, nil, nil, {
      includeHistory = false, pagePreDibHistory = 2,
    })
    assert_equal(view.pastPreDibPage, repeated.pastPreDibPage,
      "the same unchanged player page should reuse its bounded row projection")

    dibs.PlayerUI.GetSummary = originalSummary
    dibs.PreDibs.GetRecentRequestsForPlayer = originalRecent
  end)

  it("projects only the visible active and fulfilled Pre-Dibs rows", function()
    local _, dibs = setup()
    local originalSummary = dibs.PlayerUI.GetSummary
    local summaryFixture = {
      player = "Tester-Realm", season = { id = "season-current", name = "Season" },
      activePreDibs = {}, wonPreDibs = {}, balance = 0, seasonAllocation = 0, seasonUsed = 0,
    }
    for index = 1, 25 do
      summaryFixture.activePreDibs[index] = {
        requestId = "active-" .. index, status = "pending", createdAt = index,
      }
      summaryFixture.wonPreDibs[index] = {
        requestId = "fulfilled-" .. index, status = "fulfilled", fulfilledAt = index,
      }
    end
    dibs.PlayerUI.GetSummary = function() return summaryFixture end

    local view = dibs.PlayerUI.GetViewModel(nil, nil, nil, {
      includeHistory = false, pagePreDibHistory = 1,
      pageActivePreDibs = 2, pageWonPreDibs = 3,
    })
    assert_equal(25, view.activePreDibPage.count)
    assert_equal(3, view.activePreDibPage.pages)
    assert_equal(2, view.activePreDibPage.page)
    assert_equal(10, #view.activePreDibs)
    assert_equal("active-11", view.activePreDibs[1].requestId)
    assert_equal(25, view.wonPreDibPage.count)
    assert_equal(3, view.wonPreDibPage.pages)
    assert_equal(3, view.wonPreDibPage.page)
    assert_equal(5, #view.wonPreDibs)
    assert_equal("fulfilled-21", view.wonPreDibs[1].requestId)
    assert_equal(25, view.pendingRequests)

    dibs.PlayerUI.GetSummary = originalSummary
  end)

  it("uses bounded past Pre-Dibs projection for the rendered My Dibs page", function()
    local _, dibs = setup()
    local originalGetViewModel = dibs.PlayerUI.GetViewModel
    local renderedView
    dibs.PlayerUI.GetViewModel = function(...)
      renderedView = originalGetViewModel(...)
      return renderedView
    end

    local frame = dibs.PlayerUI.CreateWindow()
    frame:Refresh()
    assert_not_nil(renderedView)
    assert_not_nil(renderedView.pastPreDibPage,
      "initial My Dibs render should request page one instead of the full history projection")
    assert_equal(0, #renderedView.requests)
  end)

  it("mounts a non-empty content root for each Player navigation route", function()
    local _, dibs = setup()
    local frame = dibs.PlayerUI.CreateWindow()
    local roots = {}
    for _, route in ipairs({ "my-dibs", "requests", "history" }) do
      frame.SelectTab(route)
      assert_equal(1, #(frame.contentHost.children or {}), route .. " should mount one page root")
      local pageRoot = frame.contentHost.children[1]
      assert_true(#(pageRoot.children or {}) > 0, route .. " should render controls into the page root")
      roots[route] = pageRoot
    end
    assert_true(roots["my-dibs"] ~= roots.requests and roots.requests ~= roots.history,
      "route transitions should replace the mounted page root")
  end)

  it("mounts Great Vault, Preferences, and Diagnostics table pages directly in the content host", function()
    local _, dibs = setup()
    local frame = dibs.PlayerUI.CreateWindow()
    for _, route in ipairs({ "vault", "preferences", "diagnostics" }) do
      frame.SelectTab(route)
      assert_equal(1, #(frame.contentHost.children or {}), route .. " should mount one page root")
      local pageRoot = frame.contentHost.children[1]
      if route == "vault" then assert_equal(frame.vaultTablePage.root, pageRoot) end
      if route == "diagnostics" then assert_equal(frame.diagnosticsTablePage.root, pageRoot) end
      assert_true(#(pageRoot.children or {}) > 0, route .. " should render into its own page root")
    end
  end)

  it("saves a selected color theme from Player Preferences and refreshes the UI", function()
    local _, dibs = setup()
    local frame = dibs.PlayerUI.CreateWindow()
    frame.SelectTab("preferences")
    local selector = frame.themeSelector
    assert_not_nil(selector)
    assert_equal("MIDNIGHT", selector.value)
    assert_equal("Fel Green", selector.list.FEL_GREEN)

    selector.callbacks.OnValueChanged(selector, "OnValueChanged", "FEL_GREEN")

    assert_equal("FEL_GREEN", dibs.Midnight.GetTokens().theme)
    assert_equal("FEL_GREEN", _G.RCLootCouncil_dibsLocalDB.presentation.profile.theme)
    assert_not_nil(frame.themeSelector, "refresh should keep the theme selector on Preferences")
    assert_equal(0.025, frame.dibsAceGUIShell.frame._backdropColor[1],
      "the refreshed Player window should use the selected palette surface")
  end)

  it("keeps adapter-provided scale when restyling the Player window and an open Officer window", function()
    local _, dibs = setup()
    assert_true(dibs.EnvironmentAdapters.Register("ELVUI", function()
      return "available", { scale = 1.2 }, "AVAILABLE"
    end))
    local frame = dibs.PlayerUI.CreateWindow()
    local playerScale
    frame.dibsAceGUIShell.frame.SetScale = function(_, value) playerScale = value end
    frame.SelectTab("preferences")
    assert_equal(1.2, playerScale, "rendering a Player page should keep the adapter scale hint")

    local officerScale
    _G.DibsOfficerFrame = {
      dibsAceGUIShell = { _dibsActive = true, frame = { SetScale = function(_, value) officerScale = value end } },
      Refresh = function() end,
    }
    local selector = frame.themeSelector
    selector.callbacks.OnValueChanged(selector, "OnValueChanged", "FEL_GREEN")
    _G.DibsOfficerFrame = nil
    assert_equal(1.2, officerScale, "changing the palette should keep the adapter scale on an open Officer window")
  end)

  it("builds a history projection only for the History page", function()
    local _, dibs = setup()
    local frame = dibs.PlayerUI.CreateWindow()
    local originalFull, originalHistory = dibs.PlayerUI.GetViewModel, dibs.PlayerUI.GetHistoryViewModel
    local fullCalls, historyCalls, includeHistory = 0, 0, nil
    dibs.PlayerUI.GetViewModel = function(...)
      fullCalls = fullCalls + 1
      local options = select(4, ...)
      includeHistory = options and options.includeHistory
      return originalFull(...)
    end
    dibs.PlayerUI.GetHistoryViewModel = function(...)
      historyCalls = historyCalls + 1
      return originalHistory(...)
    end

    frame.SelectTab("diagnostics")
    assert_equal(0, fullCalls, "diagnostics should not project the player's full ledger history")
    frame.SelectTab("requests")
    assert_equal(0, fullCalls, "the request page should not project unrelated history and vault data")
    frame.SelectTab("history")
    assert_equal(0, fullCalls, "History should not build the unrelated overview model")
    assert_equal(1, historyCalls, "History should project its ledger rows once when selected")
    frame.SelectTab("my-dibs")
    assert_equal(1, fullCalls, "My Dibs should build its summary model")
    assert_equal(false, includeHistory, "My Dibs should not project hidden History rows")
    dibs.PlayerUI.GetViewModel = originalFull
    dibs.PlayerUI.GetHistoryViewModel = originalHistory
  end)

  it("uses bounded history access on My Dibs, Reports, and History", function()
    local _, dibs = setup()
    local frame = dibs.PlayerUI.CreateWindow()
    local originalHistory, fullHistoryReads = dibs.Ledger.GetHistory, 0
    local originalSummary, summaryReads = dibs.Ledger.GetPlayerHistorySummary, 0
    local originalPage, pageReads = dibs.Ledger.GetHistoryPage, 0
    local originalChoices, choiceReads = dibs.Ledger.GetRecentHistoryChoices, 0
    local originalRequests, requestReads = dibs.Disputes.ListForPlayer, 0
    dibs.Ledger.GetHistory = function(...)
      fullHistoryReads = fullHistoryReads + 1
      return originalHistory(...)
    end
    dibs.Ledger.GetPlayerHistorySummary = function(...)
      summaryReads = summaryReads + 1
      return originalSummary(...)
    end
    dibs.Ledger.GetHistoryPage = function(...)
      pageReads = pageReads + 1
      return originalPage(...)
    end
    dibs.Ledger.GetRecentHistoryChoices = function(...)
      choiceReads = choiceReads + 1
      return originalChoices(...)
    end
    dibs.Disputes.ListForPlayer = function(...)
      requestReads = requestReads + 1
      return originalRequests(...)
    end
    for _, route in ipairs({ "my-dibs", "requests", "history" }) do
      fullHistoryReads, summaryReads, pageReads, choiceReads, requestReads = 0, 0, 0, 0, 0
      frame.SelectTab(route)
      assert_equal(0, fullHistoryReads, route .. " should not copy the full player history")
      if route == "history" then
        assert_equal(1, pageReads, "History should request one visible page")
        assert_equal(0, summaryReads, "History should not compute an unrelated summary")
      elseif route == "my-dibs" then
        assert_equal(1, summaryReads, route .. " should use the cached history summary")
      end
      if route == "requests" then
        assert_equal(1, choiceReads, "Reports should request only recent lightweight transaction choices")
        assert_equal(0, pageReads, "Reports should not deep-copy full history transactions")
        assert_equal(0, summaryReads, "Reports should get the count with the recent transaction choices")
        assert_equal(1, requestReads, "Reports should not query the review-request list twice")
      end
    end
    dibs.Ledger.GetHistory = originalHistory
    dibs.Ledger.GetPlayerHistorySummary = originalSummary
    dibs.Ledger.GetHistoryPage = originalPage
    dibs.Ledger.GetRecentHistoryChoices = originalChoices
    dibs.Disputes.ListForPlayer = originalRequests
  end)

  it("bounds Player table widgets when personal histories grow", function()
    local _, dibs = setup()
    local frame = dibs.PlayerUI.CreateWindow()
    local originalAddTable, originalAddDropdown = dibs.AceGUI.AddTable, dibs.AceGUI.AddDropdown
    local originalFull, originalHistory = dibs.PlayerUI.GetViewModel, dibs.PlayerUI.GetHistoryViewModel
    local originalLedgerHistory, originalLedgerPage = dibs.Ledger.GetHistory, dibs.Ledger.GetHistoryPage
    local originalHistoryChoices = dibs.Ledger.GetRecentHistoryChoices
    local originalLedgerSummary, originalRequests = dibs.Ledger.GetPlayerHistorySummary, dibs.Disputes.ListForPlayer
    local largestTable, reportDropdownCount = 0, nil
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, ...)
      largestTable = math.max(largestTable, #(rows or {}))
      return originalAddTable(shell, parent, columns, rows, ...)
    end
    dibs.AceGUI.AddDropdown = function(shell, parent, label, values, ...)
      if label == ((dibs.L or {}).PLAYER_REPORT_TRANSACTION or "Related ledger entry (optional)") then
        local count = 0
        for _ in pairs(values or {}) do count = count + 1 end
        reportDropdownCount = count
      end
      return originalAddDropdown(shell, parent, label, values, ...)
    end
    dibs.PlayerUI.GetViewModel = function()
      local active, won, past = {}, {}, {}
      for index = 1, 120 do
        active[index] = { requestId = "active-" .. index, date = "today", item = "Item", status = "Pending" }
        won[index] = { requestId = "won-" .. index, date = "today", item = "Item", status = "Won" }
        past[index] = { requestId = "past-" .. index, createdAt = index, item = "Item", status = "Cancelled" }
      end
      return { seasonAllocation = 0, seasonUsed = 0, balance = 0, seasonName = "Season",
        status = { label = "Ready", explanation = "Ready" }, activePreDibs = active, wonPreDibs = won,
        requests = past, empty = {} }
    end
    dibs.PlayerUI.GetHistoryViewModel = function()
      local history = {}
      for index = 1, 500 do
        history[index] = { date = "today", item = "Item", action = "AWARD", result = "Recorded",
          balanceImpact = "+1", transactionId = tostring(index) }
      end
      return { history = history, empty = {} }
    end
    dibs.Ledger.GetHistory = function()
      local history = {}
      for index = 1, 500 do
        history[index] = { transactionId = tostring(index), createdAt = index, type = "AWARD", amount = 1 }
      end
      return history
    end
    dibs.Ledger.GetPlayerHistorySummary = function()
      return { count = 500, seasonUsed = 0, balance = 0, allocation = 0 }
    end
    dibs.Ledger.GetHistoryPage = function(_, _, _, page, pageSize)
      local history, total = {}, 500
      local first = ((page or 1) - 1) * (pageSize or 20) + 1
      for index = first, math.min(total, first + (pageSize or 20) - 1) do
        history[#history + 1] = { transactionId = tostring(index), createdAt = index, type = "AWARD", amount = 1 }
      end
      return history, total, page or 1
    end
    dibs.Ledger.GetRecentHistoryChoices = function(_, _, _, pageSize)
      local choices = {}
      for index = 1, math.min(pageSize or 50, 50) do
        choices[index] = { transactionId = tostring(index), createdAt = index, type = "AWARD", amount = 1 }
      end
      return choices, 500
    end
    dibs.Disputes.ListForPlayer = function()
      local requests = {}
      for index = 1, 120 do
        requests[index] = { requestId = "report-" .. index, createdAt = index, status = "Open", category = "other" }
      end
      return requests
    end

    for _, route in ipairs({ "my-dibs", "requests", "history" }) do
      largestTable, reportDropdownCount = 0, nil
      frame.SelectTab(route)
      assert_true(largestTable <= (route == "requests" and 15 or 20),
        route .. " created an unbounded table with " .. largestTable .. " visible rows")
      if route == "requests" then
        assert_true(reportDropdownCount <= 51,
          "Reports should cap its entry dropdown and let the user refine the search")
      end
    end
    dibs.AceGUI.AddTable, dibs.AceGUI.AddDropdown = originalAddTable, originalAddDropdown
    dibs.PlayerUI.GetViewModel, dibs.PlayerUI.GetHistoryViewModel = originalFull, originalHistory
    dibs.Ledger.GetHistory, dibs.Ledger.GetHistoryPage = originalLedgerHistory, originalLedgerPage
    dibs.Ledger.GetRecentHistoryChoices = originalHistoryChoices
    dibs.Ledger.GetPlayerHistorySummary, dibs.Disputes.ListForPlayer = originalLedgerSummary, originalRequests
  end)

  it("lets a player enable diagnostics and run a sync channel test", function()
    local _, dibs = setup({ wow = {
      playerName = "Player-Realm", guildLeader = false,
      guildMembers = { "GM-Realm", "Officer-Realm", "Player-Realm", "LongPlayerNameForWidth-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1, [3] = 3, [4] = 3 },
    } })
    local originalAddTable = dibs.AceGUI.AddTable
    local matrixOptions
    local matrixParent
    local matrixColumns
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, options)
      if columns[1] and columns[1].title == "Player" then
        matrixOptions = options
        matrixParent = parent
        matrixColumns = columns
      end
      return originalAddTable(shell, parent, columns, rows, height, rowActions, options)
    end
    local frame = dibs.PlayerUI.CreateWindow()
    frame:Show()
    frame.SelectTab("diagnostics")
    assert_not_nil(frame.developerModeToggle)
    assert_not_nil(frame.guildDiagnosticsSection)
    assert_equal("Guild sync scope: realm:testguild", frame.guildScopeLabel.text)
    assert_true(frame.guildSyncStatusLabel.text:find("Guild sync:", 1, true) ~= nil)
    assert_true(frame.guildSyncStatusLabel.text:find("Protocol:", 1, true) ~= nil)
    assert_true(frame.guildSyncStatusLabel.text:find("Guild policy:", 1, true) ~= nil)
    assert_nil(frame.channelTestAutoPingToggle)
    assert_nil(frame.channelTestRunButton)
    frame.developerModeToggle.callbacks.OnValueChanged(frame.developerModeToggle, "OnValueChanged", true)
    assert_true(dibs.DeveloperMode.IsEnabled())
    assert_not_nil(frame.channelTestRunButton)
    assert_not_nil(frame.channelTestScanButton)
    assert_not_nil(matrixOptions)
    assert_equal(true, matrixOptions.noScrolling)
    assert_equal(26, matrixOptions.scrollbarReserve)
    assert_equal(frame.diagnosticsTablePage.scroll, matrixParent)
    assert_true(not matrixColumns[8].wrap)
    assert_true(matrixColumns[8].minWidth >= dibs.AceGUI.MeasureTextWidth(matrixColumns[8].title) + 12)
    local statusMinimumWidth = 0
    for index = 2, #matrixColumns do statusMinimumWidth = statusMinimumWidth + matrixColumns[index].minWidth end
    local measuredPlayerWidth = dibs.AceGUI.MeasureTextWidth("LongPlayerNameForWidth-Realm") + 16
    assert_equal(math.max(60, math.min(measuredPlayerWidth,
      matrixOptions.widthHint - statusMinimumWidth - matrixOptions.scrollbarReserve)), matrixColumns[1].width)
    local minimumColumnsWidth = 0
    for _, column in ipairs(matrixColumns) do minimumColumnsWidth = minimumColumnsWidth + column.minWidth end
    assert_true(minimumColumnsWidth <= matrixOptions.widthHint - matrixOptions.scrollbarReserve)
    _G.time = function() return 1700000000 end
    local sentBefore = #dibs.Ace3.libs.comm.sent
    frame.channelTestRunButton.callbacks.OnClick(frame.channelTestRunButton, "OnClick")
    assert_equal(sentBefore + 1, #dibs.Ace3.libs.comm.sent)
    local outgoing = dibs.Ace3.Deserialize(dibs.Ace3.libs.comm.sent[#dibs.Ace3.libs.comm.sent].payload)
    assert_equal("CHANNEL_TEST", outgoing.type)
    assert_equal("GUILD", outgoing.testChannel)
    assert_true(frame.channelTestStatus:find(outgoing.testId, 1, true) ~= nil)
    local playerRow, officerRow
    for _, row in ipairs(frame.channelTestMatrixRows or {}) do
      if row[1] == "Player-Realm" then playerRow = row end
      if row[1] == "Officer-Realm" then officerRow = row end
    end
    assert_not_nil(playerRow)
    assert_true(playerRow[2]:find("YOU", 1, true) ~= nil)
    assert_not_nil(officerRow)
    assert_true(officerRow[2]:find("WAIT", 1, true) ~= nil)
    local acknowledgement = assert(dibs.Sync.BuildEnvelope({ type = "CHANNEL_TEST_ACK", testId = outgoing.testId,
      testChannel = "GUILD", ackTransport = "WHISPER", result = "RECEIVED",
      reasonCode = "CHANNEL_MESSAGE_VALIDATED" }))
    acknowledgement.senderNameRealm = "Officer-Realm"
    acknowledgement.senderMemberKey = "officer-realm"
    assert_true(dibs.Sync.Receive(acknowledgement, "Officer-Realm", "WHISPER"))
    officerRow = nil
    for _, row in ipairs(frame.channelTestMatrixRows or {}) do
      if row[1] == "Officer-Realm" then officerRow = row; break end
    end
    assert_not_nil(officerRow)
    assert_true(officerRow[2]:find("PONG", 1, true) ~= nil)
    assert_true(officerRow[2]:find(date("%H:%M", 1700000000), 1, true) ~= nil)
  end)

  it("uses player row actions instead of right-click sort menus and shows history details cleanly", function()
    local _, dibs = setup()
    local originalGetViewModel = dibs.PlayerUI.GetViewModel
    dibs.PlayerUI.GetViewModel = function(...)
      local view = originalGetViewModel(...)
      view.history = { {
        date = "2026-09-27", item = "Midnight Blade", action = "SEASON_ALLOCATION",
        result = "Rank allocation reconciliation", balanceImpact = 2,
      } }
      return view
    end
    local capturedTables = {}
    local originalAddTable = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, options)
      capturedTables[#capturedTables + 1] = { columns = columns, options = options }
      return originalAddTable(shell, parent, columns, rows, height, rowActions, options)
    end

    local frame = dibs.PlayerUI.CreateWindow()
    frame.SelectTab("my-dibs")
    frame:Refresh()
    local balanceOptions
    for _, tableInfo in ipairs(capturedTables) do
      if tableInfo.columns[1].title == "Season allocation" then balanceOptions = tableInfo.options end
    end
    assert_not_nil(balanceOptions)
    assert_equal(false, balanceOptions.allowTableSort)
    assert_equal(true, balanceOptions.flatBackground)
    assert_equal(true, balanceOptions.fluidColumns)
    assert_equal(true, balanceOptions.shrinkToFit)
    assert_equal(true, balanceOptions.hideScrollbarWhenFits)
    assert_true(balanceOptions.widthHint > 300)
    local overviewMenu = balanceOptions.contextMenu({})
    assert_equal(3, #overviewMenu)
    assert_equal("View Reports", overviewMenu[1].text)
    assert_equal("View History", overviewMenu[2].text)
    assert_equal("Open Diagnostics", overviewMenu[3].text)
    overviewMenu[1].callback()
    assert_equal("requests", frame.playerTab)
    local requestsOptions
    for _, tableInfo in ipairs(capturedTables) do
      if tableInfo.columns[3].title == "Status" then requestsOptions = tableInfo.options end
    end
    assert_not_nil(requestsOptions)
    assert_equal(true, requestsOptions.fluidColumns)
    assert_equal(true, requestsOptions.shrinkToFit)
    assert_equal(true, requestsOptions.hideScrollbarWhenFits)
    assert_true(requestsOptions.widthHint > 300)
    frame.SelectTab("history")

    local historyOptions
    for _, tableInfo in ipairs(capturedTables) do
      if tableInfo.options and tableInfo.options.contextMenu then historyOptions = tableInfo.options end
    end
    assert_not_nil(historyOptions)
    assert_equal(false, historyOptions.allowTableSort)
    assert_equal(true, historyOptions.flatBackground)
    assert_equal(true, historyOptions.fluidColumns)
    assert_equal(true, historyOptions.shrinkToFit)
    assert_equal(true, historyOptions.hideScrollbarWhenFits)
    assert_true(historyOptions.widthHint > 300)
    local menu = historyOptions.contextMenu({ entry = {
      date = "2026-09-27", item = "Midnight Blade", action = "SEASON_ALLOCATION",
      result = "Rank allocation reconciliation", balanceImpact = 2,
    } })
    assert_equal(1, #menu)
    assert_equal("View details", menu[1].text)
    menu[1].callback()
    assert_not_nil(frame.historyDetailTitle)
    assert_not_nil(frame.historyDetailCloseButton)
    assert_true(frame.historyDetailTitle.kind == "Heading" or frame.historyDetailTitle.kind == "Label")

    frame.historyDetailCloseButton.callbacks.OnClick(frame.historyDetailCloseButton, "OnClick")
    assert_nil(frame.historyDetail)
    assert_nil(frame.historyDetailTitle)
  end)

  it("shows a received probe's reason when local Developer Mode suppresses the reply", function()
    local _, dibs = setup({ wow = { playerName = "Firebutt-Realm", guildLeader = false,
      guildMembers = { "Officer-Realm", "Firebutt-Realm" }, guildRankIndices = { [1] = 1, [2] = 3 } } })
    local frame = dibs.PlayerUI.CreateWindow()
    frame:Show()
    frame.SelectTab("diagnostics")
    local probe = assert(dibs.Sync.BuildEnvelope({ type = "CHANNEL_TEST", testId = "firebutt-probe",
      testChannel = "GUILD", startedAt = time() }))
    probe.senderNameRealm = "Officer-Realm"
    probe.senderMemberKey = "officer-realm"

    local accepted, reason = dibs.Sync.Receive(probe, "Officer-Realm", "GUILD")
    assert_false(accepted)
    assert_equal("DEVELOPER_MODE_REQUIRED", reason)
    assert_not_nil(frame.channelTestReceivedStatus)
    assert_true(frame.channelTestReceivedStatus.text:find("Last received probe: GUILD from Officer-Realm", 1, true) ~= nil)
    assert_true(frame.channelTestReceivedStatus.text:find("DEVELOPER_MODE_REQUIRED", 1, true) ~= nil)
  end)

  it("shows a duplicated realm suffix only once in the channel matrix", function()
    local _, dibs = setup({ wow = { guildLeader = true,
      guildMembers = { "Tester-Realm", "Manu-Zul'jin-Zul'jin-Zul'jin" } } })
    local frame = dibs.PlayerUI.CreateWindow()
    frame:Show()
    frame.SelectTab("diagnostics")
    frame.developerModeToggle.callbacks.OnValueChanged(frame.developerModeToggle, "OnValueChanged", true)

    local found
    for _, row in ipairs(frame.channelTestMatrixRows or {}) do
      if row[1]:find("Manu", 1, true) then found = row[1]; break end
    end
    assert_equal("Manu-Zul'jin", found)
  end)

  it("does not report no-pong for members outside the probed channel audience", function()
    local _, dibs = setup({ wow = {
      guildLeader = true,
      guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
    } })
    local frame = dibs.PlayerUI.CreateWindow()
    frame:Show()
    frame.SelectTab("diagnostics")
    frame.developerModeToggle.callbacks.OnValueChanged(frame.developerModeToggle, "OnValueChanged", true)

    local sent, testId = dibs.Sync.StartChannelTest("OFFICER")
    assert_true(sent)
    frame:Refresh()
    local statuses = {}
    for _, row in ipairs(frame.channelTestMatrixRows or {}) do statuses[row[1]] = row[3] end
    assert_true(statuses["Officer-Realm"]:find("--", 1, true) == nil)
    assert_true(statuses["Player-Realm"]:find("--", 1, true) ~= nil)

    sent = dibs.Sync.StartChannelTest("WHISPER", "Officer-Realm")
    assert_true(sent)
    frame:Refresh()
    local whisperStatuses = {}
    for _, row in ipairs(frame.channelTestMatrixRows or {}) do whisperStatuses[row[1]] = row[7] end
    assert_true(whisperStatuses["Officer-Realm"]:find("--", 1, true) == nil)
    assert_true(whisperStatuses["Player-Realm"]:find("--", 1, true) ~= nil)

    _G.IsInRaid = function() return true end
    _G.IsInGroup = function() return true end
    _G.GetNumGroupMembers = function() return 2 end
    _G.GetRaidRosterInfo = function(index)
      if index == 1 then return "Tester-Realm" end
      if index == 2 then return "Officer-Realm" end
    end
    sent = dibs.Sync.StartChannelTest("RAID")
    assert_true(sent)
    frame:Refresh()
    local raidStatuses = {}
    for _, row in ipairs(frame.channelTestMatrixRows or {}) do raidStatuses[row[1]] = row[4] end
    assert_true(raidStatuses["Officer-Realm"]:find("--", 1, true) == nil)
    assert_true(raidStatuses["Player-Realm"]:find("--", 1, true) ~= nil)
    assert_true(type(testId) == "string")
  end)

  it("limits automatic channel scans to opted-in GM or Officer diagnostics sessions", function()
    local _, dibs = setup({ wow = {
      guildLeader = true,
      guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
      guildRankIndices = { [1] = 0, [2] = 1, [3] = 3 },
    } })
    local frame = dibs.PlayerUI.CreateWindow()
    frame:Show()
    frame.SelectTab("diagnostics")
    frame.developerModeToggle.callbacks.OnValueChanged(frame.developerModeToggle, "OnValueChanged", true)
    assert_not_nil(frame.channelTestAutoPingToggle)

    local timerCount = #dibs.Ace3.libs.timer.scheduled
    frame.channelTestAutoPingToggle.callbacks.OnValueChanged(frame.channelTestAutoPingToggle, "OnValueChanged", true)
    assert_true(frame.channelTestAutoPingScheduled)
    assert_equal(timerCount + 3, #dibs.Ace3.libs.timer.scheduled)
    assert_equal(300, dibs.Ace3.libs.timer.scheduled[#dibs.Ace3.libs.timer.scheduled].delay)
    local staleCallback = dibs.Ace3.libs.timer.scheduled[#dibs.Ace3.libs.timer.scheduled].callback

    frame.SelectTab("history")
    assert_false(frame.channelTestAutoPingScheduled)
    frame.SelectTab("diagnostics")
    assert_true(frame.channelTestAutoPingScheduled)
    staleCallback()
    assert_true(frame.channelTestAutoPingScheduled)

    local activeCallback = dibs.Ace3.libs.timer.scheduled[#dibs.Ace3.libs.timer.scheduled].callback
    local sentBefore = #dibs.Ace3.libs.comm.sent
    activeCallback()
    assert_equal(sentBefore + 2, #dibs.Ace3.libs.comm.sent)
    assert_true(frame.channelTestAutoPingScheduled)
    frame.SelectTab("history")
    assert_false(frame.channelTestAutoPingScheduled)
  end)

  it("projects authoritative personal data without administrative or technical details", function()
    local _, dibs = setup()
    dibs.PlayerUI.GetSummary = function()
      return {
        player = "Tester-Realm",
        balance = 17,
        season = { id = 1, name = "Midnight" },
        activePreDibs = {
          { requestId = "request-1", itemID = 123, itemName = "Midnight Blade", status = "pending", createdAt = 100 },
        },
        acquisitions = {},
      }
    end
    dibs.Readiness.Evaluate = function() return {
      status = "Ready", reasonCodes = {}, integrationStatus = "Ready", liveConsumptionAllowed = true,
    } end
    dibs.Ledger.GetHistory = function()
      return {
        {
          createdAt = 100, itemName = "Midnight Blade", type = "AWARD", amount = -3,
          transactionId = "technical-id", epoch = 4, contentHash = "technical-hash",
          rootHash = "technical-root", evidenceId = "technical-evidence",
        },
      }
    end

    local view = dibs.PlayerUI.GetViewModel()
    assert_equal("Tester-Realm", view.player)
    assert_equal(17, view.balance)
    assert_equal("Midnight", view.seasonName)
    assert_equal(1, #view.activePreDibs)
    assert_equal("Ready", view.status.label)
    assert_nil(view.empty.activePreDibs)
    assert_false(containsForbiddenValue(view, { "RCLootCouncil - Dibs options", "Officer", "GM", "Developer", "hash", "epoch", "root", "evidence" }))
  end)

  it("shows season allocation, net Dibs use, remaining balance, and fulfilled Pre-Dibs separately", function()
    local _, dibs = setup({ wow = { playerName = "Tester-Realm", guildMembers = { "Tester-Realm" } } })
    local season = { id = "season-current", name = "Midnight S1" }
    dibs.Seasons.GetCurrent = function() return season end
    dibs.Ledger.GetPlayerHistorySummary = function()
      return { count = 3, seasonUsed = 2, balance = 3, allocation = 5 }
    end
    dibs.Ledger.GetCanonicalPlayerDibsState = function() return { available = true, balance = 3, availableBalance = 3 } end
    dibs.Ledger.GetPlayerState = function() return { allocation = 5, balance = 3 } end
    dibs.Ledger.GetHistory = function()
      return {
        { type = "SEASON_ALLOCATION", amount = 5, createdAt = 100 },
        { type = "DIB_USED", amount = -3, createdAt = 200 },
        { type = "DIB_REFUNDED", amount = 1, createdAt = 250 },
      }
    end
    dibs.PreDibs.GetActiveRequests = function()
      return {
        { requestId = "active-current", playerName = "Tester-Realm", itemName = "Current item", seasonId = "season-current", status = "confirmed", createdAt = 200 },
        { requestId = "active-old", playerName = "Tester-Realm", itemName = "Old item", seasonId = "season-old", status = "pending", createdAt = 100 },
      }
    end
    dibs.PreDibs.GetPlayerSeasonRequestSummary = function()
      return {
        active = {
          { requestId = "active-current", playerName = "Tester-Realm", itemName = "Current item", seasonId = "season-current", status = "confirmed", createdAt = 200 },
        },
        fulfilled = {
          { requestId = "won-current", playerName = "Tester-Realm", itemName = "Won item", seasonId = "season-current", status = "fulfilled", fulfilledAt = 300 },
        },
      }
    end
    local playerRequestFixture = {
        { requestId = "won-current", playerName = "Tester-Realm", itemName = "Won item", seasonId = "season-current", status = "fulfilled", fulfilledAt = 300 },
        { requestId = "won-old", playerName = "Tester-Realm", itemName = "Old win", seasonId = "season-old", status = "fulfilled", fulfilledAt = 200 },
        { requestId = "other-player", playerName = "Other-Realm", itemName = "Private win", seasonId = "season-current", status = "fulfilled", fulfilledAt = 400 },
      }
    dibs.PreDibs.GetHistory = function() return playerRequestFixture end
    dibs.PreDibs.GetRequestsForPlayer = function(playerName)
      local result = {}
      for _, request in ipairs(playerRequestFixture) do
        if string.lower(request.playerName) == string.lower(playerName) then result[#result + 1] = request end
      end
      return result
    end
    dibs.PreDibs.GetAcquisitionsForPlayer = function() return {} end

    local summary = dibs.PlayerUI.GetSummary()
    assert_equal(5, summary.seasonAllocation)
    assert_equal(2, summary.seasonUsed)
    assert_equal(3, summary.balance)
    assert_equal(1, #summary.activePreDibs)
    assert_equal("active-current", summary.activePreDibs[1].requestId)
    assert_equal(1, #summary.wonPreDibs)
    assert_equal("won-current", summary.wonPreDibs[1].requestId)

    local tables = {}
    local originalAddTable = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, options)
      local grid = originalAddTable(shell, parent, columns, rows, height, rowActions, options)
      tables[#tables + 1] = { columns = columns, rows = rows, height = height, options = options, grid = grid }
      return grid
    end
    local frame = dibs.PlayerUI.CreateWindow()
    frame.SelectTab("my-dibs")
    local metricTable = tables[1]
    assert_equal(3, #metricTable.columns)
    assert_equal("5", metricTable.rows[1][1])
    assert_equal("2", metricTable.rows[1][2])
    assert_equal("3", metricTable.rows[1][3])
    for _, column in ipairs(metricTable.columns) do assert_equal("CENTER", column.align) end
    local activeTable, wonTable
    for _, tableInfo in ipairs(tables) do
      if #tableInfo.columns == 5 and tableInfo.columns[5].action then activeTable = tableInfo end
      if #tableInfo.columns == 4 and tableInfo.columns[4].title == "Status" then wonTable = tableInfo end
    end
    assert_not_nil(activeTable)
    assert_true(activeTable.height < 170)
    assert_equal(1, #activeTable.rows)
    assert_equal("Current item", activeTable.rows[1][2])
    assert_not_nil(wonTable)
    assert_true(wonTable.height < 145)
    assert_equal(1, #wonTable.rows)
    assert_equal("Won item", wonTable.rows[1][2])

    local shell = frame.dibsAceGUIShell
    local windowFrame = shell.frame
    assert_not_nil(windowFrame._scripts.OnSizeChanged)
    windowFrame._scripts.OnSizeChanged(windowFrame, 900, 620)
    local wideWidths = {}
    for index, cell in ipairs(metricTable.grid.children[1].children) do
      wideWidths[index] = cell._dibsColumnWidth
    end
    windowFrame._scripts.OnSizeChanged(windowFrame, 650, 620)
    local narrowWidths = {}
    for index, cell in ipairs(metricTable.grid.children[1].children) do
      narrowWidths[index] = cell._dibsColumnWidth
    end
    assert_equal(3, #wideWidths)
    assert_equal(3, #narrowWidths)
    assert_true(wideWidths[1] > narrowWidths[1])
    assert_true(wideWidths[2] > narrowWidths[2])
    assert_true(wideWidths[3] > narrowWidths[3])
  end)

  it("uses intentional empty states and player-safe readiness explanations", function()
    local _, dibs = setup()
    dibs.PlayerUI.GetSummary = function()
      return { player = "Tester-Realm", balance = 0, season = nil, activePreDibs = {}, acquisitions = {} }
    end
    dibs.Ledger.GetHistory = function() return {} end
    dibs.Readiness.Evaluate = function() return {
      status = "Blocked", reasonCodes = { COORDINATOR_UNAVAILABLE = true },
    } end
    local view = dibs.PlayerUI.GetViewModel()
    assert_equal("No active Pre-Dibs this season.", view.empty.activePreDibs)
    assert_equal("No won Pre-Dibs this season.", view.empty.wonPreDibs)
    assert_equal("No history yet.", view.empty.history)
    assert_equal("Dibs temporarily unavailable", view.status.label)
    assert_equal("Guild Dibs is unavailable right now. Try again later or contact an Officer.", view.status.explanation)

    local status = dibs.PlayerUI.GetStatusPresentation({ status = "Unavailable", reasonCodes = { SYNC_BEHIND = true } })
    assert_equal("Syncing guild data", status.label)
    assert_equal("Your guild Dibs data is catching up. You can try again shortly.", status.explanation)
    status = dibs.PlayerUI.GetStatusPresentation({ status = "Unavailable", reasonCodes = { RECOVERY_PENDING = true } })
    assert_equal("Guild Dibs recovery in progress", status.label)
  end)

  it("keeps sandbox role simulation out of the normal Player surface", function()
    local _, dibs = setup({ wow = { guildLeader = true } })
    dibs.DeveloperMode.SetEnabled(true)
    local before = loader.snapshotProductionState(dibs)
    assert_true(dibs.DeveloperSandbox.EnterSandbox({ clone = true, role = "guild_master" }))
    local view = dibs.PlayerUI.GetViewModel()
    assert_equal("My Dibs", view.navigation[1].text)
    assert_false(containsForbiddenValue(view, { "Officer dashboard", "review administration", "reconciliation", "Developer Mode" }))
    assert_true(loader.productionStateEquals(dibs, before))
    assert_true(dibs.DeveloperSandbox.ExitSandbox())
  end)
end)
