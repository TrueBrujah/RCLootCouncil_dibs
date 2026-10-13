local loader = require("helpers.load_addon")

describe("Dibs.IndependentRaid", function()
  local function setup(options)
    options = options or {}
    options.wow = options.wow or {
      playerName = "MasterLooter-Realm",
      guildLeader = false,
      guildMembers = { "MasterLooter-Realm", "Officer-Realm", "RaiderA-Realm", "RaiderB-Realm" },
      guildRankIndices = { [1] = 1, [2] = 1, [3] = 3, [4] = 3 },
    }
    return loader.load(options)
  end

  it("manages independent raid session lifecycle (start, active, conclude)", function()
    local _, dibs = setup()
    assert_false(dibs.IndependentRaid.IsSessionActive())
    assert_nil(dibs.IndependentRaid.GetActiveSession())

    local start = dibs.IndependentRaid.StartSession("Pug Raid Night", 2)
    assert_true(start.ok)
    assert_not_nil(start.sessionId)
    assert_true(dibs.IndependentRaid.IsSessionActive())

    local active = dibs.IndependentRaid.GetActiveSession()
    assert_not_nil(active)
    assert_equal("Pug Raid Night", active.name)
    assert_equal(2, active.startingPoints)
    assert_equal("ACTIVE", active.status)

    -- Cannot start a second session while one is active
    local second = dibs.IndependentRaid.StartSession("Conflict", 1)
    assert_false(second.ok)
    assert_equal("SESSION_ALREADY_ACTIVE", second.reasonCode)

    -- Conclude session
    local conclude = dibs.IndependentRaid.ConcludeSession()
    assert_true(conclude.ok)
    assert_false(dibs.IndependentRaid.IsSessionActive())
    assert_nil(dibs.IndependentRaid.GetActiveSession())

    local past = dibs.IndependentRaid.GetPastSessions()
    assert_equal(1, #past)
    assert_equal("CONCLUDED", past[1].status)
  end)

  it("tracks local ephemeral point balances and prevents overspending", function()
    local _, dibs = setup()
    dibs.IndependentRaid.StartSession("Friday Ad-hoc", 1)

    local function evidence(id, playerName, itemID)
      return { evidenceId = id, awardRef = id, playerName = playerName, itemID = itemID }
    end
    -- Initial balance is startingPoints (1)
    assert_equal(1, dibs.IndependentRaid.GetPlayerBalance("RaiderA-Realm"))

    -- Award with DIB response spends 1 point
    local award1 = dibs.IndependentRaid.RecordAward("RaiderA-Realm", 19019, "Item Link 1", true,
      evidence("test:1", "RaiderA-Realm", 19019))
    assert_true(award1.ok)
    assert_equal(0, dibs.IndependentRaid.GetPlayerBalance("RaiderA-Realm"))

    -- Subsequent DIB award fails due to insufficient points
    local award2 = dibs.IndependentRaid.RecordAward("RaiderA-Realm", 19020, "Item Link 2", true,
      evidence("test:2", "RaiderA-Realm", 19020))
    assert_false(award2.ok)
    assert_equal("INDEPENDENT_NO_POINTS", award2.reasonCode)

    -- Non-DIB award (e.g. Free/MS/OS) succeeds without spending points
    local freeAward = dibs.IndependentRaid.RecordAward("RaiderA-Realm", 19021, "Item Link 3", false,
      evidence("test:3", "RaiderA-Realm", 19021))
    assert_true(freeAward.ok)
    assert_equal(0, dibs.IndependentRaid.GetPlayerBalance("RaiderA-Realm"))

    -- Another player still has their full starting points
    assert_equal(1, dibs.IndependentRaid.GetPlayerBalance("RaiderB-Realm"))
  end)

  it("allows officers to reconcile an independent award into a guild ledger", function()
    local _, dibs = setup()
    dibs.IndependentRaid.StartSession("Community Run", 2)
    local award = dibs.IndependentRaid.RecordAward("RaiderA-Realm", 19019, "Item Link 1", true,
      { evidenceId = "test:reconcile", awardRef = "test:reconcile", playerName = "RaiderA-Realm", itemID = 19019 })
    assert_true(award.ok)
    local sessionId = dibs.IndependentRaid.GetActiveSessionId()
    local awardId = award.awardId
    dibs.IndependentRaid.ConcludeSession()

    -- Non-officer cannot reconcile
    local nonOfficer = "RaiderB-Realm"
    local failReconcile = dibs.IndependentRaid.ReconcileAward(nonOfficer, sessionId, awardId, "guild-primary")
    assert_false(failReconcile.ok)
    assert_equal("GUILD_ADMIN_REQUIRED", failReconcile.reasonCode)

    -- Officer can reconcile into guild-primary
    local officer = "MasterLooter-Realm"
    local seasonId = dibs.GetCurrentSeasonId()
    local gVal, gReason = dibs.Ledger.Grant("RaiderA-Realm", 2, "Starting dibs", "test", seasonId, nil, "guild-primary")
    assert_not_nil(gVal, "Grant failed: " .. tostring(gReason))
    local reconcile = dibs.IndependentRaid.ReconcileAward(officer, sessionId, awardId, "guild-primary")
    assert_true(reconcile.ok, tostring(reconcile.reasonCode))
    assert_not_nil(reconcile.transactionId)

    -- Cannot double reconcile
    local doubleReconcile = dibs.IndependentRaid.ReconcileAward(officer, sessionId, awardId, "guild-primary")
    assert_true(doubleReconcile.ok)
    assert_true(doubleReconcile.duplicate)
    assert_equal(reconcile.transactionId, doubleReconcile.transactionId)
  end)
end)
