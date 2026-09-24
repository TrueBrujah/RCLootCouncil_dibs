--[[
Module: Dibs.AceGUI
Layer: UI toolkit adapter
Purpose: Provide consistent AceGUI container, table, and action helpers.
Responsibilities: Widget construction, scrolling tables, safe callbacks, and layout sizing.
Non-responsibilities: It does not decide business policy or persist data.
Dependencies: AceGUI-3.0, ScrollingTable, Dibs.Ace3.
Blizzard events: None directly.
Internal events/messages: Widget callbacks to owning UI controllers.
SavedVariables: None directly.
RCLootCouncil: Supports the options projection but is otherwise independent.
Combat safety: Frame creation and mutation must be deferred outside combat lockdown.
Related docs: docs/developer/architecture.md, docs/developer/combat-safety.md.
]]

local Dibs = _G.Dibs
Dibs.AceGUI = Dibs.AceGUI or {}

local Adapter = Dibs.AceGUI
local unpackValues = table.unpack or unpack
local LOGO_TEXTURE = Dibs.ICON_TEXTURE or "Interface\\AddOns\\RCLootCouncil_dibs\\media\\RCLootCouncil_Dibs_Logo"

Adapter.windowShellEnabled = true

local function getLibrary()
  if Dibs.Ace3 and Dibs.Ace3.libs and Dibs.Ace3.libs.gui then
    return Dibs.Ace3.libs.gui
  end
  if _G.LibStub == nil then return nil end
  local ok, library = pcall(_G.LibStub, "AceGUI-3.0", true)
  return ok and library or nil
end

-- MSA-DropDownMenu is considerably lighter than creating a full AceGUI
-- Dropdown widget for every small choice. Keep a runtime check so reduced
-- test clients and older installations continue to use the AceGUI fallback.
local HAS_MSA_DROPDOWN = type(_G.MSA_DropDownMenu_Create) == "function"
  and type(_G.MSA_DropDownMenu_Initialize) == "function"
  and type(_G.MSA_DropDownMenu_CreateInfo) == "function"
  and type(_G.MSA_DropDownMenu_AddButton) == "function"
  and type(_G.MSA_DropDownMenu_SetText) == "function"
local msaDropdownSerial = 0
local msaDropdownPool = {}
local contextMenuSerial = 0
local contextMenuFrame
local refreshState = { queued = false, dirty = false, callbacks = {} }

function Adapter.HideContextMenu()
  if type(_G.MSA_CloseDropDownMenus) == "function" then
    pcall(_G.MSA_CloseDropDownMenus)
  end
  if contextMenuFrame and type(contextMenuFrame.Hide) == "function" then
    pcall(contextMenuFrame.Hide, contextMenuFrame)
  end
  if _G.GameTooltip and type(_G.GameTooltip.Hide) == "function" then
    pcall(_G.GameTooltip.Hide, _G.GameTooltip)
  end
end

local function runRefreshes(reason)
  refreshState.queued = false
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return false end
  if not refreshState.dirty then return true end
  refreshState.dirty = false
  local callbacks = refreshState.callbacks
  refreshState.callbacks = {}
  for _, pending in ipairs(callbacks) do pcall(pending, reason) end
  return true
end

local function getScrollingTable()
  if Dibs.Ace3 and Dibs.Ace3.libs and Dibs.Ace3.libs.scrollingTable then
    return Dibs.Ace3.libs.scrollingTable
  end
  if type(_G.LibStub) == "function" or type(_G.LibStub) == "table" then
    local ok, library = pcall(_G.LibStub, "ScrollingTable", true)
    if ok and library then return library end
  end
  return nil
end

local function call(widget, method, ...)
  if widget and type(widget[method]) == "function" then
    return pcall(widget[method], widget, ...)
  end
  return false
end

function Adapter.GetLayoutMetrics()
  if Dibs.Midnight and type(Dibs.Midnight.GetLayoutMetrics) == "function" then
    return Dibs.Midnight.GetLayoutMetrics()
  end
  return { minWidth = 520, minHeight = 360, maxWidth = 1400, maxHeight = 1100, actionMinWidth = 88, rowHeight = 24 }
end

function Adapter.FitColumnWidths(columns, availableWidth)
  local definitions = columns or {}
  local widths, minimums, priorities = {}, {}, {}
  local total = 0
  for index, column in ipairs(definitions) do
    local width = math.max(48, tonumber(column.width) or 100)
    local minimum = math.max(48, tonumber(column.minWidth) or (column.action and Adapter.GetLayoutMetrics().actionMinWidth or 48))
    widths[index], minimums[index] = math.max(width, minimum), minimum
    priorities[index] = tonumber(column.priority) or (column.action and 100 or 1)
    total = total + widths[index]
  end
  local available = tonumber(availableWidth) or total
  if total <= available then return widths, false end

  local order = {}
  for index = 1, #definitions do order[#order + 1] = index end
  table.sort(order, function(left, right) return priorities[left] < priorities[right] end)
  local deficit = total - available
  for _, index in ipairs(order) do
    if deficit <= 0 then break end
    local reducible = widths[index] - minimums[index]
    if reducible > 0 then
      local reduction = math.min(reducible, deficit)
      widths[index] = widths[index] - reduction
      deficit = deficit - reduction
    end
  end
  return widths, deficit > 0
end

local function applyRCLootCouncilTheme(frame)
  if not frame then return end
  if type(frame.SetBackdropColor) == "function" then
    frame:SetBackdropColor(0.035, 0.055, 0.065, 0.96)
  end
  if type(frame.SetBackdropBorderColor) == "function" then
    frame:SetBackdropBorderColor(0.62, 0.52, 0.22, 1)
  end
end

function Adapter.GetPresentationTokens()
  if Dibs.EnvironmentAdapters and Dibs.EnvironmentAdapters.ResolveTokens then
    local ok, tokens = pcall(Dibs.EnvironmentAdapters.ResolveTokens)
    if ok and type(tokens) == "table" then return tokens end
  end
  return Dibs.Midnight and Dibs.Midnight.GetTokens and Dibs.Midnight.GetTokens() or nil
end

function Adapter.RequestRefresh(reason, callback)
  refreshState.dirty = true
  if type(callback) == "function" then refreshState.callbacks[#refreshState.callbacks + 1] = callback end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return false end
  if refreshState.queued then return true end
  refreshState.queued = true
  local flush = function() runRefreshes(reason) end
  if Dibs.Ace3 and Dibs.Ace3.ScheduleTimer then Dibs.Ace3.ScheduleTimer(flush, 0) elseif _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0, flush) else flush() end
  return true
end

function Adapter.FlushRefreshes()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return false end
  return runRefreshes("POST_COMBAT")
end

local function addAddonLogo(frame)
  if not frame or type(frame.CreateTexture) ~= "function" then return nil end
  local texture = frame:CreateTexture(nil, "ARTWORK")
  if not texture then return nil end
  if type(texture.SetTexture) == "function" then texture:SetTexture(LOGO_TEXTURE) end
  if type(texture.SetTexCoord) == "function" then texture:SetTexCoord(0.04, 0.96, 0.04, 0.96) end
  if type(texture.SetSize) == "function" then texture:SetSize(30, 30) end
  if type(texture.SetPoint) == "function" then texture:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -7) end
  frame.dibsLogoTexture = texture
  return texture
end

function Adapter.IsAvailable()
  local gui = getLibrary()
  return gui ~= nil and type(gui.Create) == "function"
end

