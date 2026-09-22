local loader = require("helpers.load_addon")

describe("Health dashboard contract", function()
  it("projects bounded operational health without private records", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local report = dibs.HealthUI.Evaluate()
    assert_true(report.status == "READY" or report.status == "DEGRADED" or report.status == "BLOCKED" or report.status == "UNAVAILABLE")
    assert_true(report.version ~= nil)
    assert_true(report.schemaVersion ~= nil)
    assert_true(#report.checks >= 5)
    assert_true(report.persistence ~= nil)
    assert_true(report.sync ~= nil)
    assert_true(report.rclootcouncil ~= nil)
    assert_false(report.privateData)
    assert_nil(report.transactions)
    assert_nil(report.playerNames)
  end)

  it("denies the administrative report to a normal player", function()
    loader.load({ wow = { guildLeader = false, guildRankIndices = { ["Tester-Realm"] = 3 } }, withAce3 = true })
    local report = _G.Dibs.HealthUI.Evaluate()
    assert_equal("DENIED", report.status)
    assert_equal("player", report.role)
    assert_equal(0, #report.checks)
  end)

  it("keeps unavailable integration and sync states explicit", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = false })
    local report = dibs.HealthUI.Evaluate()
    local states = {}
    for _, item in ipairs(report.checks) do states[item.id] = item.state end
    assert_true(states.rclootcouncil == "unavailable" or states.rclootcouncil == "degraded")
    assert_true(states.sync == "unavailable" or states.sync == "degraded")
  end)

  it("describes loaded RCLootCouncil separately from missing raid context", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    dibs.RCLootCouncil.GetLocalStatus = function()
      return { status = "degraded", reasonCode = "RC_MASTER_LOOTER_UNVERIFIABLE" }
    end
    dibs.Readiness.Evaluate = function()
      return { context = { inRaid = false }, status = "Unavailable" }
    end
    local report = dibs.HealthUI.Evaluate()
    local rcCheck
    for _, item in ipairs(report.checks) do
      if item.id == "rclootcouncil" then rcCheck = item end
    end
    assert_equal("ready", rcCheck.state)
    assert_equal("RC_LOADED_NO_RAID_CONTEXT", rcCheck.reason)
  end)
end)