local loader = require("helpers.load_addon")
local uiMocks = require("helpers.b11_ui_mocks")

local function countText(widget, text)
  if type(widget) ~= "table" then return 0 end
  local count = (tostring(widget.text or "") == text and 1 or 0)
    + (tostring(widget.label or "") == text and 1 or 0)
    + (tostring(widget.title or "") == text and 1 or 0)
  for _, child in ipairs(widget.children or {}) do count = count + countText(child, text) end
  return count
end

local function findControl(widget, label)
  if type(widget) ~= "table" then return nil end
  if widget.kind == "Dropdown" and tostring(widget.label or "") == label then return widget end
  for _, child in ipairs(widget.children or {}) do
    local found = findControl(child, label)
    if found then return found end
  end
  return nil
end

local function setup()
  return loader.load({
    wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Officer-Realm" } },
    withAce3 = true,
  })
end

describe("B11 Retail UI-004 ownership", function()
  it("passes every supported table cell value through the Retail tooltip contract", function()
    local _, dibs = setup()
    local calls = {}
    _G.GameTooltip = {
      SetOwner = function(_, owner, anchor) calls.owner = owner; calls.anchor = anchor end,
      SetText = function(_, ... ) calls.text = { ... } end,
      SetHyperlink = function(_, value) calls.hyperlink = value end,
      Show = function() calls.shown = true end,
    }

    for _, value in ipairs({ "", "Unavailable", "Tier Set", "normal text", string.rep("long text ", 40) }) do
      calls.text, calls.hyperlink, calls.shown = nil, nil, nil
      assert_true(dibs.AceGUI.ShowTableCellTooltip({}, value))
      assert_equal(value, calls.text[1])
      assert_equal(1, calls.text[2])
      assert_equal(1, calls.text[3])
      assert_equal(1, calls.text[4])
      assert_equal(1, calls.text[5])
      assert_equal(true, calls.text[6])
      assert_true(calls.shown)
    end

    calls.text, calls.hyperlink, calls.shown = nil, nil, nil
    local itemLink = "|cffa335ee|Hitem:280001::::::::::::|h[Warden's Curio]|h|r"
    assert_true(dibs.AceGUI.ShowTableCellTooltip({}, itemLink))
    assert_nil(calls.text)
    assert_equal(itemLink, calls.hyperlink)
    assert_true(calls.shown)
    assert_false(dibs.AceGUI.ShowTableCellTooltip({}, nil))
  end)

  it("keeps raw-frame parents out of AceGUI Create and releases one owned lib-st table", function()
    local _, dibs = setup()
    local shell = dibs.PlayerUI.CreateWindow().dibsAceGUIShell
    local rawFrame = _G.CreateFrame("Frame")
    assert_nil(dibs.AceGUI.Create(shell, "SimpleGroup", rawFrame))

    local tableCalls = {}
    dibs.Ace3.libs.scrollingTable = {
      SORT_ASC = 1,
      SORT_DSC = 2,
      CreateST = function(_, columns, _, _, _, parent)
        local tableFrame = _G.CreateFrame("Frame", nil, parent)
        tableFrame.ClearAllPoints = function() end
        tableCalls.parent = parent
        local scrollingTable = {
          frame = tableFrame,
          cols = columns,
          RegisterEvents = function(self, events) self.events = events end,
          SetDefaultHighlight = function() end,
          EnableSelection = function() end,
          SetDisplayCols = function() end,
          SetData = function(self, data) self.data = data end,
          SortData = function() end,
          Show = function() end,
          Hide = function(self) self.hidden = true end,
        }
        return scrollingTable
      end,
    }

    local host = dibs.AceGUI.AddTable(shell, shell.window, {
      { title = "Status", width = 120 },
    }, { { "Unavailable" } }, 100, nil, { disableContextMenu = true })
    assert_not_nil(host)
    assert_equal(host.frame, tableCalls.parent)
    assert_not_nil(host._dibsScrollingTable)
    assert_not_nil(host._dibsScrollingTable.events.OnEnter)
    dibs.AceGUI.Clear(shell.window)
    assert_nil(host._dibsScrollingTable)
  end)

  it("keeps Player and Officer trees isolated through repeated close and reopen", function()
    local _, dibs = setup()
    local player = dibs.PlayerUI.CreateWindow()
    local officer = dibs.OfficerUI.CreateWindow()
    assert_not_nil(player.aceTabs)
    assert_not_nil(officer.aceTabs)
    assert_true(player.aceTabs ~= officer.aceTabs)
    assert_true(player.dibsAceGUIShell.window ~= officer.dibsAceGUIShell.window)

    for _ = 1, 3 do
      player.SelectTab("requests")
      local playerChildCount = #(player.aceTabs.children or {})
      assert_true(playerChildCount > 0)
      player:Refresh()
      assert_equal(playerChildCount, #(player.aceTabs.children or {}))
      player.dibsAceGUIShell.window.callbacks.OnClose(player.dibsAceGUIShell.window, "OnClose")
      player = dibs.PlayerUI.CreateWindow()
      assert_not_nil(player.aceTabs)
      assert_equal("my-dibs", player.playerTab)

      officer.SelectTab("settings")
      assert_equal(1, #(officer.contentHost.children or {}))
      officer.dibsAceGUIShell.window.callbacks.OnClose(officer.dibsAceGUIShell.window, "OnClose")
      officer = dibs.OfficerUI.CreateWindow()
      assert_not_nil(officer.aceTabs)
      assert_equal("overview", officer.activeTab)
      assert_equal(1, #(officer.contentHost.children or {}))
      assert_true(player.aceTabs ~= officer.aceTabs)
    end
  end)

  it("renders Requests with live ownership diagnostics and clears the released shell", function()
    local _, dibs = setup()
    dibs.DebugLogs.entries = {}
    dibs.DebugLogs.Add = function(module, level, message)
      dibs.DebugLogs.entries[#dibs.DebugLogs.entries + 1] = { module = module, level = level, message = message }
    end
    local player = dibs.PlayerUI.CreateWindow()
    local officer = dibs.OfficerUI.CreateWindow()
    officer.SelectTab("requests")
    assert_equal("disputes", officer.activeTab)

    local sawBegin, sawEnd = false, false
    for _, entry in ipairs(dibs.DebugLogs.entries or {}) do
      if entry.module == "ui" and entry.message:find("ROUTE=requests RENDER_BEGIN", 1, true) then sawBegin = true end
      if entry.module == "ui" and entry.message:find("ROUTE=requests RENDER_END", 1, true) then
        sawEnd = entry.message:find("CONTENT_HOST=", 1, true) ~= nil
          and entry.message:find("REQUEST_COUNT=", 1, true) ~= nil
          and entry.message:find("CHILD_COUNT_AFTER=", 1, true) ~= nil
      end
    end
    assert_true(sawBegin)
    if not sawEnd then
      local messages = {}
      for _, entry in ipairs(dibs.DebugLogs.entries or {}) do messages[#messages + 1] = tostring(entry.message) end
      error("missing Requests render end: " .. table.concat(messages, " || "))
    end
    assert_true(#(officer.contentHost.children or {}) > 0)

    local oldShell = player.dibsAceGUIShell
    local oldWindow = oldShell.window
    oldWindow.callbacks.OnClose(oldWindow, "OnClose")
    assert_false(oldShell._dibsActive)
    assert_nil(oldShell.window)
    assert_nil(oldShell.frame)

    local reopenedPlayer = dibs.PlayerUI.CreateWindow()
    assert_true(reopenedPlayer.dibsAceGUIShell ~= oldShell)
    assert_true(reopenedPlayer.aceTabs ~= officer.aceTabs)
    assert_not_nil(_G.RCLootCouncil_dibsLocalDB.presentation.windows.PlayerWindowPosition)
    assert_not_nil(_G.RCLootCouncil_dibsLocalDB.presentation.windows.OfficerWindowPosition)
  end)

  it("restores each native window position once and keeps route refreshes out of positioning", function()
    local _, dibs = loader.load({
      wow = { guildLeader = true, guildMembers = { "Tester-Realm", "Officer-Realm" } },
      withAce3 = true,
      skipInitialize = true,
    })
    local previous = _G.LibStub
    local _, windowLibrary = uiMocks.installLibraries(previous)

    assert_true(dibs.AceGUI.IsAvailable())
    dibs.Initialize()
    local officer = _G.DibsOfficerFrame
    local player = _G.DibsPlayerFrame
    local initialRestores = windowLibrary.restoreCount or 0
    officer.SelectTab("requests")
    officer.SelectTab("history")
    officer.SelectTab("requests")
    assert_equal(initialRestores, windowLibrary.restoreCount or 0)
    assert_true(#(windowLibrary.registrations or {}) >= 2)
    assert_not_nil(_G.RCLootCouncil_dibsLocalDB.presentation.windows.OfficerWindowPosition)
    assert_not_nil(_G.RCLootCouncil_dibsLocalDB.presentation.windows.PlayerWindowPosition)
    assert_true(windowLibrary.registrations[1].names.prefix == nil)
    assert_true(windowLibrary.registrations[#windowLibrary.registrations].names.prefix == nil)
    assert_not_nil(windowLibrary.registrations[1].config)
    assert_not_nil(windowLibrary.registrations[#windowLibrary.registrations].config)
    assert_true(officer ~= player)
    uiMocks.clear()
  end)

  it("saves a title-region drag without restoring or clamping a valid position", function()
    local _, dibs = setup()
    local previous = _G.LibStub
    local _, windowLibrary = uiMocks.installLibraries(previous)
    local fake = {
      _point = { "BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 120, 180 },
      _width = 700, _height = 500,
      GetPoint = function(self) return unpack(self._point) end,
      ClearAllPoints = function(self) self._cleared = true end,
      SetPoint = function(self, ...) self._point = { ... } end,
      GetLeft = function() return 120 end, GetTop = function() return 680 end,
      GetWidth = function(self) return self._width end, GetHeight = function(self) return self._height end,
      GetParent = function() return _G.UIParent end, GetScale = function() return 1 end,
      GetEffectiveScale = function() return 1 end, SetMovable = function() end,
      RegisterForDrag = function() end, SetScript = function(self, name, fn) self._scripts = self._scripts or {}; self._scripts[name] = fn end,
      StartMoving = function() end, StopMovingOrSizing = function() end,
    }
    assert_true(dibs.WindowState.Register(fake, "DragPosition"))
    local restores = windowLibrary.restoreCount or 0
    fake.__secureHooks.StopMovingOrSizing[1](fake)
    assert_equal(restores, windowLibrary.restoreCount or 0)
    assert_equal(1, windowLibrary.saveCount)
    assert_not_nil(_G.RCLootCouncil_dibsLocalDB.presentation.windows.DragPosition)
    uiMocks.clear()
  end)

  it("keeps one routed page title and clears the prior title description", function()
    local _, dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    local expected = {
      overview = "Officer dashboard", preDibs = "Pre-Dibs", settings = "Settings", lootTypes = "Loot Rules",
    }
    for _, route in ipairs({ "overview", "preDibs", "settings", "lootTypes", "overview" }) do
      frame.SelectTab(route)
      assert_equal(1, countText(frame.contentHost, expected[route]))
      assert_true(countText(frame.contentHost, "Active season request mode") <= 1)
      assert_false(countText(frame.contentHost, "Pre-Dibs") > 1)
    end
  end)

  it("keeps exactly one current header through Guild Rules and Pre-Dibs routes", function()
    local _, dibs = setup()
    local frame = dibs.OfficerUI.CreateWindow()
    local expected = {
      overview = "Officer dashboard",
      seasons = "Seasons",
      ranks = "Rank Rules",
      preDibs = "Pre-Dibs",
      settings = "Settings",
    }
    local descriptions = {
      overview = "Guild-wide operational summary for authorized Officers and GM.",
      preDibs = "Officer controls and current local projection.",
    }
    for _, route in ipairs({ "overview", "seasons", "ranks", "preDibs", "settings" }) do
      frame.SelectTab(route)
      assert_equal(1, countText(frame.contentHost, expected[route]))
      for previousRoute, title in pairs(expected) do
        if previousRoute ~= route then assert_equal(0, countText(frame.contentHost, title), previousRoute) end
      end
      local descriptionCount = 0
      for _, description in pairs(descriptions) do descriptionCount = descriptionCount + countText(frame.contentHost, description) end
      assert_true(descriptionCount <= 1, route)
    end
  end)

  it("passes canonical Pre-Dib and enum dropdown keys to services", function()
    local _, dibs = setup()
    local captured = {}
    local originalExecute = dibs.ProtectedActions.Execute
    dibs.ProtectedActions.Execute = function(actionId, actor, payload)
      captured[#captured + 1] = { actionId = actionId, payload = payload }
      return { ok = true, value = payload }
    end
    local frame = dibs.OfficerUI.CreateWindow()
    frame.SelectTab("preDibs")
    local options = dibs.RCOptions.GetOptionsTable()
    local mode = options.args.dibsSettings.args.officer.args.preDibs.args.mode
    mode.set(nil, "Wild Open")
    mode.set(nil, "Encounter")
    mode.set(nil, "not-a-mode")
    assert_equal("WILD_OPEN", captured[1].payload.mode)
    assert_equal("ENCOUNTER", captured[2].payload.mode)
    assert_equal(2, #captured)
    assert_false(captured[1].payload.mode == "Wild Open")
    assert_false(captured[2].payload.mode == "Encounter")
    local dropdown = dibs.AceGUI.AddDropdown(frame.dibsAceGUIShell, frame.contentHost, "Channel", { GUILD = "Guild" }, function(value)
      captured.channel = value
    end, 180, false)
    dropdown.callbacks.OnValueChanged(dropdown, "OnValueChanged", "Guild")
    assert_equal("GUILD", captured.channel)
    dibs.ProtectedActions.Execute = originalExecute
  end)
end)
