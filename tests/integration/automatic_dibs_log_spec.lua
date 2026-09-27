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

    local automatic = dibs.Ledger.RegisterSeasonAllocation("Alice-Realm", seasonId, 1, "Promotion to Member", {
      action = "rank.reconcile", actor = "Tester-Realm", source = "automatic_rank_assignment",
      rankIndex = 3, rankName = "Member",
    })
    assert_not_nil(automatic)
    local manual = dibs.Ledger.RegisterSeasonAllocation("Alice-Realm", seasonId, 1, "Officer correction", {
      action = "rank.reconcile", actor = "Tester-Realm", source = "rank_reconciliation",
    })
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

describe("Automatic Dibs table presentation", function()
  local function loadReconciliationRoster(extraPlayers, locale)
    local guildMembers = { "Tester-Realm", "Alice-Realm", "Bob-Realm", "Cara-Realm", "Dane-Realm" }
    local guildRankIndices = { [1] = 0, [2] = 1, [3] = 3, [4] = 2, [5] = 3 }
    for playerIndex = 1, extraPlayers or 0 do
      guildMembers[#guildMembers + 1] = string.format("Extra%02d-Realm", playerIndex)
      guildRankIndices[#guildMembers] = 3
    end
    local _, dibs = loader.load({ withAce3 = true, wow = {
      locale = locale,
      playerName = "Tester-Realm", guildLeader = true,
      guildMembers = guildMembers,
      guildRankIndices = guildRankIndices,
    } })
    assert_true(dibs.Governance.AdoptInitial(nil, { reason = "Automatic Dibs presentation fixture" }))
    local baseline = assert(dibs.LegacyBaseline.FinalizeBaseline(nil))
    local coordinator = assert(dibs.Identity.CreateSnapshot("Tester-Realm"))
    assert_true(dibs.Governance.Change(nil, { future = { authority = {
      schema = 1, state = "ACTIVE", coordinator = coordinator, ledgerEpoch = 1,
      transition = { kind = "INITIAL", baselineHash = baseline.legacyBaselineHash },
    } } }))
    assert_true(dibs.Governance.EnableV2(nil, { "Tester-Realm" }))
    local seasonId = dibs.GetCurrentSeasonId()
    local currentAllocation = dibs.Ledger.GetPlayerState("Tester-Realm", seasonId).allocation
    for _, rule in ipairs({
      { index = 0, name = "Guild Master", allocation = currentAllocation },
      { index = 1, name = "Officer", allocation = 1 },
      { index = 2, name = "Veteran", allocation = 2 },
      { index = 3, name = "Member", allocation = 1 },
    }) do
      local result = dibs.ProtectedActions.Execute("rank.set", nil, {
        seasonId = seasonId, rankIndex = rule.index, rankName = rule.name, allocation = rule.allocation,
      })
      assert_true(result.ok, tostring(result.diagnostic))
    end
    for _, assignment in ipairs({
      { player = "Bob-Realm", amount = 1 },
      { player = "Cara-Realm", amount = 3 },
    }) do
      local tx, reasonCode = dibs.Ledger.RegisterSeasonAllocation(assignment.player, seasonId,
        assignment.amount, "Presentation fixture", {
          action = "rank.reconcile", actor = "Tester-Realm", source = "ui_fixture",
        })
      assert_not_nil(tx, tostring(reasonCode))
    end
    return dibs, seasonId
  end

  local function captureAutomaticTable(dibs, contentWidth)
    local capture, captureCount
    captureCount = 0
    local originalAddTable = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, options)
      captureCount = captureCount + 1
      capture = { columns = columns, rows = rows, rowActions = rowActions, options = options }
      return originalAddTable(shell, parent, columns, rows, height, rowActions, options)
    end
    local frame = dibs.OfficerUI.CreateWindow("automaticDibs")
    frame:ActivateRoute("automaticDibs")
    if contentWidth then
      local page = frame.automaticDibsTablePage
      page.root.frame.GetWidth = function() return contentWidth end
      page.boundsFrame.GetWidth = function() return contentWidth end
      frame.ReflowAutomaticDibsTable(true)
    end
    return frame, function() return capture end, function() return captureCount end
  end

  local function findWidget(predicate)
    for index = #(_G.__dibsAceWidgets or {}), 1, -1 do
      local widget = _G.__dibsAceWidgets[index]
      if predicate(widget) then return widget end
    end
  end

  local function findRow(capture, playerName)
    for _, row in ipairs(capture.rows or {}) do
      if row.reconciliationRow and row.reconciliationRow.plainPlayerName == playerName then return row end
    end
  end

  local function clickButton(text)
    local widget = findWidget(function(candidate)
      return candidate.kind == "Button" and candidate.text == text
    end)
    assert_not_nil(widget, "Button not found: " .. text)
    widget.callbacks.OnClick(widget, "OnClick")
    return widget
  end

  local function selectStatus(value)
    local dropdown = findWidget(function(widget)
      return widget.kind == "Dropdown" and widget.label == "Status"
    end)
    assert_not_nil(dropdown, "Status dropdown not found")
    dropdown.callbacks.OnValueChanged(dropdown, "OnValueChanged", value)
  end

  local function selectPageSize(value)
    local dropdown = findWidget(function(widget)
      return widget.kind == "Dropdown" and widget._dibsRowsPerPageSelector
    end)
    assert_not_nil(dropdown, "Players per page dropdown not found")
    dropdown.callbacks.OnValueChanged(dropdown, "OnValueChanged", tostring(value))
  end

  it("limits rendered rows to the selected page size", function()
    local dibs = loadReconciliationRoster(22)
    local frame, getCapture = captureAutomaticTable(dibs)
    local page = frame.automaticDibsTablePage
    local routeDispatchCount = frame.routeDispatchCount
    local canonicalCommitCount = dibs.Ledger.GetCanonicalState().commitCount
    assert_equal(page.root, page.scroll.parent)
    assert_equal(page.root, page.columnHeader.parent)
    assert_equal(page.root, page.footer.parent)
    assert_true(page.scroll ~= page.footer)
    assert_equal(page.scroll, page.scroll.children[1].parent)
    assert_equal(frame.automaticDibsPagination.navigationGroup, page.footer.children[1])
    assert_equal(frame.automaticDibsPagination.pageSizeGroup, page.footer.children[2])
    assert_equal(frame.automaticDibsPagination.navigationGroup, frame.automaticDibsPreviousPage.parent)
    assert_equal(frame.automaticDibsPagination.navigationGroup, frame.automaticDibsPageIndicator.parent)
    assert_equal(frame.automaticDibsPagination.navigationGroup, frame.automaticDibsNextPage.parent)
    assert_equal(frame.automaticDibsPagination.pageSizeGroup, frame.automaticDibsPageSizeDropdown.parent)
    assert_equal(frame.automaticDibsPreviousPage, frame.automaticDibsPagination.navigationGroup.children[1])
    assert_equal(frame.automaticDibsPageIndicator, frame.automaticDibsPagination.navigationGroup.children[2])
    assert_equal(frame.automaticDibsNextPage, frame.automaticDibsPagination.navigationGroup.children[3])
    assert_equal(frame.automaticDibsPagination.pageSizeGroup.children[2], frame.automaticDibsPageSizeDropdown)
    assert_true(frame.automaticDibsPagination.navigationWidth < 500)
    local choices = frame.automaticDibsPageSizeDropdown.list
    for _, size in ipairs({ "5", "10", "15", "20" }) do assert_equal(size, choices[size]) end

    local pageHeight = 700
    page.boundsFrame.GetHeight = function() return pageHeight end
    page.boundsFrame.GetWidth = function() return 720 end
    page.header.frame.GetHeight = function() return 190 end
    page.columnHeader.frame.GetHeight = function() return 24 end
    page.footer.frame.GetHeight = function() return 32 end
    local metrics = dibs.AceGUI.GetLayoutMetrics()
    page.UpdateViewportHeight()
    assert_equal(pageHeight - 190 - 24 - 32 - metrics.tableVerticalGap, page.scroll.height)
    pageHeight = 600
    page.UpdateViewportHeight()
    assert_equal(pageHeight - 190 - 24 - 32 - metrics.tableVerticalGap, page.scroll.height)

    assert_equal(10, #getCapture().rows)
    assert_equal("Page 1 / 3", findWidget(function(widget)
      return widget.kind == "Label" and tostring(widget.text):find("Page 1 /", 1, true) == 1
    end).text)

    selectPageSize(5)
    assert_equal(5, #getCapture().rows)
    local firstPagePlayer = getCapture().rows[1].reconciliationRow.plainPlayerName
    clickButton("Next")
    assert_equal(2, frame.automaticDibsPage)
    assert_equal(5, #getCapture().rows)
    assert_true(getCapture().rows[1].reconciliationRow.plainPlayerName ~= firstPagePlayer)
    clickButton("Previous")
    assert_equal(1, frame.automaticDibsPage)

    selectPageSize(15)
    assert_equal(15, #getCapture().rows)
    selectPageSize(20)
    assert_equal(20, #getCapture().rows)
    clickButton("Next")
    assert_true(frame.automaticDibsNextPage.disabled)
    assert_equal(false, frame.automaticDibsPreviousPage.disabled)
    assert_equal(4, #getCapture().rows)
    assert_equal("Page 2 / 2", findWidget(function(widget)
      return widget.kind == "Label" and tostring(widget.text):find("Page 2 /", 1, true) == 1
    end).text)
    local pageTwoFirst = getCapture().rows[1].reconciliationRow.plainPlayerName
    selectPageSize(5)
    assert_equal(5, frame.automaticDibsPage)
    assert_equal(4, #getCapture().rows)
    assert_equal(pageTwoFirst, getCapture().rows[1].reconciliationRow.plainPlayerName)
    assert_true(frame.automaticDibsNextPage.disabled)
    selectPageSize(10)
    assert_equal(3, frame.automaticDibsPage)
    assert_equal(4, #getCapture().rows)
    assert_equal(pageTwoFirst, getCapture().rows[1].reconciliationRow.plainPlayerName)
    assert_equal(routeDispatchCount, frame.routeDispatchCount)
    assert_equal(canonicalCommitCount, dibs.Ledger.GetCanonicalState().commitCount)

    local shell = frame.dibsAceGUIShell
    local scrollCount = #shell._dibsResponsiveScrolls
    local oldScroll = page.scroll
    frame:Refresh()
    assert_equal(scrollCount, #shell._dibsResponsiveScrolls)
    assert_true(frame.automaticDibsTablePage.scroll ~= oldScroll)
    assert_not_nil(frame)
  end)

  it("renders aligned headers and associates a positive action with its player without mutating the ledger", function()
    local dibs = loadReconciliationRoster()
    local before = dibs.Ledger.GetCanonicalState().commitCount
    local frame, getCapture = captureAutomaticTable(dibs, 1400)
    local capture = getCapture()
    local expectedHeaders = { "Player Name", "Guild Rank", "Expected", "Assigned", "Difference", "Status", "Action" }
    assert_equal(#expectedHeaders, #capture.columns)
    for index, header in ipairs(expectedHeaders) do assert_equal(header, capture.columns[index].title) end
    local actionColumn = capture.columns[7]
    local reconcileLabel = dibs.L.UI_ACTION_RECONCILE
    local requiredActionWidth = dibs.AceGUI.GetContentSizedActionWidth({ reconcileLabel },
      dibs.AceGUI.GetLayoutMetrics().actionMinWidth)
    assert_true(actionColumn.fixed)
    assert_nil(actionColumn.weight)
    assert_equal(requiredActionWidth, actionColumn.width)
    assert_equal(reconcileLabel, actionColumn.actionLabels[1])
    assert_true(actionColumn.width >= dibs.AceGUI.MeasureTextWidth(reconcileLabel)
      + dibs.AceGUI.GetLayoutMetrics().buttonHorizontalPadding
      + dibs.AceGUI.GetLayoutMetrics().buttonSizingSafetyMargin)
    local tableHost = frame.automaticDibsTablePage.scroll.children[1]
    local actionButtonCount = 0
    for _, rowGroup in ipairs(tableHost.children or {}) do
      for _, child in ipairs(rowGroup.children or {}) do
        if child.kind == "Button" and child.text == reconcileLabel then
          assert_equal(actionColumn.width, child.width)
          assert_true(child.frame:GetWidth() >= child._dibsLabelWidth
            + child._dibsHorizontalPadding + dibs.AceGUI.GetLayoutMetrics().buttonSizingSafetyMargin)
          assert_equal(actionColumn.width, child._dibsColumnWidth)
          actionButtonCount = actionButtonCount + 1
        end
      end
    end
    assert_equal(2, actionButtonCount)
    local allocated = dibs.AceGUI.AllocateFluidColumnWidths(capture.columns, 1100, {
      horizontalPadding = capture.options.horizontalPadding,
      scrollbarReserve = capture.options.scrollbarReserve,
      columnGap = capture.options.columnGap,
    })
    assert_equal(actionColumn.width, allocated[7])
    assert_true(allocated[1] > capture.columns[1].minWidth)
    assert_true(allocated[2] > capture.columns[2].minWidth)
    assert_true(allocated[6] > capture.columns[6].minWidth)
    assert_equal(2, #capture.rows)
    local alice = assert(findRow(capture, "Alice-Realm"))
    assert_equal("Officer", alice[2])
    assert_equal("1", alice[3])
    assert_equal("0", alice[4])
    assert_equal("+1", alice[5])
    assert_equal("Needs action", alice[6])
    assert_equal(reconcileLabel, alice[7])
    assert_true(getCapture().options.noScrolling)
    assert_equal(32, getCapture().options.rowHeight)
    local action = assert(capture.rowActions(alice))
    assert_equal(reconcileLabel, action.text)
    assert_not_nil(findWidget(function(widget)
      return widget.kind == "Button" and widget.text == reconcileLabel
    end))
    local reconcileButton = findWidget(function(widget)
      return widget.kind == "Button" and widget.text == reconcileLabel
    end)
    assert_equal(frame.automaticDibsTablePage.scroll, reconcileButton.parent.parent.parent)
    assert_nil(findWidget(function(widget)
      return widget.label == "Reason" or widget.label == "Required reason"
    end))

    local invokedPlayer
    local invokedReason
    local reconcile = dibs.OfficerUI.ReconcileRankAllocation
    dibs.OfficerUI.ReconcileRankAllocation = function(row, reason)
      invokedPlayer = row.plainPlayerName
      invokedReason = reason
      return { ok = true, outcome = "COMMITTED" }
    end
    action.callback(alice)
    assert_equal(before, dibs.Ledger.GetCanonicalState().commitCount)
    clickButton("Cancel")
    assert_equal(before, dibs.Ledger.GetCanonicalState().commitCount)
    action.callback(alice)
    local reason = findWidget(function(widget) return widget.kind == "Dropdown" and widget.label == "Reason" end)
    assert_not_nil(reason)
    assert_equal("RANK_RECONCILIATION", reason.value)
    assert_equal("Rank allocation reconciliation", reason.list.RANK_RECONCILIATION)
    assert_equal("Rank allocation reconciliation", reason.text)
    local details = findWidget(function(widget) return widget.label == "Details (optional)" end)
    assert_not_nil(details)
    details.callbacks.OnTextChanged(details, "OnTextChanged", "Reviewed rank allocation")
    local confirm = clickButton("Reconcile")
    assert_equal("Dibs | Confirm reconciliation", confirm.parent.parent.parent.title)
    assert_equal("Flow", confirm.parent.layout)
    assert_equal("List", confirm.parent.parent.layout)
    dibs.OfficerUI.ReconcileRankAllocation = reconcile
    assert_equal("Alice-Realm", invokedPlayer)
    assert_equal("Rank allocation reconciliation: Reviewed rank allocation", invokedReason)
    assert_equal(before, dibs.Ledger.GetCanonicalState().commitCount)
    assert_equal("automaticDibs", frame.activeTab)
  end)

  it("shows Ready and Keep granted rows without destructive actions", function()
    local dibs = loadReconciliationRoster()
    local frame, getCapture = captureAutomaticTable(dibs, 1400)
    selectStatus("ready")
    local readyCapture = getCapture()
    assert_equal(2, #readyCapture.rows)
    local bob = assert(findRow(readyCapture, "Bob-Realm"))
    assert_equal("0", bob[5])
    assert_equal("Ready", bob[6])
    assert_equal("-", bob[7])
    assert_nil(readyCapture.rowActions(bob))

    selectStatus("surplus")
    local surplusCapture = getCapture()
    assert_equal(1, #surplusCapture.rows)
    local cara = assert(findRow(surplusCapture, "Cara-Realm"))
    assert_equal("-1", cara[5])
    assert_equal("Keep granted", cara[6])
    assert_equal("-", cara[7])
    assert_nil(surplusCapture.rowActions(cara))
    assert_equal("automaticDibs", frame.activeTab)
  end)

  it("sorts Automatic Dibs rows from sortable headers in both directions", function()
    local dibs = loadReconciliationRoster()
    local frame, getCapture = captureAutomaticTable(dibs, 1400)
    selectStatus("all")
    local ledgerCommitCount = dibs.Ledger.GetCanonicalState().commitCount
    local capture = getCapture()
    assert_equal("rank", capture.columns[2].sortKey)
    assert_equal("expected", capture.columns[3].sortKey)
    assert_equal("assigned", capture.columns[4].sortKey)
    assert_equal("difference", capture.columns[5].sortKey)
    assert_equal("status", capture.columns[6].sortKey)
    assert_false(capture.columns[7].sortable ~= false)

    frame.automaticDibsPage = 2
    local rankHeader = findWidget(function(widget)
      return widget.kind == "Button" and widget.text == "Guild Rank"
    end)
    assert_not_nil(rankHeader)
    rankHeader.callbacks.OnClick(rankHeader, "OnClick")
    local ascending = getCapture()
    assert_equal(1, frame.automaticDibsPage)
    assert_equal("Guild Rank ^", ascending.columns[2].title)
    for index = 2, #ascending.rows do
      assert_true(ascending.rows[index - 1].reconciliationRow.rankIndex
        <= ascending.rows[index].reconciliationRow.rankIndex)
    end

    local ascendingRankHeader = findWidget(function(widget)
      return widget.kind == "Button" and widget.text == "Guild Rank ^"
    end)
    assert_not_nil(ascendingRankHeader)
    ascendingRankHeader.callbacks.OnClick(ascendingRankHeader, "OnClick")
    local descending = getCapture()
    assert_equal("Guild Rank v", descending.columns[2].title)
    for index = 2, #descending.rows do
      assert_true(descending.rows[index - 1].reconciliationRow.rankIndex
        >= descending.rows[index].reconciliationRow.rankIndex)
    end
    assert_equal(ledgerCommitCount, dibs.Ledger.GetCanonicalState().commitCount)
  end)

  it("keeps localized RECONCILE buttons content-sized across supported widths", function()
    for _, locale in ipairs({ "enUS", "frFR" }) do
      local dibs = loadReconciliationRoster(nil, locale)
      local frame, getCapture = captureAutomaticTable(dibs, 1500)
      local page = frame.automaticDibsTablePage
      local actionLabel = dibs.L.UI_ACTION_RECONCILE
      local fixedWidth
      for _, testWidth in ipairs({ 1500, 900, 700, 520 }) do
        page.boundsFrame.GetWidth = function() return testWidth end
        page.root.frame.GetWidth = function() return testWidth end
        frame.ReflowAutomaticDibsTable(true)
        local capture = getCapture()
        local actionIndex, actionColumn
        for index, column in ipairs(capture.columns) do
          if column.action then actionIndex, actionColumn = index, column break end
        end
        assert_not_nil(actionColumn)
        assert_true(actionColumn.fixed)
        assert_nil(actionColumn.weight)
        assert_equal(actionLabel, actionColumn.actionLabels[1])
        assert_equal(dibs.AceGUI.GetContentSizedActionWidth({ actionLabel },
          dibs.AceGUI.GetLayoutMetrics().actionMinWidth), actionColumn.width)
        fixedWidth = fixedWidth or actionColumn.width
        assert_equal(fixedWidth, actionColumn.width)

        local tableHost = page.scroll.children[1]
        local buttons = 0
        for _, rowGroup in ipairs(tableHost.children or {}) do
          for _, button in ipairs(rowGroup.children or {}) do
            if button.kind == "Button" and button.text == actionLabel then
              local fontString = button.frame:GetFontString()
              local requiredWidth = fontString:GetStringWidth()
                + dibs.AceGUI.GetLayoutMetrics().buttonHorizontalPadding
                + dibs.AceGUI.GetLayoutMetrics().buttonSizingSafetyMargin
              assert_true(button.frame:GetWidth() >= requiredWidth)
              assert_true(button.frame:GetWidth() >= button._dibsRequiredWidth)
              assert_equal(actionColumn.width, button._dibsColumnWidth)
              assert_equal(actionIndex, button._dibsColumnIndex)
              buttons = buttons + 1
            end
          end
        end
        assert_true(buttons > 0)
      end
    end
  end)

  it("shows Reconcile All totals and confirms independent operations over the full roster", function()
    local dibs = loadReconciliationRoster()
    local frame, getCapture = captureAutomaticTable(dibs)
    assert_not_nil(findWidget(function(widget)
      return widget.kind == "Label" and tostring(widget.text):find("2 players need reconciliation", 1, true) ~= nil
    end))
    assert_not_nil(findWidget(function(widget)
      return widget.kind == "Label" and tostring(widget.text):find("Missing allocation: +2 Dibs", 1, true) ~= nil
    end))
    frame.automaticDibsFilter = "surplus"
    frame:Refresh()
    clickButton("Reconcile All — 2 players / +2 Dibs")
    assert_not_nil(findWidget(function(widget)
      return widget.kind == "Label" and tostring(widget.text) == "2"
    end))
    assert_not_nil(findWidget(function(widget)
      return widget.kind == "Label" and tostring(widget.text) == "+2 Dibs"
    end))
    assert_not_nil(findWidget(function(widget)
      return widget.kind == "Label" and tostring(widget.text):find("partial success is possible", 1, true) ~= nil
    end))

    local submitted
    local reconcileAll = dibs.OfficerUI.ReconcileAllAllocations
    dibs.OfficerUI.ReconcileAllAllocations = function(seasonId, requiredReason, rows)
      submitted = { seasonId = seasonId, reason = requiredReason, rows = rows }
      return { succeeded = 2, stale = 0, skipped = 2, failed = 0, pending = 0, results = {} }
    end
    local reason = findWidget(function(widget) return widget.kind == "Dropdown" and widget.label == "Reason" end)
    assert_equal("RANK_RECONCILIATION", reason.value)
    local details = findWidget(function(widget) return widget.label == "Details (optional)" end)
    details.callbacks.OnTextChanged(details, "OnTextChanged", "Review all rank allocations")
    clickButton("Reconcile All")
    dibs.OfficerUI.ReconcileAllAllocations = reconcileAll
    assert_equal(dibs.GetCurrentSeasonId(), submitted.seasonId)
    assert_equal("Rank allocation reconciliation: Review all rank allocations", submitted.reason)
    assert_equal(5, #submitted.rows)
    assert_equal("surplus", frame.automaticDibsFilter)
    assert_equal("automaticDibs", frame.activeTab)
    assert_not_nil(getCapture())
  end)

  it("keeps the measured viewport and pagination inside the panel for empty, single, and many rows", function()
    local dibs = loadReconciliationRoster(29)
    local frame, getCapture = captureAutomaticTable(dibs)
    local page = frame.automaticDibsTablePage
    local panelHeight, panelWidth = 700, 900
    page.boundsFrame.GetHeight = function() return panelHeight end
    page.boundsFrame.GetWidth = function() return panelWidth end
    page.header.frame.GetHeight = function() return panelWidth < 500 and 220 or 190 end
    page.columnHeader.frame.GetHeight = function() return 24 end
    page.footer.frame.GetHeight = function() return panelWidth < 500 and 64 or 32 end
    local metrics = dibs.AceGUI.GetLayoutMetrics()

    local function assertGeometry()
      page.UpdateViewportHeight()
      local headerHeight = panelWidth < 500 and 220 or 190
      local columnHeight = 24
      local footerHeight = panelWidth < 500 and 64 or 32
      local gap = metrics.tableVerticalGap
      local rootTopLeft = framePoint(page.root.frame, "TOPLEFT")
      local rootTopRight = framePoint(page.root.frame, "TOPRIGHT")
      local headerTop = framePoint(page.header.frame, "TOPLEFT")
      local columnTop = framePoint(page.columnHeader.frame, "TOPLEFT")
      local viewportTop = framePoint(page.scroll.frame, "TOPLEFT")
      local viewportBottom = framePoint(page.scroll.frame, "BOTTOMRIGHT")
      local footerBottomLeft = framePoint(page.footer.frame, "BOTTOMLEFT")
      local footerBottomRight = framePoint(page.footer.frame, "BOTTOMRIGHT")
      assert_equal(page.boundsFrame, rootTopLeft[2])
      assert_equal(page.boundsFrame, rootTopRight[2])
      assert_equal(page.contentFrame, headerTop[2])
      assert_equal(page.header.frame, columnTop[2])
      assert_equal(page.columnHeader.frame, viewportTop[2])
      assert_equal(page.header, page.root.children[1])
      assert_equal(page.columnHeader, page.root.children[2])
      assert_equal(page.scroll, page.root.children[3])
      assert_equal(page.footer, page.root.children[4])
      assert_equal(page.root, page.scroll.parent)
      assert_equal(page.root, page.footer.parent)
      local footerInline = panelWidth >= page.pagination.navigationWidth
        + page.pagination.pageSizeWidth + page.pagination.footerGap
      assert_equal(footerInline and "INLINE" or "STACKED", page.pagination.layoutMode)
      assert_equal(page.footer, page.pagination.navigationGroup.parent)
      assert_equal(page.footer, page.pagination.pageSizeGroup.parent)
      local navigation = page.pagination.navigationGroup
      local previousPoint = framePoint(page.pagination.previous.frame, "LEFT")
      local pagePoint = framePoint(page.pagination.page.frame, "LEFT")
      local nextPoint = framePoint(page.pagination.next.frame, "LEFT")
      local pageSizeLabelPoint = framePoint(page.pagination.pageSizeLabel.frame, "LEFT")
      local pageSizePoint = framePoint(page.pagination.pageSize.frame, "LEFT")
      assert_equal(navigation.frame, previousPoint[2])
      assert_equal(page.pagination.previous.frame, pagePoint[2])
      assert_equal("RIGHT", pagePoint[3])
      assert_equal(page.pagination.page.frame, nextPoint[2])
      assert_equal("RIGHT", nextPoint[3])
      assert_equal(page.pagination.pageSizeGroup.frame, pageSizeLabelPoint[2])
      assert_equal(page.pagination.pageSizeLabel.frame, pageSizePoint[2])
      assert_equal("RIGHT", pageSizePoint[3])
      assert_true(navigation.frame:GetWidth() >= page.pagination.previous.frame:GetWidth()
        + page.pagination.page.frame:GetWidth() + page.pagination.next.frame:GetWidth())
      assert_true(page.pagination.pageSizeGroup.frame:GetWidth()
        >= page.pagination.pageSizeLabel.frame:GetWidth() + page.pagination.pageSize.frame:GetWidth())
      if footerInline then
        local pageSizePoint = framePoint(page.pagination.pageSizeGroup.frame, "LEFT")
        assert_equal(page.pagination.navigationGroup.frame, pageSizePoint[2])
        assert_equal("RIGHT", pageSizePoint[3])
      else
        local pageSizePoint = framePoint(page.pagination.pageSizeGroup.frame, "TOPLEFT")
        assert_equal(page.pagination.navigationGroup.frame, pageSizePoint[2])
        assert_equal("BOTTOMLEFT", pageSizePoint[3])
      end
      local registeredScrolls = 0
      for _, scroll in ipairs(frame.dibsAceGUIShell._dibsResponsiveScrolls) do
        if scroll == page.scroll then registeredScrolls = registeredScrolls + 1 end
      end
      assert_equal(1, registeredScrolls)
      assert_true(page.scroll.height >= metrics.tableViewportMinimum)
      assert_equal(panelHeight, page.root.height)
      assert_equal(page.boundsFrame, footerBottomLeft[2])
      assert_equal(page.boundsFrame, footerBottomRight[2])
      assert_equal("BOTTOMLEFT", footerBottomLeft[1])
      assert_equal("BOTTOMRIGHT", footerBottomRight[1])
      assert_equal(2, #page.footer.frame._points)
      assert_equal(page.footer.frame, viewportBottom[2])
      assert_equal("TOPRIGHT", viewportBottom[3])

      local viewportStart = headerHeight + gap + columnHeight
      local viewportEnd = viewportStart + page.scroll.height
      local footerStart = panelHeight - footerHeight
      assert_true(viewportStart > headerHeight)
      assert_equal(panelHeight - headerHeight - columnHeight - footerHeight - gap, page.scroll.height)
      assert_equal(footerStart, viewportEnd)
      assert_true(footerStart + footerHeight <= panelHeight)
      assert_true(page.scroll ~= page.footer)
      assert_true(page.scroll.parent ~= frame.dibsAceGUIShell.window)
      assert_true(frame.dibsAceGUIShell.window ~= page.scroll)
      local closeButton = frame.dibsAceGUIShell.window.closebutton
      assert_not_nil(closeButton)
      assert_equal(frame.dibsAceGUIShell.frame, closeButton.parent)
      assert_equal("BOTTOMRIGHT", framePoint(closeButton, "BOTTOMRIGHT")[1])
      assert_true(closeButton ~= page.scroll.frame)
      assert_true(closeButton.parent ~= page.scroll.frame)
      local tableHost = page.scroll.children[1]
      local renderedRows = 0
      for _, child in ipairs(tableHost.children or {}) do
        if child.kind == "SimpleGroup" then renderedRows = renderedRows + 1 end
      end
      assert_equal(#getCapture().rows, renderedRows)
    end

    assertGeometry()
    local stableViewportHeight = page.scroll.height
    local stableFooterPoint = framePoint(page.footer.frame, "BOTTOMLEFT")
    local search = frame.automaticDibsSearch
    search.callbacks.OnTextChanged(search, "OnTextChanged", "no-such-player")
    assert_equal(0, #getCapture().rows)
    assert_equal("Page 1 / 1", frame.automaticDibsPageIndicator.text)
    assertGeometry()
    assert_equal(stableViewportHeight, page.scroll.height)

    search.callbacks.OnTextChanged(search, "OnTextChanged", "Alice-Realm")
    assert_equal(1, #getCapture().rows)
    assert_equal("Page 1 / 1", frame.automaticDibsPageIndicator.text)
    assertGeometry()
    assert_equal(stableViewportHeight, page.scroll.height)

    search.callbacks.OnTextChanged(search, "OnTextChanged", "")
    assert_equal(31, #frame.automaticDibsCachedPresentation.rows)
    for _, size in ipairs({ 5, 10, 15, 20 }) do
      selectPageSize(size)
      assert_equal(size, #getCapture().rows)
      assert_equal(string.format("Page 1 / %d", math.ceil(31 / size)),
        frame.automaticDibsPageIndicator.text)
      assertGeometry()
      assert_equal(stableViewportHeight, page.scroll.height)
      local currentFooterPoint = framePoint(page.footer.frame, "BOTTOMLEFT")
      assert_equal(stableFooterPoint[2], currentFooterPoint[2])
      assert_equal(stableFooterPoint[3], currentFooterPoint[3])
    end

    local shellFrame = frame.dibsAceGUIShell.frame
    local resizeWidths = { 1300, 1000, 650, 1300 }
    for _, width in ipairs(resizeWidths) do
      panelWidth = width - 240
      shellFrame._scripts.OnSizeChanged(shellFrame, width, 700)
      dibs.AceGUI.FlushRefreshes()
      assertGeometry()
    end

    local function assertSameFooterPoint(point, current)
      assert_equal(point[1], current[1])
      assert_equal(point[2], current[2])
      assert_equal(point[3], current[3])
      assert_equal(point[4], current[4])
      assert_equal(point[5], current[5])
    end
    panelWidth, panelHeight = 900, 700
    page.UpdateViewportHeight()
    local stableFooterAnchor = framePoint(page.footer.frame, "BOTTOMLEFT")
    for _ = 1, 100 do
      page.UpdateViewportHeight()
      assertGeometry()
      assertSameFooterPoint(stableFooterAnchor, framePoint(page.footer.frame, "BOTTOMLEFT"))
      assert_equal(2, #page.footer.frame._points)
    end
    local alternatingWidths = { 1300, 1000, 1300, 1000, 650, 1000 }
    for index = 1, 100 do
      local width = alternatingWidths[(index - 1) % #alternatingWidths + 1]
      panelWidth = width - 240
      shellFrame._scripts.OnSizeChanged(shellFrame, width, 700)
      dibs.AceGUI.FlushRefreshes()
      assertGeometry()
      assertSameFooterPoint(stableFooterAnchor, framePoint(page.footer.frame, "BOTTOMLEFT"))
      assert_equal(2, #page.footer.frame._points)
    end

    panelWidth = 900
    panelHeight = 190 + 24 + 32 + metrics.tableVerticalGap + metrics.tableViewportMinimum - 10
    local shell = frame.dibsAceGUIShell
    local originalWindowGetHeight = shell.frame.GetHeight
    local originalWindowSetHeight = shell.window.SetHeight
    local windowHeight = 760
    shell.frame.GetHeight = function() return windowHeight end
    shell.window.SetHeight = function(_, nextHeight)
      panelHeight = panelHeight + nextHeight - windowHeight
      windowHeight = nextHeight
    end
    page.UpdateViewportHeight()
    assert_equal(760 + 10, windowHeight)
    assert_equal(190 + 24 + 32 + metrics.tableVerticalGap + metrics.tableViewportMinimum, panelHeight)
    assertGeometry()
    shell.frame.GetHeight = originalWindowGetHeight
    shell.window.SetHeight = originalWindowSetHeight
  end)

  it("filters statuses and searches player name or rank", function()
    local dibs = loadReconciliationRoster()
    local frame, getCapture, getTableRenderCount = captureAutomaticTable(dibs)
    assert_equal(2, #getCapture().rows)
    selectStatus("all")
    assert_equal(5, #getCapture().rows)
    local search = findWidget(function(widget)
      return widget.kind == "EditBox" and widget.label == "Search player"
    end)
    assert_not_nil(search)
    assert_true(search.buttonDisabled)
    local searchFrame = search.frame
    local pageRefresh = frame.Refresh
    frame.Refresh = function() error("Search must not rebuild the page") end
    local typed = ""
    for character in string.gmatch("mast", ".") do
      typed = typed .. character
      search:SetText(typed)
      search.callbacks.OnTextChanged(search, "OnTextChanged", typed)
      assert_equal(search, findWidget(function(widget)
        return widget.kind == "EditBox" and widget.label == "Search player"
      end))
      assert_equal(searchFrame, search.frame)
    end
    assert_equal("mast", frame.automaticDibsQuery)
    assert_equal("mast", search:GetText())
    assert_equal(1, #getCapture().rows)
    assert_equal("Tester-Realm", getCapture().rows[1].reconciliationRow.plainPlayerName)

    search:SetText("Alice")
    search.callbacks.OnTextChanged(search, "OnTextChanged", "Alice")
    assert_equal(1, #getCapture().rows)
    assert_equal("Alice-Realm", getCapture().rows[1].reconciliationRow.plainPlayerName)
    search:SetText("Officer")
    search.callbacks.OnTextChanged(search, "OnTextChanged", "Officer")
    assert_equal(1, #getCapture().rows)
    assert_equal("Alice-Realm", getCapture().rows[1].reconciliationRow.plainPlayerName)
    search:SetText("Offic")
    search.callbacks.OnTextChanged(search, "OnTextChanged", "Offic")
    assert_equal(1, #getCapture().rows)
    search:SetText("")
    search.callbacks.OnTextChanged(search, "OnTextChanged", "")
    assert_equal(5, #getCapture().rows)
    clickButton("Clear")
    assert_equal(search, findWidget(function(widget)
      return widget.kind == "EditBox" and widget.label == "Search player"
    end))
    assert_equal("", frame.automaticDibsQuery)
    local buildDetails = dibs.OfficerUI.BuildAutomaticAllocationDetails
    local buildPresentation = dibs.OfficerUI.BuildAutomaticDibsPresentation
    local resizeCalculations = 0
    dibs.OfficerUI.BuildAutomaticAllocationDetails = function(...)
      resizeCalculations = resizeCalculations + 1
      return buildDetails(...)
    end
    dibs.OfficerUI.BuildAutomaticDibsPresentation = function(...)
      resizeCalculations = resizeCalculations + 1
      return buildPresentation(...)
    end

    frame.dibsAceGUIShell.frame._scripts.OnSizeChanged(frame.dibsAceGUIShell.frame, 650, 700)
    frame.dibsAceGUIShell.frame._scripts.OnSizeChanged(frame.dibsAceGUIShell.frame, 1000, 700)
    frame.dibsAceGUIShell.frame._scripts.OnSizeChanged(frame.dibsAceGUIShell.frame, 1300, 700)
    assert_true(frame._automaticDibsReflowQueued)
    dibs.AceGUI.FlushRefreshes()
    assert_equal(0, resizeCalculations)
    assert_equal("WIDE", frame.automaticDibsLayoutMode)
    assert_equal("FULL", frame.automaticDibsStructureMode)
    local tableRenderCountBeforeDirectReflow = getTableRenderCount()
    frame:ReflowAutomaticDibsTable(false)
    assert_equal(tableRenderCountBeforeDirectReflow, getTableRenderCount())

    local tableRenderCountBeforeSameStructureResize = getTableRenderCount()
    local refreshBeforeResize = frame.Refresh
    local resizeRefreshCount = 0
    frame.Refresh = function(self, ...)
      resizeRefreshCount = resizeRefreshCount + 1
      return refreshBeforeResize(self, ...)
    end
    frame.dibsAceGUIShell.frame._scripts.OnSizeChanged(frame.dibsAceGUIShell.frame, 1000, 700)
    dibs.AceGUI.FlushRefreshes()
    assert_equal("MEDIUM", frame.automaticDibsLayoutMode)
    assert_equal(0, resizeRefreshCount)
    assert_equal(tableRenderCountBeforeSameStructureResize, getTableRenderCount())

    frame.dibsAceGUIShell.frame._scripts.OnSizeChanged(frame.dibsAceGUIShell.frame, 650, 700)
    dibs.AceGUI.FlushRefreshes()
    assert_equal("NARROW", frame.automaticDibsLayoutMode)
    assert_equal(search, findWidget(function(widget)
      return widget.kind == "EditBox" and widget.label == "Search player"
    end))
    frame.dibsAceGUIShell.frame._scripts.OnSizeChanged(frame.dibsAceGUIShell.frame, 1300, 700)
    dibs.AceGUI.FlushRefreshes()
    assert_equal("WIDE", frame.automaticDibsLayoutMode)
    assert_equal(0, resizeCalculations)
    dibs.OfficerUI.BuildAutomaticAllocationDetails = buildDetails
    dibs.OfficerUI.BuildAutomaticDibsPresentation = buildPresentation
    assert_equal(search, findWidget(function(widget)
      return widget.kind == "EditBox" and widget.label == "Search player"
    end))
    frame.Refresh = pageRefresh
    local rankSearchResults = dibs.OfficerUI.BuildAutomaticDibsPresentation(
      dibs.OfficerUI.BuildAutomaticAllocationDetails(), "all", "Officer")
    assert_equal(1, #rankSearchResults.rows)
    assert_equal("Alice-Realm", rankSearchResults.rows[1].source.plainPlayerName)
  end)

  it("reflows the table through narrow, compact, and full layouts", function()
    local dibs = loadReconciliationRoster()
    local frame, getCapture = captureAutomaticTable(dibs)
    assert_equal("NARROW", dibs.OfficerUI.GetAutomaticDibsResponsiveLayoutMode(420))
    assert_equal("COMPACT", dibs.OfficerUI.GetAutomaticDibsResponsiveLayoutMode(640))
    assert_equal("MEDIUM", dibs.OfficerUI.GetAutomaticDibsResponsiveLayoutMode(900))
    assert_equal("WIDE", dibs.OfficerUI.GetAutomaticDibsResponsiveLayoutMode(1100))

    frame.dibsAceGUIShell.frame.GetWidth = function() return 600 end
    frame:Refresh()
    local narrow = getCapture()
    assert_equal(4, #narrow.columns)
    assert_equal("Player Name", narrow.columns[1].title)
    assert_false(narrow.columns[1].wrap)
    assert_equal("Diff", narrow.columns[2].title)
    assert_equal("Status", narrow.columns[3].title)
    assert_true(narrow.columns[4].action)
    assert_equal(32, narrow.options.rowHeight)
    local alice = assert(findRow(narrow, "Alice-Realm"))
    assert_equal("Alice-Realm", alice[1])
    assert_true(narrow.options.cellTooltip(alice, 1):find("Officer | Expected 1 | Assigned 0", 1, true) ~= nil)
    local narrowAction = findWidget(function(widget)
      return widget.kind == "Button" and widget.text == "RECONCILE"
    end)
    assert_equal(frame.automaticDibsTablePage.scroll, narrowAction.parent.parent.parent)

    frame.dibsAceGUIShell.frame.GetWidth = function() return 900 end
    frame:Refresh()
    assert_equal("COMPACT", frame.automaticDibsLayoutMode)
    assert_equal(6, #getCapture().columns)
    assert_equal("Allocation", getCapture().columns[3].title)
    local compactAlice = assert(findRow(getCapture(), "Alice-Realm"))
    assert_equal("1 / 0", compactAlice[3])
    assert_false(compactAlice[1]:find("\n", 1, true) ~= nil)
    local compactAction = findWidget(function(widget)
      return widget.kind == "Button" and widget.text == "RECONCILE"
    end)
    assert_equal(frame.automaticDibsTablePage.scroll, compactAction.parent.parent.parent)
    frame.dibsAceGUIShell.frame.GetWidth = function() return 1150 end
    frame:Refresh()
    assert_equal("MEDIUM", frame.automaticDibsLayoutMode)
    assert_equal(7, #getCapture().columns)
    local mediumAction = findWidget(function(widget)
      return widget.kind == "Button" and widget.text == "RECONCILE"
    end)
    assert_equal(frame.automaticDibsTablePage.scroll, mediumAction.parent.parent.parent)
  end)

  it("requests a guild roster refresh from the Automatic Dibs controls", function()
    local dibs = loadReconciliationRoster()
    local frame = captureAutomaticTable(dibs)
    local refreshRequested = false
    local previousGuildRoster = _G.GuildRoster
    _G.GuildRoster = function() refreshRequested = true end
    clickButton("Refresh roster")
    _G.GuildRoster = previousGuildRoster
    assert_true(refreshRequested)
    assert_true(frame.automaticDibsRosterLoading)
    assert_not_nil(findWidget(function(widget)
      return widget.kind == "Dropdown" and widget.label == "Status"
    end))
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
    assert_true(captured.columns[4].width < dibs.AceGUI.GetLayoutMetrics().actionMinWidth)
    assert_true(captured.columns[5].width < dibs.AceGUI.GetLayoutMetrics().actionMinWidth)
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
        local addColumn, removeColumn = capture.columns[4], capture.columns[5]
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
              assert_equal(button.text == addLabel and 4 or 5, button._dibsColumnIndex)
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

  it("projects offline-capable roster members without creating ledger records and sorts and searches", function()
    local dibs = loadOfficer("Tester-Realm", true)
    local seasonId = dibs.GetCurrentSeasonId()
    local grant = dibs.ProtectedActions.Execute("ledger.grant", nil, {
      playerName = "Firebut-DunModr", amount = 2, reason = "Sort fixture", source = "test", seasonId = seasonId,
    })
    assert_true(grant.ok)
    local before = #dibs.Ledger.GetAllTransactions()
    local roster = dibs.OfficerUI.BuildDibsAdministrationRoster(seasonId, "", "rank", false)

    assert_equal("ready", roster.state)
    assert_equal(4, #roster.rows)
    assert_equal("Tester-Realm", roster.rows[1].playerName)
    assert_equal("Firebut-DunModr", roster.rows[3].playerName)
    assert_equal(2, roster.rows[3].balance)
    assert_true(roster.rows[3].identityAvailable)
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