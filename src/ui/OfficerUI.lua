local Dibs = _G.Dibs
Dibs.OfficerUI = Dibs.OfficerUI or {}

function Dibs.OfficerUI.GetLedgerOverview()
  local transactions = Dibs.Ledger and Dibs.Ledger.GetAllTransactions() or {}
  return {
    count = #transactions,
    transactions = transactions,
    isOfficer = Dibs.Permissions and Dibs.Permissions.IsOfficer() or false,
  }
end

function Dibs.OfficerUI.BuildStatusText()
  local season = Dibs.Seasons and Dibs.Seasons.GetCurrent() or nil
  local seasons = Dibs.Seasons and Dibs.Seasons.List() or {}
  local overview = Dibs.OfficerUI.GetLedgerOverview()
  local rules = Dibs.RankRules and Dibs.RankRules.GetRulesForSeason(season and season.id or Dibs.GetCurrentSeasonId()) or {}
  local ruleText = ""
  local items = {}

  for _, rule in pairs(rules) do
    table.insert(items, "R" .. tostring(rule.rankIndex) .. "=" .. tostring(rule.allocation))
  end
  table.sort(items)
  ruleText = table.concat(items, ", ")
  if ruleText == "" then
    ruleText = "none"
  end

  return "Season: " .. tostring(season and season.name or "None") .. "\n" ..
    "Seasons: " .. tostring(#seasons) .. "\n" ..
    "Transactions: " .. tostring(overview.count) .. "\n" ..
    "Role: " .. tostring(Dibs.Permissions and Dibs.Permissions.GetRole() or "player") .. "\n" ..
    "Rank rules: " .. ruleText
end

function Dibs.OfficerUI.CreateWindow()
  if _G.DibsOfficerFrame then
    return _G.DibsOfficerFrame
  end

  local frame = CreateFrame("Frame", "DibsOfficerFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(420, 260)
  frame:SetPoint("CENTER", 260, 0)
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
  title:SetText("Dibs Officer")

  local summaryText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  summaryText:SetPoint("TOPLEFT", 16, -40)
  summaryText:SetWidth(360)
  summaryText:SetJustifyH("LEFT")

  local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

  local newSeasonButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  newSeasonButton:SetSize(120, 24)
  newSeasonButton:SetPoint("BOTTOMLEFT", 16, 14)
  newSeasonButton:SetText("New Season")
  newSeasonButton:SetScript("OnClick", function()
    local season = Dibs.Seasons and Dibs.Seasons.Create("Season " .. tostring((Dibs.Seasons and #Dibs.Seasons.List() or 0) + 1))
    if season then
      Dibs.Message("Created season: " .. tostring(season.name))
      frame:Refresh()
    end
  end)

  local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refreshButton:SetSize(90, 24)
  refreshButton:SetPoint("BOTTOMLEFT", 150, 14)
  refreshButton:SetText("Refresh")
  refreshButton:SetScript("OnClick", function()
    frame:Refresh()
  end)

  local setRankButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  setRankButton:SetSize(120, 24)
  setRankButton:SetPoint("BOTTOMLEFT", 255, 14)
  setRankButton:SetText("Set Rank 1")
  setRankButton:SetScript("OnClick", function()
    local season = Dibs.Seasons and Dibs.Seasons.GetCurrent() or nil
    if Dibs.RankRules and Dibs.RankRules.SetAllocation then
      Dibs.RankRules.SetAllocation(season and season.id or Dibs.GetCurrentSeasonId(), 1, "Rank 1", 1)
      Dibs.Message("Rank 1 set to 1 Dib for the current season.")
      frame:Refresh()
    end
  end)

  frame.summaryText = summaryText
  frame.Refresh = function(self)
    self.summaryText:SetText(Dibs.OfficerUI.BuildStatusText())
  end

  frame:HookScript("OnShow", function(self)
    self:Refresh()
  end)

  _G.DibsOfficerFrame = frame
  return frame
end

function Dibs.OfficerUI.Show()
  local frame = Dibs.OfficerUI.CreateWindow()
  frame:Show()
  frame:Raise()
  if frame.Refresh then
    frame:Refresh()
  end

  local overview = Dibs.OfficerUI.GetLedgerOverview()
  Dibs.Message("Dibs officer ledger: " .. tostring(overview.count) .. " transactions")
  return overview
end

function Dibs.OfficerUI.Toggle(forceShow)
  local frame = Dibs.OfficerUI.CreateWindow()
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

function Dibs.OfficerUI.CreateSeason(name)
  if not Dibs.Seasons then
    return nil
  end

  return Dibs.Seasons.Create(name)
end
