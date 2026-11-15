local loader = require("helpers.load_addon")

local function framePoint(frame, pointName)
  for _, point in ipairs(frame and frame._points or {}) do
    if point[1] == pointName then return point end
  end
end

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

    local automatic, automaticReason = dibs.Ledger.RegisterSeasonAllocation("Alice-Realm", seasonId, 1, "Promotion to Member", {
        action = "ledger.adjust", actor = "Tester-Realm", actorId = "tester-realm", source = "automatic_rank_assignment",
      rankIndex = 3, rankName = "Member",
    })
      print("DEBUG automatic:", automatic, "reason:", automaticReason)
      if not automatic then
        local manual2 = dibs.Ledger.RegisterSeasonAllocation("Alice-Realm", seasonId, 1, "Officer correction", {
          action = "ledger.adjust", actor = "Tester-Realm", actorId = "tester-realm", source = "rank_reconciliation",
        })
        print("DEBUG manual:", manual2)
      end
      assert_not_nil(automatic)
      local manual, manualReason = dibs.Ledger.RegisterSeasonAllocation("Alice-Realm", seasonId, 1, "Officer correction", {
        action = "ledger.adjust", actor = "Tester-Realm", actorId = "tester-realm", source = "rank_reconciliation",
      })
      print("DEBUG manual:", manual, "reason:", manualReason)
      assert_not_nil(manual)

    local details = dibs.OfficerUI.BuildAutomaticAllocationDetails(seasonId)
    assert_equal(2, #details.allocations)
    assert_true(string.find(details.allocations[1], "Alice-Realm", 1, true) ~= nil)
    assert_true(string.find(details.allocations[1], "Member", 1, true) ~= nil)
    assert_true(string.find(details.allocations[1], "Difference -1", 1, true) ~= nil)

    local page = dibs.OfficerUI.GetPagedView("automaticDibs", seasonId, 1, 8)
    assert_equal("Automatic Dibs", page.title)
    assert_equal(2, page.totalCount)
    assert_equal(2, #page.rows)
    assert_true(page.rows[1].playerName ~= nil)
  end)

  it("does not run guild-wide reconciliation scans on the Automatic Dibs page", function()
    local _, dibs = loader.load({
      withAce3 = true,
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Alice-Realm" },
        guildRankIndices = { [1] = 0, [2] = 3 } },
    })
    local frame = dibs.OfficerUI.CreateWindow("overview")
    frame.dibsAceGUIShell.window.SetStatusText = function() end
    local original = dibs.RankRules.GetAllocationReconciliation
    local reads = 0
    dibs.RankRules.GetAllocationReconciliation = function()
      reads = reads + 1
      return {}
    end

    frame:ActivateRoute("automaticDibs")

    assert_equal(0, reads, "the seasonal route must not inspect the full guild roster")
    dibs.RankRules.GetAllocationReconciliation = original
  end)

  it("uses the compact season catalog summary for allocation details", function()
    local _, dibs = loader.load({
      wow = {
        guildLeader = true,
        guildMembers = { "Tester-Realm", "Alice-Realm" },
        guildRankIndices = { [1] = 0, [2] = 3 },
      },
    })
    local seasonId = dibs.GetCurrentSeasonId()
    local originalGetCatalogSummary = dibs.Seasons.GetCatalogSummary
    local originalGetCatalogState = dibs.Seasons.GetCatalogState
    dibs.Seasons.GetCatalogSummary = function()
      return { catalogRevision = 42, hash = "catalog-summary-test" }
    end
    dibs.Seasons.GetCatalogState = function() error("full season catalog copy is not needed") end

    local details = dibs.OfficerUI.BuildAutomaticAllocationDetails(seasonId, { deferSnapshots = true })

    dibs.Seasons.GetCatalogSummary = originalGetCatalogSummary
    dibs.Seasons.GetCatalogState = originalGetCatalogState
    assert_equal(42, details.seasonCatalogRevision)
    assert_equal("catalog-summary-test", details.rows[1].seasonCatalogHash)
  end)

  it("uses the compact catalog summary to build rank catalog status", function()
    local _, dibs = loader.load({})
    local originalGetCatalogSummary = dibs.Seasons.GetCatalogSummary
    local originalGetCatalogState = dibs.Seasons.GetCatalogState
    local originalGetCatalogRecord = dibs.Seasons.GetCatalogRecord
    local originalIsSyncBehind = dibs.Sync.IsSyncBehind
    dibs.Seasons.GetCatalogSummary = function()
      return { catalogRevision = 7, hash = "published-catalog" }
    end
    dibs.Seasons.GetCatalogState = function() error("full catalog copy is not needed for status") end
    dibs.Seasons.GetCatalogRecord = function(revision)
      assert_equal(7, revision)
      return { revision = revision }
    end
    dibs.Sync.IsSyncBehind = function() return false end

    local status = dibs.OfficerUI.BuildRankCatalogStatus()

    dibs.Seasons.GetCatalogSummary = originalGetCatalogSummary
    dibs.Seasons.GetCatalogState = originalGetCatalogState
    dibs.Seasons.GetCatalogRecord = originalGetCatalogRecord
    dibs.Sync.IsSyncBehind = originalIsSyncBehind
    assert_equal("Guild configuration: Synchronized.\nCatalog revision: 7", status)
  end)

  it("records Automatic Dibs route timings for a section-qualified navigation value", function()
    local _, dibs = loader.load({
      withAce3 = true,
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Alice-Realm" },
        guildRankIndices = { [1] = 0, [2] = 3 } },
    })
    local frame = dibs.OfficerUI.CreateWindow("overview")
    dibs.UIRenderStats.Reset()
    local originalDebugProfileStop = _G.debugprofilestop
    local profileTicks = 0
    _G.debugprofilestop = function()
      profileTicks = profileTicks + 1
      return profileTicks
    end
    dibs.UIRenderStats.SetEnabled(true)

    frame:ActivateRoute("section_dibs" .. string.char(1) .. "automaticDibs")

    dibs.UIRenderStats.SetEnabled(false)
    _G.debugprofilestop = originalDebugProfileStop
    assert_equal("automaticDibs", frame.activeTab)
    local recorded = {}
    for _, entry in ipairs(dibs.UIRenderStats.GetReport().pages) do
      if entry.kind == "Officer data" then recorded[entry.page] = true end
    end
    assert_true(recorded["automatic-dibs-route-preflight"])
    assert_true(recorded["automatic-dibs-route-resolution"])
    assert_true(recorded["automatic-dibs-content-clear"])
    assert_true(recorded["automatic-dibs-route-tree-selection"])
    assert_true(recorded["automatic-dibs-route-batch-start"])
    assert_true(recorded["automatic-dibs-route-body"])
    assert_true(recorded["automatic-dibs-route-layout-flush"])
    assert_true(recorded["automaticDibs-route-content-layout"])
    local tableTimings = {}
    for _, entry in ipairs(dibs.UIRenderStats.GetReport().pages) do
      if entry.kind == "UI table" then tableTimings[entry.page] = true end
    end
    assert_equal(0, next(tableTimings) and 1 or 0,
      "deferred seasonal reconciliation must not render the legacy guild-wide table")
  end)

  it("does not query the full module catalogue twice for a selected route", function()
    local _, dibs = loader.load({
      withAce3 = true,
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Alice-Realm" },
        guildRankIndices = { [1] = 0, [2] = 3 } },
    })
    local frame = dibs.OfficerUI.CreateWindow("overview")
    local originalGetModuleStatus = dibs.OperationalPolicy.GetModuleStatus
    local queried = {}
    dibs.OperationalPolicy.GetModuleStatus = function(moduleKey, ...)
      queried[moduleKey] = (queried[moduleKey] or 0) + 1
      return originalGetModuleStatus(moduleKey, ...)
    end

    frame:ActivateRoute("section_dibs" .. string.char(1) .. "automaticDibs")

    dibs.OperationalPolicy.GetModuleStatus = originalGetModuleStatus
    assert_equal("automaticDibs", frame.activeTab)
    -- The selected route's tree sync builds the visible navigation once. Route
    -- validation must not query every module a second time.
    assert_equal(1, queried.requests)
  end)

  it("skips the unrelated full Setup Assistant evaluation on Automatic Dibs", function()
    local _, dibs = loader.load({
      withAce3 = true,
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Alice-Realm" },
        guildRankIndices = { [1] = 0, [2] = 3 } },
    })
    local frame = dibs.OfficerUI.CreateWindow("overview")
    local originalEvaluate = dibs.SetupAssistant.Evaluate
    local evaluations = 0
    dibs.SetupAssistant.Evaluate = function(...)
      evaluations = evaluations + 1
      return originalEvaluate(...)
    end

    frame:ActivateRoute("automaticDibs")

    dibs.SetupAssistant.Evaluate = originalEvaluate
    assert_equal("automaticDibs", frame.activeTab)
    assert_equal(0, evaluations)
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

