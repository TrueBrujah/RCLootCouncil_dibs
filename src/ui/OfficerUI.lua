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
  local permissions = Dibs.GetDB().permissions or {}
  local adminCount = 0
  for _ in pairs(permissions.activeStandaloneAdmins or {}) do adminCount = adminCount + 1 end
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
    "Standalone admins: " .. tostring(adminCount) .. " (audit events: " .. tostring(#(permissions.adminEvents or {})) .. ")\n" ..
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
    local result = Dibs.ProtectedActions.Execute("season.create", nil, { name = "Season " .. tostring((Dibs.Seasons and #Dibs.Seasons.List() or 0) + 1) })
    local season = result.value
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
      local result = Dibs.ProtectedActions.Execute("rank.set", nil, { seasonId = season and season.id or Dibs.GetCurrentSeasonId(), rankIndex = 1, rankName = "Rank 1", allocation = 1 })
      Dibs.Message(result.ok and "Rank 1 set to 1 Dib for the current season." or result.diagnostic)
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

function Dibs.OfficerUI.ManageStandaloneAdmin(target, appoint)
  return Dibs.ProtectedActions.Execute(appoint and "admin.appoint" or "admin.revoke", nil, { target = target, reason = "Officer UI" })
end

function Dibs.OfficerUI.GetCandidateFallback(playerName, itemID)
  if not Dibs.RCLootCouncil or not Dibs.RCLootCouncil.GetStatusForCandidate then
    return nil, (Dibs.L and Dibs.L.RC_STATUS_UNAVAILABLE) or "RCLootCouncil status is unavailable."
  end
  local status = Dibs.RCLootCouncil.GetStatusForCandidate(playerName, itemID)
  local availability = Dibs.RCLootCouncil.GetAvailability and Dibs.RCLootCouncil.GetAvailability() or "absent"
  if availability ~= "operational" then
    status.diagnostic = (Dibs.L and Dibs.L.RC_COMPATIBILITY_FALLBACK) or "RCLootCouncil candidate integration is unavailable; using the local Dibs display."
  end
  return status, status.diagnostic
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
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    Dibs.OfficerUI.pendingToggle = forceShow ~= false
    Dibs.Message((Dibs.L and Dibs.L.UI_DEFERRED_COMBAT) or "Officer UI will open after combat.")
    return false
  end
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
  if not Dibs.ProtectedActions then
    return nil
  end
  local result = Dibs.ProtectedActions.Execute("season.create", nil, { name = name })
  return result.ok and result.value or nil, result
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
  if Dibs.OfficerUI.pendingToggle then
    Dibs.OfficerUI.pendingToggle = nil
    Dibs.OfficerUI.Toggle(true)
  end
end)
