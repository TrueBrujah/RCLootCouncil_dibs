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

function Dibs.PlayerUI.RenderSeasonIdentity(shell, parent, frame, season)
  local ui, labels, service = Dibs.AceGUI, Dibs.L or {}, Dibs.SeasonalRoster
  ui.AddHeader(shell, parent, labels.SEASONAL_ROSTER_IDENTITY)
  ui.AddLabel(shell, parent, labels.SEASONAL_ROSTER_IDENTITY_HELP, true)
  if not service.DeclareRelationship or not service.RequestMainChange then return end
  local actor = Dibs.GetPlayerName()
  local review, failure = service.GetSeasonIdentityReview(season.seasonId)
  if not review then ui.AddLabel(shell, parent, Dibs.OfficerUI.SeasonalText(failure), true); return end
  local projection = Dibs.CharacterEligibility and Dibs.CharacterEligibility.GetPersonProjection(actor, season.seasonId)
  ui.AddLabel(shell, parent, labels.SEASONAL_ROSTER_MAIN .. ": " .. tostring(projection and projection.mainCharacterKey or actor), true)
  local probation = Dibs.CharacterEligibility and Dibs.CharacterEligibility.GetProbation(actor, season.seasonId)
  if probation then ui.AddLabel(shell, parent, string.format(labels.SEASONAL_ROSTER_PROBATION,
    date("%Y-%m-%d %H:%M", probation.probationEndsAt), probation.approverName or probation.approverId or "—"), true) end
  local rows = {}
  for _, relationship in ipairs(review.relationships or {}) do rows[#rows + 1] = {
    relationship.mainCharacterName or relationship.mainCharacterId,
    relationship.altCharacterName or relationship.altCharacterId, Dibs.OfficerUI.SeasonalText(relationship.status) } end
  for _, change in ipairs(review.mainChanges or {}) do rows[#rows + 1] = {
    change.oldMainName or change.oldMainId, change.newMainName or change.newMainId, Dibs.OfficerUI.SeasonalText(change.status) } end
  local page = math.max(1, math.min(frame.seasonIdentityPage or 1, math.max(1, math.ceil(#rows / 20))))
  local visible = {}
  for index = (page - 1) * 20 + 1, math.min(page * 20, #rows) do visible[#visible + 1] = rows[index] end
  ui.AddTable(shell, parent, { { title = labels.SEASONAL_ROSTER_MAIN, width = 180, minWidth = 100, weight = 2 },
    { title = labels.SEASONAL_ROSTER_ALT_CHARACTER, width = 200, minWidth = 100, weight = 2 },
    { title = labels.SEASONAL_ROSTER_ENROLLMENT_STATUS, width = 120, minWidth = 80, weight = 1 } }, visible, 150, nil,
    { fluidColumns = true, widthHint = 680, shrinkToFit = true, emptyText = labels.SEASONAL_ROSTER_EMPTY })
  local pager = ui.AddPaginationFooter(shell, { footer = ui.AddInlineGroup(shell, parent) }, {
    showPageSize = false, onPrevious = function() frame.seasonIdentityPage = page - 1; frame:Refresh() end,
    onNext = function() frame.seasonIdentityPage = page + 1; frame:Refresh() end })
  if pager then pager.UpdateState(page, #rows, 20) end
  if (season.lifecycle or {}).readOnly then return end
  local target = ui.AddEditBox(shell, parent, labels.SEASONAL_ROSTER_ALT_CHARACTER,
    function(value) frame.seasonIdentityCharacter = value or "" end, 300)
  if target and target.SetText then target:SetText(frame.seasonIdentityCharacter or "") end
  local reason = ui.AddEditBox(shell, parent, labels.SEASONAL_ROSTER_REVIEW_REASON,
    function(value) frame.seasonIdentityReason = value or "" end, 360)
  if reason and reason.SetText then reason:SetText(frame.seasonIdentityReason or "") end
  for _, action in ipairs({ "DeclareRelationship", "RequestMainChange" }) do
    ui.AddButton(shell, parent, action == "DeclareRelationship" and labels.SEASONAL_ROSTER_DECLARE_ALT or labels.SEASONAL_ROSTER_REQUEST_MAIN,
      function()
        local input = action == "DeclareRelationship" and { mainCharacter = actor, altCharacter = frame.seasonIdentityCharacter,
          reason = frame.seasonIdentityReason } or { oldMain = actor, newMain = frame.seasonIdentityCharacter, reason = frame.seasonIdentityReason }
        local result = service[action](season.seasonId, input, review.revision, Dibs.NewId("season-identity"))
        frame.seasonalRosterMessage = result and result.ok and labels.SEASONAL_ROSTER_IDENTITY_SUBMITTED
          or Dibs.OfficerUI.SeasonalText(result and result.code or "SERVICE_UNAVAILABLE")
        frame:Refresh()
      end, 260)
  end
end
local helpText = Dibs.L or {}
local playerPreDibSummaryCache

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

local guildCharacterRosterCache = { generation = nil, members = {} }
local GUILD_CHARACTER_ONLINE_PAGE_SIZE = 100
local GUILD_CHARACTER_OFFLINE_PAGE_SIZE = 50

local function getGuildCharacterChoices(search, currentCharacter)
  local identity = Dibs.Identity
  if not identity or type(identity.GetRosterSnapshot) ~= "function"
    or type(identity.GetInvalidationGeneration) ~= "function" then
    return {}, {}, { error = "ROSTER_API_UNAVAILABLE" }
  end
  local generation = identity.GetInvalidationGeneration()
  if guildCharacterRosterCache.generation ~= generation then
    local snapshot, reason = identity.GetRosterSnapshot()
    if not snapshot then return {}, {}, { error = reason or "ROSTER_UNAVAILABLE" } end
    local members = {}
    for _, member in ipairs(snapshot) do
      if type(member) == "table" and type(member.displayName) == "string"
        and member.displayName ~= "" then
        members[#members + 1] = { name = member.displayName, online = member.online == true }
      end
    end
    guildCharacterRosterCache = { generation = identity.GetInvalidationGeneration(), members = members }
  end

  local currentKey = identity.CanonicalMemberKey(currentCharacter or "")
  local query = string.lower(trimText(search))
  local onlineChoices, offlineChoices, onlineTotal, offlineTotal, onlineShown, offlineShown = {}, {}, 0, 0, 0, 0
  local firstOnline, firstOffline
  for _, member in ipairs(guildCharacterRosterCache.members) do
    local memberKey = identity.CanonicalMemberKey(member.name)
    if memberKey and memberKey ~= currentKey
      and (query == "" or string.find(string.lower(member.name), query, 1, true)) then
      if member.online then
        onlineTotal = onlineTotal + 1
        if onlineShown < GUILD_CHARACTER_ONLINE_PAGE_SIZE then
          onlineChoices[member.name] = member.name
          onlineShown = onlineShown + 1
          firstOnline = firstOnline or member.name
        end
      else
        offlineTotal = offlineTotal + 1
        if offlineShown < GUILD_CHARACTER_OFFLINE_PAGE_SIZE then
          offlineChoices[member.name] = member.name
          offlineShown = offlineShown + 1
          firstOffline = firstOffline or member.name
        end
      end
    end
  end
  return onlineChoices, offlineChoices, { onlineTotal = onlineTotal, offlineTotal = offlineTotal,
    firstOnline = firstOnline, firstOffline = firstOffline, search = query }
end

local function addEligibilityCharacterPicker(shell, parent, frame, currentCharacter, labels)
  labels = labels or {}
  Dibs.AceGUI.AddLabel(shell, parent,
    (labels.PLAYER_ELIGIBILITY_CURRENT_MAIN or "Current character (selected Main): %s"):format(currentCharacter), true)
  local searchInput = Dibs.AceGUI.AddEditBox(shell, parent,
    labels.PLAYER_ELIGIBILITY_GUILD_SEARCH or "Search guild characters", function(value)
      frame.eligibilitySearchDraft = value or ""
    end, 240)
  setControlText(searchInput, frame.eligibilitySearchDraft or frame.eligibilitySearch or "")
  Dibs.AceGUI.AddButton(shell, parent, labels.PLAYER_ELIGIBILITY_SEARCH or "Search", function()
    frame.eligibilitySearch = trimText(frame.eligibilitySearchDraft or "")
    frame.eligibilityCharacter = nil
    frame:Refresh()
  end, 90)

  local onlineChoices, offlineChoices, info = getGuildCharacterChoices(
    frame.eligibilitySearch or "", currentCharacter)
  if info.error then
    Dibs.AceGUI.AddLabel(shell, parent,
      (labels.PLAYER_ELIGIBILITY_ROSTER_UNAVAILABLE or "Guild roster unavailable: %s"):format(info.error), true)
    return nil
  end
  local selected = frame.eligibilityCharacter
  if not selected or (onlineChoices[selected] == nil and offlineChoices[selected] == nil) then
    selected = info.firstOnline or info.firstOffline
    frame.eligibilityCharacter = selected
  end
  local onlineTitle = info.onlineTotal > GUILD_CHARACTER_ONLINE_PAGE_SIZE
      and (labels.PLAYER_ELIGIBILITY_ONLINE_MORE or "Online guild characters (%d; showing %d)")
        :format(info.onlineTotal, GUILD_CHARACTER_ONLINE_PAGE_SIZE)
      or (labels.PLAYER_ELIGIBILITY_ONLINE_CHARACTERS or "Online guild characters (%d)"):format(info.onlineTotal)
  Dibs.AceGUI.AddLabel(shell, parent, onlineTitle, true)
  local onlineDropdown = Dibs.AceGUI.AddDropdown(shell, parent,
    labels.PLAYER_ELIGIBILITY_ONLINE_LIST or "Online", onlineChoices, function(value)
      frame.eligibilityCharacter = value
    end, 280)
  if selected and onlineChoices[selected] then Dibs.AceGUI.SetValue(onlineDropdown, selected) end
  local offlineTitle = info.offlineTotal > GUILD_CHARACTER_OFFLINE_PAGE_SIZE
      and (labels.PLAYER_ELIGIBILITY_OFFLINE_MORE or "Other guild characters (%d; showing %d)")
        :format(info.offlineTotal, GUILD_CHARACTER_OFFLINE_PAGE_SIZE)
      or (labels.PLAYER_ELIGIBILITY_OFFLINE_CHARACTERS or "Other guild characters (%d)"):format(info.offlineTotal)
  Dibs.AceGUI.AddLabel(shell, parent, offlineTitle, true)
  local offlineDropdown = Dibs.AceGUI.AddDropdown(shell, parent,
    labels.PLAYER_ELIGIBILITY_OFFLINE_LIST or "Offline / remaining", offlineChoices, function(value)
      frame.eligibilityCharacter = value
    end, 280)
  if selected and offlineChoices[selected] then Dibs.AceGUI.SetValue(offlineDropdown, selected) end
  return selected
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

local function playerPageSlice(frame, key, rows, pageSize)
  local visible, page, total = Dibs.AceGUI.GetPageSlice(rows, frame[key] or 1, pageSize)
  frame[key] = page
  return visible, page, total
end

local function projectPlayerRequestPage(source, requestedPage, pageSize, project)
  local total = #source
  local pages = math.max(1, math.ceil(total / pageSize))
  local page = math.max(1, math.min(pages, math.floor(tonumber(requestedPage) or 1)))
  local first = (page - 1) * pageSize + 1
  local rows = {}
  for index = first, math.min(total, first + pageSize - 1) do
    rows[#rows + 1] = project(source[index])
  end
  return rows, { page = page, pages = pages, count = total }
end

local function addPlayerPager(shell, parent, frame, key, page, total, pageLabel)
  if total <= 1 then return end
  local controls = Dibs.AceGUI.AddInlineGroup(shell, parent)
  local previous = Dibs.AceGUI.AddButton(shell, controls, "Previous", function()
    frame[key] = math.max(1, (frame[key] or page) - 1)
    frame:Refresh()
  end, 90)
  Dibs.AceGUI.SetDisabled(previous, page <= 1)
  Dibs.AceGUI.AddLabel(shell, controls,
    string.format(pageLabel or "Page %d / %d", page, total), false)
  local nextPage = Dibs.AceGUI.AddButton(shell, controls, "Next", function()
    frame[key] = math.min(total, (frame[key] or page) + 1)
    frame:Refresh()
  end, 70)
  Dibs.AceGUI.SetDisabled(nextPage, page >= total)
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
  { text = (Dibs.L or {}).PLAYER_NAV_SEASONAL_ROSTER or "Raid Roster", value = "seasonal-roster", module = "seasonalRoster" },
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
  local source = type(filter.requests) == "table" and filter.requests
    or (Dibs.Disputes and Dibs.Disputes.ListForPlayer
      and Dibs.Disputes.ListForPlayer(Dibs.GetPlayerName and Dibs.GetPlayerName() or nil, filter) or {})
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
function Dibs.PlayerUI.GetSummary(playerName, ledgerId, options)
  local renderStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  options = type(options) == "table" and options or {}
  local season = Dibs.Seasons and Dibs.Seasons.GetCurrent() or nil
  local currentPlayer = playerName or Dibs.GetPlayerName()
  local historySummary = Dibs.Ledger and Dibs.Ledger.GetPlayerHistorySummary
    and Dibs.Ledger.GetPlayerHistorySummary(currentPlayer, season and season.id, ledgerId) or nil
  local canonical = not historySummary and Dibs.Ledger and Dibs.Ledger.GetCanonicalPlayerDibsState
    and Dibs.Ledger.GetCanonicalPlayerDibsState(season and season.id, currentPlayer, ledgerId) or nil
  local playerState = not historySummary and Dibs.Ledger and Dibs.Ledger.GetPlayerState
    and Dibs.Ledger.GetPlayerState(currentPlayer, season and season.id, ledgerId) or {}
  local used = historySummary and historySummary.seasonUsed or 0
  if not historySummary then
    local transactions = Dibs.Ledger and Dibs.Ledger.GetHistory
      and Dibs.Ledger.GetHistory(currentPlayer, season and season.id, ledgerId) or {}
    for _, transaction in ipairs(transactions) do
      local amount = tonumber(transaction.amount or transaction.quantityDelta) or 0
      if transaction.type == "DIB_USED" then
        used = used + math.max(0, -amount)
      elseif transaction.type == "DIB_REFUNDED" then
        used = math.max(0, used - math.max(0, amount))
      end
    end
  end
  local requestSummary
  local preDibs = Dibs.PreDibs
  if options.includeRequests ~= false and preDibs and type(preDibs.GetPlayerSeasonRequestSummary) == "function" then
    local requestSummaryCacheStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
    local revision = preDibs.GetHistoryRevisionFast and preDibs.GetHistoryRevisionFast(ledgerId) or nil
    local playerKey = string.lower(tostring(currentPlayer or ""))
    local seasonKey = tostring(season and season.id or "*")
    local ledgerKey = tostring(ledgerId or (Dibs.MultiLedger and Dibs.MultiLedger.GetActiveLedgerId
      and Dibs.MultiLedger.GetActiveLedgerId()) or "guild-primary")
    if revision ~= nil and playerPreDibSummaryCache
      and playerPreDibSummaryCache.player == playerKey
      and playerPreDibSummaryCache.season == seasonKey
      and playerPreDibSummaryCache.ledger == ledgerKey
      and playerPreDibSummaryCache.revision == revision then
      requestSummary = playerPreDibSummaryCache.summary
      if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
        Dibs.UIRenderStats.Record("Player data", "predib-ui-summary-hit", requestSummaryCacheStartedAt)
      end
    else
      requestSummary = preDibs.GetPlayerSeasonRequestSummary(currentPlayer, season and season.id, ledgerKey)
      if revision ~= nil and requestSummary then
        playerPreDibSummaryCache = {
          player = playerKey, season = seasonKey, ledger = ledgerKey,
          revision = revision, summary = requestSummary,
        }
      end
      if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
        Dibs.UIRenderStats.Record("Player data", "predib-ui-summary-miss", requestSummaryCacheStartedAt)
      end
    end
  end
  local requests = options.includeRequests == false and {}
    or requestSummary and requestSummary.active
    or (Dibs.PreDibs and Dibs.PreDibs.GetActiveRequests(currentPlayer, ledgerId) or {})
  local activePreDibs = requestSummary and requests or {}
  if not requestSummary then
    for _, request in ipairs(requests) do
      if not season or request.seasonId == season.id then activePreDibs[#activePreDibs + 1] = request end
    end
  end
  local wonPreDibs = options.includeRequests == false and {}
    or requestSummary and requestSummary.fulfilled or {}
  if options.includeRequests ~= false and not requestSummary then
    wonPreDibs = {}
    local playerKey = string.lower(tostring(currentPlayer or ""))
    local requestHistory = Dibs.PreDibs and Dibs.PreDibs.GetRequestsForPlayer
      and Dibs.PreDibs.GetRequestsForPlayer(currentPlayer, ledgerId)
      or (Dibs.PreDibs and Dibs.PreDibs.GetHistory and Dibs.PreDibs.GetHistory(ledgerId) or {})
    for _, request in ipairs(requestHistory) do
      if string.lower(tostring(request.playerName or "")) == playerKey and request.status == "fulfilled"
        and (not season or request.seasonId == season.id) then
        wonPreDibs[#wonPreDibs + 1] = request
      end
    end
    table.sort(wonPreDibs, function(first, second)
      return (first.fulfilledAt or first.updatedAt or first.createdAt or 0)
        > (second.fulfilledAt or second.updatedAt or second.createdAt or 0)
    end)
  end
  local acquisitions = {}
  if options.includeAcquisitions ~= false then
    acquisitions = Dibs.PreDibs and Dibs.PreDibs.GetAcquisitionsForPlayer
      and Dibs.PreDibs.GetAcquisitionsForPlayer(currentPlayer) or {}
    if Dibs.PreDibs and Dibs.PreDibs.ProjectVaultAcquisition then
      local projected = {}
      for _, acquisition in ipairs(acquisitions) do
        local entry = Dibs.PreDibs.ProjectVaultAcquisition(acquisition, "player")
        entry.status = Dibs.PlayerUI.GetVaultAcquisitionPresentation(entry)
        projected[#projected + 1] = entry
      end
      acquisitions = projected
    end
  end
  local eligibility = options.includeEligibility ~= false and Dibs.CharacterEligibility and Dibs.CharacterEligibility.GetSummary
    and Dibs.CharacterEligibility.GetSummary(currentPlayer, season and season.id) or nil

  local summary = {
    season = season,
    player = currentPlayer,
    balance = historySummary and historySummary.balance or (canonical and canonical.balance or 0),
    balanceState = canonical,
    seasonAllocation = historySummary and historySummary.allocation or (tonumber(playerState.allocation) or 0),
    seasonUsed = used,
    activePreDibs = activePreDibs,
    wonPreDibs = wonPreDibs,
    predibsRequestSummary = requestSummary,
    acquisitions = acquisitions,
    eligibility = eligibility,
    modePolicy = options.includeModePolicy ~= false and Dibs.PreDibs and Dibs.PreDibs.GetModePolicy
      and Dibs.PreDibs.GetModePolicy(season and season.id) or nil,
  }
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Player data", "summary", renderStartedAt)
  end
  return summary
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

function Dibs.PlayerUI.GetIntegrationState(result)
  result = type(result) == "table" and result or {}
  local availability = string.lower(tostring(result.availability or result.status or ""))
  if availability == "operational" or availability == "ready" then return { status = "Ready" } end
  if availability == "degraded" or availability == "limited" then return { status = "Degraded" } end
  return { status = "Unavailable" }
end

local function playerRequestHistory(playerName, activeRequests, ledgerId)
  local renderStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local history = {}
  local active = {}
  for _, request in ipairs(activeRequests or {}) do
    active[request.requestId] = true
  end
  local sortedSource = Dibs.PreDibs and Dibs.PreDibs.GetRecentRequestsForPlayer
  local source = sortedSource and sortedSource(playerName, ledgerId)
    or (Dibs.PreDibs and Dibs.PreDibs.GetRequestsForPlayer
      and Dibs.PreDibs.GetRequestsForPlayer(playerName, ledgerId))
    or (Dibs.PreDibs and Dibs.PreDibs.GetHistory and Dibs.PreDibs.GetHistory(ledgerId) or {})
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
  if not sortedSource then
    table.sort(history, function(first, second)
      return (first.createdAt or 0) > (second.createdAt or 0)
    end)
  end
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Player data", "predib-history", renderStartedAt)
  end
  return history
end

local playerPastRequestPageCache
local function playerPastRequestPage(playerName, activeRequests, wonRequests, requestSummary, ledgerId, requestedPage, pageSize)
  local cacheCheckStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local predibs = Dibs.PreDibs
  local source, sortedSource, prefilteredPast
  if type(requestSummary) == "table" and type(requestSummary.pastRequests) == "table" then
    source, sortedSource, prefilteredPast = requestSummary.pastRequests, true, true
  elseif type(requestSummary) == "table" and type(requestSummary.recentRequests) == "table" then
    source, sortedSource = requestSummary.recentRequests, true
  elseif predibs and type(predibs.GetRecentRequestsForPlayer) == "function" then
    source, sortedSource = predibs.GetRecentRequestsForPlayer(playerName, ledgerId), true
  elseif predibs and type(predibs.GetRequestsForPlayer) == "function" then
    source = predibs.GetRequestsForPlayer(playerName, ledgerId)
  else
    source = predibs and predibs.GetHistory and predibs.GetHistory(ledgerId) or {}
  end
  source = type(source) == "table" and source or {}

  local playerKey = string.lower(tostring(playerName or ""))
  local size = math.max(1, math.min(50, math.floor(tonumber(pageSize) or 10)))
  local page = math.max(1, math.floor(tonumber(requestedPage) or 1))
  if sortedSource and playerPastRequestPageCache
    and playerPastRequestPageCache.source == source
    and playerPastRequestPageCache.summary == requestSummary
    and playerPastRequestPageCache.active == activeRequests
    and playerPastRequestPageCache.won == wonRequests
    and playerPastRequestPageCache.player == playerKey
    and playerPastRequestPageCache.page == page
    and playerPastRequestPageCache.size == size then
    if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
      Dibs.UIRenderStats.Record("Player data", "predib-page-hit", cacheCheckStartedAt)
    end
    return playerPastRequestPageCache.value
  end
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Player data", "predib-page-miss", cacheCheckStartedAt)
  end
  local pageBuildStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local active, won = {}, {}
  if not prefilteredPast then
    for _, request in ipairs(activeRequests or {}) do active[request.requestId] = true end
    for _, request in ipairs(wonRequests or {}) do won[request.requestId] = true end
  end

  local function collect(startIndex, endIndex)
    local rows, count = {}, 0
    if prefilteredPast then
      count = #source
      for index = startIndex, math.min(endIndex, count) do
        local request = source[index]
        rows[#rows + 1] = {
          createdAt = request.createdAt or request.updatedAt,
          item = request.itemName or request.itemLink or ("Item " .. tostring(request.itemID or "?")),
          status = tostring(request.status or "Pending"),
        }
      end
      return rows, count
    end
    for _, request in ipairs(source) do
      if string.lower(tostring(request.playerName or "")) == playerKey
        and not active[request.requestId or false] and not won[request.requestId or false] then
        count = count + 1
        if count >= startIndex and count <= endIndex then
          rows[#rows + 1] = {
            createdAt = request.createdAt or request.updatedAt,
            item = request.itemName or request.itemLink or ("Item " .. tostring(request.itemID or "?")),
            status = tostring(request.status or "Pending"),
          }
        end
      end
    end
    return rows, count
  end

  if not sortedSource then
    local sorted = {}
    for _, request in ipairs(source) do
      if string.lower(tostring(request.playerName or "")) == playerKey then sorted[#sorted + 1] = request end
    end
    table.sort(sorted, function(first, second)
      return (tonumber(first.createdAt or first.updatedAt) or 0)
        > (tonumber(second.createdAt or second.updatedAt) or 0)
    end)
    source = sorted
  end

  local count = prefilteredPast and #source or nil
  if count then page = math.min(page, math.max(1, math.ceil(count / size))) end
  local first = (page - 1) * size + 1
  local rows
  rows, count = collect(first, first + size - 1)
  local pages = math.max(1, math.ceil(count / size))
  local currentPage = math.min(page, pages)
  if currentPage ~= page then
    first = (currentPage - 1) * size + 1
    rows = collect(first, first + size - 1)
  end
  local result = { rows = rows, count = count, page = currentPage, pages = pages, pageSize = size }
  if sortedSource then
    playerPastRequestPageCache = {
      source = source, active = activeRequests, won = wonRequests, player = playerKey,
      summary = requestSummary, page = page, size = size, value = result,
    }
  end
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Player data", "predib-page-build", pageBuildStartedAt)
  end
  return result
end

local function projectHistoryTransactions(entries)
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

local function projectHistory(playerName, seasonId, ledgerId)
  return projectHistoryTransactions(getPlayerTransactions(playerName, seasonId, "current", ledgerId))
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

function Dibs.PlayerUI.GetViewModel(playerName, historyFilters, ledgerId, options)
  local renderStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  options = type(options) == "table" and options or {}
  local summary = Dibs.PlayerUI.GetSummary(playerName, ledgerId, {
    includeAcquisitions = false,
    includeEligibility = options.includeEligibility == true,
    includeModePolicy = false,
  })
  local readiness = Dibs.Readiness and Dibs.Readiness.Evaluate and Dibs.Readiness.Evaluate({ allowPlayer = true }) or {}
  local activeSource = summary.activePreDibs or {}
  local active, activePage
  local function projectActiveRequest(request)
    return {
      requestId = request.requestId,
      date = formatDate(request.createdAt or request.updatedAt),
      item = request.itemName or request.itemLink or ("Item " .. tostring(request.itemID or "?")),
      status = tostring(request.status or "Pending"),
      difficulty = request.difficulty and tostring(request.difficulty) or nil,
      request = request,
    }
  end
  if options.pageActivePreDibs then
    active, activePage = projectPlayerRequestPage(activeSource, options.pageActivePreDibs, 10, projectActiveRequest)
  else
    active = {}
    for _, request in ipairs(activeSource) do active[#active + 1] = projectActiveRequest(request) end
  end
  local wonSource = summary.wonPreDibs or {}
  local won, wonPage
  local function projectWonRequest(request)
    return {
      requestId = request.requestId,
      date = formatDate(request.fulfilledAt or request.updatedAt or request.createdAt),
      item = request.itemName or request.itemLink or ("Item " .. tostring(request.itemID or "?")),
      difficulty = request.difficulty and tostring(request.difficulty) or nil,
      status = (Dibs.L or {}).PLAYER_PREDIB_WON_STATUS or "Won",
      request = request,
    }
  end
  if options.pageWonPreDibs then
    won, wonPage = projectPlayerRequestPage(wonSource, options.pageWonPreDibs, 10, projectWonRequest)
  else
    won = {}
    for _, request in ipairs(wonSource) do won[#won + 1] = projectWonRequest(request) end
  end
  local history = options.includeHistory == false and {}
    or projectHistory(summary.player, summary.season and summary.season.id, ledgerId)
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
  local pastPreDibPage
  local requests
  if options.pagePreDibHistory then
    local pastHistoryStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
    pastPreDibPage = playerPastRequestPage(summary.player, summary.activePreDibs, summary.wonPreDibs,
      summary.predibsRequestSummary, ledgerId, options.pagePreDibHistory, 10)
    if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
      Dibs.UIRenderStats.Record("Player data", "predib-history", pastHistoryStartedAt)
    end
    requests = {}
  else
    requests = playerRequestHistory(summary.player, summary.activePreDibs, ledgerId)
  end
  local view = {
    navigation = Dibs.PlayerUI.GetNavigation(),
    player = summary.player,
    season = summary.season,
    balance = summary.balance,
    eligibility = summary.eligibility,
    seasonAllocation = summary.seasonAllocation or 0,
    seasonUsed = summary.seasonUsed or 0,
    seasonName = summary.season and summary.season.name or "No active season",
    activePreDibs = active,
    activePreDibPage = activePage,
    wonPreDibs = won,
    wonPreDibPage = wonPage,
    requests = requests,
    pastPreDibPage = pastPreDibPage,
    pendingRequests = activePage and activePage.count or #active,
    history = history,
    historyFilterError = historyFilterError,
    status = Dibs.PlayerUI.GetStatusPresentation(readiness),
    empty = {
      activePreDibs = #active == 0 and ((Dibs.L or {}).PLAYER_NO_ACTIVE_PREDIBS or "No active Pre-Dibs this season.") or nil,
      wonPreDibs = #won == 0 and ((Dibs.L or {}).PLAYER_NO_FULFILLED_PREDIBS or "No won Pre-Dibs this season.") or nil,
      requests = (pastPreDibPage and pastPreDibPage.count == 0
        or not pastPreDibPage and #requests == 0) and "No requests yet." or nil,
      history = #history == 0 and "No history yet." or nil,
    },
  }
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Player data", "view-model", renderStartedAt)
  end
  return view
end

function Dibs.PlayerUI.GetHistoryViewModel(playerName, historyFilters, ledgerId, page, pageSize)
  local renderStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local season = Dibs.Seasons and Dibs.Seasons.GetCurrent and Dibs.Seasons.GetCurrent() or nil
  local player = playerName or (Dibs.GetPlayerName and Dibs.GetPlayerName())
  local paged = not hasActiveHistoryFilters(historyFilters)
    and Dibs.Ledger and type(Dibs.Ledger.GetHistoryPage) == "function"
  local history, total, currentPage
  if paged then
    local transactions
    transactions, total, currentPage = Dibs.Ledger.GetHistoryPage(player, season and season.id, ledgerId, page, pageSize)
    history = projectHistoryTransactions(transactions)
  else
    history = projectHistory(player, season and season.id, ledgerId)
  end
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
  local view = {
    player = player,
    season = season,
    history = history,
    paged = paged,
    total = total,
    page = currentPage,
    pageSize = paged and math.max(1, math.min(50, math.floor(tonumber(pageSize) or 20))) or nil,
    historyFilterError = historyFilterError,
    empty = { history = #history == 0 and "No history yet." or nil },
  }
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Player data", "history-view-model", renderStartedAt)
  end
  return view
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
      -- The page only needs the name; do not retain LootPipeline's full item object.
      cached.itemName = item and item.itemName or nil
      cached.reason = reason
      if not item and Dibs.Message then
        Dibs.Message("[GreatVault] " .. key .. ": " .. tostring(reason or "ITEM_LOAD_FAILED"), { chat = false })
      end
      if not synchronous and frame.playerTab == "vault"
        and (not frame.IsShown or frame:IsShown()) and frame.Refresh then frame:Refresh() end
    end)
    synchronous = false
  end
  if cached and cached.itemName then
    record.itemName = cached.itemName
  end
  return record
end

local function renderVaultCaptureStatus(shell, parent)
  local gui = Dibs.AceGUI
  local policy = Dibs.OperationalPolicy
  if policy and type(policy.RequireModuleEnabled) == "function"
    and not policy.RequireModuleEnabled("preDibs") then
    gui.AddLabel(shell, parent, helpText.PLAYER_VAULT_CAPTURE_DISABLED
      or "Automatic Great Vault capture is disabled by guild policy.", true)
    return
  end
  local adapter = Dibs.GreatVault
  local capture = adapter and type(adapter.GetCaptureStatus) == "function" and adapter.GetCaptureStatus() or nil
  if type(capture) ~= "table" then capture = nil end
  if not capture or capture.status ~= "OPERATIONAL" then
    gui.AddLabel(shell, parent, helpText.PLAYER_VAULT_CAPTURE_UNAVAILABLE
      or "Automatic Great Vault capture is unavailable on this client.", true)
    local reason = capture and helpText["VAULT_REASON_" .. tostring(capture.reasonCode or "")]
      or helpText.VAULT_REASON_CLAIM_SIGNAL_UNAVAILABLE
    if reason then gui.AddLabel(shell, parent, reason, true) end
  else
    gui.AddLabel(shell, parent, helpText.PLAYER_VAULT_CAPTURE_ACTIVE
      or "Automatic Great Vault capture is active.", true)
    local count = math.max(0, math.floor(tonumber(capture.choiceCount) or 0))
    gui.AddLabel(shell, parent, string.format(helpText.PLAYER_VAULT_CAPTURE_CHOICES
      or "Readable equipment choices in the currently opened Vault: %d.", count), true)
  end
  if type(capture) == "table" and capture.lastReasonCode then
    local reason = helpText["VAULT_REASON_" .. tostring(capture.lastReasonCode)]
      or helpText.PLAYER_VAULT_CAPTURE_LAST_UNKNOWN
      or "The last capture attempt could not be confirmed; use manual recording if needed."
    gui.AddLabel(shell, parent, string.format(helpText.PLAYER_VAULT_CAPTURE_LAST
      or "Last capture: %s", reason), true)
  end
  gui.AddLabel(shell, parent, helpText.PLAYER_VAULT_CAPTURE_HELP
    or "Only the selected reward actually received is recorded. Opening the Vault or viewing its choices does not add an acquisition.", true)
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
  renderVaultCaptureStatus(shell, page.header)
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
  -- Keep reminder scans on the lifecycle timer; page redraws should not walk
  -- the full request order just to update delivery state.
  local disputes = Dibs.Disputes

  Dibs.AceGUI.AddHeader(shell, parent, strings.PLAYER_REPORT_TITLE or "Report a problem",
    strings.PLAYER_REPORT_HELP or "Report a wrong Dib debit, a Dib recorded on the wrong item or player, or another Dibs problem. An Officer reviews it; submitting does not change your balance.")
  local transactionDataStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local categories = sortedLabels(disputes and disputes.GetCategories and disputes.GetCategories() or { other = "Other" })
  local transactionQuery = string.lower(trimText(frame.reportTransactionQuery))
  local transactions, transactionCount
  local ledger = Dibs.Ledger
  if transactionQuery == "" and ledger and type(ledger.GetRecentHistoryChoices) == "function" then
    local historyChoicesStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
    transactions, transactionCount = ledger.GetRecentHistoryChoices(summary.player, summary.season and summary.season.id,
      summary.ledgerId, 50)
    if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
      Dibs.UIRenderStats.Record("Player data", "report-history-choices", historyChoicesStartedAt)
    end
  elseif transactionQuery == "" and ledger and type(ledger.GetHistoryPage) == "function"
    and type(ledger.GetPlayerHistorySummary) == "function" then
    local historySummaryStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
    local historySummary = ledger.GetPlayerHistorySummary(summary.player, summary.season and summary.season.id)
    if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
      Dibs.UIRenderStats.Record("Player data", "report-history-summary", historySummaryStartedAt)
    end
    transactionCount = tonumber(historySummary.count) or 0
    local pageSize = 50
    local page = math.max(1, math.ceil(transactionCount / pageSize))
    local historyPageStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
    transactions = ledger.GetHistoryPage(summary.player, summary.season and summary.season.id,
      nil, page, pageSize)
    if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
      Dibs.UIRenderStats.Record("Player data", "report-history-page", historyPageStartedAt)
    end
  else
    transactions = getPlayerTransactions(summary.player, summary.season and summary.season.id, options.historyMode)
  end
  local transactionChoices = { [""] = strings.PLAYER_REPORT_GENERAL or "General request (no ledger entry)" }
  local transactionLabelsStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local matchingTransactions, visibleTransactions = 0, 0
  for _, tx in ipairs(transactions) do
    local id = tostring(tx.transactionId or "")
    local label = id ~= "" and reportTransactionLabel(tx) or ""
    if id ~= "" and (transactionQuery == "" or string.find(string.lower(label), transactionQuery, 1, true)) then
      matchingTransactions = matchingTransactions + 1
      if visibleTransactions < 50 then
        transactionChoices[id] = label
        visibleTransactions = visibleTransactions + 1
      end
    end
  end
  if transactionCount ~= nil then matchingTransactions = transactionCount end
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Player data", "report-transaction-labels", transactionLabelsStartedAt)
  end
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Player data", "report-transactions", transactionDataStartedAt)
  end
  local reportFormStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local transactionSearch = Dibs.AceGUI.AddEditBox(shell, parent,
    strings.PLAYER_REPORT_TRANSACTION_SEARCH or "Search ledger entries", function(value)
      frame.reportTransactionQuery = value or ""
      frame.disputeTransactionId = ""
      frame:Refresh()
    end, fieldWidth)
  setControlText(transactionSearch, frame.reportTransactionQuery or "")
  if matchingTransactions > visibleTransactions then
    local explanation = transactionQuery == "" and "Showing the most recent %d of %d entries. Search to find older entries."
      or "Showing %d of %d matching entries. Refine the search to find older entries."
    Dibs.AceGUI.AddLabel(shell, parent, string.format(explanation,
      visibleTransactions, matchingTransactions), true)
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
      if Dibs.RequestDelivery and Dibs.RequestDelivery.Pump then Dibs.RequestDelivery.Pump(true) end
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
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Player UI", "report-form-build", reportFormStartedAt)
  end

  Dibs.AceGUI.AddHeader(shell, parent, strings.PLAYER_REVIEW_REQUESTS or "My review requests",
    strings.PLAYER_REVIEW_REQUESTS_HELP or "Follow delivery, Officer replies and the decision for each report.")
  local requestDataStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local requests, requestReason = {}, nil
  local requestFetchStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  if disputes and disputes.ListForPlayer then
    requests, requestReason = disputes.ListForPlayer(summary.player)
  end
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Player data", "request-list-fetch", requestFetchStartedAt)
  end
  local requestProjectionStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  local requestProjection = requestReason
    and Dibs.PlayerUI.BuildRequestView({ unavailable = requestReason })
    or Dibs.PlayerUI.BuildRequestView({ limit = 50, requests = requests })
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Player data", "request-list-projection", requestProjectionStartedAt)
  end
  local requestRowsStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
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
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Player data", "request-list-rows", requestRowsStartedAt)
    Dibs.UIRenderStats.Record("Player data", "request-list", requestDataStartedAt)
  end
  local requestTableOptions = {}
  for key, value in pairs(tableOptions) do requestTableOptions[key] = value end
  requestTableOptions.emptyText = strings.PLAYER_REVIEW_REQUESTS_EMPTY or "No review requests yet."
  local visibleRequestRows, requestPage, requestPages = playerPageSlice(frame, "requestsPage", requestRows, 15)
  local requestTableStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
  Dibs.AceGUI.AddTable(shell, parent, {
    { title = "Date", width = 120, minWidth = 90, weight = 1, tooltip = helpText.UI_HELP_DATE },
    { title = strings.PLAYER_REPORT_TYPE or "Problem type", width = 170, minWidth = 110, weight = 2 },
    { title = "Status", width = 120, minWidth = 88, weight = 1, tooltip = helpText.UI_HELP_REQUEST_STATUS },
    { title = "Next step", width = 170, minWidth = 110, weight = 2, tooltip = helpText.UI_HELP_NEXT_STEP },
    { title = "Action", width = 80, minWidth = 70, action = true, tooltip = helpText.UI_HELP_ACTION },
  }, visibleRequestRows, playerListHeight(#visibleRequestRows, 230), function(row)
    if not row.request then return nil end
    return {
      text = strings.PLAYER_REPORT_VIEW or "View",
      callback = function()
        frame.selectedDisputeRequestId = row.request.requestId
        frame:Refresh()
      end,
    }
  end, requestTableOptions)
  addPlayerPager(shell, parent, frame, "requestsPage", requestPage, requestPages, "Requests %d / %d")
  if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Player UI", "request-list-table", requestTableStartedAt)
  end

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
      if result and Dibs.RequestDelivery and Dibs.RequestDelivery.Pump then Dibs.RequestDelivery.Pump(true) end
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
    if not frame._dibsInitialTreeSelection then frame:Refresh() end
  end, 170)
  frame.aceTabs = tabs
  local contentHost = tabs and Dibs.AceGUI.Create(shell, "SimpleGroup", tabs) or nil
  if contentHost then
    if contentHost.SetFullWidth then contentHost:SetFullWidth(true) end
    if contentHost.SetFullHeight then contentHost:SetFullHeight(true) end
    if contentHost.SetLayout then contentHost:SetLayout("List") end
  end
  frame.contentHost = contentHost
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
    local ledgersStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
    local ledgers = Dibs.MultiLedger.GetLedgers({ includeTransactionCount = false })
    if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
      Dibs.UIRenderStats.Record("Player UI", "ledger-toolbar-ledgers", ledgersStartedAt)
    end
    local activeLedgerStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
    local activeLedgerId = Dibs.MultiLedger.GetActiveLedgerId()
    if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
      Dibs.UIRenderStats.Record("Player UI", "ledger-toolbar-active-id", activeLedgerStartedAt)
    end
    local viewLedgerId = Dibs.MultiLedger.GetViewLedgerId and Dibs.MultiLedger.GetViewLedgerId() or activeLedgerId
    local dropdownValuesStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
    local ledgerValues = Dibs.AceGUI.GetLedgerDropdownValues(ledgers, activeLedgerId, viewLedgerId)
    if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
      Dibs.UIRenderStats.Record("Player UI", "ledger-toolbar-dropdown-values", dropdownValuesStartedAt)
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
    return toolbar, activeLedgerId
  end

  frame.Refresh = function(self)
    if not contentHost then return end
    shell._dibsPerfRoute = "Player/" .. tostring(self.playerTab or "unknown")
    local renderStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
    if Dibs.Midnight and Dibs.Midnight.ApplyToFrame and shell.frame then
      Dibs.Midnight.ApplyToFrame(shell.frame, Dibs.AceGUI.GetPresentationTokens())
    end
    local clearStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
    Dibs.AceGUI.Clear(contentHost)
    if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
      Dibs.UIRenderStats.Record("Player UI", "clear", clearStartedAt)
    end
    -- Views that create and size their own table-page root should be mounted
    -- directly in the host so an extra full-height group cannot distort their
    -- custom viewport anchors.
    local ownsTablePage = self.playerTab == "vault" or self.playerTab == "preferences"
      or self.playerTab == "diagnostics"
    local pageRoot = contentHost
    if not ownsTablePage then
      pageRoot = Dibs.AceGUI.Create(shell, "SimpleGroup", contentHost) or contentHost
    end
    if pageRoot ~= contentHost then
      if pageRoot.SetFullWidth then pageRoot:SetFullWidth(true) end
      if pageRoot.SetFullHeight then pageRoot:SetFullHeight(true) end
      if pageRoot.SetLayout then pageRoot:SetLayout("List") end
    end
    self.playerPageHost = pageRoot
    local tabs = pageRoot
    local layoutBatch = Dibs.AceGUI.BeginLayoutBatch and Dibs.AceGUI.BeginLayoutBatch(pageRoot) or nil
    local function finishLayoutBatch()
      if layoutBatch and Dibs.AceGUI.EndLayoutBatch then
        local layoutStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
        Dibs.AceGUI.EndLayoutBatch(layoutBatch)
        layoutBatch = nil
        if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
          Dibs.UIRenderStats.Record("Player UI", "layout-flush", layoutStartedAt)
        end
      end
    end
    local ok, refreshError = pcall(function()
    if Dibs.AceGUI.SetShellStatus then Dibs.AceGUI.SetShellStatus(shell) end
    if self.playerTab ~= "diagnostics" then stopAutoPing() end
    if self.playerTab == "vault" then
      renderVaultHistory(shell, tabs, self, playerContentWidthHint())
      finishLayoutBatch()
      return
    end
    if self.playerTab == "seasonal-roster" then
      self.seasonalRosterSaveButton, self.seasonalRosterWithdrawButton = nil, nil
      local labels = Dibs.L or {}
      local page = Dibs.AceGUI.AddScrollableList(shell, tabs, 600) or tabs
      Dibs.AceGUI.AddHeading(shell, page, labels.SEASONAL_ROSTER_TITLE or "Seasonal Raid Roster",
        labels.SEASONAL_ROSTER_PLAYER_HELP or "Enroll your character for an open raid season.")
      local status = Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetModuleStatus
        and Dibs.OperationalPolicy.GetModuleStatus("seasonalRoster") or { enabled = false }
      if status.enabled ~= true then
        Dibs.AceGUI.AddLabel(shell, page, labels.SEASONAL_ROSTER_DISABLED or "This feature is disabled by the guild.", true)
        finishLayoutBatch()
        return
      end
      local seasons, seasonReason
      if Dibs.SeasonalRoster and Dibs.SeasonalRoster.ListSeasons then
        seasons, seasonReason = Dibs.SeasonalRoster.ListSeasons()
      end
      if not seasons then
        Dibs.AceGUI.AddLabel(shell, page, labels.SEASONAL_ROSTER_UNAVAILABLE or
          ("Seasonal roster unavailable: " .. tostring(seasonReason)), true)
        finishLayoutBatch()
        return
      end
      local seasonValues, selectedSeason = {}, nil
      for _, season in ipairs(seasons) do
        local registrationStatus = season.lifecycle and season.lifecycle.registrationStatus or season.registrationState
        seasonValues[season.seasonId] = tostring(season.name) .. " (" .. Dibs.OfficerUI.SeasonalText(registrationStatus) .. ")"
        if registrationStatus == "OPEN" and not selectedSeason then selectedSeason = season end
      end
      if self.seasonalRosterSeasonId and seasonValues[self.seasonalRosterSeasonId] then
        for _, season in ipairs(seasons) do
          if season.seasonId == self.seasonalRosterSeasonId then selectedSeason = season; break end
        end
      end
      if not selectedSeason then selectedSeason = seasons[1] end
      if not selectedSeason then
        Dibs.AceGUI.AddLabel(shell, page, labels.SEASONAL_ROSTER_NO_SEASONS or "No raid seasons have been configured yet.", true)
        finishLayoutBatch()
        return
      end
      self.seasonalRosterSeasonId = selectedSeason.seasonId
      local seasonDropdown = Dibs.AceGUI.AddDropdown(shell, page, labels.SEASONAL_ROSTER_SEASON or "Season",
        seasonValues, function(value)
          self.seasonalRosterSeasonId = value
          self.seasonalRosterEnrollmentId, self.seasonalRosterFormLoaded = nil, nil
          self.seasonalRosterNewCharacter, self.seasonalRosterCharacter = nil, nil
          self.seasonalRosterPrimarySpec, self.seasonalRosterSecondarySpec = nil, nil
          self.seasonalRosterRequestedPath, self.seasonalRosterCategory = nil, nil
          self.seasonalRosterRoles, self.seasonalRosterMessage = {}, nil
          self.seasonalRosterPublicPage = 1
          self:Refresh()
        end, 280)
      Dibs.AceGUI.SetValue(seasonDropdown, selectedSeason.seasonId)
      local lifecycle = selectedSeason.lifecycle or { registrationStatus = selectedSeason.registrationState }
      local registrationMessage
      if lifecycle.seasonStatus == "ARCHIVED" then
        registrationMessage = labels.SEASONAL_ROSTER_SEASON_ARCHIVED or "This season is archived and read-only."
      elseif lifecycle.seasonStatus == "COMPLETED" then
        registrationMessage = labels.SEASONAL_ROSTER_SEASON_COMPLETED
          or "Season ended. The roster is read-only until it is archived."
      elseif lifecycle.seasonStatus == "UPCOMING" then
        registrationMessage = (labels.SEASONAL_ROSTER_SEASON_UPCOMING or "Season starts on %s.")
          :format(formatDate(selectedSeason.startAt, "%Y-%m-%d"))
      elseif lifecycle.registrationStatus == "OPEN" then
        registrationMessage = labels.SEASONAL_ROSTER_REGISTRATION_OPEN or "Registration is open."
      elseif lifecycle.registrationStatus == "SCHEDULED" then
        registrationMessage = (labels.SEASONAL_ROSTER_REGISTRATION_SCHEDULED or "Registration opens on %s.")
          :format(formatDate(selectedSeason.registrationStartAt, "%Y-%m-%d"))
      elseif lifecycle.seasonStatus == "ACTIVE" then
        registrationMessage = (labels.SEASONAL_ROSTER_SEASON_ACTIVE or "Season is active.") .. " "
          .. (labels.SEASONAL_ROSTER_REGISTRATION_CLOSED or "Registration is closed.")
      else
        registrationMessage = Dibs.OfficerUI.SeasonalText(lifecycle.seasonStatus)
          .. " — " .. Dibs.OfficerUI.SeasonalText(lifecycle.registrationStatus)
      end
      Dibs.AceGUI.AddLabel(shell, page, registrationMessage, true)
      if selectedSeason.raidRules and selectedSeason.raidRules ~= "" then
        Dibs.AceGUI.AddHeader(shell, page, (labels.SEASONAL_ROSTER_RULES or "Season raid rules")
          .. " (v" .. tostring(selectedSeason.rulesRevision or selectedSeason.revision or 1) .. ")")
        Dibs.AceGUI.AddLabel(shell, page, selectedSeason.raidRules, true)
      end
      if selectedSeason.promotionPolicy and selectedSeason.promotionPolicy ~= "" then
        Dibs.AceGUI.AddHeader(shell, page, labels.SEASONAL_ROSTER_CORE_POLICY or "Core Raider promotion criteria")
        Dibs.AceGUI.AddLabel(shell, page, selectedSeason.promotionPolicy, true)
      end
      Dibs.PlayerUI.RenderSeasonIdentity(shell, page, self, selectedSeason)
      local ownEnrollments = Dibs.SeasonalRoster.GetOwnEnrollments(selectedSeason.seasonId) or {}
      local enrollmentValues = { __NEW__ = labels.SEASONAL_ROSTER_NEW_CHARACTER or "Add another character" }
      for _, ownEnrollment in ipairs(ownEnrollments) do
        enrollmentValues[ownEnrollment.enrollmentId] = ownEnrollment.character
      end
      if self.seasonalRosterEnrollmentId then
        local stillExists = false
        for _, ownEnrollment in ipairs(ownEnrollments) do
          if ownEnrollment.enrollmentId == self.seasonalRosterEnrollmentId then stillExists = true; break end
        end
        if not stillExists then self.seasonalRosterEnrollmentId = nil end
      end
      local enrollment
      for _, ownEnrollment in ipairs(ownEnrollments) do
        if ownEnrollment.enrollmentId == self.seasonalRosterEnrollmentId then enrollment = ownEnrollment; break end
      end
      if not self.seasonalRosterEnrollmentId and ownEnrollments[1] and not self.seasonalRosterNewCharacter then
        enrollment = ownEnrollments[1]
        self.seasonalRosterEnrollmentId = enrollment.enrollmentId
      end
      local enrollmentSelector = Dibs.AceGUI.AddDropdown(shell, page,
        labels.SEASONAL_ROSTER_MY_CHARACTERS or "Your characters", enrollmentValues, function(value)
          self.seasonalRosterEnrollmentId = value ~= "__NEW__" and value or nil
          self.seasonalRosterNewCharacter = value == "__NEW__"
          self.seasonalRosterFormLoaded = nil
          self.seasonalRosterCharacter = nil
          self.seasonalRosterPrimarySpec = nil
          self.seasonalRosterSecondarySpec = nil
          self.seasonalRosterCategory = nil
          self.seasonalRosterRequestedPath = nil
          self.seasonalRosterRoles = nil
          self:Refresh()
        end, 280)
      Dibs.AceGUI.SetValue(enrollmentSelector, enrollment and enrollment.enrollmentId or "__NEW__")
      local categories = {}
      for _, category in ipairs(selectedSeason.categories or {}) do categories[category] = category end
      local canEdit = lifecycle.registrationStatus == "OPEN" and lifecycle.readOnly ~= true
      self.seasonalRosterCharacter = self.seasonalRosterCharacter or (enrollment and enrollment.character)
        or (Dibs.GetPlayerName and Dibs.GetPlayerName() or "")
      self.seasonalRosterPrimarySpec = self.seasonalRosterPrimarySpec or (enrollment and enrollment.primarySpec) or ""
      self.seasonalRosterSecondarySpec = self.seasonalRosterSecondarySpec or (enrollment and enrollment.secondarySpec) or ""
      self.seasonalRosterCategory = self.seasonalRosterCategory or (enrollment and enrollment.categoryId)
        or (categories.RAIDER and "RAIDER") or (selectedSeason.categories or {})[1]
      self.seasonalRosterRequestedPath = self.seasonalRosterRequestedPath
        or (enrollment and enrollment.requestedPath) or "STANDARD"
      local selectedCategory
      for _, category in ipairs(selectedSeason.categoryCatalog or {}) do
        if category.id == self.seasonalRosterCategory and category.active ~= false then
          selectedCategory = category
          break
        end
      end
      self.seasonalRosterRoles = self.seasonalRosterRoles or {}
      if enrollment and not self.seasonalRosterFormLoaded then
        self.seasonalRosterRoles = {}
        for _, role in ipairs(enrollment.roles or {}) do self.seasonalRosterRoles[role] = true end
      end
      self.seasonalRosterFormLoaded = true
      local roleControls = {}
      self.seasonalRosterCharacterInput = Dibs.AceGUI.AddEditBox(shell, page,
        labels.SEASONAL_ROSTER_CHARACTER or "Character (Name-Realm)", function(value) self.seasonalRosterCharacter = value or "" end, 280)
      setControlText(self.seasonalRosterCharacterInput, self.seasonalRosterCharacter)
      Dibs.AceGUI.AddLabel(shell, page, (labels.SEASONAL_ROSTER_AWARDED_STATUS or "Starting seasonal status")
        .. ": " .. tostring(selectedCategory and selectedCategory.name or self.seasonalRosterCategory or "RAIDER")
        .. " (" .. (labels.SEASONAL_ROSTER_PENDING_REVIEW or "pending Officer review") .. ")", true)
      if selectedCategory and selectedCategory.description and selectedCategory.description ~= "" then
        Dibs.AceGUI.AddLabel(shell, page,
          (labels.SEASONAL_ROSTER_CATEGORY_EXPLANATION or "Status explanation") .. ": "
            .. selectedCategory.description, true)
      end
      if labels.SEASONAL_ROSTER_OFFICER_NOT_CORE then
        Dibs.AceGUI.AddLabel(shell, page, labels.SEASONAL_ROSTER_OFFICER_NOT_CORE, true)
      end
      local requestedPaths = {
        STANDARD = labels.SEASONAL_ROSTER_PATH_STANDARD or "Raider",
        CORE_PROGRESSION = labels.SEASONAL_ROSTER_PATH_CORE or "Core Raider progression (Thursday)",
        CASUAL = labels.SEASONAL_ROSTER_PATH_CASUAL or "Casual",
      }
      self.seasonalRosterRequestedPathInput = Dibs.AceGUI.AddDropdown(shell, page,
        labels.SEASONAL_ROSTER_REQUESTED_PATH or "Requested raid path", requestedPaths, function(value)
          self.seasonalRosterRequestedPath = value
        end, 320)
      Dibs.AceGUI.SetValue(self.seasonalRosterRequestedPathInput, self.seasonalRosterRequestedPath)
      Dibs.AceGUI.AddLabel(shell, page, labels.SEASONAL_ROSTER_PATH_HELP
        or "This is your request, not an awarded Core Raider status. New registrations await Officer review.", true)
      self.seasonalRosterPrimaryInput = Dibs.AceGUI.AddEditBox(shell, page,
        labels.SEASONAL_ROSTER_PRIMARY_SPEC or "Primary specialization ID", function(value) self.seasonalRosterPrimarySpec = value or "" end, 280)
      setControlText(self.seasonalRosterPrimaryInput, self.seasonalRosterPrimarySpec)
      self.seasonalRosterSecondaryInput = Dibs.AceGUI.AddEditBox(shell, page,
        labels.SEASONAL_ROSTER_SECONDARY_SPEC or "Secondary specialization ID (optional)", function(value) self.seasonalRosterSecondarySpec = value or "" end, 280)
      setControlText(self.seasonalRosterSecondaryInput, self.seasonalRosterSecondarySpec)
      Dibs.AceGUI.AddLabel(shell, page, labels.SEASONAL_ROSTER_ROLES or "Available raid roles", true)
      for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
        roleControls[#roleControls + 1] = Dibs.AceGUI.AddCheckBox(shell, page, labels["SEASONAL_ROSTER_ROLE_" .. role] or role,
          self.seasonalRosterRoles[role] == true, function(value)
            self.seasonalRosterRoles[role] = value == true
          end, 180)
      end
      self.seasonalRosterStatus = Dibs.AceGUI.AddLabel(shell, page, self.seasonalRosterMessage or "", true)
      if canEdit then
        Dibs.AceGUI.SetDisabled(self.seasonalRosterCharacterInput, false)
        Dibs.AceGUI.SetDisabled(self.seasonalRosterPrimaryInput, false)
        Dibs.AceGUI.SetDisabled(self.seasonalRosterSecondaryInput, false)
        self.seasonalRosterSaveButton = Dibs.AceGUI.AddButton(shell, page, labels.SEASONAL_ROSTER_SAVE_ENROLLMENT or "Save enrollment", function()
          local roles = {}
          for role, checked in pairs(self.seasonalRosterRoles or {}) do if checked then roles[#roles + 1] = role end end
          table.sort(roles)
          local result = Dibs.SeasonalRoster.UpsertOwnEnrollment(selectedSeason.seasonId, {
            enrollmentId = enrollment and enrollment.enrollmentId or nil,
            character = self.seasonalRosterCharacter, categoryId = self.seasonalRosterCategory,
            requestedPath = self.seasonalRosterRequestedPath,
            primarySpec = self.seasonalRosterPrimarySpec, secondarySpec = self.seasonalRosterSecondarySpec ~= ""
              and self.seasonalRosterSecondarySpec or nil, roles = roles,
          }, enrollment and enrollment.revision or 0, Dibs.NewId("seasonal-enrollment"))
          self.seasonalRosterMessage = result.ok and (labels.SEASONAL_ROSTER_SAVED or "Enrollment saved. Guild sync may take time.")
            or (labels.SEASONAL_ROSTER_SAVE_FAILED or "Enrollment was not saved: ") .. Dibs.OfficerUI.SeasonalText(result.code)
          if result.ok then
            self.seasonalRosterEnrollmentId = result.value
            self.seasonalRosterNewCharacter = nil
          end
          self.seasonalRosterFormLoaded = nil
          self:Refresh()
        end, 190)
        if enrollment and (enrollment.status == "ACTIVE" or enrollment.status == "PENDING_REVIEW") then
          self.seasonalRosterWithdrawButton = Dibs.AceGUI.AddButton(shell, page, labels.SEASONAL_ROSTER_WITHDRAW or "Withdraw enrollment", function()
            local result = Dibs.SeasonalRoster.WithdrawOwnEnrollment(selectedSeason.seasonId,
              enrollment.enrollmentId, enrollment.revision, Dibs.NewId("seasonal-withdraw"))
            self.seasonalRosterMessage = result.ok and (labels.SEASONAL_ROSTER_WITHDRAWN_NOTICE or "Enrollment withdrawn.")
              or (labels.SEASONAL_ROSTER_SAVE_FAILED or "Enrollment was not changed: ") .. Dibs.OfficerUI.SeasonalText(result.code)
            self.seasonalRosterFormLoaded = nil
            self:Refresh()
          end, 190)
        end
      else
        Dibs.AceGUI.SetDisabled(self.seasonalRosterCharacterInput, true)
        Dibs.AceGUI.SetDisabled(self.seasonalRosterPrimaryInput, true)
        Dibs.AceGUI.SetDisabled(self.seasonalRosterSecondaryInput, true)
        for _, control in ipairs(roleControls) do Dibs.AceGUI.SetDisabled(control, true) end
      end
      Dibs.AceGUI.AddHeader(shell, page, labels.SEASONAL_ROSTER_PUBLIC_TITLE or "Registered raid roster",
        labels.SEASONAL_ROSTER_PUBLIC_HELP or "This list shows active public enrollment choices only.")
      local searchInput = Dibs.AceGUI.AddEditBox(shell, page, labels.SEASONAL_ROSTER_SEARCH or "Search character",
        function(value) self.seasonalRosterSearchDraft = value or "" end, 260)
      setControlText(searchInput, self.seasonalRosterSearchDraft or self.seasonalRosterSearch or "")
      local categoryFilters = { ALL = labels.SEASONAL_ROSTER_ALL_CATEGORIES or "All categories" }
      for _, category in ipairs(selectedSeason.categories or {}) do categoryFilters[category] = category end
      local categoryFilter = Dibs.AceGUI.AddDropdown(shell, page,
        labels.SEASONAL_ROSTER_CATEGORY_FILTER or "Category filter", categoryFilters, function(value)
          self.seasonalRosterCategoryFilterDraft = value
        end, 250)
      Dibs.AceGUI.SetValue(categoryFilter, self.seasonalRosterCategoryFilter or "ALL")
      local sortOptions = {
        character = labels.SEASONAL_ROSTER_SORT_CHARACTER or "Character",
        category = labels.SEASONAL_ROSTER_SORT_CATEGORY or "Category",
        class = labels.SEASONAL_ROSTER_SORT_CLASS or "Class",
      }
      local sortBy = self.seasonalRosterSortBy or "character"
      local sortControl = Dibs.AceGUI.AddDropdown(shell, page,
        labels.SEASONAL_ROSTER_SORT or "Sort by", sortOptions, function(value)
          self.seasonalRosterSortDraft = value
        end, 180)
      Dibs.AceGUI.SetValue(sortControl, sortBy)
      Dibs.AceGUI.AddButton(shell, page, labels.SEASONAL_ROSTER_APPLY_FILTERS or "Apply filters", function()
        self.seasonalRosterSearch = self.seasonalRosterSearchDraft or ""
        self.seasonalRosterCategoryFilter = self.seasonalRosterCategoryFilterDraft or self.seasonalRosterCategoryFilter or "ALL"
        self.seasonalRosterSortBy = self.seasonalRosterSortDraft or self.seasonalRosterSortBy or "character"
        self.seasonalRosterPublicPage = 1
        self:Refresh()
      end, 130)
      local projection, projectionReason = Dibs.SeasonalRoster.GetPublicRosterPage(selectedSeason.seasonId, {
        page = self.seasonalRosterPublicPage or 1, pageSize = 20,
        search = self.seasonalRosterSearch or "",
        categoryId = self.seasonalRosterCategoryFilter ~= "ALL" and self.seasonalRosterCategoryFilter or nil,
        sortBy = sortBy,
      })
      if not projection then
        Dibs.AceGUI.AddLabel(shell, page, (labels.SEASONAL_ROSTER_ERROR or "Unable to load roster: %s")
          :format(tostring(projectionReason)), true)
      else
        if projection.status == "CATCHING_UP" then
          Dibs.AceGUI.AddLabel(shell, page, labels.SEASONAL_ROSTER_CATCHING_UP
            or "Guild sync is behind; recent roster changes may not be available yet.", true)
        else
          Dibs.AceGUI.AddLabel(shell, page, labels.SEASONAL_ROSTER_SYNC_CURRENT
            or "Guild sync is current.", true)
        end
        local rows = {}
        for _, entry in ipairs(projection.rows) do
          rows[#rows + 1] = { entry.character, entry.requestedPath, entry.categoryId, entry.primarySpec,
            entry.secondarySpec or "—", table.concat(entry.roles or {}, ", "),
            entry.className or (labels.SEASONAL_ROSTER_UNKNOWN or "Unknown"),
            entry.armorType or (labels.SEASONAL_ROSTER_UNKNOWN or "Unknown") }
        end
        Dibs.AceGUI.AddLabel(shell, page, string.format(labels.SEASONAL_ROSTER_RESULT_COUNT or "%d registered character(s)", projection.total), true)
        local function countSummary(counts)
          local keys = {}
          for key in pairs(counts or {}) do keys[#keys + 1] = key end
          table.sort(keys)
          local values = {}
          for _, key in ipairs(keys) do values[#values + 1] = key .. ": " .. tostring(counts[key]) end
          return #values > 0 and table.concat(values, ", ") or "—"
        end
        Dibs.AceGUI.AddLabel(shell, page, (labels.SEASONAL_ROSTER_COMPOSITION or "Composition") .. ": "
          .. tostring(projection.uniquePlayers or 0) .. " | "
          .. (labels.SEASONAL_ROSTER_ROLES or "Roles") .. ": " .. countSummary(projection.roles) .. " | "
          .. (labels.SEASONAL_ROSTER_CLASS or "Class") .. ": " .. countSummary(projection.classes) .. " | "
          .. (labels.SEASONAL_ROSTER_ARMOR or "Armor") .. ": " .. countSummary(projection.armor) .. " | "
          .. (labels.SEASONAL_ROSTER_CATEGORY or "Category") .. ": " .. countSummary(projection.categories), true)
        Dibs.AceGUI.AddLabel(shell, page, labels.SEASONAL_ROSTER_COMPOSITION_HELP or
          "Counts use active filters and one approved Main per linked player.", true)
        Dibs.AceGUI.AddTable(shell, page, {
          { title = labels.SEASONAL_ROSTER_CHARACTER or "Character", width = 190, minWidth = 100, weight = 3 },
          { title = labels.SEASONAL_ROSTER_REQUESTED_PATH or "Requested path", width = 150, minWidth = 80, weight = 2 },
          { title = labels.SEASONAL_ROSTER_CATEGORY or "Category", width = 110, minWidth = 65, weight = 1 },
          { title = labels.SEASONAL_ROSTER_PRIMARY_SPEC or "Primary spec", width = 130, minWidth = 70, weight = 1 },
          { title = labels.SEASONAL_ROSTER_SECONDARY_SPEC or "Second spec", width = 130, minWidth = 70, weight = 1 },
          { title = labels.SEASONAL_ROSTER_ROLES or "Roles", width = 120, minWidth = 60, weight = 1 },
          { title = labels.SEASONAL_ROSTER_CLASS or "Class", width = 100, minWidth = 55, weight = 1 },
          { title = labels.SEASONAL_ROSTER_ARMOR or "Armor", width = 80, minWidth = 50, weight = 1 },
        }, rows, math.min(420, math.max(100, #rows * 24)), nil, {
          fluidColumns = true, widthHint = playerContentWidthHint(), shrinkToFit = true,
          emptyText = projection.total == 0 and ((self.seasonalRosterSearch or "") ~= ""
            or self.seasonalRosterCategoryFilter and self.seasonalRosterCategoryFilter ~= "ALL")
            and (labels.SEASONAL_ROSTER_NO_MATCHES or "No players match these filters.")
            or (labels.SEASONAL_ROSTER_EMPTY or "No players are enrolled for this season yet."),
        })
        local navigation = Dibs.AceGUI.AddInlineGroup(shell, page)
        self.seasonalRosterPrevious = Dibs.AceGUI.AddButton(shell, navigation,
          labels.HISTORY_PREVIOUS or "Previous", function()
            self.seasonalRosterPublicPage = math.max(1, projection.page - 1)
            self:Refresh()
          end, 90)
        Dibs.AceGUI.AddLabel(shell, navigation, string.format("%d / %d", projection.page, projection.pages))
        self.seasonalRosterNext = Dibs.AceGUI.AddButton(shell, navigation,
          labels.HISTORY_NEXT or "Next", function()
            self.seasonalRosterPublicPage = math.min(projection.pages, projection.page + 1)
            self:Refresh()
          end, 90)
        Dibs.AceGUI.SetDisabled(self.seasonalRosterPrevious, projection.page <= 1)
        Dibs.AceGUI.SetDisabled(self.seasonalRosterNext, projection.page >= projection.pages)
      end
      finishLayoutBatch()
      return
    end
    if self.playerTab == "preferences" then
      local page = Dibs.AceGUI.AddTablePage(shell, tabs, {
        footer = true, boundsFrame = tabs.content or tabs.frame,
      })
      if not page then finishLayoutBatch(); return end
      Dibs.AceGUI.AddHeading(shell, page.header,
        helpText.MINIMAP_SETTINGS_TITLE or "Player preferences",
        helpText.MINIMAP_SETTINGS_DESCRIPTION or "Personal display preferences for this character.")
      local appearanceSection = Dibs.AceGUI.AddSection(shell, page.header,
        helpText.PLAYER_APPEARANCE_SECTION or "Appearance",
        helpText.PLAYER_APPEARANCE_HELP or "Choose a local Dibs color palette. This only changes how the addon is displayed for this character.")
      local themeCatalog = Dibs.Midnight and Dibs.Midnight.GetThemeCatalog and Dibs.Midnight.GetThemeCatalog() or {}
      local themeValues = {}
      for _, theme in ipairs(themeCatalog) do
        if type(theme) == "table" and type(theme.id) == "string" and type(theme.name) == "string" then
          themeValues[theme.id] = theme.name
        end
      end
      local profile = Dibs.Midnight and Dibs.Midnight.GetProfile and Dibs.Midnight.GetProfile() or {}
      local selectedTheme = profile.theme or "MIDNIGHT"
      self.themeSelector = Dibs.AceGUI.AddDropdown(shell, appearanceSection,
        helpText.PLAYER_APPEARANCE_THEME or "Color theme", themeValues, function(themeID)
          if Dibs.Midnight and Dibs.Midnight.SetProfile and Dibs.Midnight.SetProfile({ theme = themeID }) then
            self:Refresh()
            local officerFrame = _G.DibsOfficerFrame
            local officerShell = officerFrame and officerFrame.dibsAceGUIShell
            if officerShell and officerShell._dibsActive == true and type(officerFrame.Refresh) == "function"
              and (not officerFrame.IsShown or officerFrame:IsShown()) then
              Dibs.Midnight.ApplyToFrame(officerShell.frame, Dibs.AceGUI.GetPresentationTokens())
              officerFrame:Refresh()
            end
          end
        end, 360)
      if self.themeSelector then Dibs.AceGUI.SetValue(self.themeSelector, selectedTheme) end
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
      finishLayoutBatch()
      return
    end
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
        finishLayoutBatch()
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
      finishLayoutBatch()
      return
    end
    if self.playerTab == "requests" then
      -- This page belongs to the review-request module; Pre-Dib reservations
      -- live on My Dibs so disabling reports never hides them.
      local requestsShellStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
      local pageStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
      local page = Dibs.AceGUI.AddScrollableList(shell, tabs, 535) or tabs
      if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
        Dibs.UIRenderStats.Record("Player UI", "requests-page-container", pageStartedAt)
      end
      local pageWidth = math.max(320, playerContentWidthHint() - 26)
      local headingStartedAt = Dibs.UIRenderStats and Dibs.UIRenderStats.Begin and Dibs.UIRenderStats.Begin()
      Dibs.AceGUI.AddHeading(shell, page, helpText.PLAYER_NAV_REPORTS or "Reports",
        helpText.PLAYER_REQUESTS_HELP or "Report a wrong Dib or a Dib removed without loot, then follow the Officer review.")
      if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
        Dibs.UIRenderStats.Record("Player UI", "requests-heading", headingStartedAt)
      end
      local _, activeLedgerId = addActiveLedgerToolbar(page)
      local reportContext = {
        player = Dibs.GetPlayerName and Dibs.GetPlayerName() or nil,
        season = Dibs.Seasons and Dibs.Seasons.GetCurrent and Dibs.Seasons.GetCurrent() or nil,
        ledgerId = activeLedgerId,
      }
      if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
        Dibs.UIRenderStats.Record("Player UI", "requests-shell", requestsShellStartedAt)
      end
      renderReviewRequests(shell, page, self, reportContext, { widthHint = pageWidth })
      finishLayoutBatch()
      return
    end
    local viewLedgerId = Dibs.MultiLedger and Dibs.MultiLedger.GetViewLedgerId and Dibs.MultiLedger.GetViewLedgerId() or nil
    local historyPageSize = 20
    local view = self.playerTab == "history"
      and Dibs.PlayerUI.GetHistoryViewModel(nil, self.historyFilters, viewLedgerId, self.historyPage, historyPageSize)
      or Dibs.PlayerUI.GetViewModel(nil, self.historyFilters, viewLedgerId, {
        includeHistory = false, pagePreDibHistory = self.myDibsPastPage or 1,
        pageActivePreDibs = self.myDibsActivePage or 1,
        pageWonPreDibs = self.myDibsWonPage or 1,
        includeEligibility = self.playerTab == "my-dibs",
      })
    if self.playerTab == "history" then
      Dibs.AceGUI.AddHeading(shell, tabs, "History", "Your Dibs activity for the current season.")
      addActiveLedgerToolbar(tabs)
      addHistoryFilterControls(shell, tabs, self, "historyFilters", "history", playerContentWidthHint())
      if view.historyFilterError then Dibs.AceGUI.AddLabel(shell, tabs, view.historyFilterError, true) end
      local historyRows = {}
      for _, entry in ipairs(view.history or {}) do
        historyRows[#historyRows + 1] = { entry.date, entry.item, entry.action, entry.result, entry.balanceImpact, entry = entry }
      end
      local visibleHistoryRows, historyPage, historyPages
      if view.paged then
        visibleHistoryRows = historyRows
        historyPage = view.page or 1
        historyPages = math.max(1, math.ceil((tonumber(view.total) or 0) / historyPageSize))
        self.historyPage = historyPage
      else
        visibleHistoryRows, historyPage, historyPages = playerPageSlice(self, "historyPage", historyRows, historyPageSize)
      end
      Dibs.AceGUI.AddTable(shell, tabs, {
        { title = "Date", width = 145, minWidth = 100, weight = 1 },
        { title = "Item", width = 220, minWidth = 140, weight = 2 },
        { title = "Action", width = 130, minWidth = 95, weight = 1 },
        { title = "Result", width = 190, minWidth = 120, weight = 2 },
        { title = "Balance", width = 90, minWidth = 70, weight = 1 },
      }, visibleHistoryRows, 300, nil, {
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
      addPlayerPager(shell, tabs, self, "historyPage", historyPage, historyPages, "History %d / %d")
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
      finishLayoutBatch()
      return
    end

    Dibs.AceGUI.AddHeading(shell, tabs, "My Dibs", "Your season allocation, Dibs use, and current balance.")
    Dibs.AceGUI.AddHeader(shell, tabs, view.seasonName, helpText.UI_HELP_SEASON)
    addActiveLedgerToolbar(tabs)
    if self.playerTab == "my-dibs" then
      local integration = Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetLocalStatus
        and Dibs.RCLootCouncil.GetLocalStatus() or nil
      if integration then
        local integrationState = Dibs.PlayerUI.GetIntegrationState(integration)
        local integrationView = Dibs.PlayerUI.GetStatusPresentation(integrationState)
        Dibs.Midnight.AddStatusBadge(shell, tabs, integrationView.tone,
          "RCLootCouncil: " .. integrationView.label)
      end
      local eligibility = view.eligibility
      if eligibility then
        Dibs.AceGUI.AddLabel(shell, tabs, "Protected-loot group: " .. tostring(eligibility.groupId or "Not linked"), true)
        Dibs.AceGUI.AddLabel(shell, tabs, "Main-change probation: " .. tostring(eligibility.probation
          and ("Until " .. tostring(eligibility.probation.probationEndsAt)) or "None"), true)
        local relationshipSection = Dibs.AceGUI.AddSection(shell, tabs, "Main / alt declarations",
          "Declare your characters explicitly. An Officer must approve a link before it affects Dibs.")
         local currentCharacter = Dibs.GetPlayerName and Dibs.GetPlayerName() or ""
         addEligibilityCharacterPicker(shell, relationshipSection, self, currentCharacter, Dibs.L)
        Dibs.AceGUI.AddButton(shell, relationshipSection, "Declare alt", function()
          local alt = self.eligibilityCharacter
          local relationship = alt and Dibs.CharacterEligibility.DeclareRelationship({
            seasonId = view.season and view.season.id, mainCharacter = Dibs.GetPlayerName(), altCharacter = alt,
          }) or nil
          self.eligibilityStatus = relationship and "Declaration submitted for Officer approval."
            or "Choose a guild character before submitting."
          self:Refresh()
        end, 130)
        Dibs.AceGUI.AddButton(shell, relationshipSection, "Request main change", function()
          local newMain = self.eligibilityCharacter
          local request = newMain and Dibs.CharacterEligibility.RequestMainChange({
            seasonId = view.season and view.season.id, oldMainId = Dibs.GetPlayerName(), newMainId = newMain,
          }) or nil
          self.eligibilityStatus = request and "Main change submitted for Officer approval."
            or "Link the new Main to your current character and select it first."
          self:Refresh()
        end, 180)
        if self.eligibilityStatus then Dibs.AceGUI.AddLabel(shell, relationshipSection, self.eligibilityStatus, true) end
      end
    end
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
    local activeRows, activePage, activePages = {}, 1, 1
    if view.activePreDibPage then
      activePage, activePages = view.activePreDibPage.page, view.activePreDibPage.pages
      for _, request in ipairs(view.activePreDibs or {}) do
        activeRows[#activeRows + 1] = {
          request.date, request.item, request.status, request.difficulty or "Any", "Cancel",
          request = request.request,
        }
      end
      self.myDibsActivePage = activePage
    else
      for _, request in ipairs(view.activePreDibs or {}) do
        activeRows[#activeRows + 1] = {
          request.date, request.item, request.status, request.difficulty or "Any", "Cancel",
          request = request,
        }
      end
      activeRows, activePage, activePages = playerPageSlice(self, "myDibsActivePage", activeRows, 10)
    end
    local visibleActiveRows = activeRows
    Dibs.AceGUI.AddHeader(shell, tabs, helpText.PLAYER_ACTIVE_PREDIBS or "Active Pre-Dibs", helpText.UI_HELP_PREDIB)
    Dibs.AceGUI.AddTable(shell, tabs, {
      { title = "Date", width = 145, minWidth = 100, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_DATE },
      { title = "Item", width = 250, minWidth = 140, weight = 3, tooltip = helpText.UI_HELP_ITEM },
      { title = "Status", width = 120, minWidth = 88, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_REQUEST_STATUS },
      { title = "Difficulty", width = 100, minWidth = 75, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_DIFFICULTY },
      { title = "Action", width = 90, minWidth = 80, action = true, tooltip = helpText.UI_HELP_ACTION },
    }, visibleActiveRows, playerListHeight(#visibleActiveRows, 170), function(row)
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
    addPlayerPager(shell, tabs, self, "myDibsActivePage", activePage, activePages, "Active Pre-Dibs %d / %d")
    local wonRows, wonPage, wonPages = {}, 1, 1
    for _, request in ipairs(view.wonPreDibs or {}) do
      wonRows[#wonRows + 1] = {
        request.date, request.item, request.difficulty or "Any", request.status,
      }
    end
    if view.wonPreDibPage then
      wonPage, wonPages = view.wonPreDibPage.page, view.wonPreDibPage.pages
      self.myDibsWonPage = wonPage
    else
      wonRows, wonPage, wonPages = playerPageSlice(self, "myDibsWonPage", wonRows, 10)
    end
    local visibleWonRows = wonRows
    Dibs.AceGUI.AddHeader(shell, tabs, helpText.PLAYER_FULFILLED_PREDIBS or "Won Pre-Dibs",
      "Pre-Dibs fulfilled by a finalized loot award.")
    Dibs.AceGUI.AddTable(shell, tabs, {
      { title = "Date", width = 145, minWidth = 100, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_DATE },
      { title = "Item", width = 300, minWidth = 160, weight = 3, tooltip = helpText.UI_HELP_ITEM },
      { title = "Difficulty", width = 120, minWidth = 80, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_DIFFICULTY },
      { title = "Status", width = 110, minWidth = 80, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_REQUEST_STATUS },
    }, visibleWonRows, playerListHeight(#visibleWonRows, 145), nil, { allowTableSort = false, flatBackground = true, fluidColumns = true,
      widthHint = playerContentWidthHint(), shrinkToFit = true, hideScrollbarWhenFits = true,
      scrollbarReserve = 26, emptyText = view.empty.wonPreDibs })
    addPlayerPager(shell, tabs, self, "myDibsWonPage", wonPage, wonPages, "Won Pre-Dibs %d / %d")
    local visiblePastRows, pastPage, pastPages
    if view.pastPreDibPage then
      visiblePastRows, pastPage, pastPages = {}, view.pastPreDibPage.page, view.pastPreDibPage.pages
      for _, request in ipairs(view.pastPreDibPage.rows) do
        visiblePastRows[#visiblePastRows + 1] = {
          formatDate(request.createdAt), request.item, request.status,
        }
      end
      self.myDibsPastPage = pastPage
    else
      local listedPreDibs = {}
      for _, request in ipairs(view.activePreDibs or {}) do listedPreDibs[request.requestId or false] = true end
      for _, request in ipairs(view.wonPreDibs or {}) do listedPreDibs[request.requestId or false] = true end
      local pastRows = {}
      for _, request in ipairs(view.requests or {}) do
        if not listedPreDibs[request.requestId or false] then
          pastRows[#pastRows + 1] = { formatDate(request.createdAt), request.item, request.status }
        end
      end
      visiblePastRows, pastPage, pastPages = playerPageSlice(self, "myDibsPastPage", pastRows, 10)
    end
    Dibs.AceGUI.AddHeader(shell, tabs, helpText.PLAYER_PREDIB_HISTORY or "Past Pre-Dibs",
      helpText.PLAYER_PREDIB_HISTORY_HELP or "Cancelled, expired or otherwise closed Pre-Dibs.")
    Dibs.AceGUI.AddTable(shell, tabs, {
      { title = "Date", width = 145, minWidth = 100, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_DATE },
      { title = "Item", width = 300, minWidth = 160, weight = 3, tooltip = helpText.UI_HELP_ITEM },
      { title = "Status", width = 120, minWidth = 88, weight = 1, align = "CENTER", tooltip = helpText.UI_HELP_REQUEST_STATUS },
    }, visiblePastRows, playerListHeight(#visiblePastRows, 120), nil, { allowTableSort = false, flatBackground = true, fluidColumns = true,
      widthHint = playerContentWidthHint(), shrinkToFit = true, hideScrollbarWhenFits = true,
      scrollbarReserve = 26, emptyText = helpText.PLAYER_PREDIB_HISTORY_EMPTY or "No past Pre-Dibs." })
    addPlayerPager(shell, tabs, self, "myDibsPastPage", pastPage, pastPages, "Past Pre-Dibs %d / %d")
    addRequestAction(tabs, view)
    finishLayoutBatch()
    end)
    finishLayoutBatch()
    if Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
      Dibs.UIRenderStats.Record("Player", self.playerTab or "unknown", renderStartedAt)
    end
    if not ok then error(refreshError, 0) end
  end

  shell.onRelease = function()
    stopAutoPing()
    for _, key in ipairs({
      "aceTabs", "contentHost", "playerPageHost", "preDibInput", "preDibButton", "preDibStatus", "preDibStatusText", "preDibValue", "devItemText",
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
      if self._dibsOpeningExplicitly then
        self._dibsOpeningExplicitly = nil
      elseif activeShell and activeShell._dibsActive then
        self:Refresh()
      end
    end)
  end
  _G.DibsPlayerFrame = frame
  frame._dibsInitialTreeSelection = true
  Dibs.AceGUI.SelectTree(tabs, frame.playerTab)
  frame._dibsInitialTreeSelection = nil
  frame:Refresh()
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

function Dibs.PlayerUI.RefreshVaultCapture()
  local frame = _G.DibsPlayerFrame
  if not frame or frame.playerTab ~= "vault" or type(frame.Refresh) ~= "function"
    or type(frame.IsShown) ~= "function" or not frame:IsShown() then return false end
  local shell = frame.dibsAceGUIShell
  if shell and shell._dibsActive ~= true then return false end
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
  local createdNow = _G.DibsPlayerFrame == nil
  local frame = Dibs.PlayerUI.CreateWindow()
  local wasShown = frame:IsShown()
  if not wasShown then
    frame._dibsOpeningExplicitly = true
    if not createdNow and frame.Refresh then frame:Refresh() end
  end
  frame:Show()
  frame._dibsOpeningExplicitly = nil
  frame:Raise()
  -- The newly created AceGUI window was rendered while hidden. Suppress the
  -- duplicate OnShow render; later explicit opens refresh through OnShow.
  if wasShown and frame.Refresh then
    frame:Refresh()
  end

  return frame
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
