--[[
Module: Dibs.LogsUI
Layer: UI / read-only audit views
Purpose: Display player, acquisition, and officer history.
Responsibilities: Read-only projection and navigation to relevant detail views.
Non-responsibilities: It does not mutate ledger or RC history.
Dependencies: AceGUI, Ledger, PreDibs, Disputes, Permissions.
Blizzard events: None directly.
Internal events/messages: Widget callbacks only.
SavedVariables: Reads via domain services.
RCLootCouncil: Displays award/evidence references when available.
Combat safety: Read-only windows still follow UI combat restrictions.
Related docs: docs/officer/auditing.md, docs/player/README.md.
]]

local Dibs = _G.Dibs
Dibs.LogsUI = Dibs.LogsUI or {}

local function windowSize(width, height)
  local metrics = Dibs.Midnight and Dibs.Midnight.GetLayoutMetrics and Dibs.Midnight.GetLayoutMetrics() or {}
  return math.max(metrics.minWidth or 520, math.min(metrics.maxWidth or 1400, tonumber(width) or 760)),
    math.max(metrics.minHeight or 360, math.min(metrics.maxHeight or 1100, tonumber(height) or 560))
end

local function canViewOfficerLogs()
  if type(Dibs.Permissions) ~= "table" or type(Dibs.Permissions.GetGuildRole) ~= "function" then
    return false
  end
  local ok, role = pcall(Dibs.Permissions.GetGuildRole, nil)
  return ok and (role == "gm" or role == "officer")
end

local function localActor()
  return Dibs.GetPlayerName and Dibs.GetPlayerName() or nil
end

local function canViewReconciliation()
  return type(Dibs.Permissions) == "table"
    and type(Dibs.Permissions.Can) == "function"
    and Dibs.Permissions.Can("history.confirm", localActor()) == true
end

function Dibs.LogsUI.CanViewReconciliation()
  return canViewReconciliation()
end

local function reconciliationAvailability()
  local status = Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetLocalStatus
    and Dibs.RCLootCouncil.GetLocalStatus() or { availability = "absent" }
  local availability = tostring(status.availability or status.status or "absent")
  local presentations = {
    absent = { label = "Unavailable", explanation = "History reconciliation is unavailable because RCLootCouncil is not currently available.", tone = "warning" },
    disabled = { label = "Unavailable", explanation = "History reconciliation is unavailable because RCLootCouncil is disabled.", tone = "warning" },
    degraded = { label = "Degraded", explanation = "Some award evidence cannot be verified safely. Review remains read-only until evidence is sufficient.", tone = "warning" },
    unsupported = { label = "Unsupported", explanation = "This RCLootCouncil adapter is not supported for safe history reconciliation.", tone = "warning" },
    operational = { label = "Available", explanation = "RCLootCouncil history is available as read-only evidence.", tone = "ready" },
  }
  local result = presentations[availability] or presentations.absent
  return {
    label = result.label, explanation = result.explanation, tone = result.tone,
    availability = availability, reasonCode = status.reasonCode, technical = status,
  }
end

function Dibs.LogsUI.GetReconciliationAvailability()
  return reconciliationAvailability()
end

local function bounded(value, limit)
  local text = tostring(value or "")
  local maximum = tonumber(limit) or 240
  if #text > maximum then return text:sub(1, maximum) end
  return text
end

local function candidateStatus(candidate)
  local classification = tostring(candidate and candidate.classification or "unsupported")
  if classification == "eligible" then
    return { label = "Ready to review", explanation = candidate.finalStatusInferred
      and "Likely eligible Dib award; final status was inferred from history."
      or "Likely eligible Dib award.", tone = "ready" }
  end
  if classification == "already_accounted" then
    return { label = "Already accounted", explanation = "This award is already recorded; no second debit is available.", tone = "normal" }
  end
  if classification == "rejected" then
    return { label = "Ignored", explanation = "This history row does not match a finalized DIB award.", tone = "normal" }
  end
  if classification == "legacy" then
    return { label = "Display only", explanation = "Legacy Dibs markers are evidence hints only and cannot be confirmed.", tone = "warning" }
  end
  return { label = "Needs review", explanation = "The award could not be matched safely.", tone = "warning" }
end

