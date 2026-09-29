local loader = require("helpers.load_addon")

local function getLootCheck(dibs)
  local report = dibs.SetupAssistant.Evaluate()
  for _, item in ipairs(report.checks or {}) do
    if item.id == "loot_types" then return item, report end
  end
  error("Loot Rules readiness check is missing")
end

describe("First installation assistant integration", function()
  it("delegates local dry-run without creating ledger state", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local before = #((dibs.GetDB() or {}).ledger and dibs.GetDB().ledger.transactions or {})
    local result = dibs.SetupAssistant.RunDryRun({
      item = 275658,
      winner = "Tester-Realm",
      response = "DIB",
      status = "test",
      sessionIdentity = "setup-assistant-test",
    }, { allowPlayer = true })
    assert_not_nil(result)
    assert_equal("would_ignore", result.outcome)
    local after = #((dibs.GetDB() or {}).ledger and dibs.GetDB().ledger.transactions or {})
    assert_equal(before, after)
    assert_false(result.wouldConsumeDib)
  end)

  it("returns a bounded unavailable result when the dry-run service is absent", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local original = dibs.DryRun.Run
    dibs.DryRun.Run = nil
    local result, reason = dibs.SetupAssistant.RunDryRun({ item = 275658 }, { allowPlayer = true })
    dibs.DryRun.Run = original
    assert_equal(nil, result)
    assert_equal("DRY_RUN_UNAVAILABLE", reason)
  end)

  it("reports the real Loot Rules option source as available and ready", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local options = dibs.RCOptions.GetLootTypeOptions()
    assert_not_nil(options.types)
    assert_equal("function", type(options.types.values))
    assert_equal("function", type(options.types.get))
    assert_equal("function", type(options.types.set))
    local check = getLootCheck(dibs)
    assert_equal("ready", check.state)
    assert_equal(nil, check.reasonCode)
    assert_equal("options", check.source)
  end)

  it("keeps valid local Loot Rules ready when operational policy is unadopted or adopted", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local changed = dibs.RCLootCouncil.SetDibEnabledForType("MOUNTS", false)
    assert_true(changed)
    assert_equal(false, dibs.GetDB().settings.dibAllowedTypes.MOUNTS)

    dibs.OperationalPolicy.IsAdopted = function() return false end
    local unadopted = getLootCheck(dibs)
    assert_equal("ready", unadopted.state)
    assert_equal("Controls available", unadopted.scopeLabel)
    assert_true(unadopted.scopeExplanation:find("explicitly adopt", 1, true) ~= nil)

    dibs.OperationalPolicy.IsAdopted = function() return true end
    local adopted = getLootCheck(dibs)
    assert_equal("ready", adopted.state)
    assert_true(adopted.scopeExplanation:find("guild authority", 1, true) ~= nil)
  end)

  it("reports a missing Loot Rules option source as unavailable", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    dibs.RCOptions.GetLootTypeOptions = nil
    local check = getLootCheck(dibs)
    assert_equal("unavailable", check.state)
    assert_equal("LOOT_TYPES_UNAVAILABLE", check.reasonCode)
  end)

  it("reports malformed Loot Rules option data as a warning", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    dibs.RCOptions.GetLootTypeOptions = function()
      return { types = { values = function() return {} end } }
    end
    local check = getLootCheck(dibs)
    assert_equal("degraded", check.state)
    assert_equal("LOOT_TYPES_INVALID", check.reasonCode)
  end)

  it("uses accurate GM and Officer local-scope explanations", function()
    local _, gm = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    gm.Permissions.GetGuildRole = function() return "gm" end
    local gmCheck = getLootCheck(gm)
    assert_equal("Loot Rules controls are available. Review the draft and explicitly adopt it to establish guild authority.", gmCheck.scopeExplanation)

    local _, officer = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    officer.Permissions.GetGuildRole = function() return "officer" end
    local officerCheck = getLootCheck(officer)
    assert_equal("Loot Rules controls are available. Only the Guild Master can adopt or publish guild authority.", officerCheck.scopeExplanation)
  end)

  it("re-probes the Loot Rules option source on each readiness evaluation", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local source = dibs.RCOptions.GetLootTypeOptions()
    local calls = 0
    dibs.RCOptions.GetLootTypeOptions = function()
      calls = calls + 1
      if calls == 1 then return source end
      return nil
    end
    local first = getLootCheck(dibs)
    local second = getLootCheck(dibs)
    assert_equal("ready", first.state)
    assert_equal("unavailable", second.state)
    assert_equal(2, calls)
  end)
end)
