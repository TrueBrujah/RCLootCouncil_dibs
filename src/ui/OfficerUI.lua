local Dibs = _G.Dibs
Dibs.OfficerUI = Dibs.OfficerUI or {}

local RANK_LABELS = {
  [0] = "Guild Master",
  [1] = "Officer",
  [2] = "Veteran",
  [3] = "Member",
  [4] = "Initiate",
  [5] = "Alt",
}

local ANNOUNCEMENT_CHANNEL_VALUES = {
  NONE = "None",
  RAID = "Raid",
  RAID_WARNING = "Raid Warning",
  RAID_DIBS = "Raid Dibs",
  SAY = "Say",
  YELL = "Yell",
  GUILD = "Guild",
  OFFICER = "Officer",
  PARTY = "Party",
  INSTANCE_CHAT = "Instance Chat",
}
local DEFAULT_PREDIB_TEMPLATE = "[Dibs] %player requested %item (%difficulty) - %date %time"
local DEFAULT_REMINDER_TEMPLATE = "[Dibs] Review your eligible Pre-Dibs before the encounter. [%date %time]"

local OFFICER_NAV_TREE = {
  { text = "Overview", value = "overview" },
  { text = "Review Requests", value = "disputes" },
  { text = "Seasons", value = "seasons" },
  { text = "Rank Rules", value = "ranks" },
  { text = "Settings", value = "settings" },
  { text = "Pre-Dibs", value = "preDibs" },
  { text = "Announcements", value = "announcements" },
  { text = "Developer", value = "developer" },
  { text = "RCLootCouncil", value = "integration" },
  { text = "Debug", value = "debug" },
}

-- Keep the old programmatic names working for macros and existing tests while
-- presenting the same Officer tree as the RCLootCouncil options panel.
local OFFICER_TAB_ALIASES = {
  dashboard = "overview",
  lootTypes = "integration",
  predibs = "preDibs",
  dispute = "disputes",
  review = "disputes",
}

local function normalizeOfficerTab(tab)
  return OFFICER_TAB_ALIASES[tab] or tab
end

-- Officer views contain the guild-wide ledger, Pre-Dibs history and rank
-- diagnostics.  Keep the authorization check at the read boundary so a
-- normal player cannot bypass the UI by calling these Lua functions directly.
local function canViewOfficerData()
  if type(Dibs.Permissions) ~= "table" or type(Dibs.Permissions.GetGuildRole) ~= "function" then
    return false
  end
  local ok, role = pcall(Dibs.Permissions.GetGuildRole, nil)
  return ok and (role == "gm" or role == "officer")
end

local function emptyOfficerPage(view, query)
  local selectedView = view == "actions" and "actions" or (view == "predibs" and "predibs" or "players")
  local title = selectedView == "actions" and "Actions"
    or (selectedView == "predibs" and "Pre-Dibs" or "Players")
  return {
    title = title,
    lines = { "Officer access required." },
    page = 1,
    totalPages = 1,
    totalCount = 0,
    query = string.lower(tostring(query or "")),
    hiddenCount = 0,
  }
end

local HAS_DROPDOWN = type(_G.UIDropDownMenu_Initialize) == "function"
  and type(_G.UIDropDownMenu_CreateInfo) == "function"
  and type(_G.UIDropDownMenu_AddButton) == "function"
  and type(_G.UIDropDownMenu_SetText) == "function"

