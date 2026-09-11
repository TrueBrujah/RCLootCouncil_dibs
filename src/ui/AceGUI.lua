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

local function applyRCLootCouncilTheme(frame)
  if not frame then return end
  if type(frame.SetBackdropColor) == "function" then
    frame:SetBackdropColor(0.035, 0.055, 0.065, 0.96)
  end
  if type(frame.SetBackdropBorderColor) == "function" then
    frame:SetBackdropBorderColor(0.62, 0.52, 0.22, 1)
  end
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

function Adapter.CreateWindow(title, width, height, point)
  if Adapter.windowShellEnabled ~= true then return nil end
  local gui = getLibrary()
  if not gui or type(gui.Create) ~= "function" then return nil end

  local ok, window = pcall(gui.Create, gui, "Frame")
  if not ok or type(window) ~= "table" or not window.frame then return nil end

  call(window, "SetTitle", title)
  call(window, "SetWidth", width)
  call(window, "SetHeight", height)
  -- AceGUI Frame widgets expose the native frame; keep resizing optional for
  -- older clients while enabling it on current Retail clients.
  if window.frame and type(window.frame.SetResizable) == "function" then
    window.frame:SetResizable(true)
    if type(window.frame.SetResizeBounds) == "function" then
      window.frame:SetResizeBounds(420, 320, 1400, 1100)
    elseif type(window.frame.SetMinResize) == "function" then
      window.frame:SetMinResize(420, 320)
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
  applyRCLootCouncilTheme(window.frame)
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
  -- Children are owned by their AceGUI container.  Do not mirror every page
  -- widget in the shell: Refresh() releases and recreates those widgets, and
  -- a tracking array would retain the historical numeric slots forever.
  local shell = { gui = gui, window = window, frame = window.frame }
  call(window, "SetCallback", "OnClose", function(widget)
    if shell and shell.frame == widget.frame then
      shell.frame = nil
    end
    if _G.DibsPlayerFrame == widget.frame then _G.DibsPlayerFrame = nil end
    if _G.DibsOfficerFrame == widget.frame then _G.DibsOfficerFrame = nil end
    gui:Release(widget)
  end)

  return shell
end

function Adapter.Create(shell, kind, parent)
  if not shell or not shell.gui then return nil end
  local ok, widget = pcall(shell.gui.Create, shell.gui, kind)
  if not ok or not widget then return nil end
  if parent and type(parent.AddChild) == "function" then
    parent:AddChild(widget)
  elseif shell.window and type(shell.window.AddChild) == "function" then
    shell.window:AddChild(widget)
  end
  return widget
end

