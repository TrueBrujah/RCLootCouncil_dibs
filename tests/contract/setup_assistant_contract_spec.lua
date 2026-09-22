local loader = require("helpers.load_addon")

describe("First installation assistant contract", function()
  it("projects required checks and keeps administrative details role-scoped", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local report = dibs.SetupAssistant.Evaluate()
    assert_true(report.status == "READY_FOR_RAID" or report.status == "NEEDS_ATTENTION" or report.status == "UNAVAILABLE")
    assert_true(#report.checks >= 6)
    local ids = {}
    for _, item in ipairs(report.checks) do ids[item.id] = true end
    assert_true(ids.season)
    assert_true(ids.policy or ids.rank_rules)
    assert_true(ids.rclootcouncil)
    assert_true(ids.channels)
    assert_true(ids.loot_types)

    loader.load({ wow = { guildLeader = false, guildRankIndices = { ["Tester-Realm"] = 3 } }, withAce3 = true })
    local denied = _G.Dibs.SetupAssistant.Evaluate()
    assert_equal("DENIED", denied.status)
  end)

  it("delegates only allowlisted setup actions", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local captured
    local original = dibs.ProtectedActions.Execute
    dibs.ProtectedActions.Execute = function(actionId, actor, payload)
      captured = { actionId = actionId, actor = actor, payload = payload }
      return { ok = true, value = payload }
    end
    local result = dibs.SetupAssistant.ExecuteAction("installation.mode.set", "Tester-Realm", { mode = "STANDALONE" })
    local rejected = dibs.SetupAssistant.ExecuteAction("ledger.use", "Tester-Realm", { amount = 1 })
    dibs.ProtectedActions.Execute = original
    assert_true(result.ok)
    assert_equal("installation.mode.set", captured.actionId)
    assert_equal("setup-assistant", captured.payload.source)
    assert_false(rejected.ok)
    assert_equal("INVALID_SETUP_ACTION", rejected.reasonCode)
  end)

  it("separates a loaded RCLootCouncil addon from missing raid context", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local original = dibs.Readiness.Evaluate
    dibs.Readiness.Evaluate = function()
      return { status = "Unavailable", probes = {
        { name = "rclootcouncil", state = "unavailable", required = false,
          reasonCode = "NO_RAID_CONTEXT", impact = "loaded", remediation = "enter raid" },
      } }
    end
    local report = dibs.SetupAssistant.Evaluate()
    dibs.Readiness.Evaluate = original
    local rcCheck
    for _, item in ipairs(report.checks) do
      if item.id == "rclootcouncil" then rcCheck = item end
    end
    assert_equal("ready", rcCheck.state)
    assert_equal("RC_LOADED_NO_RAID_CONTEXT", rcCheck.reasonCode)
  end)
end)
