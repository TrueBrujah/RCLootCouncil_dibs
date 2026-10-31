local loader = require("helpers.load_addon")
local fixtures = require("helpers.dispute_fixtures")

-- Dispute center integrity suite.
--
-- The audit brief asks for the dispute paths to be covered: creation,
-- unauthorized player, duplicate, historical, missing or ambiguous origin
-- transaction, wrong ledger, wrong guild, rejected, approved, replayed
-- decision, coordinator change, interruption between canonical acceptance and
-- reconstruction, out-of-order receipt, contradictory commit, disconnected
-- client, restore then dispute, Secondary Ledger, local mutation attempt,
-- and permission-bypass attempt.
--
-- The invariants:
--   * the transactions stay immutable;
--   * the stable identifiers stay stable;
--   * the operation stays idempotent;
--   * the association with the ledger of origin is preserved;
--   * the multi-leg commits stay logically atomic;
--   * no dangerous compensation is reintroduced;
--   * neither SyncV2 nor ProtectedActions is bypassed.
--
-- The dispute center is a **local context** module: every read and every
-- write is scoped to the local character or to a locally verified officer.
-- A remote actor is refused rather than served.

local function setup(options)
  options = options or {}
  local _, dibs = loader.load({ withAce3 = true, savedVariables = options.savedVariables or {}, wow = {
    playerName = options.playerName or "Tester-Realm",
    guildLeader = options.guildLeader ~= false,
    guildMembers = { "Tester-Realm", "Officer-Realm", "Player-Realm" },
    guildRankIndices = { [1] = options.rank or 0, [2] = 1, [3] = 3 },
  } })
  return dibs
end

local function seasonOf(dibs)
  return dibs.GetCurrentSeasonId()
end

-- A committed transaction the dispute can reference.
local function seedTransaction(dibs, options)
  options = options or {}
  local playerName = options.playerName or "Tester-Realm"
  local seasonId = seasonOf(dibs)
  local row = fixtures.transaction(playerName, seasonId, {
    transactionId = options.transactionId or ("rf-dispute-tx-" .. tostring(playerName)),
    amount = options.amount or 1,
    type = options.type or "DIB_GRANTED",
    actionType = options.type or "DIB_GRANTED",
  })
  return dibs.Ledger.AddTransaction(row, options.ledgerId or "guild-primary")
end

