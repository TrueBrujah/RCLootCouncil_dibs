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
  sizing = { minWidth = 520, minHeight = 360, buttonHeight = 24, modalWidth = 560 },
  surfaces = { statusbar = FALLBACK_STATUSBAR, borderThickness = 1, backgroundAlpha = 0.97 },
  density = "comfortable",
  scale = 1,
  contrast = "normal",
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

function Midnight.GetDefaults()
  return copy(defaults)
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
  local text = tostring(label or status or "")
  local badge = gui.AddLabel(shell, parent, text, false)
  if badge then badge.dibsMidnightStatus = tostring(status or "INFO") end
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

function Midnight.AddModal(shell, title, width, height)
  local gui = Dibs.AceGUI
  if not gui or type(gui.CreateWindow) ~= "function" then return nil end
  return gui.CreateWindow(title, width or defaults.sizing.modalWidth, height or 320)
end

return Midnight
