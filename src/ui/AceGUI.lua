local Dibs = _G.Dibs
Dibs.AceGUI = Dibs.AceGUI or {}

local Adapter = Dibs.AceGUI
local unpackValues = table.unpack or unpack

Adapter.windowShellEnabled = true

local function getLibrary()
  if Dibs.Ace3 and Dibs.Ace3.libs and Dibs.Ace3.libs.gui then
    return Dibs.Ace3.libs.gui
  end
  if _G.LibStub == nil then return nil end
  local ok, library = pcall(_G.LibStub, "AceGUI-3.0", true)
  return ok and library or nil
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
  if point and window.frame.SetPoint then
    if window.frame.ClearAllPoints then window.frame:ClearAllPoints() end
    window.frame:SetPoint(unpackValues(point))
  end
  local shell = { gui = gui, window = window, frame = window.frame, widgets = {} }
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
  table.insert(shell.widgets, widget)
  return widget
end

function Adapter.Clear(container)
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

function Adapter.AddLabel(shell, parent, text, fullWidth)
  local label = Adapter.Create(shell, "Label", parent)
  if not label then return nil end
  if fullWidth then call(label, "SetFullWidth", true) end
  Adapter.SetText(label, text)
  return label
end

local function addTableCell(shell, parent, text, width, tooltip)
  local cell = Adapter.AddLabel(shell, parent, text, false)
  if cell and width then call(cell, "SetWidth", width) end
  if tooltip then Adapter.AddTooltip(cell, text, tooltip) end
  return cell
end

function Adapter.AddTable(shell, parent, columns, rows, height, rowActions)
  local scroll = Adapter.AddScrollableList(shell, parent, height)
  if not scroll then return nil end
  local function formatRow(values)
    local cells = {}
    local totalWidth = 0
    for _, column in ipairs(columns or {}) do totalWidth = totalWidth + (tonumber(column.width) or 100) end
    local frameWidth = scroll.frame and scroll.frame.GetWidth and scroll.frame:GetWidth() or 0
    local totalCharacters = math.max(48, math.floor((frameWidth > 0 and frameWidth or 640) / 7))
    for index, column in ipairs(columns or {}) do
      local value = tostring(values[index] or "")
      local characters = math.max(8, math.floor(((tonumber(column.width) or 100) / math.max(1, totalWidth)) * totalCharacters))
      if #value > characters then
        value = value:sub(1, math.max(1, characters - 3)) .. "..."
      end
      table.insert(cells, string.format("%-" .. tostring(characters) .. "s", value))
    end
    return table.concat(cells, " | ")
  end

  local headers = {}
  for _, column in ipairs(columns or {}) do table.insert(headers, column.title or "") end
  Adapter.AddHeader(shell, scroll, formatRow(headers), "Hover the column names for details.")
  for _, row in ipairs(rows or {}) do
    Adapter.AddLabel(shell, scroll, formatRow(row), true)
    if rowActions then
      local action = rowActions(row)
      if action then Adapter.AddButton(shell, scroll, action.text or "Action", action.callback, 90) end
    end
  end
  return scroll
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
  if width then call(edit, "SetWidth", width) end
  call(edit, "SetCallback", "OnTextChanged", function(_, _, value)
    if callback then callback(value or "") end
  end)
  return edit
end

function Adapter.AddDropdown(shell, parent, label, values, callback, width)
  local dropdown = Adapter.Create(shell, "Dropdown", parent)
  if not dropdown then return nil end
  call(dropdown, "SetLabel", label or "")
  call(dropdown, "SetList", values or {})
  if width then call(dropdown, "SetWidth", width) end
  call(dropdown, "SetCallback", "OnValueChanged", function(_, _, value)
    if callback then callback(value) end
  end)
  return dropdown
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
  table.insert(shell.widgets, group)
  return group
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
  table.insert(shell.widgets, search)
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
      table.insert(shell.widgets, button)
      table.insert(controls, button)
    end
  end
  return controls
end
