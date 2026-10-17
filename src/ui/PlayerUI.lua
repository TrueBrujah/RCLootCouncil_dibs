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

local function formatDate(timestamp, pattern)
  local value = tonumber(timestamp) or 0
  if value > 0 and type(date) == "function" then
    local ok, formatted = pcall(date, pattern or "%Y-%m-%d %H:%M:%S", value)
    if ok and formatted then return tostring(formatted) end
  end
  return value > 0 and tostring(value) or "Unknown"
end

local function playerListHeight(rowCount, maximum)
  return math.min(maximum, math.max(72, 44 + (tonumber(rowCount) or 0) * 32))
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
  { text = helpText.PLAYER_NAV_REPORTS or "Reports", value = "requests", module = "requests" },
  { text = "History", value = "history" },
  { text = helpText.PLAYER_VAULT_TITLE or "Great Vault", value = "vault" },
  { text = helpText.MINIMAP_SETTINGS_NAV or "Preferences", value = "preferences" },
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

local function getPlayerTransactions(playerName, seasonId, mode, ledgerId)
  local items = {}
  if mode == "all" and Dibs.Ledger and Dibs.Ledger.GetAllTransactions then
    local playerKey = string.lower(tostring(playerName or Dibs.GetPlayerName()))
    for _, tx in ipairs(Dibs.Ledger.GetAllTransactions()) do
      if string.lower(tostring(tx.playerName or tx.playerKey or "")) == playerKey then
        table.insert(items, tx)
      end
    end
  elseif Dibs.Ledger and Dibs.Ledger.GetHistory then
    items = Dibs.Ledger.GetHistory(playerName, seasonId, ledgerId)
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
    Closed = { label = Dibs.L.REQUEST_CLOSED or "Closed", nextAction = Dibs.L.REQUEST_VIEW_DOSSIER or "View dossier",
      explanation = Dibs.L.REQUEST_RETAINED or "The complete dossier is retained; this stage does not change Dibs." },
    Archived = { label = Dibs.L.REQUEST_ARCHIVED or "Archived", nextAction = Dibs.L.REQUEST_VIEW_DOSSIER or "View dossier",
      explanation = Dibs.L.REQUEST_RETAINED or "The complete dossier is retained; this stage does not change Dibs." },
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
function Dibs.PlayerUI.GetSummary(playerName, ledgerId)
  local season = Dibs.Seasons and Dibs.Seasons.GetCurrent() or nil
  local currentPlayer = playerName or Dibs.GetPlayerName()
  local canonical = Dibs.Ledger and Dibs.Ledger.GetCanonicalPlayerDibsState
    and Dibs.Ledger.GetCanonicalPlayerDibsState(season and season.id, currentPlayer, ledgerId) or nil
  local playerState = Dibs.Ledger and Dibs.Ledger.GetPlayerState and Dibs.Ledger.GetPlayerState(currentPlayer, season and season.id, ledgerId) or {}
  local transactions = Dibs.Ledger and Dibs.Ledger.GetHistory and Dibs.Ledger.GetHistory(currentPlayer, season and season.id, ledgerId) or {}
  local used = 0
  for _, transaction in ipairs(transactions) do
    local amount = tonumber(transaction.amount or transaction.quantityDelta) or 0
    if transaction.type == "DIB_USED" then
      used = used + math.max(0, -amount)
    elseif transaction.type == "DIB_REFUNDED" then
      used = math.max(0, used - math.max(0, amount))
    end
  end
  local requests = Dibs.PreDibs and Dibs.PreDibs.GetActiveRequests(currentPlayer, ledgerId) or {}
  local activePreDibs = {}
  for _, request in ipairs(requests) do
    if not season or request.seasonId == season.id then activePreDibs[#activePreDibs + 1] = request end
  end
  local wonPreDibs = {}
  local playerKey = string.lower(tostring(currentPlayer or ""))
  for _, request in ipairs(Dibs.PreDibs and Dibs.PreDibs.GetHistory and Dibs.PreDibs.GetHistory(ledgerId) or {}) do
    if string.lower(tostring(request.playerName or "")) == playerKey and request.status == "fulfilled"
      and (not season or request.seasonId == season.id) then
      wonPreDibs[#wonPreDibs + 1] = request
    end
  end
  table.sort(wonPreDibs, function(first, second)
    return (first.fulfilledAt or first.updatedAt or first.createdAt or 0)
      > (second.fulfilledAt or second.updatedAt or second.createdAt or 0)
  end)
  local acquisitions = Dibs.PreDibs and Dibs.PreDibs.GetAcquisitionsForPlayer and Dibs.PreDibs.GetAcquisitionsForPlayer(currentPlayer) or {}
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
    and Dibs.CharacterEligibility.GetSummary(currentPlayer, season and season.id) or nil

  return {
    season = season,
    player = currentPlayer,
    balance = canonical and canonical.balance or 0,
    balanceState = canonical,
    seasonAllocation = tonumber(playerState.allocation) or 0,
    seasonUsed = used,
    activePreDibs = activePreDibs,
    wonPreDibs = wonPreDibs,
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

local function projectHistory(playerName, seasonId, ledgerId)
  local entries = getPlayerTransactions(playerName, seasonId, "current", ledgerId)
  local history = {}
  for _, transaction in ipairs(entries) do
    local amount = tonumber(transaction.amount or transaction.quantityDelta) or 0
    table.insert(history, {
      transactionId = transaction.transactionId,
      date = formatDate(transaction.createdAt or transaction.timestamp),
      item = transaction.itemName or transaction.itemLink or (transaction.itemID and ("Item " .. tostring(transaction.itemID)) or "Dibs"),
      itemID = transaction.itemID,
      itemName = transaction.itemName,
      itemLink = transaction.itemLink,
      action = tostring(transaction.type or transaction.actionType or "Activity"),
      result = tostring(transaction.reason or "Recorded"),
      balanceImpact = (amount >= 0 and "+" or "") .. tostring(amount),
      createdAt = tonumber(transaction.createdAt or transaction.timestamp),
      source = transaction.source,
      status = transaction.status or transaction.sourceStatus,
      sourceStatus = transaction.sourceStatus,
      raidName = transaction.raidName or transaction.instanceName,
      instanceName = transaction.instanceName,
      bossName = transaction.bossName or transaction.encounterName,
      encounterName = transaction.encounterName,
    })
  end
  return history
end

local PLAYER_HISTORY_FILTER_OPTIONS = {
  queryFields = {
    "itemName", "itemLink", "itemID", "source", "status", "sourceStatus",
    "action", "raidName", "instanceName", "bossName", "encounterName",
  },
  fieldMap = {
    item = { "itemName", "itemLink", "itemID" },
    raid = { "raidName", "instanceName" },
    boss = { "bossName", "encounterName" },
    source = { "source" },
    status = { "status", "sourceStatus", "action" },
  },
  timestampFields = { "createdAt" },
  identityFields = { "transactionId" },
}

local function filterPlayerHistory(entries, criteria)
  if type(criteria) ~= "table" then return entries end
  if not Dibs.HistoryFilters or type(Dibs.HistoryFilters.FilterRecords) ~= "function" then
    return nil, "FILTER_UNAVAILABLE"
  end
  return Dibs.HistoryFilters.FilterRecords(entries, criteria, PLAYER_HISTORY_FILTER_OPTIONS)
end

local function historyFilterErrorText(reason)
  local keys = {
    INVALID_FROM_DATE = "HISTORY_FILTER_INVALID_FROM_DATE",
    INVALID_TO_DATE = "HISTORY_FILTER_INVALID_TO_DATE",
    INVALID_DATE_RANGE = "HISTORY_FILTER_INVALID_DATE_RANGE",
    DATE_UNAVAILABLE = "HISTORY_FILTER_DATE_UNAVAILABLE",
  }
  local key = keys[reason]
  return key and helpText[key] or helpText.HISTORY_FILTER_SOURCE_UNAVAILABLE
end

local function hasActiveHistoryFilters(criteria)
  for _, field in ipairs({ "query", "fromDate", "toDate", "source", "status" }) do
    if trimText(criteria and criteria[field]) ~= "" then return true end
  end
  return false
end

local function addHistoryFilterControls(shell, parent, frame, filterKey, prefix, widthHint)
  local gui = Dibs.AceGUI
  local state = frame[filterKey] or {}
  local inputs = {}
  local group = gui.AddInlineGroup(shell, parent)
  local definitions = {
    { field = "query", label = helpText.HISTORY_FILTER_SEARCH or "Search history", width = math.max(220, math.min(340, widthHint * 0.52)) },
    { field = "fromDate", label = helpText.HISTORY_FILTER_FROM_DATE or "From date (YYYY-MM-DD)", width = 170 },
    { field = "toDate", label = helpText.HISTORY_FILTER_TO_DATE or "To date (YYYY-MM-DD)", width = 170 },
    { field = "source", label = helpText.HISTORY_FILTER_SOURCE or "Source", width = 150 },
    { field = "status", label = helpText.HISTORY_FILTER_STATUS or "Status", width = 150 },
  }
  for _, definition in ipairs(definitions) do
    local input = gui.AddEditBox(shell, group, definition.label, nil, definition.width)
    inputs[definition.field] = input
    if input then
      Dibs.AceGUI.AddTooltip(input, definition.label, helpText.HISTORY_FILTER_SEARCH_HELP)
      if trimText(state[definition.field]) ~= "" then setControlText(input, state[definition.field]) end
    end
  end

  local function applyFilters()
    local criteria = {}
    for _, definition in ipairs(definitions) do
      criteria[definition.field] = getControlText(inputs[definition.field])
    end
    frame[filterKey] = criteria
    if prefix == "vault" then frame.vaultPage = 1 else frame.historyPage = 1 end
    frame:Refresh()
  end
  local apply = gui.AddButton(shell, group, helpText.HISTORY_FILTER_APPLY or "Apply filters", applyFilters, 145)
  local clear = gui.AddButton(shell, group, helpText.HISTORY_FILTER_CLEAR or "Clear filters", function()
    frame[filterKey] = {}
    if prefix == "vault" then frame.vaultPage = 1 else frame.historyPage = 1 end
    frame:Refresh()
  end, 130)
  local clearFields = {}
  frame[prefix .. "FilterClearFields"] = clearFields
  local activeFilters = {}
  for _, definition in ipairs(definitions) do
    if trimText(state[definition.field]) ~= "" then
      activeFilters[#activeFilters + 1] = definition
    end
  end
  if #activeFilters > 0 then
    local clearGroup = gui.AddInlineGroup(shell, parent)
    for _, definition in ipairs(activeFilters) do
      local label = string.format(helpText.HISTORY_FILTER_CLEAR_FIELD or "Clear %s", definition.label)
      local button = gui.AddButton(shell, clearGroup, label, function()
        local updated = {}
        for key, value in pairs(frame[filterKey] or {}) do
          if key ~= definition.field then updated[key] = value end
        end
        frame[filterKey] = updated
        if prefix == "vault" then frame.vaultPage = 1 else frame.historyPage = 1 end
        frame:Refresh()
      end, 180)
      clearFields[definition.field] = button
      gui.AddTooltip(button, definition.label, helpText.HISTORY_FILTER_CLEAR_FIELD_HELP)
    end
  end
  if prefix == "vault" then
    frame.vaultFilterSearch = inputs.query
    frame.vaultFilterApply = apply
    frame.vaultFilterClear = clear
  else
    frame.historyFilterSearch = inputs.query
    frame.historyFilterApply = apply
    frame.historyFilterClear = clear
  end
end

function Dibs.PlayerUI.GetViewModel(playerName, historyFilters, ledgerId)
  local summary = Dibs.PlayerUI.GetSummary(playerName, ledgerId)
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
  local won = {}
  for _, request in ipairs(summary.wonPreDibs or {}) do
    table.insert(won, {
      requestId = request.requestId,
      date = formatDate(request.fulfilledAt or request.updatedAt or request.createdAt),
      item = request.itemName or request.itemLink or ("Item " .. tostring(request.itemID or "?")),
      difficulty = request.difficulty and tostring(request.difficulty) or nil,
      status = (Dibs.L or {}).PLAYER_PREDIB_WON_STATUS or "Won",
      request = request,
    })
  end
  local history = projectHistory(summary.player, summary.season and summary.season.id, ledgerId)
  local historyFilterError
  if type(historyFilters) == "table" then
    local filtered, reason = filterPlayerHistory(history, historyFilters)
    if filtered then
      history = filtered
    else
      history = {}
      historyFilterError = historyFilterErrorText(reason)
    end
  end
  local requests = playerRequestHistory(summary.player, summary.activePreDibs)
  return {
    navigation = Dibs.PlayerUI.GetNavigation(),
    player = summary.player,
    balance = summary.balance,
    seasonAllocation = summary.seasonAllocation or 0,
    seasonUsed = summary.seasonUsed or 0,
    seasonName = summary.season and summary.season.name or "No active season",
    activePreDibs = active,
    wonPreDibs = won,
    requests = requests,
    pendingRequests = #active,
    history = history,
    historyFilterError = historyFilterError,
    status = Dibs.PlayerUI.GetStatusPresentation(readiness),
    empty = {
      activePreDibs = #active == 0 and ((Dibs.L or {}).PLAYER_NO_ACTIVE_PREDIBS or "No active Pre-Dibs this season.") or nil,
      wonPreDibs = #won == 0 and ((Dibs.L or {}).PLAYER_NO_FULFILLED_PREDIBS or "No won Pre-Dibs this season.") or nil,
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

local function getOwnedVaultItemLinks()
  local links, ambiguous = {}, {}
  local function addLink(link)
    if type(_G.issecretvalue) == "function" and issecretvalue(link) then return end
    if type(link) ~= "string" then return end
    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID then return end
    local itemString = link:match("|H(item:[^|]+)|h")
    local existing = links[itemID]
    if existing and existing:match("|H(item:[^|]+)|h") ~= itemString then ambiguous[itemID] = true end
    links[itemID] = link
  end
  if type(GetInventoryItemLink) == "function" then
    for slot = 1, 19 do addLink(GetInventoryItemLink("player", slot)) end
  end
  if type(C_Container) == "table" and type(C_Container.GetContainerNumSlots) == "function"
    and type(C_Container.GetContainerItemLink) == "function" then
    for bag = 0, (_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5) do
      for slot = 1, C_Container.GetContainerNumSlots(bag) do
        addLink(C_Container.GetContainerItemLink(bag, slot))
      end
    end
  end
  for itemID in pairs(ambiguous) do links[itemID] = nil end
  return links
end

local function resolveVaultItem(record, frame, ownedLinks)
  if record.itemLink or not record.itemID then return record end
  local ownedLink = ownedLinks[tonumber(record.itemID)]
  if ownedLink then
    record.isOwnedItemPreview = true
    record.itemLink = ownedLink
    record.itemName = record.itemName or ownedLink:match("|h%[(.-)%]|h")
    record.itemPreviewHint = helpText.PLAYER_VAULT_OWNED_PREVIEW
      or "Preview of the matching item currently owned; the acquired variant was not recorded."
    return record
  end
  record.itemPreviewHint = helpText.PLAYER_VAULT_VARIANT_UNKNOWN
    or "Exact acquired variant unavailable. Record the full item link to preserve its level and bonuses."
  if record.itemName then return record end
  frame.vaultItemCache = frame.vaultItemCache or {}
  local key = tostring(record.itemID)
  local cached = frame.vaultItemCache[key]
  if not cached and Dibs.LootPipeline and Dibs.LootPipeline.ResolveItem then
    cached = { loading = true }
    frame.vaultItemCache[key] = cached
    local synchronous = true
    Dibs.LootPipeline.ResolveItem(record.itemID, function(item, reason)
      cached.loading = false
      cached.item = item
      cached.reason = reason
      if not item and Dibs.Message then
        Dibs.Message("[GreatVault] " .. key .. ": " .. tostring(reason or "ITEM_LOAD_FAILED"), { chat = false })
      end
      if not synchronous and frame.playerTab == "vault"
        and (not frame.IsShown or frame:IsShown()) and frame.Refresh then frame:Refresh() end
    end)
    synchronous = false
  end
  if cached and cached.item then
    record.itemName = cached.item.itemName
  end
  return record
end

local function renderVaultHistory(shell, parent, frame, widthHint)
  local gui = Dibs.AceGUI
  local page = gui.AddTablePage(shell, parent, { footer = true, boundsFrame = parent.content or parent.frame })
  if not page then
    Dibs.Message(helpText.PLAYER_VAULT_UNAVAILABLE or "Great Vault history is unavailable.")
    return
  end
  frame.vaultTablePage = page
  gui.AddHeading(shell, page.header, helpText.PLAYER_VAULT_TITLE or "Great Vault",
    helpText.PLAYER_VAULT_HELP or "Your recorded rewards across seasons in the current guild scope. Read-only; no Dibs are spent.")
  if not (Dibs.PreDibs and type(Dibs.PreDibs.GetAcquisitionsForPlayer) == "function"
    and type(Dibs.PreDibs.ProjectVaultAcquisition) == "function") then
    gui.AddLabel(shell, page.header, helpText.PLAYER_VAULT_UNAVAILABLE or "Great Vault history is unavailable.", true)
    page.UpdateViewportHeight()
    return
  end
  addHistoryFilterControls(shell, page.header, frame, "vaultFilters", "vault", widthHint)
  gui.AddLabel(shell, page.header, helpText.PLAYER_VAULT_MANUAL
    or "Use /dibs vault <item link>: raid items keep their origin (Raid Finder = LFR); Heroic dungeon rewards on Veteran stay Heroic, while Champion = Normal, Hero = Heroic and Myth = Mythic. Otherwise specify LFR, Normal, Heroic or Mythic for manual review.", true)
  local records = {}
  local ownedLinks = getOwnedVaultItemLinks()
  for _, record in ipairs(Dibs.PreDibs.GetAcquisitionsForPlayer(Dibs.GetPlayerName())) do
    records[#records + 1] = resolveVaultItem(Dibs.PreDibs.ProjectVaultAcquisition(record, "player"), frame, ownedLinks)
  end
  local filtered, filterReason = Dibs.HistoryFilters.FilterRecords(records, frame.vaultFilters or {}, {
    queryFields = { "itemName", "itemLink", "itemID", "source", "verificationState",
      "status", "raidName", "instanceName", "bossName", "encounterName" },
    fieldMap = {
      item = { "itemName", "itemLink", "itemID" },
      raid = { "raidName", "instanceName" },
      boss = { "bossName", "encounterName" },
      source = { "source" },
      status = { "status", "verificationState" },
    },
    timestampFields = { "acquiredAt", "createdAt" },
    identityFields = { "acquisitionId" },
  })
  frame.vaultFilterError = filterReason and historyFilterErrorText(filterReason) or nil
  records = filtered or {}
  if frame.vaultFilterError then
    gui.AddLabel(shell, page.header, frame.vaultFilterError, true)
  end
  local visible, currentPage = gui.GetPageSlice(records, frame.vaultPage, 10)
  frame.vaultPage = currentPage
  local rows = {}
  for _, record in ipairs(visible) do
    local status = Dibs.PlayerUI.GetVaultAcquisitionPresentation(record)
    local itemName = record.itemName or ("Item " .. tostring(record.itemID))
    local itemLink = record.itemLink
    if not itemLink and tonumber(record.itemID) then
      itemLink = "|Hitem:" .. tostring(record.itemID) .. "|h[" .. itemName .. "]|h"
    end
    local variantLabel = record.isOwnedItemPreview
      and (helpText.PLAYER_VAULT_PREVIEW_LABEL or "owned preview")
      or (not record.itemLink and (helpText.PLAYER_VAULT_REFERENCE_LABEL or "item reference"))
    rows[#rows + 1] = {
      formatDate(record.acquiredAt, "%Y-%m-%d"),
      tostring(itemLink or itemName),
      tostring(record.difficulty or helpText.PLAYER_VAULT_UNKNOWN or "Unknown"),
      status.label .. (variantLabel and ("\n(" .. variantLabel .. ")") or ""),
      itemLink = itemLink,
      tooltip = table.concat({
        formatDate(record.acquiredAt),
        status.label, status.explanation, record.itemPreviewHint or "",
        (helpText.PLAYER_VAULT_SOURCE or "Source") .. ": " .. tostring(record.source or helpText.PLAYER_VAULT_UNKNOWN or "Unknown"),
        (helpText.PLAYER_VAULT_RESET or "Weekly reset") .. ": " .. tostring(record.resetId or helpText.PLAYER_VAULT_UNKNOWN or "Unknown"),
        (helpText.PLAYER_VAULT_SYNC or "Synchronization") .. ": " .. tostring(record.syncState or helpText.PLAYER_VAULT_UNKNOWN or "Unknown"),
      }, "\n"),
    }
  end
  frame.vaultHistoryTable = gui.AddTable(shell, page.scroll, {
    { title = helpText.PLAYER_VAULT_DATE or "Date", width = 84, fixed = true, wrap = true },
    { title = helpText.PLAYER_VAULT_ITEM or "Item", width = 300, minWidth = 140, weight = 3, wrap = true },
    { title = helpText.PLAYER_VAULT_DIFFICULTY or "Difficulty", width = 76, fixed = true, wrap = true },
    { title = helpText.PLAYER_VAULT_STATUS or "Verification", width = 180, minWidth = 90, weight = 1, wrap = true },
  }, rows, 300, nil, {
    fluidColumns = true, widthHint = widthHint, allowTableSort = false,
    noScrolling = true, headerParent = page.columnHeader, scrollbarReserve = 26,
    emptyText = frame.vaultFilterError or (hasActiveHistoryFilters(frame.vaultFilters)
      and helpText.HISTORY_FILTER_NO_RESULTS or helpText.PLAYER_VAULT_EMPTY)
      or "No Great Vault acquisitions recorded for your character in this guild scope.",
    cellTooltip = function(row) return row.tooltip end,
    onRowClick = function(row, column)
      if column ~= 2 or not row.itemLink then return end
      local itemLink = gui.ResolveItemHyperlink(row.itemLink)
      if not itemLink or type(_G.SetItemRef) ~= "function" then
        Dibs.Message(helpText.PLAYER_VAULT_LINK_UNAVAILABLE or "The item link cannot be opened right now.")
        return
      end
      local itemString = itemLink:match("|H(item:[^|]+)|h")
      if itemString then SetItemRef(itemString, itemLink, "LeftButton") end
    end,
  })
  local pagination = gui.AddPaginationFooter(shell, page, {
    showPageSize = false,
    onPrevious = function() frame.vaultPage = frame.vaultPage - 1; frame:Refresh() end,
    onNext = function() frame.vaultPage = frame.vaultPage + 1; frame:Refresh() end,
  })
  if pagination then pagination.UpdateState(currentPage, #records, 10) end
  page.UpdateViewportHeight()
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

local function reportTransactionLabel(tx)
  local line = compactLine(tx)
  local item = tx.itemLink or tx.itemName or (tx.itemID and ("Item " .. tostring(tx.itemID))) or nil
  return item and (line .. " | " .. tostring(item)) or line
end

-- Report form, review-request list and details shared by the Player windows.
-- Submitting records a request for Officer review; it never changes balances.
local function renderReviewRequests(shell, parent, frame, summary, options)
  options = options or {}
  local strings = Dibs.L or {}
  local widthHint = math.max(320, tonumber(options.widthHint) or 560)
  local fieldWidth = math.max(280, math.min(560, widthHint - 24))
  local tableOptions = {
    allowTableSort = false, flatBackground = true, fluidColumns = true, widthHint = widthHint,
    shrinkToFit = true, hideScrollbarWhenFits = true, scrollbarReserve = 26,
  }
  if Dibs.RequestDelivery and Dibs.RequestDelivery.Pump then Dibs.RequestDelivery.Pump() end
  local disputes = Dibs.Disputes

  Dibs.AceGUI.AddHeader(shell, parent, strings.PLAYER_REPORT_TITLE or "Report a problem",
    strings.PLAYER_REPORT_HELP or "Report a wrong Dib debit, a Dib recorded on the wrong item or player, or another Dibs problem. An Officer reviews it; submitting does not change your balance.")
  local categories = sortedLabels(disputes and disputes.GetCategories and disputes.GetCategories() or { other = "Other" })
  local transactions = getPlayerTransactions(summary.player, summary.season and summary.season.id, options.historyMode)
  local transactionChoices = { [""] = strings.PLAYER_REPORT_GENERAL or "General request (no ledger entry)" }
  for _, tx in ipairs(transactions) do
    local id = tostring(tx.transactionId or "")
    if id ~= "" then transactionChoices[id] = reportTransactionLabel(tx) end
  end
  frame.disputeCategory = categories[frame.disputeCategory] and frame.disputeCategory or "other"
  frame.disputeTransactionId = transactionChoices[frame.disputeTransactionId or ""] and frame.disputeTransactionId or ""
  frame.disputeNote = frame.disputeNote or ""
  frame.disputeCategoryControl = Dibs.AceGUI.AddDropdown(shell, parent, strings.PLAYER_REPORT_TYPE or "Problem type", categories, function(value)
    frame.disputeCategory = value
  end, math.min(420, fieldWidth))
  Dibs.AceGUI.SetValue(frame.disputeCategoryControl, frame.disputeCategory)
  frame.disputeTransactionControl = Dibs.AceGUI.AddDropdown(shell, parent,
    strings.PLAYER_REPORT_TRANSACTION or "Related ledger entry (optional)", transactionChoices, function(value)
      frame.disputeTransactionId = value or ""
    end, fieldWidth)
  Dibs.AceGUI.SetValue(frame.disputeTransactionControl, frame.disputeTransactionId)
  frame.disputeNoteControl = Dibs.AceGUI.AddEditBox(shell, parent, strings.PLAYER_REPORT_NOTE or "What should an Officer review?", function(value)
    frame.disputeNote = value or ""
  end, fieldWidth)
  setControlText(frame.disputeNoteControl, frame.disputeNote)
  frame.disputeSubmitButton = Dibs.AceGUI.AddButton(shell, parent, strings.PLAYER_REPORT_SUBMIT or "Submit report", function()
    local payload = {
      category = frame.disputeCategory,
      note = frame.disputeNote,
      playerName = summary.player,
      seasonId = summary.season and summary.season.id or nil,
    }
    if frame.disputeTransactionId ~= "" then payload.transactionRef = frame.disputeTransactionId end
    local request, reason
    if disputes and disputes.CreateReport then request, reason = disputes.CreateReport(payload) end
    if request then
      frame.disputeStatusText = (strings.REQUEST_SAVED or "Request saved. Delivery is tracked separately; receipt is not a resolution.")
        .. " " .. tostring(request.requestId)
      frame.disputeNote = ""
      frame.disputeTransactionId = ""
      frame.selectedDisputeRequestId = request.requestId
    else
      frame.disputeStatusText = (strings.PLAYER_REPORT_FAILED or "Unable to submit request: %s"):format(tostring(reason or "DISPUTES_UNAVAILABLE"))
    end
    frame:Refresh()
  end, 150)
  Dibs.AceGUI.SetDisabled(frame.disputeSubmitButton, not (disputes and disputes.CreateReport))
  frame.disputeStatusLabel = Dibs.AceGUI.AddLabel(shell, parent, frame.disputeStatusText
    or strings.PLAYER_REPORT_PRIVACY or "Requests are visible only to you and guild Officers.", true)

  Dibs.AceGUI.AddHeader(shell, parent, strings.PLAYER_REVIEW_REQUESTS or "My review requests",
    strings.PLAYER_REVIEW_REQUESTS_HELP or "Follow delivery, Officer replies and the decision for each report.")
  local requests, requestReason = {}, nil
  if disputes and disputes.ListForPlayer then
    requests, requestReason = disputes.ListForPlayer(summary.player)
  end
  local requestProjection = Dibs.PlayerUI.BuildRequestView({ limit = 50 })
  if requestReason then
    requestProjection = Dibs.PlayerUI.BuildRequestView({ unavailable = requestReason })
  end
  local projectedById = {}
  for _, projected in ipairs(requestProjection) do
    if projected.requestId then projectedById[projected.requestId] = projected end
  end
  local requestRows = {}
  if requestReason then
    local projected = requestProjection[1]
    requestRows[1] = { "", projected.status.label, "", projected.explanation, "" }
  else
    for _, request in ipairs(requests or {}) do
      local projected = projectedById[request.requestId] or {
        status = { label = "Unavailable" }, nextAction = "Try again later", details = {},
      }
      requestRows[#requestRows + 1] = {
        formatDate(request.createdAt or request.updatedAt),
        tostring(request.categoryLabel or request.category or "Other"),
        projected.status.label,
        tostring(projected.nextAction or ""),
        "",
        request = request,
      }
    end
  end
  local requestTableOptions = {}
  for key, value in pairs(tableOptions) do requestTableOptions[key] = value end
  requestTableOptions.emptyText = strings.PLAYER_REVIEW_REQUESTS_EMPTY or "No review requests yet."
  Dibs.AceGUI.AddTable(shell, parent, {
    { title = "Date", width = 120, minWidth = 90, weight = 1, tooltip = helpText.UI_HELP_DATE },
    { title = strings.PLAYER_REPORT_TYPE or "Problem type", width = 170, minWidth = 110, weight = 2 },
    { title = "Status", width = 120, minWidth = 88, weight = 1, tooltip = helpText.UI_HELP_REQUEST_STATUS },
    { title = "Next step", width = 170, minWidth = 110, weight = 2, tooltip = helpText.UI_HELP_NEXT_STEP },
    { title = "Action", width = 80, minWidth = 70, action = true, tooltip = helpText.UI_HELP_ACTION },
  }, requestRows, playerListHeight(#requestRows, 230), function(row)
    if not row.request then return nil end
    return {
      text = strings.PLAYER_REPORT_VIEW or "View",
      callback = function()
        frame.selectedDisputeRequestId = row.request.requestId
        frame:Refresh()
      end,
    }
  end, requestTableOptions)

  if not (frame.selectedDisputeRequestId and disputes and disputes.GetRequest) then return end
  local selected = disputes.GetRequest(frame.selectedDisputeRequestId, summary.player)
  if not selected then return end
  frame.disputeDetailTitle = Dibs.AceGUI.AddHeader(shell, parent, strings.PLAYER_REQUEST_DETAILS or "Request details", disputeStatusLabel(selected))
  local delivery = selected.delivery
  if delivery then
    local labels = { queued = strings.REQUEST_QUEUED or "Queued", sent = strings.REQUEST_SENT or "Sent; awaiting receipt",
      received = strings.REQUEST_RECEIVED or "Received", error = strings.REQUEST_ERROR or "Delivery error" }
    Dibs.AceGUI.AddLabel(shell, parent, (strings.REQUEST_DELIVERY or "Delivery") .. ": " .. tostring(labels[delivery.state] or delivery.state)
      .. (delivery.reason and (" — " .. delivery.reason) or ""), true)
    if delivery.state ~= "received" and Dibs.RequestDelivery and Dibs.RequestDelivery.Retry then
      Dibs.AceGUI.AddButton(shell, parent, strings.REQUEST_RETRY or "Retry delivery", function()
        local ok, reason = Dibs.RequestDelivery.Retry(selected.requestId)
        frame.disputeStatusText = ok and (strings.REQUEST_REPLY_SAVED or "Delivery retried; check its status.") or tostring(reason)
        frame:Refresh()
      end, 150)
    end
  end
  if selected.followUpAt and Dibs.RequestDelivery and Dibs.RequestDelivery.Snooze then
    Dibs.AceGUI.AddLabel(shell, parent, (strings.REQUEST_FOLLOWUP or "Next follow-up") .. ": " .. formatDate(selected.followUpAt), true)
    Dibs.AceGUI.AddButton(shell, parent, strings.REQUEST_SNOOZE or "Snooze reminder for one hour", function()
      local ok, reason = Dibs.RequestDelivery.Snooze(selected.requestId, time() + 3600)
      frame.disputeStatusText = ok and (strings.REQUEST_SNOOZED or "Reminder snoozed on this character.") or tostring(reason)
      frame:Refresh()
    end, 240)
  end
  local replyRows = {}
  for _, reply in ipairs(selected.replies or {}) do
    replyRows[#replyRows + 1] = { tostring(reply.author), formatDate(reply.createdAt), tostring(reply.boundedText or "") }
  end
  if #replyRows > 0 then
    Dibs.AceGUI.AddTable(shell, parent, {
      { title = strings.REQUEST_REPLY_AUTHOR or "Author", width = 85, minWidth = 70, weight = 1 },
      { title = strings.REQUEST_REPLY_DATE or "Date", width = 120, minWidth = 90, weight = 1 },
      { title = strings.REQUEST_PUBLIC_REPLY or "Public reply", width = 360, minWidth = 140, weight = 3 },
    }, replyRows, 150, nil, tableOptions)
  end
  local evidence = selected.evidence and selected.evidence[1] or {}
  Dibs.AceGUI.AddPropertyTable(shell, parent, {
    { "Status", tostring(selected.status) },
    { "Category", tostring(selected.categoryLabel or selected.category) },
    { "Item", tostring(evidence.item or selected.attachedContext and selected.attachedContext.item or "Unavailable") },
    { "Evidence", tostring(evidence.source or "unavailable") },
    { "Note", tostring(selected.note or "") },
  }, 180)
  if selected.question and selected.status == "Need information" then
    Dibs.AceGUI.AddLabel(shell, parent, "Officer question: " .. tostring(selected.question), true)
    frame.disputeReply = frame.disputeReply or ""
    local reply = Dibs.AceGUI.AddEditBox(shell, parent, "Reply", function(value) frame.disputeReply = value or "" end, fieldWidth)
    setControlText(reply, frame.disputeReply)
    Dibs.AceGUI.AddButton(shell, parent, "Send reply", function()
      local result, reason = disputes.AddReply(frame.selectedDisputeRequestId, frame.disputeReply, summary.player)
      frame.disputeStatusText = result and (strings.REQUEST_REPLY_SAVED or "Reply saved; check delivery status.")
        or ("Unable to reply: " .. tostring(reason or "unknown error"))
      if result then frame.disputeReply = "" end
      frame:Refresh()
    end, 120)
  end
  local timeline = disputes.GetTimeline and disputes.GetTimeline(frame.selectedDisputeRequestId, summary.player) or {}
  local timelineRows = {}
  for _, event in ipairs(timeline) do
    timelineRows[#timelineRows + 1] = { formatDate(event.timestamp or event.createdAt), tostring(event.action or ""), tostring(event.newStatus or ""), tostring(event.reason or "") }
  end
  if #timelineRows > 0 then
    Dibs.AceGUI.AddTable(shell, parent, {
      { title = "Date", width = 120, minWidth = 90, weight = 1, tooltip = helpText.UI_HELP_DATE },
      { title = "Event", width = 140, minWidth = 90, weight = 1, tooltip = helpText.UI_HELP_EVENT },
      { title = "Status", width = 120, minWidth = 88, weight = 1, tooltip = helpText.UI_HELP_REQUEST_STATUS },
      { title = "Details", width = 240, minWidth = 120, weight = 2, tooltip = helpText.UI_HELP_DETAILS },
    }, timelineRows, 170, nil, tableOptions)
  end
  Dibs.AceGUI.AddButton(shell, parent, strings.PLAYER_REQUEST_CLOSE_DETAILS or "Close details", function()
    frame.selectedDisputeRequestId = nil
    frame.disputeDetailTitle = nil
    frame:Refresh()
  end, 130)
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
    if Dibs.AceGUI.SetShellStatus then Dibs.AceGUI.SetShellStatus(shell) end
    if self.playerTab == "vault" then
      renderVaultHistory(shell, tabs, self, 480)
      return
    end
    local summary = Dibs.PlayerUI.GetSummary(nil, Dibs.MultiLedger and Dibs.MultiLedger.GetViewLedgerId and Dibs.MultiLedger.GetViewLedgerId() or nil)
    if self.playerTab == "requests" then
      -- Keep the report form, request list and details in one bounded page so
      -- the lower controls remain reachable on smaller screens.
      local tabs = Dibs.AceGUI.AddScrollableList(shell, tabs, 535) or tabs
      Dibs.AceGUI.AddHeading(shell, tabs, "RCLootCouncil - Dibs options", helpText.UI_HELP_PLAYER_OVERVIEW)
      local toolbar = Dibs.AceGUI.AddInlineGroup(shell, tabs)
      Dibs.AceGUI.AddButton(shell, toolbar, "Open shared options", function() Dibs.RCOptions.Open() end, 170)
      renderReviewRequests(shell, tabs, self, summary, { historyMode = self.historyMode, widthHint = 560 })
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
    local activeLedgerName = "Default"
    if Dibs.MultiLedger and type(Dibs.MultiLedger.GetLedgers) == "function" then
      local ledgers = Dibs.MultiLedger.GetLedgers()
      local activeLedgerId = Dibs.MultiLedger.GetActiveLedgerId()
      local approvedCount = 0
      local ledgerValues = {}
      for _, l in ipairs(ledgers) do
        if l.status == "APPROVED" then
          ledgerValues[l.id] = l.name
          approvedCount = approvedCount + 1
          if l.id == activeLedgerId then
            activeLedgerName = l.name
          end
        end
      end
      if approvedCount > 0 then
        if not ledgerValues[activeLedgerId] then
          ledgerValues[activeLedgerId] = (activeLedgerId == "guild-primary" and "Primary") or activeLedgerId
        end
        local viewLedgerId = Dibs.MultiLedger.GetViewLedgerId and Dibs.MultiLedger.GetViewLedgerId() or activeLedgerId
        local ledgerDropdown = Dibs.AceGUI.AddDropdown(shell, tabs, (Dibs.L or {}).LEDGER_VIEW_LABEL or "View ledger", ledgerValues, function(value)
          if Dibs.MultiLedger.SetViewLedger then Dibs.MultiLedger.SetViewLedger(value) end
          self:Refresh()
        end, 200)
        Dibs.AceGUI.SetValue(ledgerDropdown, viewLedgerId)
      end
    end
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
      { "Active Ledger", tostring(activeLedgerName) },
      { "Season", tostring(summary.season and summary.season.name or "None") },
      { (Dibs.L or {}).PLAYER_SEASON_ALLOCATION or "Season allocation", tostring(summary.seasonAllocation or 0) },
      { (Dibs.L or {}).PLAYER_DIBS_USED or "Dibs used", tostring(summary.seasonUsed or 0) },
      { (Dibs.L or {}).PLAYER_DIBS_REMAINING or "Dibs remaining", tostring(summary.balance) },
      { "Active Pre-Dibs", tostring(#(summary.activePreDibs or {})) },
      { (Dibs.L or {}).PLAYER_FULFILLED_PREDIBS or "Won Pre-Dibs", tostring(#(summary.wonPreDibs or {})) },
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
    Dibs.AceGUI.AddHeader(shell, tabs, (Dibs.L or {}).PLAYER_ACTIVE_PREDIBS or "Active Pre-Dibs", helpText.UI_HELP_PREDIB)
    local activeRows = {}
    for _, request in ipairs(summary.activePreDibs or {}) do
      activeRows[#activeRows + 1] = {
        formatDate(request.createdAt or request.updatedAt),
        tostring(request.itemName or request.itemLink or ("Item " .. tostring(request.itemID))),
        tostring(request.difficulty or "Normal"), tostring(request.status), "", request = request,
      }
    end
    Dibs.AceGUI.AddTable(shell, tabs, {
      { title = "Date", width = 145, align = "CENTER", tooltip = "When the Pre-Dib was created." },
      { title = "Item", width = 240, tooltip = "The reserved loot." },
      { title = "Difficulty", width = 100, align = "CENTER", tooltip = "Normal, Heroic, or Mythic." },
      { title = "Status", width = 100, align = "CENTER", tooltip = "Pending or confirmed." },
      { title = "Action", width = 90, tooltip = "Cancel your request." },
    }, activeRows, playerListHeight(#activeRows, 145), function(row)
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
    end, { fluidColumns = true, widthHint = playerContentWidthHint(), scrollbarReserve = 0,
      columnGap = Dibs.AceGUI.GetLayoutMetrics().tableColumnGap,
      emptyText = (Dibs.L or {}).PLAYER_NO_ACTIVE_PREDIBS or "No active Pre-Dibs this season." })
    Dibs.AceGUI.AddHeader(shell, tabs, (Dibs.L or {}).PLAYER_FULFILLED_PREDIBS or "Won Pre-Dibs",
      "Pre-Dibs fulfilled by a finalized loot award.")
    local wonRows = {}
    for _, request in ipairs(summary.wonPreDibs or {}) do
      wonRows[#wonRows + 1] = {
        formatDate(request.fulfilledAt or request.updatedAt or request.createdAt),
        tostring(request.itemName or request.itemLink or ("Item " .. tostring(request.itemID))),
        tostring(request.difficulty or "Normal"), (Dibs.L or {}).PLAYER_PREDIB_WON_STATUS or "Won",
      }
    end
    Dibs.AceGUI.AddTable(shell, tabs, {
      { title = "Date", width = 145, align = "CENTER", tooltip = "When the Pre-Dib was fulfilled." },
      { title = "Item", width = 260, tooltip = "The item won through the fulfilled Pre-Dib." },
      { title = "Difficulty", width = 110, align = "CENTER", tooltip = helpText.UI_HELP_DIFFICULTY },
      { title = "Status", width = 100, align = "CENTER", tooltip = helpText.UI_HELP_REQUEST_STATUS },
    }, wonRows, playerListHeight(#wonRows, 145), nil, { fluidColumns = true, widthHint = playerContentWidthHint(), scrollbarReserve = 0,
      columnGap = Dibs.AceGUI.GetLayoutMetrics().tableColumnGap,
      emptyText = (Dibs.L or {}).PLAYER_NO_FULFILLED_PREDIBS or "No won Pre-Dibs this season." })
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
  local function playerContentWidthHint()
    local content = tabs.content
    local width = content and content.GetWidth and tonumber(content:GetWidth()) or 0
    if width and width > 0 then return width end
    local windowWidth = shell.frame and shell.frame.GetWidth and tonumber(shell.frame:GetWidth())
      or (shell.layout and tonumber(shell.layout.width)) or 720
    return math.max(320, windowWidth - 170 - 48)
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
    end, math.max(300, playerContentWidthHint() - 24))
    if frame.preDibInput and frame.preDibInput.SetFullWidth then frame.preDibInput:SetFullWidth(true) end
    Dibs.AceGUI.AddTooltip(frame.preDibInput, "Pre-Dib", helpText.UI_HELP_PREDIB_FIELD)
    setControlText(frame.preDibInput, frame.preDibValue)
    local submit = Dibs.AceGUI.AddButton(shell, parent, "Submit request", submitFromInput, 150)
    Dibs.AceGUI.AddTooltip(submit, "Pre-Dib", helpText.UI_HELP_PREDIB_SUBMIT)
    local publicEnabled = Dibs.PreDibs and Dibs.PreDibs.IsPublicEnabled and Dibs.PreDibs.IsPublicEnabled() or false
    local viewingOther = Dibs.MultiLedger and Dibs.MultiLedger.IsViewingOtherLedger and Dibs.MultiLedger.IsViewingOtherLedger() or false
    Dibs.AceGUI.SetDisabled(submit, not publicEnabled or viewingOther)
    Dibs.AceGUI.AddLabel(shell, parent, frame.preDibStatusText or (viewingOther
      and ((Dibs.L or {}).LEDGER_VIEW_PREDIB_BLOCKED or "Return to the guild active ledger to request a Pre-Dib.")
      or publicEnabled
      and "Public Pre-Dibs are enabled."
      or "Public Pre-Dibs are currently disabled by Officers."), true)
  end

  local function addActiveLedgerToolbar(parent)
    if not (Dibs.MultiLedger and type(Dibs.MultiLedger.GetLedgers) == "function") then return end
    local strings = Dibs.L or {}
    local toolbar = Dibs.AceGUI.AddInlineGroup(shell, parent)
    local ledgers = Dibs.MultiLedger.GetLedgers()
    local activeLedgerId = Dibs.MultiLedger.GetActiveLedgerId()
    local viewLedgerId = Dibs.MultiLedger.GetViewLedgerId and Dibs.MultiLedger.GetViewLedgerId() or activeLedgerId
    local ledgerValues = {}
    for _, l in ipairs(ledgers) do
      if l.status == "APPROVED" then
        ledgerValues[l.id] = l.name or l.id
      end
    end
    if not ledgerValues[activeLedgerId] then
      ledgerValues[activeLedgerId] = (activeLedgerId == "guild-primary" and "Primary") or activeLedgerId
    end
    -- Consultation only: the working ledger is imposed by GM/Officers.
    local ledgerDropdown = Dibs.AceGUI.AddDropdown(shell, toolbar, strings.LEDGER_VIEW_LABEL or "View ledger", ledgerValues, function(value)
      if Dibs.MultiLedger.SetViewLedger then Dibs.MultiLedger.SetViewLedger(value) end
      frame:Refresh()
    end, 200)
    Dibs.AceGUI.SetValue(ledgerDropdown, viewLedgerId)
    Dibs.AceGUI.AddTooltip(ledgerDropdown, strings.LEDGER_VIEW_LABEL or "View ledger",
      strings.LEDGER_VIEW_TOOLTIP or "Consult another ledger in read-only mode. Pre-Dibs and awards always use the guild active ledger set by GM/Officers.")
    if viewLedgerId ~= activeLedgerId then
      Dibs.Midnight.AddStatusBadge(shell, toolbar, "warning", string.format(strings.LEDGER_VIEW_READONLY or "Read-only: %s",
        tostring(ledgerValues[viewLedgerId] or viewLedgerId)))
    end
    if Dibs.IndependentRaid and Dibs.IndependentRaid.IsSessionActive and Dibs.IndependentRaid.IsSessionActive() then
      Dibs.Midnight.AddStatusBadge(shell, toolbar, "warning", "Independent Raid Active (Session Points)")
    end
    return toolbar
  end

  frame.Refresh = function(self)
    Dibs.AceGUI.Clear(tabs)
    if Dibs.AceGUI.SetShellStatus then Dibs.AceGUI.SetShellStatus(shell) end
    if self.playerTab ~= "diagnostics" then stopAutoPing() end
    if self.playerTab == "vault" then
      renderVaultHistory(shell, tabs, self, playerContentWidthHint())
      return
    end
    if self.playerTab == "preferences" then
      local page = Dibs.AceGUI.AddTablePage(shell, tabs, {
        footer = true, boundsFrame = tabs.content or tabs.frame,
      })
      if not page then return end
      Dibs.AceGUI.AddHeading(shell, page.header,
        helpText.MINIMAP_SETTINGS_TITLE or "Player preferences",
        helpText.MINIMAP_SETTINGS_DESCRIPTION or "Personal display preferences for this character.")
      local section = Dibs.AceGUI.AddSection(shell, page.header,
        helpText.MINIMAP_SETTINGS_SECTION or "Minimap",
        helpText.MINIMAP_SETTINGS_HELP or "Choose whether the Dibs shortcut appears beside the minimap, and adjust its size.")
      local visible = Dibs.MinimapButton and Dibs.MinimapButton.GetVisible and Dibs.MinimapButton.GetVisible() or true
      self.minimapButtonToggle = Dibs.AceGUI.AddCheckBox(shell, section,
        helpText.MINIMAP_SETTINGS_CHECKBOX or "Show Dibs minimap icon", visible, function(value)
          if Dibs.MinimapButton and Dibs.MinimapButton.SetVisible then
            local ok, reason = Dibs.MinimapButton.SetVisible(value)
            if not ok then
              Dibs.Message((helpText.MINIMAP_SETTINGS_FAILED or "Unable to update the minimap icon: %s"):format(tostring(reason or "unknown error")))
            end
          end
        end, 360)
      local scaleLabel = helpText.MINIMAP_SETTINGS_SCALE or "Icon size (%)"
      local minimapModule = Dibs.MinimapButton
      local currentScale = minimapModule and minimapModule.GetScale and minimapModule.GetScale() or 1
      self.minimapButtonScale = Dibs.AceGUI.AddRange(shell, section, scaleLabel, 50, 200, 5,
        math.floor(currentScale * 100 + 0.5), function(value)
          if minimapModule and minimapModule.SetScale then
            local ok, reason = minimapModule.SetScale((tonumber(value) or 100) / 100)
            if not ok then
              Dibs.Message((helpText.MINIMAP_SETTINGS_FAILED or "Unable to update the minimap icon: %s"):format(tostring(reason or "unknown error")))
            end
          end
        end, 360)
      self.minimapButtonReset = Dibs.AceGUI.AddButton(shell, section,
        helpText.MINIMAP_SETTINGS_RESET or "Reset position and size", function()
          if minimapModule and minimapModule.ResetLayout then
            local ok, reason = minimapModule.ResetLayout()
            if not ok then
              Dibs.Message((helpText.MINIMAP_SETTINGS_FAILED or "Unable to update the minimap icon: %s"):format(tostring(reason or "unknown error")))
              return
            end
            if self.minimapButtonScale then Dibs.AceGUI.SetValue(self.minimapButtonScale, 100) end
          end
        end, 220)
      Dibs.AceGUI.AddLabel(shell, section,
        helpText.MINIMAP_SETTINGS_COMMAND or "Drag the icon to move it around the minimap. You can also use /dibs minimap show|hide|scale <50-200>|reset. These preferences are saved for this character.",
        true)
      page.UpdateViewportHeight()
      return
    end
    local viewLedgerId = Dibs.MultiLedger and Dibs.MultiLedger.GetViewLedgerId and Dibs.MultiLedger.GetViewLedgerId() or nil
    local view = Dibs.PlayerUI.GetViewModel(nil, self.historyFilters, viewLedgerId)
    if self.playerTab == "diagnostics" then
      local diagnosticsPage = Dibs.AceGUI.AddTablePage(shell, tabs, {
        footer = true, boundsFrame = tabs.content or tabs.frame,
      })
      if not diagnosticsPage then return end
      self.diagnosticsTablePage = diagnosticsPage
      local diagnosticsHeader = diagnosticsPage.header
      Dibs.AceGUI.AddHeading(shell, diagnosticsHeader, "Diagnostics", "Local sync transport tests and debug controls.")
      local syncSection = Dibs.AceGUI.AddSection(shell, diagnosticsHeader, "Guild synchronization",
        "Current guild scope, synchronization state, and protocol readiness.")
      self.guildDiagnosticsSection = syncSection
      self.guildScopeLabel = Dibs.AceGUI.AddLabel(shell, syncSection,
        "Guild sync scope: " .. tostring(Dibs.GetGuildKey and Dibs.GetGuildKey() or "unknown"), true)
      local syncStatus = Dibs.Sync and Dibs.Sync.GetStatus and Dibs.Sync.GetStatus() or {}
      local syncDetails = Dibs.Sync and Dibs.Sync.GetSynchronizationStatus and Dibs.Sync.GetSynchronizationStatus() or {}
      local policyStatus = type(syncDetails.operationalPolicyAdopted) == "boolean"
        and (syncDetails.operationalPolicyAdopted and "Adopted" or "Not adopted") or "Unknown"
      local syncLines = {
        "Guild sync: " .. tostring(syncStatus.state or "Unknown"),
        "Protocol: " .. tostring(syncStatus.protocolState or "Unknown"),
        "Guild policy: " .. policyStatus,
      }
      if syncStatus.syncBehind then table.insert(syncLines, "Guild data is catching up.") end
      if syncStatus.reason then table.insert(syncLines, "Sync detail: " .. tostring(syncStatus.reason)) end
      if syncDetails.lastProtocolMismatch then
        table.insert(syncLines, "Last protocol mismatch: " .. tostring(syncDetails.lastProtocolMismatch.sender or "unknown peer"))
      end
      if syncDetails.lastAddonVersionMismatch then
        table.insert(syncLines, "Last addon version mismatch: " .. tostring(syncDetails.lastAddonVersionMismatch.sender or "unknown peer"))
      end
      self.guildSyncStatusLabel = Dibs.AceGUI.AddLabel(shell, syncSection, table.concat(syncLines, "\n"), true)
      local devEnabled = Dibs.DeveloperMode and Dibs.DeveloperMode.IsEnabled and Dibs.DeveloperMode.IsEnabled() or false
      self.developerModeToggle = Dibs.AceGUI.AddCheckBox(shell, syncSection, "Enable Developer Mode", devEnabled, function(value)
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
        self.channelTestReceivedStatus = Dibs.AceGUI.AddLabel(shell, syncSection, string.format("Last received probe: %s from %s at %s (%s).",
          tostring(receivedProbe.channel or "unknown channel"), tostring(receivedProbe.peer or "unknown sender"),
          receivedTime, tostring(receivedProbe.reasonCode or receivedProbe.status or "unknown result")), true)
      end
      if not devEnabled then
        Dibs.AceGUI.AddLabel(shell, syncSection, "Enable Developer Mode on both the sender and any client expected to reply. This setting is also controlled by /dibs dev on and /dibs dev off.", true)
        diagnosticsPage.UpdateViewportHeight()
        return
      end

      local channelTest = Dibs.AceGUI.AddSection(shell, diagnosticsHeader, "Transport channel test",
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
      local measureText = Dibs.AceGUI.MeasureTextWidth or function(text) return #tostring(text or "") * 8 end
      local matrixWidthHint = playerContentWidthHint()
      local customTitle = latestByChannel.CHANNEL and latestByChannel.CHANNEL.channelName or "Custom"
      local customMinimumWidth = math.max(52, math.min(measureText(customTitle) + 12,
        matrixWidthHint - 26 - (6 * 24) - 60))
      local matrixChannelColumns = {
        { title = "Guild", width = 58, minWidth = 24, wrap = true, weight = 1 },
        { title = "Officer", width = 65, minWidth = 24, wrap = true, weight = 1 },
        { title = "Raid", width = 50, minWidth = 24, wrap = true, weight = 1 },
        { title = "Party", width = 55, minWidth = 24, wrap = true, weight = 1 },
        { title = "Instance", width = 66, minWidth = 24, wrap = true, weight = 1 },
        { title = "Whisper", width = 65, minWidth = 24, wrap = true, weight = 1 },
        { title = customTitle, width = 65, minWidth = customMinimumWidth, weight = 1 },
      }
      local channelMinimumWidth = 0
      for _, column in ipairs(matrixChannelColumns) do
        channelMinimumWidth = channelMinimumWidth + column.minWidth
      end
      local measuredPlayerWidth = 120
      for _, row in ipairs(allRows) do
        measuredPlayerWidth = math.max(measuredPlayerWidth, measureText(row[1]) + 16)
      end
      local maxPlayerWidth = matrixWidthHint - channelMinimumWidth - 26
      local playerColumnWidth = math.max(60, math.min(measuredPlayerWidth, maxPlayerWidth))
      local matrixColumns = {
        { title = "Player", width = playerColumnWidth, minWidth = playerColumnWidth, fixed = true },
      }
      for _, column in ipairs(matrixChannelColumns) do matrixColumns[#matrixColumns + 1] = column end
      self.channelTestMatrix = Dibs.AceGUI.AddTable(shell, diagnosticsPage.scroll, matrixColumns,
        self.channelTestMatrixRows, 300, nil, {
        fluidColumns = true, widthHint = matrixWidthHint, allowTableSort = false,
        noScrolling = true, headerParent = diagnosticsPage.columnHeader, scrollbarReserve = 26,
      })
      local pagination = Dibs.AceGUI.AddInlineGroup(shell, diagnosticsPage.footer)
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
      self.channelTestSummary = Dibs.AceGUI.AddLabel(shell, diagnosticsPage.footer, table.concat(summaries, "\n"), true)
      diagnosticsPage.UpdateViewportHeight()
      scheduleAutoPing()
      return
    end
    if self.playerTab == "requests" then
      -- This page belongs to the review-request module; Pre-Dib reservations
      -- live on My Dibs so disabling reports never hides them.
      local page = Dibs.AceGUI.AddScrollableList(shell, tabs, 535) or tabs
      local pageWidth = math.max(320, playerContentWidthHint() - 26)
      Dibs.AceGUI.AddHeading(shell, page, helpText.PLAYER_NAV_REPORTS or "Reports",
        helpText.PLAYER_REQUESTS_HELP or "Report a wrong Dib or a Dib removed without loot, then follow the Officer review.")
      addActiveLedgerToolbar(page)
      renderReviewRequests(shell, page, self, Dibs.PlayerUI.GetSummary(), { widthHint = pageWidth })
      return
    end
    if self.playerTab == "history" then
      Dibs.AceGUI.AddHeading(shell, tabs, "History", "Your Dibs activity for the current season.")
      addActiveLedgerToolbar(tabs)
      addHistoryFilterControls(shell, tabs, self, "historyFilters", "history", playerContentWidthHint())
      if view.historyFilterError then Dibs.AceGUI.AddLabel(shell, tabs, view.historyFilterError, true) end
      local historyRows = {}
      for _, entry in ipairs(view.history or {}) do
        historyRows[#historyRows + 1] = { entry.date, entry.item, entry.action, entry.result, entry.balanceImpact, entry = entry }
      end
      Dibs.AceGUI.AddTable(shell, tabs, {
        { title = "Date", width = 145, minWidth = 100, weight = 1 },
        { title = "Item", width = 220, minWidth = 140, weight = 2 },
        { title = "Action", width = 130, minWidth = 95, weight = 1 },
        { title = "Result", width = 190, minWidth = 120, weight = 2 },
        { title = "Balance", width = 90, minWidth = 70, weight = 1 },
      }, historyRows, 300, nil, {
        allowTableSort = false,
        flatBackground = true,
        fluidColumns = true,
        widthHint = playerContentWidthHint(),
        scrollbarReserve = 26,
        shrinkToFit = true,
        hideScrollbarWhenFits = true,
        emptyText = view.historyFilterError or (hasActiveHistoryFilters(self.historyFilters)
          and helpText.HISTORY_FILTER_NO_RESULTS or view.empty.history),
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
        local detail = self.historyDetail
        self.historyDetailTitle = Dibs.AceGUI.AddHeading(shell, tabs, "History details", detail.item)
        Dibs.AceGUI.AddLabel(shell, tabs, "Item: " .. tostring(detail.item or "Unknown item"), true)
        Dibs.AceGUI.AddLabel(shell, tabs, "Date: " .. tostring(detail.date or "Unknown"), true)
        Dibs.AceGUI.AddLabel(shell, tabs, "Action: " .. tostring(detail.action or "Unknown"), true)
        Dibs.AceGUI.AddLabel(shell, tabs, "Result: " .. tostring(detail.result or "Unknown"), true)
        Dibs.AceGUI.AddLabel(shell, tabs, "Balance impact: " .. tostring(detail.balanceImpact or 0), true)
        self.historyReportButton = Dibs.AceGUI.AddButton(shell, tabs,
          helpText.PLAYER_REPORT_FROM_HISTORY or "Report a problem with this entry", function()
            self.disputeTransactionId = tostring(detail.transactionId or "")
            self.selectedDisputeRequestId = nil
            self.disputeStatusText = nil
            self.historyDetail = nil
            self.historyDetailTitle = nil
            self.historyDetailCloseButton = nil
            self.historyReportButton = nil
            self.SelectTab("requests")
          end, 260)
        self.historyDetailCloseButton = Dibs.AceGUI.AddButton(shell, tabs, "Close details", function()
          self.historyDetail = nil
          self.historyDetailTitle = nil
          self.historyDetailCloseButton = nil
          self.historyReportButton = nil
          self:Refresh()
        end, 130)
      end
      return
    end

    Dibs.AceGUI.AddHeading(shell, tabs, "My Dibs", "Your season allocation, Dibs use, and current balance.")
    Dibs.AceGUI.AddHeader(shell, tabs, view.seasonName, helpText.UI_HELP_SEASON)
    addActiveLedgerToolbar(tabs)
    Dibs.AceGUI.AddTable(shell, tabs, {
      { title = helpText.PLAYER_SEASON_ALLOCATION or "Season allocation", width = 180, minWidth = 120, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_SEASON },
      { title = helpText.PLAYER_DIBS_USED or "Dibs used", width = 150, minWidth = 100, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_DIB_BALANCE },
      { title = helpText.PLAYER_DIBS_REMAINING or "Dibs remaining", width = 180, minWidth = 120, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_DIB_BALANCE },
    }, {{ tostring(view.seasonAllocation), tostring(view.seasonUsed), tostring(view.balance) }}, 90,
      nil, {
        allowTableSort = false,
        flatBackground = true,
        fluidColumns = true,
        widthHint = playerContentWidthHint(),
        scrollbarReserve = 0,
        shrinkToFit = true,
        hideScrollbarWhenFits = true,
        contextMenu = function()
          return {
            { text = helpText.PLAYER_VIEW_REPORTS or "View Reports", callback = function() self.SelectTab("requests") end },
            { text = "View History", callback = function() self.SelectTab("history") end },
            { text = "Open Diagnostics", callback = function() self.SelectTab("diagnostics") end },
          }
        end,
      })
    Dibs.AceGUI.AddHeader(shell, tabs, view.status.label, view.status.explanation)
    local activeRows = {}
    for _, request in ipairs(view.activePreDibs or {}) do
      activeRows[#activeRows + 1] = {
        request.date, request.item, request.status, request.difficulty or "Any", "Cancel",
        request = request,
      }
    end
    Dibs.AceGUI.AddHeader(shell, tabs, helpText.PLAYER_ACTIVE_PREDIBS or "Active Pre-Dibs", helpText.UI_HELP_PREDIB)
    Dibs.AceGUI.AddTable(shell, tabs, {
      { title = "Date", width = 145, minWidth = 100, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_DATE },
      { title = "Item", width = 250, minWidth = 140, weight = 3, tooltip = helpText.UI_HELP_ITEM },
      { title = "Status", width = 120, minWidth = 88, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_REQUEST_STATUS },
      { title = "Difficulty", width = 100, minWidth = 75, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_DIFFICULTY },
      { title = "Action", width = 90, minWidth = 80, action = true, tooltip = helpText.UI_HELP_ACTION },
    }, activeRows, playerListHeight(#activeRows, 170), function(row)
      if not row.request then return nil end
      return {
        text = "Cancel",
        callback = function()
          local cancelled = Dibs.PlayerUI.CancelPreDib(row.request.requestId)
          self.preDibStatusText = cancelled and "Request cancelled." or "Unable to cancel this request."
          self:Refresh()
        end,
      }
    end, { allowTableSort = false, flatBackground = true, fluidColumns = true,
      widthHint = playerContentWidthHint(), shrinkToFit = true, hideScrollbarWhenFits = true,
      scrollbarReserve = 26, emptyText = view.empty.activePreDibs })
    local wonRows = {}
    for _, request in ipairs(view.wonPreDibs or {}) do
      wonRows[#wonRows + 1] = { request.date, request.item, request.difficulty or "Any", request.status }
    end
    Dibs.AceGUI.AddHeader(shell, tabs, helpText.PLAYER_FULFILLED_PREDIBS or "Won Pre-Dibs",
      "Pre-Dibs fulfilled by a finalized loot award.")
    Dibs.AceGUI.AddTable(shell, tabs, {
      { title = "Date", width = 145, minWidth = 100, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_DATE },
      { title = "Item", width = 300, minWidth = 160, weight = 3, tooltip = helpText.UI_HELP_ITEM },
      { title = "Difficulty", width = 120, minWidth = 80, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_DIFFICULTY },
      { title = "Status", width = 110, minWidth = 80, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_REQUEST_STATUS },
    }, wonRows, playerListHeight(#wonRows, 145), nil, { allowTableSort = false, flatBackground = true, fluidColumns = true,
      widthHint = playerContentWidthHint(), shrinkToFit = true, hideScrollbarWhenFits = true,
      scrollbarReserve = 26, emptyText = view.empty.wonPreDibs })
    local listedPreDibs = {}
    for _, request in ipairs(view.activePreDibs or {}) do listedPreDibs[request.requestId or false] = true end
    for _, request in ipairs(view.wonPreDibs or {}) do listedPreDibs[request.requestId or false] = true end
    local pastRows = {}
    for _, request in ipairs(view.requests or {}) do
      if not listedPreDibs[request.requestId or false] then
        pastRows[#pastRows + 1] = { formatDate(request.createdAt), request.item, request.status }
      end
    end
    Dibs.AceGUI.AddHeader(shell, tabs, helpText.PLAYER_PREDIB_HISTORY or "Past Pre-Dibs",
      helpText.PLAYER_PREDIB_HISTORY_HELP or "Cancelled, expired or otherwise closed Pre-Dibs.")
    Dibs.AceGUI.AddTable(shell, tabs, {
      { title = "Date", width = 145, minWidth = 100, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_DATE },
      { title = "Item", width = 300, minWidth = 160, weight = 3, tooltip = helpText.UI_HELP_ITEM },
      { title = "Status", width = 120, minWidth = 88, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_REQUEST_STATUS },
    }, pastRows, playerListHeight(#pastRows, 120), nil, { allowTableSort = false, flatBackground = true, fluidColumns = true,
      widthHint = playerContentWidthHint(), shrinkToFit = true, hideScrollbarWhenFits = true,
      scrollbarReserve = 26, emptyText = helpText.PLAYER_PREDIB_HISTORY_EMPTY or "No past Pre-Dibs." })
    addRequestAction(tabs, view)
  end

  shell.onRelease = function()
    stopAutoPing()
    for _, key in ipairs({
      "aceTabs", "preDibInput", "preDibButton", "preDibStatus", "preDibStatusText", "preDibValue", "devItemText",
      "devRequestButton", "devStatusText", "devStatus", "playerTab", "historyDetail", "historyMode", "historyPage",
      "guildDiagnosticsSection", "guildSyncStatusLabel", "historyDetailSection", "historyDetailCloseButton",
      "historyQuery", "eligibilityCharacter", "eligibilityStatus", "Refresh", "SelectTab", "dibsAceGUIShell", "_dibsUiShell",
      "developerModeToggle", "channelTestChannel", "channelTestTarget", "channelTestCustomChannelName", "channelTestStatus",
      "channelTestReceivedStatus",
      "channelTestSelector", "channelTestTargetInput", "channelTestCustomChannelInput", "channelTestRunButton",
      "channelTestScanButton", "channelTestRefreshButton", "channelTestAutoPingToggle", "channelTestMatrix",
      "channelTestMatrixRows", "channelTestMatrixPage", "channelTestPrevious", "channelTestPageLabel",
      "diagnosticsTablePage",
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
    local status = (Dibs.AceGUI and Dibs.AceGUI.BuildShellStatusText and Dibs.AceGUI.BuildShellStatusText() or "") .. "\n" ..
      "Season: " .. tostring((summary.season and summary.season.name) or "None") .. "\n" ..
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
      Dibs.Message("Developer Mode is disabled. Use /dibs dev on to enable test commands.", { chat = false })
      frame:Refresh()
      return
    end

    local context = frame.devContext or (Dibs.LootPipeline and Dibs.LootPipeline.GetPendingDevContext and Dibs.LootPipeline.GetPendingDevContext()) or nil
    if not context then
      Dibs.Message("[Dibs DEV] No injected test item. Use /dibs testitem <itemID>.", { chat = false })
      frame:Refresh()
      return
    end

    if Dibs.LootPipeline and Dibs.LootPipeline.RequestDibFromContext then
      local request, reason = Dibs.LootPipeline.RequestDibFromContext(context)
      if request then
        Dibs.Message("[Dibs DEV] Test Request Dib created for item " .. tostring(request.itemID) .. ".", { chat = false })
      elseif reason == "INVALID_ITEM" then
        Dibs.Message("[Dibs DEV] Invalid test item.", { chat = false })
      else
        Dibs.Message("[Dibs DEV] Unable to create test Request Dib.", { chat = false })
      end
    else
      Dibs.Message("[Dibs DEV] Loot pipeline unavailable.", { chat = false })
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

  return Dibs.PlayerUI.GetSummary()
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
