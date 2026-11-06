local loader = require("helpers.load_addon")
local fixtures = require("helpers.dispute_fixtures")

describe("Dispute center", function()
  local function setup(wow)
    local _, dibs = loader.load({ wow = wow or { guildLeader = true }, withAce3 = true })
    local season = dibs.Seasons.GetCurrent()
    return dibs, season
  end

  it("creates an own-context report without changing the ledger", function()
    local dibs, season = setup({ guildLeader = true })
    local tx = fixtures.transaction("Tester-Realm", season.id)
    local stored = dibs.Ledger.AddTransaction(tx)
    assert_equal("Tester-Realm", dibs.GetPlayerName())
    assert_equal("tester-realm", dibs.Permissions.CanonicalPlayerId("Tester-Realm"))
    assert_equal("Player-1-TESTER", dibs.Permissions.CanonicalPlayerId(nil))
    assert_equal("Tester-Realm", stored.playerName)
    assert_equal("tester-realm", dibs.Permissions.CanonicalPlayerId(stored.playerName))
    local all = dibs.Ledger.GetAllTransactions()
    assert_equal(2, #all)
    local foundStored = false
    for _, value in ipairs(all) do if value.transactionId == stored.transactionId then foundStored = true end end
    assert_true(foundStored)
    local normalizedDirect, normalizedDirectReason = dibs.Disputes.NormalizeEvidence({ transaction = stored }, "Tester-Realm")
    assert_not_nil(normalizedDirect, tostring(normalizedDirectReason))
    local normalized, normalizedReason = dibs.Disputes.NormalizeEvidence({ transactionRef = stored.transactionId }, "Tester-Realm")
    assert_not_nil(normalized, tostring(normalizedReason))
    local before = #dibs.Ledger.GetHistory("Tester-Realm", season.id)
    local request, reportReason = dibs.Disputes.CreateReport({ category = "wrong debit", transactionRef = stored.transactionId })
    assert_not_nil(request, tostring(reportReason))
    assert_equal("wrong_debit", request.category)
    assert_equal("Open", request.status)
    assert_equal(stored.transactionId, request.evidence[1].transactionRef)
    assert_equal(before, #dibs.Ledger.GetHistory("Tester-Realm", season.id))
  end)

  it("deduplicates an active report and rejects another player's evidence", function()
    local dibs, season = setup({ guildLeader = true, guildMembers = { "Tester-Realm", "Other-Realm" } })
    local tx = dibs.Ledger.AddTransaction(fixtures.transaction("Tester-Realm", season.id, { transactionId = "tx-own" }))
    local first = dibs.Disputes.CreateReport({ category = "duplicate", transactionRef = tx.transactionId })
    local second, reason, duplicate = dibs.Disputes.CreateReport({ category = "duplicate", transactionRef = tx.transactionId })
    assert_equal(first.requestId, second.requestId)
    assert_equal("DUPLICATE_ACTIVE", reason)
    assert_true(duplicate)
    dibs.Ledger.Grant("Other-Realm", 1, "Test allocation", "test", season.id)
    local other = dibs.Ledger.AddTransaction(fixtures.transaction("Other-Realm", season.id, { transactionId = "tx-other", awardRef = "history:other-award" }))
    assert_equal("Other-Realm", other.playerName)
    assert_equal("other-realm", dibs.Permissions.CanonicalPlayerId(other.playerName))
    local rejected, rejectReason = dibs.Disputes.CreateReport({ category = "wrong debit", transactionRef = other.transactionId })
    assert_nil(rejected)
    assert_equal("PLAYER_SCOPE_REQUIRED", rejectReason)
  end)

  it("supports information requests and a bounded owner reply", function()
    local dibs = setup({ guildLeader = true })
    local fixturePayload = fixtures.report("integration")
    local evidence, evidenceReason = dibs.Disputes.NormalizeEvidence(fixturePayload, "Tester-Realm")
    assert_not_nil(evidence, tostring(evidenceReason))
    local request, requestReason = dibs.Disputes.CreateReport(fixturePayload)
    assert_not_nil(request, tostring(requestReason))
    local asked = dibs.Disputes.AskForInformation(request.requestId, "Which raid was this?", "Tester-Realm")
    assert_true(asked.ok)
    assert_equal("Need information", asked.request.status)
    local reply = dibs.Disputes.AddReply(request.requestId, "Wednesday raid", "Tester-Realm")
    assert_not_nil(reply)
    assert_equal("Open", dibs.Disputes.GetRequest(request.requestId, "Tester-Realm").status)
  end)

  it("corrects a missing debit through one linked append-only transaction", function()
    local dibs = setup({ guildLeader = true })
    local request, requestReason = dibs.Disputes.CreateReport(fixtures.report("missing debit"))
    assert_not_nil(request, tostring(requestReason))
    local before = #dibs.Ledger.GetHistory("Tester-Realm")
    local result, reason = dibs.Disputes.CorrectBalance(request.requestId, { confirmed = true, reason = "Confirmed missing award" }, "Other-Realm")
    assert_true(result == nil)
    assert_equal("GUILD_ADMIN_REQUIRED", reason)
    local officerResult = dibs.Disputes.CorrectBalance(request.requestId, { confirmed = true, reason = "Confirmed missing award" }, nil)
    assert_true(officerResult.ok)
    assert_true(officerResult.changedBalance)
    assert_equal("Resolved", officerResult.request.status)
    assert_equal(request.requestId, officerResult.transaction.reviewRequestId)
    assert_equal(before + 1, #dibs.Ledger.GetHistory("Tester-Realm"))
    local replay, replayReason = dibs.Disputes.CorrectBalance(request.requestId, { confirmed = true, reason = "Confirmed missing award" }, nil)
    assert_nil(replay)
    assert_equal("REQUEST_ALREADY_RESOLVED", replayReason)
    assert_equal(before + 1, #dibs.Ledger.GetHistory("Tester-Realm"))
  end)

  it("keeps the Officer queue private and exposes only safe owner views", function()
    local dibs = setup({ guildLeader = true })
    local request, requestReason = dibs.Disputes.CreateReport(fixtures.report("other", { note = "Player supplied note" }))
    assert_not_nil(request, tostring(requestReason))
    assert_equal("tester-realm", request.player.id)
    assert_equal("tester-realm", dibs.Permissions.CanonicalPlayerId(request.player.id))
    local queue = dibs.Disputes.ListForOfficer(nil)
    assert_equal(1, #queue)
    local safe = dibs.Disputes.GetRequest(request.requestId, "Tester-Realm")
    assert_equal(request.requestId, safe.requestId)
    assert_nil(safe.guildScope)
    local unauthorized = dibs.Disputes.ListForOfficer("Other-Realm")
    assert_equal(0, #unauthorized)
    assert_equal("GUILD_ADMIN_REQUIRED", select(2, dibs.Disputes.ListForOfficer("Other-Realm")))
  end)

  it("keeps empty-query Officer queues complete and searches details when requested", function()
    local dibs = setup({ guildLeader = true })
    local request = dibs.Disputes.CreateReport(fixtures.report("other", { note = "Needle in the audit note" }))
    assert_not_nil(request)

    local unfiltered = dibs.Disputes.ListForOfficer(nil, { query = "" })
    assert_equal(1, #unfiltered)
    assert_equal(request.requestId, unfiltered[1].requestId)

    local matching = dibs.Disputes.ListForOfficer(nil, { query = "needle in the audit note" })
    assert_equal(1, #matching)
    assert_equal(request.requestId, matching[1].requestId)

    local missing = dibs.Disputes.ListForOfficer(nil, { query = "not present" })
    assert_equal(0, #missing)
  end)

  it("paginates Officer review requests before copying full dossiers", function()
    local dibs = setup({ guildLeader = true })
    local categories = { "other", "eligibility", "duplicate" }
    for index, category in ipairs(categories) do
      local request = dibs.Disputes.CreateReport(fixtures.report(category, {
        note = "Paginated report " .. tostring(index),
      }))
      assert_not_nil(request)
    end
    local complete = dibs.Disputes.ListForOfficer(nil)
    assert_equal(3, #complete)

    local originalBuildOfficerView = dibs.Disputes.BuildOfficerView
    local dossierCopies = 0
    dibs.Disputes.BuildOfficerView = function(request)
      dossierCopies = dossierCopies + 1
      return originalBuildOfficerView(request)
    end
    local firstPage, firstReason, firstTotal, firstPageNumber = dibs.Disputes.ListForOfficer(nil, {
      page = 1, pageSize = 2,
    })
    local lastPage, lastReason, lastTotal, lastPageNumber = dibs.Disputes.ListForOfficer(nil, {
      page = 2, pageSize = 2,
    })
    local outOfRange, rangeReason, rangeTotal, clampedPage = dibs.Disputes.ListForOfficer(nil, {
      page = 99, pageSize = 2,
    })
    dibs.Disputes.BuildOfficerView = originalBuildOfficerView

    assert_nil(firstReason)
    assert_nil(lastReason)
    assert_nil(rangeReason)
    assert_equal(3, firstTotal)
    assert_equal(3, lastTotal)
    assert_equal(3, rangeTotal)
    assert_equal(1, firstPageNumber)
    assert_equal(2, lastPageNumber)
    assert_equal(2, clampedPage)
    assert_equal(2, #firstPage)
    assert_equal(1, #lastPage)
    assert_equal(1, #outOfRange)
    assert_equal(4, dossierCopies, "only visible dossiers should be copied for paginated reads")
    assert_equal(complete[1].requestId, firstPage[1].requestId)
    assert_equal(complete[2].requestId, firstPage[2].requestId)
    assert_equal(complete[3].requestId, lastPage[1].requestId)
    assert_equal(complete[3].requestId, outOfRange[1].requestId)
    assert_equal(#complete[1].timeline, #firstPage[1].timeline)
  end)

  it("reuses the resolved database for the request module gate and owner list", function()
    local dibs = setup({ guildLeader = true })
    local originalGetDB, databaseReads = dibs.GetDB, 0
    dibs.GetDB = function()
      databaseReads = databaseReads + 1
      return originalGetDB()
    end

    local requests, reason = dibs.Disputes.ListForPlayer(nil)

    dibs.GetDB = originalGetDB
    assert_nil(reason)
    assert_equal(0, #requests)
    assert_equal(1, databaseReads, "policy and request lookup should share one database resolution")
  end)

  it("renders the player request page and Officer review queue", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local request = dibs.Disputes.CreateReport(fixtures.report("other"))
    assert_not_nil(request)
    local player = dibs.PlayerUI.CreateWindow()
    assert_true(player ~= nil and player.SelectTab ~= nil)
    player.SelectTab("requests")
    assert_equal("requests", player.playerTab)
    local officer = dibs.OfficerUI.CreateWindow()
    assert_true(officer ~= nil and officer.SelectTab ~= nil)
    officer.SelectTab("disputes")
    assert_equal("disputes", officer.activeTab)
    assert_not_nil(officer.disputeSearchBox)
  end)

  it("keeps Officer queue rendering from rescanning request reminders", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local originalCheckReminders = dibs.RequestDelivery.CheckReminders
    local originalPump = dibs.RequestDelivery.Pump
    local reminderScans, skipReminderScan, requestsModuleEnabled = 0, nil, nil
    dibs.RequestDelivery.CheckReminders = function(...)
      reminderScans = reminderScans + 1
      return originalCheckReminders(...)
    end
    dibs.RequestDelivery.Pump = function(skip, moduleEnabled)
      skipReminderScan, requestsModuleEnabled = skip, moduleEnabled
      return originalPump(skip, moduleEnabled)
    end

    local officer = dibs.OfficerUI.CreateWindow()
    officer.SelectTab("disputes")

    dibs.RequestDelivery.CheckReminders = originalCheckReminders
    dibs.RequestDelivery.Pump = originalPump
    assert_equal(true, skipReminderScan, "queue render should still pump pending delivery without scanning reminders")
    assert_equal(true, requestsModuleEnabled, "successful Officer queue preflight should be reused by the delivery pump")
    assert_equal(0, reminderScans)
  end)

  it("checks Requests module policy only once while rendering the Officer queue", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local officer = dibs.OfficerUI.CreateWindow()
    local originalRequire = dibs.OperationalPolicy.RequireModuleEnabled
    local requestsChecks = 0
    dibs.OperationalPolicy.RequireModuleEnabled = function(moduleId, ...)
      if moduleId == "requests" then requestsChecks = requestsChecks + 1 end
      return originalRequire(moduleId, ...)
    end

    officer.SelectTab("disputes")

    dibs.OperationalPolicy.RequireModuleEnabled = originalRequire
    assert_equal(1, requestsChecks, "ListForOfficer preflight should supply the same-render policy result to Pump")
  end)

  it("does not start delivery when the Officer queue preflight fails", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local officer = dibs.OfficerUI.CreateWindow()
    local originalList, originalPump = dibs.Disputes.ListForOfficer, dibs.RequestDelivery.Pump
    local pumpCalls = 0
    dibs.Disputes.ListForOfficer = function() return {}, "REQUESTS_DISABLED" end
    dibs.RequestDelivery.Pump = function() pumpCalls = pumpCalls + 1 end

    officer.SelectTab("disputes")

    dibs.Disputes.ListForOfficer = originalList
    dibs.RequestDelivery.Pump = originalPump
    assert_equal(0, pumpCalls, "a failed queue preflight must not use the optimized delivery path")
  end)

  it("records the distinct synchronous work in the Officer review queue", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local originalDebugProfileStop = _G.debugprofilestop
    local profileTicks = 0
    _G.debugprofilestop = function()
      profileTicks = profileTicks + 1
      return profileTicks
    end
    dibs.UIRenderStats.Reset()
    dibs.UIRenderStats.SetEnabled(true)
    local officer = dibs.OfficerUI.CreateWindow()
    officer.SelectTab("disputes")
    dibs.UIRenderStats.SetEnabled(false)
    _G.debugprofilestop = originalDebugProfileStop

    local measured = {}
    for _, entry in ipairs(dibs.UIRenderStats.GetReport().pages) do
      if entry.kind == "Officer data" then measured[entry.page] = true end
    end
    assert_true(measured["disputes-request-delivery-pump"])
    assert_true(measured["disputes-row-presentation"])
    assert_true(measured["disputes-table-build"])
  end)

  it("corrects a wrong item or player with an auditable target change", function()
    local dibs, season = setup({ guildLeader = true, guildMembers = { "Tester-Realm", "Recipient-Realm" } })
    local original = dibs.Ledger.AddTransaction(fixtures.transaction("Tester-Realm", season.id, {
      transactionId = "tx-target-correction",
      itemID = 19019,
      itemLink = "|Hitem:19019::::::::::::|h[Old Item]|h|r",
    }))
    local oldBalance = dibs.Ledger.GetBalance("Tester-Realm", season.id)
    local newBalance = dibs.Ledger.GetBalance("Recipient-Realm", season.id)
    local request, requestReason = dibs.Disputes.CreateReport({
      category = "wrong_item_player",
      transactionRef = original.transactionId,
      note = "The award was recorded against the wrong player and item.",
    })
    assert_not_nil(request, tostring(requestReason))
    local result, reason = dibs.Disputes.Resolve(request.requestId, "correct_target", {
      confirmed = true,
      reason = "Officer verified the award history.",
      playerName = "Recipient-Realm",
      itemLink = "|Hitem:19020::::::::::::|h[Correct Item]|h|r",
    }, nil)
    assert_true(result and result.ok, tostring(reason))
    assert_true(result.changedBalance)
    assert_equal("Resolved", result.request.status)
    assert_equal("Recipient-Realm", result.request.targetCorrection.correctedPlayer)
    assert_equal(19020, result.request.targetCorrection.correctedItemID)
    assert_equal(oldBalance + 1, dibs.Ledger.GetBalance("Tester-Realm", season.id))
    assert_equal(newBalance - 1, dibs.Ledger.GetBalance("Recipient-Realm", season.id))
    local replay, replayReason = dibs.Disputes.Resolve(request.requestId, "correct_target", {
      confirmed = true,
      reason = "Officer verified the award history.",
      playerName = "Recipient-Realm",
      itemLink = "|Hitem:19020::::::::::::|h[Correct Item]|h|r",
    }, nil)
    assert_nil(replay)
    assert_equal("REQUEST_ALREADY_RESOLVED", replayReason)
  end)

  it("routes advanced corrections through protected ledger actions", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    for _, action in ipairs({ "refund", "revoke", "historical_import", "adjustment" }) do
      local request = dibs.Disputes.CreateReport(fixtures.report("other", { note = action }))
      local result, reason = dibs.Disputes.Resolve(request.requestId, action, { amount = 1, confirmed = true, reason = "Audited " .. action }, nil)
      assert_true(result and result.ok, tostring(action) .. ": " .. tostring(reason))
      assert_true(result.changedBalance)
      assert_equal("Resolved", result.request.status)
    end
  end)

  it("canonicalizes a short player name before an accounting correction", function()
    local dibs, season = setup({ guildLeader = true, guildMembers = { "Tester-Realm", "Huudada-Durotan" } })
    local request = dibs.Disputes.CreateReport({ category = "wrong_debit", note = "short name correction" })
    request.player.name = "Huudada"
    local result, reason = dibs.Disputes.Resolve(request.requestId, "adjustment", {
      amount = 2, confirmed = true, reason = "Canonical identity test",
    }, nil)
    assert_true(result and result.ok, tostring(reason))
    local history = dibs.Ledger.GetHistory("Huudada-Durotan", season.id)
    assert_equal(2, history[#history].amount)
    assert_equal("Huudada-Durotan", history[#history].playerName)
  end)
end)
