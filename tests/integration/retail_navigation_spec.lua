local loader = require("helpers.load_addon")

local function setup(options)
  options = options or {}
  options.withAce3 = true
  options.wow = options.wow or { guildLeader = true }
  local _, dibs = loader.load(options)
  return dibs
end

local function containsText(widget, text)
  if type(widget) ~= "table" then return false end
  if tostring(widget.text or widget.label or ""):find(text, 1, true) then return true end
  for _, child in ipairs(widget.children or {}) do
    if containsText(child, text) then return true end
  end
  return false
end

local function findText(widget, text)
  if type(widget) ~= "table" then return nil end
  if tostring(widget.text or "") == text then return widget end
  for _, child in ipairs(widget.children or {}) do
    local found = findText(child, text)
    if found then return found end
  end
  return nil
end

describe("Retail Officer navigation lifecycle", function()
  it("mounts Dashboard immediately when opened directly", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow("overview")
    assert_equal("overview", frame.selectedRoute)
    assert_equal("overview", frame.mountedPage)
    assert_true(#(frame.contentHost.children[1].children or {}) > 0)
  end)

  it("mounts Requests immediately through its public route alias", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow("requests")
    assert_equal("disputes", frame.selectedRoute)
    assert_equal("disputes", frame.mountedPage)
    assert_true(containsText(frame.contentHost, "Officer review requests"))
    assert_true(#(frame.contentHost.children[1].children or {}) > 0)
  end)

  it("mounts Pre-Dibs immediately when opened directly", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow("preDibs")
    assert_equal("preDibs", frame.selectedRoute)
    assert_equal("preDibs", frame.mountedPage)
    assert_true(#(frame.contentHost.children[1].children or {}) > 0)
  end)

  it("keeps the initial TreeGroup selection aligned with the mounted page", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow("requests")
    assert_equal("disputes", frame._dibsTreeRoute)
    assert_equal(frame.selectedRoute, frame.mountedPage)
    assert_true(frame.routeDispatchCount >= 1)
  end)

  it("does not require a second navigation event for the initial route", function()
    local dibs = setup()
    local before = dibs.OfficerUI.CreateWindow().routeDispatchCount
    local frame = dibs.OfficerUI.CreateWindow("requests")
    assert_equal(before + 1, frame.routeDispatchCount)
    assert_true(containsText(frame.contentHost, "Officer review requests"))
  end)

  it("keeps Requests and Pre-Dibs mounted across direct route transitions", function()
    local dibs = setup()
    local before = dibs.OfficerUI.CreateWindow().routeDispatchCount
    local frame = dibs.OfficerUI.CreateWindow("requests")
    frame.SelectTab("preDibs")
    assert_equal("preDibs", frame.mountedPage)
    frame.SelectTab("requests")
    assert_equal("disputes", frame.mountedPage)
    assert_true(containsText(frame.contentHost, "Officer review requests"))
    assert_equal(before + 3, frame.routeDispatchCount)
  end)

  it("does not leave Pre-Dibs announcement controls in Requests", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow("preDibs")
    assert_true(containsText(frame.contentHost, "Officer pre-dib announce channel"))
    frame.SelectTab("requests")
    assert_true(containsText(frame.contentHost, "Officer review requests"))
    assert_false(containsText(frame.contentHost, "Officer pre-dib announce channel"))
  end)

  it("mounts the first page after leaving Announcements without stale route controls", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow("announcements")
    assert_true(containsText(frame.contentHost, "Public pre-dib announce channel"))
    frame.SelectTab("history")
    assert_true(containsText(frame.contentHost, "Target season"))
    assert_false(containsText(frame.contentHost, "Officer pre-dib announce channel"))
    frame.SelectTab("requests")
    assert_true(containsText(frame.contentHost, "Officer review requests"))
    assert_false(containsText(frame.contentHost, "Target season"))
    frame.SelectTab("preDibs")
    assert_true(containsText(frame.contentHost, "Active season request mode"))
    assert_false(containsText(frame.contentHost, "Target season"))
  end)

  it("lays out Requests and History during their first TreeGroup selection", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow("overview")
    local layoutCalls = 0
    local originalDoLayout = frame.aceTabs.DoLayout
    frame.aceTabs.DoLayout = function(self)
      layoutCalls = layoutCalls + 1
      if originalDoLayout then originalDoLayout(self) end
    end
    local callback = frame.aceTabs.callbacks.OnGroupSelected
    local separator = string.char(1)

    callback(frame.aceTabs, "OnGroupSelected", "section_dibs" .. separator .. "disputes")
    assert_true(containsText(frame.contentHost, "Officer review requests"))
    assert_true(layoutCalls > 0)

    local callsAfterRequests = layoutCalls
    callback(frame.aceTabs, "OnGroupSelected", "section_dibs" .. separator .. "history")
    assert_true(containsText(frame.contentHost, "RCLootCouncil History"))
    assert_true(layoutCalls > callsAfterRequests)
  end)

  it("reopens directly on Requests without a blank page", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow("requests")
    frame.dibsAceGUIShell.window.callbacks.OnClose(frame.dibsAceGUIShell.window, "OnClose")
    local reopened = dibs.OfficerUI.CreateWindow("requests")
    assert_equal("disputes", reopened.selectedRoute)
    assert_equal("disputes", reopened.mountedPage)
    assert_true(containsText(reopened.contentHost, "Officer review requests"))
  end)

  it("opens Requests immediately after a fresh addon load", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow("requests")
    assert_equal("disputes", frame.mountedPage)
    assert_true(#(frame.contentHost.children[1].children or {}) > 0)
  end)

  it("does not double-dispatch when synchronizing the TreeGroup selection", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    local before = frame.routeDispatchCount
    frame.SelectTab("requests")
    assert_equal(before + 1, frame.routeDispatchCount)
    assert_equal("disputes", frame.mountedPage)
  end)

  it("selects grouped Officer routes by value so the DIBS section opens", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    local selectedByValue
    local selectedDirectly
    frame.aceTabs.SelectByValue = function(_, value)
      selectedByValue = value
    end
    frame.aceTabs.Select = function(_, value)
      selectedDirectly = value
    end

    frame.SelectTab("requests")

    assert_equal("section_dibs" .. string.char(1) .. "disputes", selectedByValue)
    assert_nil(selectedDirectly)
  end)

  it("never leaves a blank page root for a valid initial route", function()
    local dibs = setup()
    for _, route in ipairs({ "overview", "requests", "preDibs", "history", "seasons", "ranks", "lootTypes", "announcements", "integration", "settings", "diagnostics", "eligibility" }) do
      local frame = dibs.OfficerUI.CreateWindow(route)
      assert_equal(1, #(frame.contentHost.children or {}), route)
      assert_true(#(frame.contentHost.children[1].children or {}) > 0, route)
      frame.dibsAceGUIShell.window.callbacks.OnClose(frame.dibsAceGUIShell.window, "OnClose")
    end
  end)

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

  it("releases the previous page before mounting the next page", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("history")
    assert_true(containsText(frame.contentHost, "History reconciliation"))
    local previousPage = frame.contentHost.children[1]
    frame.SelectTab("debug")
    assert_false(containsText(frame.contentHost, "History reconciliation"))
    assert_false(previousPage.frame._shown)
    assert_equal(1, #(frame.contentHost.children or {}))
  end)

  it("keeps History-owned content out of Settings, Eligibility, and Debug", function()
    local dibs = setup()
    dibs.DeveloperMode.SetEnabled(true)
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("history")
    assert_true(containsText(frame.contentHost, "History reconciliation"))
    for _, route in ipairs({ "settings", "eligibility", "debug" }) do
      frame.SelectTab(route)
      assert_false(containsText(frame.contentHost, "History reconciliation"), route)
      assert_false(containsText(frame.contentHost, "Historical DIB transfer"), route)
    end
  end)

  it("fully releases Seasons-owned content across the Retail route sequence", function()
    local dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    local sequence = { "overview", "preDibs", "seasons", "ranks", "lootTypes", "settings", "eligibility", "overview" }
    for cycle = 1, 10 do
      for _, route in ipairs(sequence) do
        frame.SelectTab(route)
        assert_equal(1, #(frame.contentHost.children or {}), route)
        local pageRoot = frame.contentHost.children[1]
        assert_equal(route, pageRoot._dibsRoute, route)
        assert_equal(route, frame.mountedPage, route)
        assert_equal(pageRoot, frame.contentHost._dibsCurrentPageRoot)
        for _, child in ipairs(frame.contentHost.children or {}) do
          assert_equal(route, child._dibsRoute, "unexpected routed page survived: " .. route)
        end
        if route ~= "seasons" then
          assert_false(containsText(frame.contentHost, "New season name"), route)
          assert_false(containsText(frame.contentHost, "Rename selected to"), route)
        end
      end
    end
  end)

  it("activates the sandbox through the Developer page button without granting a role", function()
    local dibs = setup()
    dibs.DeveloperMode.SetEnabled(true)
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("developer")
    local button = findText(frame.contentHost, "Open developer sandbox")
    assert_true(button ~= nil)
    button.callbacks.OnClick(button, "OnClick")
    local status = dibs.DeveloperSandbox.GetStatus()
    assert_true(status.active)
    assert_equal("sandbox", status.provider)
    assert_equal(nil, status.role)
    assert_true(containsText(frame.contentHost, "DEVELOPER SANDBOX ACTIVE"))
    assert_true(containsText(frame.contentHost, "Simulated authority: none"))
    dibs.DeveloperSandbox.ExitSandbox()
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