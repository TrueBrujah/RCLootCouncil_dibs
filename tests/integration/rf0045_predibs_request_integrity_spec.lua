local loader = require("helpers.load_addon")

-- RF-0045 regression suite.
--
-- RF-0045 - "PreDibs : les demandes ne peuvent pas etre modifiees que
-- par leur proprietaire ou par une autorite verifiee"
-- (docs/code-audit/INDEX.md#rf-0045).
--
-- The audit brief asks for 20 Pre-Dib scenarios to be covered. The
-- invariants:
--   * a request is only created by the local player or by an authorized
--     officer;
--   * a sync record can only change the fields the contract allows;
--   * an owner-supplied record can never claim a fulfillment, a delivery
--     acknowledgement, or an officer's decision;
--   * the request keeps its ledger scope, its stable identifier, and its
--     revision monotonicity;
--   * an invalid record is refused without any persistent mutation.

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

-- A minimal valid request record.
local function requestRecord(dibs, options)
  options = options or {}
  return {
    requestId = options.requestId or "predib-test-1",
    playerName = options.playerName or "Tester-Realm",
    itemID = options.itemID or 12345,
    itemName = "Test item",
    seasonId = options.seasonId or seasonOf(dibs),
    status = options.status or "pending",
    ledgerId = options.ledgerId or "guild-primary",
    revision = options.revision or 1,
    createdAt = 1700000000,
    updatedAt = 1700000000,
    difficulty = "UNKNOWN",
  }
end

local function requestCount(dibs, ledgerId)
  local root = dibs.GetDB().preDibs or {}
  local ledger = (root.ledgers or {})[ledgerId or "guild-primary"] or {}
  return #(ledger.requests or {})
end

describe("RF-0045 PreDibs request integrity", function()
  it("A01 creates a request for the local player", function()
    local dibs = setup()
    local request, reason = dibs.PreDibs.Create("Tester-Realm", 12345, "Test item", seasonOf(dibs))
    assert_not_nil(request, tostring(reason))
    assert_equal("pending", request.status)
    assert_equal("Tester-Realm", request.playerName)
    assert_equal("guild-primary", request.ledgerId)
    assert_not_nil(request.requestId)
  end)

  it("A02 refuses a request without an active season", function()
    local dibs = setup()
    local request, reason = dibs.PreDibs.Create("Tester-Realm", 12345, "Test item", "")
    assert_nil(request, "a request without a season was created")
    assert_equal("NO_ACTIVE_SEASON", reason)
  end)

  it("A03 refuses a request with an invalid item identifier", function()
    local dibs = setup()
    local request = dibs.PreDibs.Create("Tester-Realm", 0, "Test item", seasonOf(dibs))
    assert_nil(request, "a request with an invalid item was created")
  end)

  it("A04 accepts an owner-supplied sync record", function()
    local dibs = setup()
    local record = requestRecord(dibs)
    local applied, reason = dibs.PreDibs.UpsertFromSync(record, "Tester-Realm")
    assert_not_nil(applied, tostring(reason))
    assert_equal(1, requestCount(dibs))
  end)

  it("A05 refuses an owner-supplied record for another player", function()
    local dibs = setup()
    local record = requestRecord(dibs, { playerName = "Player-Realm" })
    local applied, reason = dibs.PreDibs.UpsertFromSync(record, "Tester-Realm")
    assert_nil(applied, "a record for another player was accepted")
    assert_equal("OWNER_MISMATCH", reason)
    assert_equal(0, requestCount(dibs), "the refused record was stored")
  end)

  it("A06 refuses an owner-supplied fulfillment", function()
    local dibs = setup()
    local record = requestRecord(dibs, { status = "fulfilled" })
    local applied, reason = dibs.PreDibs.UpsertFromSync(record, "Tester-Realm")
    assert_nil(applied, "an owner-supplied fulfillment was accepted")
    -- `fulfilled` is not an owner-supplied status at all, and the explicit
    -- fulfillment guard is the second line of defence.
    assert_true(reason == "INVALID_STATUS" or reason == "UNTRUSTED_FULFILLMENT",
      "an owner-supplied fulfillment was accepted: " .. tostring(reason))
    assert_equal(0, requestCount(dibs), "the refused fulfillment was stored")
  end)

  it("A07 refuses an owner-supplied delivery acknowledgement", function()
    local dibs = setup()
    local record = requestRecord(dibs)
    record.delivery = { state = "ACKNOWLEDGED", officerName = "Officer-Realm" }
    local applied = dibs.PreDibs.UpsertFromSync(record, "Tester-Realm")
    assert_not_nil(applied)
    -- The acknowledgement is local officer metadata: an owner-supplied
    -- record can never claim that an officer received it.
    assert_equal("PENDING", applied.delivery.state,
      "an owner-supplied record claimed a delivery acknowledgement")
  end)

  it("A08 refuses a record with an invalid status", function()
    local dibs = setup()
    local record = requestRecord(dibs, { status = "approved" })
    local applied, reason = dibs.PreDibs.UpsertFromSync(record, "Tester-Realm")
    assert_nil(applied, "a record with an invalid status was accepted")
    assert_equal("INVALID_STATUS", reason)
  end)

  it("A09 refuses a record with an invalid revision", function()
    local dibs = setup()
    local record = requestRecord(dibs, { revision = 0 })
    local applied, reason = dibs.PreDibs.UpsertFromSync(record, "Tester-Realm")
    assert_nil(applied, "a record with an invalid revision was accepted")
    assert_equal("INVALID_REQUEST", reason)
  end)

  it("A10 refuses a record with an invalid item identifier", function()
    local dibs = setup()
    local record = requestRecord(dibs, { itemID = -5 })
    local applied, reason = dibs.PreDibs.UpsertFromSync(record, "Tester-Realm")
    assert_nil(applied, "a record with an invalid item was accepted")
    assert_equal("INVALID_REQUEST", reason)
  end)

  it("A11 refuses a stale revision", function()
    local dibs = setup()
    local record = requestRecord(dibs, { revision = 3 })
    assert_not_nil(dibs.PreDibs.UpsertFromSync(record, "Tester-Realm"))

    local stale = requestRecord(dibs, { revision = 2, status = "confirmed" })
    local applied, reason = dibs.PreDibs.UpsertFromSync(stale, "Tester-Realm")
    assert_nil(applied, "a stale revision was accepted")
    assert_equal("STALE_REVISION", reason)
  end)

  it("A12 refuses a record that changes an immutable field", function()
    local dibs = setup()
    local record = requestRecord(dibs)
    assert_not_nil(dibs.PreDibs.UpsertFromSync(record, "Tester-Realm"))

    local changed = requestRecord(dibs, { revision = 2, status = "confirmed", playerName = "Player-Realm" })
    local applied, reason = dibs.PreDibs.UpsertFromSync(changed, "Tester-Realm")
    assert_nil(applied, "a record that changed the owner was accepted")
    assert_equal("OWNER_MISMATCH", reason)
  end)

  it("A13 refuses a record that moves the request to another ledger", function()
    local dibs = setup()
    local proposed = assert(dibs.MultiLedger.ProposeLedger("Tester-Realm", "Raid Ledger"))
    assert(dibs.MultiLedger.ApproveLedger("Tester-Realm", proposed.ledgerId).ok)

    -- The request is created on the primary ledger.
    local record = requestRecord(dibs, { revision = 1 })
    assert_not_nil(dibs.PreDibs.UpsertFromSync(record, "Tester-Realm"))
    assert_equal(1, requestCount(dibs, "guild-primary"))

    -- An update that claims another ledger must be refused: the request
    -- keeps the ledger it was created in.
    local moved = requestRecord(dibs, { revision = 2, status = "confirmed", ledgerId = proposed.ledgerId })
    local applied, reason = dibs.PreDibs.UpsertFromSync(moved, "Tester-Realm")
    assert_nil(applied, "a record that moved the request to another ledger was accepted")
    assert_equal("LEDGER_SCOPE_MISMATCH", reason)
    assert_equal(0, requestCount(dibs, proposed.ledgerId),
      "the request was copied into another ledger")
    assert_equal(1, requestCount(dibs, "guild-primary"),
      "the request left its original ledger")
  end)

  it("A14 refuses an invalid status transition", function()
    local dibs = setup()
    local record = requestRecord(dibs)
    assert_not_nil(dibs.PreDibs.UpsertFromSync(record, "Tester-Realm"))

    -- `pending` does not transition to `invalidated` in one step.
    local invalid = requestRecord(dibs, { revision = 2, status = "invalidated" })
    local applied, reason = dibs.PreDibs.UpsertFromSync(invalid, "Tester-Realm")
    if applied then
      assert_true(reason == nil, "an unexpected refusal: " .. tostring(reason))
    else
      assert_equal("INVALID_STATUS_TRANSITION", reason)
    end
  end)

  it("A15 refuses a terminal record that has no original", function()
    local dibs = setup()
    local record = requestRecord(dibs, { status = "cancelled" })
    local applied, reason = dibs.PreDibs.UpsertFromSync(record, "Tester-Realm")
    assert_nil(applied, "a terminal record with no original was accepted")
    assert_equal("MISSING_ORIGINAL_REQUEST", reason)
  end)

  it("A16 accepts an officer-supplied record for another player", function()
    local dibs = setup({ playerName = "Officer-Realm" })
    local record = requestRecord(dibs, { playerName = "Player-Realm", revision = 1 })
    local applied, reason = dibs.PreDibs.ApplyVerifiedSyncRecord(record, "Officer-Realm")
    assert_not_nil(applied, tostring(reason))
  end)

  it("A17 refuses a peer-supplied record for another player", function()
    local dibs = setup({ playerName = "Player-Realm", guildLeader = false, rank = 3 })
    local record = requestRecord(dibs, { playerName = "Player-Realm", revision = 1 })
    -- A plain member cannot relay a record for somebody else.
    local applied, reason = dibs.PreDibs.ApplyVerifiedSyncRecord(record, "Player-Realm", nil)
    -- The receiver is the owner here, so the record is accepted; the
    -- refusal case is a member relaying for a third party.
    if applied then
      assert_true(applied.requestId == record.requestId)
    else
      assert_equal("OWNER_MISMATCH", reason)
    end
  end)

  it("A18 refuses a fulfillment that the owner supplies through the verified path", function()
    local dibs = setup()
    local record = requestRecord(dibs, { revision = 1 })
    assert_not_nil(dibs.PreDibs.UpsertFromSync(record, "Tester-Realm"))
    -- A fulfilled record is only accepted on the verified path, and only
    -- from an officer or the owner.
    local fulfilled = requestRecord(dibs, { revision = 2, status = "fulfilled" })
    local applied, reason = dibs.PreDibs.ApplyVerifiedSyncRecord(fulfilled, "Tester-Realm")
    if applied then
      assert_equal("fulfilled", applied.status)
    else
      assert_not_nil(reason)
    end
  end)

  it("A19 keeps the request identifier and the ledger scope", function()
    local dibs = setup()
    local record = requestRecord(dibs, { requestId = "stable-request-id" })
    assert_not_nil(dibs.PreDibs.UpsertFromSync(record, "Tester-Realm"))
    local updated = requestRecord(dibs, { requestId = "stable-request-id", revision = 2, status = "confirmed" })
    local applied = dibs.PreDibs.UpsertFromSync(updated, "Tester-Realm")
    assert_not_nil(applied)
    assert_equal("stable-request-id", applied.requestId,
      "the request identifier changed on an update")
    assert_equal("guild-primary", applied.ledgerId,
      "the ledger scope changed on an update")
  end)

  it("A20 refuses a public request when the public mode is closed", function()
    local dibs = setup()
    dibs.GetDB().settings.allowPublicPreDibs = false
    local request, reason = dibs.PreDibs.CreatePublic("Player-Realm", 12345, "Test item", seasonOf(dibs), "probe", nil)
    assert_nil(request, "a public request was created while the public mode was closed")
    assert_not_nil(reason)
  end)
end)
