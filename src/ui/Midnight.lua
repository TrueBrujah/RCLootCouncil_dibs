--[[
Module: Dibs.Midnight
Layer: UI presentation
Purpose: Own the single Midnight design system and local presentation profile.
Non-responsibilities: Guild policy, authority, ledger, sync, and RC state.
]]

local Dibs = _G.Dibs
Dibs.Midnight = Dibs.Midnight or {}

local Midnight = Dibs.Midnight
local LOCAL_ROOT = "RCLootCouncil_dibsLocalDB"
local LOCAL_SCHEMA = 1
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local FALLBACK_STATUSBAR = "Interface\\TargetingFrame\\UI-StatusBar"

local defaults = {
  theme = "MIDNIGHT",
  colors = {
    PRIMARY = { 0.20, 0.55, 0.82, 1 },
    TEXT = { 0.94, 0.96, 0.98, 1 },
    TEXT_MUTED = { 0.64, 0.70, 0.76, 1 },
    SUCCESS = { 0.28, 0.78, 0.48, 1 },
    WARNING = { 0.95, 0.67, 0.20, 1 },
    DANGER = { 0.88, 0.28, 0.30, 1 },
    INFO = { 0.34, 0.68, 0.92, 1 },
    SURFACE = { 0.035, 0.055, 0.075, 0.97 },
    SURFACE_RAISED = { 0.075, 0.10, 0.13, 0.98 },
    BORDER = { 0.22, 0.30, 0.38, 1 },
  },
  typography = { font = FALLBACK_FONT, body = 13, heading = 16, title = 20, lineHeight = 1.15 },
  spacing = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24, row = 24 },
  sizing = {
    minWidth = 520, minHeight = 360, maxWidth = 1400, maxHeight = 1100,
    buttonHeight = 24, modalWidth = 560, modalHeight = 320,
    defaultScrollHeight = 420, actionMinWidth = 88,
  },
  surfaces = { statusbar = FALLBACK_STATUSBAR, borderThickness = 1, backgroundAlpha = 0.97 },
  density = "comfortable",
  scale = 1,
  contrast = "normal",
}

local THEME_CATALOG = {
  {
    id = "MIDNIGHT",
    name = "Midnight",
    description = "Bleu nuit, acier et or discret.",
    colors = defaults.colors,
  },
  {
    id = "AZEROTH_GOLD",
    name = "Azeroth Gold",
    description = "Noir profond, or chaud et bronze.",
    colors = {
      PRIMARY = { 0.82, 0.58, 0.16, 1 }, TEXT = { 0.98, 0.95, 0.86, 1 },
      TEXT_MUTED = { 0.72, 0.66, 0.54, 1 }, SUCCESS = { 0.32, 0.78, 0.42, 1 },
      WARNING = { 0.96, 0.72, 0.18, 1 }, DANGER = { 0.88, 0.30, 0.24, 1 },
      INFO = { 0.38, 0.68, 0.84, 1 }, SURFACE = { 0.075, 0.055, 0.035, 0.97 },
      SURFACE_RAISED = { 0.14, 0.105, 0.065, 0.98 }, BORDER = { 0.55, 0.36, 0.12, 1 },
    },
  },
  {
    id = "FEL_GREEN",
    name = "Fel Green",
    description = "Obsidienne, jade et energie gangrenee.",
    colors = {
      PRIMARY = { 0.22, 0.82, 0.52, 1 }, TEXT = { 0.90, 0.98, 0.92, 1 },
      TEXT_MUTED = { 0.58, 0.74, 0.64, 1 }, SUCCESS = { 0.34, 0.92, 0.48, 1 },
      WARNING = { 0.94, 0.70, 0.20, 1 }, DANGER = { 0.94, 0.28, 0.26, 1 },
      INFO = { 0.30, 0.78, 0.76, 1 }, SURFACE = { 0.025, 0.075, 0.055, 0.97 },
      SURFACE_RAISED = { 0.055, 0.14, 0.095, 0.98 }, BORDER = { 0.16, 0.48, 0.30, 1 },
    },
  },
  {
    id = "ARCANE_VIOLET",
    name = "Arcane Violet",
    description = "Prune profond, violet arcanique et argent.",
    colors = {
      PRIMARY = { 0.70, 0.40, 0.94, 1 }, TEXT = { 0.96, 0.92, 1, 1 },
      TEXT_MUTED = { 0.70, 0.64, 0.80, 1 }, SUCCESS = { 0.34, 0.82, 0.56, 1 },
      WARNING = { 0.96, 0.68, 0.24, 1 }, DANGER = { 0.94, 0.32, 0.46, 1 },
      INFO = { 0.46, 0.70, 0.96, 1 }, SURFACE = { 0.055, 0.035, 0.085, 0.97 },
      SURFACE_RAISED = { 0.12, 0.07, 0.17, 0.98 }, BORDER = { 0.42, 0.24, 0.62, 1 },
    },
  },
  {
    id = "FROST_STEEL",
    name = "Frost Steel",
    description = "Givre, acier clair et cyan froid.",
    colors = {
      PRIMARY = { 0.30, 0.74, 0.92, 1 }, TEXT = { 0.92, 0.98, 1, 1 },
      TEXT_MUTED = { 0.62, 0.76, 0.84, 1 }, SUCCESS = { 0.28, 0.86, 0.68, 1 },
      WARNING = { 0.94, 0.74, 0.28, 1 }, DANGER = { 0.88, 0.34, 0.38, 1 },
      INFO = { 0.38, 0.82, 0.96, 1 }, SURFACE = { 0.035, 0.075, 0.10, 0.97 },
      SURFACE_RAISED = { 0.08, 0.15, 0.19, 0.98 }, BORDER = { 0.30, 0.58, 0.70, 1 },
    },
  },
}

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
  return result
