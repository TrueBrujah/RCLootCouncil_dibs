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
  call(edit, "SetWidth", width or 420)
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
