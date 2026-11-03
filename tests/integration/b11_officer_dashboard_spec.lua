local loader = require("helpers.load_addon")

local function setup()
  local _, dibs = loader.load({ wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Player-1", "Player-2", "Player-3", "Player-4", "Player-5", "Player-6", "Player-7", "Player-8", "Coordinator-Realm" } }, withAce3 = true })
  dibs.Seasons.GetCurrent = function() return { id = 7, name = "Midnight Season" } end
  local fixtureTransactions = {}
  for index = 1, 8 do
    fixtureTransactions["dashboard-" .. tostring(index)] = {
      seasonId = 7, createdAt = 100 + index, playerName = "Player-" .. tostring(index),
      type = "DIB_USED", amount = -index, reason = "Award",
    }
  end
  dibs.GetDB().ledgers["guild-primary"].transactions = fixtureTransactions
  dibs.Ledger.GetTransactions = function()
    local rows = {}
    for index = 1, 8 do
      rows[index] = fixtureTransactions["dashboard-" .. tostring(index)]
    end
    return rows
  end
  dibs.Ledger.GetRecentTransactions = function(seasonId, limit, ledgerId, include)
    local rows = dibs.Ledger.GetTransactions(seasonId, nil, ledgerId)
    local recent = {}
    table.sort(rows, function(first, second) return first.createdAt > second.createdAt end)
    for _, row in ipairs(rows) do
      if type(include) ~= "function" or include(row) then
        recent[#recent + 1] = row
        if #recent >= limit then break end
      end
    end
    return recent
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
  dibs.Sync.GetStatusSummary = function() return dibs.Sync.GetStatus() end
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
    assert_equal("Online", dashboard.status.coordinator.label)
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

  it("builds only the projection requested by a paged view", function()
    local dibs = setup()
    local calls = { ledger = 0, automatic = 0, predibs = 0, vault = 0 }
    dibs.OfficerUI.BuildLedgerDetails = function()
      calls.ledger = calls.ledger + 1
      return { players = { "Player" }, actions = { "Action" }, hiddenTransactionCount = 0 }
    end
    dibs.OfficerUI.BuildAutomaticAllocationDetails = function()
      calls.automatic = calls.automatic + 1
      return { allocations = { "Allocation" }, rows = {}, hiddenTransactionCount = 0 }
    end
    dibs.OfficerUI.BuildPreDibDetails = function()
      calls.predibs = calls.predibs + 1
      return { requests = { "Pre-Dib" }, hiddenRequestCount = 0 }
    end
    dibs.OfficerUI.BuildVaultAcquisitionReview = function()
      calls.vault = calls.vault + 1
      return { rows = { { text = "Vault" } }, hiddenCount = 0 }
    end

    assert_equal("Action", dibs.OfficerUI.GetPagedView("actions", 7, 1, 5).lines[1])
    assert_equal(1, calls.ledger)
    assert_equal(0, calls.automatic)
    assert_equal(0, calls.predibs)
    assert_equal(0, calls.vault)

    assert_equal("Pre-Dib", dibs.OfficerUI.GetPagedView("predibs", 7, 1, 5).lines[1])
    assert_equal(1, calls.ledger)
    assert_equal(0, calls.automatic)
    assert_equal(1, calls.predibs)
    assert_equal(0, calls.vault)
  end)

  it("shares one season scan between statistics and recent dashboard activity", function()
    local dibs = setup()
    local original = dibs.OfficerUI.GetPagedView
    local originalSummary = dibs.Ledger.GetSeasonActivitySummary
    local fullActions, fullPreDibs = 0, 0
    local summaryReads = 0
    local summaryDB
    dibs.Ledger.GetSeasonActivitySummary = function(...)
      summaryReads = summaryReads + 1
      local arguments = { ... }
      summaryDB = arguments[5]
      return originalSummary(...)
    end
    dibs.OfficerUI.GetPagedView = function(view, ...)
      if view == "actions" then fullActions = fullActions + 1 end
      if view == "predibs" then fullPreDibs = fullPreDibs + 1 end
      return original(view, ...)
    end

    local originalDebugProfileStop = _G.debugprofilestop
    local profileTicks = 0
    _G.debugprofilestop = function()
      profileTicks = profileTicks + 1
      return profileTicks
    end
    dibs.UIRenderStats.Reset()
    dibs.UIRenderStats.SetEnabled(true)
    local dashboard = dibs.OfficerUI.GetDashboardProjection()
    dibs.UIRenderStats.SetEnabled(false)
    _G.debugprofilestop = originalDebugProfileStop
    dibs.OfficerUI.GetDashboardProjection()

    assert_equal(5, #dashboard.recentActivity)
    assert_equal(1, summaryReads, "statistics and recent rows should share one cold ledger scan")
    assert_true(type(summaryDB) == "table", "statistics should pass its resolved DB to the ledger aggregation")
    assert_equal(0, fullActions, "dashboard should use the bounded transaction query")
    assert_equal(0, fullPreDibs, "five recent actions should avoid scanning Pre-Dibs history")
    local timed = {}
    for _, entry in ipairs(dibs.UIRenderStats.GetReport().pages) do
      if entry.kind == "Officer data" then timed[entry.page] = true end
    end
    assert_true(timed["dashboard-recent-transaction-query"])
    assert_true(timed["dashboard-recent-transaction-format"])
    assert_true(timed["dashboard-context-ledger"])
    assert_true(timed["dashboard-context-database"])
    assert_true(timed["dashboard-context-role"])
    assert_true(timed["dashboard-context-sandbox"])
    assert_true(timed["dashboard-context-season"])
    assert_true(timed["dashboard-context-active-ledger"])
    assert_true(timed["dashboard-context-view-ledger"])
    assert_true(timed["dashboard-predibs-history-read"])
    assert_true(timed["dashboard-sync-status"])
    assert_true(timed["dashboard-authority-status"])
    assert_true(timed["dashboard-rclootcouncil-status"])
    assert_true(timed["dashboard-encounter-projection"])
    assert_true(timed["dashboard-projection-assembly"])
    dibs.Ledger.MarkTransactionsChanged()
    dibs.OfficerUI.GetDashboardProjection()
    assert_equal(2, summaryReads, "ledger revision should invalidate both statistics and recent rows")
    dibs.OfficerUI.GetPagedView = original
    dibs.Ledger.GetSeasonActivitySummary = originalSummary
  end)

  it("shares one resolved DB across dashboard season and ledger context reads", function()
    local dibs = setup()
    local db = dibs.GetDB()
    local originalSeason = dibs.Seasons.GetCurrent
    local originalActiveLedger = dibs.MultiLedger.GetActiveLedgerId
    local originalViewLedger = dibs.MultiLedger.GetViewLedgerId
    local originalGetLedgers = dibs.MultiLedger.GetLedgers
    local originalBuildStatistics = dibs.OfficerUI.BuildSeasonStatistics
    local originalAuthority = dibs.Governance.GetAuthorityState
    local originalRevision = dibs.Ledger.GetDataRevision
    local observed = {}
    local revisionDatabases = {}
    dibs.Seasons.GetCurrent = function(resolvedDB)
      observed.season = resolvedDB
      return originalSeason(resolvedDB)
    end
    dibs.MultiLedger.GetActiveLedgerId = function(resolvedDB)
      observed.activeLedger = resolvedDB
      return originalActiveLedger(resolvedDB)
    end
    dibs.MultiLedger.GetViewLedgerId = function(resolvedDB)
      observed.viewLedger = resolvedDB
      return originalViewLedger(resolvedDB)
    end
    dibs.MultiLedger.GetLedgers = function(options, resolvedDB)
      observed.ledgerChoices = resolvedDB
      assert_equal(false, options and options.includeTransactionCount)
      return originalGetLedgers(options, resolvedDB)
    end
    dibs.Governance.GetAuthorityState = function(resolvedDB)
      observed.authority = resolvedDB
      return originalAuthority(resolvedDB)
    end
    dibs.Ledger.GetDataRevision = function(ledgerId, resolvedDB)
      revisionDatabases[#revisionDatabases + 1] = resolvedDB
      return originalRevision(ledgerId, resolvedDB)
    end
    dibs.OfficerUI.BuildSeasonStatistics = function(...)
      local arguments = { ... }
      observed.statistics = arguments[6]
      return originalBuildStatistics(...)
    end

    local getDB = dibs.GetDB
    dibs.GetDB = function() error("dashboard should reuse the route's resolved DB") end
    local ok, projection = pcall(dibs.OfficerUI.GetDashboardProjection, db)
    dibs.GetDB = getDB
    dibs.Seasons.GetCurrent = originalSeason
    dibs.MultiLedger.GetActiveLedgerId = originalActiveLedger
    dibs.MultiLedger.GetViewLedgerId = originalViewLedger
    dibs.MultiLedger.GetLedgers = originalGetLedgers
    dibs.Governance.GetAuthorityState = originalAuthority
    dibs.Ledger.GetDataRevision = originalRevision
    dibs.OfficerUI.BuildSeasonStatistics = originalBuildStatistics

    assert_true(ok, tostring(projection))
    assert_true(type(projection) == "table")
    assert_equal(db, observed.season)
    assert_equal(db, observed.activeLedger)
    assert_equal(db, observed.viewLedger)
    assert_equal(db, observed.ledgerChoices)
    assert_equal(db, observed.authority)
    assert_equal(db, observed.statistics)
    assert_true(#revisionDatabases >= 2, "dashboard statistics and activity cache should read the ledger revision")
    for _, resolvedDB in ipairs(revisionDatabases) do
      assert_equal(db, resolvedDB, "dashboard revision reads should reuse the shared DB")
    end
  end)

  it("builds only the bounded recent Pre-Dibs fallback instead of the full history view", function()
    local dibs = setup()
    local originalRecentTransactions = dibs.Ledger.GetRecentTransactions
    local originalBuildSeasonStatistics = dibs.OfficerUI.BuildSeasonStatistics
    local originalGetPagedView = dibs.OfficerUI.GetPagedView
    local originalBuildPreDibDetails = dibs.OfficerUI.BuildPreDibDetails
    local originalGetAcquisitions = dibs.PreDibs.GetAcquisitions
    local originalGetAcquisitionsSnapshotFast = dibs.PreDibs.GetAcquisitionsSnapshotFast
    local originalGetHistory = dibs.PreDibs.GetHistory
    local historyReads, acquisitionFastReads = 0, 0
    dibs.Ledger.GetRecentTransactions = function() return {} end
    dibs.OfficerUI.BuildSeasonStatistics = function(...)
      local statistics = originalBuildSeasonStatistics(...)
      statistics.recentTransactions = {}
      return statistics
    end
    dibs.OfficerUI.GetPagedView = function(view, ...)
      if view == "actions" then return { lines = {} } end
      return originalGetPagedView(view, ...)
    end
    dibs.OfficerUI.BuildPreDibDetails = function()
      error("dashboard fallback must not build the full Pre-Dibs history projection")
    end
    dibs.PreDibs.GetHistory = function(...)
      historyReads = historyReads + 1
      return originalGetHistory(...)
    end
    local fixtureAcquisitions = {
      { acquisitionId = "a-new", seasonId = 7, playerName = "Player-5", itemID = 900,
        acquiredAt = 109, difficulty = "Heroic", source = "VAULT" },
      { acquisitionId = "a-old", seasonId = 7, playerName = "Player-6", itemID = 901,
        acquiredAt = 104, difficulty = "Normal", source = "VAULT" },
    }
    dibs.PreDibs.GetAcquisitionsSnapshotFast = function()
      acquisitionFastReads = acquisitionFastReads + 1
      return fixtureAcquisitions
    end
    dibs.PreDibs.GetAcquisitions = function()
      error("dashboard fallback should use the initialized fast acquisition snapshot")
    end

    local originalDebugProfileStop = _G.debugprofilestop
    local profileTicks = 0
    _G.debugprofilestop = function()
      profileTicks = profileTicks + 1
      return profileTicks
    end
    dibs.UIRenderStats.Reset()
    dibs.UIRenderStats.SetEnabled(true)
    local dashboard = dibs.OfficerUI.GetDashboardProjection()
    dibs.UIRenderStats.SetEnabled(false)
    _G.debugprofilestop = originalDebugProfileStop

    assert_equal(5, #dashboard.recentActivity)
    assert_equal(1, historyReads, "the dashboard should reuse its already-read request history")
    assert_equal(1, acquisitionFastReads, "the dashboard should read acquisitions through the fast snapshot")
    assert_true(dashboard.recentActivity[1]:find("| Player-5 | Acquired | Item 900 |", 1, true) ~= nil)
    assert_true(dashboard.recentActivity[2]:find("| Player-1 | pending | Item 1 |", 1, true) ~= nil)
    assert_true(dashboard.recentActivity[5]:find("| Player-4 | fulfilled | Item 4 |", 1, true) ~= nil)
    local timed = {}
    for _, entry in ipairs(dibs.UIRenderStats.GetReport().pages) do
      if entry.kind == "Officer data" then timed[entry.page] = true end
    end
    assert_true(timed["dashboard-recent-predibs-roster"])
    assert_true(timed["dashboard-recent-predibs-request-scan"])
    assert_true(timed["dashboard-recent-predibs-acquisition-read"])
    assert_true(timed["dashboard-recent-predibs-acquisition-scan"])
    assert_true(timed["dashboard-recent-predibs-format"])
    dibs.Ledger.GetRecentTransactions = originalRecentTransactions
    dibs.OfficerUI.BuildSeasonStatistics = originalBuildSeasonStatistics
    dibs.OfficerUI.GetPagedView = originalGetPagedView
    dibs.OfficerUI.BuildPreDibDetails = originalBuildPreDibDetails
    dibs.PreDibs.GetAcquisitions = originalGetAcquisitions
    dibs.PreDibs.GetAcquisitionsSnapshotFast = originalGetAcquisitionsSnapshotFast
    dibs.PreDibs.GetHistory = originalGetHistory
  end)

  it("avoids a duplicate first-show render and a full-ledger overview scan", function()
    local dibs = setup()
    dibs.Ledger.GetAllTransactions = function()
      error("OfficerUI.Show must not copy and sort the full ledger")
    end

    local frame = dibs.OfficerUI.Show()
    assert_not_nil(frame)
    assert_equal(1, frame.routeDispatchCount)
    local onShow = frame.GetScript and frame:GetScript("OnShow") or frame._scripts and frame._scripts.OnShow
    assert_not_nil(onShow)
    onShow(frame)
    assert_equal(1, frame.routeDispatchCount)
    onShow(frame)
    assert_equal(2, frame.routeDispatchCount)
    local originalDebugProfileStop = _G.debugprofilestop
    local profileTicks = 0
    _G.debugprofilestop = function()
      profileTicks = profileTicks + 1
      return profileTicks
    end
    dibs.UIRenderStats.Reset()
    dibs.UIRenderStats.SetEnabled(true)
    frame:ActivateRoute("overview")
    dibs.UIRenderStats.SetEnabled(false)
    _G.debugprofilestop = originalDebugProfileStop
    local timed = {}
    for _, entry in ipairs(dibs.UIRenderStats.GetReport().pages) do
      if entry.kind == "Officer data" then timed[entry.page] = true end
    end
    assert_true(timed["dashboard-ui-total"])
    assert_true(timed["dashboard-ui-projection"])
    assert_true(timed["dashboard-context-ledger-choices"])
    assert_true(timed["dashboard-ui-control-header"])
    assert_true(timed["dashboard-ui-ledger-selector"])
    assert_true(timed["dashboard-ui-controls"])
    assert_true(timed["dashboard-ui-metrics"])
    assert_true(timed["dashboard-ui-predibs"])
    assert_true(timed["dashboard-ui-services"])
    assert_true(timed["dashboard-ui-activity"])
    assert_true(timed["dashboard-ui-technical"])
  end)

  it("does not build the Pre-Dib table projection twice when opening its Officer route", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    local original = dibs.OfficerUI.GetPagedView
    dibs.OfficerUI.GetPagedView = function(view, ...)
      if view == "predibs" then error("Pre-Dib Requests should reuse its filtered request projection") end
      return original(view, ...)
    end

    local ok, reason = pcall(frame.ActivateRoute, frame, "preDibRequests")
    dibs.OfficerUI.GetPagedView = original
    assert_true(ok, tostring(reason))
    assert_equal("preDibRequests", frame.activeTab)
  end)

  it("records CPU-only subphases for the Officer Pre-Dib Requests page", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    local originalDebugProfileStop = _G.debugprofilestop
    local profileTicks = 0
    _G.debugprofilestop = function()
      profileTicks = profileTicks + 1
      return profileTicks
    end
    dibs.UIRenderStats.Reset()
    dibs.UIRenderStats.SetEnabled(true)
    frame:ActivateRoute("preDibRequests")
    dibs.UIRenderStats.SetEnabled(false)
    _G.debugprofilestop = originalDebugProfileStop

    local measured = {}
    for _, entry in ipairs(dibs.UIRenderStats.GetReport().pages) do
      if entry.kind == "Officer data" then measured[entry.page] = true end
    end
    assert_true(measured["preDibRequests-filter-controls"])
    assert_true(measured["preDibRequests-ledger-selector"])
    assert_true(measured["preDibRequests-view-build"])
    assert_true(measured["preDibRequests-page-slice"])
    assert_true(measured["preDibRequests-table-rows"])
    assert_true(measured["preDibRequests-pagination-controls"])
    assert_true(measured["preDibRequests-table-build"])
  end)

  it("records CPU-only health and eligibility route phases", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    local originalDebugProfileStop = _G.debugprofilestop
    local profileTicks = 0
    _G.debugprofilestop = function()
      profileTicks = profileTicks + 1
      return profileTicks
    end
    dibs.UIRenderStats.Reset()
    dibs.UIRenderStats.SetEnabled(true)
    frame:ActivateRoute("diagnostics")
    frame:ActivateRoute("eligibility")
    dibs.UIRenderStats.SetEnabled(false)
    _G.debugprofilestop = originalDebugProfileStop

    local measured = {}
    for _, entry in ipairs(dibs.UIRenderStats.GetReport().pages) do
      if entry.kind == "Officer data" then measured[entry.page] = true end
    end
    assert_true(measured["diagnostics-health-evaluate"])
    assert_true(measured["diagnostics-anomaly-scan"])
    local measuredHealthPhases = {}
    for _, entry in ipairs(dibs.UIRenderStats.GetReport().pages) do
      if entry.kind == "Health data" then measuredHealthPhases[entry.page] = true end
    end
    assert_true(measuredHealthPhases.persistence)
    assert_true(measuredHealthPhases.readiness)
    assert_true(measuredHealthPhases.integrations)
    assert_true(measuredHealthPhases.backup)
    assert_true(measuredHealthPhases.finalize)
    assert_true(measured["eligibility-policy-projection"])
    assert_true(measured["eligibility-relationship-reads"])
    assert_true(measured["eligibility-route-previous-state-cleanup"])
    assert_true(measured["eligibility-route-content-clear"])
    assert_true(measured["eligibility-route-scaffold"])
    assert_true(measured["eligibility-route-season-context"])
    assert_true(measured["eligibility-route-season-list"])
    assert_true(measured["eligibility-route-selected-season"])
    assert_true(measured["eligibility-route-normalization"])
    assert_true(measured["eligibility-route-visibility-check"])
  end)

  it("records the internal phases of a profiled guild database lookup", function()
    local dibs = setup()
    local originalDebugProfileStop = _G.debugprofilestop
    local profileTicks = 0
    _G.debugprofilestop = function()
      profileTicks = profileTicks + 1
      return profileTicks
    end
    dibs.UIRenderStats.Reset()
    dibs.UIRenderStats.SetEnabled(true)
    dibs.GetDB()
    dibs._persistenceSource = nil
    dibs.GetDB()
    dibs.UIRenderStats.SetEnabled(false)
    _G.debugprofilestop = originalDebugProfileStop

    local measured = {}
    for _, entry in ipairs(dibs.UIRenderStats.GetReport().pages) do
      if entry.kind == "Core data" then measured[entry.page] = true end
    end
    assert_true(measured["get-db-guild-key"])
    assert_true(measured["get-db-ensure"])
    assert_true(measured["get-db-sandbox-store"])
    assert_true(measured["get-db-ready-root-check"])
    assert_true(measured["get-db-fast-path-hit"])
    assert_true(measured["get-db-fast-path-miss-source-identity"])
    assert_true(measured["get-db-root-copy"])
  end)

  it("records CPU-only subphases for the Officer Modules page", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    local originalDebugProfileStop = _G.debugprofilestop
    local profileTicks = 0
    _G.debugprofilestop = function()
      profileTicks = profileTicks + 1
      return profileTicks
    end
    dibs.UIRenderStats.Reset()
    dibs.UIRenderStats.SetEnabled(true)
    frame:ActivateRoute("modules")
    dibs.UIRenderStats.SetEnabled(false)
    _G.debugprofilestop = originalDebugProfileStop

    local measured = {}
    for _, entry in ipairs(dibs.UIRenderStats.GetReport().pages) do
      if entry.kind == "Officer data" then measured[entry.page] = true end
    end
    assert_true(measured["modules-feature-catalog"])
    assert_true(measured["modules-core-features-ui"])
    assert_true(measured["modules-optional-features-ui"])
    assert_true(measured["modules-actions-ui"])
    assert_true(measured["modules-governance-ui"])
    assert_true(measured["modules-governance-heading"])
    assert_true(measured["modules-governance-status-ui"])
  end)

  it("records CPU-only Guided Setup view-model and stage-render phases", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    local originalDebugProfileStop = _G.debugprofilestop
    local profileTicks = 0
    _G.debugprofilestop = function()
      profileTicks = profileTicks + 1
      return profileTicks
    end
    dibs.UIRenderStats.Reset()
    dibs.UIRenderStats.SetEnabled(true)
    frame:ActivateRoute("wizard")
    dibs.UIRenderStats.SetEnabled(false)
    _G.debugprofilestop = originalDebugProfileStop

    local measured = {}
    for _, entry in ipairs(dibs.UIRenderStats.GetReport().pages) do
      if entry.kind == "Officer data" then measured[entry.page] = true end
    end
    assert_true(measured["wizard-view-model"])
    assert_true(measured["wizard-stage-navigation"])
    assert_true(measured["wizard-stage-content"])
  end)

  it("lays out the mounted Officer page without reflowing the navigation tree", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    local navigation, contentHost = frame.aceTabs, frame.contentHost
    local originalNavigationLayout = navigation.DoLayout
    local originalContentLayout = contentHost.DoLayout
    local navigationLayoutCalls, contentLayoutCalls = 0, 0
    navigation.DoLayout = function(self)
      navigationLayoutCalls = navigationLayoutCalls + 1
      return originalNavigationLayout(self)
    end
    contentHost.DoLayout = function(self)
      contentLayoutCalls = contentLayoutCalls + 1
      if originalContentLayout then return originalContentLayout(self) end
    end

    frame:ActivateRoute("wizard")

    navigation.DoLayout = originalNavigationLayout
    contentHost.DoLayout = originalContentLayout
    assert_equal(0, navigationLayoutCalls)
    assert_equal(1, contentLayoutCalls)
    assert_equal("wizard", frame.activeTab)
  end)

  it("reuses the route database for Officer setup-help evaluation", function()
    local dibs = setup()
    local originalSetShellStatus = dibs.AceGUI.SetShellStatus
    local originalEvaluate = dibs.SetupAssistant.Evaluate
    local routeDB = dibs.GetDB()
    local evaluateDB
    dibs.AceGUI.SetShellStatus = function(shell, text)
      local ok = originalSetShellStatus(shell, text)
      return ok, routeDB
    end
    dibs.SetupAssistant.Evaluate = function(options)
      evaluateDB = options and options.db
      return originalEvaluate(options)
    end

    local frame = dibs.OfficerUI.CreateWindow("installation")
    frame:ActivateRoute("installation")

    dibs.AceGUI.SetShellStatus = originalSetShellStatus
    dibs.SetupAssistant.Evaluate = originalEvaluate
    assert_equal(routeDB, evaluateDB, "setup guidance should reuse the route's validated DB")
  end)

  it("reuses the route database for Diagnostics health evaluation", function()
    local dibs = setup()
    local originalSetShellStatus = dibs.AceGUI.SetShellStatus
    local originalEvaluate = dibs.HealthUI.Evaluate
    local routeDB = dibs.GetDB()
    local evaluatedDB
    dibs.AceGUI.SetShellStatus = function(shell, text)
      local ok = originalSetShellStatus(shell, text)
      return ok, routeDB
    end
    dibs.HealthUI.Evaluate = function(options)
      evaluatedDB = options and options.db
      return originalEvaluate(options)
    end

    local frame = dibs.OfficerUI.CreateWindow("diagnostics")
    frame:ActivateRoute("diagnostics")

    dibs.AceGUI.SetShellStatus = originalSetShellStatus
    dibs.HealthUI.Evaluate = originalEvaluate
    assert_equal(routeDB, evaluatedDB, "the health report should use the shell's resolved guild DB")
  end)

  it("reuses the route database for Officer Requests and delivery preflight", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow("disputes")
    local originalSetShellStatus = dibs.AceGUI.SetShellStatus
    local originalListForOfficer = dibs.Disputes.ListForOfficer
    local originalPump = dibs.RequestDelivery.Pump
    local originalGetModuleStatus = dibs.OperationalPolicy.GetModuleStatus
    local routeDB = dibs.GetDB()
    local listDB, pumpDB
    local requestModuleDBs = {}
    dibs.AceGUI.SetShellStatus = function(shell, text)
      local ok = originalSetShellStatus(shell, text)
      return ok, routeDB
    end
    dibs.Disputes.ListForOfficer = function(actor, options)
      listDB = options and options.db
      return originalListForOfficer(actor, options)
    end
    dibs.RequestDelivery.Pump = function(skipReminderScan, moduleEnabled, dbOverride)
      pumpDB = dbOverride
      return originalPump(skipReminderScan, moduleEnabled, dbOverride)
    end
    dibs.OperationalPolicy.GetModuleStatus = function(moduleKey, dbOverride)
      if moduleKey == "requests" then requestModuleDBs[#requestModuleDBs + 1] = dbOverride end
      return originalGetModuleStatus(moduleKey, dbOverride)
    end

    frame:ActivateRoute("disputes")

    dibs.AceGUI.SetShellStatus = originalSetShellStatus
    dibs.Disputes.ListForOfficer = originalListForOfficer
    dibs.RequestDelivery.Pump = originalPump
    dibs.OperationalPolicy.GetModuleStatus = originalGetModuleStatus
    assert_equal(routeDB, listDB, "the Requests preflight and state query should reuse the route DB")
    assert_equal(routeDB, pumpDB, "delivery checks should reuse the route DB")
    assert_true(#requestModuleDBs > 0, "the Requests module should be checked during route resolution")
    for _, dbOverride in ipairs(requestModuleDBs) do
      assert_equal(routeDB, dbOverride, "Requests module checks should reuse the route DB")
    end
  end)

  it("reuses the route database for Raid Readiness and Guild Setup evaluation", function()
    local dibs = setup()
    local originalSetShellStatus = dibs.AceGUI.SetShellStatus
    local originalEvaluate = dibs.SetupAssistant.Evaluate
    local routeDB = dibs.GetDB()
    local evaluated = {}
    dibs.AceGUI.SetShellStatus = function(shell, text)
      local ok = originalSetShellStatus(shell, text)
      return ok, routeDB
    end
    dibs.SetupAssistant.Evaluate = function(options)
      evaluated[#evaluated + 1] = { scope = options and options.scope, db = options and options.db }
      return originalEvaluate(options)
    end

    local frame = dibs.OfficerUI.CreateWindow("setup")
    frame:ActivateRoute("setup")
    frame:ActivateRoute("guildSetup")

    dibs.AceGUI.SetShellStatus = originalSetShellStatus
    dibs.SetupAssistant.Evaluate = originalEvaluate
    local scopes = {}
    for _, evaluation in ipairs(evaluated) do
      scopes[evaluation.scope] = true
      assert_equal(routeDB, evaluation.db, "setup routes should reuse the route database")
    end
    assert_true(scopes.raid, "Raid Readiness should evaluate raid scope")
    assert_true(scopes.guild, "Guild Setup should evaluate guild scope")
  end)

  it("reuses the route database in Pre-Dibs AceConfig getters", function()
    local dibs = setup()
    local originalSetShellStatus = dibs.AceGUI.SetShellStatus
    local originalGetModePolicy = dibs.PreDibs.GetModePolicy
    local originalIsPublicEnabled = dibs.PreDibs.IsPublicEnabled
    local routeDB = dibs.GetDB()
    local modeDB, publicDB
    dibs.AceGUI.SetShellStatus = function(shell, text)
      local ok = originalSetShellStatus(shell, text)
      return ok, routeDB
    end
    dibs.PreDibs.GetModePolicy = function(seasonId, ledgerId, dbOverride)
      modeDB = dbOverride
      return originalGetModePolicy(seasonId, ledgerId, dbOverride)
    end
    dibs.PreDibs.IsPublicEnabled = function(dbOverride)
      publicDB = dbOverride
      return originalIsPublicEnabled(dbOverride)
    end

    local frame = dibs.OfficerUI.CreateWindow("preDibs")
    frame:ActivateRoute("preDibs")

    dibs.AceGUI.SetShellStatus = originalSetShellStatus
    dibs.PreDibs.GetModePolicy = originalGetModePolicy
    dibs.PreDibs.IsPublicEnabled = originalIsPublicEnabled
    assert_equal(routeDB, modeDB, "the mode getter should receive the route DB")
    assert_equal(routeDB, publicDB, "the public toggle getter should receive the route DB")
  end)

  it("reuses the route database for eligibility policies and Main/Alt lists", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    local originalSetShellStatus = dibs.AceGUI.SetShellStatus
    local eligibility = dibs.CharacterEligibility
    local seasons = dibs.Seasons
    local originalGetPolicy = eligibility.GetPolicy
    local originalListRelationships = eligibility.ListRelationships
    local originalListMainChanges = eligibility.ListMainChanges
    local originalListSeasons = seasons.List
    local originalGetSeasonById = seasons.GetById
    local originalGetCurrentSeason = seasons.GetCurrent
    local routeDB = dibs.GetDB()
    frame.selectedSeasonId = seasons.GetCurrent(routeDB).id
    local policyDBs, relationshipsDB, mainChangesDB = {}, nil, nil
    local seasonListDB, selectedSeasonDB, currentSeasonDB
    dibs.AceGUI.SetShellStatus = function(shell, text)
      local ok = originalSetShellStatus(shell, text)
      return ok, routeDB
    end
    eligibility.GetPolicy = function(seasonId, family, dbOverride)
      policyDBs[#policyDBs + 1] = dbOverride
      return originalGetPolicy(seasonId, family, dbOverride)
    end
    eligibility.ListRelationships = function(actor, seasonId, dbOverride)
      relationshipsDB = dbOverride
      return originalListRelationships(actor, seasonId, dbOverride)
    end
    eligibility.ListMainChanges = function(actor, seasonId, dbOverride)
      mainChangesDB = dbOverride
      return originalListMainChanges(actor, seasonId, dbOverride)
    end
    seasons.List = function(includeArchived, dbOverride)
      seasonListDB = dbOverride
      return originalListSeasons(includeArchived, dbOverride)
    end
    seasons.GetById = function(seasonId, dbOverride)
      selectedSeasonDB = dbOverride
      return originalGetSeasonById(seasonId, dbOverride)
    end
    seasons.GetCurrent = function(dbOverride)
      currentSeasonDB = dbOverride
      return originalGetCurrentSeason(dbOverride)
    end

    frame:ActivateRoute("eligibility")
    frame.selectedSeasonId = nil
    frame:ActivateRoute("eligibility")

    dibs.AceGUI.SetShellStatus = originalSetShellStatus
    eligibility.GetPolicy = originalGetPolicy
    eligibility.ListRelationships = originalListRelationships
    eligibility.ListMainChanges = originalListMainChanges
    seasons.List = originalListSeasons
    seasons.GetById = originalGetSeasonById
    seasons.GetCurrent = originalGetCurrentSeason
    assert_true(#policyDBs >= 2, "the policy projection should read the TOKEN policies")
    for _, resolvedDB in ipairs(policyDBs) do
      assert_equal(routeDB, resolvedDB, "every policy read should use the route database")
    end
    assert_equal(routeDB, relationshipsDB)
    assert_equal(routeDB, mainChangesDB)
    assert_equal(routeDB, seasonListDB)
    assert_equal(routeDB, selectedSeasonDB)
    assert_equal(routeDB, currentSeasonDB)
  end)

  it("reuses the route database for Guided Setup administration and governance summaries", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    local routeDB = dibs.GetDB()
    local originalSetShellStatus = dibs.AceGUI.SetShellStatus
    local originalGetAuthorizedOfficers = dibs.Permissions.GetAuthorizedOfficers
    local originalGetInstallationSummary = dibs.Governance.GetInstallationSummary
    local originalGetState = dibs.Governance.GetState
    local officerDB, governanceDBs = nil, {}
    dibs.AceGUI.SetShellStatus = function(shell, text)
      local ok = originalSetShellStatus(shell, text)
      return ok, routeDB
    end
    dibs.Permissions.GetAuthorizedOfficers = function(dbOverride)
      officerDB = dbOverride
      return originalGetAuthorizedOfficers(dbOverride)
    end
    dibs.Governance.GetInstallationSummary = function(dbOverride)
      governanceDBs[#governanceDBs + 1] = dbOverride
      return originalGetInstallationSummary(dbOverride)
    end
    dibs.Governance.GetState = function()
      error("Guided Setup should not copy the full governance state")
    end
    dibs.Installation.GetStatus(nil, routeDB)
    dibs.Wizard.SetCurrentStage("verify")

    frame:ActivateRoute("wizard")

    dibs.AceGUI.SetShellStatus = originalSetShellStatus
    dibs.Permissions.GetAuthorizedOfficers = originalGetAuthorizedOfficers
    dibs.Governance.GetInstallationSummary = originalGetInstallationSummary
    dibs.Governance.GetState = originalGetState
    assert_equal(routeDB, officerDB)
    assert_true(#governanceDBs > 0, "Guided Setup should read its compact governance summary")
    for _, resolvedDB in ipairs(governanceDBs) do
      assert_equal(routeDB, resolvedDB, "every governance summary should use the route database")
    end
  end)

  it("does not count every ledger transaction to build the Pre-Dib Requests selector", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    local originalGetLedgers = dibs.MultiLedger.GetLedgers
    local originalGetActiveLedgerId = dibs.MultiLedger.GetActiveLedgerId
    local originalGetViewLedgerId = dibs.MultiLedger.GetViewLedgerId
    local originalSetShellStatus = dibs.AceGUI.SetShellStatus
    local reads, transactionCountReads = 0, 0
    local selectorDB, activeLedgerDB, viewLedgerDB
    dibs.MultiLedger.GetLedgers = function(options, dbOverride)
      reads = reads + 1
      selectorDB = dbOverride
      if type(options) ~= "table" or options.includeTransactionCount ~= false then
        transactionCountReads = transactionCountReads + 1
      end
      return originalGetLedgers(options, dbOverride)
    end
    dibs.MultiLedger.GetActiveLedgerId = function(dbOverride)
      activeLedgerDB = dbOverride
      return originalGetActiveLedgerId(dbOverride)
    end
    dibs.MultiLedger.GetViewLedgerId = function(dbOverride)
      viewLedgerDB = dbOverride
      return originalGetViewLedgerId(dbOverride)
    end
    dibs.AceGUI.SetShellStatus = function(shell, text)
      local ok, db = originalSetShellStatus(shell, text)
      return ok, db or dibs.GetDB()
    end

    frame:ActivateRoute("preDibRequests")

    dibs.MultiLedger.GetLedgers = originalGetLedgers
    dibs.MultiLedger.GetActiveLedgerId = originalGetActiveLedgerId
    dibs.MultiLedger.GetViewLedgerId = originalGetViewLedgerId
    dibs.AceGUI.SetShellStatus = originalSetShellStatus
    assert_equal(1, reads, "the ledger selector should read its metadata once")
    assert_equal(0, transactionCountReads, "a view selector must not count unrelated ledger transactions")
    assert_not_nil(selectorDB, "the route should reuse the database resolved for its shell status")
    assert_equal(selectorDB, activeLedgerDB, "active-ledger lookup should reuse the selector database")
    assert_equal(selectorDB, viewLedgerDB, "view-ledger lookup should reuse the selector database")
  end)
end)
