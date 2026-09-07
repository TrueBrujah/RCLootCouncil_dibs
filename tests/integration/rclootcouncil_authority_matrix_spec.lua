local loader = require("helpers.load_addon")

local function settingsDecision(wowOptions, rcOptions)
  local _, dibs = loader.load({
    wow = wowOptions,
    rclootcouncil = loader.makeRCLootCouncil(rcOptions),
  })
  return dibs.Permissions.Evaluate("settings.modify", nil), dibs
end

describe("RCLootCouncil authority matrix", function()
  it("keeps guild GM and officer authority independent of raid roles", function()
    local gm, gmDibs = settingsDecision({ playerName = "GM-Realm", playerGUID = "Player-1-GM", guildLeader = true, guildMembers = { "GM-Realm" }, guildRankIndices = { [1] = 0 } }, { masterLooter = { guid = "Player-2-ML", name = "ML-Realm" } })
    local officer, officerDibs = settingsDecision({ playerName = "Officer-Realm", playerGUID = "Player-2-OFFICER", guildLeader = false, guildMembers = { "Officer-Realm" }, guildRankIndices = { [1] = 1 } }, { masterLooter = { guid = "Player-3-ML", name = "ML-Realm" } })

    assert_true(gm.allowed)
    assert_equal("gm", gm.role)
    assert_true(officer.allowed)
    assert_equal("officer", officer.role)
  end)

  it("limits a local non-admin Master Looter to the award exception", function()
    local rc = loader.makeRCLootCouncil({ masterLooter = { guid = "Player-1-ML", name = "ML-Realm" }, currentSessionId = "matrix-session" })
    local _, dibs = loader.load({
      rclootcouncil = rc,
      wow = { playerName = "ML-Realm", playerGUID = "Player-1-ML", guildLeader = false, guildMembers = { "ML-Realm" }, guildRankIndices = { [1] = 3 } },
    })
    local settings = dibs.Permissions.Evaluate("settings.modify", nil)
    local award = dibs.Permissions.Evaluate("award.finalize", nil)
    local manual = dibs.Permissions.Evaluate("ledger.grant", nil)

    assert_false(settings.allowed)
    assert_true(award.allowed)
    assert_false(manual.allowed)
    assert_equal("rclootcouncil", award.authority)
  end)

  it("does not promote raid leader, assistant, council, or remote claims", function()
    local raidLeader = settingsDecision({ raidLeader = true, guildLeader = false, guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 3 } }, {})
    local raidAssistant = settingsDecision({ raidAssistant = true, guildLeader = false, guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 3 } }, {})
    local _, dibs = loader.load({
      rclootcouncil = loader.makeRCLootCouncil({ masterLooter = { guid = "Player-2-ML", name = "Other-Realm" } }),
      wow = { guildLeader = false, guildMembers = { "Tester-Realm", "Other-Realm" }, guildRankIndices = { [1] = 3, [2] = 3 } },
    })
    local council = dibs.Permissions.Evaluate("settings.modify", { council = true, name = "Tester-Realm" })
    local remoteClaim = dibs.Permissions.Evaluate("settings.modify", { role = "gm", name = "Other-Realm" })

    assert_false(raidLeader.allowed)
    assert_false(raidAssistant.allowed)
    assert_false(council.allowed)
    assert_false(remoteClaim.allowed)
    assert_equal("GUILD_ADMIN_REQUIRED", council.reasonCode)
  end)
end)
