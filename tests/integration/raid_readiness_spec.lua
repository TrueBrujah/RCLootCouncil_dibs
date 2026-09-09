local loader = require("helpers.load_addon")
local fixtures = require("helpers.rclootcouncil_fixtures")

describe("Raid readiness", function()
  local function setup(wow, rc)
    rc = rc or loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({
      wow = wow or { guildLeader = true },
      rclootcouncil = rc,
      withAce3 = true,
    })
    return dibs, rc
  end

  it("keeps standalone administration ready and marks no-group integration unavailable", function()
    local dibs = setup({ guildLeader = true, inRaid = false })
    local result = dibs.Readiness.Run()
    assert_not_nil(result)
    assert_equal("Ready", result.standaloneStatus)
    assert_equal("Unavailable", result.integrationStatus)
    assert_equal("Unavailable", result.status)
    assert_true(result.freshnessMarker ~= nil)
    assert_true(#(result.probes or {}) >= 5)
    for _, probe in ipairs(result.probes) do
      if probe.state == "ready" then assert_nil(probe.reasonCode) end
    end
    assert_true(dibs.Readiness.CanProcessLiveAward())
  end)

  it("reports a blocked live integration when the Master Looter is unverifiable", function()
    local rc = loader.makeRCLootCouncil(fixtures.degraded())
    local dibs = setup({ guildLeader = true, inRaid = true, instanceType = "raid" }, rc)
    local result = dibs.Readiness.Run()
    assert_equal("Ready", result.standaloneStatus)
    assert_equal("Blocked", result.integrationStatus)
    assert_equal("Blocked", result.status)
    assert_true(result.reasonCodes.RC_MASTER_LOOTER_UNVERIFIABLE == true)
    assert_false(dibs.Readiness.CanProcessLiveAward())
  end)

  it("invalidates a previous result after roster or zone changes", function()
    local dibs = setup({ guildLeader = true, inRaid = false })
    local result = dibs.Readiness.Run()
    assert_false(result.stale == true)
    dibs.Readiness.Invalidate("GROUP_ROSTER_UPDATE")
    assert_true(dibs.Readiness.GetLast().stale == true)
    assert_equal("GROUP_ROSTER_UPDATE", dibs.Readiness.GetLast().staleReason)
  end)

  it("produces safe reports without live loot state", function()
    local dibs = setup({ guildLeader = true, inRaid = false })
    local result = dibs.Readiness.Run()
    local safe = dibs.Readiness.BuildReport(result, "safe")
    assert_true(safe:find("Raid Readiness", 1, true) ~= nil)
    assert_true(safe:find("Candidates", 1, true) == nil)
    assert_true(safe:find("votes", 1, true) == nil)
    assert_true(safe:find(dibs.GetPlayerName(), 1, true) == nil)
  end)

  it("exposes officer readiness controls and a player-safe summary", function()
    local dibs = setup({ guildLeader = true })
    assert_true(dibs.RCOptions.EnsureRegistered(1))
    local args = dibs.Ace3.libs.config.tables.RCLootCouncil_dibs.args.dibsSettings.args
    assert_not_nil(args.player.args.readiness)
    assert_not_nil(args.officer.args.integration.args.readiness)
    assert_not_nil(args.officer.args.integration.args.readiness.args.runDryRun)
  end)

  it("supports the authorized readiness slash command", function()
    local dibs = setup({ guildLeader = true })
    dibs.HandleSlashCommand("readiness")
    assert_true(#(_G.__dibsMessages or {}) > 0)
  end)
end)