local function trimText(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function sortedLabels(values)
  local entries = {}
  for key, label in pairs(values or {}) do
    table.insert(entries, { key = key, label = label })
  end
  table.sort(entries, function(a, b) return tostring(a.label) < tostring(b.label) end)
  local result = {}
  for _, entry in ipairs(entries) do result[entry.key] = entry.label end
  return result
end

local function disputeStatusText(request)
  if not request then return "" end
  return tostring(request.status or "Open") .. " | " .. tostring(request.categoryLabel or request.category or "Other")
end

local function setControlText(control, text)
  if not control then
    return
  end
  control._dibsText = tostring(text or "")
  if control.SetText then
    control:SetText(control._dibsText)
  end
end

local function getControlText(control)
  if not control then
    return ""
  end
  if control.GetText then
    local ok, value = pcall(control.GetText, control)
    if ok then
      return tostring(value or "")
    end
  end
  return tostring(control._dibsText or "")
end

local function setDropdownText(control, text)
  if control and HAS_DROPDOWN and _G.UIDropDownMenu_SetText then
    _G.UIDropDownMenu_SetText(control, tostring(text or ""))
  elseif control and control.SetText then
    control:SetText(tostring(text or ""))
  end
end

local function setControlsVisible(controls, visible)
  for _, control in ipairs(controls or {}) do
    if control then
      if visible and control.Show then
        control:Show()
      elseif not visible and control.Hide then
        control:Hide()
      end
    end
  end
end

local function formatHistoryDate(timestamp)
  local value = tonumber(timestamp) or 0
  if type(date) == "function" and value > 0 then
    local ok, formatted = pcall(date, "%Y-%m-%d %H:%M", value)
    if ok and formatted then
      return tostring(formatted)
    end
  end
  return tostring(value)
end

local function configureDropdown(control, width, initializer)
  if not control or not HAS_DROPDOWN then
    return false
  end
  if _G.UIDropDownMenu_SetWidth then
    _G.UIDropDownMenu_SetWidth(control, width or 120)
  end
  if _G.UIDropDownMenu_JustifyText then
    _G.UIDropDownMenu_JustifyText(control, "LEFT")
  end
  _G.UIDropDownMenu_Initialize(control, initializer)
  return true
end

local function getSeasonList()
  local seasons = Dibs.Seasons and Dibs.Seasons.List and Dibs.Seasons.List() or {}
  table.sort(seasons, function(a, b)
    return (a.createdAt or 0) < (b.createdAt or 0)
  end)
  return seasons
end

local function findSeasonById(seasonId)
  return Dibs.Seasons and Dibs.Seasons.GetById and Dibs.Seasons.GetById(seasonId) or nil
end

local function getSelectedSeason(frame)
  local selected = frame and frame.selectedSeasonId or nil
  local season = selected and findSeasonById(selected) or nil
  if season and not season.isArchived then
    return season
  end
  return Dibs.Seasons and Dibs.Seasons.GetCurrent and Dibs.Seasons.GetCurrent() or nil
end

local function getGuildRankNames()
  local names = {}

  if type(_G.GuildControlGetNumRanks) == "function" and type(_G.GuildControlGetRankName) == "function" then
    local okCount, rankCount = pcall(_G.GuildControlGetNumRanks)
    if okCount and tonumber(rankCount) then
      for i = 1, tonumber(rankCount) do
        local okName, rankName = pcall(_G.GuildControlGetRankName, i)
        if okName and rankName and rankName ~= "" then
          names[i - 1] = tostring(rankName)
        end
      end
    end
  end

  if next(names) == nil and type(_G.GetNumGuildMembers) == "function" and type(_G.GetGuildRosterInfo) == "function" then
    local memberCount = _G.GetNumGuildMembers()
    local count = tonumber(memberCount) or 0
    for i = 1, count do
      local _, rankName, rankIndex = _G.GetGuildRosterInfo(i)
      local idx = tonumber(rankIndex)
      if idx ~= nil and rankName and rankName ~= "" and names[idx] == nil then
        names[idx] = tostring(rankName)
      end
    end
  end

  for idx, fallback in pairs(RANK_LABELS) do
    if names[idx] == nil then
      names[idx] = fallback
    end
  end

  return names
end

local function getCurrentGuildMemberNames()
  if type(_G.GetNumGuildMembers) ~= "function" or type(_G.GetGuildRosterInfo) ~= "function" then
    return nil
  end

  local memberNames = {}
  local memberCount = _G.GetNumGuildMembers()
  local count = tonumber(memberCount) or 0
  for index = 1, count do
    local name = _G.GetGuildRosterInfo(index)
    if name and name ~= "" then
      local fullName = string.lower(tostring(name))
      memberNames[fullName] = tostring(name)
      local shortName = fullName:match("^([^-]+)")
      if shortName then
        memberNames[shortName] = tostring(name)
      end
    end
  end

  return next(memberNames) and memberNames or nil
end

local function getCurrentGuildMemberName(memberNames, playerName)
  if not memberNames then
    return tostring(playerName or "Unknown")
  end
  local fullName = string.lower(tostring(playerName or ""))
  local shortName = fullName:match("^([^-]+)")
  return memberNames[fullName] or (shortName ~= nil and memberNames[shortName]) or nil
end

local function getRankName(rankIndex)
  local idx = tonumber(rankIndex) or 0
  local names = getGuildRankNames()
  return names[idx] or ("Rank " .. tostring(idx))
end

local function buildRankLabel(rankIndex)
  local idx = tonumber(rankIndex) or 0
  return tostring(idx) .. " - " .. getRankName(idx)
end

local function getExpansionName()
  if type(_G.GetExpansionLevel) == "function" then
    local ok, level = pcall(_G.GetExpansionLevel)
    local idx = ok and tonumber(level) or nil
    if idx then
      local current = _G["EXPANSION_NAME" .. tostring(idx)]
      if type(current) == "string" and current ~= "" then
        return current
      end
    end
  end

  if type(_G.GetBuildInfo) == "function" then
    local ok, _, _, interfaceVersion = pcall(_G.GetBuildInfo)
    local iv = ok and tonumber(interfaceVersion) or nil
    if iv then
      local idx = math.floor(iv / 10000)
      local fromBuild = _G["EXPANSION_NAME" .. tostring(idx)]
      if type(fromBuild) == "string" and fromBuild ~= "" then
        return fromBuild
      end
    end
  end

  for i = 1, 20 do
    local name = _G["EXPANSION_NAME" .. tostring(i)]
    if type(name) == "string" and name ~= "" and not string.find(name, "^Expansion%d+$") then
      return name
    end
  end

  return "Season"
end

local function getDefaultSeasonName()
  local count = #getSeasonList()
  local expansion = tostring(getExpansionName()):gsub("%s+", "")
  if expansion == "" then
    expansion = "Season"
  end
  return expansion .. "_Season" .. tostring(count + 1)
end

local function normalizeSeasonName(name)
  return trimText(name):lower()
end

local function findSeasonByName(name, excludeSeasonId)
  local needle = normalizeSeasonName(name)
  if needle == "" then
    return nil
  end
  for _, season in ipairs(getSeasonList()) do
    if season.id ~= excludeSeasonId and normalizeSeasonName(season.name) == needle then
      return season
    end
  end
  return nil
end

local function makeUniqueSeasonName(name)
  local base = trimText(name)
  if base == "" then
    base = getDefaultSeasonName()
  end
  if not findSeasonByName(base, nil) then
    return base
  end

  local suffix = 2
  while suffix < 999 do
    local candidate = base .. "_" .. tostring(suffix)
    if not findSeasonByName(candidate, nil) then
      return candidate
    end
    suffix = suffix + 1
  end

  return base .. "_dup"
end

local function applyRankRule(frame, row)
  local season = getSelectedSeason(frame)
  if not season then
    frame:SetStatus("No active season available.")
    return
  end

  local rankIndex = tonumber(row.rankIndex) or 0
  local allocation = tonumber(row.allocation) or 0
  if allocation < 0 then
    allocation = 0
  end

  local result = Dibs.ProtectedActions.Execute("rank.set", nil, {
    seasonId = season.id,
    rankIndex = rankIndex,
    rankName = getRankName(rankIndex),
    allocation = allocation,
  })

  frame:SetStatus(result.ok and ("Saved " .. buildRankLabel(rankIndex) .. " = " .. tostring(allocation)) or result.diagnostic)
  frame:Refresh()
end

local function refreshRankRowVisual(row)
  if not row then
    return
  end
  if row.rankButton then
    row.rankButton:SetText(buildRankLabel(row.rankIndex))
  end
  if row.rankDropdown then
    setDropdownText(row.rankDropdown, buildRankLabel(row.rankIndex))
  end
  if row.valueText then
    row.valueText:SetText("Dibs: " .. tostring(row.allocation))
  end
end

local function createRankRow(frame, index)
  local row = CreateFrame("Frame", nil, frame)
  row:SetSize(600, 24)
  row:SetPoint("TOPLEFT", 14, -310 - ((index - 1) * 26))
  row.rankIndex = index - 1
  row.allocation = 1

  local rankButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  rankButton:SetSize(160, 22)
  rankButton:SetPoint("LEFT", 0, 0)
  rankButton:SetScript("OnClick", function()
    row.rankIndex = ((tonumber(row.rankIndex) or 0) + 1) % 10
    refreshRankRowVisual(row)
  end)
  row.rankButton = rankButton

  if HAS_DROPDOWN then
    local rankDropdown = CreateFrame("Frame", nil, row, "UIDropDownMenuTemplate")
    rankDropdown:SetPoint("LEFT", -12, 0)
    configureDropdown(rankDropdown, 150, function(_, level)
      if level ~= 1 then
        return
      end
      local maxRank = math.max(9, (_G.GuildControlGetNumRanks and _G.GuildControlGetNumRanks() - 1) or 9)
      for idx = 0, maxRank do
        local info = _G.UIDropDownMenu_CreateInfo()
        info.text = buildRankLabel(idx)
        info.func = function()
          row.rankIndex = idx
          refreshRankRowVisual(row)
        end
        info.checked = tonumber(row.rankIndex) == idx
        _G.UIDropDownMenu_AddButton(info, level)
      end
    end)
    row.rankDropdown = rankDropdown
    if row.rankButton.Hide then
      row.rankButton:Hide()
    end
  end

  local minusButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  minusButton:SetSize(28, 22)
  minusButton:SetPoint("LEFT", rankButton, "RIGHT", 8, 0)
  minusButton:SetText("-")
  minusButton:SetScript("OnClick", function()
    row.allocation = math.max(0, (tonumber(row.allocation) or 0) - 1)
    refreshRankRowVisual(row)
  end)

  local plusButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  plusButton:SetSize(28, 22)
  plusButton:SetPoint("LEFT", minusButton, "RIGHT", 4, 0)
  plusButton:SetText("+")
  plusButton:SetScript("OnClick", function()
    row.allocation = (tonumber(row.allocation) or 0) + 1
    refreshRankRowVisual(row)
  end)

  local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  valueText:SetPoint("LEFT", plusButton, "RIGHT", 10, 0)
  valueText:SetWidth(90)
  valueText:SetJustifyH("LEFT")
  row.valueText = valueText

  local applyButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  applyButton:SetSize(72, 22)
  applyButton:SetPoint("LEFT", valueText, "RIGHT", 8, 0)
  applyButton:SetText("Set")
  applyButton:SetScript("OnClick", function()
    applyRankRule(frame, row)
  end)

  refreshRankRowVisual(row)
  return row
end

local function syncRowsToSeason(frame, season)
  local rules = Dibs.RankRules and Dibs.RankRules.GetRulesForSeason and Dibs.RankRules.GetRulesForSeason(season and season.id or Dibs.GetCurrentSeasonId()) or {}
  local list = {}
  for _, rule in pairs(rules) do
    table.insert(list, rule)
  end
  table.sort(list, function(a, b)
    return (a.rankIndex or 0) < (b.rankIndex or 0)
  end)

  if #list == 0 then
    list = {
      { rankIndex = 0, allocation = 1 },
      { rankIndex = 1, allocation = 1 },
    }
  end

  for i, row in ipairs(frame.rankRows or {}) do
    local source = list[i]
    if source then
      row.rankIndex = tonumber(source.rankIndex) or 0
      row.allocation = tonumber(source.allocation) or 0
      if row.Show then
        row:Show()
      end
      refreshRankRowVisual(row)
    elseif row.Hide then
      row:Hide()
    end
  end
end

function Dibs.OfficerUI.GetLedgerOverview()
  if not canViewOfficerData() then
    return { count = 0, transactions = {}, isOfficer = false, hidden = true }
  end
  local transactions = Dibs.Ledger and Dibs.Ledger.GetAllTransactions() or {}
  return {
    count = #transactions,
    transactions = transactions,
    isOfficer = Dibs.Permissions and Dibs.Permissions.IsOfficer() or false,
  }
end

function Dibs.OfficerUI.BuildLedgerDetails(seasonId)
  if not canViewOfficerData() then
    return { players = {}, actions = {}, transactionCount = 0, hiddenTransactionCount = 0, hidden = true }
  end
  local allTransactions = Dibs.Ledger and Dibs.Ledger.GetTransactions and Dibs.Ledger.GetTransactions(seasonId) or {}
  local memberNames = getCurrentGuildMemberNames()
  local transactions = {}
  local hiddenTransactionCount = 0
  for _, tx in ipairs(allTransactions) do
    local playerName = getCurrentGuildMemberName(memberNames, tx.playerName or tx.playerKey or tx.playerId)
    if playerName then
      table.insert(transactions, { transaction = tx, playerName = playerName })
    else
      hiddenTransactionCount = hiddenTransactionCount + 1
    end
  end
  local players = {}

  for _, entry in ipairs(transactions) do
    local tx = entry.transaction
    local playerName = entry.playerName
    local playerKey = string.lower(playerName)
    if not players[playerKey] then
      local rankInfo = Dibs.RankRules and Dibs.RankRules.GetPlayerRankInfo and Dibs.RankRules.GetPlayerRankInfo(playerName) or {}
      local allocation = Dibs.RankRules and Dibs.RankRules.GetAllocation and Dibs.RankRules.GetAllocation(seasonId, rankInfo.rankIndex) or 0
      players[playerKey] = {
        name = playerName,
        balance = tonumber(allocation) or 0,
        count = 0,
      }
    end
    players[playerKey].count = players[playerKey].count + 1
    if tx.type ~= "SEASON_ALLOCATION" then
      players[playerKey].balance = players[playerKey].balance + (tonumber(tx.amount or tx.quantityDelta) or 0)
    end
  end

  local playerLines = {}
  for _, player in pairs(players) do
    table.insert(playerLines, player.name .. " | " .. tostring(player.balance) .. " dibs | " .. tostring(player.count) .. " actions")
  end
  table.sort(playerLines)

  table.sort(transactions, function(a, b)
    local first = a.transaction
    local second = b.transaction
    return (first.createdAt or first.timestamp or 0) > (second.createdAt or second.timestamp or 0)
  end)
  local actionLines = {}
  for index = 1, #transactions do
    local entry = transactions[index]
    local tx = entry.transaction
    local amount = tonumber(tx.amount or tx.quantityDelta) or 0
    local sign = amount >= 0 and "+" or ""
    table.insert(actionLines, formatHistoryDate(tx.createdAt or tx.timestamp) .. " | " .. entry.playerName .. " | " .. tostring(tx.type or tx.actionType or "UNKNOWN") .. " | " .. sign .. tostring(amount) .. " | " .. tostring(tx.reason or ""))
  end

  return {
    players = playerLines,
    actions = actionLines,
    transactionCount = #transactions,
    hiddenTransactionCount = hiddenTransactionCount,
  }
end

function Dibs.OfficerUI.BuildPreDibDetails(seasonId)
  if not canViewOfficerData() then
    return { requests = {}, activeRequestCount = 0, hiddenRequestCount = 0, hidden = true }
  end
  local memberNames = getCurrentGuildMemberNames()
  local lines = {}
  local hiddenRequestCount = 0
  local requests = Dibs.PreDibs and Dibs.PreDibs.GetHistory and Dibs.PreDibs.GetHistory() or {}
  local activeRequestCount = 0

  for _, request in ipairs(requests) do
    local isActive = request.status == "pending" or request.status == "confirmed"
    if request.seasonId == seasonId then
      local playerName = getCurrentGuildMemberName(memberNames, request.playerName)
      if playerName then
        if isActive then
          activeRequestCount = activeRequestCount + 1
        end
        table.insert(lines, {
          createdAt = request.createdAt or 0,
          text = formatHistoryDate(request.createdAt) .. " | " .. playerName .. " | " .. tostring(request.status) .. " | " .. tostring(request.itemName or ("Item " .. tostring(request.itemID or "?"))) .. " | " .. tostring(request.difficulty or "UNKNOWN") .. " | " .. tostring(request.modeAtCreation or "WILD_OPEN") .. " | " .. tostring(request.delivery and request.delivery.state or "PENDING"),
        })
      else
        hiddenRequestCount = hiddenRequestCount + 1
      end
    end
  end

  local acquisitions = Dibs.PreDibs and Dibs.PreDibs.GetAcquisitions and Dibs.PreDibs.GetAcquisitions() or {}
  for _, record in ipairs(acquisitions) do
    if record.seasonId == nil or record.seasonId == seasonId then
      local playerName = getCurrentGuildMemberName(memberNames, record.playerName)
      if playerName then
        table.insert(lines, {
          createdAt = record.acquiredAt or 0,
          text = formatHistoryDate(record.acquiredAt) .. " | " .. playerName .. " | Acquired | Item " .. tostring(record.itemID) .. " | " .. tostring(record.difficulty or "UNKNOWN") .. " | " .. tostring(record.source or "VAULT"),
        })
      else
        hiddenRequestCount = hiddenRequestCount + 1
      end
    end
  end

  table.sort(lines, function(a, b)
    return a.createdAt > b.createdAt
  end)

  local result = {}
  for _, line in ipairs(lines) do
    table.insert(result, line.text)
  end
  return { requests = result, activeRequestCount = activeRequestCount, hiddenRequestCount = hiddenRequestCount }
end

function Dibs.OfficerUI.GetPagedView(view, seasonId, page, pageSize, query)
  if not canViewOfficerData() then
    return emptyOfficerPage(view, query)
  end
  local selectedView = view == "actions" and "actions" or (view == "predibs" and "predibs" or "players")
  local ledger = Dibs.OfficerUI.BuildLedgerDetails(seasonId)
  local preDibs = Dibs.OfficerUI.BuildPreDibDetails(seasonId)
  local lines = selectedView == "actions" and ledger.actions
    or (selectedView == "predibs" and preDibs.requests or ledger.players)
  local emptyText = selectedView == "actions" and "No history for this season."
    or (selectedView == "predibs" and "No pre-Dibs for this season." or "No player activity for this season.")
  local title = selectedView == "actions" and "Actions"
    or (selectedView == "predibs" and "Pre-Dibs" or "Players")
  local needle = string.lower(tostring(query or ""))
  if needle ~= "" then
    local filtered = {}
    for _, line in ipairs(lines) do
      if string.find(string.lower(line), needle, 1, true) then
        table.insert(filtered, line)
      end
    end
    lines = filtered
  end
  local size = math.max(1, tonumber(pageSize) or 8)
  local totalPages = math.max(1, math.ceil(#lines / size))
  local currentPage = math.max(1, math.min(tonumber(page) or 1, totalPages))
  local first = ((currentPage - 1) * size) + 1
  local visible = {}
  for index = first, math.min(first + size - 1, #lines) do
    table.insert(visible, lines[index])
  end
  if #visible == 0 then
    visible[1] = emptyText
  end

  return {
    title = title,
    lines = visible,
    page = currentPage,
    totalPages = totalPages,
    totalCount = #lines,
    query = needle,
    hiddenCount = selectedView == "predibs" and preDibs.hiddenRequestCount or ledger.hiddenTransactionCount,
  }
end

function Dibs.OfficerUI.BuildSeasonStatistics(seasonId)
  if not canViewOfficerData() then
    return {
      players = 0,
      transactions = 0,
      granted = 0,
      used = 0,
      awards = 0,
      corrections = 0,
      activePreDibs = 0,
      hidden = true,
    }
  end
  local memberNames = getCurrentGuildMemberNames()
  local transactions = Dibs.Ledger and Dibs.Ledger.GetTransactions and Dibs.Ledger.GetTransactions(seasonId) or {}
  local players = {}
  local granted, used, corrections, awards = 0, 0, 0, 0

  for _, tx in ipairs(transactions) do
    local playerName = getCurrentGuildMemberName(memberNames, tx.playerName or tx.playerKey or tx.playerId)
    if playerName then
      players[string.lower(playerName)] = true
      local amount = tonumber(tx.amount or tx.quantityDelta) or 0
      if tx.type == "DIB_GRANTED" then
        granted = granted + amount
      elseif tx.type == "DIB_USED" then
        used = used + math.abs(amount)
        awards = awards + 1
      elseif tx.type == "DIB_REFUNDED" or tx.type == "DIB_REVOKED" or tx.type == "DIB_ADMIN_ADJUSTMENT" then
        corrections = corrections + 1
      end
    end
  end

  local activePreDibs = Dibs.OfficerUI.BuildPreDibDetails(seasonId)
  local playerCount = 0
  for _ in pairs(players) do playerCount = playerCount + 1 end
  return {
    players = playerCount,
    transactions = #transactions,
    granted = granted,
    used = used,
    awards = awards,
    corrections = corrections,
    activePreDibs = activePreDibs.activeRequestCount,
  }
end

function Dibs.OfficerUI.BuildDashboardDetails(season)
  if not canViewOfficerData() then
    return { "Officer access required." }
  end
  local seasonId = season and season.id or nil
  local statistics = Dibs.OfficerUI.BuildSeasonStatistics(seasonId)
  local actions = Dibs.OfficerUI.GetPagedView("actions", seasonId, 1, 1)
  return {
    "Season: " .. tostring(season and season.name or "None"),
    "Pre-Dib mode: " .. tostring(Dibs.PreDibs and Dibs.PreDibs.GetModePolicy and Dibs.PreDibs.GetModePolicy(seasonId).mode or "WILD_OPEN"),
    "Players active: " .. tostring(statistics.players),
    "Active pre-Dibs: " .. tostring(statistics.activePreDibs),
    "Actions this season: " .. tostring(statistics.transactions),
    "Latest action: " .. tostring(actions.lines[1] or "None"),
  }
end

function Dibs.OfficerUI.SetPreDibMode(seasonId, mode)
  return Dibs.ProtectedActions.Execute("predib.mode.set", nil, { seasonId = seasonId, mode = mode, source = "officer-ui" })
end

function Dibs.OfficerUI.GetRankChangeDiagnostics()
  if not canViewOfficerData() then
    return { playersWithRankTransitions = 0, totalPlayersInLedger = 0, hidden = true }
  end
  local transactions = Dibs.Ledger and Dibs.Ledger.GetAllTransactions() or {}
  local playerRanks = {}

  for _, tx in ipairs(transactions) do
    local player = string.lower(tostring(tx.playerName or tx.playerId or tx.playerGuid or "unknown"))
    local rank = tonumber(tx.playerRankIndex or tx.playerRank)
    if rank ~= nil then
      playerRanks[player] = playerRanks[player] or {}
      playerRanks[player][rank] = true
    end
  end

  local changingPlayers = 0
  local totalPlayers = 0
  for _, ranks in pairs(playerRanks) do
    totalPlayers = totalPlayers + 1
    local count = 0
    for _ in pairs(ranks) do
      count = count + 1
    end
    if count > 1 then
      changingPlayers = changingPlayers + 1
    end
  end

  return {
    playersWithRankTransitions = changingPlayers,
    totalPlayersInLedger = totalPlayers,
  }
end

function Dibs.OfficerUI.BuildStatusText(selectedSeason)
  if not canViewOfficerData() then
    return "Officer access required."
  end
  local season = selectedSeason or (Dibs.Seasons and Dibs.Seasons.GetCurrent() or nil)
  local seasons = Dibs.Seasons and Dibs.Seasons.List() or {}
  local overview = Dibs.OfficerUI.GetLedgerOverview()
  local rankDiagnostics = Dibs.OfficerUI.GetRankChangeDiagnostics()
  local permissions = Dibs.GetDB().permissions or {}
  local adminCount = 0
  for _ in pairs(permissions.activeStandaloneAdmins or {}) do
    adminCount = adminCount + 1
  end

  return "Season selected: " .. tostring(season and season.name or "None") .. "\n" ..
    "Seasons: " .. tostring(#seasons) .. " | Ledger transactions (all seasons): " .. tostring(overview.count) .. "\n" ..
    "Rank transitions: " .. tostring(rankDiagnostics.playersWithRankTransitions) .. "/" .. tostring(rankDiagnostics.totalPlayersInLedger) .. " players\n" ..
    "Standalone admins: " .. tostring(adminCount) .. " (events: " .. tostring(#(permissions.adminEvents or {})) .. ")\n" ..
    "Role: " .. tostring(Dibs.Permissions and Dibs.Permissions.GetRole() or "player") .. "\n" ..
    "RCLootCouncil: " .. tostring(Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetAvailability and Dibs.RCLootCouncil.GetAvailability() or "absent")
end

local function splitPipeLine(line, expected)
  local cells = {}
  for cell in (tostring(line or "") .. "|"):gmatch("(.-)|") do
    table.insert(cells, cell:match("^%s*(.-)%s*$"))
  end
  while #cells < (expected or 1) do table.insert(cells, "") end
  return cells
end

local function createAceWindow()
  local shell = Dibs.AceGUI.CreateWindow("RCLootCouncil - Dibs | Officer", 980, 760, { "CENTER", 280, 0 })
  if not shell then return nil end
  local frame = shell.frame
  if frame and frame.SetUserPlaced then frame:SetUserPlaced(true) end
  frame.dibsAceGUIShell = shell
  frame.activeTab = "overview"
  frame.ledgerPage = 1
  frame.rankRows = {}
  frame.rankDrafts = {}
  frame.rankRowCount = 3
  frame.inputBoundSeasonId = nil

  frame.SetStatus = function(self, message)
    self.statusMessage = tostring(message or "")
    Dibs.Message(self.statusMessage)
  end

  local function selectSeason(offset)
    local seasons = getSeasonList()
    if #seasons == 0 then return end
    local index = 1
    for i, season in ipairs(seasons) do
      if season.id == frame.selectedSeasonId then index = i break end
    end
    index = ((index - 1 + offset) % #seasons) + 1
    frame.selectedSeasonId = seasons[index].id
    frame.inputBoundSeasonId = nil
    frame:Refresh()
  end

  local tabs = Dibs.AceGUI.AddTree(shell, OFFICER_NAV_TREE, function(value)
    frame.activeTab, frame.ledgerPage = normalizeOfficerTab(value), 1
    frame:Refresh()
  end, 190)
  frame.aceTabs = tabs
  frame.SelectTab = function(tab)
    local normalized = normalizeOfficerTab(tab)
    if not Dibs.AceGUI.SelectTree(tabs, normalized) then
      frame.activeTab, frame.ledgerPage = normalized, 1
      frame:Refresh()
    end
  end

  frame.Refresh = function(self)
    Dibs.AceGUI.Clear(tabs)
    Dibs.AceGUI.AddHeading(shell, tabs, "RCLootCouncil - Dibs options", "Officer controls use the same shared options as RCLootCouncil.")
    local seasons = getSeasonList()
    local current = getSelectedSeason(self)
    if not current and #seasons > 0 then
      current = seasons[#seasons]
      self.selectedSeasonId = current.id
    end
    local currentId = current and current.id or nil

    -- Render the canonical Officer options directly from the shared
    -- AceConfig table.  This keeps Seasons, Rank Rules, Settings, Pre-Dibs,
    -- Announcements, Developer, RCLootCouncil and Debug in lockstep with the
    -- options visible in RCLootCouncil's own panel.
    local optionGroup
    local optionsTable
    if Dibs.RCOptions and Dibs.RCOptions.GetOptionsTable then
      optionsTable = Dibs.RCOptions.GetOptionsTable()
      local groups = optionsTable and optionsTable.args and optionsTable.args.dibsSettings and optionsTable.args.dibsSettings.args
      if groups then
        optionGroup = self.activeTab == "overview" and groups.overview
          -- Review Requests is a custom OfficerUI page.  The options table
          -- also exposes a small entry point with the same key, but rendering
          -- that AceConfig group here hides the actual queue and its actions.
          or (self.activeTab ~= "disputes" and groups.officer and groups.officer.args and groups.officer.args[self.activeTab])
      end
    end
    if optionGroup and Dibs.AceGUI.RenderOptionsGroup then
      self.lootTypeControls = self.activeTab == "integration" and {} or nil
      local controlMap = self.lootTypeControls
      Dibs.AceGUI.RenderOptionsGroup(shell, tabs, optionGroup, {
        controlMap = controlMap,
        onChanged = function()
          self:Refresh()
        end,
      })
      if self.activeTab == "overview" then
        local officerRoot = optionsTable and optionsTable.args and optionsTable.args.dibsSettings
          and optionsTable.args.dibsSettings.args and optionsTable.args.dibsSettings.args.officer
        local openLogs = officerRoot and officerRoot.args and officerRoot.args.openLogs
        if Dibs.RCOptions and Dibs.RCOptions.Open then
          Dibs.AceGUI.AddButton(shell, tabs, "Open full options", function() Dibs.RCOptions.Open() end, 180)
        end
        if openLogs then
          Dibs.AceGUI.AddHeader(shell, tabs, "Officer management", "Open the detailed player, Pre-Dib and history logs.")
          Dibs.AceGUI.AddButton(shell, tabs, tostring(type(openLogs.name) == "function" and openLogs.name() or openLogs.name or "Open logs window"), function()
            if type(openLogs.func) == "function" then pcall(openLogs.func) end
          end, 220)
        end
      end
      if self.activeTab == "integration" and controlMap then
        self.enableLootTypes = controlMap.enable
        self.defaultLootTypes = controlMap.disable
      end
      return
    end

    if self.activeTab == "disputes" then
      -- The queue can contain evidence, controls and a full audit timeline;
      -- keep it inside its own scrollable content area instead of letting the
      -- TreeGroup clip the resolution actions below the fold.
      local tabs = Dibs.AceGUI.AddScrollableList(shell, tabs, 660) or tabs
      Dibs.AceGUI.AddHeading(shell, tabs, "RCLootCouncil - Dibs options", "Officer review and correction center.")
      Dibs.AceGUI.AddHeader(shell, tabs, "Officer review requests", "Review player reports with the attached Dibs and RCLootCouncil evidence. Every resolution records an auditable reason.")
      local statusChoices = { [""] = "All statuses" }
      for key, value in pairs(Dibs.Disputes and Dibs.Disputes.GetStatuses and Dibs.Disputes.GetStatuses() or {}) do
        statusChoices[value] = value
      end
      self.disputeStatusFilter = self.disputeStatusFilter or ""
      self.disputeQuery = self.disputeQuery or ""
      local filterSection = Dibs.AceGUI.AddSection(shell, tabs, "Queue filters", "Filter by lifecycle status or search the player, item and report note.")
      local filter = Dibs.AceGUI.AddDropdown(shell, filterSection, "Status", statusChoices, function(value)
        self.disputeStatusFilter = value or ""
        self.disputePage = 1
        self:Refresh()
      end, 190)
      Dibs.AceGUI.SetValue(filter, self.disputeStatusFilter)
      self.disputeSearchBox = Dibs.AceGUI.AddEditBox(shell, filterSection, "Search", function(value)
        self.disputeQuery = value or ""
        self.disputePage = 1
        self:Refresh()
      end, 300)
      setControlText(self.disputeSearchBox, self.disputeQuery)
      Dibs.AceGUI.AddButton(shell, filterSection, "Clear", function()
        self.disputeQuery, self.disputeStatusFilter, self.disputeSelectedId = "", "", nil
        self:Refresh()
      end, 70)

      local requests, queueReason = {}, nil
      if Dibs.Disputes and Dibs.Disputes.ListForOfficer then
        requests, queueReason = Dibs.Disputes.ListForOfficer(nil, {
          status = self.disputeStatusFilter ~= "" and self.disputeStatusFilter or nil,
          query = self.disputeQuery,
        })
      end
      if queueReason then
        Dibs.AceGUI.AddLabel(shell, tabs, "Officer access required: " .. tostring(queueReason), true)
        return
      end
      local pageSize = 10
      local totalPages = math.max(1, math.ceil(#(requests or {}) / pageSize))
      self.disputePage = math.min(math.max(1, self.disputePage or 1), totalPages)
      local firstRequest = ((self.disputePage - 1) * pageSize) + 1
      local lastRequest = math.min(#(requests or {}), self.disputePage * pageSize)
      local requestRows = {}
      for index = firstRequest, lastRequest do
        local request = requests[index]
        local evidence = request.evidence and request.evidence[1] or {}
        requestRows[#requestRows + 1] = {
          tostring(request.requestId),
          tostring(request.player and request.player.name or "Unknown"),
          disputeStatusText(request),
          tostring(evidence.item or "Unavailable"),
          tostring(request.note or ""),
          "",
          request = request,
        }
      end
      if #requestRows == 0 then requestRows[1] = { "No requests", "", "", "", "", "" } end
      Dibs.AceGUI.AddTable(shell, tabs, {
        { title = "Request", width = 110, tooltip = "Player review request identifier." },
        { title = "Player", width = 110, tooltip = "Character that submitted the request." },
        { title = "Status", width = 130, tooltip = "Current review status." },
        { title = "Item", width = 150, tooltip = "Attached item when available." },
        { title = "Note", width = 180, tooltip = "Player note." },
        { title = "Action", width = 75, tooltip = "Open request details." },
      }, requestRows, 270, function(row)
        if not row.request then return nil end
        return {
          text = "Open",
          callback = function()
            self.disputeSelectedId = row.request.requestId
            self:Refresh()
          end,
        }
      end)
      local previousPage = Dibs.AceGUI.AddButton(shell, tabs, "Previous", function()
        self.disputePage = math.max(1, self.disputePage - 1)
        self:Refresh()
      end, 90)
      local pageLabel = Dibs.AceGUI.AddLabel(shell, tabs, "Page " .. tostring(self.disputePage) .. "/" .. tostring(totalPages))
      local nextPage = Dibs.AceGUI.AddButton(shell, tabs, "Next", function()
        self.disputePage = math.min(totalPages, self.disputePage + 1)
        self:Refresh()
      end, 70)
      Dibs.AceGUI.SetDisabled(previousPage, self.disputePage <= 1)
      Dibs.AceGUI.SetDisabled(nextPage, self.disputePage >= totalPages)
      Dibs.AceGUI.AddTooltip(pageLabel, "Page", "Current review queue page.")

      if self.disputeSelectedId then
        local selected = Dibs.Disputes.GetRequest(self.disputeSelectedId, nil)
        if selected then
          local evidence = selected.evidence and selected.evidence[1] or {}
          local detailSection = Dibs.AceGUI.AddSection(shell, tabs, "Selected request", disputeStatusText(selected))
          local unavailable = evidence.unavailableFields and table.concat(evidence.unavailableFields, ", ") or "none"
          Dibs.AceGUI.AddLabel(shell, detailSection, "Player: " .. tostring(selected.player and selected.player.name or "Unknown") ..
            "\nCategory: " .. tostring(selected.categoryLabel or selected.category) ..
            "\nStatus: " .. tostring(selected.status) ..
            "\nNote: " .. tostring(selected.note or "") ..
            "\nEvidence source: " .. tostring(evidence.source or "unknown") ..
            "\nIntegration: " .. tostring(evidence.integrationStatus or "standalone/unavailable") ..
            " (" .. tostring(evidence.integrationReason or "") .. ")" ..
            "\nItem: " .. tostring(evidence.item or "Unavailable") ..
            "\nTransaction: " .. tostring(evidence.transactionRef or "Unavailable") ..
            "\nAward/history reference: " .. tostring(evidence.awardRef or evidence.historyRef or "Unavailable") ..
            "\nUnavailable fields: " .. unavailable, true)

          local resolutionSection = Dibs.AceGUI.AddSection(shell, tabs, "Resolution", "Every decision requires a clear reason. Ledger-changing actions also require explicit confirmation.")
          self.disputeReason = self.disputeReason or ""
          local reason = Dibs.AceGUI.AddEditBox(shell, resolutionSection, "Reason or question", function(value) self.disputeReason = value or "" end, 540)
          setControlText(reason, self.disputeReason)
          local amount = Dibs.AceGUI.AddEditBox(shell, resolutionSection, "Balance change (optional)", function(value) self.disputeAmount = value or "" end, 180)
          setControlText(amount, self.disputeAmount or "")
          self.disputeConfirmed = self.disputeConfirmed == true
          local confirmation = Dibs.AceGUI.AddCheckBox(shell, resolutionSection, "Confirm ledger or target correction", self.disputeConfirmed, function(value) self.disputeConfirmed = value == true end, 300)

          local function resolve(action, options)
            options = options or {}
            options.reason = self.disputeReason
            local result, resolveReason = Dibs.Disputes.Resolve(self.disputeSelectedId, action, options, nil)
            self.disputeStatusMessage = result and ("Request updated: " .. tostring(result.request and result.request.status or "done"))
              or ("Unable to update request: " .. tostring(resolveReason or "unknown error"))
            if result then
              self.disputeReason, self.disputeAmount = "", ""
              self.disputeCorrectPlayer, self.disputeCorrectItem = "", ""
              self.disputeConfirmed = false
            end
            self:Refresh()
          end

          local targetButton
          if selected.category == "wrong_item_player" then
            local targetSection = Dibs.AceGUI.AddSection(shell, tabs, "Correct item or player", "Use this for a wrong-item or wrong-player report. Leave a field blank to keep its current value. A linked ledger entry is moved to the corrected player with two auditable entries.")
            Dibs.AceGUI.AddLabel(shell, targetSection, "Current player: " .. tostring(evidence.winner or selected.player and selected.player.name or "Unavailable") ..
              "\nCurrent item: " .. tostring(evidence.item or evidence.itemID or "Unavailable"), true)
            self.disputeCorrectPlayer = self.disputeCorrectPlayer or ""
            self.disputeCorrectItem = self.disputeCorrectItem or ""
            local correctedPlayer = Dibs.AceGUI.AddEditBox(shell, targetSection, "Correct player (optional)", function(value) self.disputeCorrectPlayer = value or "" end, 250)
            setControlText(correctedPlayer, self.disputeCorrectPlayer)
            local correctedItem = Dibs.AceGUI.AddEditBox(shell, targetSection, "Correct item ID or link (optional)", function(value) self.disputeCorrectItem = value or "" end, 300)
            setControlText(correctedItem, self.disputeCorrectItem)
            targetButton = Dibs.AceGUI.AddButton(shell, targetSection, "Apply target correction", function()
              resolve("correct_target", {
                confirmed = self.disputeConfirmed,
                playerName = trimText(getControlText(correctedPlayer)),
                itemLink = trimText(getControlText(correctedItem)),
              })
            end, 180)
          end

          local actionGroup = Dibs.AceGUI.AddInlineGroup(shell, resolutionSection)
          local reviewButton = Dibs.AceGUI.AddButton(shell, actionGroup, "Start review", function() resolve("under_review") end, 110)
          local questionButton = Dibs.AceGUI.AddButton(shell, actionGroup, "Ask for information", function() resolve("ask_information", { question = self.disputeReason }) end, 150)
          local noCorrection = Dibs.AceGUI.AddButton(shell, actionGroup, "Resolve: no correction", function() resolve("no_correction") end, 155)
          local duplicate = Dibs.AceGUI.AddButton(shell, actionGroup, "Mark duplicate", function() resolve("duplicate", { duplicateOf = self.disputeDuplicateId }) end, 110)
          local reject = Dibs.AceGUI.AddButton(shell, actionGroup, "Reject", function() resolve("reject") end, 80)
          local correction = Dibs.AceGUI.AddButton(shell, actionGroup, "Correct balance", function()
            local options = { confirmed = self.disputeConfirmed }
            local parsed = tonumber(trimText(self.disputeAmount))
            if parsed then options.amount = parsed end
            resolve("correct_balance", options)
          end, 120)
          local refund = Dibs.AceGUI.AddButton(shell, actionGroup, "Refund Dib", function()
            local options = { confirmed = self.disputeConfirmed }
            local parsed = tonumber(trimText(self.disputeAmount))
            if parsed then options.amount = parsed end
            resolve("refund", options)
          end, 95)
          local revoke = Dibs.AceGUI.AddButton(shell, actionGroup, "Revoke Dib", function()
            local options = { confirmed = self.disputeConfirmed }
            local parsed = tonumber(trimText(self.disputeAmount))
            if parsed then options.amount = parsed end
            resolve("revoke", options)
          end, 95)
          local import = Dibs.AceGUI.AddButton(shell, actionGroup, "Import historical", function()
            local options = { confirmed = self.disputeConfirmed }
            local parsed = tonumber(trimText(self.disputeAmount))
            if parsed then options.amount = parsed end
            resolve("historical_import", options)
          end, 125)
          local adjustment = Dibs.AceGUI.AddButton(shell, actionGroup, "Admin adjustment", function()
            local options = { confirmed = self.disputeConfirmed }
            local parsed = tonumber(trimText(self.disputeAmount))
            if parsed then options.amount = parsed end
            resolve("adjustment", options)
          end, 120)
          local reopen = Dibs.AceGUI.AddButton(shell, actionGroup, "Reopen", function() resolve("reopen") end, 80)
          local terminal = selected.status == "Resolved" or selected.status == "Rejected"
          Dibs.AceGUI.SetDisabled(reviewButton, terminal)
          Dibs.AceGUI.SetDisabled(questionButton, terminal)
          Dibs.AceGUI.SetDisabled(noCorrection, terminal)
          Dibs.AceGUI.SetDisabled(duplicate, terminal)
          Dibs.AceGUI.SetDisabled(reject, terminal)
          Dibs.AceGUI.SetDisabled(correction, terminal)
          Dibs.AceGUI.SetDisabled(refund, terminal)
          Dibs.AceGUI.SetDisabled(revoke, terminal)
          Dibs.AceGUI.SetDisabled(import, terminal)
          Dibs.AceGUI.SetDisabled(adjustment, terminal)
          Dibs.AceGUI.SetDisabled(targetButton, terminal)
          Dibs.AceGUI.SetDisabled(reopen, not terminal)
          Dibs.AceGUI.AddLabel(shell, resolutionSection, self.disputeStatusMessage or "Choose an action. Ledger-changing corrections require a reason and explicit confirmation.", true)

          local timelineRows = {}
          for _, event in ipairs(Dibs.Disputes.GetTimeline(self.disputeSelectedId, nil) or {}) do
            timelineRows[#timelineRows + 1] = { tostring(event.timestamp or ""), tostring(event.action or ""), tostring(event.actorName or ""), tostring(event.reason or "") }
          end
          if #timelineRows > 0 then
            Dibs.AceGUI.AddTable(shell, tabs, {
              { title = "Time", width = 130, tooltip = "Audit event time." },
              { title = "Action", width = 150, tooltip = "Recorded action." },
              { title = "Actor", width = 140, tooltip = "Actor identity is officer-only." },
              { title = "Reason", width = 300, tooltip = "Recorded justification." },
            }, timelineRows, 190)
          end
        end
      end
      return
    end

    if self.activeTab == "announcements" then
      local templates = Dibs.PreDibs.GetAnnouncementTemplates()
      local announcementSettings = Dibs.PreDibs.GetAnnouncementSettings()
      local updatePreview = function()
        if self.announcementPreview then
          local sample = {
            playerName = Dibs.GetPlayerName and Dibs.GetPlayerName() or "Player-Realm",
            itemName = "Example item",
            itemID = 12345,
            difficulty = "Mythic",
            modeAtCreation = "WILD_OPEN",
            status = "confirmed",
            seasonId = currentId or "Current season",
            requestId = "example-request",
            source = "Officer UI preview",
          }
          local preDib = Dibs.PreDibs.FormatAnnouncement(getControlText(self.preDibTemplateInput), sample)
          local reminder = Dibs.PreDibs.FormatAnnouncement(getControlText(self.reminderTemplateInput), { source = "Raid reminder" })
          self.announcementPreview:SetText("Pre-Dib: " .. preDib .. "\nReminder: " .. reminder)
        end
      end
      Dibs.AceGUI.AddLabel(shell, tabs, "Announcement templates and facts", true)
      Dibs.AceGUI.AddLabel(shell, tabs, "Variables: %player %item %itemID %difficulty %mode %status %season %date %time %requestID %source %channel", true)
      self.preDibTemplateInput = Dibs.AceGUI.AddEditBox(shell, tabs, "Pre-Dib announcement", function(value)
        local currentTemplates = Dibs.PreDibs.GetAnnouncementTemplates()
        Dibs.PreDibs.SetAnnouncementTemplates(value, currentTemplates.reminder)
        updatePreview()
      end, 520)
      setControlText(self.preDibTemplateInput, templates.preDib)
      self.reminderTemplateInput = Dibs.AceGUI.AddEditBox(shell, tabs, "Raid reminder", function(value)
        local currentTemplates = Dibs.PreDibs.GetAnnouncementTemplates()
        Dibs.PreDibs.SetAnnouncementTemplates(currentTemplates.preDib, value)
        updatePreview()
      end, 520)
      setControlText(self.reminderTemplateInput, templates.reminder)
      self.publicAnnouncementChannel = Dibs.AceGUI.AddDropdown(shell, tabs, "Public channel", ANNOUNCEMENT_CHANNEL_VALUES, function(value)
        local announcementState = Dibs.PreDibs.GetAnnouncementSettings()
        Dibs.PreDibs.SetAnnouncementChannels(value, announcementState.officerChannel)
      end, 180)
      Dibs.AceGUI.SetValue(self.publicAnnouncementChannel, announcementSettings.publicChannel)
      self.officerAnnouncementChannel = Dibs.AceGUI.AddDropdown(shell, tabs, "Officer channel", ANNOUNCEMENT_CHANNEL_VALUES, function(value)
        local announcementState = Dibs.PreDibs.GetAnnouncementSettings()
        Dibs.PreDibs.SetAnnouncementChannels(announcementState.publicChannel, value)
      end, 180)
      Dibs.AceGUI.SetValue(self.officerAnnouncementChannel, announcementSettings.officerChannel)
      Dibs.AceGUI.AddButton(shell, tabs, "Test public channel", function()
        local settings = Dibs.PreDibs.GetAnnouncementSettings()
        local ok, reason = Dibs.PreDibs.SendTestAnnouncement(settings.publicChannel, "Public")
        Dibs.Message(ok and "Public announcement test sent." or ((reason == "RAID_DIBS_NOT_JOINED" or reason == "RAID_DIBS_UNAVAILABLE") and "Raid Dibs is not joined on this character." or ("Public announcement channel is unavailable (" .. tostring(reason) .. ").")))
      end, 150)
      Dibs.AceGUI.AddButton(shell, tabs, "Test officer channel", function()
        local settings = Dibs.PreDibs.GetAnnouncementSettings()
        local ok, reason = Dibs.PreDibs.SendTestAnnouncement(settings.officerChannel, "Officer")
        Dibs.Message(ok and "Officer announcement test sent." or ((reason == "RAID_DIBS_NOT_JOINED" or reason == "RAID_DIBS_UNAVAILABLE") and "Raid Dibs is not joined on this character." or ("Officer announcement channel is unavailable (" .. tostring(reason) .. ").")))
      end, 150)
      Dibs.AceGUI.AddButton(shell, tabs, "Reset templates", function()
        Dibs.PreDibs.SetAnnouncementTemplates(DEFAULT_PREDIB_TEMPLATE, DEFAULT_REMINDER_TEMPLATE)
        self:Refresh()
      end, 120)
      self.announcementPreview = Dibs.AceGUI.AddLabel(shell, tabs, "", true)
      updatePreview()
      return
    end

    if self.activeTab == "lootTypes" then
      local options = Dibs.RCOptions.GetLootTypeOptions()
      local policy = options.types
      Dibs.AceGUI.AddHeader(shell, tabs, "Dib loot types", "Shared with RCLootCouncil - Dibs options.")
      local list = Dibs.AceGUI.AddScrollableList(shell, tabs, 380)
      local values, keys = policy.values(), {}
      for key in pairs(values) do keys[#keys + 1] = key end
      table.sort(keys, function(a, b) return values[a] < values[b] end)
      self.lootTypeControls = {}
      for _, key in ipairs(keys) do
        local checkbox = Dibs.AceGUI.Create(shell, "CheckBox", list)
        checkbox:SetLabel(values[key])
        checkbox:SetFullWidth(true)
        checkbox:SetValue(policy.get(nil, key))
        checkbox:SetCallback("OnValueChanged", function(_, _, value)
          policy.set(nil, key, value)
        end)
        self.lootTypeControls[key] = checkbox
      end
      self.enableLootTypes = Dibs.AceGUI.AddButton(shell, tabs, options.enable.name, function()
        options.enable.func()
        self:Refresh()
      end, 200)
      self.defaultLootTypes = Dibs.AceGUI.AddButton(shell, tabs, options.disable.name, function()
        options.disable.func()
        self:Refresh()
      end, 200)
      return
    end
    if self.activeTab == "debug" then
      Dibs.AceGUI.AddHeader(shell, tabs, "Debug report", "Diagnostic visibility and runtime state.")
      Dibs.AceGUI.AddLabel(shell, tabs, Dibs.BuildDebugReport(), true)
      for _, entry in ipairs({ { "All", "all" }, { "Announcements", "announce" }, { "Sync", "sync" }, { "UI", "ui" }, { "Adventure Guide", "encounter_journal" } }) do
        local key, label = entry[2], entry[1]
        local debugLevel = tonumber(Dibs.GetDebugLevels()[key]) or tonumber(Dibs.GetDebugLevels().all) or 1
        local control = Dibs.AceGUI.AddDropdown(shell, tabs, label .. " level", { [0]="0 - hidden", [1]="1 - normal", [2]="2", [3]="3", [4]="4", [5]="5 - maximum" }, function(value)
          Dibs.SetDebugLevel(key, tonumber(value) or 0); self:Refresh()
        end, 220)
        Dibs.AceGUI.SetValue(control, debugLevel)
      end
      Dibs.AceGUI.AddButton(shell, tabs, "Copy report to chat", function() Dibs.Message(Dibs.BuildDebugReport()) end, 180)
      return
    end

    if self.activeTab == "settings" then
      local seasonValues = {}
      for _, season in ipairs(seasons) do seasonValues[season.id] = season.name end
      self.seasonDropdown = Dibs.AceGUI.AddDropdown(shell, tabs, "Selected season", seasonValues, function(value)
        self.selectedSeasonId, self.inputBoundSeasonId = value, nil
        self:Refresh()
      end, 240)
      Dibs.AceGUI.SetValue(self.seasonDropdown, currentId)
      Dibs.AceGUI.AddButton(shell, tabs, "Previous", function() selectSeason(-1) end, 80)
      Dibs.AceGUI.AddButton(shell, tabs, "Next", function() selectSeason(1) end, 60)
      Dibs.AceGUI.AddButton(shell, tabs, "Activate", function()
        local selected = getSelectedSeason(self)
        local result = selected and Dibs.ProtectedActions.Execute("season.set", nil, { seasonId = selected.id })
        self:SetStatus(result and result.ok and ("Active season: " .. selected.name) or (result and result.diagnostic) or "No season selected.")
        self:Refresh()
      end, 80)
      self.seasonLabel = Dibs.AceGUI.AddLabel(shell, tabs, "Season: " .. tostring(current and current.name or "None"), true)
      self.seasonNameInput = Dibs.AceGUI.AddEditBox(shell, tabs, "Season name", nil, 260)
      setControlText(self.seasonNameInput, current and current.name or getDefaultSeasonName())
      Dibs.AceGUI.AddButton(shell, tabs, "Create", function()
        local name = makeUniqueSeasonName(trimText(getControlText(self.seasonNameInput)))
        local result = Dibs.ProtectedActions.Execute("season.create", nil, { name = name })
        if result.ok and result.value then self.selectedSeasonId = result.value.id end
        self:SetStatus(result.ok and ("Created season: " .. tostring(result.value.name)) or result.diagnostic)
        self:Refresh()
      end, 70)
      Dibs.AceGUI.AddButton(shell, tabs, "Rename", function()
        local typed = trimText(getControlText(self.seasonNameInput))
        local duplicate = current and findSeasonByName(typed, current.id)
         local result = current and typed ~= "" and not duplicate and Dibs.ProtectedActions.Execute("season.rename", nil, { seasonId = current.id, name = typed })
         self:SetStatus(result and result.ok and result.value and ("Season renamed: " .. result.value.name) or (result and result.diagnostic) or "Unable to rename the selected season.")
        self:Refresh()
      end, 70)
      Dibs.AceGUI.AddButton(shell, tabs, "Delete", function()
         local result = current and #seasons > 1 and Dibs.ProtectedActions.Execute("season.archive", nil, { seasonId = current.id })
         if result and result.ok then self.selectedSeasonId = nil end
         self:SetStatus(result and result.ok and result.value and ("Season archived: " .. result.value.name) or (result and result.diagnostic) or "At least one season must remain.")
        self:Refresh()
      end, 70)
      self.summaryText = Dibs.AceGUI.AddLabel(shell, tabs, Dibs.OfficerUI.BuildStatusText(current), true)
      self.statusText = Dibs.AceGUI.AddLabel(shell, tabs, self.statusMessage or "Ready", true)
      Dibs.AceGUI.AddLabel(shell, tabs, "Rank allocations", true)
      local rules = Dibs.RankRules and Dibs.RankRules.GetRulesForSeason and Dibs.RankRules.GetRulesForSeason(currentId) or {}
      for index = 1, self.rankRowCount do
        local source = self.rankDrafts[index] or rules[index] or { rankIndex = index - 1, allocation = 1 }
        local row = { rankIndex = tonumber(source.rankIndex) or 0, allocation = tonumber(source.allocation) or 0 }
        self.rankDrafts[index] = row
        table.insert(self.rankRows, row)
        local ranks = {}
        for rank = 0, math.max(9, row.rankIndex) do ranks[rank] = buildRankLabel(rank) end
        row.rankDropdown = Dibs.AceGUI.AddDropdown(shell, tabs, "Rank", ranks, function(value) row.rankIndex = tonumber(value) or 0 end, 210)
        Dibs.AceGUI.SetValue(row.rankDropdown, row.rankIndex)
        row.valueText = Dibs.AceGUI.AddLabel(shell, tabs, "Dibs: " .. tostring(row.allocation))
        Dibs.AceGUI.AddButton(shell, tabs, "-", function() row.allocation = math.max(0, row.allocation - 1); self.rankDrafts[index] = row; self:Refresh() end, 28)
        Dibs.AceGUI.AddButton(shell, tabs, "+", function() row.allocation = row.allocation + 1; self.rankDrafts[index] = row; self:Refresh() end, 28)
        Dibs.AceGUI.AddButton(shell, tabs, "Set", function() applyRankRule(self, row) end, 50)
      end
      Dibs.AceGUI.AddButton(shell, tabs, "Add rank", function() self.rankRowCount = self.rankRowCount + 1; self:Refresh() end, 80)
      return
    end

    if self.activeTab == "dashboard" then
      self.ledgerTitle = Dibs.AceGUI.AddLabel(shell, tabs, "Dashboard", true)
      self.ledgerText = Dibs.AceGUI.AddLabel(shell, tabs, table.concat(Dibs.OfficerUI.BuildDashboardDetails(current), "\n"), true)
      return
    end
    if self.activeTab == "statistics" then
      local statistics = Dibs.OfficerUI.BuildSeasonStatistics(currentId)
      self.ledgerTitle = Dibs.AceGUI.AddLabel(shell, tabs, "Season statistics", true)
      self.ledgerText = Dibs.AceGUI.AddLabel(shell, tabs, "Active players: " .. statistics.players .. "\nTransactions: " .. statistics.transactions .. "\nDibs used: " .. statistics.used .. "\nActive pre-Dibs: " .. statistics.activePreDibs, true)
      return
    end
    self.searchBox = Dibs.AceGUI.AddEditBox(shell, tabs, "Search", function(value)
      self.ledgerQuery, self.ledgerPage = value, 1
      self:Refresh()
    end, 220)
    setControlText(self.searchBox, self.ledgerQuery or "")
    Dibs.AceGUI.AddButton(shell, tabs, "Clear", function() self.ledgerQuery, self.ledgerPage = "", 1; self:Refresh() end, 60)
    local view = Dibs.OfficerUI.GetPagedView(self.activeTab == "history" and "actions" or self.activeTab, currentId, self.ledgerPage, 8, self.ledgerQuery)
    self.ledgerPage = view.page
    self.ledgerTitle = Dibs.AceGUI.AddLabel(shell, tabs, view.title .. " (" .. view.totalCount .. ")", true)
    local headerText, headerTooltip
    if self.activeTab == "history" or self.activeTab == "actions" then
      headerText = "Date | Player | Action | Amount | Reason"
      headerTooltip = "Date: when the ledger entry was recorded. Player: who it affected. Action: the ledger operation. Amount: Dibs gained or spent. Reason: audit context."
    elseif self.activeTab == "predibs" then
      headerText = "Date | Player | Status | Item | Difficulty | Mode | Sync"
      headerTooltip = "Date: request time. Player: requester. Status: lifecycle state. Item: reserved loot. Difficulty: requested difficulty. Mode: Wild Open or Encounter. Sync: delivery acknowledgement."
    else
      headerText = "Player | Balance | Actions"
      headerTooltip = "Player: guild member. Balance: current Dibs allocation after ledger activity. Actions: number of ledger entries."
    end
    local expectedColumns = self.activeTab == "history" and 5 or (self.activeTab == "predibs" and 7 or 3)
    local tableRows = {}
    for _, line in ipairs(view.lines) do table.insert(tableRows, splitPipeLine(line, expectedColumns)) end
    local columns = {}
    if expectedColumns == 5 then
      columns = {
        { title = "Date", width = 145, tooltip = "When the ledger entry was recorded." },
        { title = "Player", width = 135, tooltip = "Guild member affected by the entry." },
        { title = "Action", width = 135, tooltip = "Ledger operation." },
        { title = "Amount", width = 70, tooltip = "Dibs gained or spent." },
        { title = "Reason", width = 220, tooltip = "Audit context." },
      }
    elseif expectedColumns == 7 then
      columns = {
        { title = "Date", width = 135, tooltip = "Request creation time." },
        { title = "Player", width = 130, tooltip = "Player who requested the item." },
        { title = "Status", width = 80, tooltip = "Current request lifecycle status." },
        { title = "Item", width = 180, tooltip = "Reserved item." },
        { title = "Difficulty", width = 80, tooltip = "Normal, Heroic, or Mythic." },
        { title = "Mode", width = 100, tooltip = "Wild Open or Encounter." },
        { title = "Sync", width = 100, tooltip = "Officer delivery acknowledgement." },
      }
    else
      columns = {
        { title = "Player", width = 220, tooltip = "Guild member." },
        { title = "Balance", width = 100, tooltip = "Current Dibs balance." },
        { title = "Actions", width = 100, tooltip = "Number of ledger entries." },
      }
    end
    self.aceLedgerScroll = Dibs.AceGUI.AddTable(shell, tabs, columns, tableRows, 430)
    local previous = Dibs.AceGUI.AddButton(shell, tabs, "Previous", function() self.ledgerPage = math.max(1, self.ledgerPage - 1); self:Refresh() end, 80)
    self.pageText = Dibs.AceGUI.AddLabel(shell, tabs, "Page " .. view.page .. "/" .. view.totalPages)
    local nextButton = Dibs.AceGUI.AddButton(shell, tabs, "Next", function() self.ledgerPage = math.min(view.totalPages, self.ledgerPage + 1); self:Refresh() end, 60)
    Dibs.AceGUI.SetDisabled(previous, view.page <= 1)
    Dibs.AceGUI.SetDisabled(nextButton, view.page >= view.totalPages)
    Dibs.AceGUI.AddTooltip(self.pageText, "Page", "Current page and total number of pages.")
  end
  frame:HookScript("OnShow", function(self) self:Refresh() end)
  _G.DibsOfficerFrame = frame
  frame:Refresh()
  Dibs.AceGUI.SelectTree(tabs, frame.activeTab)
  return frame
end

function Dibs.OfficerUI.CreateWindow()
  if _G.DibsOfficerFrame then
    local existingShell = _G.DibsOfficerFrame.dibsAceGUIShell
    if existingShell and existingShell.window then
      existingShell.window:SetWidth(980)
      existingShell.window:SetHeight(760)
    else
      _G.DibsOfficerFrame:SetSize(980, 760)
    end
    return _G.DibsOfficerFrame
  end

  if Dibs.AceGUI and Dibs.AceGUI.IsAvailable and Dibs.AceGUI.IsAvailable() then
    return createAceWindow()
  end

  local aceShell = nil
  local frame = CreateFrame("Frame", "DibsOfficerFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(640, 650)
  frame:SetPoint("CENTER", 280, 0)
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
   title:SetText("RCLootCouncil - Dibs | Officer")

  local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

  local seasonLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  seasonLabel:SetPoint("TOPLEFT", 16, -92)
  seasonLabel:SetWidth(610)
  seasonLabel:SetJustifyH("LEFT")

  local seasonDropdown = nil
  if HAS_DROPDOWN then
    seasonDropdown = CreateFrame("Frame", "DibsOfficerSeasonDropdown", frame, "UIDropDownMenuTemplate")
    seasonDropdown:SetPoint("TOPLEFT", 8, -20)
  end

  local previousSeasonButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  previousSeasonButton:SetSize(32, 22)
  previousSeasonButton:SetPoint("TOPLEFT", 242, -34)
  previousSeasonButton:SetText("<")

  local nextSeasonButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  nextSeasonButton:SetSize(32, 22)
  nextSeasonButton:SetPoint("LEFT", previousSeasonButton, "RIGHT", 4, 0)
  nextSeasonButton:SetText(">")

  local activateSeasonButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  activateSeasonButton:SetSize(84, 22)
  activateSeasonButton:SetPoint("LEFT", nextSeasonButton, "RIGHT", 6, 0)
  activateSeasonButton:SetText("Activate")

  local seasonNameInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  seasonNameInput:SetSize(260, 20)
  seasonNameInput:SetPoint("TOPLEFT", 16, -148)
  if seasonNameInput.SetAutoFocus then
    seasonNameInput:SetAutoFocus(false)
  end

  local newSeasonButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  newSeasonButton:SetSize(76, 22)
  newSeasonButton:SetPoint("LEFT", seasonNameInput, "RIGHT", 8, 0)
  newSeasonButton:SetText("Create")

  local renameSeasonButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  renameSeasonButton:SetSize(68, 22)
  renameSeasonButton:SetPoint("LEFT", newSeasonButton, "RIGHT", 4, 0)
  renameSeasonButton:SetText("Rename")

  local deleteSeasonButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  deleteSeasonButton:SetSize(62, 22)
  deleteSeasonButton:SetPoint("LEFT", renameSeasonButton, "RIGHT", 4, 0)
  deleteSeasonButton:SetText("Delete")

  local summaryText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  summaryText:SetPoint("TOPLEFT", 16, -178)
  summaryText:SetWidth(610)
  summaryText:SetJustifyH("LEFT")

  local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  statusText:SetPoint("TOPLEFT", 16, -256)
  statusText:SetWidth(610)
  statusText:SetJustifyH("LEFT")
  statusText:SetText("Ready")

  local sectionTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  sectionTitle:SetPoint("TOPLEFT", 16, -282)
  sectionTitle:SetText("Rank allocations (choose rank + dibs, then Set)")

  local addRowButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  addRowButton:SetSize(28, 22)
  addRowButton:SetPoint("LEFT", sectionTitle, "RIGHT", 10, 0)
  addRowButton:SetText("+")

  local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refreshButton:SetSize(90, 24)
  refreshButton:SetPoint("BOTTOMLEFT", 16, 14)
  refreshButton:SetText("Refresh")

  local dashboardButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  dashboardButton:SetSize(90, 22)
  dashboardButton:SetPoint("TOPLEFT", 16, -116)
  dashboardButton:SetText("Dashboard")

  local playersButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  playersButton:SetSize(76, 22)
  playersButton:SetPoint("LEFT", dashboardButton, "RIGHT", 4, 0)
  playersButton:SetText("Players")

  local preDibsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  preDibsButton:SetSize(76, 22)
  preDibsButton:SetPoint("LEFT", playersButton, "RIGHT", 4, 0)
  preDibsButton:SetText("Pre-Dibs")

  local historyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  historyButton:SetSize(76, 22)
  historyButton:SetPoint("LEFT", preDibsButton, "RIGHT", 4, 0)
  historyButton:SetText("History")

  local statisticsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  statisticsButton:SetSize(72, 22)
  statisticsButton:SetPoint("LEFT", historyButton, "RIGHT", 4, 0)
  statisticsButton:SetText("Stats")

  local settingsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  settingsButton:SetSize(76, 22)
  settingsButton:SetPoint("LEFT", statisticsButton, "RIGHT", 4, 0)
  settingsButton:SetText("Settings")

  local ledgerTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ledgerTitle:SetPoint("TOPLEFT", 16, -150)
  ledgerTitle:SetText("Dashboard")

  local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  searchLabel:SetPoint("TOPLEFT", 310, -150)
  searchLabel:SetText("Search:")

  local searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  searchBox:SetSize(150, 20)
  searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 6, 0)
  if searchBox.SetAutoFocus then
    searchBox:SetAutoFocus(false)
  end
  setControlText(searchBox, "")

  local clearSearchButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  clearSearchButton:SetSize(52, 22)
  clearSearchButton:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
  clearSearchButton:SetText("Clear")

  local ledgerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ledgerText:SetPoint("TOPLEFT", 16, -174)
  ledgerText:SetWidth(610)
  ledgerText:SetJustifyH("LEFT")

  local previousPageButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  previousPageButton:SetSize(28, 22)
  previousPageButton:SetPoint("BOTTOMLEFT", refreshButton, "RIGHT", 8, 0)
  previousPageButton:SetText("<")

  local pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  pageText:SetPoint("LEFT", previousPageButton, "RIGHT", 6, 0)
  pageText:SetWidth(100)
  pageText:SetJustifyH("LEFT")

  local nextPageButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  nextPageButton:SetSize(28, 22)
  nextPageButton:SetPoint("LEFT", pageText, "RIGHT", 6, 0)
  nextPageButton:SetText(">")

  frame.summaryText = summaryText
  frame.statusText = statusText
  frame.seasonLabel = seasonLabel
  frame.seasonDropdown = seasonDropdown
  frame.seasonNameInput = seasonNameInput
  frame.ledgerText = ledgerText
  frame.ledgerTitle = ledgerTitle
  frame.pageText = pageText
  frame.searchBox = searchBox
  frame.activeTab = "dashboard"
  frame.ledgerPage = 1
  frame.inputBoundSeasonId = nil
  frame.rankRows = {}
  frame.dibsAceGUIShell = aceShell
  frame.settingsControls = {
    seasonNameInput, newSeasonButton, renameSeasonButton, deleteSeasonButton,
    summaryText, statusText, sectionTitle, addRowButton,
  }

  frame.SetStatus = function(self, msg)
    local text = tostring(msg or "")
    if self.statusText and self.statusText.SetText then
      self.statusText:SetText(text)
    end
    Dibs.Message(text)
  end

  local function ensureRows(count)
    while #frame.rankRows < count do
      table.insert(frame.rankRows, createRankRow(frame, #frame.rankRows + 1))
    end
  end

  ensureRows(3)

  local function refreshSeasonDropdown(self, seasons)
    if not self.seasonDropdown or not HAS_DROPDOWN then
      return
    end

    configureDropdown(self.seasonDropdown, 210, function(_, level)
      if level ~= 1 then
        return
      end
      for _, season in ipairs(seasons) do
        local info = _G.UIDropDownMenu_CreateInfo()
        info.text = tostring(season.name)
        info.func = function()
          self.selectedSeasonId = season.id
          self.inputBoundSeasonId = nil
          setDropdownText(self.seasonDropdown, tostring(season.name))
          self:Refresh()
        end
        info.checked = season.id == self.selectedSeasonId
        _G.UIDropDownMenu_AddButton(info, level)
      end
    end)
  end

  frame.Refresh = function(self)
    local seasons = getSeasonList()
    local current = getSelectedSeason(self)
    if not current and #seasons > 0 then
      current = seasons[#seasons]
      self.selectedSeasonId = current.id
    end

    local activeSeasonId = Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil
    local selectedName = current and current.name or "None"
    local activeName = (activeSeasonId and findSeasonById(activeSeasonId) and findSeasonById(activeSeasonId).name) or "None"

    self.seasonLabel:SetText("Season: " .. selectedName .. " (active: " .. activeName .. ")")

    if self.seasonNameInput and self.inputBoundSeasonId ~= (current and current.id or nil) then
      setControlText(self.seasonNameInput, selectedName ~= "None" and selectedName or getDefaultSeasonName())
      self.inputBoundSeasonId = current and current.id or nil
    end

    refreshSeasonDropdown(self, seasons)
    if self.seasonDropdown and current then
      setDropdownText(self.seasonDropdown, tostring(current.name))
    end

    self.summaryText:SetText(Dibs.OfficerUI.BuildStatusText(current))

    ensureRows(math.max(3, #seasons > 0 and 3 or 2))
    syncRowsToSeason(self, current)

    local isSettings = self.activeTab == "settings"
    local isSearchable = self.activeTab == "players" or self.activeTab == "predibs" or self.activeTab == "history"
    setControlsVisible(self.settingsControls, isSettings)
    setControlsVisible(self.rankRows, isSettings)
    setControlsVisible({ self.ledgerTitle, self.ledgerText }, not isSettings)
    setControlsVisible({ searchLabel, searchBox, clearSearchButton }, isSearchable)

    if isSettings then
      setControlsVisible({ previousPageButton, pageText, nextPageButton }, false)
      return
    end

    if self.activeTab == "dashboard" then
      self.ledgerTitle:SetText("Dashboard")
      self.ledgerText:SetText(table.concat(Dibs.OfficerUI.BuildDashboardDetails(current), "\n"))
      setControlsVisible({ previousPageButton, pageText, nextPageButton }, false)
      return
    end

    if self.activeTab == "statistics" then
      local statistics = Dibs.OfficerUI.BuildSeasonStatistics(current and current.id or nil)
      self.ledgerTitle:SetText("Season statistics")
      self.ledgerText:SetText("Active players: " .. tostring(statistics.players) .. "\n" ..
        "Transactions: " .. tostring(statistics.transactions) .. "\n" ..
        "Dibs used: " .. tostring(statistics.used) .. "\n" ..
        "Active pre-Dibs: " .. tostring(statistics.activePreDibs))
      setControlsVisible({ previousPageButton, pageText, nextPageButton }, false)
      return
    end

    local viewName = self.activeTab == "history" and "actions" or self.activeTab
    local view = Dibs.OfficerUI.GetPagedView(viewName, current and current.id or nil, self.ledgerPage, 8, getControlText(self.searchBox))
    self.ledgerPage = view.page
    self.ledgerTitle:SetText(view.title .. " (" .. tostring(view.totalCount) .. ")")
    self.pageText:SetText("Page " .. tostring(view.page) .. "/" .. tostring(view.totalPages))
    self.ledgerText:SetText(table.concat(view.lines, "\n"))
    setControlsVisible({ previousPageButton, pageText, nextPageButton }, true)
  end

  local function shiftSeason(offset)
    local seasons = getSeasonList()
    if #seasons == 0 then
      return
    end
    local selected = frame.selectedSeasonId
    local idx = 1
    for i, season in ipairs(seasons) do
      if season.id == selected then
        idx = i
        break
      end
    end
    idx = idx + offset
    if idx < 1 then
      idx = #seasons
    elseif idx > #seasons then
      idx = 1
    end
    frame.selectedSeasonId = seasons[idx].id
    frame.inputBoundSeasonId = nil
    frame:Refresh()
  end

  previousSeasonButton:SetScript("OnClick", function()
    shiftSeason(-1)
  end)

  nextSeasonButton:SetScript("OnClick", function()
    shiftSeason(1)
  end)

  activateSeasonButton:SetScript("OnClick", function()
    local selected = getSelectedSeason(frame)
    if not selected then
      frame:SetStatus("No season selected.")
      return
    end
    local result = Dibs.ProtectedActions.Execute("season.set", nil, { seasonId = selected.id })
    frame:SetStatus(result.ok and ("Active season: " .. tostring(selected.name)) or result.diagnostic)
    frame:Refresh()
  end)

  newSeasonButton:SetScript("OnClick", function()
    local typed = trimText(getControlText(frame.seasonNameInput))
    local name = makeUniqueSeasonName(typed ~= "" and typed or getDefaultSeasonName())
    local result = Dibs.ProtectedActions.Execute("season.create", nil, { name = name })
    if result.ok and result.value then
      frame.selectedSeasonId = result.value.id
      frame.inputBoundSeasonId = nil
      frame:SetStatus("Created season: " .. tostring(result.value.name))
      setControlText(frame.seasonNameInput, getDefaultSeasonName())
    else
      frame:SetStatus(result.diagnostic or "Failed to create season.")
    end
    frame:Refresh()
  end)

  renameSeasonButton:SetScript("OnClick", function()
    local selected = getSelectedSeason(frame)
    if not selected then
      frame:SetStatus("No season selected.")
      return
    end

    local typed = trimText(getControlText(frame.seasonNameInput))
    if typed == "" then
      frame:SetStatus("Enter a season name first.")
      return
    end

    local duplicate = findSeasonByName(typed, selected.id)
    if duplicate then
      frame:SetStatus("A season with this name already exists.")
      return
    end

    local result = Dibs.ProtectedActions.Execute("season.rename", nil, { seasonId = selected.id, name = typed })
    if result.ok and result.value then
      frame.inputBoundSeasonId = nil
      frame:SetStatus("Season renamed: " .. tostring(result.value.name))
    else
      frame:SetStatus(result.diagnostic or "Unable to rename the selected season.")
    end
    frame:Refresh()
  end)

  deleteSeasonButton:SetScript("OnClick", function()
    local selected = getSelectedSeason(frame)
    if not selected then
      frame:SetStatus("No season selected.")
      return
    end

    local seasons = getSeasonList()
    if #seasons <= 1 then
      frame:SetStatus("At least one season must remain.")
      return
    end

    local result = Dibs.ProtectedActions.Execute("season.archive", nil, { seasonId = selected.id })
    if result.ok and result.value then
      frame.selectedSeasonId = nil
      frame.inputBoundSeasonId = nil
      frame:SetStatus("Season archived: " .. tostring(result.value.name))
    else
      frame:SetStatus(result.diagnostic or "Unable to delete the selected season.")
    end
    frame:Refresh()
  end)

  addRowButton:SetScript("OnClick", function()
    ensureRows(#frame.rankRows + 1)
    frame:Refresh()
  end)

  refreshButton:SetScript("OnClick", function()
    frame:Refresh()
  end)

  local function selectTab(tab)
    frame.activeTab = tab
    frame.ledgerPage = 1
    frame:Refresh()
  end

  frame.SelectTab = selectTab
  if aceShell then
    frame.aceTabs = Dibs.AceGUI.AddTabs(aceShell, {
      { text = "Dashboard", value = "dashboard" },
      { text = "Players", value = "players" },
      { text = "Pre-Dibs", value = "predibs" },
      { text = "History", value = "history" },
      { text = "Statistics", value = "statistics" },
      { text = "Settings", value = "settings" },
    }, selectTab)
    frame.aceLedgerScroll = Dibs.AceGUI.AddScrollableList(aceShell)
    frame.aceLedgerSearch = Dibs.AceGUI.AddSearch(aceShell, function(value)
      setControlText(frame.searchBox, value)
      frame.ledgerPage = 1
      frame:Refresh()
    end)
    frame.aceLedgerPagination = Dibs.AceGUI.AddPagination(aceShell, function()
      frame.ledgerPage = math.max(1, (frame.ledgerPage or 1) - 1)
      frame:Refresh()
    end, function()
      frame.ledgerPage = (frame.ledgerPage or 1) + 1
      frame:Refresh()
    end)
  end

  dashboardButton:SetScript("OnClick", function() selectTab("dashboard") end)
  playersButton:SetScript("OnClick", function() selectTab("players") end)
  preDibsButton:SetScript("OnClick", function() selectTab("predibs") end)
  historyButton:SetScript("OnClick", function() selectTab("history") end)
  statisticsButton:SetScript("OnClick", function() selectTab("statistics") end)
  settingsButton:SetScript("OnClick", function() selectTab("settings") end)
  searchBox:SetScript("OnTextChanged", function()
    frame.ledgerPage = 1
    frame:Refresh()
  end)
  clearSearchButton:SetScript("OnClick", function()
    setControlText(searchBox, "")
    frame.ledgerPage = 1
    frame:Refresh()
  end)
  previousPageButton:SetScript("OnClick", function()
    frame.ledgerPage = math.max(1, (frame.ledgerPage or 1) - 1)
    frame:Refresh()
  end)
  nextPageButton:SetScript("OnClick", function()
    frame.ledgerPage = (frame.ledgerPage or 1) + 1
    frame:Refresh()
  end)

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
  if not canViewOfficerData() then
    Dibs.Message("Only the guild master or an officer may open the officer view.")
    return nil
  end
  local frame = Dibs.OfficerUI.CreateWindow()
  local shell = frame.dibsAceGUIShell
  if shell and shell.window then
    shell.window:SetWidth(800)
    shell.window:SetHeight(720)
  else
    frame:SetSize(800, 720)
  end
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
  if not canViewOfficerData() then
    Dibs.Message("Only the guild master or an officer may open the officer view.")
    return false
  end
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
