--[[
Module: Dibs.PlayerUI
Layer: Player UI controller
Purpose: Show a player's balance, requests, acquisition history, and Pre-Dib actions.
Responsibilities: Player-scoped read views and request submission.
Non-responsibilities: It does not expose officer data or decide awards.
Dependencies: AceGUI, Ledger, PreDibs, EncounterJournal, Permissions.
Blizzard events: None directly.
Internal events/messages: UI callbacks to PreDibs.
SavedVariables: Reads via domain services.
RCLootCouncil: Optional item context only.
Combat safety: Request/UI actions respect combat lockdown and readiness.
Invariants: DIBS-RULE-002, DIBS-RULE-003, DIBS-RULE-005.
Related docs: docs/player/README.md.
]]

---@diagnostic disable: redundant-return-value

local Dibs = _G.Dibs
Dibs.PlayerUI = Dibs.PlayerUI or {}
local helpText = Dibs.L or {}

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

local function getGuildCharacterChoices()
  local choices = {}
  local localName = string.lower(trimText(Dibs.GetPlayerName and Dibs.GetPlayerName() or ""))
  if type(_G.GetNumGuildMembers) == "function" and type(_G.GetGuildRosterInfo) == "function" then
    local count = _G.GetNumGuildMembers() or 0
    if type(count) ~= "number" then count = tonumber(count) or 0 end
    for index = 1, count do
      local ok, name = pcall(_G.GetGuildRosterInfo, index)
      name = ok and trimText(name) or ""
      if name ~= "" and string.lower(name) ~= localName then choices[name] = name end
    end
  end
  return choices
end

local function formatDate(timestamp)
  local value = tonumber(timestamp) or 0
  if value > 0 and type(date) == "function" then
    local ok, formatted = pcall(date, "%Y-%m-%d %H:%M:%S", value)
    if ok and formatted then return tostring(formatted) end
  end
  return value > 0 and tostring(value) or "Unknown"
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

local PLAYER_NAV_TREE = {
  { text = "My Dibs", value = "my-dibs" },
  { text = "Requests", value = "requests", module = "requests" },
  { text = "History", value = "history" },
  { text = "Diagnostics", value = "diagnostics" },
}

local function moduleEnabled(moduleKey)
  return not moduleKey or not Dibs.OperationalPolicy or not Dibs.OperationalPolicy.GetModuleStatus
    or Dibs.OperationalPolicy.GetModuleStatus(moduleKey).enabled == true
end

