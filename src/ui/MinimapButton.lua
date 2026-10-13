--[[
Module: Dibs.MinimapButton
Purpose: Provide a small, permission-preserving shortcut to the Dibs UI.
The button is deliberately local and has no effect on ledger, sync, or authority.
]]

local Dibs = _G.Dibs

Dibs.MinimapButton = Dibs.MinimapButton or {}
local MinimapButton = Dibs.MinimapButton

local function getText(key, fallback)
  return (Dibs.L and Dibs.L[key]) or fallback
end

local function openPlayer()
  if Dibs.PlayerUI and Dibs.PlayerUI.Show then
    Dibs.PlayerUI.Show()
  end
end

local function openOfficerOrPlayer()
  local permissions = Dibs.Permissions
  local isOfficer = permissions and permissions.IsOfficer and permissions.IsOfficer()
  local isGM = permissions and permissions.IsGM and permissions.IsGM()
  if (isOfficer or isGM) and Dibs.OfficerUI and Dibs.OfficerUI.Toggle then
    Dibs.OfficerUI.Toggle(true)
    return
  end
  openPlayer()
end

local function showTooltip(button)
  if type(_G.GameTooltip) ~= "table" and type(_G.GameTooltip) ~= "userdata" then return end
  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  GameTooltip:SetText(getText("MINIMAP_TOOLTIP", "RCLootCouncil_dibs"))
  GameTooltip:AddLine(getText("MINIMAP_LEFT_CLICK", "Left-click: open Dibs"))
  GameTooltip:AddLine(getText("MINIMAP_RIGHT_CLICK", "Right-click: open your Dibs"))
  GameTooltip:Show()
end

local function hideTooltip()
  if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
end

function MinimapButton.Create()
  if MinimapButton.button then return MinimapButton.button end
  if type(_G.CreateFrame) ~= "function" or not _G.Minimap then return nil end

  local button = CreateFrame("Button", "DibsMinimapButton", Minimap)
  button:SetSize(32, 32)
  button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -4, 4)
  button:SetFrameStrata("MEDIUM")
  button:SetClampedToScreen(true)
  button:RegisterForClicks("AnyUp")

  local icon = button:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture(Dibs.ICON_TEXTURE or "Interface\\Icons\\INV_Misc_Coin_01")
  icon:SetAllPoints(button)
  button.icon = icon

  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
  if highlight.SetBlendMode then highlight:SetBlendMode("ADD") end
  highlight:SetAllPoints(button)
  button:SetHighlightTexture(highlight)

  button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
      openPlayer()
    else
      openOfficerOrPlayer()
    end
  end)
  button:SetScript("OnEnter", showTooltip)
  button:SetScript("OnLeave", hideTooltip)

  MinimapButton.button = button
  return button
end

function MinimapButton.Initialize()
  return MinimapButton.Create()
end

local bootstrap = type(_G.CreateFrame) == "function" and CreateFrame("Frame") or nil
if bootstrap then
  bootstrap:RegisterEvent("PLAYER_LOGIN")
  bootstrap:SetScript("OnEvent", function()
    MinimapButton.Initialize()
  end)
end
