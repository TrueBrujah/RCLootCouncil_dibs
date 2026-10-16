--[[
Module: Dibs.MinimapButton
Purpose: Provide a small, permission-preserving shortcut to the Dibs UI.
The button is deliberately local and has no effect on ledger, sync, or authority.
]]

local Dibs = _G.Dibs

Dibs.MinimapButton = Dibs.MinimapButton or {}
local MinimapButton = Dibs.MinimapButton

local function isVisible()
  local settings = Dibs.GetLocalSettings and Dibs.GetLocalSettings()
  if type(settings) ~= "table" then return true end
  if type(settings.minimapButtonShown) ~= "boolean" then settings.minimapButtonShown = true end
  return settings.minimapButtonShown
end

local BUTTON_SIZE = 31
local DEFAULT_ANGLE = 135
local DEFAULT_SCALE = 1
local MIN_SCALE = 0.5
local MAX_SCALE = 2
local EDGE_OFFSET = 5

local function getSettings()
  local settings = Dibs.GetLocalSettings and Dibs.GetLocalSettings()
  if type(settings) ~= "table" then return nil end
  return settings
end

local function normalizeAngle(angle)
  angle = tonumber(angle)
  if not angle or angle ~= angle then return nil end
  return angle % 360
end

local function normalizeScale(scale)
  scale = tonumber(scale)
  if not scale or scale ~= scale or scale < MIN_SCALE or scale > MAX_SCALE then return nil end
  return math.floor(scale * 100 + 0.5) / 100
end

local function getAngle()
  local settings = getSettings()
  local angle = settings and normalizeAngle(settings.minimapButtonAngle)
  return angle or DEFAULT_ANGLE
end

local function getScale()
  local settings = getSettings()
  local scale = settings and normalizeScale(settings.minimapButtonScale)
  return scale or DEFAULT_SCALE
end

local function isSquareMinimap()
  local shape = type(_G.GetMinimapShape) == "function" and _G.GetMinimapShape() or "ROUND"
  return shape == "SQUARE"
end

local function applyPosition(button)
  local minimap = _G.Minimap
  if not (button and minimap) then return end
  local radians = math.rad(getAngle())
  local x, y = math.cos(radians), math.sin(radians)
  local width = (minimap.GetWidth and minimap:GetWidth() or 140)
  local height = (minimap.GetHeight and minimap:GetHeight() or 140)
  if width <= 0 then width = 140 end
  if height <= 0 then height = 140 end
  local radiusX, radiusY = width / 2 + EDGE_OFFSET, height / 2 + EDGE_OFFSET
  if isSquareMinimap() then
    -- Project onto the square edge instead of a circle.
    local diagonal = math.sqrt(2)
    x = math.max(-radiusX, math.min(x * radiusX * diagonal, radiusX))
    y = math.max(-radiusY, math.min(y * radiusY * diagonal, radiusY))
  else
    x, y = x * radiusX, y * radiusY
  end
  local scale = button.GetScale and button:GetScale() or 1
  if not scale or scale <= 0 then scale = 1 end
  button:ClearAllPoints()
  button:SetPoint("CENTER", minimap, "CENTER", x / scale, y / scale)
end

local function applyScale(button)
  if not button then return end
  if button.SetScale then button:SetScale(getScale()) end
  applyPosition(button)
end

local function updateDragPosition(button)
  local minimap = _G.Minimap
  if not (minimap and minimap.GetCenter and type(_G.GetCursorPosition) == "function") then return end
  local centerX, centerY = minimap:GetCenter()
  if not (centerX and centerY) then return end
  local cursorX, cursorY = _G.GetCursorPosition()
  local scale = minimap.GetEffectiveScale and minimap:GetEffectiveScale() or 1
  if not scale or scale <= 0 then scale = 1 end
  local dx, dy = cursorX / scale - centerX, cursorY / scale - centerY
  if dx == 0 and dy == 0 then return end
  local settings = getSettings()
  if settings then settings.minimapButtonAngle = normalizeAngle(math.deg((math.atan2 or math.atan)(dy, dx))) end
  applyPosition(button)
end

local function getText(key, fallback)
  return (Dibs.L and Dibs.L[key]) or fallback
end

local function openPlayer()
  if Dibs.PlayerUI and Dibs.PlayerUI.Toggle then
    Dibs.PlayerUI.Toggle()
  end
end

local function openOfficerOrPlayer()
  local permissions = Dibs.Permissions
  local isOfficer = permissions and permissions.IsOfficer and permissions.IsOfficer()
  local isGM = permissions and permissions.IsGM and permissions.IsGM()
  if (isOfficer or isGM) and Dibs.OfficerUI and Dibs.OfficerUI.Toggle then
    Dibs.OfficerUI.Toggle()
    return
  end
  openPlayer()
end

