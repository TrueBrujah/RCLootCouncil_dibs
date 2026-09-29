--[[
Module: Dibs.AceGUI
Layer: UI toolkit adapter
Purpose: Provide consistent AceGUI container, Data Grid, and action helpers.
Responsibilities: Widget construction, grid interactions, safe callbacks, and layout sizing.
Non-responsibilities: It does not decide business policy or persist data.
Dependencies: AceGUI-3.0 and Dibs.Ace3.
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

local function clearTooltipAttachment(widget)
  local attachment = widget and widget._dibsTooltipAttachment
  if not attachment then return end
  local frame = attachment.frame
  if frame and type(frame.SetScript) == "function" then
    local currentEnter = type(frame.GetScript) == "function" and frame:GetScript("OnEnter") or nil
    local currentLeave = type(frame.GetScript) == "function" and frame:GetScript("OnLeave") or nil
    if currentEnter == attachment.onEnter or type(frame.GetScript) ~= "function" then
      frame:SetScript("OnEnter", attachment.previousEnter)
    end
    if currentLeave == attachment.onLeave or type(frame.GetScript) ~= "function" then
      frame:SetScript("OnLeave", attachment.previousLeave)
    end
  end
  if GameTooltip and type(GameTooltip.Hide) == "function" then pcall(GameTooltip.Hide, GameTooltip) end
  widget._dibsTooltipAttachment = nil
end

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

local function call(widget, method, ...)
  if widget and type(widget[method]) == "function" then
    return pcall(widget[method], widget, ...)
  end
  return false
end

function Adapter.GetLayoutMetrics()
  if Dibs.Midnight and type(Dibs.Midnight.GetLayoutMetrics) == "function" then
    local metrics = Dibs.Midnight.GetLayoutMetrics()
    local tokens = Adapter.GetPresentationTokens() or {}
    local spacing = tokens.spacing or {}
    local sizing = tokens.sizing or {}
    metrics.tableColumnGap = math.max(0, tonumber(spacing.xs) or 4)
    metrics.tableHorizontalPadding = math.max(0, tonumber(spacing.sm) or 8)
    metrics.tableScrollbarReserve = math.max(12, tonumber(sizing.scrollbarReserve) or 18)
    metrics.tableVerticalGap = math.max(0, tonumber(spacing.xs) or 4)
    metrics.tableFooterHeight = math.max(metrics.buttonHeight, tonumber(sizing.tableFooterHeight) or metrics.buttonHeight + 8)
    metrics.tableViewportMinimum = math.max(96, tonumber(sizing.tableViewportMinimum) or 120)
    metrics.buttonHorizontalPadding = 30
    metrics.buttonSizingSafetyMargin = 8
    metrics.selectHeight = math.max(24, tonumber(sizing.selectHeight) or 28)
    metrics.selectLabelHeight = math.max(12, tonumber(sizing.selectLabelHeight) or 16)
    metrics.selectMinWidth = math.max(100, tonumber(sizing.selectMinWidth) or 150)
    metrics.selectMaxWidth = math.max(180, tonumber(sizing.selectMaxWidth) or 420)
    metrics.selectPadding = math.max(4, tonumber(sizing.selectPadding) or 8)
    metrics.selectArrowSize = math.max(10, tonumber(sizing.selectArrowSize) or 14)
    metrics.selectArrowSpacing = math.max(4, tonumber(sizing.selectArrowSpacing) or 8)
    return metrics
  end
  return {
    minWidth = 520, minHeight = 360, maxWidth = 1400, maxHeight = 1100,
    actionMinWidth = 88, rowHeight = 24, buttonHeight = 24,
    tableColumnGap = 4, tableHorizontalPadding = 8, tableScrollbarReserve = 18,
    tableVerticalGap = 4, tableFooterHeight = 32, tableViewportMinimum = 120,
    buttonHorizontalPadding = 30,
    buttonSizingSafetyMargin = 8,
    selectHeight = 28, selectLabelHeight = 16, selectMinWidth = 150,
    selectMaxWidth = 420, selectPadding = 8, selectArrowSize = 14, selectArrowSpacing = 8,
  }
end

local measuredTextFontString
local measuredTextWidths = {}
local measuredTextLocale

function Adapter.MeasureTextWidth(text)
  local value = tostring(text or "")
  local locale = type(_G.GetLocale) == "function" and _G.GetLocale() or "unknown"
  if measuredTextLocale ~= locale then
    measuredTextLocale = locale
    measuredTextWidths = {}
  end
  if measuredTextWidths[value] then return measuredTextWidths[value] end
  local parent = _G.UIParent
  if not measuredTextFontString and parent and type(parent.CreateFontString) == "function" then
    local ok, fontString = pcall(parent.CreateFontString, parent, nil, "ARTWORK", "GameFontNormal")
    if ok then measuredTextFontString = fontString end
  end
  local width
  if measuredTextFontString then
    if measuredTextFontString.SetText then pcall(measuredTextFontString.SetText, measuredTextFontString, value) end
    if measuredTextFontString.GetStringWidth then
      local ok, measured = pcall(measuredTextFontString.GetStringWidth, measuredTextFontString)
      if ok then width = tonumber(measured) end
    end
  end
  width = math.ceil(width or (#value * 8))
  measuredTextWidths[value] = width
  return width
end

function Adapter.GetContentSizedActionWidth(labels, minimumWidth)
  local metrics = Adapter.GetLayoutMetrics()
  local maximumTextWidth = 0
  if type(labels) == "string" then labels = { labels } end
  for _, label in ipairs(labels or {}) do
    maximumTextWidth = math.max(maximumTextWidth, Adapter.MeasureTextWidth(label))
  end
  return math.max(tonumber(minimumWidth) or metrics.actionMinWidth,
    maximumTextWidth + (tonumber(metrics.buttonHorizontalPadding) or 30)
      + (tonumber(metrics.buttonSizingSafetyMargin) or 8))
end

function Adapter.GetPageSlice(rows, page, pageSize)
  local source = rows or {}
  local size = math.max(1, math.floor(tonumber(pageSize) or 10))
  local rowCount = #source
  local totalPages = math.max(1, math.ceil(rowCount / size))
  local currentPage = math.min(totalPages, math.max(1, math.floor(tonumber(page) or 1)))
  local firstIndex = ((currentPage - 1) * size) + 1
  local lastIndex = math.min(rowCount, currentPage * size)
  local visibleRows = {}
  for index = firstIndex, lastIndex do
    if source[index] ~= nil then visibleRows[#visibleRows + 1] = source[index] end
  end
  return visibleRows, currentPage, totalPages, rowCount, firstIndex, lastIndex
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

function Adapter.AllocateFluidColumnWidths(columns, contentWidth, options)
  local definitions = columns or {}
  options = options or {}
  local widths, flexible = {}, {}
  local fixedTotal, flexibleMinimumTotal = 0, 0
  local gaps = math.max(0, #definitions - 1) * math.max(0, tonumber(options.columnGap) or 0)
  local insets = math.max(0, tonumber(options.horizontalPadding) or 0)
    + math.max(0, tonumber(options.scrollbarReserve) or 0) + gaps
  local available = math.max(0, (tonumber(contentWidth) or 0) - insets)

  for index, column in ipairs(definitions) do
    local minimum = math.max(0, tonumber(column.minWidth) or 0)
    local width = math.max(minimum, tonumber(column.width) or minimum)
    local weight = not column.fixed and math.max(0, tonumber(column.weight) or 0) or 0
    if weight > 0 then
      widths[index] = minimum
      flexible[#flexible + 1] = { index = index, weight = weight }
      flexibleMinimumTotal = flexibleMinimumTotal + minimum
    else
      widths[index] = width
      fixedTotal = fixedTotal + width
    end
  end

  local remaining = available - fixedTotal - flexibleMinimumTotal
  local totalWeight = 0
  for _, column in ipairs(flexible) do totalWeight = totalWeight + column.weight end
  if remaining > 0 and totalWeight > 0 then
    for _, column in ipairs(flexible) do
      widths[column.index] = widths[column.index] + remaining * column.weight / totalWeight
    end
  end

  local used = fixedTotal + flexibleMinimumTotal + math.max(0, remaining)
  return widths, used > available, used + insets
end

local function fluidColumnBudget(columns, options, preferred)
  options = options or {}
  local definitions = columns or {}
  local width = math.max(0, #definitions - 1) * math.max(0, tonumber(options.columnGap) or 0)
    + math.max(0, tonumber(options.horizontalPadding) or 0)
    + math.max(0, tonumber(options.scrollbarReserve) or 0)
  for _, column in ipairs(definitions) do
    local minimum = math.max(0, tonumber(column.minWidth) or 0)
    local isFlexible = not column.fixed and (tonumber(column.weight) or 0) > 0
    if preferred or not isFlexible then
      width = width + math.max(minimum, tonumber(column.width) or minimum)
    else
      width = width + minimum
    end
  end
  return width
end

function Adapter.GetFluidColumnMinimumWidth(columns, options)
  return fluidColumnBudget(columns, options, false)
end

function Adapter.GetFluidColumnPreferredWidth(columns, options)
  return fluidColumnBudget(columns, options, true)
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
    window.frame:HookScript("OnSizeChanged", function(frame, width, height)
      local activeShell = frame._dibsWindowShell
      if not activeShell or not activeShell._dibsActive then return end
      local activeWindow = activeShell.window
      width = tonumber(width) or (frame.GetWidth and frame:GetWidth()) or nil
      height = tonumber(height) or (frame.GetHeight and frame:GetHeight()) or nil
      if activeShell.layout then
        if width then activeShell.layout.width = width end
        if height then activeShell.layout.height = height end
      end
      if activeWindow and activeWindow.DoLayout then activeWindow:DoLayout() end
      if height or width then
        for _, scroll in ipairs(activeShell._dibsResponsiveScrolls) do
          if scroll and type(scroll._dibsViewportUpdater) == "function" then
            pcall(scroll._dibsViewportUpdater)
          elseif scroll and scroll.SetHeight and scroll._dibsResizeOffset then
            scroll:SetHeight(math.max(120, height - scroll._dibsResizeOffset))
          end
          if width and scroll and not scroll._dibsViewportUpdater
            and type(scroll._dibsApplyFluidWidth) == "function" then
            local availableWidth = scroll.frame and scroll.frame.GetWidth and scroll.frame:GetWidth() or 0
            if availableWidth <= 0 then availableWidth = math.max(240, width - 220) end
            pcall(scroll._dibsApplyFluidWidth, availableWidth)
          end
          if scroll and scroll.DoLayout then scroll:DoLayout() end
        end
      end
      for _, callback in ipairs(activeShell._dibsResizeHandlers) do
        pcall(callback, activeShell, width, height)
      end
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
  for scriptName, attachment in pairs(widget._dibsGridScripts or {}) do
    local frame = attachment.frame
    if frame and type(frame.GetScript) == "function" and type(frame.SetScript) == "function"
      and frame:GetScript(scriptName) == attachment.handler then
      frame:SetScript(scriptName, attachment.previous)
    end
  end
  widget._dibsGridScripts = nil
  clearTooltipAttachment(widget)
  if widget._dibsGridSelectionTexture then
    if widget._dibsGridSelectionTexture.Hide then widget._dibsGridSelectionTexture:Hide() end
    widget._dibsGridSelectionTexture = nil
  end
  clearTooltipAttachment(widget._dibsTooltipFrame)
  widget._dibsTooltipFrame = nil
  local selectMenu = widget._dibsSelectMenu
  if selectMenu and selectMenu.open and selectMenu.pullout and type(selectMenu.pullout.Close) == "function" then
    pcall(selectMenu.pullout.Close, selectMenu.pullout)
  end
  widget._dibsSelectMenu = nil
  widget._dibsSelectLabel = nil
  widget._dibsSelectWrapper = nil
  widget._dibsSelectValues = nil
  local selectTrigger = widget._dibsSelectTrigger
  if selectTrigger then
    if selectTrigger.Hide then pcall(selectTrigger.Hide, selectTrigger) end
    if selectTrigger.ClearAllPoints then pcall(selectTrigger.ClearAllPoints, selectTrigger) end
    if selectTrigger.SetScript then
      for _, scriptName in ipairs({ "OnClick", "OnEnter", "OnLeave", "OnFocusGained", "OnFocusLost", "OnKeyDown", "OnKeyUp" }) do
        pcall(selectTrigger.SetScript, selectTrigger, scriptName, nil)
      end
    end
    if selectTrigger.SetParent then pcall(selectTrigger.SetParent, selectTrigger, nil) end
    widget._dibsSelectTrigger = nil
  end
  local resize = widget._dibsSelectResize
  if resize and resize.frame and type(resize.frame.SetScript) == "function" then
    local current = type(resize.frame.GetScript) == "function" and resize.frame:GetScript("OnSizeChanged") or nil
    if current == resize.handler or type(resize.frame.GetScript) ~= "function" then
      resize.frame:SetScript("OnSizeChanged", resize.previous)
    end
  end
  widget._dibsSelectResize = nil
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
  -- AceGUI reuses SimpleGroup instances.  Restore the widget's original
  -- width handler before returning a table host to the pool; otherwise a
  -- later, unrelated SimpleGroup keeps the previous table closure and can
  -- reflow a released native frame.
  if widget._dibsTableWidthHandler and widget.OnWidthSet == widget._dibsTableWidthHandler then
    widget.OnWidthSet = widget._dibsBaseOnWidthSet
  end
  widget._dibsTableWidthHandler = nil
  widget._dibsBaseOnWidthSet = nil
  if widget._dibsTablePageLayout and widget.LayoutFunc == widget._dibsTablePageLayout then
    widget.LayoutFunc = widget._dibsBaseLayoutFunc
  end
  widget._dibsTablePageLayout = nil
  widget._dibsBaseLayoutFunc = nil
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

function Adapter.AttachHelp(widget, title, description)
  local frame = widget and (widget.frame or widget)
  if not frame or type(frame.SetScript) ~= "function" then
    return widget
  end
  clearTooltipAttachment(widget)
  local previousEnter = type(frame.GetScript) == "function" and frame:GetScript("OnEnter") or nil
  local previousLeave = type(frame.GetScript) == "function" and frame:GetScript("OnLeave") or nil
  local onEnter = function(self, ...)
    if previousEnter then previousEnter(self, ...) end
    if not GameTooltip or type(GameTooltip.SetOwner) ~= "function" then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(tostring(title or ""), 1, 0.82, 0, 1)
    if description and description ~= "" and GameTooltip.AddLine then
      GameTooltip:AddLine(tostring(description), 1, 1, 1, true)
    end
    if GameTooltip.Show then GameTooltip:Show() end
  end
  local onLeave = function(self, ...)
    if GameTooltip and type(GameTooltip.Hide) == "function" then GameTooltip:Hide() end
    if previousLeave then previousLeave(self, ...) end
  end
  frame:SetScript("OnEnter", onEnter)
  frame:SetScript("OnLeave", onLeave)
  widget._dibsTooltipAttachment = {
    frame = frame, onEnter = onEnter, onLeave = onLeave,
    previousEnter = previousEnter, previousLeave = previousLeave,
  }
  return widget
end

Adapter.AddTooltip = Adapter.AttachHelp

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

function Adapter.AddTable(shell, parent, columns, rows, height, rowActions, options)
  options = options or {}
  local scroll = options.noScrolling and parent or (parent and parent.type == "ScrollFrame" and parent or Adapter.AddScrollableList(shell, parent, height))
  if not scroll then return nil end
  local definitions = columns or {}
  local actionLabelsByColumn = {}
  for index, column in ipairs(definitions) do
    if column.action or (rowActions and index == #definitions) then
      local labels = {}
      for _, label in ipairs(column.actionLabels or {}) do labels[#labels + 1] = label end
      if column.title and column.title ~= "Action" then labels[#labels + 1] = column.title end
      actionLabelsByColumn[index] = labels
    end
  end
  for index, column in ipairs(definitions) do
    if column.action or (rowActions and index == #definitions) then
      local requiredWidth = Adapter.GetContentSizedActionWidth(actionLabelsByColumn[index] or {},
        tonumber(column.minWidth) or 0)
      column.width = math.max(tonumber(column.width) or 0, requiredWidth)
      column.minWidth = math.max(tonumber(column.minWidth) or 0, requiredWidth)
      column.fixed = true
      column.weight = nil
    end
  end
  local desiredWidth = 0
  for _, column in ipairs(definitions) do desiredWidth = desiredWidth + (tonumber(column.width) or 100) end
  local frameWidth = tonumber(options.widthHint) or (scroll.frame and scroll.frame.GetWidth and scroll.frame:GetWidth() or 0)
  if frameWidth <= 0 and parent and parent.frame and parent.frame.GetWidth then frameWidth = parent.frame:GetWidth() or 0 end
  if frameWidth <= 0 and shell and shell.frame and shell.frame.GetWidth then frameWidth = (shell.frame:GetWidth() or 760) - 220 end
  if options.fluidColumns then
    if frameWidth <= 0 then frameWidth = math.min(desiredWidth, 760) end
  else
    frameWidth = math.max(360, frameWidth > 0 and frameWidth - 8 or math.min(desiredWidth, 760))
  end
  local fitDefinitions = {}
  for index, column in ipairs(definitions) do
    local title = string.lower(tostring(column.title or column.name or ""))
    local action = column.action == true or (rowActions and index == #definitions)
    local minimum = column.minWidth
    local priority = column.priority
    if not minimum and title:find("player", 1, true) then minimum = 120 end
    if not minimum and title:find("item", 1, true) then minimum = 140 end
    if not minimum and title:find("status", 1, true) then minimum = 88 end
    if action then minimum, priority = minimum or Adapter.GetLayoutMetrics().actionMinWidth, priority or 100 end
    local contentSizedAction = column.action == true or (rowActions and index == #definitions)
    fitDefinitions[index] = {
      width = column.width, minWidth = minimum,
      priority = priority, action = action, fixed = contentSizedAction or column.fixed,
      weight = contentSizedAction and 0 or column.weight,
    }
  end
  local widths
  local fluidOptions = {
    horizontalPadding = options.horizontalPadding or 0,
    scrollbarReserve = options.scrollbarReserve or 0,
    columnGap = options.columnGap or 0,
  }
  if options.fluidColumns then
    widths = Adapter.AllocateFluidColumnWidths(fitDefinitions, frameWidth, fluidOptions)
  else
    widths = Adapter.FitColumnWidths(fitDefinitions, frameWidth)
  end
  local function promoteActionWidth(index, requiredWidth)
    local definition = fitDefinitions[index]
    if not definition or not definition.fixed or not requiredWidth then return end
    local width = math.ceil(tonumber(requiredWidth) or 0)
    if width <= (tonumber(widths[index]) or 0) then return end
    widths[index] = width
    definition.width, definition.minWidth = width, width
    definitions[index].width, definitions[index].minWidth = width, width
  end
  local actualWidth = 0
  for index in ipairs(definitions) do actualWidth = actualWidth + widths[index] end

  local function cellText(value, width, preserveText)
    local result = tostring(value or "")
    if preserveText then return result end
    -- Let WoW render a complete hyperlink. Truncating the colour and Hitem
    -- escape sequence makes the visible cell look like raw `[Hitem:...]` text.
    if result:find("|Hitem:", 1, true) then return result end
    local characters = math.max(8, math.floor((width or 100) / 7))
    if Dibs.Midnight and Dibs.Midnight.Truncate then result = Dibs.Midnight.Truncate(result, characters) end
    return result
  end

  local renderedGroups = {}
  local gridRows = {}
  local headerCells = {}
  local gridState = { columns = definitions, rows = {}, selectedRow = nil }
  scroll._dibsDataGrid = gridState
  local function attachGridScript(widget, scriptName, callback)
    local frame = widget and widget.frame
    if not frame or type(frame.SetScript) ~= "function" then return end
    local previous = type(frame.GetScript) == "function" and frame:GetScript(scriptName) or nil
    local handler = function(self, ...)
      if previous then previous(self, ...) end
      return callback(self, ...)
    end
    frame:SetScript(scriptName, handler)
    widget._dibsGridScripts = widget._dibsGridScripts or {}
    widget._dibsGridScripts[scriptName] = { frame = frame, handler = handler, previous = previous }
  end

  local function showDataGridContextMenu(record)
    local entries = {}
    local action = record and record.action
    if action and type(action.callback) == "function" then
      entries[#entries + 1] = { text = action.text or "Open", callback = action.callback }
    end
    if record and type(options.contextMenu) == "function" then
      local ok, custom = pcall(options.contextMenu, record.source, gridState)
      if ok and type(custom) == "table" then
        for _, entry in ipairs(custom) do
          if type(entry) == "table" and type(entry.callback) == "function" then
            entries[#entries + 1] = {
              text = entry.text or "Action", callback = entry.callback, disabled = entry.disabled == true,
            }
          end
        end
      end
    end
    if options.allowTableSort ~= false then
      for index, column in ipairs(definitions) do
        if column.sortable ~= false and not column.action then
          local title = safeContextText(column.title or column.name or ("Column " .. tostring(index)))
          entries[#entries + 1] = {
            text = title .. " (A-Z)", callback = function() gridState.Sort(index, "asc") end,
          }
          entries[#entries + 1] = {
            text = title .. " (Z-A)", callback = function() gridState.Sort(index, "desc") end,
          }
        end
      end
    end
    return #entries > 0 and Adapter.ShowContextMenu(entries) or false
  end

  local function updateGridSelection()
    for _, record in ipairs(gridRows) do
      local selected = record.source == gridState.selectedRow
      record.widget._dibsGridSelected = selected
      local texture = record.widget._dibsGridSelectionTexture
      if texture then
        if selected and texture.Show then texture:Show()
        elseif texture.Hide then texture:Hide() end
      end
    end
  end

  local sortGrid
  local function addGridRow(values, action, header, target)
    local rowGroup = Adapter.Create(shell, "SimpleGroup", target or scroll)
    if not rowGroup then return end
    renderedGroups[#renderedGroups + 1] = rowGroup
    call(rowGroup, "SetFullWidth", true)
    call(rowGroup, "SetLayout", "Flow")
    if options.rowHeight then call(rowGroup, "SetHeight", tonumber(options.rowHeight)) end
    local record = not header and { source = values, action = action, widget = rowGroup } or nil
    if record then
      rowGroup._dibsDataGridRow = true
      gridRows[#gridRows + 1] = record
      local frame = rowGroup.frame
      if frame and type(frame.CreateTexture) == "function" then
        local texture = frame:CreateTexture(nil, "BACKGROUND")
        local tokens = Adapter.GetPresentationTokens()
        local primary = tokens and tokens.colors and tokens.colors.PRIMARY or { 0.20, 0.55, 0.82, 1 }
        if texture and texture.SetColorTexture then
          texture:SetColorTexture(primary[1], primary[2], primary[3], 0.20)
          if texture.SetAllPoints then texture:SetAllPoints(frame) end
          if texture.Hide then texture:Hide() end
          rowGroup._dibsGridSelectionTexture = texture
        end
      end
    end
    local columnCount = action and math.max(0, #definitions - 1) or #definitions
    for index = 1, columnCount do
      local column = definitions[index]
      local value = header and column.title or values[index]
      local cellAction = not header and options.cellAction and options.cellAction(values, index)
      local cell
      if header and column.sortable ~= false and not column.action
        and (options.onHeaderClick or options.allowTableSort ~= false) then
        cell = Adapter.AddButton(shell, rowGroup, value, function()
          if options.onHeaderClick then options.onHeaderClick(column, index)
          elseif sortGrid then sortGrid(index) end
        end, widths[index])
        if cell then headerCells[index] = cell end
      elseif cellAction then
        cell = Adapter.AddButton(shell, rowGroup, cellAction.text or value, cellAction.callback, widths[index],
          Adapter.GetLayoutMetrics().buttonSizingSafetyMargin)
        Adapter.SetDisabled(cell, cellAction.disabled)
        Adapter.AddTooltip(cell, cellAction.text, cellAction.tooltip)
      else
        cell = Adapter.AddLabel(shell, rowGroup, cellText(value, widths[index], column.wrap), false)
      end
      if cell then
        if cellAction then promoteActionWidth(index, cell._dibsRequiredWidth) end
        local cellWidth = math.max(widths[index], tonumber(cell._dibsRequiredWidth) or 0)
        cell._dibsColumnWidth = widths[index]
        cell._dibsColumnIndex = index
        call(cell, "SetWidth", cellWidth)
        if cell.SetJustifyH then cell:SetJustifyH(column.align or "LEFT") end
        if not cellAction then
          local tooltip = header and column.tooltip or (options.cellTooltip and options.cellTooltip(values, index) or column.tooltip)
          if options.disableCellTooltips ~= true then Adapter.AddTooltip(cell, value, tooltip) end
          if not header and record then
            attachGridScript(cell, "OnMouseUp", function(_, mouseButton)
              if mouseButton == "RightButton" then
                if options.disableContextMenu then return true end
                return showDataGridContextMenu(record)
              end
              if mouseButton and mouseButton ~= "LeftButton" then return false end
              gridState.selectedRow = gridState.selectedRow == record.source and nil or record.source
              updateGridSelection()
              if type(options.onRowClick) == "function" then options.onRowClick(record.source, index) end
              return true
            end)
            if cell.frame and cell.frame.EnableMouse then cell.frame:EnableMouse(true) end
            if cell.frame and cell.frame.RegisterForClicks then cell.frame:RegisterForClicks("AnyUp") end
            if options.disableCellTooltips ~= true and type(value) == "string" and value:find("|Hitem:", 1, true) then
              attachGridScript(cell, "OnEnter", function(frame)
                showTableCellTooltip(frame, value)
              end)
            end
          end
        end
      end
    end
    if action then
      -- The action lives in the final cell's visual column, so it stays on
      -- the same row as its request even when the table is narrow.
      local columnWidth = widths[#definitions] or 86
      local button = Adapter.AddButton(shell, rowGroup, action.text or "Action", action.callback, columnWidth,
        Adapter.GetLayoutMetrics().buttonSizingSafetyMargin)
      if button then
        promoteActionWidth(#definitions, button._dibsRequiredWidth)
        columnWidth = widths[#definitions] or columnWidth
        button._dibsColumnWidth = columnWidth
        button._dibsColumnIndex = #definitions
        call(button, "SetWidth", math.max(columnWidth, tonumber(button._dibsRequiredWidth) or 0))
      end
    end
    return rowGroup
  end

  local headerTarget = options.headerParent or scroll
  addGridRow({}, nil, true, headerTarget)
  if #(rows or {}) == 0 and options.emptyText then
    Adapter.AddLabel(shell, scroll, options.emptyText, true)
  end
  for _, row in ipairs(rows or {}) do
    local action = rowActions and rowActions(row) or nil
    gridState.rows[#gridState.rows + 1] = row
    addGridRow(row, action, false)
  end
  sortGrid = function(index, direction)
    local column = definitions[index]
    if not column or column.sortable == false or column.action then return false end
    if direction ~= "asc" and direction ~= "desc" then
      direction = gridState.sortColumn == index and (gridState.sortDirection == "asc" and "desc" or "asc") or "desc"
    end
    gridState.sortColumn, gridState.sortDirection = index, direction
    table.sort(gridRows, function(left, right)
      local leftValue, rightValue = left.source[index], right.source[index]
      if type(column.sortValue) == "function" then
        local leftOk, leftSorted = pcall(column.sortValue, left.source)
        local rightOk, rightSorted = pcall(column.sortValue, right.source)
        if leftOk then leftValue = leftSorted end
        if rightOk then rightValue = rightSorted end
      end
      local leftNumber, rightNumber = tonumber(leftValue), tonumber(rightValue)
      local less
      if leftNumber and rightNumber then less = leftNumber < rightNumber
      else less = string.lower(tostring(leftValue or "")) < string.lower(tostring(rightValue or "")) end
      local equal = leftValue == rightValue or tostring(leftValue or "") == tostring(rightValue or "")
      if equal then return left.originalIndex < right.originalIndex end
      if direction == "asc" then return less end
      return not less
    end)
    gridState.rows = {}
    local childPositions = {}
    for childIndex, child in ipairs(scroll.children or {}) do
      if child._dibsDataGridRow then childPositions[#childPositions + 1] = childIndex end
    end
    for rowIndex, record in ipairs(gridRows) do
      gridState.rows[rowIndex] = record.source
      if childPositions[rowIndex] then scroll.children[childPositions[rowIndex]] = record.widget end
    end
    for index, cell in pairs(headerCells) do
      local title = tostring(definitions[index].title or definitions[index].name or ("Column " .. tostring(index)))
      local marker = index == gridState.sortColumn and (gridState.sortDirection == "asc" and "  ^" or "  v") or ""
      Adapter.SetText(cell, title .. marker)
    end
    updateGridSelection()
    if scroll.DoLayout then pcall(scroll.DoLayout, scroll) end
    return true
  end
  gridState.Sort = sortGrid
  gridState.Select = function(row)
    gridState.selectedRow = gridState.selectedRow == row and nil or row
    updateGridSelection()
    return gridState.selectedRow
  end
  for rowIndex, record in ipairs(gridRows) do record.originalIndex = rowIndex end
  local defaultColumn = options.defaultSortColumn
  if not defaultColumn then
    for index, column in ipairs(definitions) do
      local title = string.lower(tostring(column.title or column.name or ""))
      if title:find("date", 1, true) or title:find("time", 1, true) then defaultColumn = index; break end
    end
  end
  if defaultColumn and options.allowTableSort ~= false then sortGrid(defaultColumn, options.defaultSortDirection or "desc") end
  local function applyAllocatedWidths(nextWidths)
    for _, rowGroup in ipairs(renderedGroups) do
      for index, cell in ipairs(rowGroup.children or {}) do
        if nextWidths[index] then
          local cellWidth = math.max(nextWidths[index], tonumber(cell._dibsRequiredWidth) or 0)
          cell._dibsColumnWidth = nextWidths[index]
          cell._dibsColumnIndex = index
          call(cell, "SetWidth", cellWidth)
        end
      end
      if rowGroup.DoLayout then pcall(rowGroup.DoLayout, rowGroup) end
    end
    local headerContainer = options.headerParent
    if headerContainer and headerContainer.DoLayout then pcall(headerContainer.DoLayout, headerContainer) end
  end
  local function applyFluidWidth(width)
    local nextWidths
    if options.fluidColumns then
      nextWidths = Adapter.AllocateFluidColumnWidths(fitDefinitions, width, fluidOptions)
    else
      nextWidths = Adapter.FitColumnWidths(fitDefinitions, width)
    end
    applyAllocatedWidths(nextWidths)
  end
  scroll._dibsApplyFluidWidth = applyFluidWidth
  if shell then
    scroll._dibsShell = shell
    shell._dibsResponsiveScrolls = shell._dibsResponsiveScrolls or {}
    local alreadyRegistered = false
    for _, registered in ipairs(shell._dibsResponsiveScrolls) do
      if registered == scroll then alreadyRegistered = true; break end
    end
    if not alreadyRegistered then shell._dibsResponsiveScrolls[#shell._dibsResponsiveScrolls + 1] = scroll end
  end
  applyFluidWidth(frameWidth)
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

function Adapter.AddButton(shell, parent, text, callback, width, sizingSafetyMargin)
  local button = Adapter.Create(shell, "Button", parent)
  if not button then return nil end
  Adapter.SetText(button, text)
  call(button, "SetAutoWidth", true)
  call(button, "SetHeight", Adapter.GetLayoutMetrics().buttonHeight)
  local fontString = type(button.text) == "table" and button.text or nil
  if not fontString and button.frame and type(button.frame.GetFontString) == "function" then
    local ok, result = pcall(button.frame.GetFontString, button.frame)
    if ok then fontString = result end
  end
  local labelWidth
  if fontString and type(fontString.GetStringWidth) == "function" then
    local ok, measured = pcall(fontString.GetStringWidth, fontString)
    if ok then labelWidth = tonumber(measured) end
  end
  labelWidth = math.max(0, labelWidth or Adapter.MeasureTextWidth(text))
  local metrics = Adapter.GetLayoutMetrics()
  local requiredWidth = math.ceil(labelWidth + (tonumber(metrics.buttonHorizontalPadding) or 30)
    + math.max(0, tonumber(sizingSafetyMargin) or 0))
  local autoWidth = button.frame and type(button.frame.GetWidth) == "function"
    and tonumber(button.frame:GetWidth()) or 0
  button._dibsLabelWidth = labelWidth
  button._dibsRequiredWidth = requiredWidth
  button._dibsHorizontalPadding = tonumber(metrics.buttonHorizontalPadding) or 30
  button._dibsSizingSafetyMargin = math.max(0, tonumber(sizingSafetyMargin) or 0)
  call(button, "SetWidth", math.max(tonumber(width) or 0, autoWidth or 0, requiredWidth))
  call(button, "SetCallback", "OnClick", function()
    if callback then callback() end
  end)
  return button
end

function Adapter.AddHelpButton(shell, parent, title, description)
  local button = Adapter.AddButton(shell, parent, "?", function() end, 32)
  if not button then return nil end
  call(button, "SetAutoWidth", false)
  call(button, "SetWidth", 32)
  button._dibsHelpTitle = tostring(title or "Help")
  button._dibsHelpDescription = tostring(description or "")
  Adapter.AddTooltip(button, button._dibsHelpTitle, button._dibsHelpDescription)
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
  if useMSA == true and HAS_MSA_DROPDOWN then
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

function Adapter.AddDibsSelect(shell, parent, label, values, callback, width, options)
  if type(width) == "table" then options, width = width, width.width end
  options = type(options) == "table" and options or {}
  local sourceValues = type(values) == "table" and values or {}
  local copiedValues = {}
  for key, value in pairs(sourceValues) do copiedValues[key] = value end
  if not shell or not parent then return nil end

  local selectedValue = options.value
  local dropdown = Adapter.AddDropdown(shell, parent, label, copiedValues, function(value)
    selectedValue = value
    if callback then callback(value) end
  end, width, false)
  if not dropdown then return nil end
  local setValue, setList, setText, setDisabled = dropdown.SetValue, dropdown.SetList,
    dropdown.SetText, dropdown.SetDisabled
  local disabled = options.disabled == true
  local readOnly = options.readOnly == true
  local function canonicalValue(value)
    if copiedValues[value] ~= nil then return value end
    for key, text in pairs(copiedValues) do
      if tostring(key) == tostring(value) or tostring(text) == tostring(value) then return key end
    end
    return value
  end
  dropdown.GetValue = function() return selectedValue end
  dropdown.GetText = function() return tostring(copiedValues[selectedValue] or selectedValue or "") end
  dropdown.SetValue = function(_, value)
    selectedValue = canonicalValue(value)
    if setValue then pcall(setValue, dropdown, selectedValue) end
    if setText then pcall(setText, dropdown, copiedValues[selectedValue] or selectedValue or "") end
  end
  dropdown.SetList = function(_, nextValues)
    local replacement = {}
    for key, value in pairs(type(nextValues) == "table" and nextValues or {}) do
      replacement[key] = value
    end
    for key in pairs(copiedValues) do copiedValues[key] = nil end
    for key, value in pairs(replacement) do copiedValues[key] = value end
    if setList then pcall(setList, dropdown, copiedValues) end
    if selectedValue ~= nil and copiedValues[selectedValue] == nil then selectedValue = nil end
    if setText then pcall(setText, dropdown, copiedValues[selectedValue] or selectedValue or "") end
  end
  dropdown.SetDisabled = function(_, value)
    disabled = value == true
    if setDisabled then pcall(setDisabled, dropdown, disabled or readOnly) end
  end
  dropdown.SetReadOnly = function(_, value)
    readOnly = value == true
    if setDisabled then pcall(setDisabled, dropdown, disabled or readOnly) end
  end
  dropdown._dibsSelectLabel = tostring(label or "")
  dropdown._dibsSelectValues = copiedValues
  if options.value ~= nil then dropdown:SetValue(options.value) end
  if disabled or readOnly then dropdown:SetDisabled(true) end
  if options.tooltip or options.description then
    Adapter.AttachHelp(dropdown, options.tooltipTitle or label, options.tooltip or options.description)
  end
  return dropdown
end

function Adapter.AddPaginationFooter(shell, page, options)
  if not shell or not page or not page.footer then return nil end
  options = options or {}
  local metrics = Adapter.GetLayoutMetrics()
  local footer = page.footer
  local navigation = Adapter.Create(shell, "SimpleGroup", footer)
  local showPageSize = options.showPageSize ~= false
  local pageSizeGroup = showPageSize and Adapter.Create(shell, "SimpleGroup", footer) or nil
  if not navigation or (showPageSize and not pageSizeGroup) then return nil end
  call(navigation, "SetLayout", "Flow")
  call(navigation, "SetAutoAdjustHeight", false)
  if pageSizeGroup then
    call(pageSizeGroup, "SetLayout", "Flow")
    call(pageSizeGroup, "SetAutoAdjustHeight", false)
  end

  local previousWidth = Adapter.GetContentSizedActionWidth({ "Previous" }, 72)
  local nextWidth = Adapter.GetContentSizedActionWidth({ "Next" }, 64)
  local pageLabelWidth = 96
  local navigationGap = 6
  local pageSizeLabelWidth = Adapter.MeasureTextWidth("Rows per page:") + 4
  local pageSizeDropdownWidth = 76
  local pageSizeGap = 8
  local pageSizeHeight = math.max(metrics.buttonHeight, 26)
  local footerGap = math.max(12, metrics.tableColumnGap * 3)
  call(navigation, "SetHeight", metrics.buttonHeight)
  if pageSizeGroup then call(pageSizeGroup, "SetHeight", pageSizeHeight) end

  local controls = {}
  controls.previous = Adapter.AddButton(shell, navigation, "Previous", function()
    if options.onPrevious then options.onPrevious() end
  end, previousWidth)
  controls.page = Adapter.AddLabel(shell, navigation, "Page 1 / 1", false)
  call(controls.page, "SetWidth", pageLabelWidth)
  call(controls.page, "SetHeight", metrics.buttonHeight)
  controls.next = Adapter.AddButton(shell, navigation, "Next", function()
    if options.onNext then options.onNext() end
  end, nextWidth)
  if pageSizeGroup then
    controls.pageSizeLabel = Adapter.AddLabel(shell, pageSizeGroup, "Rows per page:", false)
    call(controls.pageSizeLabel, "SetWidth", pageSizeLabelWidth)
    call(controls.pageSizeLabel, "SetHeight", metrics.buttonHeight)
    controls.pageSize = Adapter.AddDropdown(shell, pageSizeGroup, "",
      options.pageSizes or { ["5"] = "5", ["10"] = "10", ["15"] = "15", ["20"] = "20" },
      options.onPageSizeChanged, pageSizeDropdownWidth, false)
  end
  if controls.pageSize then controls.pageSize._dibsRowsPerPageSelector = true end
  local dropdownHeight = controls.pageSize and controls.pageSize.frame
    and controls.pageSize.frame.GetHeight and tonumber(controls.pageSize.frame:GetHeight()) or nil
  if pageSizeGroup then
    pageSizeHeight = math.max(pageSizeHeight, dropdownHeight or 0)
    call(pageSizeGroup, "SetHeight", pageSizeHeight)
  else
    pageSizeHeight = 0
  end

  local function controlWidth(widget, fallback)
    local frame = widget and widget.frame
    local frameWidth = frame and type(frame.GetWidth) == "function" and tonumber(frame:GetWidth()) or 0
    return math.max(0, tonumber(widget and widget.width) or 0, tonumber(frame and frame.width) or 0,
      frameWidth or 0, tonumber(fallback) or 0)
  end
  local function anchorOneLine(group, widgets, gap)
    local totalWidth = 0
    local previous
    group.LayoutFunc = function() end
    for _, widget in ipairs(widgets) do
      local frame = widget and widget.frame
      if frame then
        if frame.ClearAllPoints then frame:ClearAllPoints() end
        if previous then
          frame:SetPoint("LEFT", previous.frame, "RIGHT", gap, 0)
          totalWidth = totalWidth + gap
        else
          frame:SetPoint("LEFT", group.frame, "LEFT", 0, 0)
        end
        totalWidth = totalWidth + controlWidth(widget)
        previous = widget
      end
    end
    call(group, "SetWidth", totalWidth)
    return totalWidth
  end
  local navigationWidth = anchorOneLine(navigation,
    { controls.previous, controls.page, controls.next }, navigationGap)
  local pageSizeWidth = pageSizeGroup and anchorOneLine(pageSizeGroup,
    { controls.pageSizeLabel, controls.pageSize }, pageSizeGap) or 0

  footer._dibsBaseLayoutFunc = footer.LayoutFunc
  footer._dibsTablePageLayout = function() end
  footer.LayoutFunc = footer._dibsTablePageLayout
  footer._dibsPaginationLayout = function(availableWidth)
    local inline = not pageSizeGroup
      or (tonumber(availableWidth) or 0) >= navigationWidth + pageSizeWidth + footerGap
    local footerHeight = pageSizeGroup and math.max(metrics.buttonHeight, pageSizeHeight) or metrics.buttonHeight
    if pageSizeGroup and not inline then
      footerHeight = metrics.buttonHeight + metrics.tableVerticalGap + pageSizeHeight
    end
    call(footer, "SetHeight", footerHeight)
    if navigation.frame and navigation.frame.ClearAllPoints then navigation.frame:ClearAllPoints() end
    if pageSizeGroup and pageSizeGroup.frame and pageSizeGroup.frame.ClearAllPoints then pageSizeGroup.frame:ClearAllPoints() end
    if inline then
      if navigation.frame and navigation.frame.SetPoint then navigation.frame:SetPoint("LEFT", footer.frame, "LEFT", 0, 0) end
      if pageSizeGroup and pageSizeGroup.frame and pageSizeGroup.frame.SetPoint then
        pageSizeGroup.frame:SetPoint("LEFT", navigation.frame, "RIGHT", footerGap, 0)
      end
    else
      if navigation.frame and navigation.frame.SetPoint then navigation.frame:SetPoint("TOPLEFT", footer.frame, "TOPLEFT", 0, 0) end
      if pageSizeGroup and pageSizeGroup.frame and pageSizeGroup.frame.SetPoint then
        pageSizeGroup.frame:SetPoint("TOPLEFT", navigation.frame, "BOTTOMLEFT", 0, -metrics.tableVerticalGap)
      end
    end
    controls.layoutMode = inline and "INLINE" or "STACKED"
    return inline and "INLINE" or "STACKED"
  end
  page.UpdateFooterLayout = footer._dibsPaginationLayout
  page.pagination = controls
  page.pagination.navigationGroup = navigation
  page.pagination.pageSizeGroup = pageSizeGroup
  page.pagination.navigationWidth = navigationWidth
  page.pagination.pageSizeWidth = pageSizeWidth
  page.pagination.pageSizeHeight = pageSizeHeight
  page.pagination.footerGap = footerGap
  page.pagination.UpdateState = function(currentPage, rowCount, pageSize)
    local totalPages = math.max(1, math.ceil((tonumber(rowCount) or 0) / math.max(1, tonumber(pageSize) or 10)))
    local selectedPage = math.min(totalPages, math.max(1, math.floor(tonumber(currentPage) or 1)))
    Adapter.SetText(controls.page, string.format("Page %d / %d", selectedPage, totalPages))
    Adapter.SetDisabled(controls.previous, selectedPage <= 1)
    Adapter.SetDisabled(controls.next, selectedPage >= totalPages)
    return selectedPage, totalPages
  end
  local initialSize = tostring(options.pageSize or 10)
  if controls.pageSize then Adapter.SetValue(controls.pageSize, initialSize) end
  page.UpdateFooterLayout(page.boundsFrame and page.boundsFrame.GetWidth
    and page.boundsFrame:GetWidth() or page.pagination.navigationWidth + page.pagination.pageSizeWidth + footerGap)
  return page.pagination
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

function Adapter.AddColorPicker(shell, parent, label, color, callback, width)
  local picker = Adapter.Create(shell, "ColorPicker", parent)
  if not picker then return nil end
  local values = type(color) == "table" and color or { 1, 1, 1, 1 }
  call(picker, "SetLabel", label or "")
  call(picker, "SetHasAlpha", true)
  call(picker, "SetColor", tonumber(values[1]) or 1, tonumber(values[2]) or 1,
    tonumber(values[3]) or 1, tonumber(values[4]) or 1)
  call(picker, "SetWidth", width or 200)
  local function updateColor(_, _, red, green, blue, alpha)
    if callback then callback(red, green, blue, alpha or 1) end
  end
  call(picker, "SetCallback", "OnValueChanged", updateColor)
  call(picker, "SetCallback", "OnValueConfirmed", updateColor)
  return picker
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
    -- Sliders notify on mouse release, so rebuilding here won't interrupt a drag.
    if context.onChanged and (kind == "select" or kind == "execute" or kind == "range") then
      context.onChanged(option, kind)
    end
  end

  local function controlWidth(option, fallback)
    local width = tonumber(option and option.widthPx)
    if width and width > 0 then return width end
    if option and option.width == "double" then return 360 end
    return fallback
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
        if option.dibsLayout == "FLOW_ROW" then
          groupTarget = Adapter.AddInlineGroup(shell, target)
          local rowTitle = Adapter.AddLabel(shell, groupTarget, label, false)
          if rowTitle then
            call(rowTitle, "SetWidth", tonumber(option.titleWidthPx) or 58)
            Adapter.AddTooltip(rowTitle, label, description)
          end
        elseif label ~= "" then
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
        end, controlWidth(option, nil))
        if control then
          Adapter.SetValue(control, getValue(option))
          Adapter.SetDisabled(control, isDisabled(option))
          Adapter.AddTooltip(control, label, description)
          register(key, control)
        end
      elseif kind == "range" then
        local control = Adapter.AddRange(shell, target, label, option.min, option.max, option.step, getValue(option), function(value)
          setValue(option, nil, value)
          changed(option, kind)
        end, controlWidth(option, nil))
        if control then
          Adapter.SetDisabled(control, isDisabled(option))
          Adapter.AddTooltip(control, label, description)
          register(key, control)
        end
      elseif kind == "color" then
        local ok, red, green, blue, alpha = false, 1, 1, 1, 1
        if type(option.get) == "function" then ok, red, green, blue, alpha = pcall(option.get, nil) end
        if not ok then red, green, blue, alpha = 1, 1, 1, 1 end
        local control = Adapter.AddColorPicker(shell, target, label, { red, green, blue, alpha }, function(r, g, b, a)
          if type(option.set) == "function" then pcall(option.set, nil, r, g, b, a) end
        end, controlWidth(option, 180))
        if control then
          Adapter.SetDisabled(control, isDisabled(option))
          Adapter.AddTooltip(control, label, description)
          register(key, control)
        end
      elseif kind == "toggle" then
        local control = Adapter.AddCheckBox(shell, target, label, getValue(option), function(value)
          setValue(option, nil, value)
        end, controlWidth(option, nil))
        if control then
          Adapter.SetDisabled(control, isDisabled(option))
          Adapter.AddTooltip(control, label, description)
          register(key, control)
        end
      elseif kind == "input" then
        local control = Adapter.AddEditBox(shell, target, label, function(value)
          setValue(option, nil, value)
        end, controlWidth(option, nil))
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
        end, controlWidth(option, option.width == "half" and 180 or 220))
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

function Adapter.AddScrollableList(shell, parent, height, resizeOffset)
  local scroll = parent and parent.type == "ScrollFrame" and parent or nil
  if scroll and not tonumber(resizeOffset) then return scroll end
  if not scroll then
    scroll = Adapter.Create(shell, "ScrollFrame", parent)
    if not scroll then
      scroll = Adapter.Create(shell, "SimpleGroup", parent)
    end
  end
  if not scroll then return nil end
  local metrics = Adapter.GetLayoutMetrics()
  local requestedHeight = tonumber(height) or metrics.defaultScrollHeight or 260
  local frameHeight = shell and shell.frame and shell.frame.GetHeight and shell.frame:GetHeight() or nil
  local fixedOffset = tonumber(resizeOffset)
  if fixedOffset and frameHeight and frameHeight > 0 then
    requestedHeight = math.max(120, math.min(requestedHeight, frameHeight - fixedOffset))
  elseif frameHeight and frameHeight > 0 then
    requestedHeight = math.min(requestedHeight, math.max(240, frameHeight - 180))
  end
  call(scroll, "SetHeight", requestedHeight)
  call(scroll, "SetFullWidth", true)
  call(scroll, "SetLayout", "List")
  -- Long pages should follow a resizable Dibs window. Keep compact embedded
  -- lists (for example multiselect checkboxes) at their requested height.
  if shell and fixedOffset then
    scroll._dibsShell = shell
    scroll._dibsResizeOffset = fixedOffset
    shell._dibsResponsiveScrolls = shell._dibsResponsiveScrolls or {}
    shell._dibsResponsiveScrolls[#shell._dibsResponsiveScrolls + 1] = scroll
  elseif shell and requestedHeight >= 380 and frameHeight and frameHeight > requestedHeight then
    scroll._dibsShell = shell
    scroll._dibsResizeOffset = frameHeight - requestedHeight
    shell._dibsResponsiveScrolls = shell._dibsResponsiveScrolls or {}
    shell._dibsResponsiveScrolls[#shell._dibsResponsiveScrolls + 1] = scroll
  end
  return scroll
end

function Adapter.AddTablePage(shell, parent, options)
  if not shell or not parent then return nil end
  options = options or {}
  local metrics = Adapter.GetLayoutMetrics()
  local boundsFrame = options.boundsFrame or parent.content or parent.frame
  if not boundsFrame then return nil end
  local pageRoot = Adapter.Create(shell, "SimpleGroup", parent)
  if not pageRoot then return nil end
  call(pageRoot, "SetFullWidth", true)
  call(pageRoot, "SetFullHeight", true)
  call(pageRoot, "SetAutoAdjustHeight", false)
  pageRoot._dibsBaseLayoutFunc = pageRoot.LayoutFunc
  pageRoot._dibsTablePageLayout = function() end
  pageRoot.LayoutFunc = pageRoot._dibsTablePageLayout
  local pageContent = pageRoot.content or pageRoot.frame

  local header = Adapter.Create(shell, "SimpleGroup", pageRoot)
  local columnHeader = Adapter.Create(shell, "SimpleGroup", pageRoot)
  local scroll = Adapter.AddScrollableList(shell, pageRoot, options.initialScrollHeight or metrics.defaultScrollHeight)
  local footer = options.footer and Adapter.Create(shell, "SimpleGroup", pageRoot) or nil
  if not header or not columnHeader or not scroll or (options.footer and not footer) then return nil end
  call(header, "SetFullWidth", true)
  call(header, "SetLayout", "List")
  call(columnHeader, "SetFullWidth", true)
  call(columnHeader, "SetLayout", "Flow")
  if footer then
    call(footer, "SetFullWidth", true)
    call(footer, "SetLayout", "Flow")
  end

  local function setAnchors(frame, firstPoint, firstRelative, firstRelativePoint, firstX, firstY,
      secondPoint, secondRelative, secondRelativePoint, secondX, secondY)
    if not frame or type(frame.ClearAllPoints) ~= "function" or type(frame.SetPoint) ~= "function" then return end
    frame:ClearAllPoints()
    frame:SetPoint(firstPoint, firstRelative, firstRelativePoint, firstX or 0, firstY or 0)
    if secondPoint then
      frame:SetPoint(secondPoint, secondRelative, secondRelativePoint, secondX or 0, secondY or 0)
    end
  end

  local function measure(widget)
    local frame = widget and widget.frame
    if frame and type(frame.GetHeight) == "function" then
      local height = tonumber(frame:GetHeight())
      if height and height > 0 then return height end
    end
    if widget and type(widget.GetHeight) == "function" then
      local height = tonumber(widget:GetHeight())
      if height and height > 0 then return height end
    end
    return 0
  end
  local function measureWidth(widget)
    local frame = widget and widget.frame
    if frame and type(frame.GetWidth) == "function" then
      local width = tonumber(frame:GetWidth())
      if width and width > 0 then return width end
    end
    if widget and type(widget.GetWidth) == "function" then
      local width = tonumber(widget:GetWidth())
      if width and width > 0 then return width end
    end
    return 0
  end
  local adjustingWindowHeight = false
  local function updateViewportHeight()
    local availableHeight = measure(boundsFrame)
    local availableWidth = measureWidth(boundsFrame)
    local hasMeasuredBounds = availableHeight > 0
    if availableHeight <= 0 then availableHeight = metrics.defaultScrollHeight or 260 end
    if availableWidth <= 0 then availableWidth = metrics.defaultTableWidth or 640 end
    setAnchors(pageRoot.frame, "TOPLEFT", boundsFrame, "TOPLEFT", 0, 0,
      "TOPRIGHT", boundsFrame, "TOPRIGHT", 0, 0)
    if header.SetWidth then pcall(header.SetWidth, header, availableWidth) end
    if columnHeader.SetWidth then pcall(columnHeader.SetWidth, columnHeader, availableWidth) end
    if footer and footer.SetWidth then pcall(footer.SetWidth, footer, availableWidth) end
    if header.DoLayout then pcall(header.DoLayout, header) end
    if columnHeader.DoLayout then pcall(columnHeader.DoLayout, columnHeader) end
    if footer and footer._dibsPaginationLayout then
      pcall(footer._dibsPaginationLayout, availableWidth)
    end
    if footer and footer.DoLayout then pcall(footer.DoLayout, footer) end
    local footerHeight = measure(footer)
    if footer and footerHeight <= 0 then footerHeight = metrics.tableFooterHeight end
    local headerHeight = measure(header)
    local columnHeaderHeight = measure(columnHeader)
    local gap = metrics.tableVerticalGap
    local fixedHeight = headerHeight + columnHeaderHeight + footerHeight + gap
    local availableViewportHeight = availableHeight - fixedHeight
    if hasMeasuredBounds and availableViewportHeight < metrics.tableViewportMinimum and not adjustingWindowHeight then
      local windowFrame = shell.frame
      local currentWindowHeight = windowFrame and windowFrame.GetHeight and tonumber(windowFrame:GetHeight()) or nil
      if currentWindowHeight and currentWindowHeight > 0 and shell.window and shell.window.SetHeight then
        local targetHeight = currentWindowHeight + metrics.tableViewportMinimum - availableViewportHeight
        local maximumHeight = shell.layout and tonumber(shell.layout.maxHeight) or nil
        if maximumHeight then targetHeight = math.min(targetHeight, maximumHeight) end
        if targetHeight > currentWindowHeight then
          adjustingWindowHeight = true
          call(shell.window, "SetHeight", targetHeight)
          adjustingWindowHeight = false
          local resizedHeight = measure(boundsFrame)
          if resizedHeight > availableHeight then availableHeight = resizedHeight end
          availableViewportHeight = availableHeight - fixedHeight
        end
      end
    end
    if pageRoot.SetHeight then pcall(pageRoot.SetHeight, pageRoot, availableHeight) end
    local viewportHeight = math.max(metrics.tableViewportMinimum,
      availableViewportHeight)

    setAnchors(header.frame, "TOPLEFT", pageContent, "TOPLEFT", 0, 0,
      "TOPRIGHT", pageContent, "TOPRIGHT", 0, 0)
    setAnchors(columnHeader.frame, "TOPLEFT", header.frame, "BOTTOMLEFT", 0, -gap,
      "TOPRIGHT", header.frame, "BOTTOMRIGHT", 0, -gap)
    if footer then
      setAnchors(footer.frame, "BOTTOMLEFT", boundsFrame, "BOTTOMLEFT", 0, 0,
        "BOTTOMRIGHT", boundsFrame, "BOTTOMRIGHT", 0, 0)
    end
    if footer then
      setAnchors(scroll.frame, "TOPLEFT", columnHeader.frame, "BOTTOMLEFT", 0, 0,
        "BOTTOMRIGHT", footer.frame, "TOPRIGHT", 0, 0)
    else
      setAnchors(scroll.frame, "TOPLEFT", columnHeader.frame, "BOTTOMLEFT", 0, 0,
        "TOPRIGHT", columnHeader.frame, "BOTTOMRIGHT", 0, 0)
    end
    if scroll.frame and scroll.frame.SetHeight then pcall(scroll.frame.SetHeight, scroll.frame, viewportHeight) end
    if scroll.SetHeight then pcall(scroll.SetHeight, scroll, viewportHeight) end
    if scroll.DoLayout then pcall(scroll.DoLayout, scroll) end
    local function updateFluidWidths(widget, width, seen)
      if type(widget) ~= "table" or seen[widget] then return end
      seen[widget] = true
      if type(widget._dibsApplyFluidWidth) == "function" then
        pcall(widget._dibsApplyFluidWidth, width)
      end
      for _, child in ipairs(widget.children or {}) do updateFluidWidths(child, width, seen) end
    end
    if availableWidth > 0 then updateFluidWidths(pageRoot, availableWidth, {}) end
    return viewportHeight
  end

  scroll._dibsViewportUpdater = updateViewportHeight
  scroll._dibsShell = shell
  shell._dibsResponsiveScrolls = shell._dibsResponsiveScrolls or {}
  for index = #shell._dibsResponsiveScrolls, 1, -1 do
    if shell._dibsResponsiveScrolls[index] == scroll then
      table.remove(shell._dibsResponsiveScrolls, index)
    end
  end
  scroll._dibsResizeOffset = nil
  shell._dibsResponsiveScrolls[#shell._dibsResponsiveScrolls + 1] = scroll
  updateViewportHeight()
  return {
    root = pageRoot, header = header, columnHeader = columnHeader,
    scroll = scroll, footer = footer, boundsFrame = boundsFrame, contentFrame = pageContent,
    UpdateViewportHeight = updateViewportHeight,
  }
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
