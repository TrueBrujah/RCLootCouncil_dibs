local loader = require("helpers.load_addon")

describe("B12b page cleanup contracts", function()
  it("keeps Pre-Dibs settings canonical at the visible control boundary", function()
    local rc = loader.makeRCLootCouncil({ optionsFrame = {} })
    local _, dibs = loader.load({ wow = { guildLeader = true }, rclootcouncil = rc, withAce3 = true })
    local captured = {}
    local original = dibs.ProtectedActions.Execute
    dibs.ProtectedActions.Execute = function(actionId, actor, payload)
      captured[#captured + 1] = { actionId = actionId, payload = payload }
      return { ok = true, value = payload }
    end

    local options = dibs.RCOptions.GetOptionsTable()
    local mode = options.args.dibsSettings.args.officer.args.preDibs.args.mode
    mode.set(nil, "Wild Open")
    mode.set(nil, "Encounter")
    mode.set(nil, "not-a-mode")

    dibs.ProtectedActions.Execute = original
    assert_equal(2, #captured)
    assert_equal("predib.mode.set", captured[1].actionId)
    assert_equal("WILD_OPEN", captured[1].payload.mode)
    assert_equal("ENCOUNTER", captured[2].payload.mode)
  end)

  it("keeps eligibility and Debug presentation authorization-aware", function()
    local _, player = loader.load({ wow = { guildLeader = false, guildRank = 0 } })
    local hidden = player.OfficerUI.GetEligibilityProjection(player.GetCurrentSeasonId())
    assert_true(hidden.hidden)
    assert_false(player.DeveloperUI.GetProjection().visible)

    local _, officer = loader.load({ wow = { guildLeader = true } })
    local visible = officer.OfficerUI.GetEligibilityProjection(officer.GetCurrentSeasonId())
    assert_true(visible.hidden ~= true)
    officer.HandleSlashCommand("dev on")
    local debug = officer.DeveloperUI.GetProjection()
    assert_true(debug.visible)
    assert_false(debug.active)
    assert_equal("production", debug.provider)
  end)

  it("exposes fail-closed RCLootCouncil capability states", function()
    local _, absent = loader.load({ withLibStub = false, wow = { guildLeader = true } })
    assert_equal("absent", absent.RCLootCouncil.GetAvailability())

    local degradedRC = loader.makeRCLootCouncil({ enabled = true, currentSessionId = false })
    degradedRC.RegisterMessage = nil
    local _, degraded = loader.load({ rclootcouncil = degradedRC, wow = { guildLeader = true } })
    assert_equal("degraded", degraded.RCLootCouncil.GetAvailability())

    local unsupportedRC = loader.makeRCLootCouncil({ enabled = true })
    local _, unsupported = loader.load({ rclootcouncil = unsupportedRC, wow = { guildLeader = true } })
    unsupported.RCLootCouncil.IsDibResponse = nil
    assert_equal("unsupported", unsupported.RCLootCouncil.GetAvailability())
  end)
end)