local function showTooltip(button)
  if type(_G.GameTooltip) ~= "table" and type(_G.GameTooltip) ~= "userdata" then return end
  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  GameTooltip:SetText(getText("MINIMAP_TOOLTIP", "RCLootCouncil_dibs"))
  GameTooltip:AddLine(getText("MINIMAP_LEFT_CLICK", "Left-click: toggle Dibs"))
  GameTooltip:AddLine(getText("MINIMAP_RIGHT_CLICK", "Right-click: toggle your Dibs"))
  GameTooltip:AddLine(getText("MINIMAP_DRAG_HINT", "Drag: move the icon around the minimap"))
  GameTooltip:Show()
end

local function hideTooltip()
  if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
end

function MinimapButton.Create()
  if MinimapButton.button then return MinimapButton.button end
  if type(_G.CreateFrame) ~= "function" or not _G.Minimap then return nil end

  local button = CreateFrame("Button", "DibsMinimapButton", Minimap)
  button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
  button:SetFrameStrata("MEDIUM")
  button:SetClampedToScreen(true)
  button:RegisterForClicks("AnyUp")
  if button.RegisterForDrag then button:RegisterForDrag("LeftButton") end

  if button.SetFrameLevel then button:SetFrameLevel(8) end

  -- Same round tracking-button styling as LibDBIcon-based buttons (e.g. BugSack).
  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
  background:SetSize(24, 24)
  background:SetPoint("CENTER", button, "CENTER", 0, 0)
  button.background = background

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(Dibs.ICON_TEXTURE or "Interface\\Icons\\INV_Misc_Coin_01")
  icon:SetSize(18, 18)
  icon:SetPoint("CENTER", button, "CENTER", 0, 0)
  if icon.SetTexCoord then icon:SetTexCoord(0.05, 0.95, 0.05, 0.95) end
  if button.CreateMaskTexture and icon.AddMaskTexture then
    local mask = button:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    button.iconMask = mask
  end
  button.icon = icon

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
  border:SetSize(50, 50)
  border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  button.border = border

  button:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight

  button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
      openPlayer()
    else
      openOfficerOrPlayer()
    end
  end)
  button:SetScript("OnEnter", showTooltip)
  button:SetScript("OnLeave", hideTooltip)
  button:SetScript("OnDragStart", function(self)
    hideTooltip()
    self.isDragging = true
    self:SetScript("OnUpdate", updateDragPosition)
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    self.isDragging = nil
    updateDragPosition(self)
  end)

  MinimapButton.button = button
  applyScale(button)
  if not isVisible() then button:Hide() end
  return button
end

function MinimapButton.GetVisible()
  return isVisible()
end

function MinimapButton.SetVisible(visible)
  if type(visible) ~= "boolean" then return false, "INVALID_VALUE" end
  local settings = Dibs.GetLocalSettings and Dibs.GetLocalSettings()
  if type(settings) ~= "table" then return false, "SETTINGS_UNAVAILABLE" end
  settings.minimapButtonShown = visible
  local button = MinimapButton.button or MinimapButton.Create()
  if button then
    if visible then button:Show() else button:Hide() end
  end
  return true
end

MinimapButton.MIN_SCALE = MIN_SCALE
MinimapButton.MAX_SCALE = MAX_SCALE
MinimapButton.DEFAULT_SCALE = DEFAULT_SCALE
MinimapButton.DEFAULT_ANGLE = DEFAULT_ANGLE

function MinimapButton.GetScale()
  return getScale()
end

function MinimapButton.SetScale(scale)
  local value = normalizeScale(scale)
  if not value then return false, "INVALID_VALUE" end
  local settings = getSettings()
  if not settings then return false, "SETTINGS_UNAVAILABLE" end
  settings.minimapButtonScale = value
  applyScale(MinimapButton.button)
  return true
end

function MinimapButton.GetAngle()
  return getAngle()
end

function MinimapButton.SetAngle(angle)
  local value = normalizeAngle(angle)
  if not value then return false, "INVALID_VALUE" end
  local settings = getSettings()
  if not settings then return false, "SETTINGS_UNAVAILABLE" end
  settings.minimapButtonAngle = value
  applyPosition(MinimapButton.button)
  return true
end

function MinimapButton.ResetLayout()
  local settings = getSettings()
  if not settings then return false, "SETTINGS_UNAVAILABLE" end
  settings.minimapButtonAngle = nil
  settings.minimapButtonScale = nil
  applyScale(MinimapButton.button)
  return true
end

function MinimapButton.Initialize()
  local button = MinimapButton.Create()
  if button and isVisible() then button:Show() end
  return button
end

local bootstrap = type(_G.CreateFrame) == "function" and CreateFrame("Frame") or nil
if bootstrap then
  bootstrap:RegisterEvent("PLAYER_LOGIN")
  bootstrap:SetScript("OnEvent", function()
    MinimapButton.Initialize()
  end)
end
