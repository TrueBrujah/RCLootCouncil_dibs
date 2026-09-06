local loader = require("helpers.load_addon")

describe("Combat safety", function()
  it("defers officer toggle during combat", function()
    local _, dibs = loader.load({ wow = { guildLeader = true, inCombat = true } })
    local shown = dibs.OfficerUI.Toggle(true)
    assert_false(shown)
    assert_true(dibs.OfficerUI.pendingToggle == true)
  end)

  it("does not expose officer data or open the officer view to ordinary guild members", function()
    local _, dibs = loader.load({ wow = {
      guildLeader = false,
      guildRankIndices = { [1] = 3 },
      guildMembers = { "Tester-Realm", "Officer-Realm" },
    } })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.Ledger.Grant("Officer-Realm", 2, "Private ledger check", "test", seasonId)

    local overview = dibs.OfficerUI.GetLedgerOverview()
    local details = dibs.OfficerUI.BuildLedgerDetails(seasonId)
    local page = dibs.OfficerUI.GetPagedView("actions", seasonId, 1, 10)

    assert_equal(0, overview.count)
    assert_true(overview.hidden == true)
    assert_equal(0, details.transactionCount)
    assert_true(details.hidden == true)
    assert_equal(0, page.totalCount)
    assert_false(dibs.OfficerUI.Toggle(true))
    assert_true(_G.DibsOfficerFrame == nil or not _G.DibsOfficerFrame:IsShown())
  end)

  it("builds player balances and recent actions for the selected season", function()
    local _, dibs = loader.load({ wow = {
      guildLeader = true,
      guildMembers = { "Tester-Realm", "Alice-Realm", "Bob-Realm" },
    } })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.Ledger.Grant("Alice-Realm", 2, "Raid reward", "test", seasonId)
    dibs.Ledger.Use("Bob-Realm", 1, "Item awarded", "test", seasonId)
    dibs.Ledger.Grant("Foreign-Realm", 2, "Other guild", "test", seasonId)

    local details = dibs.OfficerUI.BuildLedgerDetails(seasonId)

    assert_true(#details.players >= 2)
    assert_true(#details.actions >= 2)
    assert_true(string.find(details.players[1] .. details.players[2], "Alice-Realm", 1, true) ~= nil)
    assert_true(string.find(details.players[1] .. details.players[2], "Bob-Realm", 1, true) ~= nil)
    assert_true(string.find(details.actions[1] .. details.actions[2], "DIB_GRANTED", 1, true) ~= nil)
    assert_true(string.find(details.actions[1] .. details.actions[2], "DIB_USED", 1, true) ~= nil)
    assert_equal(1, details.hiddenTransactionCount)
  end)

  it("merges a guild member's short and realm-qualified names", function()
    local _, dibs = loader.load({ wow = {
      guildLeader = true,
      guildMembers = { "Tester-Realm", "Huudada-Durotan" },
    } })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.Ledger.Grant("Huudada", 3, "Short name", "test", seasonId)
    dibs.Ledger.Use("Huudada-Durotan", 1, "Full name", "test", seasonId)

    local details = dibs.OfficerUI.BuildLedgerDetails(seasonId)
    local playerSummary = table.concat(details.players, "\n")

    assert_equal(2, #details.players)
    assert_true(string.find(playerSummary, "Huudada-Durotan", 1, true) ~= nil)
    assert_true(string.find(playerSummary, "Huudada-Durotan |", 1, true) ~= nil)
    assert_true(string.find(playerSummary, "2 actions", 1, true) ~= nil)
  end)

  it("stores a roster member's full name when a short name is supplied", function()
    local _, dibs = loader.load({ wow = {
      guildLeader = true,
      guildMembers = { "Tester-Realm", "Huudada-Durotan" },
    } })
    local tx = dibs.Ledger.Grant("Huudada", 1, "Canonical identity", "test", dibs.GetCurrentSeasonId())

    assert_equal("Huudada-Durotan", tx.playerName)
    assert_equal("huudada-durotan", tx.playerKey)
    assert_equal(1, #dibs.Ledger.GetHistory("Huudada-Durotan"))
  end)

  it("paginates the officer action view", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    for index = 1, 10 do
      dibs.Ledger.Grant("Tester-Realm", 1, "Action " .. tostring(index), "test", seasonId)
    end

    local firstPage = dibs.OfficerUI.GetPagedView("actions", seasonId, 1, 5)
    local secondPage = dibs.OfficerUI.GetPagedView("actions", seasonId, 2, 5)
    local filtered = dibs.OfficerUI.GetPagedView("actions", seasonId, 1, 5, "Action 10")

    assert_equal(3, firstPage.totalPages)
    assert_equal(5, #firstPage.lines)
    assert_equal(5, #secondPage.lines)
    assert_equal(1, filtered.totalCount)
    assert_true(string.find(filtered.lines[1], "Action 10", 1, true) ~= nil)
  end)

  it("uses AceGUI widgets without native duplicate controls when services are available", function()
    local _, dibs = loader.load({ withAce3 = true, wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    for index = 1, 10 do
      dibs.Ledger.Grant("Tester-Realm", 1, "Ace action " .. tostring(index), "test", seasonId)
    end

    local firstWindowFrame = #_G.__dibsFrameCreations + 1
    local officer = dibs.OfficerUI.CreateWindow()
    local player = dibs.PlayerUI.CreateWindow()
    assert_true(dibs.AceGUI.IsAvailable())
    assert_not_nil(officer.dibsAceGUIShell)
    assert_not_nil(player.dibsAceGUIShell)
    assert_true(#_G.__dibsAceWidgets > 2)
    for index = firstWindowFrame, #_G.__dibsFrameCreations do
      assert_nil(_G.__dibsFrameCreations[index].template)
    end
    assert_equal(3, dibs.OfficerUI.GetPagedView("actions", seasonId, 1, 5).totalPages)
  end)

  it("summarizes current-season activity for dashboard and statistics tabs", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local season = dibs.Seasons.GetCurrent()
    dibs.Ledger.Grant("Tester-Realm", 3, "Reward", "test", season.id)
    dibs.Ledger.Use("Tester-Realm", 1, "Award", "test", season.id)
    dibs.PreDibs.CreatePublic("Tester-Realm", 21051, "Requested item", season.id, "test")

    local statistics = dibs.OfficerUI.BuildSeasonStatistics(season.id)
    local dashboard = dibs.OfficerUI.BuildDashboardDetails(season)

    assert_equal(3, statistics.granted)
    assert_equal(1, statistics.used)
    assert_equal(1, statistics.awards)
    assert_equal(1, statistics.activePreDibs)
    assert_true(string.find(table.concat(dashboard, "\n"), "Active pre-Dibs: 1", 1, true) ~= nil)
  end)

  it("keeps dashboard latest action within the selected season", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local earlierSeason = dibs.Seasons.GetCurrent()
    dibs.Ledger.Grant("Tester-Realm", 1, "Earlier season action", "test", earlierSeason.id)
    local laterSeason = dibs.Seasons.Create("Later season")
    dibs.Ledger.Grant("Tester-Realm", 1, "Later season action", "test", laterSeason.id)

    local dashboard = table.concat(dibs.OfficerUI.BuildDashboardDetails(earlierSeason), "\n")

    assert_true(string.find(dashboard, "Earlier season action", 1, true) ~= nil)
    assert_true(string.find(dashboard, "Later season action", 1, true) == nil)
  end)

  it("renders request difficulty and Vault acquisition state in officer search", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.PreDibs.CreatePublic("Tester-Realm", 21063, "Requested", seasonId, "test", { difficulty = "Mythic" })
    dibs.PreDibs.RecordVaultAcquisition("Tester-Realm", 21064, "Heroic")

    local requests = dibs.OfficerUI.GetPagedView("predibs", seasonId, 1, 10, "Mythic")
    local acquired = dibs.OfficerUI.GetPagedView("predibs", seasonId, 1, 10, "Acquired")

    assert_equal(1, requests.totalCount)
    assert_true(string.find(requests.lines[1], "Mythic", 1, true) ~= nil)
    assert_equal(1, acquired.totalCount)
    assert_true(string.find(acquired.lines[1], "VAULT", 1, true) ~= nil)
  end)
end)