function Dibs.PlayerUI.GetNavigation()
  local navigation = {}
  for _, entry in ipairs(PLAYER_NAV_TREE) do
    if moduleEnabled(entry.module) then
      navigation[#navigation + 1] = { text = entry.text, value = entry.value }
    end
  end
  return navigation
end

local function submitPublicPreDib(rawItem)
  local itemID = parseItemInput(rawItem)
  if not itemID then
    return nil, "Invalid item: use item ID or item link."
  end

  local itemName = "Item " .. tostring(itemID)
  if type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then
    local _, link = C_Item.GetItemInfo(itemID)
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

Dibs.PlayerUI.CancelPreDib = cancelPlayerPreDib

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
  if tx.source == "rclootcouncil_history" then
    reason = "Historical RCLootCouncil" .. (reason ~= "" and (": " .. reason) or "")
  end
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

local function getPlayerTransactions(playerName, seasonId, mode)
  local items = {}
  if mode == "all" and Dibs.Ledger and Dibs.Ledger.GetAllTransactions then
    local playerKey = string.lower(tostring(playerName or Dibs.GetPlayerName()))
    for _, tx in ipairs(Dibs.Ledger.GetAllTransactions()) do
      if string.lower(tostring(tx.playerName or tx.playerKey or "")) == playerKey then
        table.insert(items, tx)
      end
    end
  elseif Dibs.Ledger and Dibs.Ledger.GetHistory then
    items = Dibs.Ledger.GetHistory(playerName, seasonId)
  end
  table.sort(items, function(a, b)
    return (a.createdAt or a.timestamp or 0) > (b.createdAt or b.timestamp or 0)
  end)
  return items
end

local function getFilteredHistoryEntries(playerName, seasonId, query, mode)
  local q = string.lower(tostring(query or ""))
  local filtered = {}
  for _, tx in ipairs(getPlayerTransactions(playerName, seasonId, mode)) do
    local line = compactLine(tx)
    if q == "" or string.find(string.lower(line), q, 1, true) then
      table.insert(filtered, { line = line, transaction = tx })
    end
  end
  return filtered
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

local function disputeStatusLabel(request)
  if not request then return "" end
  return tostring(request.status or "Open") .. " | " .. tostring(request.categoryLabel or request.category or "Other")
end

local function playerRequestStatus(status, unavailable)
  if unavailable == "SYNC_BEHIND" then
    return { label = "Syncing guild data", nextAction = "Try again shortly", explanation = "Your request data is catching up. Try again shortly.", tone = "warning" }
  end
  if unavailable == "RECOVERY_PENDING" then
    return { label = "Recovery in progress", nextAction = "Try again later", explanation = "Guild Dibs is restoring your request data.", tone = "warning" }
  end
  if unavailable then
    return { label = "Unavailable", nextAction = "Try again later", explanation = "Your request details are unavailable right now.", tone = "warning" }
  end
  local values = {
    ["Open"] = { label = "Open", nextAction = "Wait for Officer review", explanation = "Your request is waiting for Officer review." },
    ["Under review"] = { label = "Under review", nextAction = "Wait for the decision", explanation = "An Officer is reviewing your request." },
    ["Need information"] = { label = "Need information", nextAction = "Reply to Officer", explanation = "An Officer requested more information before deciding." },
    Resolved = { label = "Resolved", nextAction = "View resolution", explanation = "The Officer completed the review." },
    Rejected = { label = "Rejected", nextAction = "View resolution", explanation = "The Officer rejected the request with an audit reason." },
  }
  local value = values[status] or { label = tostring(status or "Unavailable"), nextAction = "View request", explanation = "Your request status is available." }
  return { label = value.label, nextAction = value.nextAction, explanation = value.explanation, tone = "normal" }
end

---@param filter table|nil Player-scoped request options.
---@return table rows Bounded, safe request rows for the local player.
function Dibs.PlayerUI.BuildRequestView(filter)
  filter = type(filter) == "table" and filter or {}
  if filter.unavailable then
    local status = playerRequestStatus(nil, filter.unavailable)
    return { { status = status, nextAction = status.nextAction, explanation = status.explanation, details = {} } }
  end
  local source = Dibs.Disputes and Dibs.Disputes.ListForPlayer and Dibs.Disputes.ListForPlayer(Dibs.GetPlayerName and Dibs.GetPlayerName() or nil, filter) or {}
  local rows, limit = {}, math.max(1, math.min(50, tonumber(filter.limit) or 25))
  for _, request in ipairs(source or {}) do
    if #rows >= limit then break end
    local status = playerRequestStatus(request.status)
    local evidence = request.evidence and request.evidence[1] or {}
    table.insert(rows, {
      requestId = request.requestId,
      status = status,
      nextAction = status.nextAction,
      explanation = status.explanation,
      details = {
        category = tostring(request.categoryLabel or request.category or "Other"),
        item = tostring(evidence.item or evidence.itemID or "Unavailable"),
        note = tostring(request.note or ""):sub(1, 240),
      },
    })
  end
  return rows
end

---@param playerName string|nil Player identity; defaults to local player.
---@return table summary Player-scoped balance and request summary.
function Dibs.PlayerUI.GetSummary(playerName)
  local season = Dibs.Seasons and Dibs.Seasons.GetCurrent() or nil
  local canonical = Dibs.Ledger and Dibs.Ledger.GetCanonicalPlayerDibsState
    and Dibs.Ledger.GetCanonicalPlayerDibsState(season and season.id, playerName or Dibs.GetPlayerName()) or nil
  local requests = Dibs.PreDibs and Dibs.PreDibs.GetActiveRequests(playerName or Dibs.GetPlayerName()) or {}
  local acquisitions = Dibs.PreDibs and Dibs.PreDibs.GetAcquisitionsForPlayer and Dibs.PreDibs.GetAcquisitionsForPlayer(playerName or Dibs.GetPlayerName()) or {}
  if Dibs.PreDibs and Dibs.PreDibs.ProjectVaultAcquisition then
    local projected = {}
    for _, acquisition in ipairs(acquisitions) do
      local entry = Dibs.PreDibs.ProjectVaultAcquisition(acquisition, "player")
      entry.status = Dibs.PlayerUI.GetVaultAcquisitionPresentation(entry)
      projected[#projected + 1] = entry
    end
    acquisitions = projected
  end
  local eligibility = Dibs.CharacterEligibility and Dibs.CharacterEligibility.GetSummary
    and Dibs.CharacterEligibility.GetSummary(playerName or Dibs.GetPlayerName(), season and season.id) or nil

  return {
    season = season,
    player = playerName or Dibs.GetPlayerName(),
    balance = canonical and canonical.balance or 0,
    balanceState = canonical,
    activePreDibs = requests,
    acquisitions = acquisitions,
    eligibility = eligibility,
    modePolicy = Dibs.PreDibs and Dibs.PreDibs.GetModePolicy and Dibs.PreDibs.GetModePolicy(season and season.id) or nil,
  }
end

local function hasReason(result, code)
  if type(result) ~= "table" then return false end
  if result.reasonCode == code then return true end
  return type(result.reasonCodes) == "table" and result.reasonCodes[code] == true
end

---@doc.id player.status
---@doc.category setup
---@doc.since 0.6.5
---@doc.audience player
---@doc.scope guild
---@doc.audit false
---@doc.help-key UI_HELP_PLAYER_STATUS
---@doc.label-key DOC_PLAYER_STATUS_LABEL
function Dibs.PlayerUI.GetStatusPresentation(result)
  result = type(result) == "table" and result or {}
  if hasReason(result, "RECOVERY_PENDING") then
    return {
      label = "Guild Dibs recovery in progress",
      explanation = "Guild Dibs is restoring its shared state. Your personal data will return when recovery is complete.",
      tone = "warning",
    }
  end
  if hasReason(result, "SYNC_BEHIND") then
    return {
      label = "Syncing guild data",
      explanation = "Your guild Dibs data is catching up. You can try again shortly.",
      tone = "warning",
    }
  end
  if hasReason(result, "COORDINATOR_UNAVAILABLE") then
    return {
      label = "Dibs temporarily unavailable",
      explanation = "Guild Dibs is unavailable right now. Try again later or contact an Officer.",
      tone = "warning",
    }
  end
  local state = tostring(result.status or "Unavailable")
  if state == "Ready" then
    return { label = "Ready", explanation = "Your guild Dibs information is current.", tone = "ready" }
  end
  if state == "Degraded" then
    return {
      label = "Limited availability",
      explanation = "Your personal Dibs information is available, but some live loot features are limited.",
      tone = "warning",
    }
  end
  return {
    label = "Dibs temporarily unavailable",
    explanation = "Guild Dibs is unavailable right now. Try again later or contact an Officer.",
    tone = "warning",
  }
end

local function playerRequestHistory(playerName, activeRequests)
  local history = {}
  local active = {}
  for _, request in ipairs(activeRequests or {}) do
    active[request.requestId] = true
  end
  local source = Dibs.PreDibs and Dibs.PreDibs.GetHistory and Dibs.PreDibs.GetHistory() or {}
  local playerKey = string.lower(tostring(playerName or ""))
  for _, request in ipairs(source) do
    if string.lower(tostring(request.playerName or "")) == playerKey then
      table.insert(history, {
        requestId = request.requestId,
        createdAt = request.createdAt or request.updatedAt,
        item = request.itemName or request.itemLink or ("Item " .. tostring(request.itemID or "?")),
        status = tostring(request.status or "Pending"),
        cancelAllowed = active[request.requestId] == true,
      })
    end
  end
  table.sort(history, function(first, second)
    return (first.createdAt or 0) > (second.createdAt or 0)
  end)
  return history
end

local function projectHistory(playerName, seasonId)
  local entries = getPlayerTransactions(playerName, seasonId, "current")
  local history = {}
  for _, transaction in ipairs(entries) do
    local amount = tonumber(transaction.amount or transaction.quantityDelta) or 0
    table.insert(history, {
      date = formatDate(transaction.createdAt or transaction.timestamp),
      item = transaction.itemName or transaction.itemLink or (transaction.itemID and ("Item " .. tostring(transaction.itemID)) or "Dibs"),
      action = tostring(transaction.type or transaction.actionType or "Activity"),
      result = tostring(transaction.reason or "Recorded"),
      balanceImpact = (amount >= 0 and "+" or "") .. tostring(amount),
    })
  end
  return history
end

function Dibs.PlayerUI.GetViewModel(playerName)
  local summary = Dibs.PlayerUI.GetSummary(playerName)
  local readiness = Dibs.Readiness and Dibs.Readiness.Evaluate and Dibs.Readiness.Evaluate({ allowPlayer = true }) or {}
  local active = {}
  for _, request in ipairs(summary.activePreDibs or {}) do
    table.insert(active, {
      requestId = request.requestId,
      date = formatDate(request.createdAt or request.updatedAt),
      item = request.itemName or request.itemLink or ("Item " .. tostring(request.itemID or "?")),
      status = tostring(request.status or "Pending"),
      difficulty = request.difficulty and tostring(request.difficulty) or nil,
    })
  end
  local history = projectHistory(summary.player, summary.season and summary.season.id)
  local requests = playerRequestHistory(summary.player, summary.activePreDibs)
  return {
    navigation = Dibs.PlayerUI.GetNavigation(),
    player = summary.player,
    balance = summary.balance,
    seasonName = summary.season and summary.season.name or "No active season",
    activePreDibs = active,
    requests = requests,
    pendingRequests = #active,
    history = history,
    status = Dibs.PlayerUI.GetStatusPresentation(readiness),
    empty = {
      activePreDibs = #active == 0 and "No active Pre-Dibs." or nil,
      requests = #requests == 0 and "No requests yet." or nil,
      history = #history == 0 and "No history yet." or nil,
    },
  }
end

---@param itemID integer Item identifier.
---@param difficulty DibsDifficulty|nil Difficulty context.
---@return DibsVaultAcquisition|nil acquisition
---@return string|nil reasonCode
function Dibs.PlayerUI.RecordVaultAcquisition(itemID, difficulty)
  if not (Dibs.PreDibs and Dibs.PreDibs.RecordVaultAcquisition) then return nil, "ACQUISITIONS_UNAVAILABLE" end
  return Dibs.PreDibs.RecordVaultAcquisition(Dibs.GetPlayerName and Dibs.GetPlayerName() or nil, itemID, difficulty)
end

function Dibs.PlayerUI.GetVaultAcquisitionPresentation(record)
  record = type(record) == "table" and record or {}
  local status = tostring(record.verificationState or "UNVERIFIED")
  local label = helpText["VAULT_STATUS_" .. status] or status
  local explanation = record.evidenceState == "COMPLETE"
    and (helpText.VAULT_EVIDENCE_COMPLETE or "The stored Great Vault evidence is complete.")
    or (helpText.VAULT_REASON_EVIDENCE_UNCERTAIN or "Great Vault evidence needs review.")
  return { label = label, explanation = explanation, verificationState = status, source = record.source,
    resetId = record.resetId, syncState = record.syncState }
end

function Dibs.PlayerUI.GetHistory(playerName)
  if not Dibs.Ledger then
    return {}
  end

  return Dibs.Ledger.GetHistory(playerName or Dibs.GetPlayerName())
end

---@param filter table|nil Local player history filters.
---@return table view Player-safe confirmed-history projection.
function Dibs.PlayerUI.BuildHistoryView(filter)
  filter = type(filter) == "table" and filter or {}
  local summary = Dibs.PlayerUI.GetSummary(filter.playerName)
  local entries = projectHistory(summary.player, summary.season and summary.season.id)
  local limit = math.max(1, math.min(50, tonumber(filter.limit) or 25))
  local bounded = {}
  for index, entry in ipairs(entries) do
    if index > limit then break end
    bounded[#bounded + 1] = {
      date = entry.date, item = tostring(entry.item or "Dibs"):sub(1, 180),
      action = entry.action, result = tostring(entry.result or "Recorded"):sub(1, 240),
      balanceImpact = entry.balanceImpact,
    }
  end
  return {
    scope = "player", player = summary.player, seasonName = summary.season and summary.season.name or "No active season",
    entries = bounded, emptyState = #bounded == 0 and "No confirmed Dibs history yet." or nil,
  }
end

local function createLegacyAceWindow()
  local shell = Dibs.AceGUI.CreateWindow("RCLootCouncil - Dibs | Player", 720, 620, { "CENTER", 0, 0 })
  if not shell then return nil end
  local frame = shell.frame
  if frame and frame.SetUserPlaced then frame:SetUserPlaced(true) end
  frame.dibsAceGUIShell = shell
  frame._dibsUiShell = shell
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

  local tabs = Dibs.AceGUI.AddTree(shell, PLAYER_NAV_TREE, function(value)
    frame.playerTab = value
    frame:Refresh()
  end, 170)
  frame.aceTabs = tabs
  frame.SelectTab = function(tab)
    if not Dibs.AceGUI.SelectTree(tabs, tab) then
      frame.playerTab = tab
      frame:Refresh()
    end
  end

  frame.Refresh = function(self)
    Dibs.AceGUI.Clear(tabs)
    local summary = Dibs.PlayerUI.GetSummary()
    if self.playerTab == "requests" then
      -- Keep the report form, request list and details in one bounded page so
      -- the lower controls remain reachable on smaller screens.
      local tabs = Dibs.AceGUI.AddScrollableList(shell, tabs, 535) or tabs
      Dibs.AceGUI.AddHeading(shell, tabs, "RCLootCouncil - Dibs options", helpText.UI_HELP_PLAYER_OVERVIEW)
      local toolbar = Dibs.AceGUI.AddInlineGroup(shell, tabs)
      Dibs.AceGUI.AddButton(shell, toolbar, "Open shared options", function() Dibs.RCOptions.Open() end, 170)
      Dibs.AceGUI.AddHeader(shell, tabs, "Report a problem", "Report a Dibs or loot history problem and follow its resolution.")
      Dibs.AceGUI.AddLabel(shell, tabs, "My review requests", true)
      local categories = sortedLabels(Dibs.Disputes and Dibs.Disputes.GetCategories and Dibs.Disputes.GetCategories() or { other = "Other" })
      local transactions = getPlayerTransactions(summary.player, summary.season and summary.season.id, self.historyMode)
      local transactionChoices = { [""] = "General request (no transaction)" }
      for _, tx in ipairs(transactions) do
        local id = tostring(tx.transactionId or "")
        if id ~= "" then transactionChoices[id] = compactLine(tx) end
      end
      self.disputeCategory = self.disputeCategory or "other"
      self.disputeTransactionId = self.disputeTransactionId or ""
      self.disputeNote = self.disputeNote or ""
      local category = Dibs.AceGUI.AddDropdown(shell, tabs, "Problem type", categories, function(value)
        self.disputeCategory = value
      end, 420)
      Dibs.AceGUI.SetValue(category, self.disputeCategory)
      local transaction = Dibs.AceGUI.AddDropdown(shell, tabs, "Related ledger entry (optional)", transactionChoices, function(value)
        self.disputeTransactionId = value or ""
      end, 560)
      Dibs.AceGUI.SetValue(transaction, self.disputeTransactionId)
      local note = Dibs.AceGUI.AddEditBox(shell, tabs, "What should an Officer review?", function(value)
        self.disputeNote = value or ""
      end, 560)
      setControlText(note, self.disputeNote)
      local submit = Dibs.AceGUI.AddButton(shell, tabs, "Submit request", function()
        local payload = {
          category = self.disputeCategory,
          note = self.disputeNote,
          playerName = summary.player,
          seasonId = summary.season and summary.season.id or nil,
        }
        if self.disputeTransactionId ~= "" then payload.transactionRef = self.disputeTransactionId end
        ---@type table
        local reportResult = {}
        if Dibs.Disputes and Dibs.Disputes.CreateReport then
          reportResult = { Dibs.Disputes.CreateReport(payload) }
        end
        local request = reportResult[1]
        local reason = reportResult[2] or "DISPUTES_UNAVAILABLE"
        if request then
          self.disputeStatusText = "Request " .. tostring(request.requestId) .. " submitted. Officers can now review it."
          self.disputeNote = ""
          self.disputeTransactionId = ""
        else
          self.disputeStatusText = "Unable to submit request: " .. tostring(reason or "unknown error")
        end
        self:Refresh()
      end, 150)
      Dibs.AceGUI.SetDisabled(submit, not (Dibs.Disputes and Dibs.Disputes.CreateReport))
      Dibs.AceGUI.AddLabel(shell, tabs, self.disputeStatusText or "Requests are visible only to you and guild Officers.", true)

      local requests, requestReason = {}, nil
      if Dibs.Disputes and Dibs.Disputes.ListForPlayer then
        requests, requestReason = Dibs.Disputes.ListForPlayer(summary.player)
      end
      local requestProjection = Dibs.PlayerUI.BuildRequestView({ limit = 50 })
      if requestReason then
        requestProjection = Dibs.PlayerUI.BuildRequestView({ unavailable = requestReason })
      end
      local projectedById = {}
      for _, projected in ipairs(requestProjection) do projectedById[projected.requestId] = projected end
      local requestRows = {}
      if #requestProjection == 0 then
        requestRows[1] = { "", "No requests yet.", "", "", "" }
      else
        for _, request in ipairs(requests) do
          local projected = projectedById[request.requestId] or {
            status = { label = "Unavailable" }, explanation = "Request details are unavailable right now.", details = {},
          }
          requestRows[#requestRows + 1] = {
            formatDate(request.createdAt or request.updatedAt),
            tostring(request.requestId),
            projected.status.label,
            projected.explanation,
            "",
            request = request,
          }
        end
      end
      Dibs.AceGUI.AddTable(shell, tabs, {
        { title = "Date", width = 145, tooltip = helpText.UI_HELP_DATE },
        { title = "Request", width = 160, tooltip = helpText.UI_HELP_REQUEST_ID },
        { title = "Status", width = 180, tooltip = helpText.UI_HELP_REQUEST_STATUS },
        { title = "Next step", width = 220, tooltip = helpText.UI_HELP_NEXT_STEP },
        { title = "Action", width = 80, tooltip = helpText.UI_HELP_ACTION },
      }, requestRows, 230, function(row)
        if not row.request then return nil end
        return {
          text = "View",
          callback = function()
            self.selectedDisputeRequestId = row.request.requestId
            self:Refresh()
          end,
        }
      end)

      if self.selectedDisputeRequestId then
        local selected = Dibs.Disputes.GetRequest(self.selectedDisputeRequestId, summary.player)
        if selected then
          Dibs.AceGUI.AddHeader(shell, tabs, "Request details", disputeStatusLabel(selected))
          local evidence = selected.evidence and selected.evidence[1] or {}
          Dibs.AceGUI.AddPropertyTable(shell, tabs, {
            { "Status", tostring(selected.status) },
            { "Category", tostring(selected.categoryLabel or selected.category) },
            { "Item", tostring(evidence.item or selected.attachedContext and selected.attachedContext.item or "Unavailable") },
            { "Evidence", tostring(evidence.source or "unavailable") },
            { "Note", tostring(selected.note or "") },
          }, 180)
          if selected.question and selected.status == "Need information" then
            Dibs.AceGUI.AddLabel(shell, tabs, "Officer question: " .. tostring(selected.question), true)
            self.disputeReply = self.disputeReply or ""
            local reply = Dibs.AceGUI.AddEditBox(shell, tabs, "Reply", function(value) self.disputeReply = value or "" end, 560)
            setControlText(reply, self.disputeReply)
            Dibs.AceGUI.AddButton(shell, tabs, "Send reply", function()
              local result, reason = Dibs.Disputes.AddReply(self.selectedDisputeRequestId, self.disputeReply, summary.player)
              self.disputeStatusText = result and "Reply sent to the Officer queue." or ("Unable to reply: " .. tostring(reason or "unknown error"))
              if result then self.disputeReply = "" end
              self:Refresh()
            end, 120)
          end
          local timeline = Dibs.Disputes.GetTimeline(self.selectedDisputeRequestId, summary.player) or {}
          local timelineRows = {}
          for _, event in ipairs(timeline) do
            timelineRows[#timelineRows + 1] = { formatDate(event.timestamp or event.createdAt), tostring(event.action or ""), tostring(event.newStatus or ""), tostring(event.reason or "") }
          end
          if #timelineRows > 0 then
            Dibs.AceGUI.AddTable(shell, tabs, {
              { title = "Date", width = 145, tooltip = helpText.UI_HELP_DATE },
              { title = "Event", width = 160, tooltip = helpText.UI_HELP_EVENT },
              { title = "Status", width = 140, tooltip = helpText.UI_HELP_REQUEST_STATUS },
              { title = "Details", width = 260, tooltip = helpText.UI_HELP_DETAILS },
            }, timelineRows, 170)
          end
        end
      end
      return
    end
    Dibs.AceGUI.AddHeading(shell, tabs, "RCLootCouncil - Dibs options", helpText.UI_HELP_PLAYER_OVERVIEW)
    local toolbar = Dibs.AceGUI.AddInlineGroup(shell, tabs)
    Dibs.AceGUI.AddButton(shell, toolbar, "Open shared options", function() Dibs.RCOptions.Open() end, 170)
    if self.playerTab == "history" then
      Dibs.AceGUI.AddLabel(shell, tabs, "History (condensed)", true)
      Dibs.AceGUI.AddButton(shell, tabs, "Report a problem", function()
        self.playerTab = "requests"
        self.disputeTransactionId = ""
        self:Refresh()
      end, 150)
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
      Dibs.AceGUI.AddTooltip(modeButton, "History scope", helpText.UI_HELP_HISTORY_SCOPE)
      Dibs.AceGUI.AddButton(shell, tabs, "Clear", function()
        self.historyQuery = ""
        self.historyPage = 1
        self:Refresh()
      end, 70)
      local historyEntries = getFilteredHistoryEntries(summary.player, summary.season and summary.season.id, self.historyQuery, self.historyMode)
      local pageSize = 9
      local totalPages = math.max(1, math.ceil(#historyEntries / pageSize))
      self.historyPage = math.min(math.max(1, self.historyPage), totalPages)
      local visible = {}
      for index = ((self.historyPage - 1) * pageSize) + 1, math.min(#historyEntries, self.historyPage * pageSize) do
        table.insert(visible, historyEntries[index])
      end
      local rows = {}
      for _, entry in ipairs(visible) do
        local row = splitPipeLine(entry.line)
        row.transaction = entry.transaction
        table.insert(rows, row)
      end
    if #rows == 0 then rows[1] = { "No matching history." } end
      self.aceHistoryScroll = Dibs.AceGUI.AddTable(shell, tabs, {
        { title = "Date", width = 145, tooltip = helpText.UI_HELP_AUDIT_HISTORY },
        { title = "Action", width = 150, tooltip = helpText.UI_HELP_AUDIT_HISTORY },
        { title = "Amount", width = 70, tooltip = helpText.UI_HELP_AUDIT_HISTORY },
        { title = "Reason", width = 170, tooltip = helpText.UI_HELP_AUDIT_HISTORY },
      }, rows, 320, function(row)
        if not row.transaction then return nil end
        return {
          text = "Report",
          callback = function()
            self.disputeTransactionId = row.transaction.transactionId or ""
            self.playerTab = "requests"
            self:Refresh()
          end,
        }
      end)
      local pageControls = Dibs.AceGUI.AddInlineGroup(shell, tabs)
      local previous = Dibs.AceGUI.AddButton(shell, pageControls, "Previous", function()
        self.historyPage = math.max(1, self.historyPage - 1)
        self:Refresh()
      end, 90)
      local pageLabel = Dibs.AceGUI.AddLabel(shell, pageControls, "Page " .. tostring(self.historyPage) .. "/" .. tostring(totalPages))
      local nextButton = Dibs.AceGUI.AddButton(shell, pageControls, "Next", function()
        self.historyPage = math.min(totalPages, self.historyPage + 1)
        self:Refresh()
      end, 70)
      Dibs.AceGUI.SetDisabled(previous, self.historyPage <= 1)
      Dibs.AceGUI.SetDisabled(nextButton, self.historyPage >= totalPages)
      Dibs.AceGUI.AddTooltip(pageLabel, "Page", "Current page and total number of pages.")
      return
    end

    Dibs.AceGUI.AddHeader(shell, tabs, "Season summary", "Your current season balance and Pre-Dib status.")
    local integration = Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetLocalStatus and Dibs.RCLootCouncil.GetLocalStatus() or nil
    if integration then
      local integrationState = integration.availability == "operational" or integration.status == "Ready" and { status = "Ready" }
        or integration.availability == "degraded" and { status = "Degraded" }
        or { status = "Unavailable" }
      local integrationView = Dibs.PlayerUI.GetStatusPresentation(integrationState)
      local integrationBadge = Dibs.Midnight.AddStatusBadge(shell, tabs, integrationView.tone, "RCLootCouncil: " .. integrationView.label)
      Dibs.AceGUI.AddLabel(shell, tabs, integrationView.explanation, true)
      Dibs.AceGUI.AddTooltip(integrationBadge, "RCLootCouncil status", helpText.UI_HELP_PLAYER_STATUS)
    end
    if Dibs.Readiness and type(Dibs.Readiness.Evaluate) == "function" then
      local readiness = Dibs.Readiness.Evaluate({ allowPlayer = true })
      local readinessView = Dibs.PlayerUI.GetStatusPresentation(readiness)
      Dibs.Midnight.AddStatusBadge(shell, tabs, readinessView.tone, "Raid readiness: " .. readinessView.label)
      local readinessExplanation = Dibs.AceGUI.AddLabel(shell, tabs, readinessView.explanation ..
        " Live Dibs consumption: " .. (readiness and readiness.liveConsumptionAllowed and "allowed after revalidation" or "blocked or unavailable"), true)
      Dibs.AceGUI.AddTooltip(readinessExplanation, "Raid readiness", helpText.UI_HELP_PLAYER_READINESS)
    end
    Dibs.AceGUI.AddTable(shell, tabs, {
      { title = "Metric", width = 180, tooltip = "Summary field." },
      { title = "Value", width = 280, tooltip = "Current value." },
    }, {
      { "Season", tostring(summary.season and summary.season.name or "None") },
      { "Balance", tostring(summary.balance) },
      { "Active Pre-Dibs", tostring(#(summary.activePreDibs or {})) },
      { "Vault acquisitions", tostring(#(summary.acquisitions or {})) },
      { "Pre-Dib mode", tostring(summary.modePolicy and summary.modePolicy.mode or "WILD_OPEN") },
      { "Protected-loot group", tostring(summary.eligibility and summary.eligibility.groupId or "Not linked") },
      { "Main-change probation", tostring(summary.eligibility and summary.eligibility.probation and ("Until " .. tostring(summary.eligibility.probation.probationEndsAt)) or "None") },
    }, 145)
    if summary.eligibility then
      local protectedRows = {}
      for _, family in ipairs({ "TOKEN", "TOKEN_SET" }) do
        local policy = summary.eligibility.policies and summary.eligibility.policies[family]
        local count = 0
        for _, acquisition in ipairs(summary.eligibility.acquisitions or {}) do
          if acquisition.family == family then count = count + 1 end
        end
        protectedRows[#protectedRows + 1] = { family == "TOKEN" and "Curio" or "Tier Set", tostring(count), tostring(policy and policy.difficultyScope or "ALL"), tostring(policy and (policy.enabled and "Enabled" or "Disabled") or "Unknown") }
      end
      Dibs.AceGUI.AddHeader(shell, tabs, "Protected-loot status", "Only finalized acquisitions and approved character links affect these counts.")
      Dibs.AceGUI.AddTable(shell, tabs, {
        { title = "Family", width = 160, tooltip = "Tracked protected-loot family." },
        { title = "Acquired", width = 90, tooltip = "Confirmed acquisitions for your linked group." },
        { title = "Scope", width = 120, tooltip = "Difficulty scope in the active policy." },
        { title = "Status", width = 150, tooltip = "Current policy status." },
      }, protectedRows, 100)
      local relationshipCount = #(summary.eligibility.relationships or {})
      Dibs.AceGUI.AddLabel(shell, tabs, "Character links: " .. tostring(relationshipCount) .. " record(s). Pending links do not affect enforcement.", true)
      local relationshipSection = Dibs.AceGUI.AddSection(shell, tabs, "Main / alt declarations", "Choose a guild character. Officers must approve the declaration before it affects protected-loot priority.")
      local characterChoices = getGuildCharacterChoices()
      self.eligibilityCharacter = self.eligibilityCharacter or next(characterChoices)
      local characterChoice = Dibs.AceGUI.AddDropdown(shell, relationshipSection, "Guild character", characterChoices, function(value)
        self.eligibilityCharacter = value
      end, 260)
      Dibs.AceGUI.SetValue(characterChoice, self.eligibilityCharacter)
      local declare = Dibs.AceGUI.AddButton(shell, relationshipSection, "Declare alt", function()
        local alt = self.eligibilityCharacter
        local relationship = alt and Dibs.CharacterEligibility and Dibs.CharacterEligibility.DeclareRelationship and Dibs.CharacterEligibility.DeclareRelationship({
          seasonId = summary.season and summary.season.id, mainCharacter = Dibs.GetPlayerName(), altCharacter = alt,
        }) or nil
        self.eligibilityStatus = relationship and "Declaration submitted for Officer approval." or "Choose a guild character before submitting."
        self:Refresh()
      end, 130)
      local requestMain = Dibs.AceGUI.AddButton(shell, relationshipSection, "Request main change", function()
        local newMain = self.eligibilityCharacter
        local request = newMain and Dibs.CharacterEligibility and Dibs.CharacterEligibility.RequestMainChange and Dibs.CharacterEligibility.RequestMainChange({
          seasonId = summary.season and summary.season.id, oldMain = Dibs.GetPlayerName(), newMain = newMain,
          reason = "Player requested a main-character change",
        }) or nil
        self.eligibilityStatus = request and "Main-change request submitted for Officer approval." or "Choose a guild character before submitting."
        self:Refresh()
      end, 170)
      Dibs.AceGUI.SetDisabled(declare, next(characterChoices) == nil)
      Dibs.AceGUI.SetDisabled(requestMain, next(characterChoices) == nil)
      Dibs.AceGUI.AddLabel(shell, relationshipSection, self.eligibilityStatus or "Declarations stay pending until an Officer reviews them.", true)
    end
    Dibs.AceGUI.AddLabel(shell, tabs, "My active Pre-Dibs", true)
    local activeRows = {}
    if #(summary.activePreDibs or {}) == 0 then
      activeRows[1] = { "", "No active Pre-Dibs.", "", "", "" }
    else
      for _, request in ipairs(summary.activePreDibs) do
        activeRows[#activeRows + 1] = {
          formatDate(request.createdAt or request.updatedAt),
          tostring(request.itemName or request.itemLink or ("Item " .. tostring(request.itemID))),
          tostring(request.difficulty or "Normal"),
          tostring(request.status),
          "",
          request = request,
        }
      end
    end
    Dibs.AceGUI.AddTable(shell, tabs, {
      { title = "Date", width = 145, tooltip = "When the Pre-Dib was created." },
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
    Dibs.AceGUI.AddTooltip(self.preDibInput, "Pre-Dib", helpText.UI_HELP_PREDIB_FIELD)
    setControlText(self.preDibInput, self.preDibValue or "")
    self.preDibButton = Dibs.AceGUI.AddButton(shell, tabs, "I want to DIB this", submitFromInput, 170)
    Dibs.AceGUI.AddTooltip(self.preDibButton, "Pre-Dib", helpText.UI_HELP_PREDIB_SUBMIT)
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
  Dibs.AceGUI.SelectTree(tabs, frame.playerTab)
  return frame
end

local function createAceWindow()
  local shell = Dibs.AceGUI.CreateWindow("Dibs | My Dibs", 720, 620, { "CENTER", 0, 0 }, "PlayerWindowPosition")
  if not shell then return nil end
  local frame = shell.frame
  if frame and frame.SetUserPlaced then frame:SetUserPlaced(true) end
  frame.dibsAceGUIShell = shell
  frame.playerTab = "my-dibs"
  frame.preDibValue = ""
  frame.preDibStatusText = nil

  local tabs = Dibs.AceGUI.AddTree(shell, Dibs.PlayerUI.GetNavigation(), function(value)
    frame.playerTab = value
    frame:Refresh()
  end, 170)
  frame.aceTabs = tabs
  frame.SelectTab = function(tab)
    frame.playerTab = tab
    if not Dibs.AceGUI.SelectTree(tabs, tab) then frame:Refresh() end
  end

  local MATRIX_CHANNELS = {
    { key = "GUILD", title = "Guild" }, { key = "OFFICER", title = "Officer" },
    { key = "RAID", title = "Raid" }, { key = "PARTY", title = "Party" },
    { key = "INSTANCE_CHAT", title = "Instance" }, { key = "WHISPER", title = "Whisper" },
    { key = "CHANNEL", title = "Custom" },
  }
  local AUTO_PING_INTERVAL = 300
  local function canAutoPing()
    local role = Dibs.Permissions and Dibs.Permissions.GetGuildRole and Dibs.Permissions.GetGuildRole(nil)
    return role == "gm" or role == "officer"
  end
  local function stopAutoPing()
    frame.channelTestAutoPingGeneration = (frame.channelTestAutoPingGeneration or 0) + 1
    frame.channelTestAutoPingScheduled = false
  end
  local function autoPingIsActive()
    return frame.channelTestAutoPingEnabled == true and frame.playerTab == "diagnostics"
      and Dibs.DeveloperMode and Dibs.DeveloperMode.IsEnabled and Dibs.DeveloperMode.IsEnabled()
      and canAutoPing() and shell._dibsActive == true
      and (not frame.IsShown or frame:IsShown())
  end
  local function runAvailableChannelTests()
    local results = Dibs.Sync and Dibs.Sync.RunAvailableChannelTests and Dibs.Sync.RunAvailableChannelTests() or {}
    local queued = 0
    for _, result in ipairs(results) do if result.sent then queued = queued + 1 end end
    frame.channelTestStatus = string.format("Queued %d available channel probe(s).", queued)
  end
  local function scheduleAutoPing()
    if not autoPingIsActive() or frame.channelTestAutoPingScheduled then return end
    if not (Dibs.Ace3 and Dibs.Ace3.ScheduleTimer) then return end
    frame.channelTestAutoPingScheduled = true
    local generation = frame.channelTestAutoPingGeneration or 0
    Dibs.Ace3.ScheduleTimer(function()
      if generation ~= frame.channelTestAutoPingGeneration then return end
      frame.channelTestAutoPingScheduled = false
      if not autoPingIsActive() then return end
      runAvailableChannelTests()
      frame:Refresh()
    end, AUTO_PING_INTERVAL)
  end

  local function submitFromInput()
    local request, errorText = submitPublicPreDib(getControlText(frame.preDibInput))
    if request then
      setControlText(frame.preDibInput, "")
      frame.preDibValue = ""
      frame.preDibStatusText = "Request submitted for " .. tostring(request.itemName or request.itemLink or ("Item " .. tostring(request.itemID))) .. "."
    else
      frame.preDibStatusText = errorText or "Unable to submit the request."
    end
    frame:Refresh()
  end

  local function addRequestAction(parent, view)
    Dibs.AceGUI.AddHeader(shell, parent, "Request a Pre-Dib", helpText.UI_HELP_PREDIB)
    frame.preDibInput = Dibs.AceGUI.AddEditBox(shell, parent, "Item ID or item link", function(value)
      frame.preDibValue = value or ""
    end, 300)
    Dibs.AceGUI.AddTooltip(frame.preDibInput, "Pre-Dib", helpText.UI_HELP_PREDIB_FIELD)
    setControlText(frame.preDibInput, frame.preDibValue)
    local submit = Dibs.AceGUI.AddButton(shell, parent, "Submit request", submitFromInput, 150)
    Dibs.AceGUI.AddTooltip(submit, "Pre-Dib", helpText.UI_HELP_PREDIB_SUBMIT)
    local publicEnabled = Dibs.PreDibs and Dibs.PreDibs.IsPublicEnabled and Dibs.PreDibs.IsPublicEnabled() or false
    Dibs.AceGUI.SetDisabled(submit, not publicEnabled)
    Dibs.AceGUI.AddLabel(shell, parent, frame.preDibStatusText or (publicEnabled
      and "Public Pre-Dibs are enabled."
      or "Public Pre-Dibs are currently disabled by Officers."), true)
  end

  frame.Refresh = function(self)
    Dibs.AceGUI.Clear(tabs)
    local view = Dibs.PlayerUI.GetViewModel()
    if self.playerTab ~= "diagnostics" then stopAutoPing() end
    if self.playerTab == "diagnostics" then
      Dibs.AceGUI.AddHeading(shell, tabs, "Diagnostics", "Local sync transport tests and debug controls.")
      self.guildScopeLabel = Dibs.AceGUI.AddLabel(shell, tabs,
        "Guild sync scope: " .. tostring(Dibs.GetGuildKey and Dibs.GetGuildKey() or "unknown"), true)
      local devEnabled = Dibs.DeveloperMode and Dibs.DeveloperMode.IsEnabled and Dibs.DeveloperMode.IsEnabled() or false
      self.developerModeToggle = Dibs.AceGUI.AddCheckBox(shell, tabs, "Enable Developer Mode", devEnabled, function(value)
        if Dibs.DeveloperMode and Dibs.DeveloperMode.SetEnabled then Dibs.DeveloperMode.SetEnabled(value) end
        if not value then
          self.channelTestAutoPingEnabled = false
          stopAutoPing()
        end
        self:Refresh()
      end, 240)
      local receivedProbe
      local channelResults = Dibs.Sync and Dibs.Sync.GetChannelTestResults and Dibs.Sync.GetChannelTestResults() or {}
      for _, result in ipairs(channelResults) do
        if result.direction == "RECEIVE" then receivedProbe = result; break end
      end
      if receivedProbe then
        local receivedAt = tonumber(receivedProbe.startedAt)
        local receivedTime = receivedAt and type(date) == "function" and date("%H:%M:%S", receivedAt) or "unknown time"
        self.channelTestReceivedStatus = Dibs.AceGUI.AddLabel(shell, tabs, string.format("Last received probe: %s from %s at %s (%s).",
          tostring(receivedProbe.channel or "unknown channel"), tostring(receivedProbe.peer or "unknown sender"),
          receivedTime, tostring(receivedProbe.reasonCode or receivedProbe.status or "unknown result")), true)
      end
      if not devEnabled then
        Dibs.AceGUI.AddLabel(shell, tabs, "Enable Developer Mode on both the sender and any client expected to reply. This setting is also controlled by /dibs dev on and /dibs dev off.", true)
        return
      end

      local channelTest = Dibs.AceGUI.AddSection(shell, tabs, "Transport channel test",
        "Sends a harmless probe on the selected channel. A matching ACK confirms that another guild member received it.")
      local channelOptions = {
        GUILD = "Guild", OFFICER = "Guild officers", RAID = "Raid", PARTY = "Party",
        INSTANCE_CHAT = "Instance group", WHISPER = "Whisper", CHANNEL = "Custom joined channel",
      }
      self.channelTestChannel = self.channelTestChannel or "GUILD"
      self.channelTestSelector = Dibs.AceGUI.AddDropdown(shell, channelTest, "Channel", channelOptions, function(value)
        self.channelTestChannel = value
        self:Refresh()
      end, 220)
      Dibs.AceGUI.SetValue(self.channelTestSelector, self.channelTestChannel)
      if self.channelTestChannel == "WHISPER" then
        self.channelTestTargetInput = Dibs.AceGUI.AddEditBox(shell, channelTest, "GM or Officer target", function(value)
          self.channelTestTarget = value or ""
        end, 260)
        setControlText(self.channelTestTargetInput, self.channelTestTarget or "")
      elseif self.channelTestChannel == "CHANNEL" then
        self.channelTestCustomChannelInput = Dibs.AceGUI.AddEditBox(shell, channelTest, "Joined channel name", function(value)
          self.channelTestCustomChannelName = value or ""
        end, 260)
        setControlText(self.channelTestCustomChannelInput, self.channelTestCustomChannelName or "")
      end
      self.channelTestRunButton = Dibs.AceGUI.AddButton(shell, channelTest, "Test selected channel", function()
        local target = self.channelTestChannel == "CHANNEL" and self.channelTestCustomChannelName or self.channelTestTarget
        local sent, result = false, "SYNC_UNAVAILABLE"
        if Dibs.Sync and type(Dibs.Sync.StartChannelTest) == "function" then
          sent, result = Dibs.Sync.StartChannelTest(self.channelTestChannel or "GUILD", target)
        end
        self.channelTestStatus = sent and ("Probe queued: " .. tostring(self.channelTestChannel or "GUILD") .. " / " .. tostring(result))
          or ("Probe not sent: " .. tostring(result or "SYNC_UNAVAILABLE"))
        self:Refresh()
      end, 190)
      self.channelTestScanButton = Dibs.AceGUI.AddButton(shell, channelTest, "Ping available channels", function()
        runAvailableChannelTests()
        self:Refresh()
      end, 210)
      self.channelTestRefreshButton = Dibs.AceGUI.AddButton(shell, channelTest, "Refresh results", function()
        self:Refresh()
      end, 130)
      if self.channelTestStatus then Dibs.AceGUI.AddLabel(shell, channelTest, self.channelTestStatus, true) end
      if canAutoPing() then
        self.channelTestAutoPingToggle = Dibs.AceGUI.AddCheckBox(shell, channelTest,
          "Auto-ping available channels every 5 minutes", self.channelTestAutoPingEnabled == true, function(value)
            self.channelTestAutoPingEnabled = value == true
            stopAutoPing()
            if value then runAvailableChannelTests() end
            self:Refresh()
          end, 330)
        Dibs.AceGUI.AddTooltip(self.channelTestAutoPingToggle, "Automatic channel check",
          "Only this GM/Officer client starts periodic probes. Disable it or leave Diagnostics to stop automatic checks.")
      else
        Dibs.AceGUI.AddLabel(shell, channelTest, "Automatic probing is controlled by a GM or Officer. You can run a manual check here.", true)
      end
      Dibs.AceGUI.AddLabel(shell, channelTest,
        "Green = pong and local receipt time. Yellow = waiting. Orange = no pong after the response window (not proof of offline). Gray = not applicable, not tested, or offline. Blue = this client. Only Developer Mode clients reply.", true)

      local latestByChannel, roster, seenMembers = {}, {}, {}
      local testResults = Dibs.Sync and Dibs.Sync.GetChannelTestResults and Dibs.Sync.GetChannelTestResults() or {}
      for _, result in ipairs(testResults) do
        if result.direction == "SEND" and not latestByChannel[result.channel] then latestByChannel[result.channel] = result end
      end
      local function playerKey(name)
        if Dibs.Identity and Dibs.Identity.CanonicalMemberKey then
          local key = Dibs.Identity.CanonicalMemberKey(name)
          if key then return string.lower(tostring(key)) end
        end
        if Dibs.Identity and Dibs.Identity.CanonicalPlayerId then
          local key = Dibs.Identity.CanonicalPlayerId(name)
          if key then return string.lower(tostring(key)) end
        end
        return string.lower(trimText(name))
      end
      local localPlayerName = Dibs.GetPlayerName and Dibs.GetPlayerName() or ""
      local localPlayerKey = playerKey(localPlayerName)
      local memberCount = 0
      if type(_G.GetNumGuildMembers) == "function" and type(_G.GetGuildRosterInfo) == "function" then
        local ok, count = pcall(_G.GetNumGuildMembers, true)
        memberCount = ok and (tonumber(count) or 0) or 0
        for index = 1, memberCount do
          local details = { pcall(_G.GetGuildRosterInfo, index) }
          local name = details[1] and trimText(details[2]) or ""
          if Dibs.Identity and Dibs.Identity.NormalizeDisplayName then
            name = Dibs.Identity.NormalizeDisplayName(name) or name
          end
          local key = name ~= "" and playerKey(name) or ""
          if key ~= "" and not seenMembers[key] then
            seenMembers[key] = true
            roster[#roster + 1] = { name = name, rawName = details[2], key = key, online = details[10] ~= false,
              isLocal = key == localPlayerKey }
          end
        end
      end
      if localPlayerKey ~= "" and not seenMembers[localPlayerKey] then
        local displayName = Dibs.Identity and Dibs.Identity.NormalizeDisplayName
          and Dibs.Identity.NormalizeDisplayName(localPlayerName) or localPlayerName
        roster[#roster + 1] = { name = tostring(displayName), key = localPlayerKey, online = true, isLocal = true }
      end

      local resultByChannel = {}
      for _, definition in ipairs(MATRIX_CHANNELS) do
        local result = latestByChannel[definition.key]
        local responders = {}
        for _, responder in ipairs(result and result.responders or {}) do
          if responder.memberKey then responders["id:" .. string.lower(tostring(responder.memberKey))] = responder end
          if responder.player then responders["name:" .. playerKey(responder.player)] = responder end
        end
        resultByChannel[definition.key] = { result = result, responders = responders }
      end
      local function groupMembership(member, channelKey)
        local inRaid = type(_G.IsInRaid) == "function" and _G.IsInRaid() == true
        local inGroup = type(_G.IsInGroup) == "function" and _G.IsInGroup() == true
        if channelKey == "RAID" and not inRaid then return false end
        if channelKey == "PARTY" and (not inGroup or inRaid) then return false end
        if channelKey == "INSTANCE_CHAT" then
          local instanceGroup = type(_G.IsInGroup) == "function" and _G.LE_PARTY_CATEGORY_INSTANCE ~= nil
            and _G.IsInGroup(_G.LE_PARTY_CATEGORY_INSTANCE) == true
          if not instanceGroup then return false end
        end
        if inRaid and type(_G.GetNumGroupMembers) == "function" and type(_G.GetRaidRosterInfo) == "function" then
          for index = 1, tonumber(_G.GetNumGroupMembers()) or 0 do
            local details = { pcall(_G.GetRaidRosterInfo, index) }
            local name = details[1] and trimText(details[2]) or ""
            if name ~= "" and playerKey(name) == member.key then return true end
          end
          return false
        end
        if not inRaid and type(_G.UnitName) == "function" then
          for index = 1, 4 do
            local name = trimText(_G.UnitName("party" .. index))
            if name ~= "" and playerKey(name) == member.key then return true end
          end
          if type(_G.GetNumSubgroupMembers) == "function" then return false end
        end
        return nil
      end
      local function channelApplies(member, channelKey, result)
        if channelKey == "OFFICER" then
          if not (Dibs.Permissions and Dibs.Permissions.GetGuildRole) then return nil end
          local role = Dibs.Permissions.GetGuildRole(member.rawName or member.name)
          return role == "gm" or role == "officer"
        end
        if channelKey == "WHISPER" then
          return result.target ~= nil and playerKey(result.target) == member.key
        end
        if channelKey == "RAID" or channelKey == "PARTY" or channelKey == "INSTANCE_CHAT" then
          return groupMembership(member, channelKey)
        end
        if channelKey == "CHANNEL" then return false end
        return true
      end
      local function statusFor(member, channelKey)
        local channelResult = resultByChannel[channelKey]
        local result = channelResult and channelResult.result
        if not result then return "|cff808080--|r" end
        if member.isLocal then return "|cff00bfffYOU|r" end
        local responder = channelResult.responders["id:" .. member.key] or channelResult.responders["name:" .. member.key]
        if responder then
          local receivedAt = tonumber(responder.receivedAt)
          local receivedTime = receivedAt and type(date) == "function" and date("%H:%M", receivedAt)
          return "|cff00ff00PONG" .. (receivedTime and ("\n" .. receivedTime) or "") .. "|r"
        end
        if not channelApplies(member, channelKey, result) then return "|cff808080--|r" end
        if not member.online then return "|cff808080OFF|r" end
        if result.ackWindowOpen or result.status == "WAITING_FOR_ACK" then return "|cffffff00WAIT|r" end
        if result.status == "SEND_FAILED" or result.status == "NOT_SENT" then return "|cff808080ERR|r" end
        return "|cffff9900NO PONG|r"
      end
      local allRows = {}
      for _, member in ipairs(roster) do
        local row = { member.name }
        for _, definition in ipairs(MATRIX_CHANNELS) do row[#row + 1] = statusFor(member, definition.key) end
        allRows[#allRows + 1] = row
      end
      local totalPages = math.max(1, math.ceil(#allRows / 20))
      self.channelTestMatrixPage = math.min(math.max(1, self.channelTestMatrixPage or 1), totalPages)
      local startIndex = ((self.channelTestMatrixPage - 1) * 20) + 1
      self.channelTestMatrixRows = {}
      for index = startIndex, math.min(#allRows, startIndex + 19) do
        self.channelTestMatrixRows[#self.channelTestMatrixRows + 1] = allRows[index]
      end
      if #allRows == 0 then self.channelTestMatrixRows[1] = { "Guild roster unavailable", "--", "--", "--", "--", "--", "--", "--" } end
      self.channelTestMatrix = Dibs.AceGUI.AddTable(shell, channelTest, {
        { title = "Player", width = 125, minWidth = 120 },
        { title = "Guild", width = 58, minWidth = 52, wrap = true },
        { title = "Officer", width = 65, minWidth = 55, wrap = true },
        { title = "Raid", width = 50, minWidth = 48, wrap = true },
        { title = "Party", width = 55, minWidth = 50, wrap = true },
        { title = "Instance", width = 66, minWidth = 58, wrap = true },
        { title = "Whisper", width = 65, minWidth = 58, wrap = true },
        { title = latestByChannel.CHANNEL and latestByChannel.CHANNEL.channelName or "Custom",
          width = 65, minWidth = 58, wrap = true },
      }, self.channelTestMatrixRows, 300, nil, { fluidColumns = true, widthHint = 520 })
      local pagination = Dibs.AceGUI.AddInlineGroup(shell, channelTest)
      self.channelTestPrevious = Dibs.AceGUI.AddButton(shell, pagination, "Previous", function()
        self.channelTestMatrixPage = math.max(1, self.channelTestMatrixPage - 1)
        self:Refresh()
      end, 100)
      self.channelTestPageLabel = Dibs.AceGUI.AddLabel(shell, pagination,
        string.format("Page %d / %d (%d guild members)", self.channelTestMatrixPage, totalPages, #allRows))
      self.channelTestNext = Dibs.AceGUI.AddButton(shell, pagination, "Next", function()
        self.channelTestMatrixPage = math.min(totalPages, self.channelTestMatrixPage + 1)
        self:Refresh()
      end, 100)
      Dibs.AceGUI.SetDisabled(self.channelTestPrevious, self.channelTestMatrixPage <= 1)
      Dibs.AceGUI.SetDisabled(self.channelTestNext, self.channelTestMatrixPage >= totalPages)
      local summaries = {}
      for _, definition in ipairs(MATRIX_CHANNELS) do
        local result = resultByChannel[definition.key].result
        local pongCount = result and #(result.responders or {}) or 0
        summaries[#summaries + 1] = definition.title .. ": " .. (result
          and (tostring(pongCount) .. " pong(s), last ping " .. formatDate(result.startedAt)) or "not tested")
      end
      self.channelTestSummary = Dibs.AceGUI.AddLabel(shell, channelTest, table.concat(summaries, "\n"), true)
      scheduleAutoPing()
      return
    end
    if self.playerTab == "requests" then
      Dibs.AceGUI.AddHeading(shell, tabs, "Requests", "Your Pre-Dib requests and their current status.")
      local requestRows = {}
      for _, request in ipairs(view.requests or {}) do
        requestRows[#requestRows + 1] = {
          request.date or "Unknown", request.item, request.status, request.cancelAllowed and "Cancel" or "",
          request = request,
        }
      end
      if #requestRows == 0 then requestRows[1] = { "", view.empty.requests, "", "" } end
      Dibs.AceGUI.AddTable(shell, tabs, {
        { title = "Date", width = 145 },
        { title = "Item", width = 260 },
        { title = "Status", width = 130 },
        { title = "Action", width = 90 },
      }, requestRows, 220, function(row)
        if not row.request or not row.request.cancelAllowed then return nil end
        return {
          text = "Cancel",
          callback = function()
            local cancelled, reason = Dibs.PlayerUI.CancelPreDib(row.request.requestId)
            self.preDibStatusText = cancelled and "Request cancelled." or (reason == "NOT_REQUEST_OWNER"
              and "You can only cancel your own requests." or "Unable to cancel this request.")
            self:Refresh()
          end,
        }
      end)
      return
    end
    if self.playerTab == "history" then
      Dibs.AceGUI.AddHeading(shell, tabs, "History", "Your Dibs activity for the current season.")
      local historyRows = {}
      for _, entry in ipairs(view.history or {}) do
        historyRows[#historyRows + 1] = { entry.date, entry.item, entry.action, entry.result, entry.balanceImpact, entry = entry }
      end
      if #historyRows == 0 then historyRows[1] = { "", view.empty.history, "", "", "" } end
      Dibs.AceGUI.AddTable(shell, tabs, {
        { title = "Date", width = 145 },
        { title = "Item", width = 220 },
        { title = "Action", width = 130 },
        { title = "Result", width = 190 },
        { title = "Balance", width = 90 },
      }, historyRows, 300, nil, {
        contextMenu = function(row)
          if not row.entry then return nil end
          return {
            {
              text = "View details",
              callback = function()
                self.historyDetail = row.entry
                self:Refresh()
              end,
            },
          }
        end,
      })
      if self.historyDetail then
        Dibs.AceGUI.AddHeader(shell, tabs, "History details", self.historyDetail.item)
        Dibs.AceGUI.AddLabel(shell, tabs,
          "Date: " .. tostring(self.historyDetail.date) .. "\n" ..
          "Action: " .. tostring(self.historyDetail.action) .. "\n" ..
          "Result: " .. tostring(self.historyDetail.result) .. "\n" ..
          "Balance impact: " .. tostring(self.historyDetail.balanceImpact), true)
      end
      return
    end

    Dibs.AceGUI.AddHeading(shell, tabs, "My Dibs", "Your balance, active requests, and current guild status.")
    Dibs.AceGUI.AddTable(shell, tabs, {
      { title = "Balance", width = 130, tooltip = helpText.UI_HELP_DIB_BALANCE },
      { title = "Season", width = 230, tooltip = helpText.UI_HELP_SEASON },
      { title = "Active Pre-Dibs", width = 150, tooltip = helpText.UI_HELP_PREDIB },
      { title = "Requests", width = 110, tooltip = helpText.UI_HELP_REQUEST_STATUS },
    }, {{ tostring(view.balance), view.seasonName, tostring(#view.activePreDibs), tostring(view.pendingRequests) }}, 90)
    Dibs.AceGUI.AddHeader(shell, tabs, view.status.label, view.status.explanation)
    local activeRows = {}
    for _, request in ipairs(view.activePreDibs or {}) do
      activeRows[#activeRows + 1] = {
        request.date, request.item, request.status, request.difficulty or "Any", "Cancel",
        request = request,
      }
    end
    if #activeRows == 0 then activeRows[1] = { "", view.empty.activePreDibs, "", "", "" } end
    Dibs.AceGUI.AddTable(shell, tabs, {
      { title = "Date", width = 145, tooltip = helpText.UI_HELP_DATE },
      { title = "Item", width = 250, tooltip = helpText.UI_HELP_ITEM },
      { title = "Status", width = 120, tooltip = helpText.UI_HELP_REQUEST_STATUS },
      { title = "Difficulty", width = 100, tooltip = helpText.UI_HELP_DIFFICULTY },
      { title = "Action", width = 90, tooltip = helpText.UI_HELP_ACTION },
    }, activeRows, 170, function(row)
      if not row.request then return nil end
      return {
        text = "Cancel",
        callback = function()
          local cancelled = Dibs.PlayerUI.CancelPreDib(row.request.requestId)
          self.preDibStatusText = cancelled and "Request cancelled." or "Unable to cancel this request."
          self:Refresh()
        end,
      }
    end)
    addRequestAction(tabs, view)
  end

  shell.onRelease = function()
    stopAutoPing()
    for _, key in ipairs({
      "aceTabs", "preDibInput", "preDibButton", "preDibStatus", "preDibStatusText", "preDibValue", "devItemText",
      "devRequestButton", "devStatusText", "devStatus", "playerTab", "historyDetail", "historyMode", "historyPage",
      "historyQuery", "eligibilityCharacter", "eligibilityStatus", "Refresh", "SelectTab", "dibsAceGUIShell", "_dibsUiShell",
      "developerModeToggle", "channelTestChannel", "channelTestTarget", "channelTestCustomChannelName", "channelTestStatus",
      "channelTestReceivedStatus",
      "channelTestSelector", "channelTestTargetInput", "channelTestCustomChannelInput", "channelTestRunButton",
      "channelTestScanButton", "channelTestRefreshButton", "channelTestAutoPingToggle", "channelTestMatrix",
      "channelTestMatrixRows", "channelTestMatrixPage", "channelTestPrevious", "channelTestPageLabel",
      "channelTestNext", "channelTestSummary", "channelTestAutoPingScheduled", "channelTestAutoPingGeneration",
      "channelTestAutoPingEnabled",
    }) do
      frame[key] = nil
    end
  end
  if not frame._dibsOnShowHookInstalled then
    frame._dibsOnShowHookInstalled = true
    frame:HookScript("OnShow", function(self)
      local activeShell = self._dibsUiShell
      if activeShell and activeShell._dibsActive then self:Refresh() end
    end)
  end
  _G.DibsPlayerFrame = frame
  frame:Refresh()
  Dibs.AceGUI.SelectTree(tabs, frame.playerTab)
  return frame
end

function Dibs.PlayerUI.RefreshDiagnostics()
  local frame = _G.DibsPlayerFrame
  local shell = frame and frame.dibsAceGUIShell
  if not frame or frame.playerTab ~= "diagnostics" or type(frame.Refresh) ~= "function"
    or not shell or shell._dibsActive ~= true or (frame.IsShown and not frame:IsShown()) then return false end
  frame:Refresh()
  return true
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
   title:SetText("RCLootCouncil - Dibs | Player")

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
  Dibs.AceGUI.AddTooltip(summaryText, "Dibs summary", helpText.UI_HELP_PLAYER_OVERVIEW)
  Dibs.AceGUI.AddTooltip(preDibLabel, "Pre-Dib", helpText.UI_HELP_PREDIB)
  Dibs.AceGUI.AddTooltip(preDibInput, "Pre-Dib", helpText.UI_HELP_PREDIB_FIELD)
  Dibs.AceGUI.AddTooltip(preDibButton, "Pre-Dib", helpText.UI_HELP_PREDIB_SUBMIT)
  Dibs.AceGUI.AddTooltip(searchBox, "History", helpText.UI_HELP_DETAILS)
  Dibs.AceGUI.AddTooltip(modeButton, "History scope", helpText.UI_HELP_HISTORY_SCOPE)
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

---@return table|nil frame Player window when UI is available.
-- Side effects: Creates/shows a player-scoped window; protected frame work may be deferred.
function Dibs.PlayerUI.Show()
  local frame = Dibs.PlayerUI.CreateWindow()
  local wasShown = frame:IsShown()
  frame:Show()
  frame:Raise()
  -- OnShow already refreshes a hidden AceGUI window.  Only refresh an
  -- already-visible window here; doing both can clear a TreeGroup while AceGUI
  -- is still laying out the first refresh.
  if wasShown and frame.Refresh then
    frame:Refresh()
  end

  local summary = Dibs.PlayerUI.GetSummary()
  Dibs.Message("Dibs: " .. tostring(summary.balance) .. " available")
  return summary
end

function Dibs.PlayerUI.Toggle(forceShow)
  local frame = Dibs.PlayerUI.CreateWindow()
  local wasShown = frame:IsShown()
  if forceShow then
    frame:Show()
    frame:Raise()
  elseif frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
    frame:Raise()
  end

  if frame:IsShown() and wasShown and frame.Refresh then
    frame:Refresh()
  end

  return frame:IsShown()
end