end

local function merge(target, source)
  if type(source) ~= "table" then return target end
  for key, value in pairs(source) do
    if type(value) == "table" and type(target[key]) == "table" then merge(target[key], value)
    elseif target[key] ~= nil then target[key] = value end
  end
  return target
end

local function localRoot()
  local root = _G[LOCAL_ROOT]
  if type(root) ~= "table" then root = {}; _G[LOCAL_ROOT] = root end
  root.schemaVersion = LOCAL_SCHEMA
  root.presentation = root.presentation or {}
  root.presentation.profile = root.presentation.profile or {}
  root.presentation.windows = root.presentation.windows or {}
  return root
end

local function safeMedia(kind, name, fallback)
  if type(_G.LibStub) ~= "function" and type(_G.LibStub) ~= "table" then return fallback end
  local ok, media = pcall(_G.LibStub, "LibSharedMedia-3.0", true)
  if not ok or type(media) ~= "table" or type(media.Fetch) ~= "function" then return fallback end
  local fetchedOK, value = pcall(media.Fetch, media, kind, name, true)
  return fetchedOK and type(value) == "string" and value ~= "" and value or fallback
end

local STATUS_PRESENTATIONS = {
  ready = { label = "Ready", marker = "[OK]", explanation = "Ready for the next action.", tone = "ready" },
  success = { label = "Complete", marker = "[OK]", explanation = "The requested operation completed.", tone = "success" },
  warning = { label = "Warning", marker = "[!]", explanation = "Review this state before continuing.", tone = "warning" },
  danger = { label = "Action required", marker = "[X]", explanation = "An action is required before continuing.", tone = "danger" },
  info = { label = "Information", marker = "[i]", explanation = "Additional information is available.", tone = "info" },
  normal = { label = "Status", marker = "[ ]", explanation = "Current state is available for review.", tone = "normal" },
}

local STATE_PRESENTATIONS = {
  SYNC_BEHIND = { status = "warning", label = "Syncing guild data", explanation = "Guild data is catching up. Try again shortly." },
  RECOVERY_PENDING = { status = "warning", label = "Recovery in progress", explanation = "Guild Dibs is restoring shared state. Try again later." },
  COORDINATOR_UNAVAILABLE = { status = "warning", label = "Coordinator unavailable", explanation = "The coordinator is unavailable. Read-only views remain available where possible." },
  RC_MASTER_LOOTER_UNVERIFIABLE = { status = "warning", label = "RCLootCouncil evidence needs review", explanation = "The current award owner cannot be verified safely." },
  RCLOOTCOUNCIL_UNAVAILABLE = { status = "warning", label = "RCLootCouncil unavailable", explanation = "RCLootCouncil is unavailable. Dibs remains available where supported." },
}

function Midnight.GetDefaults()
  return copy(defaults)
end

