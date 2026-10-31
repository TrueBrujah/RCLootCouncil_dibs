local loader = require("helpers.load_addon")

describe("Officer route Lua 5.1 upvalue budget", function()
  it("keeps renderRoute at or below Retail's 60-upvalue ceiling", function()
    local _, dibs = loader.load({ withAce3 = true })
    local frame = dibs.OfficerUI.CreateWindow("overview")
    assert_true(type(debug) == "table" and type(debug.getupvalue) == "function",
      "test runtime must expose debug.getupvalue")

    local activateRoute
    for index = 1, 100 do
      local name, value = debug.getupvalue(frame.ActivateRoute, index)
      if not name then break end
      if name == "activateRoute" then activateRoute = value; break end
    end
    assert_true(type(activateRoute) == "function", "Officer route dispatcher was not found")

    local renderRoute
    for index = 1, 100 do
      local name, value = debug.getupvalue(activateRoute, index)
      if not name then break end
      if name == "renderRoute" then renderRoute = value; break end
    end
    assert_true(type(renderRoute) == "function", "Officer page renderer was not found")

    local count = 0
    for index = 1, 100 do
      local name = debug.getupvalue(renderRoute, index)
      if not name then break end
      count = count + 1
    end
    assert_true(count <= 60, "renderRoute captures " .. count .. " upvalues; WoW Retail permits at most 60")
  end)
end)
