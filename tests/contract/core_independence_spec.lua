local loader = require("helpers.load_addon")

describe("Core independence", function()
  it("loads and executes core actions without RC or LibStub", function()
    local _, dibs = loader.load({ withLibStub = false, wow = { guildLeader = true } })

    assert_not_nil(dibs)
    assert_equal("absent", dibs.RCLootCouncil.GetAvailability())

    local season = dibs.ProtectedActions.Execute("season.create", nil, { name = "CoreOnly" })
    assert_true(season.ok)

    local rank = dibs.ProtectedActions.Execute("rank.set", nil, {
      seasonId = season.value.id,
      rankIndex = 1,
      allocation = 2,
    })
    assert_true(rank.ok)
    assert_equal(2, rank.value.allocation)
  end)

  it("preserves an externally supplied LibStub while remaining standalone", function()
    local requested = {}
    local externalStub = function(name, silent)
      requested[name] = true
      if name == "AceAddon-3.0" then
        return { GetAddon = function() return nil end }
      end
      if not silent then error("unexpected library: " .. tostring(name)) end
      return nil
    end
    local _, dibs = loader.load({ libStub = externalStub, wow = { guildLeader = true } })

    assert_equal(externalStub, _G.LibStub)
    assert_true(requested["AceEvent-3.0"])
    assert_equal("absent", dibs.RCLootCouncil.GetAvailability())
    assert_nil(dibs.PlayerUI.CreateWindow().dibsAceGUIShell)
  end)
end)
