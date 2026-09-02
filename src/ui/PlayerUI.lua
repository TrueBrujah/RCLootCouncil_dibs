local Dibs = _G.Dibs
Dibs.PlayerUI = Dibs.PlayerUI or {}

function Dibs.PlayerUI.GetSummary(playerName)
  local season = Dibs.Seasons and Dibs.Seasons.GetCurrent() or nil
  local balance = Dibs.Ledger and Dibs.Ledger.GetBalance(playerName or Dibs.GetPlayerName(), season and season.id) or 0
  local requests = Dibs.PreDibs and Dibs.PreDibs.GetActiveRequests(playerName or Dibs.GetPlayerName()) or {}

  return {
    season = season,
    player = playerName or Dibs.GetPlayerName(),
    balance = balance,
    activePreDibs = requests,
  }
end

function Dibs.PlayerUI.GetHistory(playerName)
  if not Dibs.Ledger then
    return {}
  end

  return Dibs.Ledger.GetHistory(playerName or Dibs.GetPlayerName())
end

function Dibs.PlayerUI.CreateWindow()
  if _G.DibsPlayerFrame then
    return _G.DibsPlayerFrame
  end

  local frame = CreateFrame("Frame", "DibsPlayerFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(350, 220)
  frame:SetPoint("CENTER", 0, 0)
  frame:Hide()
  frame:SetClampedToScreen(true)
  frame:SetToplevel(true)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -12)
  title:SetText("Dibs")

  local summaryText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  summaryText:SetPoint("TOPLEFT", 16, -40)
  summaryText:SetWidth(300)
  summaryText:SetJustifyH("LEFT")

  local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

  frame.summaryText = summaryText
  frame.Refresh = function(self)
    local summary = Dibs.PlayerUI.GetSummary()
    local status = "Season: " .. tostring((summary.season and summary.season.name) or "None") .. "\nBalance: " .. tostring(summary.balance) .. "\nPre-Dibs: " .. tostring(#(summary.activePreDibs or {}))
    self.summaryText:SetText(status)
  end

  frame:HookScript("OnShow", function(self)
    self:Refresh()
  end)

  _G.DibsPlayerFrame = frame
  return frame
end

function Dibs.PlayerUI.Show()
  local frame = Dibs.PlayerUI.CreateWindow()
  frame:Show()
  frame:Raise()
  if frame.Refresh then
    frame:Refresh()
  end

  local summary = Dibs.PlayerUI.GetSummary()
  Dibs.Message("Dibs: " .. tostring(summary.balance) .. " available")
  return summary
end

function Dibs.PlayerUI.Toggle(forceShow)
  local frame = Dibs.PlayerUI.CreateWindow()
  if forceShow then
    frame:Show()
    frame:Raise()
  elseif frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
    frame:Raise()
  end

  if frame:IsShown() and frame.Refresh then
    frame:Refresh()
  end

  return frame:IsShown()
end