describe("Automatic Dibs seasonal safety surface", function()
  it("does not project guild-wide allocations or expose reconciliation actions before a seasonal roster exists", function()
    local _, dibs = loader.load({
      withAce3 = true,
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Alice-Realm" },
        guildRankIndices = { [1] = 0, [2] = 3 } },
    })
    local frame = dibs.OfficerUI.CreateWindow("overview")
    local allocationReads, detailReads = 0, 0
    local originalReconciliation = dibs.RankRules.GetAllocationReconciliation
    local originalDetails = dibs.OfficerUI.BuildAutomaticAllocationDetails
    dibs.RankRules.GetAllocationReconciliation = function() allocationReads = allocationReads + 1; return {} end
    dibs.OfficerUI.BuildAutomaticAllocationDetails = function() detailReads = detailReads + 1; return {} end

    frame:ActivateRoute("automaticDibs")

    dibs.RankRules.GetAllocationReconciliation = originalReconciliation
    dibs.OfficerUI.BuildAutomaticAllocationDetails = originalDetails
    assert_equal("automaticDibs", frame.activeTab)
    assert_equal(0, allocationReads, "guild-wide allocation projection must not run")
    assert_equal(0, detailReads, "the legacy allocation detail projection must not run")
    assert_not_nil(frame.automaticDibsTablePage, "the page shell should remain available")
    assert_nil(frame.RefreshAutomaticDibsTable)
    assert_nil(frame.ReflowAutomaticDibsTable)

    local labels, buttons = {}, {}
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Label" and type(widget.text) == "string" then labels[#labels + 1] = widget.text end
      if widget.kind == "Button" and type(widget.text) == "string" then buttons[widget.text] = true end
    end
    local combinedLabels = table.concat(labels, "\n")
    assert_true(combinedLabels:find("Create the first seasonal raid roster", 1, true) ~= nil)
    assert_false(buttons["Reconcile All"] == true)
    assert_false(buttons["Refresh roster"] == true)
  end)
