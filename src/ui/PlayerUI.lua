local Dibs = _G.Dibs
Dibs.PlayerUI = Dibs.PlayerUI or {}

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

local function trimText(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function parseItemInput(raw)
  local text = trimText(raw)
  if text == "" then return nil end

  local linkId = tonumber(text:match("item:(%d+)"))
  if linkId and linkId > 0 then
    return linkId
  end

  local numericId = tonumber(text:match("^(%d+)$"))
  if numericId and numericId > 0 then
    return numericId
  end

  return nil
end

local function submitPublicPreDib(rawItem)
  local itemID = parseItemInput(rawItem)
  if not itemID then
    return nil, "Invalid item: use item ID or item link."
  end

  local itemName = "Item " .. tostring(itemID)
  if type(GetItemInfo) == "function" then
    local _, link = GetItemInfo(itemID)
    itemName = link or itemName
  end

  if Dibs.LootPipeline and Dibs.LootPipeline.RequestDibFromContext then
    return Dibs.LootPipeline.RequestDibFromContext({
      source = "player-ui",
      isTest = false,
      itemID = itemID,
      itemLink = itemName,
      itemName = itemName,
      owner = Dibs.GetPlayerName and Dibs.GetPlayerName() or nil,
      seasonId = Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil,
    })
  end

  if Dibs.PreDibs and Dibs.PreDibs.CreatePublic then
    local request, reason = Dibs.PreDibs.CreatePublic(Dibs.GetPlayerName(), itemID, itemName, Dibs.GetCurrentSeasonId(), "player-ui")
    if request then
      return request, nil
    end
    if reason == "PUBLIC_PRE_DIBS_DISABLED" then
      return nil, "Public pre-dibs are disabled by officers."
    end
    return nil, "Unable to create pre-dib request."
  end

  if Dibs.PreDibs and Dibs.PreDibs.Create then
    local request = Dibs.PreDibs.Create(Dibs.GetPlayerName(), itemID, itemName, Dibs.GetCurrentSeasonId())
    if request then
      return request, nil
    end
  end

  return nil, "Pre-dib module unavailable."
end

Dibs.PlayerUI.SubmitPreDib = submitPublicPreDib

local function cancelPlayerPreDib(requestId)
  if not (Dibs.PreDibs and Dibs.PreDibs.CancelForPlayer) then
    return nil, "Cancellation unavailable."
  end
  return Dibs.PreDibs.CancelForPlayer(requestId, Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
end

local function formatDevContextLine(context)
  if type(context) ~= "table" then
    return "No injected DEV item."
  end
  local itemName = tostring(context.itemName or context.itemLink or ("Item " .. tostring(context.itemID or "?")))
  local itemID = tonumber(context.itemID) or 0
  return "DEV TEST: [DEV] " .. itemName .. " (" .. tostring(itemID) .. ")"
end

local function compactLine(tx)
  local stamp = tonumber(tx.createdAt or tx.timestamp) or 0
  local dateText = stamp > 0 and (type(date) == "function" and date("%Y-%m-%d %H:%M:%S", stamp) or tostring(stamp)) or "Unknown"
  local action = tostring(tx.type or tx.actionType or "UNKNOWN")
  local amount = tonumber(tx.amount or tx.quantityDelta) or 0
  local reason = tostring(tx.reason or "")
  local sign = amount >= 0 and "+" or ""
  return dateText .. " | " .. action .. " | " .. sign .. tostring(amount) .. (reason ~= "" and (" | " .. reason) or "")
end

local function splitPipeLine(line)
  local cells = {}
  for cell in (tostring(line or "") .. "|"):gmatch("(.-)|") do
    table.insert(cells, cell:match("^%s*(.-)%s*$"))
  end
  while #cells > 4 do table.remove(cells) end
  return cells
end

local function buildFilteredHistory(playerName, seasonId, query, mode)
  local q = string.lower(tostring(query or ""))
  local items = {}

  if mode == "all" and Dibs.Ledger and Dibs.Ledger.GetAllTransactions then
    local playerKey = string.lower(tostring(playerName or Dibs.GetPlayerName()))
    for _, tx in ipairs(Dibs.Ledger.GetAllTransactions()) do
      local txPlayer = string.lower(tostring(tx.playerName or tx.playerKey or ""))
      if txPlayer == playerKey then
        table.insert(items, tx)
      end
    end
  elseif Dibs.Ledger and Dibs.Ledger.GetHistory then
    items = Dibs.Ledger.GetHistory(playerName, seasonId)
  end

  table.sort(items, function(a, b)
    return (a.createdAt or a.timestamp or 0) > (b.createdAt or b.timestamp or 0)
  end)

  local filtered = {}
  for _, tx in ipairs(items) do
    local line = compactLine(tx)
    if q == "" or string.find(string.lower(line), q, 1, true) then
      table.insert(filtered, line)
    end
  end

  return filtered
end

function Dibs.PlayerUI.GetSummary(playerName)
  local season = Dibs.Seasons and Dibs.Seasons.GetCurrent() or nil
  local balance = Dibs.Ledger and Dibs.Ledger.GetBalance(playerName or Dibs.GetPlayerName(), season and season.id) or 0
  local requests = Dibs.PreDibs and Dibs.PreDibs.GetActiveRequests(playerName or Dibs.GetPlayerName()) or {}
  local acquisitions = Dibs.PreDibs and Dibs.PreDibs.GetAcquisitionsForPlayer and Dibs.PreDibs.GetAcquisitionsForPlayer(playerName or Dibs.GetPlayerName()) or {}

  return {
    season = season,
    player = playerName or Dibs.GetPlayerName(),
    balance = balance,
    activePreDibs = requests,
    acquisitions = acquisitions,
    modePolicy = Dibs.PreDibs and Dibs.PreDibs.GetModePolicy and Dibs.PreDibs.GetModePolicy(season and season.id) or nil,
  }
end

function Dibs.PlayerUI.RecordVaultAcquisition(itemID, difficulty)
  if not (Dibs.PreDibs and Dibs.PreDibs.RecordVaultAcquisition) then return nil, "ACQUISITIONS_UNAVAILABLE" end
  return Dibs.PreDibs.RecordVaultAcquisition(Dibs.GetPlayerName and Dibs.GetPlayerName() or nil, itemID, difficulty)
end

function Dibs.PlayerUI.GetHistory(playerName)
  if not Dibs.Ledger then
    return {}
  end

  return Dibs.Ledger.GetHistory(playerName or Dibs.GetPlayerName())
end

local function createAceWindow()
  local shell = Dibs.AceGUI.CreateWindow("Dibs", 560, 560, { "CENTER", 0, 0 })
  if not shell then return nil end
  local frame = shell.frame
  if frame and frame.SetUserPlaced then frame:SetUserPlaced(true) end
  frame.dibsAceGUIShell = shell
  frame.historyMode = "current"
  frame.historyPage = 1
  frame.playerTab = "summary"
  frame.devContext = nil

  local function submitFromInput()
    local request, errorText = submitPublicPreDib(getControlText(frame.preDibInput))
    if request then
      setControlText(frame.preDibInput, "")
      frame.preDibStatusText = "Pre-Dib saved for item " .. tostring(request.itemID) .. " (status: " .. tostring(request.status) .. ")"
    else
      frame.preDibStatusText = errorText or "Unable to create pre-dib request."
    end
    frame:Refresh()
  end

  local function submitDevRequest()
    local enabled = Dibs.DeveloperMode and Dibs.DeveloperMode.IsEnabled and Dibs.DeveloperMode.IsEnabled() or false
    local context = frame.devContext or (Dibs.LootPipeline and Dibs.LootPipeline.GetPendingDevContext and Dibs.LootPipeline.GetPendingDevContext())
    if not enabled then
      frame.devStatus = "Developer Mode required"
    elseif not context then
      frame.devStatus = "Use /dibs testitem <itemID> to inject an item."
    elseif Dibs.LootPipeline and Dibs.LootPipeline.RequestDibFromContext then
      local request, reason = Dibs.LootPipeline.RequestDibFromContext(context)
      frame.devStatus = request and ("Test Request Dib created for item " .. tostring(request.itemID) .. ".")
        or (reason == "INVALID_ITEM" and "Invalid test item." or "Unable to create test Request Dib.")
    else
      frame.devStatus = "Loot pipeline unavailable."
    end
    frame:Refresh()
  end

  local tabs = Dibs.AceGUI.AddTabs(shell, {
    { text = "Summary", value = "summary" },
    { text = "History", value = "history" },
  }, function(value)
    frame.playerTab = value
    frame:Refresh()
  end)
  frame.aceTabs = tabs

  frame.Refresh = function(self)
    Dibs.AceGUI.Clear(tabs)
    Dibs.AceGUI.AddButton(shell, tabs, "RCLootCouncil - Dibs options", function() Dibs.RCOptions.Open() end, 240)
    local summary = Dibs.PlayerUI.GetSummary()
    if self.playerTab == "history" then
      Dibs.AceGUI.AddLabel(shell, tabs, "History (condensed)", true)
      self.searchBox = Dibs.AceGUI.AddEditBox(shell, tabs, "Search", function(value)
        self.historyQuery = value
        self.historyPage = 1
        self:Refresh()
      end, 200)
      setControlText(self.searchBox, self.historyQuery or "")
      local modeButton = Dibs.AceGUI.AddButton(shell, tabs, self.historyMode == "all" and "Mode: All" or "Mode: Season", function()
        self.historyMode = self.historyMode == "all" and "current" or "all"
        self.historyPage = 1
        self:Refresh()
      end, 110)
      Dibs.AceGUI.AddTooltip(modeButton, "History scope", self.historyMode == "all" and "Showing all seasons." or "Showing only the current season.")
      Dibs.AceGUI.AddButton(shell, tabs, "Clear", function()
        self.historyQuery = ""
        self.historyPage = 1
        self:Refresh()
      end, 70)
      local lines = buildFilteredHistory(summary.player, summary.season and summary.season.id, self.historyQuery, self.historyMode)
      local pageSize = 9
      local totalPages = math.max(1, math.ceil(#lines / pageSize))
      self.historyPage = math.min(math.max(1, self.historyPage), totalPages)
      local visible = {}
      for index = ((self.historyPage - 1) * pageSize) + 1, math.min(#lines, self.historyPage * pageSize) do
        table.insert(visible, lines[index])
      end
      if #visible == 0 then visible[1] = "No matching history." end
      local rows = {}
      for _, line in ipairs(visible) do table.insert(rows, splitPipeLine(line)) end
      self.aceHistoryScroll = Dibs.AceGUI.AddTable(shell, tabs, {
        { title = "Date", width = 145, tooltip = "When the ledger entry was recorded." },
        { title = "Action", width = 150, tooltip = "The ledger operation." },
        { title = "Amount", width = 70, tooltip = "Dibs gained or spent." },
        { title = "Reason", width = 170, tooltip = "Why the entry was created." },
      }, rows, 320)
      local previous = Dibs.AceGUI.AddButton(shell, tabs, "Previous", function()
        self.historyPage = math.max(1, self.historyPage - 1)
        self:Refresh()
      end, 90)
      local pageLabel = Dibs.AceGUI.AddLabel(shell, tabs, "Page " .. tostring(self.historyPage) .. "/" .. tostring(totalPages))
      local nextButton = Dibs.AceGUI.AddButton(shell, tabs, "Next", function()
        self.historyPage = math.min(totalPages, self.historyPage + 1)
        self:Refresh()
      end, 70)
      Dibs.AceGUI.SetDisabled(previous, self.historyPage <= 1)
      Dibs.AceGUI.SetDisabled(nextButton, self.historyPage >= totalPages)
      Dibs.AceGUI.AddTooltip(pageLabel, "Page", "Current page and total number of pages.")
      return
    end

    Dibs.AceGUI.AddHeader(shell, tabs, "Season summary", "Your current season balance and Pre-Dib status.")
    Dibs.AceGUI.AddTable(shell, tabs, {
      { title = "Metric", width = 180, tooltip = "Summary field." },
      { title = "Value", width = 280, tooltip = "Current value." },
    }, {
      { "Season", tostring(summary.season and summary.season.name or "None") },
      { "Balance", tostring(summary.balance) },
      { "Active Pre-Dibs", tostring(#(summary.activePreDibs or {})) },
      { "Vault acquisitions", tostring(#(summary.acquisitions or {})) },
      { "Pre-Dib mode", tostring(summary.modePolicy and summary.modePolicy.mode or "WILD_OPEN") },
    }, 145)
    Dibs.AceGUI.AddLabel(shell, tabs, "My active Pre-Dibs", true)
    local activeRows = {}
    if #(summary.activePreDibs or {}) == 0 then
      activeRows[1] = { "No active Pre-Dibs.", "", "", "" }
    else
      for _, request in ipairs(summary.activePreDibs) do
        activeRows[#activeRows + 1] = {
          tostring(request.itemName or request.itemLink or ("Item " .. tostring(request.itemID))),
          tostring(request.difficulty or "Normal"),
          tostring(request.status),
          "",
          request = request,
        }
      end
    end
    Dibs.AceGUI.AddTable(shell, tabs, {
      { title = "Item", width = 240, tooltip = "The reserved loot." },
      { title = "Difficulty", width = 100, tooltip = "Normal, Heroic, or Mythic." },
      { title = "Status", width = 100, tooltip = "Pending or confirmed." },
      { title = "Action", width = 90, tooltip = "Cancel your request." },
    }, activeRows, 145, function(row)
      if not row.request then return nil end
      return {
        text = "Cancel",
        callback = function()
          local request = row.request
          local cancelled, reason = cancelPlayerPreDib(request.requestId)
          frame.preDibStatusText = cancelled and ("Pre-Dib cancelled for item " .. tostring(request.itemID) .. ".")
            or (reason == "NOT_REQUEST_OWNER" and "You can only cancel your own Pre-Dibs." or "Unable to cancel this Pre-Dib.")
          frame:Refresh()
        end,
      }
    end)
    self.preDibInput = Dibs.AceGUI.AddEditBox(shell, tabs, "Public pre-dib (item ID or link)", nil, 260)
    setControlText(self.preDibInput, self.preDibValue or "")
    self.preDibButton = Dibs.AceGUI.AddButton(shell, tabs, "I want to DIB this", submitFromInput, 170)
    local publicEnabled = Dibs.PreDibs and Dibs.PreDibs.IsPublicEnabled and Dibs.PreDibs.IsPublicEnabled() or false
    Dibs.AceGUI.SetDisabled(self.preDibButton, not publicEnabled)
    self.preDibStatus = Dibs.AceGUI.AddLabel(shell, tabs, self.preDibStatusText or (publicEnabled and "Public pre-dibs enabled." or "Public pre-dibs disabled by officers."), true)
    local context = self.devContext or (Dibs.LootPipeline and Dibs.LootPipeline.GetPendingDevContext and Dibs.LootPipeline.GetPendingDevContext())
    local devEnabled = Dibs.DeveloperMode and Dibs.DeveloperMode.IsEnabled and Dibs.DeveloperMode.IsEnabled() or false
    if devEnabled or (Dibs.DebugEnabled and Dibs.DebugEnabled("ui", 4)) then
      self.devItemText = Dibs.AceGUI.AddLabel(shell, tabs, formatDevContextLine(context), true)
      self.devRequestButton = Dibs.AceGUI.AddButton(shell, tabs, "Request Dib (DEV)", submitDevRequest, 170)
      Dibs.AceGUI.SetDisabled(self.devRequestButton, not (devEnabled and type(context) == "table" and tonumber(context.itemID)))
      self.devStatusText = Dibs.AceGUI.AddLabel(shell, tabs, self.devStatus or (devEnabled and "Use /dibs testitem <itemID> to inject an item." or "Developer Mode required"), true)
    end
  end
  frame:HookScript("OnShow", function(self) self:Refresh() end)
  _G.DibsPlayerFrame = frame
  frame:Refresh()
  return frame
end

function Dibs.PlayerUI.CreateWindow()
  if _G.DibsPlayerFrame then
    return _G.DibsPlayerFrame
  end

  if Dibs.AceGUI and Dibs.AceGUI.IsAvailable and Dibs.AceGUI.IsAvailable() then
    return createAceWindow()
  end

  local aceShell = nil
  local frame = CreateFrame("Frame", "DibsPlayerFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(460, 470)
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

  local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

  local summaryText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  summaryText:SetPoint("TOPLEFT", 16, -40)
  summaryText:SetWidth(430)
  summaryText:SetJustifyH("LEFT")

  local preDibLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  preDibLabel:SetPoint("TOPLEFT", 16, -96)
  preDibLabel:SetText("Public pre-dib (item ID or link)")

  local preDibInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  preDibInput:SetSize(252, 20)
  preDibInput:SetPoint("TOPLEFT", 16, -116)
  if preDibInput.SetAutoFocus then
    preDibInput:SetAutoFocus(false)
  end
  setControlText(preDibInput, "")

  local preDibButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  preDibButton:SetSize(168, 22)
  preDibButton:SetPoint("LEFT", preDibInput, "RIGHT", 8, 0)
  preDibButton:SetText("I want to DIB this")

  local preDibStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  preDibStatus:SetPoint("TOPLEFT", 16, -142)
  preDibStatus:SetWidth(430)
  preDibStatus:SetJustifyH("LEFT")

  local devLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  devLabel:SetPoint("TOPLEFT", 16, -172)
  devLabel:SetText("Developer test context")

  local devItemText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  devItemText:SetPoint("TOPLEFT", 16, -194)
  devItemText:SetWidth(430)
  devItemText:SetJustifyH("LEFT")
  devItemText:SetText("No injected DEV item.")

  local devRequestButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  devRequestButton:SetSize(168, 22)
  devRequestButton:SetPoint("TOPLEFT", 16, -216)
  devRequestButton:SetText("Request Dib (DEV)")

  local devStatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  devStatusText:SetPoint("TOPLEFT", 16, -242)
  devStatusText:SetWidth(430)
  devStatusText:SetJustifyH("LEFT")
  devStatusText:SetText("Developer Mode required")

  local historyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  historyLabel:SetPoint("TOPLEFT", 16, -272)
  historyLabel:SetText("History (condensed)")

  local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  searchLabel:SetPoint("TOPLEFT", 16, -294)
  searchLabel:SetText("Search:")

  local searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  searchBox:SetSize(170, 20)
  searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
  if searchBox.SetAutoFocus then
    searchBox:SetAutoFocus(false)
  end
  setControlText(searchBox, "")

  local modeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  modeButton:SetSize(108, 22)
  modeButton:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)

  local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  clearButton:SetSize(62, 22)
  clearButton:SetPoint("LEFT", modeButton, "RIGHT", 6, 0)
  clearButton:SetText("Clear")

  local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refreshButton:SetSize(72, 22)
  refreshButton:SetPoint("LEFT", clearButton, "RIGHT", 6, 0)
  refreshButton:SetText("Refresh")

  local historyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  historyText:SetPoint("TOPLEFT", 16, -322)
  historyText:SetWidth(430)
  historyText:SetJustifyH("LEFT")

  frame.summaryText = summaryText
  frame.historyText = historyText
  frame.searchBox = searchBox
  frame.preDibInput = preDibInput
  frame.preDibButton = preDibButton
  frame.preDibStatus = preDibStatus
  frame.devItemText = devItemText
  frame.devRequestButton = devRequestButton
  frame.devStatusText = devStatusText
  frame.historyMode = "current"
  frame.historyPage = 1
  frame.devContext = nil
  frame.dibsAceGUIShell = aceShell

  if aceShell then
    frame.aceTabs = Dibs.AceGUI.AddTabs(aceShell, {
      { text = "Summary", value = "summary" },
      { text = "History", value = "history" },
    }, function(value)
      frame.playerTab = value
      frame:Refresh()
    end)
    frame.aceHistoryScroll = Dibs.AceGUI.AddScrollableList(aceShell)
    frame.aceHistorySearch = Dibs.AceGUI.AddSearch(aceShell, function(value)
      setControlText(frame.searchBox, value)
      frame.historyPage = 1
      frame:Refresh()
    end)
    frame.aceHistoryPagination = Dibs.AceGUI.AddPagination(aceShell, function()
      frame.historyPage = math.max(1, (frame.historyPage or 1) - 1)
      frame:Refresh()
    end, function()
      frame.historyPage = (frame.historyPage or 1) + 1
      frame:Refresh()
    end)
  end

  frame.Refresh = function(self)
    local summary = Dibs.PlayerUI.GetSummary()
    local status = "Season: " .. tostring((summary.season and summary.season.name) or "None") .. "\n" ..
      "Balance: " .. tostring(summary.balance) .. "\n" ..
      "Pre-Dibs: " .. tostring(#(summary.activePreDibs or {})) .. "\n" ..
      "Acquired: " .. tostring(#(summary.acquisitions or {})) .. "\n" ..
      "Pre-Dib mode: " .. tostring(summary.modePolicy and summary.modePolicy.mode or "WILD_OPEN")
    self.summaryText:SetText(status)

    local publicEnabled = Dibs.PreDibs and Dibs.PreDibs.IsPublicEnabled and Dibs.PreDibs.IsPublicEnabled() or false
    if self.preDibButton and self.preDibButton.Enable and self.preDibButton.Disable then
      if publicEnabled then
        self.preDibButton:Enable()
      else
        self.preDibButton:Disable()
      end
    end
    if self.preDibStatus then
      if publicEnabled then
        self.preDibStatus:SetText("Public pre-dibs enabled. Confirmed pre-dibs lock non-reserved players on drop.")
      else
        self.preDibStatus:SetText("Public pre-dibs disabled by officers.")
      end
    end

    local devEnabled = Dibs.DeveloperMode and Dibs.DeveloperMode.IsEnabled and Dibs.DeveloperMode.IsEnabled() or false
    local devContext = self.devContext or (Dibs.LootPipeline and Dibs.LootPipeline.GetPendingDevContext and Dibs.LootPipeline.GetPendingDevContext()) or nil
    if self.devItemText then
      self.devItemText:SetText(formatDevContextLine(devContext))
    end
    if self.devRequestButton and self.devRequestButton.Enable and self.devRequestButton.Disable then
      if devEnabled and type(devContext) == "table" and tonumber(devContext.itemID) and tonumber(devContext.itemID) > 0 then
        self.devRequestButton:Enable()
      else
        self.devRequestButton:Disable()
      end
    end
    if self.devStatusText then
      if not devEnabled then
        self.devStatusText:SetText("Developer Mode required")
      elseif type(devContext) ~= "table" then
        self.devStatusText:SetText("Use /dibs testitem <itemID> to inject an item.")
      else
        self.devStatusText:SetText("DEV context ready. Click Request Dib (DEV) to create a local test request.")
      end
    end

    modeButton:SetText(self.historyMode == "all" and "Mode: All" or "Mode: Season")

    local query = getControlText(self.searchBox)
    local seasonId = summary.season and summary.season.id or nil
    local lines = buildFilteredHistory(summary.player, seasonId, query, self.historyMode)
    local maxLines = 9
    local totalPages = math.max(1, math.ceil(#lines / maxLines))
    self.historyPage = math.min(math.max(1, self.historyPage or 1), totalPages)
    local startIndex = ((self.historyPage - 1) * maxLines) + 1
    local out = {}
    for i = startIndex, math.min(#lines, startIndex + maxLines - 1) do
      out[#out + 1] = lines[i]
    end
    if #out == 0 then
      out[1] = "No matching history."
    end
    if totalPages > 1 then
      out[#out + 1] = "Page " .. tostring(self.historyPage) .. "/" .. tostring(totalPages)
    end
    self.historyText:SetText(table.concat(out, "\n"))
  end

  if searchBox.SetScript then
    searchBox:SetScript("OnTextChanged", function()
      frame.historyPage = 1
      if frame.Refresh then
        frame:Refresh()
      end
    end)
  end

  clearButton:SetScript("OnClick", function()
    setControlText(searchBox, "")
    frame:Refresh()
  end)

  modeButton:SetScript("OnClick", function()
    frame.historyMode = frame.historyMode == "all" and "current" or "all"
    frame.historyPage = 1
    frame:Refresh()
  end)

  refreshButton:SetScript("OnClick", function()
    frame:Refresh()
  end)

  preDibButton:SetScript("OnClick", function()
    local request, errorText = submitPublicPreDib(getControlText(preDibInput))
    if request then
      setControlText(preDibInput, "")
      Dibs.Message("Pre-Dib saved for item " .. tostring(request.itemID) .. " (status: " .. tostring(request.status) .. ")")
    else
      Dibs.Message(errorText or "Unable to create pre-dib request.")
    end
    frame:Refresh()
  end)

  devRequestButton:SetScript("OnClick", function()
    local devEnabled = Dibs.DeveloperMode and Dibs.DeveloperMode.IsEnabled and Dibs.DeveloperMode.IsEnabled() or false
    if not devEnabled then
      Dibs.Message("Developer Mode is disabled. Use /dibs dev on to enable test commands.")
      frame:Refresh()
      return
    end

    local context = frame.devContext or (Dibs.LootPipeline and Dibs.LootPipeline.GetPendingDevContext and Dibs.LootPipeline.GetPendingDevContext()) or nil
    if not context then
      Dibs.Message("[Dibs DEV] No injected test item. Use /dibs testitem <itemID>.")
      frame:Refresh()
      return
    end

    if Dibs.LootPipeline and Dibs.LootPipeline.RequestDibFromContext then
      local request, reason = Dibs.LootPipeline.RequestDibFromContext(context)
      if request then
        Dibs.Message("[Dibs DEV] Test Request Dib created for item " .. tostring(request.itemID) .. ".")
      elseif reason == "INVALID_ITEM" then
        Dibs.Message("[Dibs DEV] Invalid test item.")
      else
        Dibs.Message("[Dibs DEV] Unable to create test Request Dib.")
      end
    else
      Dibs.Message("[Dibs DEV] Loot pipeline unavailable.")
    end
    frame:Refresh()
  end)

  if preDibInput.SetScript then
    preDibInput:SetScript("OnEnterPressed", function()
      local request, errorText = submitPublicPreDib(getControlText(preDibInput))
      if request then
        setControlText(preDibInput, "")
        Dibs.Message("Pre-Dib saved for item " .. tostring(request.itemID) .. " (status: " .. tostring(request.status) .. ")")
      else
        Dibs.Message(errorText or "Unable to create pre-dib request.")
      end
      frame:Refresh()
    end)
  end

  frame:HookScript("OnShow", function(self)
    self:Refresh()
  end)

  _G.DibsPlayerFrame = frame
  return frame
end

function Dibs.PlayerUI.SetDevContext(context)
  local frame = Dibs.PlayerUI.CreateWindow()
  frame.devContext = context
  if frame.Refresh then
    frame:Refresh()
  end
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