function Midnight.GetThemeNames()
  local names = {}
  for _, theme in ipairs(THEME_CATALOG) do names[#names + 1] = theme.id end
  return names
end

function Midnight.GetThemePalette(themeID)
  for _, theme in ipairs(THEME_CATALOG) do
    if theme.id == themeID then return copy(theme.colors) end
  end
  return nil
end

function Midnight.GetThemeTokens(themeID)
  for _, theme in ipairs(THEME_CATALOG) do
    if theme.id == themeID then
      local tokens = copy(defaults)
      tokens.theme = theme.id
      tokens.colors = copy(theme.colors)
      return tokens
    end
  end
  return nil
end

function Midnight.GetThemeCatalog()
  local catalog = {}
  for _, theme in ipairs(THEME_CATALOG) do
    catalog[#catalog + 1] = {
      id = theme.id, name = theme.name, description = theme.description,
      colors = copy(theme.colors),
    }
  end
  return catalog
end

function Midnight.GetTokens()
  local tokens = copy(defaults)
  local profile = localRoot().presentation.profile
  merge(tokens, profile)
  tokens.theme = "MIDNIGHT"
  tokens.scale = math.max(0.75, math.min(1.5, tonumber(tokens.scale) or 1))
  tokens.contrast = tokens.contrast == "high" and "high" or "normal"
  tokens.typography.font = safeMedia("font", profile.fontName, tokens.typography.font)
  tokens.surfaces.statusbar = safeMedia("statusbar", profile.statusbarName, tokens.surfaces.statusbar)
  if tokens.contrast == "high" then
    tokens.colors.TEXT = { 1, 1, 1, 1 }
    tokens.colors.TEXT_MUTED = { 0.82, 0.86, 0.90, 1 }
    tokens.colors.BORDER = { 0.60, 0.70, 0.80, 1 }
  end
  return tokens
end

function Midnight.GetLayoutMetrics()
  local tokens = Midnight.GetTokens()
  local sizing = tokens.sizing or {}
  local spacing = tokens.spacing or {}
  return {
    minWidth = math.max(420, tonumber(sizing.minWidth) or 520),
    minHeight = math.max(320, tonumber(sizing.minHeight) or 360),
    maxWidth = math.max(900, tonumber(sizing.maxWidth) or 1400),
    maxHeight = math.max(700, tonumber(sizing.maxHeight) or 1100),
    buttonHeight = math.max(22, tonumber(sizing.buttonHeight) or 24),
    modalWidth = math.max(420, tonumber(sizing.modalWidth) or 560),
    modalHeight = math.max(260, tonumber(sizing.modalHeight) or 320),
    defaultScrollHeight = math.max(260, tonumber(sizing.defaultScrollHeight) or 420),
    actionMinWidth = math.max(72, tonumber(sizing.actionMinWidth) or 88),
    rowHeight = math.max(20, tonumber(spacing.row) or 24),
  }
end

function Midnight.Truncate(value, maximum)
  local full = tostring(value or "")
  local limit = math.max(4, tonumber(maximum) or 80)
  if full:find("|Hitem:", 1, true) or #full <= limit then return full, false, full end
  local visible = full:sub(1, math.max(1, limit - 3)) .. "..."
  return visible, true, full
end

function Midnight.GetStatusPresentation(status)
  local key = string.lower(tostring(status or "normal"))
  local presentation = STATUS_PRESENTATIONS[key] or STATUS_PRESENTATIONS.normal
  return {
    label = presentation.label, marker = presentation.marker,
    explanation = presentation.explanation, tone = presentation.tone,
  }
end

function Midnight.GetStatePresentation(code)
  local key = string.upper(tostring(code or ""))
  local state = STATE_PRESENTATIONS[key]
  if not state then
    local fallback = Midnight.GetStatusPresentation("warning")
    return { label = fallback.label, marker = fallback.marker, explanation = fallback.explanation, tone = fallback.tone, technical = code }
  end
  local status = Midnight.GetStatusPresentation(state.status)
  return { label = state.label, marker = status.marker, explanation = state.explanation, tone = status.tone, technical = code }
end

function Midnight.GetProfile()
  return copy(localRoot().presentation.profile)
end

function Midnight.SetProfile(values)
  if type(values) ~= "table" then return false end
  local profile = localRoot().presentation.profile
  for key, value in pairs(values) do
    if key == "scale" then value = math.max(0.75, math.min(1.5, tonumber(value) or 1)) end
    if key == "contrast" then value = value == "high" and "high" or "normal" end
    if key == "density" and value ~= "compact" and value ~= "comfortable" then value = "comfortable" end
    if key == "fontName" or key == "statusbarName" or key == "scale" or key == "contrast" or key == "density" then
      profile[key] = value
    end
  end
  return true
end

function Midnight.ApplyToFrame(frame, tokens)
  tokens = tokens or Midnight.GetTokens()
  if not frame then return false end
  if type(frame.SetBackdropColor) == "function" then frame:SetBackdropColor(unpack(tokens.colors.SURFACE)) end
  if type(frame.SetBackdropBorderColor) == "function" then frame:SetBackdropBorderColor(unpack(tokens.colors.BORDER)) end
  if type(frame.SetScale) == "function" and tonumber(tokens.scale) then frame:SetScale(tokens.scale) end
  return true
end

function Midnight.ApplyToWidget(widget, tokens)
  tokens = tokens or Midnight.GetTokens()
  if type(widget) ~= "table" or not widget.frame then return false end
  local colors = tokens.colors or {}
  local normal = colors.TEXT or { 0.94, 0.96, 0.98, 1 }
  local muted = colors.TEXT_MUTED or { 0.64, 0.70, 0.76, 1 }
  local accent = colors.WARNING or { 0.95, 0.67, 0.20, 1 }
  local surface = colors.SURFACE or { 0.035, 0.055, 0.075, 0.97 }
  local raised = colors.SURFACE_RAISED or { 0.075, 0.10, 0.13, 0.98 }
  local border = colors.BORDER or { 0.22, 0.30, 0.38, 1 }

  local function styleBackdrop(frame, color)
    if type(frame.SetBackdropColor) == "function" then frame:SetBackdropColor(unpack(color)) end
    if type(frame.SetBackdropBorderColor) == "function" then frame:SetBackdropBorderColor(unpack(border)) end
  end

  styleBackdrop(widget.frame, surface)
  if widget.label and type(widget.label.SetTextColor) == "function" then widget.label:SetTextColor(unpack(normal)) end
  if widget.text and type(widget.text.SetTextColor) == "function" then widget.text:SetTextColor(unpack(normal)) end
  if widget.titletext and type(widget.titletext.SetTextColor) == "function" then widget.titletext:SetTextColor(unpack(accent)) end
  if widget.editbox and type(widget.editbox.SetTextColor) == "function" then widget.editbox:SetTextColor(unpack(normal)) end

  if type(widget.frame.GetChildren) == "function" then
    local children = { widget.frame:GetChildren() }
    for _, child in ipairs(children) do
      styleBackdrop(child, raised)
      if child.GetFontString and child:GetFontString() and child:GetFontString().SetTextColor then
        child:GetFontString():SetTextColor(unpack(normal))
      end
    end
  end
  if widget.type == "Heading" and widget.label and type(widget.label.SetTextColor) == "function" then
    widget.label:SetTextColor(unpack(accent))
  end
  if widget.type == "Label" and widget.label and type(widget.label.SetTextColor) == "function" then
    widget.label:SetTextColor(unpack(muted))
  end
  return true
end

function Midnight.CreatePanel(shell, parent, title)
  local gui = Dibs.AceGUI
  if not gui or type(gui.Create) ~= "function" then return nil end
  local panel = gui.Create(shell, "InlineGroup", parent) or gui.Create(shell, "SimpleGroup", parent)
  if not panel then return nil end
  if panel.SetFullWidth then panel:SetFullWidth(true) end
  if panel.SetLayout then panel:SetLayout("List") end
  if title and panel.SetTitle then panel:SetTitle(title) end
  return panel
end

function Midnight.AddStatusBadge(shell, parent, status, label)
  local gui = Dibs.AceGUI
  if not gui or type(gui.AddLabel) ~= "function" then return nil end
  local presentation = Midnight.GetStatusPresentation(status)
  local text = presentation.marker .. " " .. tostring(label or presentation.label)
  local badge = gui.AddLabel(shell, parent, text, true)
  if badge then
    badge.dibsMidnightStatus = presentation.tone
    gui.AddTooltip(badge, presentation.label, presentation.explanation)
  end
  return badge
end

function Midnight.AddEmptyState(shell, parent, title, description)
  local gui = Dibs.AceGUI
  if not gui then return nil end
  local group = Midnight.CreatePanel(shell, parent)
  if not group then return nil end
  gui.AddHeading(shell, group, title or "Nothing to show", description)
  return group
end

function Midnight.AddSandboxBanner(shell, parent, projection)
  local gui = Dibs.AceGUI
  if not gui then return nil end
  local active = type(projection) == "table" and projection.active == true
  local section = Midnight.CreatePanel(shell, parent)
  if not section then return nil end
  if active then
    Midnight.AddStatusBadge(shell, section, "warning", "DEVELOPER SANDBOX ACTIVE")
    gui.AddLabel(shell, section, "Simulated authority: " .. tostring(projection.role or "none"), true)
    gui.AddLabel(shell, section, "Production database is NOT being modified.", true)
  else
    Midnight.AddStatusBadge(shell, section, "info", "Developer Mode enabled; sandbox inactive")
    gui.AddLabel(shell, section, "Production data and authority are active until you explicitly enter the sandbox.", true)
  end
  return section
end

function Midnight.AddModal(shell, title, width, height)
  local gui = Dibs.AceGUI
  if not gui or type(gui.CreateWindow) ~= "function" then return nil end
  local metrics = Midnight.GetLayoutMetrics()
  return gui.CreateWindow(title, width or metrics.modalWidth, height or metrics.modalHeight)
end

return Midnight
