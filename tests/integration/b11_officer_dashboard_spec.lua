local loader = require("helpers.load_addon")

local function setup()
  local _, dibs = loader.load({ wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Player-1", "Player-2", "Player-3", "Player-4", "Player-5", "Player-6", "Player-7", "Player-8", "Coordinator-Realm" } }, withAce3 = true })
  dibs.Seasons.GetCurrent = function() return { id = 7, name = "Midnight Season" } end
  dibs.Ledger.GetTransactions = function()
    local rows = {}
    for index = 1, 8 do
      rows[index] = { createdAt = 100 + index, playerName = "Player-" .. tostring(index), type = "DIB_USED", amount = -index, reason = "Award" }
    end
    return rows
  end
  dibs.PreDibs.GetHistory = function()
    return {
      { requestId = "r1", seasonId = 7, status = "pending", playerName = "Player-1", itemName = "Item 1", createdAt = 108 },
      { requestId = "r2", seasonId = 7, status = "confirmed", playerName = "Player-2", itemName = "Item 2", createdAt = 107 },
      { requestId = "r3", seasonId = 7, status = "pending", playerName = "Player-3", itemName = "Item 3", createdAt = 106 },
      { requestId = "r4", seasonId = 7, status = "fulfilled", playerName = "Player-4", itemName = "Item 4", createdAt = 105 },
    }
  end
  dibs.Sync.GetStatus = function() return { state = "SYNC_BEHIND", protocolState = "V2_ENFORCED", reason = "SYNC_BEHIND" } end
  dibs.Governance.GetAuthorityState = function() return {
    state = "ACTIVE", protocolState = "V2_ENFORCED", ledgerEpoch = 4,
    coordinator = { displayName = "Coordinator-Realm" },
  } end
  dibs.RCLootCouncil.GetLocalStatus = function() return {
    availability = "degraded", status = "degraded", reasonCode = "RC_MASTER_LOOTER_UNVERIFIABLE",
    diagnostic = "Master Looter could not be verified.", observedVersion = "3.0",
  } end
  return dibs
end

describe("B11d Officer dashboard", function()
  it("projects bounded operational summaries from normalized services", function()
    local dibs = setup()
    local dashboard = dibs.OfficerUI.GetDashboardProjection()
    assert_equal("gm", dashboard.role)
    assert_equal("Midnight Season", dashboard.season.name)
    assert_equal("Healthy", dashboard.status.ledger.label)
    assert_equal("Behind / Synchronizing", dashboard.status.sync.label)
    assert_equal("Presence unknown", dashboard.status.coordinator.label)
    assert_equal("Degraded", dashboard.status.rclootcouncil.label)
    assert_equal(2, dashboard.metrics.pendingRequests)
    assert_equal(3, dashboard.metrics.activePreDibs)
    assert_equal(8, dashboard.metrics.awards)
    assert_equal(0, dashboard.metrics.grantedDibs)
    assert_equal(36, dashboard.metrics.usedDibs)
    assert_equal(0, dashboard.metrics.corrections)
    assert_equal(8, dashboard.metrics.awardRecipients)
    assert_equal(1, dashboard.metrics.averageAwardsPerRecipient)
    assert_equal(1, dashboard.metrics.medianAwardsPerRecipient)
    assert_equal(1, dashboard.metrics.maxAwardsPerRecipient)
    assert_equal(5, #dashboard.recentActivity)
    assert_equal("SYNC_BEHIND", dashboard.technical.sync.state)
    assert_equal("RC_MASTER_LOOTER_UNVERIFIABLE", dashboard.technical.rclootcouncil.reasonCode)
    assert_true(dashboard.status.sync.label:find("SYNC", 1, true) == nil)
    assert_true(dashboard.status.rclootcouncil.label:find("RC_", 1, true) == nil)
  end)

  it("shows the coordinator name and colors service state from live roster presence", function()
    local dibs = setup()
    local originalGetGuildRosterInfo = _G.GetGuildRosterInfo
    local coordinatorOnline = true
    _G.GetGuildRosterInfo = function(index)
      local name, rankName, rankIndex = originalGetGuildRosterInfo(index)
      if name == "Coordinator-Realm" then
        return name, rankName, rankIndex, nil, nil, nil, nil, nil, coordinatorOnline
      end
      return name, rankName, rankIndex
    end
    local rosterOnline
    for index = 1, _G.GetNumGuildMembers() do
      local name, _, _, _, _, _, _, _, online = _G.GetGuildRosterInfo(index)
      if name == "Coordinator-Realm" then rosterOnline = online end
    end
    assert_true(rosterOnline)

    local dashboard = dibs.OfficerUI.GetDashboardProjection()
    assert_equal("Online", dashboard.status.coordinator.label)
    assert_equal("Coordinator-Realm", dashboard.status.coordinator.memberName)
    assert_equal("success", dashboard.status.coordinator.tone)
    assert_equal("success", dashboard.status.ledger.tone)
    assert_equal("warning", dashboard.status.sync.tone)
    assert_equal("warning", dashboard.status.rclootcouncil.tone)

    dibs.OfficerUI.CreateWindow("overview")
    local coordinatorBadge
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Label" and widget.text:find("Coordinator: Coordinator-Realm (Online)", 1, true) then
        coordinatorBadge = widget
        break
      end
    end
    assert_not_nil(coordinatorBadge)
    assert_true(coordinatorBadge.text:find("[OK]", 1, true) ~= nil)
    assert_equal("success", coordinatorBadge.dibsMidnightStatus)

    coordinatorOnline = false
    dashboard = dibs.OfficerUI.GetDashboardProjection()
    assert_equal("Offline", dashboard.status.coordinator.label)
    assert_equal("warning", dashboard.status.coordinator.tone)
  end)

  it("shows season statistic blocks and opens searchable activity history", function()
    local dibs = setup()
    local openedView, openedSeasonId, openedQuery
    dibs.LogsUI.OpenOfficer = function(view, seasonId, query)
      openedView, openedSeasonId, openedQuery = view, seasonId, query
      return true
    end
    dibs.OfficerUI.CreateWindow("overview")

    local labels = {}
    local searchLogsButton
    local seasonStatsIndex, serviceStatusIndex, recentActivityIndex
    for index, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "Label" then labels[widget.text] = true end
      if widget.kind == "Button" and widget.text == "Search activity logs" then searchLogsButton = widget end
      if widget.kind == "Label" and widget.text == "Season statistics" then seasonStatsIndex = index end
      if widget.kind == "InlineGroup" and widget.title == "Service status" then serviceStatusIndex = index end
      if widget.kind == "InlineGroup" and widget.title == "Recent activity" then recentActivityIndex = index end
    end
    for _, label in ipairs({
      "Active players", "Pending requests", "Active Pre-Dibs", "Actions", "Awards",
      "Granted Dibs", "Used Dibs", "Corrections", "Award recipients",
      "Average awards", "Median awards", "Max awards",
    }) do
      assert_true(labels[label], "Dashboard statistic missing: " .. label)
    end
    assert_not_nil(searchLogsButton)
    assert_true(seasonStatsIndex < serviceStatusIndex)
    assert_true(serviceStatusIndex < recentActivityIndex)
    assert_true(#(_G.__dibsAceWidgets[serviceStatusIndex].children or {}) >= 8)
    assert_true(#(_G.__dibsAceWidgets[recentActivityIndex].children or {}) >= 2)
    searchLogsButton.callbacks.OnClick(searchLogsButton, "OnClick")
    assert_equal("actions", openedView)
    assert_equal(7, openedSeasonId)
    assert_nil(openedQuery)
  end)

  it("shows active Pre-Dibs for the live boss and offers a direct list shortcut", function()
    local dibs = setup()
    dibs.EncounterJournal.GetActiveEncounter = function()
      return { encounterID = 901, encounterName = "Test Warden", instanceID = 900, instanceName = "Citadel of Testing" }
    end
    dibs.EncounterJournal.GetLootCatalog = function()
      return {
        { itemID = 280011, encounterID = 901, instanceID = 900, itemName = "Warden's Curio" },
        { itemID = 280012, encounterID = 902, instanceID = 900, itemName = "Archive Token" },
      }, { available = true }
    end
    dibs.PreDibs.GetHistory = function()
      return {
        { seasonId = 7, status = "confirmed", playerName = "Player-1", itemID = 280011, itemName = "Warden's Curio", difficulty = "Heroic" },
        { seasonId = 7, status = "pending", playerName = "Player-2", itemID = 280012, itemName = "Archive Token" },
        { seasonId = 7, status = "fulfilled", playerName = "Player-3", itemID = 280011, itemName = "Warden's Curio" },
        { seasonId = 6, status = "confirmed", playerName = "Player-4", itemID = 280011, itemName = "Warden's Curio" },
      }
    end

    local dashboard = dibs.OfficerUI.GetDashboardProjection()
    assert_equal("Test Warden", dashboard.currentBossPreDibs.encounterName)
    assert_equal(1, dashboard.currentBossPreDibs.activeRequestCount)
    assert_equal("Warden's Curio", dashboard.currentBossPreDibs.rows[1].itemName)
    assert_equal("Player-1", dashboard.currentBossPreDibs.rows[1].playerName)

    local window = dibs.OfficerUI.CreateWindow("overview")
    local bossSection, openButton
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "InlineGroup" and widget.title == "Pre-Dibs by boss" then bossSection = widget end
      if widget.kind == "Button" and widget.text == "Open Pre-Dibs" then openButton = widget end
    end
    assert_not_nil(bossSection)
    assert_not_nil(openButton)
    assert_true(#(bossSection.children or {}) >= 3)
    openButton.callbacks.OnClick(openButton, "OnClick")
    assert_equal("preDibRequests", window.activeTab)
  end)

  it("shows up to five active Pre-Dibs per boss without requiring an active encounter", function()
    local dibs = setup()
    dibs.EncounterJournal.GetActiveEncounter = function() return nil end
    dibs.EncounterJournal.GetLootCatalog = function()
      return {
        { itemID = 280011, encounterID = 901, instanceID = 900, itemName = "Warden Curio", bossName = "Test Warden", instanceName = "Citadel" },
        { itemID = 280012, encounterID = 902, instanceID = 900, itemName = "Archive Token", bossName = "Archive Keeper", instanceName = "Citadel" },
      }, { available = true }
    end
    local requests = {}
    for index = 1, 7 do
      requests[index] = {
        requestId = "warden-" .. tostring(index), seasonId = 7,
        status = index == 1 and "pending" or "confirmed", playerName = "Player-" .. tostring(index),
        itemID = 280011, itemName = "Warden Curio", createdAt = 100 + index,
      }
    end
    requests[8] = {
      requestId = "archive-1", seasonId = 7, status = "confirmed", playerName = "Player-8",
      itemID = 280012, itemName = "Archive Token", createdAt = 200,
    }
    requests[9] = {
      requestId = "fulfilled", seasonId = 7, status = "fulfilled", playerName = "Player-9",
      itemID = 280012, itemName = "Archive Token", createdAt = 300,
    }
    dibs.PreDibs.GetHistory = function() return requests end

    local dashboard = dibs.OfficerUI.GetDashboardProjection()
    assert_equal(2, #dashboard.preDibBossGroups)
    local warden, archive
    for _, group in ipairs(dashboard.preDibBossGroups) do
      if group.encounterName == "Test Warden" then warden = group end
      if group.encounterName == "Archive Keeper" then archive = group end
    end
    assert_not_nil(warden)
    assert_equal(7, warden.activeRequestCount)
    assert_equal(5, #warden.rows)
    assert_equal(2, warden.moreCount)
    assert_not_nil(archive)
    assert_equal(1, #archive.rows)

    dibs.OfficerUI.CreateWindow("overview")
    local bossSection
    local visibleWardenRows = 0
    local visibleArchiveRows = 0
    local inWarden = false
    local inArchive = false
    for _, widget in ipairs(_G.__dibsAceWidgets or {}) do
      if widget.kind == "InlineGroup" and widget.title == "Pre-Dibs by boss" then bossSection = widget end
    end
    assert_not_nil(bossSection)
    for _, widget in ipairs(bossSection.children or {}) do
      if widget.kind == "Label" then
        if widget.text:find("Test Warden", 1, true) then inWarden = true; inArchive = false
        elseif widget.text:find("Archive Keeper", 1, true) then inArchive = true; inWarden = false
        elseif inWarden and widget.text:find("Warden Curio", 1, true) then visibleWardenRows = visibleWardenRows + 1
        elseif inArchive and widget.text:find("Archive Token", 1, true) then visibleArchiveRows = visibleArchiveRows + 1 end
      end
    end
    assert_equal(5, visibleWardenRows)
    assert_equal(1, visibleArchiveRows)
  end)

  it("keeps no-season and degraded states readable", function()
    local dibs = setup()
    dibs.Seasons.GetCurrent = function() return nil end
    dibs.Ledger.GetTransactions = function() return {} end
    dibs.PreDibs.GetHistory = function() return {} end
    dibs.Sync.GetStatus = function() return { state = "SYNC_UNAVAILABLE" } end
    dibs.Governance.GetAuthorityState = function() return { state = "COORDINATOR_UNAVAILABLE" } end
    dibs.RCLootCouncil.GetLocalStatus = function() return { availability = "absent", status = "absent", reasonCode = "RC_ABSENT" } end
    local dashboard = dibs.OfficerUI.GetDashboardProjection()
    assert_equal("No active season", dashboard.season.name)
    assert_equal("Unavailable", dashboard.status.ledger.label)
    assert_equal("Unavailable", dashboard.status.sync.label)
    assert_equal("Unavailable", dashboard.status.coordinator.label)
    assert_equal("Unavailable", dashboard.status.rclootcouncil.label)
    assert_equal("danger", dashboard.status.ledger.tone)
    assert_equal("danger", dashboard.status.sync.tone)
    assert_equal("danger", dashboard.status.coordinator.tone)
    assert_equal("danger", dashboard.status.rclootcouncil.tone)
    assert_equal("No pending requests.", dashboard.empty.pendingRequests)
    assert_equal("No active Pre-Dibs.", dashboard.empty.activePreDibs)
    assert_equal("No recent activity.", dashboard.empty.recentActivity)
  end)

  it("presents recovery as a human-readable coordinator state with technical disclosure", function()
    local dibs = setup()
    dibs.Governance.GetAuthorityState = function() return { state = "RECOVERY_PENDING", ledgerEpoch = 9 } end
    local dashboard = dibs.OfficerUI.GetDashboardProjection()
    assert_equal("Recovery in progress", dashboard.status.coordinator.label)
    assert_equal("RECOVERY_PENDING", dashboard.technical.coordinator.state)
    assert_true(dashboard.status.coordinator.explanation:find("recovery", 1, true) ~= nil)
  end)
end)