function Adapter.CreateWindow(title, width, height, point, positionId)
  if Adapter.windowShellEnabled ~= true then return nil end
  local gui = getLibrary()
  if not gui or type(gui.Create) ~= "function" then return nil end

  local ok, window = pcall(gui.Create, gui, "Frame")
  if not ok or type(window) ~= "table" or not window.frame then return nil end

  local metrics = Adapter.GetLayoutMetrics()
  local requestedWidth = tonumber(width) or metrics.minWidth
  local requestedHeight = tonumber(height) or metrics.minHeight
  local windowWidth = math.max(metrics.minWidth, math.min(metrics.maxWidth, requestedWidth))
  local windowHeight = math.max(metrics.minHeight, math.min(metrics.maxHeight, requestedHeight))
  call(window, "SetTitle", title)
  call(window, "SetWidth", windowWidth)
  call(window, "SetHeight", windowHeight)
  window.layout = {
    width = windowWidth, height = windowHeight,
    minWidth = metrics.minWidth, minHeight = metrics.minHeight,
    maxWidth = metrics.maxWidth, maxHeight = metrics.maxHeight,
  }
  -- AceGUI Frame widgets expose the native frame; keep resizing optional for
  -- older clients while enabling it on current Retail clients.
  if window.frame and type(window.frame.SetResizable) == "function" then
    window.frame:SetResizable(true)
    if type(window.frame.SetResizeBounds) == "function" then
      window.frame:SetResizeBounds(metrics.minWidth, metrics.minHeight, metrics.maxWidth, metrics.maxHeight)
    elseif type(window.frame.SetMinResize) == "function" then
      window.frame:SetMinResize(metrics.minWidth, metrics.minHeight)
    end
    if type(window.frame.CreateTexture) == "function" and type(window.frame.CreateFontString) == "function" then
      local grip = window.frame:CreateTexture(nil, "OVERLAY")
      grip:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
      grip:SetSize(16, 16)
      grip:SetPoint("BOTTOMRIGHT", -3, 3)
      local gripButton = CreateFrame("Button", nil, window.frame)
      gripButton:SetSize(24, 24)
      gripButton:SetPoint("BOTTOMRIGHT", 0, 0)
      gripButton:SetFrameLevel((window.frame.GetFrameLevel and window.frame:GetFrameLevel() or 1) + 20)
      gripButton:SetScript("OnMouseDown", function() if window.frame.StartSizing then window.frame:StartSizing("BOTTOMRIGHT") end end)
      gripButton:SetScript("OnMouseUp", function() if window.frame.StopMovingOrSizing then window.frame:StopMovingOrSizing() end end)
    end
  end
  call(window, "SetLayout", "Fill")
  window.layout = {
    width = windowWidth, height = windowHeight,
    minWidth = metrics.minWidth, minHeight = metrics.minHeight,
    maxWidth = metrics.maxWidth, maxHeight = metrics.maxHeight,
  }
  local tokens = Adapter.GetPresentationTokens()
  if Dibs.Midnight and tokens then Dibs.Midnight.ApplyToFrame(window.frame, tokens) else applyRCLootCouncilTheme(window.frame) end
  -- AceGUI's stock Window uses FULLSCREEN_DIALOG, which makes an Officer or
  -- Player window behave like a modal Settings page. Dibs windows are modeless
  -- control surfaces, so keep them above the game while allowing other panels
  -- to remain accessible beside them.
  if window.frame and type(window.frame.SetFrameStrata) == "function" then
    window.frame:SetFrameStrata("DIALOG")
  end
  addAddonLogo(window.frame)
  -- AceGUI Frame widgets are shown by OnAcquire.  PlayerUI and OfficerUI are
  -- created during addon initialization, so leave them hidden until the user
  -- explicitly opens a window; otherwise their FULLSCREEN_DIALOG frame can
  -- intercept clicks in Blizzard/RCLootCouncil Settings underneath it.
  call(window, "Hide")
  if point and window.frame.SetPoint then
    if window.frame.ClearAllPoints then window.frame:ClearAllPoints() end
    window.frame:SetPoint(unpackValues(point))
  end
  if Dibs.WindowState and Dibs.WindowState.Register then
    Dibs.WindowState.Register(window.frame, tostring(positionId or title or "DibsWindow"))
  end
  -- Children are owned by their AceGUI container.  Do not mirror every page
  -- widget in the shell: Refresh() releases and recreates those widgets, and
  -- a tracking array would retain the historical numeric slots forever.
  local shell = { gui = gui, window = window, frame = window.frame, layout = window.layout, _dibsActive = true }
  window.frame._dibsWindowShell = shell
  shell._dibsResizeHandlers = {}
  shell._dibsResponsiveScrolls = {}
  function shell:AddResizeHandler(callback)
    if type(callback) ~= "function" then return false end
    self._dibsResizeHandlers[#self._dibsResizeHandlers + 1] = callback
    return true
  end
  if window.frame and type(window.frame.HookScript) == "function" and not window.frame._dibsSizeHookInstalled then
    window.frame._dibsSizeHookInstalled = true
    window.frame:HookScript("OnSizeChanged", function(frame)
      local activeShell = frame._dibsWindowShell
      if not activeShell or not activeShell._dibsActive then return end
      local activeWindow = activeShell.window
      local height = frame.GetHeight and frame:GetHeight() or nil
      if height then
        for _, scroll in ipairs(activeShell._dibsResponsiveScrolls) do
          if scroll and scroll.SetHeight and scroll._dibsResizeOffset then
            scroll:SetHeight(math.max(120, height - scroll._dibsResizeOffset))
          end
          if scroll and scroll.DoLayout then scroll:DoLayout() end
        end
      end
      if activeWindow and activeWindow.DoLayout then activeWindow:DoLayout() end
      for _, callback in ipairs(activeShell._dibsResizeHandlers) do pcall(callback, activeShell) end
    end)
  end
  call(window, "SetCallback", "OnClose", function(widget)
    if not shell._dibsActive then return end
    shell._dibsActive = false
    if type(shell.onRelease) == "function" then shell.onRelease(shell) end
    if shell and shell.frame == widget.frame then
      shell.frame = nil
    end
    if _G.DibsPlayerFrame == widget.frame then _G.DibsPlayerFrame = nil end
    if _G.DibsOfficerFrame == widget.frame then _G.DibsOfficerFrame = nil end
    if Dibs.WindowState and type(Dibs.WindowState.Unregister) == "function" then
      Dibs.WindowState.Unregister(widget.frame)
    end
    if widget.frame and widget.frame._dibsWindowShell == shell then widget.frame._dibsWindowShell = nil end
    if type(Adapter.ReleaseOwnedState) == "function" then Adapter.ReleaseOwnedState(widget) end
    if type(gui.Release) == "function" then gui:Release(widget)
    elseif type(widget.Hide) == "function" then widget:Hide() end
    if widget.frame and widget.frame.dibsAceGUIShell == shell then widget.frame.dibsAceGUIShell = nil end
    shell.gui, shell.window, shell.frame = nil, nil, nil
  end)

  return shell
end

local function disposeUnattachedWidget(shell, widget)
  if not widget then return end
  if shell and shell.gui and type(shell.gui.Release) == "function" then
    pcall(shell.gui.Release, shell.gui, widget)
  elseif widget.frame then
    if type(widget.frame.Hide) == "function" then widget.frame:Hide() end
    if type(widget.frame.SetParent) == "function" then widget.frame:SetParent(nil) end
  end
end

local function isAceGUIContainer(value)
  return type(value) == "table"
    and type(value.AddChild) == "function"
    and value.frame ~= nil
end

local function frameContains(frame, target)
  local current = frame
  local visited = {}
  while current and not visited[current] do
    if current == target then return true end
    visited[current] = true
    current = type(current.GetParent) == "function" and current:GetParent() or nil
  end
  return false
end

local function wouldCreateParentCycle(owner, widget)
  return owner and widget and owner.frame and widget.frame
    and frameContains(owner.frame, widget.frame)
end

local function normalizeChildren(container)
  local children = container and container.children
  if type(children) ~= "table" then return end
  local ordered = {}
  local maxIndex = 0
  for index, child in pairs(children) do
    if type(index) == "number" then
      maxIndex = math.max(maxIndex, index)
      if child then
        ordered[#ordered + 1] = { index = index, child = child }
      end
    end
  end
  if maxIndex == #ordered then return end
  table.sort(ordered, function(left, right) return left.index < right.index end)
  for index = 1, #ordered do children[index] = ordered[index].child end
  for index = #ordered + 1, #children do children[index] = nil end
end

function Adapter.Create(shell, kind, parent)
  if not shell or not shell.gui then return nil end
  local ok, widget = pcall(shell.gui.Create, shell.gui, kind)
  if not ok or not widget then return nil end
  local owner = parent or shell.window
  if not isAceGUIContainer(owner) or owner == widget or owner.frame == widget.frame
    or wouldCreateParentCycle(owner, widget) then
    disposeUnattachedWidget(shell, widget)
    return nil
  end
  normalizeChildren(owner)
  owner:AddChild(widget)
  if Dibs.Midnight and type(Dibs.Midnight.ApplyToWidget) == "function" then
    Dibs.Midnight.ApplyToWidget(widget, Adapter.GetPresentationTokens())
  end
  return widget
end

function Adapter.CreateInFrame(shell, kind, parentFrame)
  if not shell or not shell.gui or type(parentFrame) ~= "table"
    or type(parentFrame.SetParent) ~= "function" then return nil end
  local ok, widget = pcall(shell.gui.Create, shell.gui, kind)
  if not ok or not widget or not widget.frame or widget.frame == parentFrame then
    disposeUnattachedWidget(shell, widget)
    return nil
  end
  widget.frame:SetParent(parentFrame)
  widget._dibsRawOwner = parentFrame
  return widget
end

local function releaseMSAControls(widget, seen)
  if type(widget) ~= "table" then return end
  seen = seen or {}
  if seen[widget] then return end
  seen[widget] = true
  if widget._dibsShell and widget._dibsShell._dibsResponsiveScrolls then
    for index = #widget._dibsShell._dibsResponsiveScrolls, 1, -1 do
      if widget._dibsShell._dibsResponsiveScrolls[index] == widget then
        table.remove(widget._dibsShell._dibsResponsiveScrolls, index)
      end
    end
  end
  local control = widget._dibsMSAControl
  if control then
    if type(_G.MSA_DropDownMenu_ClearAll) == "function" then
      pcall(_G.MSA_DropDownMenu_ClearAll, control)
    end
    if type(_G.MSA_DropDownMenu_SetText) == "function" then
      pcall(_G.MSA_DropDownMenu_SetText, control, "")
    end
    if control.Hide then pcall(control.Hide, control) end
    if control.ClearAllPoints then pcall(control.ClearAllPoints, control) end
    if control.SetParent then pcall(control.SetParent, control, nil) end
    msaDropdownPool[#msaDropdownPool + 1] = control
    widget._dibsMSAControl = nil
  end
  local label = widget._dibsMSALabel
  if label then
    if label.Hide then pcall(label.Hide, label) end
    if label.ClearAllPoints then pcall(label.ClearAllPoints, label) end
    if label.SetParent then pcall(label.SetParent, label, nil) end
    widget._dibsMSALabel = nil
  end
  if widget.type == "SimpleGroup" and widget.frame and type(widget.frame.GetRegions) == "function" then
    local ok, regions = pcall(function() return { widget.frame:GetRegions() } end)
    if ok then
      for _, region in ipairs(regions) do
        local regionType = type(region.GetObjectType) == "function" and region:GetObjectType() or nil
        if regionType == "FontString" then
          if region.Hide then pcall(region.Hide, region) end
          if region.SetText then pcall(region.SetText, region, "") end
          if region.ClearAllPoints then pcall(region.ClearAllPoints, region) end
          if region.SetParent then pcall(region.SetParent, region, nil) end
        end
      end
    end
  end
  if widget._dibsScrollingTable then
    if type(widget._dibsScrollingTable.RegisterEvents) == "function" then
      pcall(widget._dibsScrollingTable.RegisterEvents, widget._dibsScrollingTable, {}, true)
    end
    if type(widget._dibsScrollingTable.Hide) == "function" then
      pcall(widget._dibsScrollingTable.Hide, widget._dibsScrollingTable)
    end
    local tableFrame = widget._dibsScrollingTable.frame
    if tableFrame then
      if tableFrame.ClearAllPoints then pcall(tableFrame.ClearAllPoints, tableFrame) end
      if tableFrame.SetParent then pcall(tableFrame.SetParent, tableFrame, nil) end
    end
    widget._dibsScrollingTable = nil
  end
  -- AceGUI reuses SimpleGroup instances.  Restore the widget's original
  -- width handler before returning a table host to the pool; otherwise a
  -- later, unrelated SimpleGroup keeps the previous table closure and can
  -- reflow a released native frame.
  if widget._dibsTableWidthHandler and widget.OnWidthSet == widget._dibsTableWidthHandler then
    widget.OnWidthSet = widget._dibsBaseOnWidthSet
  end
  widget._dibsTableWidthHandler = nil
  widget._dibsBaseOnWidthSet = nil
  normalizeChildren(widget)
  for _, child in ipairs(widget.children or {}) do
    releaseMSAControls(child, seen)
  end
  for key in pairs(widget) do
    if type(key) == "string" and key:find("^_dibs") then widget[key] = nil end
  end
end

Adapter.ReleaseOwnedState = releaseMSAControls

function Adapter.Clear(container)
  -- Releasing children changes frame parents and sizes.  Pause the container
  -- while its array is being emptied so an OnSizeChanged callback cannot run
  -- List against the half-released array (which otherwise exposes a nil child
  -- in ElvUI's AceGUI implementation).
  local paused = container and type(container.PauseLayout) == "function"
  if paused then container:PauseLayout() end
  Adapter.HideContextMenu()
  releaseMSAControls(container)
  normalizeChildren(container)
  local childArray = container and container.children
  local hasChildArray = type(childArray) == "table"
  local children = {}
  local releasedWidgets = {}
  local seenWidgets = {}
  local function collectWidgets(widget)
    if type(widget) ~= "table" or seenWidgets[widget] then return end
    seenWidgets[widget] = true
    releasedWidgets[#releasedWidgets + 1] = widget
    for _, nested in ipairs(widget.children or {}) do collectWidgets(nested) end
  end
  for _, child in ipairs(childArray or {}) do children[#children + 1] = child end
  for _, child in ipairs(children) do collectWidgets(child) end
  local gui = getLibrary()
  local releasedByContainer = false
  if hasChildArray and gui and type(gui.Release) == "function"
    and type(container.ReleaseChildren) == "function" then
    -- AceGUI's implementation releases the live children array recursively.
    -- Keeping this path intact is important for pooled ScrollFrame and TreeGroup
    -- widgets whose native child frames are not represented by children[].
    releasedByContainer = pcall(container.ReleaseChildren, container)
  end
  if not releasedByContainer then
    for index, child in ipairs(children) do
      if child and not child.isQueuedForRelease then
        local released = false
        if gui and type(gui.Release) == "function" then
          released = pcall(gui.Release, gui, child)
        elseif type(child.Release) == "function" then
          released = pcall(child.Release, child)
        end
        if not released and child.frame and type(child.frame.Hide) == "function" then
          pcall(child.frame.Hide, child.frame)
        end
      end
      if hasChildArray then childArray[index] = nil end
    end
  end
  for _, child in ipairs(releasedWidgets) do
    if child then
      releaseMSAControls(child)
      if child.frame then
        if type(child.frame.Hide) == "function" then pcall(child.frame.Hide, child.frame) end
        if type(child.frame.SetParent) == "function" then pcall(child.frame.SetParent, child.frame, nil) end
      end
    end
  end
  if hasChildArray then
    for index = #childArray, 1, -1 do childArray[index] = nil end
  elseif container and type(container.ReleaseChildren) == "function" then
    pcall(container.ReleaseChildren, container)
  end
  normalizeChildren(container)
  if paused then container:ResumeLayout() end
end

function Adapter.SetText(widget, text)
  if widget then call(widget, "SetText", tostring(text or "")) end
end

function Adapter.SetDisabled(widget, disabled)
  if widget then call(widget, "SetDisabled", disabled == true) end
end

function Adapter.SetValue(widget, value)
  if widget then call(widget, "SetValue", value) end
end

function Adapter.AddTooltip(widget, title, description)
  local frame = widget and widget.frame
  if not frame or type(frame.SetScript) ~= "function" or not GameTooltip or type(GameTooltip.SetOwner) ~= "function" then
    return widget
  end
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(tostring(title or ""), 1, 0.82, 0, 1)
    if description and description ~= "" then
      GameTooltip:AddLine(tostring(description), 1, 1, 1, true)
    end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  return widget
end

function Adapter.AddHeader(shell, parent, text, description)
  local header = Adapter.AddLabel(shell, parent, text, true)
  return Adapter.AddTooltip(header, text, description)
end

-- A titled section keeps related controls together while still allowing the
-- parent page to use a simple vertical layout.  InlineGroup is part of AceGUI
-- on Retail; the SimpleGroup fallback keeps the same layout in reduced test
-- or standalone environments.
function Adapter.AddSection(shell, parent, title, description)
  local section = Adapter.Create(shell, "InlineGroup", parent)
  if not section then section = Adapter.Create(shell, "SimpleGroup", parent) end
  if not section then return parent end
  call(section, "SetFullWidth", true)
  -- Sections contain labels, fields and actions. Stack them so a fixed-width
  -- control cannot share a row with the next label while the parent is being
  -- measured; compact horizontal toolbars should use AddInlineGroup instead.
  call(section, "SetLayout", "List")
  if title and title ~= "" then call(section, "SetTitle", tostring(title)) end
  return Adapter.AddTooltip(section, title, description)
end

function Adapter.AddInlineGroup(shell, parent)
  local group = Adapter.Create(shell, "SimpleGroup", parent)
  if not group then return parent end
  call(group, "SetFullWidth", true)
  call(group, "SetLayout", "Flow")
  return group
end

function Adapter.AddLabel(shell, parent, text, fullWidth)
  local label = Adapter.Create(shell, "Label", parent)
  if not label then return nil end
  if fullWidth then call(label, "SetFullWidth", true) end
  Adapter.SetText(label, text)
  return label
end

-- Form rows deliberately own their vertical budget. AceGUI controls can
-- report their final height after they are attached, so the parent must not
-- infer the next row position from an unmeasured child.
function Adapter.AddFormRow(shell, parent, label, createControl, height)
  local row = Adapter.Create(shell, "SimpleGroup", parent)
  if not row then return nil, nil end
  call(row, "SetFullWidth", true)
  call(row, "SetLayout", "List")
  call(row, "SetHeight", tonumber(height) or 52)
  if label and label ~= "" then Adapter.AddLabel(shell, row, label, true) end
  local control
  if type(createControl) == "function" then control = createControl(row) end
  return control, row
end

function Adapter.AddSummaryRow(shell, parent, label, value, height)
  local row = Adapter.Create(shell, "SimpleGroup", parent)
  if not row then return nil end
  call(row, "SetFullWidth", true)
  call(row, "SetLayout", "Flow")
  call(row, "SetHeight", tonumber(height) or 28)
  local labelWidget = Adapter.AddLabel(shell, row, tostring(label or ""), false)
  local valueWidget = Adapter.AddLabel(shell, row, tostring(value or "Unavailable"), false)
  call(labelWidget, "SetWidth", 150)
  call(valueWidget, "SetWidth", 300)
  row._dibsValueWidget = valueWidget
  return valueWidget, row
end

function Adapter.AddTruncatedLabel(shell, parent, value, maximum, description)
  local full = tostring(value or "")
  local visible, truncated = full, false
  if Dibs.Midnight and type(Dibs.Midnight.Truncate) == "function" then
    visible, truncated = Dibs.Midnight.Truncate(full, maximum)
  end
  local label = Adapter.AddLabel(shell, parent, visible, false)
  if label then
    label._dibsFullText = full
    if truncated then Adapter.AddTooltip(label, full, description or "Hover to see the complete value.") end
  end
  return label
end

local function safeContextText(value)
  return tostring(value or "")
end

local function showTableCellTooltip(cellFrame, value)
  if type(value) ~= "string" or not _G.GameTooltip
    or type(_G.GameTooltip.SetOwner) ~= "function" then return false end
  local isItemLink = value:find("|Hitem:", 1, true) ~= nil
  if isItemLink and type(_G.GameTooltip.SetHyperlink) == "function" then
    _G.GameTooltip:SetOwner(cellFrame, "ANCHOR_RIGHT")
    _G.GameTooltip:SetHyperlink(value)
  elseif type(_G.GameTooltip.SetText) == "function" then
    _G.GameTooltip:SetOwner(cellFrame, "ANCHOR_RIGHT")
    _G.GameTooltip:SetText(value, 1, 1, 1, 1, true)
  else
    return false
  end
  if type(_G.GameTooltip.Show) == "function" then _G.GameTooltip:Show() end
  return true
end

Adapter.ShowTableCellTooltip = showTableCellTooltip

function Adapter.ShowContextMenu(entries)
  if type(_G.MSA_DropDownMenu_Create) ~= "function"
    or type(_G.MSA_DropDownMenu_Initialize) ~= "function"
    or type(_G.MSA_DropDownMenu_CreateInfo) ~= "function"
    or type(_G.MSA_DropDownMenu_AddButton) ~= "function"
    or type(_G.MSA_ToggleDropDownMenu) ~= "function" then return false end
  Adapter.HideContextMenu()
  if not contextMenuFrame then
    contextMenuSerial = contextMenuSerial + 1
    contextMenuFrame = _G.MSA_DropDownMenu_Create("DibsContextMenu" .. tostring(contextMenuSerial), _G.UIParent)
  end
  if not contextMenuFrame then return false end
  _G.MSA_DropDownMenu_Initialize(contextMenuFrame, function(_, level)
    if level ~= 1 then return end
    for _, entry in ipairs(entries or {}) do
      if type(entry) == "table" and type(entry.callback) == "function" then
        local info = _G.MSA_DropDownMenu_CreateInfo()
        info.text = safeContextText(entry.text or "Action")
        info.disabled = entry.disabled == true
        info.notCheckable = true
        info.func = entry.callback
        _G.MSA_DropDownMenu_AddButton(info, level)
      end
    end
  end, "MENU")
  _G.MSA_ToggleDropDownMenu(1, nil, contextMenuFrame, "cursor", 0, 0)
  return true
end

local function showTableContextMenu(st, rowRecord, columns, options)
  if not HAS_MSA_DROPDOWN or type(_G.MSA_ToggleDropDownMenu) ~= "function"
    or type(_G.MSA_DropDownMenu_Initialize) ~= "function" then
    return false
  end
  Adapter.HideContextMenu()
  if not contextMenuFrame then
    contextMenuSerial = contextMenuSerial + 1
    contextMenuFrame = _G.MSA_DropDownMenu_Create("DibsTableContext" .. tostring(contextMenuSerial), _G.UIParent)
  end
  if not contextMenuFrame then return false end

  local menuRows = {}
  local function addMenu(text, callback, disabled)
    menuRows[#menuRows + 1] = { text = text, callback = callback, disabled = disabled }
  end
  if rowRecord then
    local action = rowRecord._dibsAction
    if action and type(action.callback) == "function" then
      addMenu(action.text or "Open", action.callback)
    end
    if options and type(options.contextMenu) == "function" then
      local ok, custom = pcall(options.contextMenu, rowRecord._dibsRow or rowRecord, st)
      if ok and type(custom) == "table" then
        for _, entry in ipairs(custom) do
          if type(entry) == "table" and type(entry.callback) == "function" then
            addMenu(entry.text or "Action", entry.callback, entry.disabled == true)
          end
        end
      end
    end
    if #menuRows > 0 and (not options or options.allowTableSort ~= false) then
      menuRows[#menuRows + 1] = { isTitle = true, text = "Sort table" }
    end
  end
  if not options or options.allowTableSort ~= false then
    for index, column in ipairs(columns or {}) do
      if not column.action then
      local name = safeContextText(column.title or column.name or ("Column " .. tostring(index)))
      addMenu(name .. " (A-Z)", function()
        for i, definition in ipairs(st.cols or {}) do definition.sort = nil end
        st.cols[index].sort = getScrollingTable().SORT_ASC
        st:SortData()
        if st._dibsUpdateHeaders then st._dibsUpdateHeaders() end
      end)
      addMenu(name .. " (Z-A)", function()
        for i, definition in ipairs(st.cols or {}) do definition.sort = nil end
        st.cols[index].sort = getScrollingTable().SORT_DSC
        st:SortData()
        if st._dibsUpdateHeaders then st._dibsUpdateHeaders() end
      end)
      end
    end
  end
  if #menuRows == 0 then return false end
  _G.MSA_DropDownMenu_Initialize(contextMenuFrame, function(_, level)
    if level ~= 1 then return end
    for _, entry in ipairs(menuRows) do
      local info = _G.MSA_DropDownMenu_CreateInfo()
      info.text = entry.text
      info.isTitle = entry.isTitle
      info.disabled = entry.disabled
      info.notCheckable = true
      info.func = entry.callback
      _G.MSA_DropDownMenu_AddButton(info, level)
    end
  end, "MENU")
  _G.MSA_ToggleDropDownMenu(1, nil, contextMenuFrame, "cursor", 0, 0)
  return true
end

-- Render a real ScrollingTable when lib-st is available. Its native header
-- buttons provide stable column widths, left-click sorting, row selection and
-- right-click menus. The existing AceGUI label grid remains the compatibility
-- fallback used by reduced test clients and older installations.
function Adapter.AddScrollingTable(shell, parent, columns, rows, height, rowActions, options)
  local library = getScrollingTable()
  if not library or type(library.CreateST) ~= "function" or not parent or not parent.frame then
    return nil
  end
  options = options or {}
  local tableHeight = tonumber(height) or 260
  local rowHeight = tonumber(options.rowHeight) or 20
  local definitions = columns or {}
  if #definitions == 0 then return nil end
  local host = Adapter.Create(shell, "SimpleGroup", parent)
  if not host or not host.frame then return nil end
  call(host, "SetFullWidth", true)
  -- lib-st owns a native frame that is taller than AceGUI's SimpleGroup
  -- default. Reserve the same height in the parent layout or the next widget
  -- is placed over the table (most visible on the Profiles and Data pages).
  -- Its sortable header is anchored just above that native frame, so include
  -- one row for the header in the host's allocation as well.
  call(host, "SetHeight", tableHeight + rowHeight)
  call(host, "SetLayout", "Fill")
  -- lib-st owns a native frame rather than an AceGUI child.  An empty Fill
  -- group otherwise auto-adjusts to zero during a parent reflow, moving the
  -- next control over the table and producing the intermittent narrow layout.
  call(host, "SetAutoAdjustHeight", false)
  -- Give the header the same readable panel treatment as the rows. The
  -- embedded lib-st frame supplies its own backdrop for the body; this small
  -- background fills the reserved header band without changing AceGUI's
  -- global theme.
  if host.frame.CreateTexture then
    local background = host.frame:CreateTexture(nil, "BACKGROUND")
    if background then
      if background.SetColorTexture then
        background:SetColorTexture(0.10, 0.11, 0.12, 0.94)
      elseif background.SetTexture then
        background:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        if background.SetVertexColor then background:SetVertexColor(0.10, 0.11, 0.12, 0.94) end
      end
      if background.SetAllPoints then background:SetAllPoints(host.frame) end
      host._dibsTableBackground = background
    end
  end

  local desiredWidth = 0
  local tableColumns = {}
  for index, column in ipairs(definitions) do
    local width = math.max(48, tonumber(column.width) or 100)
    local action = column.action == true or (index == #definitions and rowActions ~= nil)
    local title = string.lower(tostring(column.title or column.name or ""))
    local defaultMinimum = action and Adapter.GetLayoutMetrics().actionMinWidth or 48
    local defaultPriority = action and 100 or 1
    if not action and title:find("player", 1, true) then defaultMinimum, defaultPriority = 120, 5 end
    if not action and title:find("item", 1, true) then defaultMinimum, defaultPriority = 140, 5 end
    if not action and title:find("status", 1, true) then defaultMinimum, defaultPriority = 88, 5 end
    desiredWidth = desiredWidth + width
    tableColumns[index] = {
      name = safeContextText(column.title or column.name or ("Column " .. tostring(index))),
      baseName = safeContextText(column.title or column.name or ("Column " .. tostring(index))),
      width = width,
      baseWidth = width,
      minWidth = tonumber(column.minWidth) or defaultMinimum,
      priority = tonumber(column.priority) or defaultPriority,
      align = column.align or "LEFT",
      tooltip = column.tooltip,
      defaultsort = column.defaultsort,
      action = action,
    }
  end

  local availableWidth = tonumber(options.widthHint) or (host.frame.GetWidth and host.frame:GetWidth() or 0)
  if availableWidth <= 0 and shell.frame and shell.frame.GetWidth then
    availableWidth = math.max(360, (shell.frame:GetWidth() or desiredWidth) - 220)
  end
  if availableWidth > 0 then availableWidth = availableWidth - 12 end
  if availableWidth > 0 and desiredWidth > availableWidth then
    local fitted = Adapter.FitColumnWidths(tableColumns, availableWidth)
    for index, column in ipairs(tableColumns) do column.width = fitted[index] end
  end

  local rowData = {}
  for _, sourceRow in ipairs(rows or {}) do
    local action = rowActions and rowActions(sourceRow) or nil
    local cells = {}
    for index = 1, #tableColumns do
      local value = sourceRow[index]
      if index == #tableColumns and action then value = action.text or "Action" end
      cells[index] = value == nil and "" or value
    end
    rowData[#rowData + 1] = { cols = cells, _dibsRow = sourceRow, _dibsAction = action }
  end
  if #rowData == 0 then
    rowData[1] = { cols = {}, _dibsRow = { "No entries" } }
    for index = 1, #tableColumns do rowData[1].cols[index] = index == 1 and "No entries" or "" end
  end

  local visibleRows = math.max(1, math.floor(tableHeight / rowHeight))
  local ok, st = pcall(library.CreateST, library, tableColumns, visibleRows, rowHeight,
    options.highlight or { r = 0.22, g = 0.45, b = 0.65, a = 0.35 }, host.frame)
  if not ok or not st then return nil end
  host._dibsScrollingTable = st
  st._dibsColumns = tableColumns
  st._dibsUpdateHeaders = function()
    for _, column in ipairs(tableColumns) do
      local marker = column.sort == library.SORT_ASC and "  ^" or (column.sort == library.SORT_DSC and "  v" or "")
      column.name = column.baseName .. marker
    end
    if type(st.SetDisplayCols) == "function" then st:SetDisplayCols(tableColumns) end
  end
  if type(st.SetDefaultHighlight) == "function" then
    pcall(st.SetDefaultHighlight, st, 0.18, 0.42, 0.62, 0.38)
  end
  if type(st.EnableSelection) == "function" then st:EnableSelection(true) end

  -- A table is often created before its List/TreeGroup parent receives its
  -- final width. Reapply the original column proportions whenever AceGUI
  -- measures the host, otherwise the first 300px default becomes permanent
  -- and date/item text is needlessly wrapped in every window.
  local baseOnWidthSet = host._dibsBaseOnWidthSet or host.OnWidthSet
  local function applyTableWidth(_, width)
    if type(baseOnWidthSet) == "function" and host.content and tonumber(width) then
      pcall(baseOnWidthSet, host, tonumber(width))
    end
    local available = tonumber(width)
    if not available or available <= 20 then return end
    available = math.max(240, available - 12)
    local fitted = Adapter.FitColumnWidths(tableColumns, available)
    local used = 0
    for index, column in ipairs(tableColumns) do
      column.width = fitted[index]
      used = used + column.width
    end
    st._dibsUpdateHeaders()
    if st.frame and st.frame.SetWidth then st.frame:SetWidth(used) end
  end
  host._dibsBaseOnWidthSet = baseOnWidthSet
  host._dibsTableWidthHandler = applyTableWidth
  host.OnWidthSet = applyTableWidth
  if st.frame then
    st.frame:ClearAllPoints()
    -- Keep the lib-st header inside the AceGUI host instead of letting it
    -- float into the heading/control row above the table.
    st.frame:SetPoint("TOPLEFT", host.frame, "TOPLEFT", 0, -rowHeight)
    applyTableWidth(host, host.frame.GetWidth and host.frame:GetWidth() or desiredWidth)
  end

  local function sortColumn(index)
    for i, column in ipairs(tableColumns) do
      if i ~= index then column.sort = nil end
    end
    local column = tableColumns[index]
    if column.sort == library.SORT_DSC then column.sort = library.SORT_ASC else column.sort = library.SORT_DSC end
    st:SortData()
    st._dibsUpdateHeaders()
  end

  local lastActionRow
  local lastActionAt = 0
  st:RegisterEvents({
    OnEnter = function(rowFrame, cellFrame, data, cols, row, realrow, column, table)
      local cell = realrow and table:GetCell(realrow, column)
      local value = type(cell) == "table" and cell.value or cell
      showTableCellTooltip(cellFrame, value)
      return false
    end,
    OnLeave = function()
      if _G.GameTooltip and type(_G.GameTooltip.Hide) == "function" then _G.GameTooltip:Hide() end
      return false
    end,
    OnClick = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, button)
      local record = realrow and table:GetRow(realrow)
      if button == "RightButton" then
        if options and options.disableContextMenu then return true end
        return showTableContextMenu(table, record, definitions, options)
      end
      if button ~= "LeftButton" then return false end
      if not realrow then
        sortColumn(column)
        return true
      end
      if record and record._dibsAction and column == #tableColumns then
        if type(record._dibsAction.callback) == "function" then record._dibsAction.callback(record._dibsRow or record) end
        return true
      end
      if record and record._dibsAction and type(record._dibsAction.callback) == "function" then
        local currentTime = type(GetTime) == "function" and GetTime() or (type(time) == "function" and time() or 0)
        if lastActionRow == realrow and currentTime - lastActionAt <= 0.35 then
          lastActionRow, lastActionAt = nil, 0
          record._dibsAction.callback(record._dibsRow or record)
          return true
        end
        lastActionRow, lastActionAt = realrow, currentTime
      end
      if table.GetSelection and table.SetSelection then
        if table:GetSelection() == realrow and table.ClearSelection then table:ClearSelection()
        else table:SetSelection(realrow) end
      end
      if options and type(options.onRowClick) == "function" then
        options.onRowClick(record and (record._dibsRow or record) or nil, column)
      end
      return true
    end,
  }, true)
  st:SetData(rowData, false)
  local defaultColumn = options.defaultSortColumn
  if not defaultColumn then
    for index, column in ipairs(tableColumns) do
      local title = string.lower(column.baseName or "")
      if title:find("date", 1, true) or title:find("time", 1, true) then
        defaultColumn = index
        break
      end
    end
  end
  if defaultColumn and tableColumns[defaultColumn] then
    for index, column in ipairs(tableColumns) do column.sort = nil end
    tableColumns[defaultColumn].sort = options.defaultSortDirection == "asc" and library.SORT_ASC or library.SORT_DSC
    st:SortData()
    st._dibsUpdateHeaders()
  end
  if st.frame and st.frame.Show then st.frame:Show() end
  return host
end

function Adapter.AddTable(shell, parent, columns, rows, height, rowActions, options)
  options = options or {}
  local scrolling = not options.noScrolling and Adapter.AddScrollingTable(shell, parent, columns, rows, height, rowActions, options)
  if scrolling then return scrolling end
  local scroll = options.noScrolling and parent or (parent and parent.type == "ScrollFrame" and parent or Adapter.AddScrollableList(shell, parent, height))
  if not scroll then return nil end
  local definitions = columns or {}
  local desiredWidth = 0
  for _, column in ipairs(definitions) do desiredWidth = desiredWidth + (tonumber(column.width) or 100) end
  local frameWidth = tonumber(options.widthHint) or (scroll.frame and scroll.frame.GetWidth and scroll.frame:GetWidth() or 0)
  if frameWidth <= 0 and parent and parent.frame and parent.frame.GetWidth then frameWidth = parent.frame:GetWidth() or 0 end
  if frameWidth <= 0 and shell and shell.frame and shell.frame.GetWidth then frameWidth = (shell.frame:GetWidth() or 760) - 220 end
  frameWidth = math.max(360, frameWidth > 0 and frameWidth - 8 or math.min(desiredWidth, 760))
  local fitDefinitions = {}
  for index, column in ipairs(definitions) do
    local title = string.lower(tostring(column.title or column.name or ""))
    local action = rowActions and index == #definitions
    local minimum = column.minWidth
    local priority = column.priority
    if not minimum and title:find("player", 1, true) then minimum = 120 end
    if not minimum and title:find("item", 1, true) then minimum = 140 end
    if not minimum and title:find("status", 1, true) then minimum = 88 end
    if action then minimum, priority = minimum or Adapter.GetLayoutMetrics().actionMinWidth, priority or 100 end
    fitDefinitions[index] = {
      width = column.width, minWidth = minimum,
      priority = priority, action = action,
    }
  end
  local widths = Adapter.FitColumnWidths(fitDefinitions, frameWidth)
  local actualWidth = 0
  for index in ipairs(definitions) do actualWidth = actualWidth + widths[index] end

  local function cellText(value, width)
    local result = tostring(value or "")
    -- Let WoW render a complete hyperlink. Truncating the colour and Hitem
    -- escape sequence makes the visible cell look like raw `[Hitem:...]` text.
    if result:find("|Hitem:", 1, true) then return result end
    local characters = math.max(8, math.floor((width or 100) / 7))
    if Dibs.Midnight and Dibs.Midnight.Truncate then result = Dibs.Midnight.Truncate(result, characters) end
    return result
  end

  local function addGridRow(values, action, header)
    local rowGroup = Adapter.Create(shell, "SimpleGroup", scroll)
    if not rowGroup then return end
    call(rowGroup, "SetFullWidth", true)
    call(rowGroup, "SetLayout", "Flow")
    local columnCount = action and math.max(0, #definitions - 1) or #definitions
    for index = 1, columnCount do
      local column = definitions[index]
      local value = header and column.title or values[index]
      local cell = Adapter.AddLabel(shell, rowGroup, cellText(value, widths[index]), false)
      if cell then
        call(cell, "SetWidth", widths[index])
        if cell.SetJustifyH then cell:SetJustifyH("LEFT") end
        Adapter.AddTooltip(cell, value, column.tooltip)
      end
    end
    if action then
      -- The action lives in the final cell's visual column, so it stays on
      -- the same row as its request even when the table is narrow.
      local button = Adapter.AddButton(shell, rowGroup, action.text or "Action", action.callback, math.max(70, widths[#definitions] or 86))
      if button then call(button, "SetWidth", math.max(70, widths[#definitions] or 86)) end
    end
  end

  addGridRow({}, nil, true)
  for _, row in ipairs(rows or {}) do
    local action = rowActions and rowActions(row) or nil
    addGridRow(row, action, false)
  end
  return scroll
end

function Adapter.AddPropertyTable(shell, parent, rows, height)
  return Adapter.AddTable(shell, parent, {
    { title = "Field", width = 150, tooltip = "Property name." },
    { title = "Value", width = 520, tooltip = "Recorded value." },
  }, rows, height or 190, nil, {
    widthHint = shell and shell.frame and shell.frame.GetWidth and math.max(360, (shell.frame:GetWidth() or 760) - 50) or nil,
  })
end

function Adapter.AddButton(shell, parent, text, callback, width)
  local button = Adapter.Create(shell, "Button", parent)
  if not button then return nil end
  Adapter.SetText(button, text)
  call(button, "SetAutoWidth", true)
  call(button, "SetHeight", Adapter.GetLayoutMetrics().buttonHeight)
  if width and button.frame and type(button.frame.GetWidth) == "function" then
    local autoWidth = button.frame:GetWidth() or 0
    call(button, "SetWidth", math.max(width, autoWidth))
  end
  call(button, "SetCallback", "OnClick", function()
    if callback then callback() end
  end)
  return button
end

function Adapter.AddEditBox(shell, parent, label, callback, width)
  local edit = Adapter.Create(shell, "EditBox", parent)
  if not edit then return nil end
  call(edit, "SetLabel", label or "")
  call(edit, "SetWidth", width or 420)
  call(edit, "SetCallback", "OnTextChanged", function(_, _, value)
    if callback then callback(value or "") end
  end)
  return edit
end

-- MultiLineEditBox ships with AceGUI's generic Accept label/button contract.
-- Request workflows own confirmation and must use only the editor surface.
function Adapter.AddMultilineEditBox(shell, parent, label, callback, width, height)
  local edit = Adapter.Create(shell, "MultiLineEditBox", parent)
  if not edit then edit = Adapter.Create(shell, "EditBox", parent) end
  if not edit then return nil end
  call(edit, "SetLabel", label or "")
  call(edit, "SetWidth", width or 420)
  call(edit, "SetHeight", height or 76)
  if edit.DisableButton then edit:DisableButton(true) end
  call(edit, "SetCallback", "OnTextChanged", function(_, _, value)
    if callback then callback(value or "") end
  end)
  return edit
end

-- Add a read-only report surface that remains selectable in the live client.
-- MultiLineEditBox is provided by AceGUI on Retail; the EditBox fallback keeps
-- the report available with older or reduced AceGUI installations.
function Adapter.AddSelectableText(shell, parent, label, value, width, height)
  local edit = Adapter.Create(shell, "MultiLineEditBox", parent)
  if not edit then edit = Adapter.Create(shell, "EditBox", parent) end
  if not edit then return nil end
  call(edit, "SetLabel", label or "")
  call(edit, "SetWidth", width or 700)
  call(edit, "SetHeight", height or 460)
  call(edit, "SetFullWidth", true)
  call(edit, "SetFullHeight", true)
  call(edit, "SetText", tostring(value or ""))
  -- Keep this as an editable widget so Ctrl+A/Ctrl+C works.  The report is
  -- immutable from Dibs' side because no OnTextChanged callback is attached.
  return edit
end

function Adapter.SelectText(widget)
  if not widget then return false end
  local targets = { widget, widget.editbox, widget.frame }
  for _, target in ipairs(targets) do
    if target and type(target.SetFocus) == "function" then pcall(target.SetFocus, target) end
    if target and type(target.HighlightText) == "function" then
      local ok = pcall(target.HighlightText, target, 0, -1)
      if ok then return true end
    end
  end
  return false
end

function Adapter.AddMSADropdown(shell, parent, label, values, callback, width)
  if not HAS_MSA_DROPDOWN or not parent or not parent.frame
    or type(parent.frame.CreateFontString) ~= "function" then
    return nil
  end

  local host = Adapter.Create(shell, "SimpleGroup", parent)
  if not host or not host.frame then return nil end
  call(host, "SetFullWidth", true)
  call(host, "SetHeight", 44)
  call(host, "SetLayout", "Fill")
  -- The MSA dropdown is attached directly to this host.  Preserve its
  -- explicit height when AceGUI lays out an empty Fill group.
  call(host, "SetAutoAdjustHeight", false)

  local hostFrame = host.frame
  local labelText = hostFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if labelText then
    labelText:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, -2)
    labelText:SetText(tostring(label or ""))
  end

  msaDropdownSerial = msaDropdownSerial + 1
  local control = table.remove(msaDropdownPool)
  if control and control.SetParent then
    control:SetParent(hostFrame)
    if control.ClearAllPoints then control:ClearAllPoints() end
  end
  if not control then
    local name = "DibsMSADropdown" .. tostring(msaDropdownSerial)
    control = _G.MSA_DropDownMenu_Create(name, hostFrame)
  end
  if not control then return nil end
  control.__dibsMSA = true
  control:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, -18)
  if control.Show then control:Show() end
  control.selectedID, control.selectedName, control.selectedValue = nil, nil, nil
  if _G.MSA_DropDownMenu_SetWidth then
    _G.MSA_DropDownMenu_SetWidth(control, width or 260, 25)
  end
  if _G.MSA_DropDownMenu_JustifyText then
    _G.MSA_DropDownMenu_JustifyText(control, "LEFT")
  end

  local wrapper = { frame = control, host = host, values = values or {}, value = nil }
  local keys = {}
  host._dibsMSALabel = labelText
  host._dibsMSAControl = control
  host._dibsMSAWrapper = wrapper

  local function valueLabel(value)
    local labelValue = wrapper.values[value]
    if labelValue == nil then labelValue = wrapper.values[tostring(value)] end
    return tostring(labelValue or value or "")
  end

  local function canonicalValue(value)
    if wrapper.values and wrapper.values[value] ~= nil then return value end
    for key, text in pairs(wrapper.values or {}) do
      if tostring(key) == tostring(value) or tostring(text) == tostring(value) then return key end
    end
    return nil
  end

  function wrapper:SetText(text)
    self.text = tostring(text or "")
    _G.MSA_DropDownMenu_SetText(control, self.text)
  end

  function wrapper:GetText()
    if _G.MSA_DropDownMenu_GetText then
      local ok, text = pcall(_G.MSA_DropDownMenu_GetText, control)
      if ok then return tostring(text or "") end
    end
    return self.text or ""
  end

  function wrapper:SetValue(value)
    self.value = canonicalValue(value) or value
    if _G.MSA_DropDownMenu_SetSelectedValue then
      _G.MSA_DropDownMenu_SetSelectedValue(control, value, true)
    end
    self:SetText(valueLabel(value))
  end

  function wrapper:GetValue()
    return self.value
  end

  function wrapper:SetList(nextValues)
    self.values = nextValues or {}
    for index = #keys, 1, -1 do keys[index] = nil end
    for key in pairs(self.values) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
      return tostring(valueLabel(a)):lower() < tostring(valueLabel(b)):lower()
    end)
    if self.value ~= nil and self.values[self.value] ~= nil then
      self:SetValue(self.value)
    else
      self.value = nil
    end
  end

  function wrapper:SetDisabled(disabled)
    self.disabled = disabled == true
    local button
    if control and type(control.GetName) == "function" then
      local name = control:GetName()
      if name then button = _G[name .. "Button"] end
    end
    if button then
      if self.disabled and button.Disable then button:Disable()
      elseif not self.disabled and button.Enable then button:Enable() end
    end
  end

  for key in pairs(wrapper.values) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    return tostring(valueLabel(a)):lower() < tostring(valueLabel(b)):lower()
  end)
  _G.MSA_DropDownMenu_Initialize(control, function(_, level)
    if level ~= 1 then return end
    for _, key in ipairs(keys) do
      local info = _G.MSA_DropDownMenu_CreateInfo()
      info.text = valueLabel(key)
      info.value = key
      info.checked = wrapper.value ~= nil and tostring(wrapper.value) == tostring(key)
      info.func = function()
        local canonical = canonicalValue(key) or key
        wrapper:SetValue(canonical)
        if callback then callback(canonical) end
      end
      _G.MSA_DropDownMenu_AddButton(info, level)
    end
  end)
  return wrapper
end

function Adapter.AddDropdown(shell, parent, label, values, callback, width, useMSA)
  if useMSA ~= false and HAS_MSA_DROPDOWN then
    local dropdown = Adapter.AddMSADropdown(shell, parent, label, values, callback, width)
    if dropdown then return dropdown end
  end
  local dropdown = Adapter.Create(shell, "Dropdown", parent)
  if not dropdown then return nil end
  call(dropdown, "SetLabel", label or "")
  call(dropdown, "SetList", values or {})
  call(dropdown, "SetWidth", width or 360)
  call(dropdown, "SetCallback", "OnValueChanged", function(_, _, value)
    local canonical
    if values and values[value] ~= nil then
      canonical = value
    else
      for key, text in pairs(values or {}) do
        if tostring(key) == tostring(value) or tostring(text) == tostring(value) then canonical = key break end
      end
    end
    local selected = canonical or value
    call(dropdown, "SetValue", selected)
    call(dropdown, "SetText", values and values[selected] or selected)
    if callback then callback(selected) end
  end)
  return dropdown
end

function Adapter.AddCheckBox(shell, parent, label, value, callback, width)
  local checkbox = Adapter.Create(shell, "CheckBox", parent)
  if not checkbox then return nil end
  if checkbox.frame and type(checkbox.frame.EnableMouse) == "function" then checkbox.frame:EnableMouse(true) end
  call(checkbox, "SetLabel", label or "")
  if width then call(checkbox, "SetWidth", width) else call(checkbox, "SetFullWidth", true) end
  if value ~= nil then Adapter.SetValue(checkbox, value == true) end
  call(checkbox, "SetCallback", "OnValueChanged", function(_, _, checked)
    if callback then callback(checked == true) end
  end)
  return checkbox
end

function Adapter.AddRange(shell, parent, label, minimum, maximum, step, value, callback, width)
  local slider = Adapter.Create(shell, "Slider", parent)
  if not slider then return nil end
  call(slider, "SetLabel", label or "")
  call(slider, "SetSliderValues", tonumber(minimum) or 0, tonumber(maximum) or 100, tonumber(step) or 1)
  call(slider, "SetWidth", width or 420)
  if value ~= nil then Adapter.SetValue(slider, value) end
  call(slider, "SetCallback", "OnMouseUp", function(_, _, changed)
    if callback then callback(changed) end
  end)
  return slider
end

function Adapter.AddTabs(shell, tabs, onSelect)
  if not shell or not shell.gui then return nil end
  local group = Adapter.Create(shell, "TabGroup", shell.window)
  if not group then return nil end
  call(group, "SetFullWidth", true)
  call(group, "SetFullHeight", true)
  call(group, "SetLayout", "List")
  call(group, "SetTabs", tabs)
  call(group, "SetCallback", "OnGroupSelected", function(_, _, value)
    if onSelect then onSelect(value) end
  end)
  return group
end

function Adapter.AddHeading(shell, parent, text, description)
  local heading = Adapter.Create(shell, "Heading", parent)
  if not heading then return Adapter.AddHeader(shell, parent, text, description) end
  call(heading, "SetFullWidth", true)
  call(heading, "SetText", text or "")
  return Adapter.AddTooltip(heading, text, description)
end

-- Add a navigation tree with a content panel.  TreeGroup is the same
-- navigation pattern used by Blizzard's options and RCLootCouncil: the
-- selected entry stays visible on the left while the page is rendered on
-- the right.  Keep this helper in the adapter so PlayerUI and OfficerUI use
-- the same shell without coupling their page content.
function Adapter.AddTree(shell, tree, onSelect, treeWidth)
  if not shell or not shell.gui then return nil end
  local group = Adapter.Create(shell, "TreeGroup", shell.window)
  if not group then return nil end
  call(group, "SetFullWidth", true)
  call(group, "SetFullHeight", true)
  -- TreeGroup owns a separate content frame for the selected page.  Its
  -- children must use a stacked layout; Fill would place every control at
  -- the same coordinates and leave the page looking empty.
  call(group, "SetLayout", "List")
  if treeWidth then
    call(group, "SetTreeWidth", treeWidth, false)
  end
  call(group, "SetTree", tree or {})
  call(group, "SetCallback", "OnGroupSelected", function(_, _, value)
    if onSelect then onSelect(value) end
  end)
  return group
end

function Adapter.SelectTree(tree, value)
  local selector = tree and (type(tree.SelectByValue) == "function" and tree.SelectByValue or tree.Select)
  if selector then
    local ok, reason = pcall(selector, tree, value)
    if not ok and Dibs.Message then
      Dibs.Message("[ui debug] Tree selection failed: " .. tostring(reason))
    end
    return ok, reason
  end
  return false
end

-- Render an AceConfig group in the same AceGUI surface used by the Officer
-- window.  Keeping this renderer data driven means every option exposed by
-- RCLootCouncilOptions.lua appears in both Blizzard's Settings panel and the
-- standalone Officer window without maintaining a second copy of the rules.
function Adapter.RenderOptionsGroup(shell, parent, group, context)
  if not shell or not parent or type(group) ~= "table" then return false end
  context = context or {}

  -- TreeGroup's content frame is also responsible for the navigation layout.
  -- Keep each options page inside one stacked root so a long ScrollFrame cannot
  -- compete with the heading or leave the selected page looking empty after a
  -- navigation refresh on Retail's AceGUI fork.
  local page = Adapter.Create(shell, "SimpleGroup", parent)
  if page then
    call(page, "SetFullWidth", true)
    call(page, "SetLayout", "List")
  else
    page = parent
  end

  local function evaluate(value, ...)
    if type(value) == "function" then
      local ok, result = pcall(value, ...)
      if ok then return result end
      return nil
    end
    return value
  end

  local function optionName(option, key)
    local value = evaluate(option and option.name)
    return tostring(value or key or "")
  end

  local function isHidden(option)
    return evaluate(option and option.hidden) == true
  end

  local function isDisabled(option)
    return evaluate(option and option.disabled) == true
  end

  local function getValue(option, key)
    if type(option and option.get) ~= "function" then return nil end
    local ok, value = pcall(option.get, nil, key)
    if ok then return value end
    return nil
  end

  local function setValue(option, key, value)
    if type(option and option.set) ~= "function" then return false end
    local ok = pcall(option.set, nil, value)
    return ok
  end

  local function valuesFor(option)
    local values = evaluate(option and option.values)
    return type(values) == "table" and values or {}
  end

  local function register(key, control)
    if context.controlMap and key ~= nil then context.controlMap[key] = control end
    if context.onControl then context.onControl(key, control) end
  end

  local function changed(option, kind)
    -- Rebuild pages after selection changes and actions.  Text, checkboxes and
    -- sliders keep their local value so typing or dragging is not interrupted.
    if context.onChanged and (kind == "select" or kind == "execute") then
      context.onChanged(option, kind)
    end
  end

  local function sortedKeys(args)
    local keys = {}
    for key, option in pairs(args or {}) do
      if type(option) == "table" and not isHidden(option) then keys[#keys + 1] = key end
    end
    table.sort(keys, function(left, right)
      local a, b = args[left], args[right]
      local ao, bo = tonumber(a.order) or 100, tonumber(b.order) or 100
      if ao ~= bo then return ao < bo end
      return tostring(left) < tostring(right)
    end)
    return keys
  end

  local function render(args, target)
    for _, key in ipairs(sortedKeys(args)) do
      local option = args[key]
      local kind = tostring(option.type or "description")
      local label = optionName(option, key)
      local description = evaluate(option.desc)

      if kind == "group" then
        local groupTarget = target
        if label ~= "" then
          if option.inline == true or context.flattenInlineGroups == true then
            Adapter.AddHeader(shell, target, label, description)
          else
            groupTarget = Adapter.AddSection(shell, target, label, description)
          end
        end
        render(option.args, groupTarget)
      elseif kind == "description" or kind == "header" then
        local control = Adapter.AddLabel(shell, target, label, true)
        Adapter.AddTooltip(control, label, description)
        register(key, control)
      elseif kind == "select" then
        local control = Adapter.AddDropdown(shell, target, label, valuesFor(option), function(value)
          setValue(option, nil, value)
          changed(option, kind)
        end, option.width == "double" and 360 or nil)
        if control then
          Adapter.SetValue(control, getValue(option))
          Adapter.SetDisabled(control, isDisabled(option))
          Adapter.AddTooltip(control, label, description)
          register(key, control)
        end
      elseif kind == "range" then
        local control = Adapter.AddRange(shell, target, label, option.min, option.max, option.step, getValue(option), function(value)
          setValue(option, nil, value)
        end, option.width == "double" and 360 or nil)
        if control then
          Adapter.SetDisabled(control, isDisabled(option))
          Adapter.AddTooltip(control, label, description)
          register(key, control)
        end
      elseif kind == "toggle" then
        local control = Adapter.AddCheckBox(shell, target, label, getValue(option), function(value)
          setValue(option, nil, value)
        end, option.width == "double" and 360 or nil)
        if control then
          Adapter.SetDisabled(control, isDisabled(option))
          Adapter.AddTooltip(control, label, description)
          register(key, control)
        end
      elseif kind == "input" then
        local control = Adapter.AddEditBox(shell, target, label, function(value)
          setValue(option, nil, value)
        end, option.width == "double" and 360 or nil)
        if control then
          Adapter.SetText(control, getValue(option) or "")
          Adapter.SetDisabled(control, isDisabled(option))
          Adapter.AddTooltip(control, label, description)
          register(key, control)
        end
      elseif kind == "execute" then
        local control = Adapter.AddButton(shell, target, label, function()
          if type(option.func) == "function" then pcall(option.func) end
          changed(option, kind)
        end, option.width == "half" and 180 or 220)
        if control then
          Adapter.SetDisabled(control, isDisabled(option))
          Adapter.AddTooltip(control, label, description)
          register(key, control)
        end
      elseif kind == "multiselect" then
        local values = valuesFor(option)
        local keys = {}
        for valueKey in pairs(values) do keys[#keys + 1] = valueKey end
        table.sort(keys, function(left, right) return tostring(values[left]) < tostring(values[right]) end)
        local list = Adapter.AddScrollableList(shell, target, math.min(360, math.max(100, #keys * 28 + 20)))
        if list then
          Adapter.AddHeader(shell, list, label, description)
          for _, valueKey in ipairs(keys) do
            local checkbox = Adapter.AddCheckBox(shell, list, values[valueKey], getValue(option, valueKey), function(value)
              setValue(option, valueKey, value)
            end)
            if checkbox then
              Adapter.SetDisabled(checkbox, isDisabled(option))
              register(valueKey, checkbox)
            end
          end
          register(key, list)
        end
      end
    end
  end

  local groupTitle = evaluate(group.name)
  if groupTitle and tostring(groupTitle) ~= "" and context.renderGroupTitle ~= false then
    Adapter.AddHeading(shell, page, tostring(groupTitle))
  end

  -- Long pages such as Rank Rules and Settings need their own scroll frame;
  -- TreeGroup only scrolls the navigation column.  Fall back to the content
  -- panel when an older AceGUI build does not provide ScrollFrame.
  local target = page
  if context.scroll ~= false then
    target = Adapter.AddScrollableList(shell, page, context.pageHeight or 680) or page
  end
  render(group.args, target)
  if context.onRendered then context.onRendered(target) end
  return true
end

function Adapter.AddScrollableList(shell, parent, height)
  if parent and parent.type == "ScrollFrame" then return parent end
  local scroll = Adapter.Create(shell, "ScrollFrame", parent)
  if not scroll then
    scroll = Adapter.Create(shell, "SimpleGroup", parent)
  end
  if not scroll then return nil end
  local metrics = Adapter.GetLayoutMetrics()
  local requestedHeight = tonumber(height) or metrics.defaultScrollHeight or 260
  local frameHeight = shell and shell.frame and shell.frame.GetHeight and shell.frame:GetHeight() or nil
  if frameHeight and frameHeight > 0 then
    requestedHeight = math.min(requestedHeight, math.max(240, frameHeight - 180))
  end
  call(scroll, "SetHeight", requestedHeight)
  call(scroll, "SetFullWidth", true)
  call(scroll, "SetLayout", "List")
  -- Long pages should follow a resizable Dibs window. Keep compact embedded
  -- lists (for example multiselect checkboxes) at their requested height.
  if shell and requestedHeight >= 380 and frameHeight and frameHeight > requestedHeight then
    scroll._dibsShell = shell
    scroll._dibsResizeOffset = frameHeight - requestedHeight
    shell._dibsResponsiveScrolls = shell._dibsResponsiveScrolls or {}
    shell._dibsResponsiveScrolls[#shell._dibsResponsiveScrolls + 1] = scroll
  end
  return scroll
end

function Adapter.AddSearch(shell, onChanged)
  if not shell or not shell.gui then return nil end
  local search = Adapter.Create(shell, "EditBox", shell.window)
  if not search then return nil end
  call(search, "SetLabel", "Search")
  call(search, "SetCallback", "OnTextChanged", function(_, _, value)
    if onChanged then onChanged(value) end
  end)
  return search
end

function Adapter.AddPagination(shell, onPrevious, onNext)
  if not shell or not shell.gui then return nil end
  local controls = {}
  for _, definition in ipairs({ { "Previous", onPrevious }, { "Next", onNext } }) do
    local button = Adapter.Create(shell, "Button", shell.window)
    if button then
      call(button, "SetText", definition[1])
      call(button, "SetCallback", "OnClick", function()
        if definition[2] then definition[2]() end
      end)
      Adapter.AddTooltip(button, definition[1], definition[1] == "Previous" and "Show the previous page." or "Show the next page.")
      table.insert(controls, button)
    end
  end
  return controls
end

if Dibs.Ace3 and Dibs.Ace3.RegisterEvent then
  Dibs.Ace3.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    Adapter.FlushRefreshes()
  end)
end