local function candidateProjection(candidate, includeTechnical)
  local status = candidateStatus(candidate)
  local classification = tostring(candidate and candidate.classification or "unsupported")
  local projected = {
    candidateId = candidate and candidate.candidateId,
    item = bounded(candidate and (candidate.itemLink or candidate.itemName or candidate.itemID) or "Unavailable", 180),
    itemID = candidate and candidate.itemID,
    winner = bounded(candidate and (candidate.playerName or candidate.winner) or "Unavailable", 100),
    date = bounded(candidate and (candidate.originalAwardTimeText or candidate.originalAwardTime) or "Unknown date", 80),
    difficulty = bounded(candidate and (candidate.difficultyText or candidate.difficulty) or "Unavailable", 40),
    response = bounded(candidate and (candidate.responseText or candidate.response) or "Unavailable", 60),
    status = status,
    evidenceSummary = status.explanation,
    canConfirm = classification == "eligible",
    canReject = classification ~= "already_accounted" and classification ~= "legacy",
  }
  if includeTechnical then
    local capability = reconciliationAvailability()
    projected.technical = {
      adapter = capability.technical and capability.technical.adapter,
      availability = capability.availability,
      reasonCode = candidate and candidate.reasonCode,
      historyRef = candidate and candidate.historyRef,
      evidenceId = candidate and candidate.evidenceId,
      sourceStatus = candidate and candidate.sourceStatus,
      finalStatusInferred = candidate and candidate.finalStatusInferred == true,
      responseIdentity = candidate and candidate.responseIdentity,
      historySource = candidate and candidate.historySource,
      sourceEvent = candidate and candidate.historyEvent,
    }
  end
  return projected
end

local function findCandidate(session, candidateId)
  for _, candidate in ipairs(session and session.candidates or {}) do
    if tostring(candidate.candidateId) == tostring(candidateId) then return candidate end
  end
  return nil
end

local function reconciliationCounts(session)
  local counts = session and session.counts or {}
  local candidates = session and session.candidates or {}
  local possible = #candidates
  local ignored = (tonumber(counts.hiddenNonDib) or 0)
    + (tonumber(counts.rejected) or 0) + (tonumber(counts.unsupported) or 0)
    + (tonumber(counts.legacy) or 0)
  local ambiguous = tonumber(counts.ambiguous) or 0
  local unresolved = 0
  local confirmed, rejected = 0, 0
  for _, candidate in ipairs(candidates) do
    if candidate.classification == "already_accounted" then confirmed = confirmed + 1
    elseif candidate.classification == "rejected" then rejected = rejected + 1
    elseif candidate.classification == "ambiguous" or candidate.classification == "unsupported" or candidate.classification == "eligible" then unresolved = unresolved + 1 end
  end
  return {
    rowsScanned = tonumber(counts.sourceScanned or counts.scanned) or 0,
    possibleDibs = possible,
    ignored = ignored,
    ambiguous = ambiguous,
    confirmed = confirmed,
    rejected = rejected,
    unresolved = unresolved,
  }
end

