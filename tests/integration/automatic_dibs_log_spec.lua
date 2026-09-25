local loader = require("helpers.load_addon")

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
    assert_equal(3, #details.allocations)
    assert_true(string.find(details.allocations[1], "Alice-Realm", 1, true) ~= nil)
    assert_true(string.find(details.allocations[1], "Member", 1, true) ~= nil)
    assert_true(string.find(details.allocations[1], "+1", 1, true) ~= nil)

    local page = dibs.OfficerUI.GetPagedView("automaticDibs", seasonId, 1, 8)
    assert_equal("Automatic Dibs", page.title)
    assert_equal(3, page.totalCount)
    assert_equal(3, #page.rows)
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

describe("Officer Dibs administration", function()
  local members = { "Tester-Realm", "Officer-Realm", "Firebut-DunModr", "Member-Realm" }
  local ranks = { [1] = 0, [2] = 1, [3] = 2, [4] = 3 }

  local function loadOfficer(playerName, guildLeader)
    local _, dibs = loader.load({ withAce3 = true, wow = {
      playerName = playerName,
      guildLeader = guildLeader,
      guildMembers = members,
      guildRankIndices = ranks,
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
    local reason = findLatestWidget(function(widget) return widget.label == "Required reason" end)
    assert_not_nil(reason)
    reason.callbacks.OnTextChanged(reason, "OnTextChanged", "  Raid contribution  ")
    clickLatestButton("Confirm")

    assert_equal("ledger.adjust", submitted.action)
    assert_equal("Firebut-DunModr", submitted.payload.playerName)
    assert_equal(1, submitted.payload.amount)
    assert_equal("Raid contribution", submitted.payload.reason)
    assert_equal("MANUAL_ADMIN", submitted.payload.source)
    assert_equal(seasonId, submitted.payload.seasonId)
    assert_equal(beforeCount + 1, #dibs.Ledger.GetAllTransactions())
    assert_equal(1, dibs.Ledger.GetBalance("Firebut-DunModr", seasonId))
    local transaction = dibs.Ledger.GetHistory("Firebut-DunModr", seasonId)[#dibs.Ledger.GetHistory("Firebut-DunModr", seasonId)]
    assert_equal(1, transaction.amount)
    assert_equal("MANUAL_ADMIN", transaction.source)
    assert_equal("Raid contribution", transaction.reason)
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
    local officerReason = findLatestWidget(function(widget) return widget.label == "Required reason" end)
    officerReason.callbacks.OnTextChanged(officerReason, "OnTextChanged", "Officer bonus")
    clickLatestButton("Confirm")
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
    local gmReason = findLatestWidget(function(widget) return widget.label == "Required reason" end)
    gmReason.callbacks.OnTextChanged(gmReason, "OnTextChanged", "Attendance correction")
    clickLatestButton("Confirm")
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
    clickLatestButton("Confirm")
    local reason = findLatestWidget(function(widget) return widget.label == "Required reason" end)
    reason.callbacks.OnTextChanged(reason, "OnTextChanged", " \t ")
    clickLatestButton("Confirm")
    assert_equal(0, calls)
    clickLatestButton("Cancel")
    assert_equal(0, calls)

    clickLatestButton("ADD")
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