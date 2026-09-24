local loader = require("helpers.load_addon")

describe("Core player identity", function()
  it("appends the realm when UnitFullName reports an empty realm for the local unit", function()
    local _, dibs = loader.load({ wow = { playerName = "Tester-Realm" } })
    -- UnitFullName("player") always returns an empty realm string for yourself; the
    -- empty string is truthy in Lua, so a naive `realm or GetRealmName()` never falls back.
    local previous = _G.UnitFullName
    _G.UnitFullName = function(unit)
      if unit == "player" then return "Tester", "" end
      return nil
    end
    assert_equal("Tester-Realm", dibs.GetPlayerName())
    _G.UnitFullName = previous
  end)
end)
