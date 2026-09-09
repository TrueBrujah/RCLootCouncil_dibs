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
    local dibs, season = setup({ guildLeader = true })
    local tx = dibs.Ledger.AddTransaction(fixtures.transaction("Tester-Realm", season.id, { transactionId = "tx-own" }))
    local first = dibs.Disputes.CreateReport({ category = "duplicate", transactionRef = tx.transactionId })
    local second, reason, duplicate = dibs.Disputes.CreateReport({ category = "duplicate", transactionRef = tx.transactionId })
    assert_equal(first.requestId, second.requestId)
    assert_equal("DUPLICATE_ACTIVE", reason)
    assert_true(duplicate)
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

  it("corrects a wrong item or player with an auditable target change", function()
    local dibs, season = setup({ guildLeader = true })
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
end)
