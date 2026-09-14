local loader = require("helpers.load_addon")

local function setup(options)
  options = options or {}
  options.withAce3 = true
  options.wow = options.wow or { guildLeader = true }
  local _, dibs = loader.load(options)
  return dibs
end

describe("Retail Officer navigation lifecycle", function()
  it("keeps the selected route, mounted page, and single content host in sync", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    local sequence = { "overview", "disputes", "preDibs", "history", "seasons", "integration", "settings", "diagnostics", "overview" }

    for _, route in ipairs(sequence) do
      frame.SelectTab(route)
      assert_equal(route, frame.selectedRoute)
      assert_equal(route, frame.activeTab)
      assert_equal(route, frame.mountedPage)
      assert_equal(1, #(frame.contentHost.children or {}))
      assert_true(#(frame.contentHost.children[1].children or {}) > 0)
    end
  end)

  it("routes the real AceGUI TreeGroup unique value to the selected renderer", function()
    local dibs = setup()
    dibs.DeveloperMode.SetEnabled(true)
    local frame = dibs.OfficerUI.CreateWindow()
    local callback = frame.aceTabs.callbacks.OnGroupSelected
    local sections = {}
    for _, entry in ipairs(dibs.OfficerUI.GetNavigationTree()) do sections[entry.value] = entry.section end
    local routes = { "overview", "disputes", "preDibs", "history", "seasons", "ranks", "lootTypes", "announcements", "integration", "settings", "diagnostics", "eligibility", "developer", "debug" }

    for _ = 1, 2 do
      for _, route in ipairs(routes) do
        local section = "section_" .. string.lower((sections[route] or ""):gsub("%s+", "_"))
        callback(frame.aceTabs, "OnGroupSelected", section .. string.char(1) .. route)

        assert_equal(route, frame.selectedRoute)
        assert_equal(route, frame.mountedPage)
        assert_equal(1, frame.primaryPageCount)
        assert_true(#(frame.contentHost.children[1].children or {}) > 0)
        assert_true(not tostring(frame.contentHost.children[1].children[1].text or ""):find("Dashboard", 1, true), route)
      end
    end
  end)

  it("does not duplicate page roots across repeated route transitions or reopen", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    local firstHost = frame.contentHost
    for _ = 1, 2 do
      for _, route in ipairs({ "overview", "disputes", "preDibs", "history", "settings", "overview" }) do
        frame.SelectTab(route)
        assert_equal(1, #(frame.contentHost.children or {}))
      end
    end
    assert_equal(firstHost, frame.contentHost)
    frame.dibsAceGUIShell.window:Hide()
    local reopened = dibs.OfficerUI.CreateWindow()
    assert_equal("overview", reopened.activeTab)
    assert_equal("overview", reopened.selectedRoute)
    assert_equal("overview", reopened.mountedPage)
    assert_equal(1, #(reopened.contentHost.children or {}))
  end)

  it("keeps Officer routes unavailable to a production player", function()
    local dibs = setup({ wow = { guildLeader = false } })
    assert_equal("player", dibs.OfficerUI.GetPresentationRole())
    assert_equal(0, #dibs.OfficerUI.GetNavigationTree())
    assert_false(dibs.OfficerUI.Toggle(true))
  end)

  it("keeps sandbox role authority separate from production routing", function()
    local dibs = setup({ wow = { guildLeader = true } })
    dibs.DeveloperMode.SetEnabled(true)
    local production = dibs.OfficerUI.CreateWindow()
    assert_equal("overview", production.mountedPage)
    assert_true(dibs.DeveloperSandbox.EnterSandbox({ clone = true, role = "guild_master" }))
    local sandbox = dibs.OfficerUI.CreateWindow()
    assert_equal("gm", dibs.OfficerUI.GetPresentationRole())
    sandbox.SelectTab("settings")
    assert_equal("settings", sandbox.mountedPage)
    assert_equal("settings", sandbox.selectedRoute)
    assert_true(dibs.DeveloperSandbox.ExitSandbox())
  end)
end)