describe("Dispute center integrity", function()
  it("B01 creates a report for the local player", function()
    local dibs = setup()
    local request, reason = dibs.Disputes.CreateReport(fixtures.report("other"))
    assert_not_nil(request, tostring(reason))
    assert_not_nil(request.requestId)
    assert_equal("Open", request.status)
  end)

  it("B02 refuses a report for another player", function()
    local dibs = setup()
    local request, reason = dibs.Disputes.CreateReport(fixtures.report("other", { playerName = "Player-Realm" }))
    assert_nil(request, "a report for another player was created")
    assert_equal("PLAYER_SCOPE_REQUIRED", reason)
  end)

  it("B03 refuses the evidence of another player", function()
    local dibs = setup()
    local other = seedTransaction(dibs, { playerName = "Player-Realm", transactionId = "rf-dispute-other" })
    assert_not_nil(other)
    local request, reason = dibs.Disputes.CreateReport({ category = "wrong_debit", transactionRef = other.transactionId })
    assert_nil(request, "a report on another player's evidence was created")
    assert_equal("PLAYER_SCOPE_REQUIRED", reason)
  end)

  it("B04 deduplicates an active report", function()
    local dibs = setup()
    local first = assert(dibs.Disputes.CreateReport(fixtures.report("duplicate")))
    local second, reason, duplicate = dibs.Disputes.CreateReport(fixtures.report("duplicate"))
    assert_not_nil(second, tostring(reason))
    assert_equal(first.requestId, second.requestId, "the duplicate created a second request")
    assert_equal("DUPLICATE_ACTIVE", reason)
    assert_true(duplicate)
  end)

  it("B05 refuses a resolution by a plain member", function()
    local dibs = setup({ playerName = "Player-Realm", rank = 3 })
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("other")))
    local result, reason = dibs.Disputes.Resolve(request.requestId, "no_correction",
      { reason = "done", actor = "Player-Realm" }, "Player-Realm")
    assert_nil(result, "a plain member resolved a dispute")
    assert_equal("GUILD_ADMIN_REQUIRED", reason)
  end)

  it("B06 refuses a resolution without a reason", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("other")))
    local result, reason = dibs.Disputes.Resolve(request.requestId, "close", { actor = "Tester-Realm" }, "Tester-Realm")
    assert_nil(result, "a resolution without a reason was accepted")
    assert_equal("REASON_REQUIRED", reason)
  end)

  it("B07 refuses a resolution on a conflicting revision", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("other")))
    local result, reason = dibs.Disputes.Resolve(request.requestId, "close",
      { reason = "done", expectedRevision = 999, actor = "Tester-Realm" }, "Tester-Realm")
    assert_nil(result, "a resolution on a conflicting revision was accepted")
    assert_equal("REQUEST_REVISION_CONFLICT", reason)
  end)

  it("B08 refuses a correction without a confirmation", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("missing_debit")))
    local result, reason = dibs.Disputes.CorrectBalance(request.requestId,
      { amount = 1, reason = "correction", actor = "Tester-Realm" }, "Tester-Realm")
    assert_nil(result, "a correction without a confirmation was accepted")
    assert_equal("CONFIRMATION_REQUIRED", reason)
  end)

  it("B09 refuses a correction without a reason", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("missing_debit")))
    local result, reason = dibs.Disputes.CorrectBalance(request.requestId,
      { amount = 1, confirmed = true, actor = "Tester-Realm" }, "Tester-Realm")
    assert_nil(result, "a correction without a reason was accepted")
    assert_equal("REASON_REQUIRED", reason)
  end)

  it("B10 refuses a correction whose original transaction is missing", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("wrong_debit")))
    local result, reason = dibs.Disputes.CorrectBalance(request.requestId,
      { amount = 1, confirmed = true, reason = "correction", actor = "Tester-Realm" }, "Tester-Realm")
    assert_nil(result, "a correction without an original transaction was accepted")
    assert_equal("ORIGINAL_TRANSACTION_REQUIRED", reason)
  end)

  it("B11 keeps the transaction history immutable when a dispute opens", function()
    local dibs = setup()
    seedTransaction(dibs, { transactionId = "rf-dispute-immutable" })
    local before = #dibs.Ledger.GetAllTransactions()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("wrong_debit", { transactionRef = "rf-dispute-immutable" })))
    assert_not_nil(request)
    local after = dibs.Ledger.GetAllTransactions()
    assert_equal(before, #after, "the transaction count changed when a dispute was opened")
    for _, row in pairs(after) do
      assert_not_nil(row.transactionId, "a transaction lost its identifier")
    end
  end)

  it("B12 returns the safe view to the owner", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("other")))
    local visible, reason = dibs.Disputes.GetRequest(request.requestId, "Tester-Realm")
    assert_not_nil(visible, tostring(reason))
    assert_equal(request.requestId, visible.requestId)
    assert_nil(visible.guildScope, "the safe view exposed the guild scope")
  end)

  it("B13 does not expose a request to a remote player", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("other")))
    local visible, reason = dibs.Disputes.GetRequest(request.requestId, "Player-Realm")
    assert_nil(visible, "a request was exposed to a remote player")
    assert_equal("REQUEST_NOT_FOUND", reason)
  end)

  it("B14 lists the requests of the local player only", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("other")))
    local list, reason = dibs.Disputes.ListForPlayer("Tester-Realm")
    assert_not_nil(list, tostring(reason))
    local found = false
    for _, entry in ipairs(list) do
      if entry.requestId == request.requestId then found = true end
    end
    assert_true(found, "the owner did not see their own request")
  end)

  it("B15 refuses the player list for a remote actor", function()
    local dibs = setup()
    local list, reason = dibs.Disputes.ListForPlayer("Player-Realm")
    assert_equal(0, #list, "a remote actor received the player list")
    assert_equal("PLAYER_SCOPE_REQUIRED", reason)
  end)

  it("B16 refuses the officer list for a plain member", function()
    local dibs = setup({ playerName = "Player-Realm", rank = 3 })
    local list, reason = dibs.Disputes.ListForOfficer("Player-Realm")
    assert_equal(0, #list, "a plain member received the officer list")
    assert_equal("GUILD_ADMIN_REQUIRED", reason)
  end)

  it("B17 lists the requests for a verified officer", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("other")))
    local list, reason = dibs.Disputes.ListForOfficer("Tester-Realm")
    assert_not_nil(list, tostring(reason))
    local found = false
    for _, entry in ipairs(list) do
      if entry.requestId == request.requestId then found = true end
    end
    assert_true(found, "the officer did not see the request")
  end)

  it("B18 isolates the requests of another guild", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("other")))
    dibs.GetGuildKey = function() return "guild:other" end
    local visible, reason = dibs.Disputes.GetRequest(request.requestId, "Tester-Realm")
    assert_nil(visible, "a request was exposed across a guild boundary")
    assert_equal("REQUEST_NOT_FOUND", reason)
  end)

  it("B19 rejects a second terminal decision", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("other")))
    local first = dibs.Disputes.NoCorrection(request.requestId, "No accounting change", "Tester-Realm")
    assert_not_nil(first)
    local before = #dibs.Disputes.GetTimeline(request.requestId, "Tester-Realm")
    local second, reason = dibs.Disputes.NoCorrection(request.requestId, "Repeat", "Tester-Realm")
    assert_nil(second, "a second terminal decision was accepted")
    assert_equal("REQUEST_ALREADY_RESOLVED", reason)
    assert_equal(before, #dibs.Disputes.GetTimeline(request.requestId, "Tester-Realm"),
      "the refused decision appended a timeline event")
  end)

  it("B20 keeps the timeline append-only", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("other")))
    local first = dibs.Disputes.GetTimeline(request.requestId, "Tester-Realm")
    assert_true(#first >= 1)
    local firstId = first[1].eventId
    dibs.Disputes.BeginReview(request.requestId, "Tester-Realm")
    dibs.Disputes.NoCorrection(request.requestId, "Confirmed", "Tester-Realm")
    local timeline = dibs.Disputes.GetTimeline(request.requestId, "Tester-Realm")
    assert_true(#timeline >= 3)
    assert_equal(firstId, timeline[1].eventId, "the first timeline event was rewritten")
  end)

  it("B21 keeps the safe view free of the internal details", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("other")))
    local view = dibs.Disputes.BuildSafeView(request)
    assert_not_nil(view)
    assert_nil(view.auditLog, "the safe view exposed the audit log")
    assert_nil(view.player, "the safe view exposed the player identity")
    assert_nil(view.deliveryAuthority, "the safe view exposed the delivery authority")
  end)

  it("B22 keeps the safe view free of the officer-only timeline details", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("other")))
    dibs.Disputes.BeginReview(request.requestId, "Tester-Realm")
    local officer = dibs.Disputes.BuildOfficerView(request)
    assert_not_nil(officer)
    assert_true(officer.officerOnly, "the officer view is not marked as officer-only")
    local safe = dibs.Disputes.BuildSafeView(request)
    assert_nil(safe.timeline, "the safe view exposed the raw timeline")
  end)

  it("B23 supports an information request and the owner reply", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("other")))
    local asked = dibs.Disputes.AskForInformation(request.requestId, "Which raid was this?", "Tester-Realm")
    assert_not_nil(asked)
    assert_equal("Need information", asked.request.status)
    local reply = dibs.Disputes.AddReply(request.requestId, "Wednesday raid", "Tester-Realm")
    assert_not_nil(reply)
    assert_equal("Open", dibs.Disputes.GetRequest(request.requestId, "Tester-Realm").status)
  end)

  it("B24 refuses a player reply that was not requested", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("other")))
    local reply, reason = dibs.Disputes.AddReply(request.requestId, "An answer", "Tester-Realm")
    assert_nil(reply, "a reply was accepted without an information request")
    assert_equal("REPLY_NOT_REQUESTED", reason)
  end)

  it("B25 keeps the dispute across a SavedVariables reload", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("other", { note = "Keep this note" })))
    local reloaded = setup({ savedVariables = dibs.GetDB() })
    local restored = reloaded.Disputes.GetRequest(request.requestId, "Tester-Realm")
    assert_not_nil(restored)
    assert_equal("Keep this note", restored.note)
    assert_equal("Open", restored.status)
  end)

  it("B26 refuses a submission whose author is not the sender", function()
    local dibs = setup()
    -- The payload declares the local character, but the message came from
    -- another member. A peer must never be able to file a request in the
    -- name of somebody else.
    local applied, reason = dibs.Disputes.ReceiveSubmission({
      requestId = "rf-dispute-sub-1", playerName = "Tester-Realm", category = "other",
    }, "Player-Realm", { memberKey = "member-key", epoch = 1 })
    assert_nil(applied, "a submission with a wrong author was accepted")
    assert_equal("PLAYER_SCOPE_REQUIRED", reason)
  end)

  it("B27 refuses a reply for an unknown request", function()
    local dibs = setup()
    local applied, reason = dibs.Disputes.ReceiveReply("request-does-not-exist",
      { text = "x" }, "reply-1", "Tester-Realm", 0)
    assert_nil(applied, "a reply for an unknown request was accepted")
    assert_equal("PLAYER_SCOPE_REQUIRED", reason)
  end)

  it("B28 refuses a correction while the release lock is closed", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("missing_debit")))
    local before = #dibs.Ledger.GetAllTransactions()
    local result, reason = dibs.Disputes.CorrectBalance(request.requestId,
      { confirmed = true, reason = "Confirmed missing award", actor = "Tester-Realm" }, "Tester-Realm")
    assert_nil(result, "a correction was accepted while the release lock is closed")
    assert_equal("FEATURE_DISABLED", reason)
    assert_equal(before, #dibs.Ledger.GetAllTransactions(),
      "the refused correction changed the accounting data")
    assert_equal("Open", dibs.Disputes.GetRequest(request.requestId, "Tester-Realm").status)
  end)

  it("B29 refuses a review by a remote actor", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("other")))
    local result, reason = dibs.Disputes.BeginReview(request.requestId, "Player-Realm")
    assert_nil(result, "a remote actor started a review")
    assert_equal("GUILD_ADMIN_REQUIRED", reason)
  end)

  it("B30 refuses a follow-up assigned to a non-officer", function()
    local dibs = setup()
    local request = assert(dibs.Disputes.CreateReport(fixtures.report("other")))
    local result, reason = dibs.Disputes.UpdateFollowUp(request.requestId,
      { assignedTo = "Player-Realm", actor = "Tester-Realm" }, "Tester-Realm")
    assert_nil(result, "a follow-up was assigned to a non-officer")
    assert_equal("VERIFIED_OFFICER_REQUIRED", reason)
  end)
end)