end)
describe("Officer Dibs administration", function()
  local members = { "Tester-Realm", "Officer-Realm", "Firebut-DunModr", "Member-Realm" }
  local ranks = { [1] = 0, [2] = 1, [3] = 2, [4] = 3 }

  local function loadOfficer(playerName, guildLeader, extraPlayers, locale)
    local officerMembers, officerRanks = {}, {}
    for index, member in ipairs(members) do
      officerMembers[index], officerRanks[index] = member, ranks[index]
    end
    for playerIndex = 1, extraPlayers or 0 do
      officerMembers[#officerMembers + 1] = string.format("Extra%02d-Realm", playerIndex)
      officerRanks[#officerMembers] = 3
    end
    local _, dibs = loader.load({ withAce3 = true, wow = {
      locale = locale,
      playerName = playerName,
      guildLeader = guildLeader,
      guildMembers = officerMembers,
      guildRankIndices = officerRanks,
        realmName = "DunModr",
      } })
      return dibs
    end

  local function clickLatestButton(text)
    for index = #(_G.__dibsAceWidgets or {}), 1, -1 do
      local widget = _G.__dibsAceWidgets[index]
      if widget.kind == "Button" and widget.text == text then
        assert_not_nil(widget.callbacks.OnClick)
        widget.callbacks.OnClick(widget, "OnClick")
        return widget
      end
    end
    error("Button not found: " .. text)
  end

  local function findLatestWidget(predicate)
    for index = #(_G.__dibsAceWidgets or {}), 1, -1 do
      local widget = _G.__dibsAceWidgets[index]
      if predicate(widget) then return widget end
    end
  end

  local function openAdminPage(dibs)
    local frame = dibs.OfficerUI.CreateWindow("dibsAdmin")
    frame:ActivateRoute("dibsAdmin")
    return frame
  end

  local function searchRoster(query)
    local search = findLatestWidget(function(widget) return widget.label == "Search player" end)
    assert_not_nil(search)
    search.callbacks.OnTextChanged(search, "OnTextChanged", query)
  end

  local function setConfirmationReason(reasonId, detailText)
    local reason = findLatestWidget(function(widget)
      return widget.kind == "Dropdown" and widget.label == "Reason"
    end)
    assert_not_nil(reason)
    assert_true(reason.list[reasonId] ~= nil)
    reason.callbacks.OnValueChanged(reason, "OnValueChanged", reasonId)
    local details = findLatestWidget(function(widget) return widget.label == "Details (optional)" end)
    assert_not_nil(details)
    details.callbacks.OnTextChanged(details, "OnTextChanged", detailText or "")
    return reason, details
  end

  it("renders Dibs Administration with shared fluid columns and same-row actions", function()
    local dibs = loadOfficer("Tester-Realm", true)
    local captured
    local originalAddTable = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, options)
      captured = { parent = parent, columns = columns, rows = rows, options = options }
      return originalAddTable(shell, parent, columns, rows, height, rowActions, options)
    end
    local frame = openAdminPage(dibs)
    local page = frame.dibsAdminTablePage
    local panelHeight = 700
    page.boundsFrame.GetHeight = function() return panelHeight end
    page.boundsFrame.GetWidth = function() return 900 end
    page.header.frame.GetHeight = function() return 72 end
    page.columnHeader.frame.GetHeight = function() return 28 end
    page.UpdateViewportHeight()
    assert_true(page.scroll.height >= dibs.AceGUI.GetLayoutMetrics().tableViewportMinimum)
    assert_equal(1, #page.scroll.children)
    local tableHost = frame.dibsAdminTableHost
    assert_true(#tableHost.children > 0)
    assert_equal(#captured.rows, #tableHost.children)
    assert_equal(page.boundsFrame, framePoint(page.root.frame, "TOPLEFT")[2])
    assert_equal(page.columnHeader.frame, framePoint(page.scroll.frame, "TOPLEFT")[2])
    assert_equal("BOTTOMLEFT", framePoint(page.scroll.frame, "TOPLEFT")[3])
    assert_equal(page.root, page.scroll.parent)
    assert_equal(page.root.height, 700)
    assert_true(captured.options.fluidColumns)
    assert_equal(tableHost, captured.parent)
    assert_equal(page.columnHeader, captured.options.headerParent)
    assert_equal(5, #captured.columns)
    assert_true(captured.columns[1].weight > 0)
    assert_true(captured.columns[3].fixed)
    assert_true(captured.columns[2].weight > 0)
    assert_true(captured.columns[4].fixed and captured.columns[5].fixed)
    local addLabel, removeLabel = dibs.L.UI_ACTION_DIBS_ADD, dibs.L.UI_ACTION_DIBS_REMOVE
    assert_equal(dibs.AceGUI.GetContentSizedActionWidth({ addLabel }, 48), captured.columns[4].width)
    assert_equal(dibs.AceGUI.GetContentSizedActionWidth({ removeLabel }, 48), captured.columns[5].width)
    assert_equal(addLabel, captured.columns[4].title)
    assert_equal(removeLabel, captured.columns[5].title)
    assert_equal(130, captured.columns[1].minWidth)
    assert_equal(2, captured.columns[1].weight)
    assert_equal("CENTER", captured.columns[2].align)
    assert_equal("CENTER", captured.columns[3].align)
    assert_true(captured.columns[4].width < dibs.AceGUI.GetLayoutMetrics().actionMinWidth)
    assert_true(captured.columns[5].width < dibs.AceGUI.GetLayoutMetrics().actionMinWidth)
    local rowMenu = captured.options.contextMenu(captured.rows[1])
    assert_equal(addLabel, rowMenu[1].text)
    assert_equal(removeLabel, rowMenu[2].text)
    assert_equal(page.root, page.scroll.parent)
    assert_equal(page.root, page.columnHeader.parent)
    local registeredScrolls = 0
    for _, scroll in ipairs(frame.dibsAceGUIShell._dibsResponsiveScrolls) do
      if scroll == page.scroll then registeredScrolls = registeredScrolls + 1 end
    end
    assert_equal(1, registeredScrolls)

    local window = frame.dibsAceGUIShell.window
    local originalDoLayout = window.DoLayout
    window.DoLayout = function() panelHeight = 640 end
    frame.dibsAceGUIShell.frame._scripts.OnSizeChanged(frame.dibsAceGUIShell.frame, 900, 640)
    assert_equal(640, page.root.height)
    window.DoLayout = originalDoLayout

    local actionRows = 0
    for _, rowGroup in ipairs(tableHost.children) do
      local addButton, removeButton
      for _, child in ipairs(rowGroup.children or {}) do
        if child.kind == "Button" and child.text == addLabel then addButton = child end
        if child.kind == "Button" and child.text == removeLabel then removeButton = child end
      end
      if addButton or removeButton then
        assert_not_nil(addButton)
        assert_not_nil(removeButton)
        assert_equal(addButton.parent, removeButton.parent)
        assert_equal(rowGroup, addButton.parent)
        assert_true(addButton.frame:GetWidth() >= addButton._dibsRequiredWidth)
        assert_true(removeButton.frame:GetWidth() >= removeButton._dibsRequiredWidth)
        assert_equal(captured.columns[4].width, addButton._dibsColumnWidth)
        assert_equal(captured.columns[5].width, removeButton._dibsColumnWidth)
        actionRows = actionRows + 1
      end
    end
    assert_equal(#captured.rows, actionRows)
    assert_not_nil(frame)
  end)

  it("keeps localized ADD and REMOVE buttons content-sized across supported widths", function()
    for _, locale in ipairs({ "enUS", "frFR" }) do
      local dibs = loadOfficer("Tester-Realm", true, nil, locale)
      local capture
      local originalAddTable = dibs.AceGUI.AddTable
      dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, options)
        capture = { columns = columns, rows = rows, options = options }
        return originalAddTable(shell, parent, columns, rows, height, rowActions, options)
      end
      local frame = openAdminPage(dibs)
      local page = frame.dibsAdminTablePage
      local tableHost = frame.dibsAdminTableHost
      local addLabel, removeLabel = dibs.L.UI_ACTION_DIBS_ADD, dibs.L.UI_ACTION_DIBS_REMOVE
      local fixedWidths
      page.boundsFrame.GetHeight = function() return 760 end
      for _, testWidth in ipairs({ 1400, 900, 520 }) do
        page.boundsFrame.GetWidth = function() return testWidth end
        page.UpdateViewportHeight()
        local addColumnIndex, removeColumnIndex = 4, 5
        local addColumn, removeColumn = capture.columns[addColumnIndex], capture.columns[removeColumnIndex]
        assert_true(addColumn.fixed and removeColumn.fixed)
        assert_nil(addColumn.weight)
        assert_nil(removeColumn.weight)
        assert_equal(dibs.AceGUI.GetContentSizedActionWidth({ addLabel }, 48), addColumn.width)
        assert_equal(dibs.AceGUI.GetContentSizedActionWidth({ removeLabel }, 48), removeColumn.width)
        fixedWidths = fixedWidths or { addColumn.width, removeColumn.width }
        assert_equal(fixedWidths[1], addColumn.width)
        assert_equal(fixedWidths[2], removeColumn.width)

        local addButtons, removeButtons = 0, 0
        for _, rowGroup in ipairs(tableHost.children or {}) do
          for _, button in ipairs(rowGroup.children or {}) do
            if button.kind == "Button" and (button.text == addLabel or button.text == removeLabel) then
              local column = button.text == addLabel and addColumn or removeColumn
              local fontString = button.frame:GetFontString()
              local requiredWidth = fontString:GetStringWidth()
                + dibs.AceGUI.GetLayoutMetrics().buttonHorizontalPadding
                + dibs.AceGUI.GetLayoutMetrics().buttonSizingSafetyMargin
              assert_true(button.frame:GetWidth() >= requiredWidth)
              assert_true(button.frame:GetWidth() >= button._dibsRequiredWidth)
              assert_equal(column.width, button._dibsColumnWidth)
              assert_equal(button.text == addLabel and addColumnIndex or removeColumnIndex, button._dibsColumnIndex)
              if button.text == addLabel then addButtons = addButtons + 1
              else removeButtons = removeButtons + 1 end
            end
          end
        end
        assert_true(addButtons > 0)
        assert_true(removeButtons > 0)
      end
      assert_equal(0, dibs.Ledger.GetCanonicalState().commitCount)
    end
  end)

  it("uses the shared Administration pager for page sizes, navigation, and resize", function()
    local dibs = loadOfficer("Tester-Realm", true, 28)
    local capture
    local originalAddTable = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, options)
      capture = { parent = parent, columns = columns, rows = rows, options = options }
      return originalAddTable(shell, parent, columns, rows, height, rowActions, options)
    end
    local frame = openAdminPage(dibs)
    local page = frame.dibsAdminTablePage
    local panelWidth, panelHeight = 900, 700
    page.boundsFrame.GetWidth = function() return panelWidth end
    page.boundsFrame.GetHeight = function() return panelHeight end
    page.header.frame.GetHeight = function() return 72 end
    page.columnHeader.frame.GetHeight = function() return 28 end
    page.UpdateViewportHeight()
    local viewportHeight = page.scroll.height
    local footerPoint = framePoint(page.footer.frame, "BOTTOMLEFT")
    assert_equal("Page 1 / 4", frame.dibsAdminPageIndicator.text)
    assert_equal(10, #capture.rows)
    assert_equal("INLINE", frame.dibsAdminPagination.layoutMode)
    assert_equal(page.footer, frame.dibsAdminPagination.navigationGroup.parent)
    assert_equal(page.footer, frame.dibsAdminPagination.pageSizeGroup.parent)
    local adminPagination = frame.dibsAdminPagination
    local adminPreviousPoint = framePoint(adminPagination.previous.frame, "LEFT")
    local adminPagePoint = framePoint(adminPagination.page.frame, "LEFT")
    local adminNextPoint = framePoint(adminPagination.next.frame, "LEFT")
    local adminRowsLabelPoint = framePoint(adminPagination.pageSizeLabel.frame, "LEFT")
    local adminRowsDropdownPoint = framePoint(adminPagination.pageSize.frame, "LEFT")
    assert_equal(adminPagination.navigationGroup.frame, adminPreviousPoint[2])
    assert_equal(adminPagination.previous.frame, adminPagePoint[2])
    assert_equal("RIGHT", adminPagePoint[3])
    assert_equal(adminPagination.page.frame, adminNextPoint[2])
    assert_equal("RIGHT", adminNextPoint[3])
    assert_equal(adminPagination.pageSizeGroup.frame, adminRowsLabelPoint[2])
    assert_equal(adminPagination.pageSizeLabel.frame, adminRowsDropdownPoint[2])
    assert_equal("RIGHT", adminRowsDropdownPoint[3])
    assert_true(adminPagination.navigationGroup.frame:GetWidth()
      >= adminPagination.previous.frame:GetWidth() + adminPagination.page.frame:GetWidth()
        + adminPagination.next.frame:GetWidth())
    assert_true(adminPagination.pageSizeGroup.frame:GetWidth()
      >= adminPagination.pageSizeLabel.frame:GetWidth() + adminPagination.pageSize.frame:GetWidth())
    assert_true(frame.dibsAdminPagination.pageSizeHeight >= 26)
    assert_true(page.footer.height >= frame.dibsAdminPagination.pageSizeHeight)

    local function choosePageSize(size)
      local dropdown = findLatestWidget(function(widget)
        return widget.kind == "Dropdown" and widget._dibsRowsPerPageSelector
      end)
      assert_not_nil(dropdown)
      dropdown.callbacks.OnValueChanged(dropdown, "OnValueChanged", tostring(size))
      assert_equal(size, frame.dibsAdminPageSize)
      assert_equal(math.min(size, 32), #capture.rows)
      assert_equal("Page 1 / " .. math.ceil(32 / size), frame.dibsAdminPageIndicator.text)
      assert_equal(viewportHeight, page.scroll.height)
      local nextFooterPoint = framePoint(page.footer.frame, "BOTTOMLEFT")
      assert_equal(footerPoint[2], nextFooterPoint[2])
      assert_equal(footerPoint[3], nextFooterPoint[3])
      assert_equal(#capture.rows, #frame.dibsAdminTableHost.children)
    end

    for _, size in ipairs({ 5, 10, 15, 20 }) do
      choosePageSize(size)
    end
    choosePageSize(5)
    local firstPageName = capture.rows[1].adminRosterRow.playerName
    clickLatestButton("Next")
    assert_equal(2, frame.dibsAdminPage)
    assert_equal("Page 2 / 7", frame.dibsAdminPageIndicator.text)
    assert_equal(5, #capture.rows)
    assert_true(capture.rows[1].adminRosterRow.playerName ~= firstPageName)
    clickLatestButton("Previous")
    assert_equal(1, frame.dibsAdminPage)
    assert_equal(0, dibs.Ledger.GetCanonicalState().commitCount)

    for _, width in ipairs({ 1300, 1000, 650, 1300 }) do
      panelWidth = width - 240
      frame.dibsAceGUIShell.frame._scripts.OnSizeChanged(frame.dibsAceGUIShell.frame, width, 700)
      dibs.AceGUI.FlushRefreshes()
      assert_true(page.scroll.height >= dibs.AceGUI.GetLayoutMetrics().tableViewportMinimum)
      assert_equal(page.root, page.scroll.parent)
      assert_equal(page.root, page.footer.parent)
      local inline = panelWidth >= frame.dibsAdminPagination.navigationWidth
        + frame.dibsAdminPagination.pageSizeWidth + frame.dibsAdminPagination.footerGap
      assert_equal(inline and "INLINE" or "STACKED", frame.dibsAdminPagination.layoutMode)
    end
    local function assertAdminPageGeometry()
      page.UpdateViewportHeight()
      local footerBottom = framePoint(page.footer.frame, "BOTTOMLEFT")
      local footerRight = framePoint(page.footer.frame, "BOTTOMRIGHT")
      local viewportTop = framePoint(page.scroll.frame, "TOPLEFT")
      local viewportBottom = framePoint(page.scroll.frame, "BOTTOMRIGHT")
      assert_equal(page.boundsFrame, footerBottom[2])
      assert_equal(page.boundsFrame, footerRight[2])
      assert_equal("BOTTOMLEFT", footerBottom[1])
      assert_equal("BOTTOMRIGHT", footerRight[1])
      assert_equal(0, footerBottom[5])
      local footerHeight = page.footer.frame:GetHeight()
      local footerTop = panelHeight - footerHeight
      assert_true(footerTop >= 0)
      assert_true(footerTop + footerHeight <= panelHeight)
      assert_equal(page.columnHeader.frame, viewportTop[2])
      assert_equal("BOTTOMLEFT", viewportTop[3])
      assert_equal(page.footer.frame, viewportBottom[2])
      assert_equal("TOPRIGHT", viewportBottom[3])
      assert_equal(2, #page.footer.frame._points)
      assert_equal(2, #page.scroll.frame._points)
      assert_equal(page.root, page.footer.parent)
      assert_equal(page.root, page.scroll.parent)
      assert_true(page.footer.parent ~= frame.dibsAdminTableHost)
      assert_true(page.footer.parent ~= page.scroll)
    end
    panelWidth, panelHeight = 900, 700
    assertAdminPageGeometry()
    local stableFooterAnchor = framePoint(page.footer.frame, "BOTTOMLEFT")
    for _ = 1, 100 do
      assertAdminPageGeometry()
      local currentAnchor = framePoint(page.footer.frame, "BOTTOMLEFT")
      for pointIndex = 1, 5 do assert_equal(stableFooterAnchor[pointIndex], currentAnchor[pointIndex]) end
    end
    local alternatingWidths = { 1300, 1000, 1300, 1000, 650, 1000 }
    for index = 1, 100 do
      local width = alternatingWidths[(index - 1) % #alternatingWidths + 1]
      panelWidth = width - 240
      frame.dibsAceGUIShell.frame._scripts.OnSizeChanged(frame.dibsAceGUIShell.frame, width, 700)
      dibs.AceGUI.FlushRefreshes()
      assertAdminPageGeometry()
      local currentAnchor = framePoint(page.footer.frame, "BOTTOMLEFT")
      for pointIndex = 1, 5 do assert_equal(stableFooterAnchor[pointIndex], currentAnchor[pointIndex]) end
    end
    local baseFooterLayout = page.footer._dibsBaseLayoutFunc
    assert_not_nil(page.footer._dibsTablePageLayout)
    dibs.AceGUI.ReleaseOwnedState(page.footer)
    assert_equal(baseFooterLayout, page.footer.LayoutFunc)
    assert_nil(page.footer._dibsTablePageLayout)
  end)

  it("loads Dibs balances only for visible rows unless sorting by balance", function()
    local dibs = loadOfficer("Tester-Realm", true, 20)
    local originalSummary = dibs.Ledger.GetPlayerHistorySummary
    local originalBatchSummaries = dibs.Ledger.GetPlayerHistorySummaries
    local summaryCalls, batchCalls, batchPlayerCount = 0, 0, 0
    dibs.Ledger.GetPlayerHistorySummary = function(...)
      summaryCalls = summaryCalls + 1
      return originalSummary(...)
    end
    dibs.Ledger.GetPlayerHistorySummaries = function(players, ...)
      batchCalls = batchCalls + 1
      batchPlayerCount = batchPlayerCount + #players
      return originalBatchSummaries(players, ...)
    end

    local frame = dibs.OfficerUI.CreateWindow("dibsAdmin")
    local visibleCount = math.min(10, #frame.dibsAdminCachedRoster.rows)
    assert_equal(1, batchCalls, "the visible page should use one grouped balance lookup")
    assert_equal(visibleCount, batchPlayerCount,
      "the default name-sorted page should read balances only for its visible rows")
    assert_equal(0, summaryCalls, "the default page should not perform per-row summary lookups")
    assert_true(#frame.dibsAdminCachedRoster.rows > 10)
    assert_not_nil(frame.dibsAdminCachedRoster.rows[1].balance)
    assert_nil(frame.dibsAdminCachedRoster.rows[11].balance,
      "off-page balances should remain uncomputed until the user visits that page")

    summaryCalls = 0
    batchCalls, batchPlayerCount = 0, 0
    local byBalance = dibs.OfficerUI.BuildDibsAdministrationRoster(
      dibs.GetCurrentSeasonId(), "", "balance", true)
    assert_equal(#byBalance.rows, batchPlayerCount,
      "balance sorting must compute each matching member balance to preserve the sort order")
    assert_equal(1, batchCalls, "full-list balance sorting should use one grouped lookup")
    assert_equal(0, summaryCalls, "balance sorting should not perform per-row summary lookups")
    dibs.Ledger.GetPlayerHistorySummary = originalSummary
    dibs.Ledger.GetPlayerHistorySummaries = originalBatchSummaries
  end)

  it("projects offline-capable roster members without creating ledger records and sorts and searches", function()
      io.stderr:write("DEBUG: Test function entered\n")
      io.stderr:flush()
      local dibs = loadOfficer("Tester-Realm", true)
      io.stderr:write("DEBUG: loadOfficer returned\n")
      io.stderr:flush()
      local seasonId = dibs.GetCurrentSeasonId()
        io.stderr:write("DEBUG: seasonId=" .. tostring(seasonId) .. "\n")
        io.stderr:flush()
      
        -- DEBUG: Check Identity state before grant
        io.stderr:write("DEBUG: Identity._rosterState.fresh=" .. tostring(Dibs.Identity._rosterState and Dibs.Identity._rosterState.fresh) .. "\n")
        io.stderr:write("DEBUG: Identity._rosterState.generation=" .. tostring(Dibs.Identity._rosterState and Dibs.Identity._rosterState.generation) .. "\n")
        if Dibs.Identity._rosterState and Dibs.Identity._rosterState.members then
          for k,v in pairs(Dibs.Identity._rosterState.members) do
            io.stderr:write("DEBUG: member " .. k .. " = " .. tostring(v.displayName) .. " rankIndex=" .. tostring(v.rankIndex) .. "\n")
          end
        else
          io.stderr:write("DEBUG: No members in rosterState\n")
        end
        -- DEBUG: Check ResolveRosterMember
        local resolved = Dibs.Identity and Dibs.Identity.ResolveRosterMember and Dibs.Identity.ResolveRosterMember("Firebut-DunModr")
        io.stderr:write("DEBUG: ResolveRosterMember(Firebut-DunModr) = " .. tostring(resolved and resolved.status or "nil") .. "\n")
        if resolved then
          for k,v in pairs(resolved) do
            io.stderr:write("DEBUG: resolved[" .. k .. "] = " .. tostring(v) .. "\n")
          end
        end
                -- DEBUG: Check CreateSnapshot
                local snapshot, reason = Dibs.Identity and Dibs.Identity.CreateSnapshot and Dibs.Identity.CreateSnapshot("Firebut-DunModr")
                io.stderr:write("DEBUG: CreateSnapshot(Firebut-DunModr) snapshot=" .. tostring(snapshot) .. " reason=" .. tostring(reason) .. "\n")
                if snapshot then
                  for k,v in pairs(snapshot) do
                    io.stderr:write("DEBUG: snapshot[" .. k .. "] = " .. tostring(v) .. "\n")
                  end
                end
                io.stderr:flush()
      
        local grant = dibs.ProtectedActions.Execute("ledger.grant", nil, {
          playerName = "Firebut-DunModr", amount = 2, reason = "Sort fixture", source = "test", seasonId = seasonId,
        })
        io.stderr:write("DEBUG: grant=" .. tostring(grant) .. ", grant.ok=" .. tostring(grant and grant.ok) .. "\n")
        if grant and grant.error then io.stderr:write("DEBUG: grant.error=" .. tostring(grant.error) .. "\n") end
        if grant then for k,v in pairs(grant) do io.stderr:write("DEBUG: grant[" .. k .. "]=" .. tostring(v) .. "\n") end end
        io.stderr:flush()
        assert_true(grant.ok)
        local before = #dibs.Ledger.GetAllTransactions()
        io.stderr:write("DEBUG: before=" .. tostring(before) .. "\n")
        io.stderr:flush()
    
        -- DEBUG: Print at the very beginning
        io.stderr:write("DEBUG: Test started\n")
        io.stderr:flush()
    
        -- DEBUG: Check what GetGuildRosterInfo returns
        local debugLines = {}
        table.insert(debugLines, "GetGuildRosterInfo calls:")
        for i = 1, 4 do
          local rosterInfo = { pcall(_G.GetGuildRosterInfo, i) }
          table.insert(debugLines, "  index " .. i .. ": success=" .. tostring(rosterInfo[1]) .. ", name=" .. tostring(rosterInfo[2]) .. ", rankIndex=" .. tostring(rosterInfo[4]))
        end
    
        -- DEBUG: Check CanonicalMemberKey directly
        table.insert(debugLines, "CanonicalMemberKey calls:")
        for _, name in ipairs({"Tester-Realm", "Officer-Realm", "Firebut-DunModr", "Member-Realm"}) do
          local key = Dibs.Identity and Dibs.Identity.CanonicalMemberKey and Dibs.Identity.CanonicalMemberKey(name)
          table.insert(debugLines, "  " .. name .. " -> " .. tostring(key))
        end
    
        local roster = dibs.OfficerUI.BuildDibsAdministrationRoster(seasonId, "", "rank", false)
    
        -- DEBUG: Print roster rows
        table.insert(debugLines, "Roster rows:")
        for i, row in ipairs(roster.rows) do
          table.insert(debugLines, "  row " .. i .. ": playerName=" .. tostring(row.playerName) .. ", memberKey=" .. tostring(row.memberKey) .. ", identityAvailable=" .. tostring(row.identityAvailable) .. ", rankIndex=" .. tostring(row.rankIndex))
        end
    
        -- Print debug info to stdout and stderr BEFORE assertion
        local debugMsg = table.concat(debugLines, "\n")
        io.stderr:write("DEBUG OUTPUT BEFORE ASSERTION:\n" .. debugMsg .. "\n")
        io.stderr:flush()
        io.write("DEBUG OUTPUT BEFORE ASSERTION:\n" .. debugMsg .. "\n")
        io.flush()

        assert_equal("ready", roster.state)
        assert_equal(4, #roster.rows)
        assert_equal("Tester-Realm", roster.rows[1].playerName)
        assert_equal("Firebut-DunModr", roster.rows[3].playerName)
        assert_equal(2, roster.rows[3].balance)
        assert_true(roster.rows[3].identityAvailable, debugMsg .. "\nidentityAvailable was false for row 3: " .. tostring(roster.rows[3].identityAvailable))
        assert_equal(before, #dibs.Ledger.GetAllTransactions())
    local byBalance = dibs.OfficerUI.BuildDibsAdministrationRoster(seasonId, "", "balance", true)
    assert_equal("Firebut-DunModr", byBalance.rows[1].playerName)

    local filtered = dibs.OfficerUI.BuildDibsAdministrationRoster(seasonId, "firebut", "name", false)
    assert_equal(1, #filtered.rows)
    assert_equal("Firebut-DunModr", filtered.rows[1].playerName)

    local _, duplicateDibs = loader.load({ withAce3 = true, wow = {
      playerName = "Tester-Realm", guildLeader = true,
      guildMembers = { "Tester-Realm", "Twin", "Twin" },
      guildRankIndices = { [1] = 0, [2] = 2, [3] = 3 },
    } })
    local duplicateRows = duplicateDibs.OfficerUI.BuildDibsAdministrationRoster(duplicateDibs.GetCurrentSeasonId(), "Twin", "name", false)
    assert_equal(2, #duplicateRows.rows)
    assert_false(duplicateRows.rows[1].identityAvailable)
    assert_false(duplicateRows.rows[2].identityAvailable)

    local _, repeatedRealmDibs = loader.load({ withAce3 = true, wow = {
      playerName = "Tester-Realm", guildLeader = true,
      guildMembers = { "Tester-Realm", "Manu-Zul'jin-Zul'jin-Zul'jin" },
      guildRankIndices = { [1] = 0, [2] = 3 },
    } })
    local repeatedRealmRows = repeatedRealmDibs.OfficerUI.BuildDibsAdministrationRoster(
      repeatedRealmDibs.GetCurrentSeasonId(), "Manu", "name", false)
    assert_equal(1, #repeatedRealmRows.rows)
    assert_equal("Manu-Zul'jin", repeatedRealmRows.rows[1].playerName)
    assert_equal("manu-zul'jin-zul'jin-zul'jin", repeatedRealmRows.rows[1].memberKey)
  end)

  it("allows GM ADD +1 only after confirmation and records the trimmed reason", function()
    local dibs = loadOfficer("Tester-Realm", true)
    local seasonId = dibs.GetCurrentSeasonId()
    local frame = openAdminPage(dibs)
    searchRoster("Firebut")
    local beforeCount = #dibs.Ledger.GetAllTransactions()
    local originalExecute = dibs.ProtectedActions.Execute
    local submitted
    dibs.ProtectedActions.Execute = function(action, actor, payload)
      submitted = { action = action, actor = actor, payload = payload }
      return originalExecute(action, actor, payload)
    end

    clickLatestButton("ADD")
    assert_equal(beforeCount, #dibs.Ledger.GetAllTransactions())
    local reason = findLatestWidget(function(widget) return widget.kind == "Dropdown" and widget.label == "Reason" end)
    assert_equal("MANUAL_ADMIN_ADDITION", reason.value)
    assert_equal("Manual administrative addition", reason.list[reason.value])
    setConfirmationReason("MANUAL_ADMIN_ADDITION", "Raid contribution")
    local confirm = clickLatestButton("Add Dib")
    assert_equal("Dibs | Confirm Dibs change", confirm.parent.parent.parent.title)
    assert_equal("List", confirm.parent.parent.layout)

    assert_equal("ledger.adjust", submitted.action)
    assert_equal("Firebut-DunModr", submitted.payload.playerName)
    assert_equal(1, submitted.payload.amount)
    assert_equal("Manual administrative addition: Raid contribution", submitted.payload.reason)
    assert_equal("MANUAL_ADMIN", submitted.payload.source)
    assert_equal(seasonId, submitted.payload.seasonId)
    assert_equal(beforeCount + 1, #dibs.Ledger.GetAllTransactions())
    assert_equal(1, dibs.Ledger.GetBalance("Firebut-DunModr", seasonId))
    local transaction = dibs.Ledger.GetHistory("Firebut-DunModr", seasonId)[#dibs.Ledger.GetHistory("Firebut-DunModr", seasonId)]
    assert_equal(1, transaction.amount)
    assert_equal("MANUAL_ADMIN", transaction.source)
    assert_equal("Manual administrative addition: Raid contribution", transaction.reason)
    assert_not_nil(transaction.transactionId)
    assert_not_nil(transaction.createdAt)
    assert_not_nil(transaction.actorId)
    assert_equal(seasonId, transaction.seasonId)
    assert_equal("Firebut-DunModr", transaction.playerName)
    assert_true(frame.activeTab == "dibsAdmin")
  end)

  it("allows an Officer ADD +1 and a GM REMOVE -1 through the authoritative action", function()
    local officer = loadOfficer("Officer-Realm", false)
    local seasonId = officer.GetCurrentSeasonId()
    local officerFrame = openAdminPage(officer)
    searchRoster("Firebut")
    clickLatestButton("ADD")
    local officerReason = findLatestWidget(function(widget) return widget.kind == "Dropdown" and widget.label == "Reason" end)
    assert_equal("MANUAL_ADMIN_ADDITION", officerReason.value)
    setConfirmationReason("MANUAL_ADMIN_ADDITION", "Officer bonus")
    clickLatestButton("Add Dib")
    assert_equal(1, officer.Ledger.GetBalance("Firebut-DunModr", seasonId))
    assert_true(officerFrame.activeTab == "dibsAdmin")

    local gm = loadOfficer("Tester-Realm", true)
    local gmSeason = gm.GetCurrentSeasonId()
    local grant = gm.ProtectedActions.Execute("ledger.grant", nil, {
      playerName = "Firebut-DunModr", amount = 1, reason = "Test starting balance", source = "test", seasonId = gmSeason,
    })
    assert_true(grant.ok)
    openAdminPage(gm)
    searchRoster("Firebut")
    clickLatestButton("REMOVE")
    local gmReason = findLatestWidget(function(widget) return widget.kind == "Dropdown" and widget.label == "Reason" end)
    assert_equal("MANUAL_ADMIN_REMOVAL", gmReason.value)
    setConfirmationReason("OTHER", "Attendance correction")
    local removeConfirm = clickLatestButton("Remove Dib")
    assert_equal("Remove Dib", removeConfirm.text)
    assert_equal(0, gm.Ledger.GetBalance("Firebut-DunModr", gmSeason))
    local history = gm.Ledger.GetHistory("Firebut-DunModr", gmSeason)
    local transaction = history[#history]
    assert_equal(-1, transaction.amount)
    assert_equal("MANUAL_ADMIN", transaction.source)
    assert_equal("Attendance correction", transaction.reason)
  end)

  it("rejects nil, empty, or whitespace-only MANUAL_ADMIN reasons at the authority boundary", function()
    local dibs = loadOfficer("Tester-Realm", true)
    local seasonId = dibs.GetCurrentSeasonId()
    local beforeCount = #dibs.Ledger.GetAllTransactions()
    for _, reason in ipairs({ "", "   \t " }) do
      local result = dibs.ProtectedActions.Execute("ledger.adjust", nil, {
        playerName = "Firebut-DunModr", amount = 1, reason = reason, source = "MANUAL_ADMIN", seasonId = seasonId,
      })
      assert_false(result.ok)
      assert_equal("REASON_REQUIRED", result.reasonCode)
    end
    local nilReason = dibs.ProtectedActions.Execute("ledger.adjust", nil, {
      playerName = "Firebut-DunModr", amount = 1, source = "MANUAL_ADMIN", seasonId = seasonId,
    })
    assert_false(nilReason.ok)
    assert_equal("REASON_REQUIRED", nilReason.reasonCode)
    assert_equal(beforeCount, #dibs.Ledger.GetAllTransactions())
  end)

  it("makes no ledger call for invalid reasons, Cancel, or closing the dialog", function()
    local dibs = loadOfficer("Tester-Realm", true)
    local seasonId = dibs.GetCurrentSeasonId()
    openAdminPage(dibs)
    local originalExecute = dibs.ProtectedActions.Execute
    local calls = 0
    dibs.ProtectedActions.Execute = function(...)
      calls = calls + 1
      return originalExecute(...)
    end

    clickLatestButton("ADD")
    setConfirmationReason("OTHER", " \t ")
    assert_equal("OTHER", findLatestWidget(function(widget)
      return widget.kind == "Dropdown" and widget.label == "Reason"
    end).value)
    clickLatestButton("Add Dib")
    assert_equal(0, calls)
    clickLatestButton("Cancel")
    assert_equal(0, calls)

    clickLatestButton("ADD")
    assert_equal("MANUAL_ADMIN_ADDITION", findLatestWidget(function(widget)
      return widget.kind == "Dropdown" and widget.label == "Reason"
    end).value)
    local dialog = findLatestWidget(function(widget)
      return widget.kind == "Frame" and widget.title == "Dibs | Confirm Dibs change"
    end)
    assert_not_nil(dialog)
    dialog:Hide()
    assert_equal(0, calls)
    assert_equal(0, dibs.Ledger.GetBalance("Firebut-DunModr", seasonId))
  end)

  it("rejects unauthorized manual changes but keeps non-manual adjustment callers compatible", function()
    local member = loadOfficer("Member-Realm", false)
    local seasonId = member.GetCurrentSeasonId()
    local denied = member.ProtectedActions.Execute("ledger.adjust", nil, {
      playerName = "Firebut-DunModr", amount = 1, reason = "Not allowed", source = "MANUAL_ADMIN", seasonId = seasonId,
    })
    assert_false(denied.ok)
    assert_equal(0, member.Ledger.GetBalance("Firebut-DunModr", seasonId))

    local officer = loadOfficer("Officer-Realm", false)
    local officerSeason = officer.GetCurrentSeasonId()
    local automatic = officer.ProtectedActions.Execute("ledger.adjust", nil, {
      playerName = "Firebut-DunModr", amount = 1, source = "rank_reconciliation", seasonId = officerSeason,
    })
    assert_true(automatic.ok, tostring(automatic.reasonCode))
    assert_equal(1, officer.Ledger.GetBalance("Firebut-DunModr", officerSeason))
  end)
end)
