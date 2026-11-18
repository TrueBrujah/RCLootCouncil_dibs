-- SA-002 regressions: authorization failures must fail the suite, not only print diagnostics.
local loader = require("helpers.load_addon")
local function load(gm, name)
  name = name or "Tester-Realm"
  return select(2, loader.load({ wow = {
    guildLeader = gm ~= false, playerName = name,
    guildMembers = { name, "Target-Realm" }, guildRankIndices = { gm == false and 3 or 0, 3 },
  } }))
end

describe("SA-002: Direct API actor spoofing", function()
  it("rejects a spoofed actor and leaves all ledger transactions unchanged", function()
    local dibs = load()
    local before = #dibs.Ledger.GetAllTransactions()
    local tx, reason = dibs.Ledger.Grant("Target-Realm", 5, "Test grant", "spoof-test", dibs.GetCurrentSeasonId(), {
      actor = "FakeGM-Realm", actorName = "FakeGM-Realm", transactionId = "spoof-test-1",
    })
    assert_nil(tx)
    assert_not_nil(reason)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)

  it("binds a direct grant without audit to the verified current GM", function()
    local dibs = load()
    local tx, reason = dibs.Ledger.Grant("Target-Realm", 5, "Test grant", "direct-test", dibs.GetCurrentSeasonId())
    assert_not_nil(tx, tostring(reason))
    assert_equal(assert(dibs.Identity.CreateSnapshot(dibs.GetPlayerName())).memberKey, tx.actorId)
  end)

  it("refuses a direct grant by an actual rank-three member", function()
    local dibs = load(false)
    local before = #dibs.Ledger.GetAllTransactions()
    local tx = dibs.Ledger.Grant("Target-Realm", 5, "Test grant", "direct-test", dibs.GetCurrentSeasonId())
    assert_nil(tx)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)

  it("allows a protected grant by the authenticated local GM", function()
    local dibs = load()
    local result = dibs.ProtectedActions.Execute("ledger.grant", nil, {
      playerName = "Target-Realm", amount = 5, reason = "Test", source = "protected-test", seasonId = dibs.GetCurrentSeasonId(),
    })
    assert_true(result.ok, tostring(result.diagnostic))
    assert_not_nil(result.value.transactionId)
  end)

  it("refuses the same protected action by an authenticated ordinary member", function()
    local dibs = load(false)
    local before = #dibs.Ledger.GetAllTransactions()
    local result = dibs.ProtectedActions.Execute("ledger.grant", nil, {
      playerName = "Target-Realm", amount = 5, reason = "Test", source = "protected-test", seasonId = dibs.GetCurrentSeasonId(),
    })
    assert_false(result.ok)
    assert_equal("GUILD_ADMIN_REQUIRED", result.decision.reasonCode)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)

  it("verifies the actual guild master identity from the local context", function()
    local dibs = load(true, "ActualGM-Realm")
    assert_equal("ActualGM-Realm", dibs.GetPlayerName())
    assert_true(dibs.Permissions.IsGM())
  end)

  it("does not confuse an arbitrary actor identifier with the local identity", function()
    local dibs = load(true, "ActualGM-Realm")
    local supplied = dibs.Permissions.CanonicalPlayerId("FakeGM-Realm")
    local current = dibs.Permissions.CanonicalPlayerId(nil)
    assert_not_nil(current)
    assert_false(supplied == current)
  end)

  it("rejects a protected grant that supplies another GM identity", function()
    local dibs = load(true, "ActualGM-Realm")
    local before = #dibs.Ledger.GetAllTransactions()
    local result = dibs.ProtectedActions.Execute("ledger.grant", "FakeGM-Realm", {
      playerName = "Target-Realm", amount = 5, reason = "Test", source = "spoof-test",
      seasonId = dibs.GetCurrentSeasonId(),
    })
    assert_false(result.ok)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)
end)
