local loader = require("helpers.load_addon")

describe("Officer player-period statistics UI", function()
  it("shows descriptive per-player activity for the selected inclusive dates", function()
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
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.GetDB().ledger.transactions = {
      one = { transactionId = "one", seasonId = seasonId, playerName = "Tester-Realm", type = "DIB_USED", amount = -1, createdAt = dayStart + 50 },
      two = { transactionId = "two", seasonId = seasonId, playerName = "Other-Realm", type = "DIB_USED", amount = -1, createdAt = dayStart + 86400 + 50 },
    }

    local tables = {}
    local originalAddTable = dibs.AceGUI.AddTable
    dibs.AceGUI.AddTable = function(shell, parent, columns, rows, height, rowActions, options)
      tables[#tables + 1] = { columns = columns, rows = rows }
      return originalAddTable(shell, parent, columns, rows, height, rowActions, options)
    end
    local frame = dibs.OfficerUI.CreateWindow("statistics")
    assert_equal("statistics", frame.activeTab)
    local statisticsRouteAvailable = false
    for _, route in ipairs(dibs.OfficerUI.GetNavigationTree()) do
      if route.value == "statistics" then statisticsRouteAvailable = true end
    end
    assert_true(statisticsRouteAvailable)
    frame.selectedSeasonId = seasonId
    frame:ActivateRoute("statistics")

    local applyButton
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Button" and widget.text == dibs.L.OFFICER_STATISTICS_APPLY then
        applyButton = widget
      end
    end
    assert_not_nil(applyButton)
    frame.statisticsFromDate = "2026-09-06"
    frame.statisticsToDate = "2026-09-06"
    applyButton.callbacks.OnClick(applyButton, "OnClick")

    local statisticsTable
    for _, renderedTable in ipairs(tables) do
      if renderedTable.columns[1] and renderedTable.columns[1].title == dibs.L.OFFICER_STATISTICS_PLAYER then
        statisticsTable = renderedTable
      end
    end
    assert_not_nil(statisticsTable)
    assert_equal(2, #statisticsTable.rows)
    local testerRow
    for _, row in ipairs(statisticsTable.rows) do
      if row[1] == "Tester-Realm" then testerRow = row end
    end
    assert_not_nil(testerRow)
    assert_equal("1", testerRow[3])
    assert_equal("1", testerRow[5])
  end)

  it("shows a validation state instead of treating invalid dates as empty results", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    dibs.OfficerUI.CreateWindow("statistics")
    local applyButton
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Button" and widget.text == dibs.L.OFFICER_STATISTICS_APPLY then
        applyButton = widget
      end
    end
    assert_not_nil(applyButton)
    local frame = _G.DibsOfficerFrame
    frame.statisticsFromDate = "2026-02-30"
    applyButton.callbacks.OnClick(applyButton, "OnClick")

    local invalidVisible = false
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Label" and widget.text == dibs.L.OFFICER_STATISTICS_INVALID_RANGE then
        invalidVisible = true
      end
    end
    assert_true(invalidVisible)
  end)

  it("supports date-filtered statistics in the standard-frame fallback", function()
    local _, dibs = loader.load({
      wow = { guildLeader = true, guildMembers = { "Tester-Realm" } },
      withAce3 = true,
    })
    dibs.AceGUI.IsAvailable = function() return false end
    _G.DibsOfficerFrame = nil
    local seasonId = dibs.GetCurrentSeasonId()
    local dayStart = 1700000000
    _G.time = function(dateParts)
      if dateParts then
        return ((dateParts.year * 400) + (dateParts.month * 32) + dateParts.day) * 86400
      end
      return dayStart
    end
    local transactionDate = _G.time({ year = 2026, month = 9, day = 6 })
    dibs.GetDB().ledger.transactions = {
      one = { transactionId = "one", seasonId = seasonId, playerName = "Tester-Realm", type = "DIB_USED", amount = -1, createdAt = transactionDate + 50 },
    }

    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("statistics")
    frame.statisticsFromDateInput:SetText("2026-09-06")
    frame.statisticsToDateInput:SetText("2026-09-06")
    frame.statisticsApplyButton:GetScript("OnClick")(frame.statisticsApplyButton, "OnClick")

    local expected = string.format(dibs.L.OFFICER_STATISTICS_ROW_SUMMARY,
      "Tester-Realm", "1", "0", "1", "0")
    assert_true(frame.ledgerText._text:find(expected, 1, true) ~= nil)
    assert_true(frame.statisticsFromDateInput:IsShown())
  end)
end)
