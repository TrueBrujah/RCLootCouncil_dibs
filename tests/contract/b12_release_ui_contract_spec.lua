local loader = require("helpers.load_addon")

describe("B12a UI contracts", function()
  it("normalizes grouped TreeGroup values and preserves programmatic aliases", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
    local frame = dibs.OfficerUI.CreateWindow()
    local sections = {}
    for _, entry in ipairs(dibs.OfficerUI.GetNavigationTree()) do sections[entry.value] = entry.section end
    local callback = frame.aceTabs.callbacks.OnGroupSelected
    for _, route in ipairs({ "overview", "disputes", "preDibs", "history", "settings", "diagnostics" }) do
      local section = "section_" .. string.lower((sections[route] or ""):gsub("%s+", "_"))
      callback(frame.aceTabs, "OnGroupSelected", section .. string.char(1) .. route)
      assert_equal(route, frame.selectedRoute)
      assert_equal(route, frame.mountedPage)
      assert_equal(1, frame.primaryPageCount)
    end
    frame.SelectTab("requests")
    assert_equal("disputes", frame.selectedRoute)
    assert_equal("disputes", frame.mountedPage)
  end)

  it("keeps visible enum labels separate from canonical service values", function()
    local _, dibs = loader.load({ wow = { guildLeader = true }, withAce3 = true })
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
    mode.set(nil, "invalid-label")
    dibs.ProtectedActions.Execute = original
    assert_equal("WILD_OPEN", captured[1].payload.mode)
    assert_equal("ENCOUNTER", captured[2].payload.mode)
    assert_equal(2, #captured)
  end)
end)
