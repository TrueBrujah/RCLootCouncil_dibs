-- Simplified SA-002 Reproduction: Test if audit.actor spoofing works

local loader = require("helpers.load_addon")

local function load(playerName, guildLeader)
  local _, dibs = loader.load({ wow = {
    playerName = playerName,
    guildLeader = guildLeader,
    guildMembers = { "ActualGM-Realm", "Member-Realm", "Target-Realm" },
    guildRankIndices = { [1] = 0, [2] = 3, [3] = 3 },
  } })
  return dibs
end

describe("SA-002: Direct API actor spoofing", function()
  it("S002-A: Direct Ledger.Grant with spoofed actor in audit", function()
    local dibs = load("ActualGM-Realm", true)
    local before = dibs.Ledger.GetBalance("Target-Realm")
    local tx, reason = dibs.Ledger.Grant("Target-Realm", 5, "Test grant", "spoof-test", dibs.GetCurrentSeasonId(), {
      actor = "FakeGM-Realm",
      actorName = "FakeGM-Realm",
      transactionId = "spoof-test-1"
    })

    assert_nil(tx, "a caller-supplied fake audit actor authorized the grant")
    assert_not_nil(reason, "the spoofed actor rejection has no diagnostic")
    assert_equal(before, dibs.Ledger.GetBalance("Target-Realm"), "a rejected spoof changed the balance")
  end)

  it("S002-B: Direct Ledger.Grant with nil audit (defaults to current player)", function()
    local dibs = load("ActualGM-Realm", true)
    local tx, reason = dibs.Ledger.Grant("Target-Realm", 5, "Test grant", "direct-test", dibs.GetCurrentSeasonId(), nil)

    assert_not_nil(tx, tostring(reason))
    assert_equal(dibs.Permissions.CanonicalPlayerId("ActualGM-Realm"), tx.actorId,
      "the audit identity did not come from the current actor")
  end)

  it("S002-C: Direct Ledger.Grant by regular member (no guildLeader)", function()
    local dibs = load("Member-Realm", false)
    local before = dibs.Ledger.GetBalance("Target-Realm")
    local tx, reason = dibs.Ledger.Grant("Target-Realm", 5, "Test grant", "direct-test", dibs.GetCurrentSeasonId(), nil)

    assert_nil(tx, "a guild member granted Dibs without Officer/GM authority")
    assert_equal("GUILD_ADMIN_REQUIRED", reason)
    assert_equal(before, dibs.Ledger.GetBalance("Target-Realm"), "a rejected member grant changed the balance")
  end)

  it("S002-D: ProtectedActions.Execute by GM", function()
    local dibs = load("ActualGM-Realm", true)
    local result = dibs.ProtectedActions.Execute("ledger.grant", "ActualGM-Realm", {
      playerName = "Target-Realm",
      amount = 5,
      reason = "Test",
      source = "protected-test",
      seasonId = dibs.GetCurrentSeasonId()
    })

    assert_true(result.ok, tostring(result.reasonCode))
    assert_equal(dibs.Permissions.CanonicalPlayerId("ActualGM-Realm"), result.value.actorId)
  end)

  it("S002-E: ProtectedActions.Execute by regular member", function()
    local dibs = load("Member-Realm", false)
    local before = dibs.Ledger.GetBalance("Target-Realm")
    local result = dibs.ProtectedActions.Execute("ledger.grant", "Member-Realm", {
      playerName = "Target-Realm",
      amount = 5,
      reason = "Test",
      source = "protected-test",
      seasonId = dibs.GetCurrentSeasonId()
    })
    assert_false(result.ok, "a regular guild member was authorized to grant Dibs")
    assert_equal("GUILD_ADMIN_REQUIRED", result.reasonCode)
    assert_equal(before, dibs.Ledger.GetBalance("Target-Realm"), "a rejected member action changed the balance")
  end)

  it("rejects a ProtectedActions call that supplies a different GM identity", function()
    local dibs = load("ActualGM-Realm", true)
    local before = dibs.Ledger.GetBalance("Target-Realm")
    local result = dibs.ProtectedActions.Execute("ledger.grant", "FakeGM-Realm", {
      playerName = "Target-Realm", amount = 5, reason = "Test", source = "spoof-test",
      seasonId = dibs.GetCurrentSeasonId(),
    })

    assert_false(result.ok, "a caller-supplied alternate GM name authorized a protected action")
    assert_equal(before, dibs.Ledger.GetBalance("Target-Realm"), "the rejected spoof changed the balance")
  end)
end)