---@param sessionId string|nil Reconciliation session identifier.
---@return table view Guided Search/Review/Complete projection.
function Dibs.LogsUI.BuildReconciliationView(sessionId)
  if not canViewReconciliation() then
    return { stage = "search", authorized = false, availability = reconciliationAvailability() }
  end
  if not sessionId or not Dibs.RCLootCouncil or type(Dibs.RCLootCouncil.GetReconciliationSession) ~= "function" then
    return { stage = "search", authorized = true, availability = reconciliationAvailability() }
  end
  local session, reason = Dibs.RCLootCouncil.GetReconciliationSession(sessionId, localActor())
  if not session then
    return { stage = "search", authorized = true, reasonCode = reason, availability = reconciliationAvailability() }
  end
  local summary = reconciliationCounts(session)
  local rows = {}
  for _, candidate in ipairs(session.candidates or {}) do
    rows[#rows + 1] = candidateProjection(candidate, false)
  end
  local stage = summary.unresolved == 0 and #rows > 0 and "complete" or "review"
  return {
    stage = stage, authorized = true, sessionId = session.sessionId, summary = summary,
    candidates = rows, emptyState = #rows == 0 and "No Dibs candidates found" or nil,
    completion = stage == "complete" and {
      label = "Reconciliation complete", confirmed = summary.confirmed,
      rejected = summary.rejected, unresolved = summary.unresolved,
    } or nil,
    availability = reconciliationAvailability(),
  }
end

function Dibs.LogsUI.SearchHistory(criteria)
  criteria = type(criteria) == "table" and criteria or {}
  if not canViewReconciliation() then return { ok = false, reasonCode = "GUILD_ADMIN_REQUIRED" } end
  if not Dibs.RCLootCouncil or type(Dibs.RCLootCouncil.CreateReconciliationSession) ~= "function" then
    return { ok = false, reasonCode = "HISTORY_UNAVAILABLE", availability = reconciliationAvailability() }
  end
  local session, reason = Dibs.RCLootCouncil.CreateReconciliationSession(criteria, localActor())
  if not session then return { ok = false, reasonCode = reason or "HISTORY_UNAVAILABLE", availability = reconciliationAvailability() } end
  local view = Dibs.LogsUI.BuildReconciliationView(session.sessionId)
  return { ok = true, sessionId = session.sessionId, session = session, view = view,
    stage = view.stage, summary = view.summary, candidates = view.candidates, emptyState = view.emptyState }
end

function Dibs.LogsUI.ReviewCandidate(sessionId, candidateId)
  if not canViewReconciliation() then return { ok = false, reasonCode = "GUILD_ADMIN_REQUIRED" } end
  if not Dibs.RCLootCouncil or type(Dibs.RCLootCouncil.GetReconciliationSession) ~= "function" then
    return { ok = false, reasonCode = "HISTORY_UNAVAILABLE" }
  end
  local session, reason = Dibs.RCLootCouncil.GetReconciliationSession(sessionId, localActor())
  local candidate = findCandidate(session, candidateId)
  if not candidate then return { ok = false, reasonCode = reason or "HISTORY_CANDIDATE_NOT_FOUND" } end
  local view = candidateProjection(candidate, true)
  return { ok = true, view = view, candidateId = view.candidateId, item = view.item, winner = view.winner,
    date = view.date, difficulty = view.difficulty, response = view.response, status = view.status,
    evidenceSummary = view.evidenceSummary, technical = view.technical, canConfirm = view.canConfirm }
end

function Dibs.LogsUI.ConfirmCandidate(sessionId, candidateId, reason, options)
  if not canViewReconciliation() then return { ok = false, reasonCode = "GUILD_ADMIN_REQUIRED" } end
  local session = Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetReconciliationSession
    and Dibs.RCLootCouncil.GetReconciliationSession(sessionId, localActor()) or nil
  local candidate = findCandidate(session, candidateId)
  if not candidate then return { ok = false, reasonCode = "HISTORY_SESSION_NOT_FOUND" } end
  if candidate.classification ~= "eligible" then return { ok = false, reasonCode = "HISTORY_CANDIDATE_NOT_CONFIRMABLE" } end
  if type(Dibs.RCLootCouncil.ConfirmReconciliationCandidate) ~= "function" then return { ok = false, reasonCode = "PROTECTED_ACTION_UNAVAILABLE" } end
  local payload = type(options) == "table" and options or {}
  payload.reason = reason or payload.reason
  payload.confirmation = payload.confirmation ~= false
  local result, decision = Dibs.RCLootCouncil.ConfirmReconciliationCandidate(sessionId, candidateId, payload, localActor())
  if not result then return { ok = false, reasonCode = decision or "HISTORY_CONFIRM_FAILED" } end
  return { ok = result.ok ~= false, reasonCode = result.reasonCode, result = result, decision = decision }
end

function Dibs.LogsUI.RejectCandidate(sessionId, candidateId, reason)
  if not canViewReconciliation() then return { ok = false, reasonCode = "GUILD_ADMIN_REQUIRED" } end
  if tostring(reason or ""):match("^%s*$") then return { ok = false, reasonCode = "HISTORY_REASON_REQUIRED" } end
  if not Dibs.RCLootCouncil or type(Dibs.RCLootCouncil.RejectReconciliationCandidate) ~= "function" then return { ok = false, reasonCode = "PROTECTED_ACTION_UNAVAILABLE" } end
  local result, serviceReason = Dibs.RCLootCouncil.RejectReconciliationCandidate(sessionId, candidateId, reason, localActor())
  if not result then return { ok = false, reasonCode = serviceReason or "HISTORY_REJECT_FAILED" } end
  return { ok = result.ok ~= false, reasonCode = result.reasonCode, result = result }
end

local function formatDate(timestamp)
  local value = tonumber(timestamp) or 0
  if value > 0 and type(date) == "function" then
    local ok, formatted = pcall(date, "%Y-%m-%d %H:%M:%S", value)
    if ok and formatted then return tostring(formatted) end
  end
  return value > 0 and tostring(value) or "Unknown"
end

local function splitLine(line, expected)
  local cells = {}
  for cell in (tostring(line or "") .. "|"):gmatch("(.-)|") do
    cells[#cells + 1] = cell:match("^%s*(.-)%s*$")
  end
  while #cells < (expected or 1) do cells[#cells + 1] = "" end
  return cells
end

local function setControlText(control, value)
  if control and control.SetText then control:SetText(value or "") end
end

local function openTable(title, columns, rows, width, height)
  if not Dibs.AceGUI or not Dibs.AceGUI.CreateWindow then return false end
  local windowWidth, windowHeight = windowSize(width or 900, height or 620)
  local shell = Dibs.AceGUI.CreateWindow(title or "Dibs Logs", windowWidth, windowHeight, { "CENTER", 0, 0 })
  if not shell then return false end
  local page = Dibs.AceGUI.AddScrollableList(shell, shell.window, windowHeight - 110)
  Dibs.AceGUI.AddHeading(shell, page, title or "Dibs Logs", "Click a column header to sort. Right-click a row or header for more choices.")
  Dibs.AceGUI.AddTable(shell, page, columns, rows, windowHeight - 170)
  shell.window:Show()
  return true
end

function Dibs.LogsUI.Open(title, lines)
  if not Dibs.AceGUI or not Dibs.AceGUI.CreateWindow then return false end
  local windowWidth, windowHeight = windowSize(760, 560)
  local shell = Dibs.AceGUI.CreateWindow(title or "Dibs Logs", windowWidth, windowHeight, { "CENTER", 0, 0 })
  if not shell then return false end
  local scroll = Dibs.AceGUI.AddScrollableList(shell, shell.window, windowHeight - 100)
  Dibs.AceGUI.AddHeading(shell, scroll, title or "Dibs Logs", "Select the text with Ctrl+A, then copy with Ctrl+C.")
  Dibs.AceGUI.AddSelectableText(shell, scroll, "", table.concat(lines or { "No log entries." }, "\n"), windowWidth - 60, windowHeight - 140)
  shell.window:Show()
  return true
end

function Dibs.LogsUI.OpenPlayerHistory()
  local rows = {}
  for _, tx in ipairs(Dibs.PlayerUI.GetHistory()) do
    rows[#rows + 1] = {
      formatDate(tx.createdAt or tx.timestamp),
      tostring(tx.type or tx.actionType or "UNKNOWN"),
      tostring(tx.amount or tx.quantityDelta or 0),
      tostring(tx.reason or ""),
    }
  end
  if #rows == 0 then rows[1] = { "", "No history entries", "", "" } end
  return openTable("Player History", {
    { title = "Date", width = 150, tooltip = "When the ledger entry was recorded." },
    { title = "Action", width = 150, tooltip = "The ledger operation." },
    { title = "Amount", width = 80, align = "RIGHT", tooltip = "Dibs gained or spent." },
    { title = "Reason", width = 360, tooltip = "Why the entry was created." },
  }, rows, 900, 560)
end

function Dibs.LogsUI.OpenPlayerAcquisitions()
  local rows = {}
  for _, record in ipairs(Dibs.PlayerUI.GetSummary().acquisitions or {}) do
    rows[#rows + 1] = {
      formatDate(record.acquiredAt or record.createdAt),
      tostring(record.itemLink or record.itemName or ("Item " .. tostring(record.itemID))),
      tostring(record.difficulty or "UNKNOWN"),
      tostring(record.source or "VAULT"),
    }
  end
  if #rows == 0 then rows[1] = { "", "No acquisitions", "", "" } end
  return openTable("Player Acquisitions", {
    { title = "Date", width = 150, tooltip = "When the acquisition was recorded." },
    { title = "Item", width = 330, tooltip = "Acquired item." },
    { title = "Difficulty", width = 120, tooltip = "Normal, Heroic, Mythic or Vault tier." },
    { title = "Source", width = 180, tooltip = "Where the acquisition was recorded." },
  }, rows, 900, 560)
end

function Dibs.LogsUI.OpenOfficer(view, seasonId, query)
  if not canViewOfficerLogs() then return false, "GUILD_ADMIN_REQUIRED" end
  if not Dibs.AceGUI or not Dibs.AceGUI.CreateWindow then return false end
  local windowWidth, windowHeight = windowSize(1020, 700)
  local shell = Dibs.AceGUI.CreateWindow("Officer Logs", windowWidth, windowHeight, { "CENTER", 0, 0 })
  if not shell then return false end
  local selectedView, search, pageNumber = view or "players", query or "", 1
  local refresh
  local tabs = Dibs.AceGUI.AddTabs(shell, {
    { text = "Players", value = "players" }, { text = "Pre-Dibs", value = "predibs" }, { text = "History", value = "actions" },
  }, function(value) selectedView, pageNumber = value, 1; refresh() end)
  refresh = function()
    Dibs.AceGUI.Clear(tabs)
    local page = Dibs.OfficerUI.GetPagedView(selectedView, seasonId, pageNumber, 25, search)
    Dibs.AceGUI.AddHeading(shell, tabs, page.title .. "  |  " .. tostring(page.totalCount) .. " entries", "Click a column header to sort ascending or descending. Right-click for the same choices in a menu.")
    local searchBox = Dibs.AceGUI.AddEditBox(shell, tabs, "Search", function(value)
      search, pageNumber = value or "", 1
      refresh()
    end, 360)
    setControlText(searchBox, search)
    Dibs.AceGUI.AddButton(shell, tabs, "Clear", function() search, pageNumber = "", 1; refresh() end, 70)
    local expected, columns
    if selectedView == "actions" then
      expected = 5
      columns = {
        { title = "Date", width = 155, tooltip = "When the ledger entry was recorded." },
        { title = "Player", width = 160, tooltip = "Guild member affected." },
        { title = "Action", width = 150, tooltip = "Ledger operation." },
        { title = "Amount", width = 85, align = "RIGHT", tooltip = "Dibs gained or spent." },
        { title = "Reason", width = 360, tooltip = "Audit context." },
      }
    elseif selectedView == "predibs" then
      expected = 7
      columns = {
        { title = "Date", width = 155, tooltip = "Request creation time." },
        { title = "Player", width = 145, tooltip = "Player who requested the item." },
        { title = "Status", width = 100, tooltip = "Request lifecycle state." },
        { title = "Item", width = 240, tooltip = "Reserved item." },
        { title = "Difficulty", width = 100, tooltip = "Requested difficulty." },
        { title = "Mode", width = 110, tooltip = "Wild Open or Encounter." },
        { title = "Sync", width = 120, tooltip = "Delivery acknowledgement." },
      }
    else
      expected = 3
      columns = {
        { title = "Player", width = 300, tooltip = "Guild member." },
        { title = "Balance", width = 130, align = "RIGHT", tooltip = "Current Dibs balance." },
        { title = "Actions", width = 130, align = "RIGHT", tooltip = "Number of ledger entries." },
      }
    end
    local rows = {}
    for _, line in ipairs(page.lines or {}) do rows[#rows + 1] = splitLine(line, expected) end
    Dibs.AceGUI.AddTable(shell, tabs, columns, rows, windowHeight - 190)
    local pageControls = Dibs.AceGUI.AddInlineGroup(shell, tabs)
    local previous = Dibs.AceGUI.AddButton(shell, pageControls, "Previous", function() pageNumber = math.max(1, pageNumber - 1); refresh() end, 95)
    Dibs.AceGUI.AddLabel(shell, pageControls, "Page " .. tostring(page.page) .. "/" .. tostring(page.totalPages))
    local nextButton = Dibs.AceGUI.AddButton(shell, pageControls, "Next", function() pageNumber = math.min(page.totalPages, pageNumber + 1); refresh() end, 75)
    Dibs.AceGUI.SetDisabled(previous, page.page <= 1)
    Dibs.AceGUI.SetDisabled(nextButton, page.page >= page.totalPages)
  end
  refresh()
  shell.window:Show()
  return true
end
