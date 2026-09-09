local loader = require("helpers.load_addon")

describe("Raid dry-run contract", function()
  local function setup(wow, rc)
    rc = rc or loader.makeRCLootCouncil({})
    local _, dibs = loader.load({
      wow = wow or { guildLeader = true },
      rclootcouncil = rc,
      withAce3 = true,
    })
    return dibs
  end

  it("evaluates a finalized DIB without mutating the ledger", function()
    local dibs = setup({ guildLeader = true })
    local before = #dibs.Ledger.GetAllTransactions()
    local result = dibs.DryRun.Run({
      item = 19019,
      winner = "Tester-Realm",
      response = "DIB",
      status = "finalized",
      sessionIdentity = "dry-session-1",
    })
    assert_equal("would_allow", result.outcome)
    assert_true(result.wouldConsumeDib == true)
    assert_true(result.simulation == true)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)

  it("rejects test or pending status deterministically", function()
    local dibs = setup({ guildLeader = true })
    local input = { item = 19019, winner = "Tester-Realm", response = "DIB", status = "test_mode", sessionIdentity = "dry-session-2" }
    local first = dibs.DryRun.Run(input)
    local second = dibs.DryRun.Run(input)
    assert_equal("would_ignore", first.outcome)
    assert_equal("AWARD_TEST_MODE", first.reasonCodes[1])
    assert_equal(first.fingerprint, second.fingerprint)
    assert_equal(first.outcome, second.outcome)
    assert_equal(first.reasonCodes[1], second.reasonCodes[1])
  end)

  it("uses the same response and item guards as live awards", function()
    local dibs = setup({ guildLeader = true })
    local result = dibs.DryRun.Run({
      item = 19019,
      winner = "Tester-Realm",
      response = "Need",
      status = "finalized",
      sessionIdentity = "dry-session-3",
    })
    assert_equal("would_ignore", result.outcome)
    assert_equal("NON_DIB_RESPONSE", result.reasonCodes[1])
    assert_false(result.mutated == true)
  end)

  it("allows local simulation when RCLootCouncil is absent without fabricating traffic", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local sentBefore = #(_G.__sentChatMessages or {})
    local result = dibs.DryRun.Run({
      item = 19019,
      winner = "Tester-Realm",
      response = "DIB",
      status = "finalized",
      sessionIdentity = "dry-session-4",
    })
    assert_equal("Unavailable", result.integrationStatus)
    assert_true(result.outcome == "would_allow" or result.outcome == "would_reject" or result.outcome == "would_require_review")
    assert_equal(sentBefore, #(_G.__sentChatMessages or {}))
  end)

  it("rejects dry-runs from ordinary players without changing state", function()
    local dibs = setup({ guildLeader = false, guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 3 } })
    local before = #dibs.Ledger.GetAllTransactions()
    local result, reason = dibs.DryRun.Run({ item = 19019, winner = "Tester-Realm", response = "DIB", status = "finalized", sessionIdentity = "dry-session-5" })
    assert_nil(result)
    assert_equal("GUILD_ADMIN_REQUIRED", reason)
    assert_equal(before, #dibs.Ledger.GetAllTransactions())
  end)
end)