local function releaseMSAControls(widget, seen)
  if type(widget) ~= "table" then return end
  seen = seen or {}
  if seen[widget] then return end
  seen[widget] = true
  local control = widget._dibsMSAControl
  if control then
    if control.Hide then pcall(control.Hide, control) end
    if control.SetParent then pcall(control.SetParent, control, nil) end
    msaDropdownPool[#msaDropdownPool + 1] = control
    widget._dibsMSAControl = nil
  end
  if widget._dibsScrollingTable then
    if type(widget._dibsScrollingTable.Hide) == "function" then
      pcall(widget._dibsScrollingTable.Hide, widget._dibsScrollingTable)
    end
    widget._dibsScrollingTable = nil
  end
  for _, child in ipairs(widget.children or {}) do
    releaseMSAControls(child, seen)
  end
end

function Adapter.Clear(container)
  releaseMSAControls(container)
  if container and type(container.ReleaseChildren) == "function" then
    container:ReleaseChildren()
  elseif container and type(container.children) == "table" then
    container.children = {}
  end
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
  call(section, "SetLayout", "Flow")
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

local function safeContextText(value)
  return tostring(value or "")
end

local function showTableContextMenu(st, rowRecord, columns, options)
  if not HAS_MSA_DROPDOWN or type(_G.MSA_ToggleDropDownMenu) ~= "function"
    or type(_G.MSA_DropDownMenu_Initialize) ~= "function" then
    return false
  end
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
    if #menuRows > 0 then
      menuRows[#menuRows + 1] = { isTitle = true, text = "Sort table" }
    end
  end
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
    desiredWidth = desiredWidth + width
    tableColumns[index] = {
      name = safeContextText(column.title or column.name or ("Column " .. tostring(index))),
      baseName = safeContextText(column.title or column.name or ("Column " .. tostring(index))),
      width = width,
      align = column.align or "LEFT",
      tooltip = column.tooltip,
      defaultsort = column.defaultsort,
      action = column.action == true or (index == #definitions and rowActions ~= nil),
    }
  end

  local availableWidth = tonumber(options.widthHint) or (host.frame.GetWidth and host.frame:GetWidth() or 0)
  if availableWidth <= 0 and shell.frame and shell.frame.GetWidth then
    availableWidth = math.max(360, (shell.frame:GetWidth() or desiredWidth) - 220)
  end
  if availableWidth > 0 then availableWidth = availableWidth - 12 end
  if availableWidth > 0 and desiredWidth > availableWidth then
    local scale = availableWidth / desiredWidth
    local used = 0
    for index, column in ipairs(tableColumns) do
      column.width = math.floor(column.width * scale)
      if index == #tableColumns then column.width = math.max(48, availableWidth - used) end
      used = used + column.width
    end
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
  if st.frame then
    st.frame:ClearAllPoints()
    -- Keep the lib-st header inside the AceGUI host instead of letting it
    -- float into the heading/control row above the table.
    st.frame:SetPoint("TOPLEFT", host.frame, "TOPLEFT", 0, -rowHeight)
    st.frame:SetWidth(desiredWidth)
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

  st:RegisterEvents({
    OnEnter = function(rowFrame, cellFrame, data, cols, row, realrow, column, table)
      local cell = realrow and table:GetCell(realrow, column)
      local value = type(cell) == "table" and cell.value or cell
      if type(value) == "string" and value:find("|Hitem:", 1, true) and _G.GameTooltip
        and type(_G.GameTooltip.SetOwner) == "function" and type(_G.GameTooltip.SetHyperlink) == "function" then
        _G.GameTooltip:SetOwner(cellFrame, "ANCHOR_RIGHT")
        _G.GameTooltip:SetHyperlink(value)
        _G.GameTooltip:Show()
      end
      return false
    end,
    OnLeave = function()
      if _G.GameTooltip and type(_G.GameTooltip.Hide) == "function" then _G.GameTooltip:Hide() end
      return false
    end,
    OnClick = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, button)
      local record = realrow and table:GetRow(realrow)
      if button == "RightButton" then
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
  local scrolling = Adapter.AddScrollingTable(shell, parent, columns, rows, height, rowActions, options)
  if scrolling then return scrolling end
  local scroll = Adapter.AddScrollableList(shell, parent, height)
  if not scroll then return nil end
  local definitions = columns or {}
  local desiredWidth = 0
  for _, column in ipairs(definitions) do desiredWidth = desiredWidth + (tonumber(column.width) or 100) end
  local frameWidth = tonumber(options.widthHint) or (scroll.frame and scroll.frame.GetWidth and scroll.frame:GetWidth() or 0)
  if frameWidth <= 0 and parent and parent.frame and parent.frame.GetWidth then frameWidth = parent.frame:GetWidth() or 0 end
  if frameWidth <= 0 and shell and shell.frame and shell.frame.GetWidth then frameWidth = (shell.frame:GetWidth() or 760) - 220 end
  frameWidth = math.max(360, frameWidth > 0 and frameWidth - 8 or math.min(desiredWidth, 760))
  local scale = desiredWidth > frameWidth and (frameWidth / desiredWidth) or 1
  local widths = {}
  local actualWidth = 0
  for index, column in ipairs(definitions) do
    local width = math.floor((tonumber(column.width) or 100) * scale)
    if index == #definitions then width = math.max(48, frameWidth - actualWidth) end
    widths[index] = width
    actualWidth = actualWidth + width
  end

  local function cellText(value, width)
    local result = tostring(value or "")
    -- Let WoW render a complete hyperlink. Truncating the colour and Hitem
    -- escape sequence makes the visible cell look like raw `[Hitem:...]` text.
    if result:find("|Hitem:", 1, true) then return result end
    local characters = math.max(8, math.floor((width or 100) / 7))
    if #result > characters then result = result:sub(1, math.max(1, characters - 3)) .. "..." end
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
  host._dibsMSAControl = control
  host._dibsMSAWrapper = wrapper

  local function valueLabel(value)
    local labelValue = wrapper.values[value]
    if labelValue == nil then labelValue = wrapper.values[tostring(value)] end
    return tostring(labelValue or value or "")
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
    self.value = value
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
    if self.value ~= nil then self:SetValue(self.value) end
  end

  function wrapper:SetDisabled(disabled)
    self.disabled = disabled == true
    local button = control.Button
    if button then
      if self.disabled and button.Disable then button:Disable()
      elseif not self.disabled and button.Enable then button:Enable() end
    end
  end

  local keys = {}
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
        wrapper:SetValue(key)
        if callback then callback(key) end
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
    if callback then callback(value) end
  end)
  return dropdown
end

function Adapter.AddCheckBox(shell, parent, label, value, callback, width)
  local checkbox = Adapter.Create(shell, "CheckBox", parent)
  if not checkbox then return nil end
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
  local ok, group = pcall(shell.gui.Create, shell.gui, "TabGroup")
  if not ok or not group then return nil end
  call(group, "SetFullWidth", true)
  call(group, "SetFullHeight", true)
  call(group, "SetLayout", "Flow")
  call(group, "SetTabs", tabs)
  call(group, "SetCallback", "OnGroupSelected", function(_, _, value)
    if onSelect then onSelect(value) end
  end)
  call(shell.window, "AddChild", group)
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
  local ok, group = pcall(shell.gui.Create, shell.gui, "TreeGroup")
  if not ok or not group then return nil end
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
  call(shell.window, "AddChild", group)
  return group
end

function Adapter.SelectTree(tree, value)
  if tree and type(tree.Select) == "function" then
    return pcall(tree.Select, tree, value)
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
    local ok = pcall(option.set, nil, key, value)
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
        if label ~= "" then Adapter.AddHeader(shell, target, label, description) end
        render(option.args, target)
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
  if groupTitle and tostring(groupTitle) ~= "" then
    Adapter.AddHeading(shell, parent, tostring(groupTitle))
  end

  -- Long pages such as Rank Rules and Settings need their own scroll frame;
  -- TreeGroup only scrolls the navigation column.  Fall back to the content
  -- panel when an older AceGUI build does not provide ScrollFrame.
  local target = parent
  if context.scroll ~= false then
    target = Adapter.AddScrollableList(shell, parent, context.pageHeight or 680) or parent
  end
  render(group.args, target)
  if context.onRendered then context.onRendered(target) end
  return true
end

function Adapter.AddScrollableList(shell, parent, height)
  local scroll = Adapter.Create(shell, "ScrollFrame", parent)
  if not scroll then
    scroll = Adapter.Create(shell, "SimpleGroup", parent)
  end
  if not scroll then return nil end
  call(scroll, "SetHeight", height or 260)
  call(scroll, "SetFullWidth", true)
  call(scroll, "SetLayout", "List")
  return scroll
end

function Adapter.AddSearch(shell, onChanged)
  if not shell or not shell.gui then return nil end
  local ok, search = pcall(shell.gui.Create, shell.gui, "EditBox")
  if not ok or not search then return nil end
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
    local ok, button = pcall(shell.gui.Create, shell.gui, "Button")
    if ok and button then
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
