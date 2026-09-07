local loader = require("helpers.load_addon")
local wow = require("helpers.wow_api")

describe("RCLootCouncil capability lifecycle", function()
  it("keeps Standalone data available while RC is absent", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.GetDB().settings.allowPublicPreDibs = false
    local balance = dibs.Ledger.GetBalance("Tester-Realm")

    local snapshot = dibs.RCLootCouncil.GetCapabilities()
    assert_equal("absent", snapshot.state)
    assert_equal("RC_ABSENT", snapshot.reasonCode)
    assert_true(dibs.Permissions.Can("settings.modify"))
    assert_equal(seasonId, dibs.GetCurrentSeasonId())
    assert_equal(balance, dibs.Ledger.GetBalance("Tester-Realm"))
  end)

  it("rechecks a late-loaded RC surface without resetting Dibs state", function()
    local _, dibs = loader.load({ wow = { guildLeader = true } })
    local seasonId = dibs.GetCurrentSeasonId()
    dibs.GetDB().settings.allowPublicPreDibs = false
    local before = dibs.GetDB()

    local rc = loader.makeRCLootCouncil({ enabled = true })
    _G.RCLootCouncil = rc
    wow.dispatch("PLAYER_LOGIN")
    dibs.RCLootCouncil.TryUseRCModule()

    assert_true(dibs.initialized == true)
    assert_true(dibs.RCLootCouncil.initialized == true)
    assert_equal("operational", dibs.RCLootCouncil.GetAvailability())
    assert_equal(seasonId, dibs.GetCurrentSeasonId())
    assert_equal(false, dibs.GetDB().settings.allowPublicPreDibs)
    assert_true(dibs.GetDB() == before)
  end)

  it("reports unsupported or disabled RC without expanding guild authority", function()
    local disabled = loader.makeRCLootCouncil({ enabled = false })
    local _, dibs = loader.load({ rclootcouncil = disabled, wow = { guildLeader = false, guildMembers = { "Tester-Realm" }, guildRankIndices = { [1] = 3 } } })
    local snapshot = dibs.RCLootCouncil.GetCapabilities()
    assert_equal("absent", snapshot.state)
    assert_equal("RC_DISABLED", snapshot.reasonCode)
    assert_false(dibs.Permissions.Can("settings.modify"))
  end)
end)
