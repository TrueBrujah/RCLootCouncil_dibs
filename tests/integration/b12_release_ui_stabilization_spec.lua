local loader = require("helpers.load_addon")

local function setup()
  return loader.load({
    wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Officer-Realm" } },
    withAce3 = true,
  })
end

local function containsText(widget, text)
  if type(widget) ~= "table" then return false end
  if tostring(widget.text or ""):find(text, 1, true) then return true end
  if tostring(widget.label or ""):find(text, 1, true) then return true end
  for _, child in ipairs(widget.children or {}) do
    if containsText(child, text) then return true end
  end
  return false
end

describe("B12a Runtime UI Stabilization", function()
  it("keeps ten alternating Player and Officer open-close cycles isolated", function()
    local _, dibs = setup()
    local player, officer = dibs.PlayerUI.CreateWindow(), dibs.OfficerUI.CreateWindow()
    local officerRoutes = { "overview", "disputes", "preDibs", "history", "settings", "diagnostics" }
    local playerRoutes = { "summary", "requests", "history", "eligibility", "settings" }

    for cycle = 1, 10 do
      player.SelectTab(playerRoutes[(cycle - 1) % #playerRoutes + 1])
      assert_true(#(player.aceTabs.children or {}) > 0)
      officer.SelectTab(officerRoutes[(cycle - 1) % #officerRoutes + 1])
      assert_equal(1, #(officer.contentHost.children or {}))
      assert_true(#(officer.contentHost.children[1].children or {}) > 0)

      local playerShell, officerShell = player.dibsAceGUIShell, officer.dibsAceGUIShell
      playerShell.window.callbacks.OnClose(playerShell.window, "OnClose")
      officerShell.window.callbacks.OnClose(officerShell.window, "OnClose")
      assert_false(playerShell._dibsActive)
      assert_false(officerShell._dibsActive)
      player, officer = dibs.PlayerUI.CreateWindow(), dibs.OfficerUI.CreateWindow()
      assert_true(player.aceTabs ~= officer.aceTabs)
      assert_true(player.dibsAceGUIShell.window ~= officer.dibsAceGUIShell.window)
    end
  end)

  it("keeps one page root and removes stale History content during transitions", function()
    local _, dibs = setup()
    dibs.DeveloperMode.SetEnabled(true)
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("history")
    assert_true(containsText(frame.contentHost, "History reconciliation"))
    local oldRoot = frame.contentHost.children[1]
    frame.SelectTab("debug")
    assert_equal(1, #(frame.contentHost.children or {}))
    assert_false(containsText(frame.contentHost, "History reconciliation"))
    assert_false(oldRoot.frame._shown)
    frame.SelectTab("settings")
    assert_equal(1, #(frame.contentHost.children or {}))
    assert_true(#(frame.contentHost.children[1].children or {}) > 0)
  end)

  it("does not leave a blank or duplicate page after repeated route refreshes", function()
    local _, dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    for _ = 1, 10 do
      frame.SelectTab("overview")
      assert_equal(1, #(frame.contentHost.children or {}))
      assert_true(#(frame.contentHost.children[1].children or {}) > 0)
      frame:Refresh()
      assert_equal(1, #(frame.contentHost.children or {}))
      assert_true(#(frame.contentHost.children[1].children or {}) > 0)
    end
  end)
end)
