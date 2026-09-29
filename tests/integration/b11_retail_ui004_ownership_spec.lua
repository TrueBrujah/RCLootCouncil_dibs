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

local function findWidget(widget, predicate)
  if type(widget) ~= "table" then return nil end
  if predicate(widget) then return widget end
  for _, child in ipairs(widget.children or {}) do
    local found = findWidget(child, predicate)
    if found then return found end
  end
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

  it("keeps raw-frame parents out of AceGUI Create and renders the shared Data Grid", function()
    local _, dibs = setup()
    local shell = dibs.PlayerUI.CreateWindow().dibsAceGUIShell
    local rawFrame = _G.CreateFrame("Frame")
    assert_nil(dibs.AceGUI.Create(shell, "SimpleGroup", rawFrame))

    local parent = dibs.AceGUI.Create(shell, "SimpleGroup", shell.window)
    local host = dibs.AceGUI.AddTable(shell, parent, {
      { title = "Status", width = 120 },
    }, { { "Unavailable" } }, 100, nil, { noScrolling = true, headerParent = parent })
    assert_not_nil(host)
    assert_equal(parent, host)
    assert_not_nil(host._dibsDataGrid)
    assert_true(#parent.children > 0)
  end)

  it("sizes shared-grid action columns for localized labels", function()
    local _, dibs = setup()
    local shell = dibs.PlayerUI.CreateWindow().dibsAceGUIShell
    local parent = dibs.AceGUI.Create(shell, "SimpleGroup", shell.window)

    local columns = {
      { title = "Player", width = 150, minWidth = 50, priority = 1 },
      { title = "Action", width = 48, minWidth = 48, action = true },
    }
    dibs.AceGUI.AddTable(shell, parent, columns, { { "Tester-Realm" } }, 100, function()
      return { text = "RAPPROCHER", callback = function() end }
    end, { noScrolling = true, widthHint = 232 })

    local requiredActionWidth = dibs.AceGUI.GetContentSizedActionWidth({ "RAPPROCHER" }, 48)
    assert_true(columns[2].width >= requiredActionWidth)
  end)

  it("keeps the shared grid empty state explicit", function()
    local _, dibs = setup()
    local shell = dibs.PlayerUI.CreateWindow().dibsAceGUIShell
    local parent = dibs.AceGUI.Create(shell, "SimpleGroup", shell.window)
    dibs.AceGUI.AddTable(shell, parent, { { title = "Status", width = 120 } }, {}, nil, nil, {
      noScrolling = true, emptyText = "No entries",
    })
    assert_equal(1, countText(parent, "No entries"))
  end)

  it("sorts rows, selects once, opens row menus, and releases grid handlers", function()
    local _, dibs = setup()
    local msaNames = {
      "MSA_DropDownMenu_Create", "MSA_DropDownMenu_Initialize", "MSA_DropDownMenu_CreateInfo",
      "MSA_DropDownMenu_AddButton", "MSA_ToggleDropDownMenu", "MSA_DropDownMenu_SetText",
      "MSA_DropDownMenu_SetWidth", "MSA_DropDownMenu_JustifyText", "MSA_DropDownMenu_SetSelectedValue",
    }
    local previousMSA = {}
    for _, name in ipairs(msaNames) do previousMSA[name] = _G[name] end
    local menuState = uiMocks.installMSA()
    local menuFrame
    local menuEntries = {}
    local createMenu = _G.MSA_DropDownMenu_Create
    local addMenuButton = _G.MSA_DropDownMenu_AddButton
    _G.MSA_DropDownMenu_Create = function(name, parent)
      menuFrame = createMenu(name, parent)
      return menuFrame
    end
    _G.MSA_DropDownMenu_AddButton = function(info) menuEntries[#menuEntries + 1] = info end
    local shell = dibs.PlayerUI.CreateWindow().dibsAceGUIShell
    local parent = dibs.AceGUI.Create(shell, "SimpleGroup", shell.window)
    local header = dibs.AceGUI.Create(shell, "SimpleGroup", shell.window)
    local rows = { { "Bravo", "10" }, { "Alpha", "2" } }
    local clickCount = 0
    local grid = dibs.AceGUI.AddTable(shell, parent, {
      { title = "Name", width = 120, weight = 2 }, { title = "Score", width = 60, fixed = true },
    }, rows, 180, nil, {
      noScrolling = true, fluidColumns = true, headerParent = header,
      contextMenu = function()
        return { { text = "Inspect", callback = function() end } }
      end,
      onRowClick = function() clickCount = clickCount + 1 end,
    })
    local nameHeader = findWidget(header, function(widget) return widget.kind == "Button" and widget.text == "Name" end)
    assert_not_nil(nameHeader)
    nameHeader.callbacks.OnClick()
    assert_equal("Bravo", grid._dibsDataGrid.rows[1][1])
    nameHeader.callbacks.OnClick()
    assert_equal("Alpha", grid._dibsDataGrid.rows[1][1])

    local alphaCell = findWidget(parent, function(widget) return widget.text == "Alpha" end)
    assert_not_nil(alphaCell)
    alphaCell.frame._scripts.OnMouseUp(alphaCell.frame, "LeftButton")
    assert_equal(rows[2], grid._dibsDataGrid.selectedRow)
    assert_equal(1, clickCount)
    local originalWidth = alphaCell._dibsColumnWidth
    local contextOpened = alphaCell.frame._scripts.OnMouseUp(alphaCell.frame, "RightButton")
    local menuShown = menuState.shown > 0
    if menuFrame and menuFrame._initialize then menuFrame._initialize(menuFrame, 1) end
    for _, name in ipairs(msaNames) do _G[name] = previousMSA[name] end
    assert_true(contextOpened)
    assert_true(menuShown)
    local sortEntry
    for _, entry in ipairs(menuEntries) do
      if entry.text == "Name (A-Z)" then sortEntry = entry end
    end
    assert_not_nil(sortEntry)
    sortEntry.func()
    assert_equal("Alpha", grid._dibsDataGrid.rows[1][1])
    shell.frame._scripts.OnSizeChanged(shell.frame, 800, 500)
    assert_true(alphaCell._dibsColumnWidth > originalWidth)

    dibs.AceGUI.Clear(parent)
    assert_nil(alphaCell.frame._scripts.OnMouseUp)
  end)

  it("shows header, status, and full item-link tooltips from grid cells", function()
    local _, dibs = setup()
    local shell = dibs.PlayerUI.CreateWindow().dibsAceGUIShell
    local parent = dibs.AceGUI.Create(shell, "SimpleGroup", shell.window)
    local header = dibs.AceGUI.Create(shell, "SimpleGroup", shell.window)
    local previousTooltip = _G.GameTooltip
    local tooltip = { lines = {} }
    function tooltip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
    function tooltip:SetText(value) self.title = value end
    function tooltip:AddLine(value) self.lines[#self.lines + 1] = value end
    function tooltip:SetHyperlink(value) self.hyperlink = value end
    function tooltip:Show() self.shown = true end
    function tooltip:Hide() self.shown = false end
    _G.GameTooltip = tooltip

    local itemLink = "|cffa335ee|Hitem:280001::::::::::::|h[Warden's Curio]|h|r"
    dibs.AceGUI.AddTable(shell, parent, {
      { title = "Item", width = 180, tooltip = "The awarded item." },
      { title = "Status", width = 100, tooltip = "Current review state." },
    }, { { itemLink, "Ready" } }, 120, nil, {
      noScrolling = true, headerParent = header, allowTableSort = false,
    })
    local itemHeader = findWidget(header, function(widget) return widget.text == "Item" end)
    local itemCell = findWidget(parent, function(widget) return widget.text == itemLink end)
    local statusCell = findWidget(parent, function(widget) return widget.text == "Ready" end)
    if itemHeader and itemHeader.frame._scripts.OnEnter then itemHeader.frame._scripts.OnEnter(itemHeader.frame) end
    local headerTitle, headerLine = tooltip.title, tooltip.lines[1]
    if itemCell and itemCell.frame._scripts.OnEnter then itemCell.frame._scripts.OnEnter(itemCell.frame) end
    local itemHyperlink = tooltip.hyperlink
    if statusCell and statusCell.frame._scripts.OnEnter then statusCell.frame._scripts.OnEnter(statusCell.frame) end
    local statusTitle, statusLine = tooltip.title, tooltip.lines[#tooltip.lines]
    _G.GameTooltip = previousTooltip
    assert_not_nil(itemHeader)
    assert_not_nil(itemCell)
    assert_not_nil(statusCell)
    assert_equal("Item", headerTitle)
    assert_equal("The awarded item.", headerLine)
    assert_equal(itemLink, itemHyperlink)
    assert_equal("Ready", statusTitle)
    assert_equal("Current review state.", statusLine)
  end)

  it("shows help details from a compact question-mark button", function()
    local _, dibs = setup()
    local shell = dibs.PlayerUI.CreateWindow().dibsAceGUIShell
    local previousTooltip = _G.GameTooltip
    local tooltip = { lines = {} }
    function tooltip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
    function tooltip:SetText(text) self.title = text end
    function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tooltip:Show() self.shown = true end
    _G.GameTooltip = tooltip

    local help = dibs.AceGUI.AddHelpButton(shell, shell.window, "Date range", "Select optional start and end dates.")
    assert_equal("?", help.text)
    help.frame._scripts.OnEnter(help.frame)
    assert_equal("Date range", tooltip.title)
    assert_equal("Select optional start and end dates.", tooltip.lines[1])
    assert_true(tooltip.shown)
    _G.GameTooltip = previousTooltip
  end)

  it("uses the shared select API and releases its dropdown help", function()
    local _, dibs = setup()
    local shell = dibs.AceGUI.CreateWindow("Select test", 520, 360)
    local previousTooltip = _G.GameTooltip
    local tooltip = { lines = {} }
    function tooltip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
    function tooltip:SetText(value) self.title = value end
    function tooltip:AddLine(value) self.lines[#self.lines + 1] = value end
    function tooltip:Show() self.shown = true end
    function tooltip:Hide() self.shown = false end
    _G.GameTooltip = tooltip

    local changed
    local suppliedValues = {
      all = "All statuses", current = "Needs Reconciliation",
    }
    local select = dibs.AceGUI.AddDibsSelect(shell, shell.window, "Status", suppliedValues,
      function(value) changed = value end, 180, {
      value = "current", tooltip = "Filters the current roster only.",
    })
    assert_not_nil(select)
    assert_equal("current", select:GetValue())
    assert_equal("Needs Reconciliation", select:GetText())
    assert_equal("Status", select._dibsSelectLabel)
    local replacementValues = { all = "Every status", current = "Needs reconciliation" }
    select:SetList(replacementValues)
    assert_equal("All statuses", suppliedValues.all)
    assert_equal("Needs Reconciliation", suppliedValues.current)
    assert_equal("current", select:GetValue())
    assert_equal("Needs reconciliation", select:GetText())
    select:SetList(suppliedValues)
    assert_equal("current", select:GetValue())
    assert_equal("Needs Reconciliation", select:GetText())

    local trigger = select._dibsMSAControl or select.frame
    local menu = select._dibsSelectWrapper or select
    menu.callbacks.OnValueChanged(menu, "OnValueChanged", "all")
    assert_equal("all", changed)
    assert_equal("All statuses", select:GetText())

    select:SetDisabled(true)
    assert_true(select.disabled)
    select:SetDisabled(false)
    select:SetReadOnly(true)
    assert_true(select.disabled)

    local tooltipFrame = select._dibsTooltipFrame or select.frame
    tooltipFrame._scripts.OnEnter(tooltipFrame)
    assert_equal("Status", tooltip.title)
    assert_equal("Filters the current roster only.", tooltip.lines[1])

    select:SetReadOnly(false)
    dibs.AceGUI.Clear(shell.window)
    assert_nil(select._dibsTooltipAttachment)
    assert_false(tooltip.shown)
    _G.GameTooltip = previousTooltip
  end)

  it("uses AceGUI dropdown widgets even when MSA is available", function()
    local msaNames = {
      "MSA_DropDownMenu_Create", "MSA_DropDownMenu_Initialize", "MSA_DropDownMenu_CreateInfo",
      "MSA_DropDownMenu_AddButton", "MSA_ToggleDropDownMenu", "MSA_DropDownMenu_SetText",
      "MSA_DropDownMenu_GetText", "MSA_DropDownMenu_SetWidth", "MSA_DropDownMenu_JustifyText",
      "MSA_DropDownMenu_SetSelectedValue", "MSA_DropDownMenu_ClearAll",
    }
    local previous = {}
    for _, name in ipairs(msaNames) do previous[name] = _G[name] end
    local msaState = uiMocks.installMSA()

    local _, dibs = setup()
    local shell = dibs.AceGUI.CreateWindow("MSA select test", 520, 360)
    local ordinary = dibs.AceGUI.AddDropdown(shell, shell.window, "Ordinary", { all = "All" }, nil, 180)
    local select = dibs.AceGUI.AddDibsSelect(shell, shell.window, "Status", {
      all = "All statuses", current = "Needs Reconciliation",
    }, nil, 180, { value = "current" })
    assert_equal("Dropdown", ordinary.kind)
    assert_not_nil(select)
    assert_equal("Dropdown", select.kind)
    assert_nil(select._dibsMSAControl)
    assert_equal(0, msaState.created)
    assert_equal(0, #select.children)
    assert_equal("current", select:GetValue())
    assert_equal("Needs Reconciliation", select:GetText())
    select:SetValue("all")
    assert_equal("All statuses", select:GetText())

    dibs.AceGUI.Clear(shell.window)
    for _, name in ipairs(msaNames) do _G[name] = previous[name] end
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
      GetPoint = function(self) return self._point[1], self._point[2], self._point[3], self._point[4], self._point[5] end,
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
