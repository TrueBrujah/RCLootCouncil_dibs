local Dibs = _G.Dibs
Dibs.Disputes = Dibs.Disputes or {}

local Disputes = Dibs.Disputes

local MAX_NOTE_LENGTH = 240
local MAX_REPLY_LENGTH = 240
local MAX_REASON_LENGTH = 360
local MAX_REQUESTS = 500
local MAX_TIMELINE = 120

Disputes.MAX_NOTE_LENGTH = MAX_NOTE_LENGTH
Disputes.MAX_REPLY_LENGTH = MAX_REPLY_LENGTH
Disputes.MAX_REASON_LENGTH = MAX_REASON_LENGTH

Disputes.CATEGORIES = {
  wrong_debit = "Wrong debit",
  missing_debit = "Missing debit",
  duplicate = "Duplicate",
  wrong_item_player = "Wrong item or player",
  eligibility = "Eligibility decision",
  integration = "Integration problem",
  other = "Other",
}

Disputes.STATUSES = {
  OPEN = "Open",
  UNDER_REVIEW = "Under review",
  NEED_INFORMATION = "Need information",
  RESOLVED = "Resolved",
  REJECTED = "Rejected",
}

Disputes.ACTIONS = {
  CORRECT_BALANCE = "correct_balance",
  CORRECT_TARGET = "correct_target",
  NO_CORRECTION = "no_correction",
  ASK_INFORMATION = "ask_information",
  DUPLICATE = "duplicate",
  REJECT = "reject",
  REOPEN = "reopen",
  REFUND = "refund",
  REVOKE = "revoke",
  HISTORICAL_IMPORT = "historical_import",
  ADJUSTMENT = "adjustment",
}

local ACTIVE_STATUSES = {
  [Disputes.STATUSES.OPEN] = true,
  [Disputes.STATUSES.UNDER_REVIEW] = true,
  [Disputes.STATUSES.NEED_INFORMATION] = true,
}

local SOURCE_VALUES = {
  dibs = true,
  rclootcouncil = true,
  readiness = true,
  reconciliation = true,
  unknown = true,
}

local function text(key, fallback)
  return (Dibs.L and Dibs.L[key]) or fallback
end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function bounded(value, maximum)
  local result = trim(value)
  if #result > maximum then result = result:sub(1, maximum) end
  return result
end

local function copy(value, depth)
  if type(value) ~= "table" then return value end
  depth = (depth or 0) + 1
  if depth > 8 then return nil end
  local result = {}
  for key, item in pairs(value) do
    result[key] = copy(item, depth)
  end
  return result
end

local function now()
  return type(time) == "function" and tonumber(time()) or 0
end

local function identity(value)
  -- A missing field must remain missing.  Permissions.CanonicalPlayerId(nil)
  -- intentionally resolves to the local GUID, which is useful for actor
  -- checks but would incorrectly turn an omitted winner into a local winner
  -- while normalizing evidence.
  if value == nil then return nil end
  if Dibs.Permissions and type(Dibs.Permissions.CanonicalPlayerId) == "function" then
    local ok, result = pcall(Dibs.Permissions.CanonicalPlayerId, value)
    if ok and result then return string.lower(tostring(result)) end
  end
  local valueText = trim(value)
  return valueText ~= "" and string.lower(valueText) or nil
end

local function localIdentity()
  local name = identity(Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
  if name then return name end
  local guid = Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId
    and Dibs.Permissions.CanonicalPlayerId(nil)
  return identity(guid)
end

local function isLocalIdentity(value)
  local candidate = identity(value)
  if not candidate then return false end
  local nameId = identity(Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
  local guid = Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId
    and Dibs.Permissions.CanonicalPlayerId(nil)
  local guidId = identity(guid)
  return candidate == nameId or candidate == guidId
end

local function isLocalActor(actor)
  if actor == nil then return true end
  return isLocalIdentity(actor)
end

local function samePlayer(first, second)
  local firstId, secondId = identity(first), identity(second)
  if firstId and secondId and firstId == secondId then return true end
  return first ~= nil and second ~= nil and isLocalIdentity(first) and isLocalIdentity(second)
end

local function isOfficer(actor)
  if not isLocalActor(actor) then return false end
  if Dibs.Permissions and type(Dibs.Permissions.GetGuildRole) == "function" then
    local ok, role = pcall(Dibs.Permissions.GetGuildRole, actor)
    if ok then return role == "gm" or role == "officer" end
  end
  return false
end

local function currentScope()
  return tostring(Dibs.currentGuildKey or (Dibs.GetGuildKey and Dibs.GetGuildKey()) or "unknown-scope")
end

local function ensureState()
  local db = Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
  db.disputes = db.disputes or {}
  db.disputes.version = tonumber(db.disputes.version) or 1
  db.disputes.requests = db.disputes.requests or {}
  db.disputes.order = db.disputes.order or {}
  db.disputes.corrections = db.disputes.corrections or {}
  return db.disputes
end

local function normalizeCategory(category)
  local value = string.lower(trim(category)):gsub("[%s%-]+", "_")
  local aliases = {
    wrongdebit = "wrong_debit",
    missingdebit = "missing_debit",
    duplicate = "duplicate",
    wrong_item = "wrong_item_player",
    wrong_player = "wrong_item_player",
    eligibility_decision = "eligibility",
    integration_problem = "integration",
  }
  value = aliases[value] or value
  return Disputes.CATEGORIES[value] and value or "other"
end

local function normalizeStatus(status)
  local value = string.lower(trim(status)):gsub("[%s%-]+", "_")
  local aliases = {
    open = Disputes.STATUSES.OPEN,
    under_review = Disputes.STATUSES.UNDER_REVIEW,
    need_information = Disputes.STATUSES.NEED_INFORMATION,
    waiting_for_information = Disputes.STATUSES.NEED_INFORMATION,
    resolved = Disputes.STATUSES.RESOLVED,
    rejected = Disputes.STATUSES.REJECTED,
  }
  return aliases[value]
end

local function normalizeSource(source)
  local value = string.lower(trim(source)):gsub("[%s%-]+", "_")
  if value == "rcloot_council" then value = "rclootcouncil" end
  return SOURCE_VALUES[value] and value or "unknown"
end

local function addUnavailable(fields, key, value)
  if value == nil or value == "" then table.insert(fields, key) end
end

local function findTransaction(reference)
  if not reference or reference == "" then return nil end
  if Dibs.Ledger and type(Dibs.Ledger.GetTransactionForAward) == "function" then
    local ok, transaction = pcall(Dibs.Ledger.GetTransactionForAward, reference)
    if ok and transaction then return transaction end
  end
  if Dibs.Ledger and type(Dibs.Ledger.GetAllTransactions) == "function" then
    for _, transaction in ipairs(Dibs.Ledger.GetAllTransactions()) do
      if tostring(transaction.transactionId or "") == tostring(reference) then return transaction end
    end
  end
  return nil
end

local function transactionForPayload(payload)
  if type(payload.transaction) == "table" then return payload.transaction end
  local reference = payload.transactionRef or payload.transactionId
  return findTransaction(reference)
end

local function ownerName(payload)
  local value = payload.playerName or payload.player or (Dibs.GetPlayerName and Dibs.GetPlayerName() or "UnknownPlayer")
  if type(value) == "table" then value = value.name or value.playerName or value.guid end
  return tostring(value or "UnknownPlayer")
end

local function categoryLabel(category)
  local keys = {
    wrong_debit = "DISPUTE_CATEGORY_WRONG_DEBIT",
    missing_debit = "DISPUTE_CATEGORY_MISSING_DEBIT",
    duplicate = "DISPUTE_CATEGORY_DUPLICATE",
    wrong_item_player = "DISPUTE_CATEGORY_WRONG_ITEM_PLAYER",
    eligibility = "DISPUTE_CATEGORY_ELIGIBILITY",
    integration = "DISPUTE_CATEGORY_INTEGRATION",
    other = "DISPUTE_CATEGORY_OTHER",
  }
  return text(keys[category], Disputes.CATEGORIES[category] or "Other")
end

local function field(raw, first, second)
  if type(raw) ~= "table" then return nil end
  return raw[first] or (second and raw[second])
end

local function normalizeOneEvidence(raw, fallbackSource, ownerId)
  raw = type(raw) == "table" and raw or {}
  local source = normalizeSource(raw.source or fallbackSource)
  local transactionRef = raw.transactionRef or raw.transactionId
  local awardRef = raw.awardRef
  local historyRef = raw.historyRef
  local winner = raw.winner or raw.playerName or raw.player
  local winnerId = identity(winner)
  if winnerId and ownerId and not samePlayer(winner, ownerId) then return nil, "PLAYER_SCOPE_REQUIRED" end
  local itemID = tonumber(raw.itemID or raw.itemId)
  local item = raw.itemLink or raw.itemName or raw.item
  local season = raw.season or raw.seasonId
  local unavailable = {}
  addUnavailable(unavailable, "source", source == "unknown" and nil or source)
  addUnavailable(unavailable, "item", itemID or item)
  addUnavailable(unavailable, "winner", winner)
  addUnavailable(unavailable, "season", season)
  addUnavailable(unavailable, "status", raw.status or raw.sourceStatus)
  if not transactionRef and not awardRef and not historyRef then
    table.insert(unavailable, "reference")
  end
  local confidence = raw.confidence
  if confidence ~= "high" and confidence ~= "medium" and confidence ~= "low" then
    confidence = (transactionRef or awardRef or historyRef) and "high" or ((itemID or item) and "medium" or "unavailable")
  end
  return {
    evidenceId = raw.evidenceId or (Dibs.NewId and Dibs.NewId("evidence") or ("evidence-" .. tostring(now()))),
    source = source,
    transactionRef = transactionRef and tostring(transactionRef) or nil,
    awardRef = awardRef and tostring(awardRef) or nil,
    historyRef = historyRef and tostring(historyRef) or nil,
    itemID = itemID,
    item = item and bounded(item, 180) or nil,
    winner = winner and bounded(winner, 80) or nil,
    response = raw.response and bounded(raw.response, 80) or nil,
    status = raw.status and bounded(raw.status, 40) or (raw.sourceStatus and bounded(raw.sourceStatus, 40) or nil),
    season = season and bounded(season, 100) or nil,
    timestamp = tonumber(raw.timestamp or raw.createdAt or raw.time),
    balanceImpact = tonumber(raw.balanceImpact or raw.amount),
    confidence = confidence,
    integrationStatus = raw.integrationStatus,
    integrationReason = raw.integrationReason,
    unavailableFields = unavailable,
  }
end

function Disputes.NormalizeEvidence(payload, owner)
  payload = type(payload) == "table" and payload or {}
  local ownerId = identity(owner or ownerName(payload))
  local list = {}
  local rawList = payload.evidence or payload.attachedEvidence
  if type(rawList) == "table" and #rawList > 0 then
    for _, raw in ipairs(rawList) do table.insert(list, raw) end
  elseif type(rawList) == "table" then
    table.insert(list, rawList)
  end

  local transaction = transactionForPayload(payload)
  if transaction then
    local txOwner = identity(transaction.playerName or transaction.playerKey or transaction.playerId)
    if txOwner and ownerId and not samePlayer(txOwner, ownerId) then return nil, "PLAYER_SCOPE_REQUIRED" end
    table.insert(list, {
      source = "dibs",
      transactionRef = transaction.transactionId,
      awardRef = transaction.awardRef,
      itemID = transaction.itemID,
      itemLink = transaction.itemLink,
      itemName = transaction.itemName,
      playerName = transaction.playerName,
      response = transaction.response or transaction.responseType,
      status = transaction.sourceStatus or transaction.status,
      seasonId = transaction.seasonId,
      timestamp = transaction.createdAt or transaction.timestamp,
      amount = transaction.amount or transaction.quantityDelta,
    })
  end

  if (payload.rclootcouncil or payload.source == "rclootcouncil")
    and Dibs.RCLootCouncil and type(Dibs.RCLootCouncil.GetAwardEvidence) == "function"
  then
    local ok, adapterEvidence = pcall(Dibs.RCLootCouncil.GetAwardEvidence, payload.rclootcouncil or payload)
    if ok and type(adapterEvidence) == "table" then table.insert(list, adapterEvidence) end
  end

  local explicit = {
    source = payload.source,
    transactionRef = payload.transactionRef or payload.transactionId,
    awardRef = payload.awardRef,
    historyRef = payload.historyRef,
    itemID = payload.itemID,
    itemLink = payload.itemLink,
    itemName = payload.itemName,
    playerName = payload.winner or payload.playerName,
    response = payload.response or payload.responseText,
    status = payload.status or payload.sourceStatus,
    seasonId = payload.seasonId,
    timestamp = payload.timestamp or payload.createdAt,
    balanceImpact = payload.balanceImpact or payload.amount,
  }
  local hasExplicit = explicit.transactionRef or explicit.awardRef or explicit.historyRef or explicit.itemID
    or explicit.itemLink or explicit.response or explicit.status
  -- A resolved transaction already supplies the canonical evidence record.
  -- Do not append a second, partial record for the same reference; this also
  -- avoids treating the payload's omitted winner as a conflicting owner.
  if hasExplicit and not transaction then table.insert(list, explicit) end

  local normalized = {}
  for _, raw in ipairs(list) do
    local value, reason = normalizeOneEvidence(raw, payload.source, ownerId)
    if not value then return nil, reason end
    table.insert(normalized, value)
  end
  if #normalized == 0 then
    local value = normalizeOneEvidence({ source = "unknown" }, "unknown", ownerId)
    table.insert(normalized, value)
  end
  return normalized
end

local function primaryEvidence(request)
  return request and request.evidence and request.evidence[1] or nil
end

local function evidenceKey(evidence, payload)
  evidence = evidence or {}
  return table.concat({
    tostring(evidence.transactionRef or ""),
    tostring(evidence.awardRef or ""),
    tostring(evidence.historyRef or ""),
    tostring(evidence.itemID or payload.itemID or ""),
    tostring(evidence.timestamp or payload.timestamp or ""),
  }, "|")
end

local function duplicateKey(ownerId, category, evidence, payload)
  local key = evidenceKey(evidence, payload)
  if key == "||||" then key = "context:" .. bounded(payload.note or payload.context or "", 80) end
  return table.concat({ tostring(ownerId or "unknown"), tostring(category), key }, "|")
end

local function audit(request, action, actor, previousStatus, newStatus, reason, extra)
  local event = {
    eventId = Dibs.NewId and Dibs.NewId("review-event") or ("review-event-" .. tostring(now())),
    requestId = request.requestId,
    scope = currentScope(),
    actorId = identity(actor) or localIdentity() or "unknown",
    actorName = bounded(type(actor) == "table" and (actor.name or actor.playerName) or actor or (Dibs.GetPlayerName and Dibs.GetPlayerName() or "unknown"), 80),
    actorRole = (actor == nil and "local" or (isOfficer(actor) and "officer" or "player")),
    timestamp = now(),
    action = action,
    previousStatus = previousStatus,
    newStatus = newStatus,
    reason = reason and bounded(reason, MAX_REASON_LENGTH) or nil,
  }
  for key, value in pairs(extra or {}) do event[key] = copy(value) end
  request.timeline = request.timeline or {}
  table.insert(request.timeline, event)
  while #request.timeline > MAX_TIMELINE do table.remove(request.timeline, 1) end
  request.lastUpdatedAt = event.timestamp
  return event
end

local function findActiveByKey(state, key)
  for _, requestId in ipairs(state.order or {}) do
    local request = state.requests[requestId]
    if request and request.duplicateKey == key and ACTIVE_STATUSES[request.status] then return request end
  end
  return nil
end

local function insertRequest(state, request)
  state.requests[request.requestId] = request
  table.insert(state.order, 1, request.requestId)
  -- Keep request storage bounded without deleting open cases. Closed cases remain
  -- in the append-only audit history until the configured retention policy acts.
  while #state.order > MAX_REQUESTS do
    local removeIndex
    for index = #state.order, 1, -1 do
      local candidate = state.requests[state.order[index]]
      if candidate and not ACTIVE_STATUSES[candidate.status] then removeIndex = index break end
    end
    if not removeIndex then break end
    state.requests[state.order[removeIndex]] = nil
    table.remove(state.order, removeIndex)
  end
end

local function requestOwner(request)
  return request and request.player and (request.player.id or request.player.guid or request.player.name) or nil
end

local function canReadRequest(requestId, actor)
  local request = ensureState().requests[requestId]
  if not request then return nil, "REQUEST_NOT_FOUND" end
  if request.guildScope ~= currentScope() then return nil, "REQUEST_NOT_FOUND" end
  -- An explicit owner identity asks for the player-safe view even when that
  -- character also happens to be a guild officer.  A nil actor is reserved
  -- for the local officer context and retains the private officer view.
  if actor ~= nil and isLocalActor(actor) and isLocalIdentity(requestOwner(request)) then
    return request, false
  end
  if isOfficer(actor) then return request, true end
  if isLocalActor(actor) and isLocalIdentity(requestOwner(request)) then return request, false end
  return nil, "REQUEST_NOT_FOUND"
end

function Disputes.GetCategories()
  local result = {}
  for key in pairs(Disputes.CATEGORIES) do result[key] = categoryLabel(key) end
  return result
end

function Disputes.GetStatuses()
  return copy(Disputes.STATUSES)
end

function Disputes.GetActionLabels()
  return {
    correct_balance = text("DISPUTE_ACTION_CORRECT", "Correct balance"),
    correct_target = text("DISPUTE_ACTION_CORRECT_TARGET", "Correct item or player"),
    no_correction = text("DISPUTE_ACTION_NO_CORRECTION", "No correction"),
    ask_information = text("DISPUTE_ACTION_ASK_INFORMATION", "Ask for information"),
    duplicate = text("DISPUTE_ACTION_DUPLICATE", "Mark duplicate"),
    reject = text("DISPUTE_ACTION_REJECT", "Reject"),
    reopen = text("DISPUTE_ACTION_REOPEN", "Reopen"),
    refund = text("DISPUTE_ACTION_REFUND", "Refund Dib"),
    revoke = text("DISPUTE_ACTION_REVOKE", "Revoke Dib"),
    historical_import = text("DISPUTE_ACTION_IMPORT", "Historical import"),
    adjustment = text("DISPUTE_ACTION_ADJUSTMENT", "Administrative adjustment"),
  }
end

function Disputes.CreateReport(payload, actor)
  payload = type(payload) == "table" and payload or {}
  actor = actor or payload.actor
  local player = ownerName(payload)
  local ownerId = identity(player)
  -- Reports are always submitted for the local character.  CanonicalPlayerId
  -- prefers GUIDs for nil actors while names are used for explicit payloads,
  -- so compare through the identity matcher instead of comparing those forms
  -- directly.
  if not ownerId or not isLocalActor(actor) or not isLocalIdentity(player) then
    return nil, "PLAYER_SCOPE_REQUIRED"
  end
  local transaction = transactionForPayload(payload)
  if transaction then
    local txOwner = identity(transaction.playerName or transaction.playerKey or transaction.playerId)
    if txOwner and not samePlayer(txOwner, ownerId) then return nil, "PLAYER_SCOPE_REQUIRED" end
  end
  local evidence, evidenceReason = Disputes.NormalizeEvidence(payload, player)
  if not evidence then return nil, evidenceReason end
  local category = normalizeCategory(payload.category)
  local state = ensureState()
  local key = duplicateKey(ownerId, category, primaryEvidence({ evidence = evidence }), payload)
  local existing = findActiveByKey(state, key)
  if existing then
    existing.duplicateSubmissionCount = (tonumber(existing.duplicateSubmissionCount) or 0) + 1
    audit(existing, "duplicate_submission", player, existing.status, existing.status, "Linked to existing active request.", { linkedRequestId = existing.requestId })
    return existing, "DUPLICATE_ACTIVE", true
  end

  local createdAt = now()
  local request = {
    requestId = Dibs.NewId and Dibs.NewId("review") or ("review-" .. tostring(createdAt)),
    guildScope = currentScope(),
    player = { id = ownerId, name = bounded(player, 80) },
    category = category,
    categoryLabel = categoryLabel(category),
    seasonId = payload.seasonId or (evidence[1] and evidence[1].season) or nil,
    note = bounded(payload.note, MAX_NOTE_LENGTH),
    attachedContext = {
      source = payload.source and normalizeSource(payload.source) or nil,
      itemID = tonumber(payload.itemID),
      item = bounded(payload.itemLink or payload.itemName or payload.item, 180),
      seasonId = payload.seasonId and bounded(payload.seasonId, 100) or nil,
      timestamp = tonumber(payload.timestamp or payload.createdAt) or createdAt,
    },
    evidence = evidence,
    status = Disputes.STATUSES.OPEN,
    duplicateKey = key,
    createdAt = createdAt,
    lastUpdatedAt = createdAt,
    replies = {},
    timeline = {},
    resolution = nil,
    version = 1,
  }
  insertRequest(state, request)
  audit(request, "created", player, nil, request.status, request.note ~= "" and request.note or "Player report created.", {
    category = request.category,
    evidenceIds = (function()
      local ids = {}
      for _, item in ipairs(evidence) do table.insert(ids, item.evidenceId) end
      return ids
    end)(),
  })
  return request
end

Disputes.SubmitReport = Disputes.CreateReport
Disputes.CreatePlayerReport = Disputes.CreateReport

function Disputes.GetRequest(requestId, actor)
  local request, officer = canReadRequest(requestId, actor)
  if not request then return nil, officer end
  return officer and Disputes.BuildOfficerView(request) or Disputes.BuildSafeView(request)
end

function Disputes.ListForPlayer(actor, options)
  options = type(options) == "table" and options or {}
  if not isLocalActor(actor) then return {}, "PLAYER_SCOPE_REQUIRED" end
  local ownerId = localIdentity()
  local state = ensureState()
  local result = {}
  for _, requestId in ipairs(state.order or {}) do
    local request = state.requests[requestId]
    if request and request.guildScope == currentScope() and isLocalIdentity(requestOwner(request)) then
      local statusOk = not options.status or normalizeStatus(options.status) == request.status
      local query = string.lower(trim(options.query))
      local haystack = string.lower((request.categoryLabel or "") .. " " .. (request.note or "") .. " " .. request.status)
      if statusOk and (query == "" or string.find(haystack, query, 1, true)) then
        table.insert(result, Disputes.BuildSafeView(request))
      end
    end
  end
  return result
end

function Disputes.ListForOfficer(actor, options)
  options = type(options) == "table" and options or {}
  if not isOfficer(actor) then return {}, "GUILD_ADMIN_REQUIRED" end
  local state = ensureState()
  local result = {}
  local status = options.status and normalizeStatus(options.status) or nil
  local query = string.lower(trim(options.query))
  for _, requestId in ipairs(state.order or {}) do
    local request = state.requests[requestId]
    if request and request.guildScope == currentScope() and (not status or request.status == status) then
      local evidence = primaryEvidence(request)
      local haystack = string.lower(table.concat({ request.player and request.player.name or "", request.categoryLabel or "", request.status or "", request.note or "", evidence and evidence.item or "" }, " "))
      if query == "" or string.find(haystack, query, 1, true) then table.insert(result, Disputes.BuildOfficerView(request)) end
    end
  end
  return result
end

function Disputes.ListRequests(actor, options)
  if type(actor) == "table" and options == nil and (actor.actor or actor.status or actor.query or actor.scope) then
    options = actor
    actor = options.actor
  end
  if isOfficer(actor) then return Disputes.ListForOfficer(actor, options) end
  return Disputes.ListForPlayer(actor, options)
end

Disputes.GetPlayerRequests = Disputes.ListForPlayer
Disputes.GetReviewQueue = Disputes.ListForOfficer

function Disputes.AddReply(requestId, replyText, actor)
  local request, officer = canReadRequest(requestId, actor)
  if not request then return nil, officer end
  if officer then return nil, "PLAYER_REPLY_REQUIRED" end
  if request.status ~= Disputes.STATUSES.NEED_INFORMATION then return nil, "REPLY_NOT_REQUESTED" end
  local value = bounded(replyText, MAX_REPLY_LENGTH)
  if value == "" then return nil, "REPLY_REQUIRED" end
  local reply = {
    replyId = Dibs.NewId and Dibs.NewId("reply") or ("reply-" .. tostring(now())),
    requestId = requestId,
    author = "player",
    authorId = localIdentity(),
    boundedText = value,
    createdAt = now(),
  }
  table.insert(request.replies, reply)
  local previous = request.status
  request.status = Disputes.STATUSES.OPEN
  request.question = nil
  audit(request, "player_reply", actor, previous, request.status, "Player replied to the information request.", { replyId = reply.replyId })
  return copy(reply)
end

Disputes.Reply = Disputes.AddReply

local function requireOfficer(requestId, actor)
  if not isOfficer(actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local request = ensureState().requests[requestId]
  if not request then return nil, "REQUEST_NOT_FOUND" end
  return request
end

local function requireReason(options)
  local reason = bounded(options and (options.reason or options.explanation), MAX_REASON_LENGTH)
  return reason ~= "" and reason or nil
end

local function finishWithoutCorrection(request, action, actor, newStatus, reason, extra)
  local previous = request.status
  request.status = newStatus
  request.resolution = {
    action = action,
    actorId = identity(actor) or localIdentity(),
    createdAt = now(),
    reason = reason,
    changedBalance = false,
  }
  audit(request, action, actor, previous, newStatus, reason, extra)
  return { ok = true, request = copy(request), changedBalance = false }
end

local function correctionDetails(request, action, options)
  options = options or {}
  local evidence = primaryEvidence(request) or {}
  local original = evidence.transactionRef and findTransaction(evidence.transactionRef) or nil
  local amount = tonumber(options.amount or options.delta)
  local ledgerAction = action
  if action == Disputes.ACTIONS.CORRECT_BALANCE then
    if amount == nil then
      if request.category == "missing_debit" then amount = 1; ledgerAction = "ledger.use"
      elseif request.category == "wrong_debit" then amount = 1; ledgerAction = "ledger.refund"
      else return nil, "AMOUNT_REQUIRED" end
    elseif request.category == "missing_debit" and amount ~= 0 then
      ledgerAction = "ledger.use"
    elseif request.category == "wrong_debit" and amount ~= 0 then
      ledgerAction = "ledger.refund"
    else
      ledgerAction = amount < 0 and "ledger.use" or "ledger.refund"
    end
  elseif action == Disputes.ACTIONS.REFUND then
    amount = math.abs(amount or 1); ledgerAction = "ledger.refund"
  elseif action == Disputes.ACTIONS.REVOKE then
    amount = -math.abs(amount or 1); ledgerAction = "ledger.adjust"
  elseif action == Disputes.ACTIONS.ADJUSTMENT then
    if amount == nil or amount == 0 then return nil, "AMOUNT_REQUIRED" end
    ledgerAction = "ledger.adjust"
  elseif action == Disputes.ACTIONS.HISTORICAL_IMPORT then
    if amount == nil or amount == 0 then return nil, "AMOUNT_REQUIRED" end
    ledgerAction = "ledger.adjust"
  else
    return nil, "ACTION_NOT_CORRECTION"
  end
  if ledgerAction == "ledger.use" then amount = math.abs(amount) end
  if ledgerAction == "ledger.refund" then amount = math.abs(amount) end
  return {
    amount = amount,
    ledgerAction = ledgerAction,
    evidence = evidence,
    original = original,
  }
end

local function parseItemID(value)
  return tonumber(tostring(value or ""):match("item:(%d+)"))
end

-- Target corrections are deliberately separate from balance corrections.  The
-- original evidence and ledger rows remain immutable; the request records the
-- corrected item/player and, when a linked ledger entry exists, appends a
-- balanced transfer between the old and new player.
local function targetCorrectionDetails(request, options)
  options = options or {}
  local evidence = primaryEvidence(request) or {}
  local original = evidence.transactionRef and findTransaction(evidence.transactionRef) or nil
  local targetPlayer = bounded(options.playerName or options.correctPlayer or options.targetPlayer, 80)
  local targetItem = bounded(options.itemLink or options.itemName or options.item, 180)
  local targetItemID = tonumber(options.itemID or options.itemId or options.correctItemID or options.targetItemID)
  local linkedItemID = parseItemID(targetItem)
  if not targetItemID and tonumber(targetItem) then targetItemID = tonumber(targetItem) end
  if not targetItemID and linkedItemID then targetItemID = linkedItemID end
  if targetItemID and linkedItemID and targetItemID ~= linkedItemID then return nil, "CORRECTION_ITEM_MISMATCH" end
  if targetPlayer == "" then targetPlayer = nil end
  if targetItem == "" then targetItem = nil end
  if not targetPlayer and not targetItemID and not targetItem then return nil, "CORRECTION_TARGET_REQUIRED" end

  local oldPlayer = original and original.playerName or evidence.winner or (request.player and request.player.name)
  local playerChanged = targetPlayer and not samePlayer(targetPlayer, oldPlayer) or false
  local itemChanged = (targetItemID and tonumber(targetItemID) ~= tonumber(evidence.itemID))
    or (targetItem and tostring(targetItem) ~= tostring(evidence.item or ""))
  if not playerChanged and not itemChanged then return nil, "CORRECTION_NO_CHANGE" end

  local amount = original and tonumber(original.amount or original.quantityDelta) or nil
  if amount == 0 then amount = nil end
  return {
    evidence = evidence,
    original = original,
    oldPlayer = oldPlayer,
    targetPlayer = targetPlayer,
    targetItem = targetItem,
    targetItemID = targetItemID,
    playerChanged = playerChanged,
    itemChanged = itemChanged == true,
    transferAmount = playerChanged and amount or nil,
  }
end

local function applyTargetCorrection(request, action, actor, options)
  options = type(options) == "table" and options or {}
  if options.confirmed ~= true and options.confirmation ~= true then return nil, "CONFIRMATION_REQUIRED" end
  local reason = requireReason(options)
  if not reason then return nil, "REASON_REQUIRED" end
  local details, detailReason = targetCorrectionDetails(request, options)
  if not details then return nil, detailReason end

  local key = table.concat({
    request.requestId,
    tostring(details.evidence.evidenceId or "unknown"),
    action,
    tostring(details.targetPlayer or ""),
    tostring(details.targetItemID or ""),
    tostring(details.targetItem or ""),
  }, "|")
  local state = ensureState()
  local existing = state.corrections[key]
  if existing then
    return {
      ok = true,
      idempotentReplay = true,
      request = copy(request),
      transactions = copy(type(existing) == "table" and existing.transactions or nil),
      changedBalance = type(existing) == "table" and existing.changedBalance == true or false,
    }
  end

  local transactionIds = {}
  if details.playerChanged and details.transferAmount and details.oldPlayer and details.targetPlayer then
    if not Dibs.ProtectedActions or type(Dibs.ProtectedActions.Execute) ~= "function" then return nil, "PROTECTED_ACTION_UNAVAILABLE" end
    local common = {
      amount = details.transferAmount,
      source = "dispute-center",
      seasonId = request.attachedContext and request.attachedContext.seasonId
        or request.seasonId
        or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId()),
      reviewRequestId = request.requestId,
      evidenceId = details.evidence.evidenceId,
      originalTransactionId = details.original and details.original.transactionId or details.evidence.transactionRef,
      correctionKey = key,
      confirmation = true,
      itemID = details.targetItemID or details.evidence.itemID,
      itemLink = details.targetItem or details.evidence.item,
    }
    local reversePayload = copy(common)
    reversePayload.playerName = details.oldPlayer
    reversePayload.amount = -details.transferAmount
    reversePayload.reason = "Review " .. request.requestId .. ": return delta from incorrect player - " .. reason
    local reverse = Dibs.ProtectedActions.Execute("ledger.adjust", actor, reversePayload)
    if not reverse or reverse.ok ~= true or not reverse.value then
      return nil, reverse and (reverse.reasonCode or reverse.diagnostic) or "TARGET_TRANSFER_FAILED"
    end
    table.insert(transactionIds, reverse.value.transactionId)

    local applyPayload = copy(common)
    applyPayload.playerName = details.targetPlayer
    applyPayload.reason = "Review " .. request.requestId .. ": apply delta to corrected player - " .. reason
    local applied = Dibs.ProtectedActions.Execute("ledger.adjust", actor, applyPayload)
    if not applied or applied.ok ~= true or not applied.value then
      -- Restore the original balance if the second append is rejected.  This
      -- keeps a failed transfer from silently leaving the old player short.
      local rollback = copy(common)
      rollback.playerName = details.oldPlayer
      rollback.amount = details.transferAmount
      rollback.reason = "Review " .. request.requestId .. ": rollback incomplete target correction"
      rollback.correctionKey = key .. ":rollback"
      Dibs.ProtectedActions.Execute("ledger.adjust", actor, rollback)
      return nil, applied and (applied.reasonCode or applied.diagnostic) or "TARGET_TRANSFER_FAILED"
    end
    table.insert(transactionIds, applied.value.transactionId)
  end

  local evidence = details.evidence
  if details.itemChanged then
    evidence.originalItemID = evidence.originalItemID or evidence.itemID
    evidence.originalItem = evidence.originalItem or evidence.item
    if details.targetItemID then evidence.itemID = details.targetItemID end
    if details.targetItem then evidence.item = details.targetItem end
  end
  if details.playerChanged then
    evidence.originalWinner = evidence.originalWinner or evidence.winner
    evidence.winner = details.targetPlayer
  end
  request.targetCorrection = {
    correctedPlayer = details.playerChanged and details.targetPlayer or nil,
    correctedItemID = details.itemChanged and details.targetItemID or nil,
    correctedItem = details.itemChanged and details.targetItem or nil,
    originalPlayer = details.playerChanged and details.oldPlayer or nil,
    originalItemID = details.itemChanged and (evidence.originalItemID or evidence.itemID) or nil,
    originalItem = details.itemChanged and (evidence.originalItem or evidence.item) or nil,
    transactionIds = copy(transactionIds),
  }
  local previous = request.status
  request.status = Disputes.STATUSES.RESOLVED
  if #transactionIds > 0 then request.correctionTransactionId = transactionIds[1] end
  request.resolution = {
    action = action,
    actorId = identity(actor) or localIdentity(),
    createdAt = now(),
    reason = reason,
    changedBalance = #transactionIds > 0,
    transactionIds = copy(transactionIds),
    targetCorrection = copy(request.targetCorrection),
  }
  state.corrections[key] = {
    transactions = copy(transactionIds),
    changedBalance = #transactionIds > 0,
  }
  audit(request, action, actor, previous, request.status, reason, {
    correctedPlayer = request.targetCorrection.correctedPlayer,
    correctedItemID = request.targetCorrection.correctedItemID,
    correctedItem = request.targetCorrection.correctedItem,
    originalPlayer = request.targetCorrection.originalPlayer,
    originalItemID = request.targetCorrection.originalItemID,
    transferTransactions = copy(transactionIds),
  })
  return {
    ok = true,
    request = copy(request),
    transactions = copy(transactionIds),
    changedBalance = #transactionIds > 0,
  }
end

local function applyCorrection(request, action, actor, options)
  options = type(options) == "table" and options or {}
  if options.confirmed ~= true and options.confirmation ~= true then return nil, "CONFIRMATION_REQUIRED" end
  local reason = requireReason(options)
  if not reason then return nil, "REASON_REQUIRED" end
  local details, detailReason = correctionDetails(request, action, options)
  if not details then return nil, detailReason end
  local evidence = details.evidence
  local key = table.concat({ request.requestId, tostring(evidence.evidenceId or "unknown"), action, tostring(details.amount) }, "|")
  local state = ensureState()
  local existingId = state.corrections[key]
  if existingId then
    local existing = Dibs.Ledger and Dibs.Ledger.GetTransactions and Dibs.Ledger.GetTransactions(request.seasonId, request.player.name) or {}
    for _, transaction in ipairs(existing) do
      if transaction.transactionId == existingId then
        return { ok = true, idempotentReplay = true, request = copy(request), transaction = copy(transaction), changedBalance = true }
      end
    end
  end
  if not Dibs.ProtectedActions or type(Dibs.ProtectedActions.Execute) ~= "function" then return nil, "PROTECTED_ACTION_UNAVAILABLE" end
  local payload = {
    playerName = request.player.name,
    amount = details.amount,
    reason = "Review " .. request.requestId .. ": " .. reason,
    source = "dispute-center",
    seasonId = request.attachedContext and request.attachedContext.seasonId
      or request.seasonId
      or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId()),
    reviewRequestId = request.requestId,
    evidenceId = evidence.evidenceId,
    originalTransactionId = details.original and details.original.transactionId or evidence.transactionRef,
    correctionKey = key,
    confirmation = true,
    itemID = evidence.itemID,
    itemLink = evidence.item,
    awardRef = nil,
  }
  local result = Dibs.ProtectedActions.Execute(details.ledgerAction, actor, payload)
  if not result or result.ok ~= true then return nil, result and (result.reasonCode or result.diagnostic) or "CORRECTION_REJECTED" end
  local transaction = result.value
  if not transaction then return nil, "CORRECTION_REJECTED" end
  state.corrections[key] = transaction.transactionId
  local previous = request.status
  request.status = Disputes.STATUSES.RESOLVED
  request.correctionTransactionId = transaction.transactionId
  request.resolution = {
    action = action,
    actorId = identity(actor) or localIdentity(),
    createdAt = now(),
    reason = reason,
    changedBalance = true,
    transactionId = transaction.transactionId,
  }
  audit(request, action, actor, previous, request.status, reason, {
    affectedTransaction = transaction.transactionId,
    originalTransaction = payload.originalTransactionId,
    correctionKey = key,
  })
  return { ok = true, request = copy(request), transaction = copy(transaction), changedBalance = true }
end

function Disputes.Resolve(requestId, action, options, actor)
  options = type(options) == "table" and options or {}
  actor = actor or options.actor
  local request, reason = requireOfficer(requestId, actor)
  if not request then return nil, reason end
  action = string.lower(trim(action)):gsub("[%s%-]+", "_")
  if request.status == Disputes.STATUSES.RESOLVED or request.status == Disputes.STATUSES.REJECTED then
    if request.correctionTransactionId then
      return nil, "REQUEST_ALREADY_RESOLVED"
    end
    if action ~= Disputes.ACTIONS.REOPEN then return nil, "REQUEST_ALREADY_RESOLVED" end
  end
  if action == Disputes.ACTIONS.CORRECT_BALANCE or action == Disputes.ACTIONS.REFUND
    or action == Disputes.ACTIONS.REVOKE or action == Disputes.ACTIONS.ADJUSTMENT
    or action == Disputes.ACTIONS.HISTORICAL_IMPORT
  then
    return applyCorrection(request, action, actor, options)
  end
  if action == Disputes.ACTIONS.CORRECT_TARGET then
    return applyTargetCorrection(request, action, actor, options)
  end
  if action == Disputes.ACTIONS.NO_CORRECTION then
    local explanation = requireReason(options)
    if not explanation then return nil, "REASON_REQUIRED" end
    return finishWithoutCorrection(request, action, actor, Disputes.STATUSES.RESOLVED, explanation)
  end
  if action == "under_review" then
    local explanation = requireReason(options) or "Officer started review."
    local previous = request.status
    request.status = Disputes.STATUSES.UNDER_REVIEW
    audit(request, action, actor, previous, request.status, explanation)
    return { ok = true, request = copy(request), changedBalance = false }
  end
  if action == Disputes.ACTIONS.ASK_INFORMATION then
    local question = requireReason({ reason = options.question or options.reason })
    if not question then return nil, "QUESTION_REQUIRED" end
    local previous = request.status
    request.status = Disputes.STATUSES.NEED_INFORMATION
    request.question = question
    request.resolution = nil
    audit(request, action, actor, previous, request.status, question)
    return { ok = true, request = copy(request), changedBalance = false }
  end
  if action == Disputes.ACTIONS.DUPLICATE then
    local linked = options.duplicateOf or options.linkedRequestId or options.transactionId
    local explanation = requireReason(options) or "Linked to an existing request or transaction."
    return finishWithoutCorrection(request, action, actor, Disputes.STATUSES.RESOLVED, explanation, { linkedRequestId = linked })
  end
  if action == Disputes.ACTIONS.REJECT then
    local explanation = requireReason(options)
    if not explanation then return nil, "REASON_REQUIRED" end
    return finishWithoutCorrection(request, action, actor, Disputes.STATUSES.REJECTED, explanation)
  end
  if action == Disputes.ACTIONS.REOPEN then
    local explanation = requireReason(options) or "Request reopened for additional review."
    local previous = request.status
    request.status = Disputes.STATUSES.OPEN
    request.resolution = nil
    request.correctionTransactionId = nil
    audit(request, action, actor, previous, request.status, explanation)
    return { ok = true, request = copy(request), changedBalance = false }
  end
  return nil, "UNKNOWN_RESOLUTION_ACTION"
end

function Disputes.BeginReview(requestId, actor)
  return Disputes.Resolve(requestId, "under_review", { reason = "Officer started review." }, actor)
end

function Disputes.AskForInformation(requestId, question, actor)
  return Disputes.Resolve(requestId, Disputes.ACTIONS.ASK_INFORMATION, { question = question }, actor)
end

function Disputes.NoCorrection(requestId, reason, actor)
  return Disputes.Resolve(requestId, Disputes.ACTIONS.NO_CORRECTION, { reason = reason }, actor)
end

function Disputes.CorrectBalance(requestId, options, actor)
  return Disputes.Resolve(requestId, Disputes.ACTIONS.CORRECT_BALANCE, options, actor)
end

function Disputes.CorrectTarget(requestId, options, actor)
  return Disputes.Resolve(requestId, Disputes.ACTIONS.CORRECT_TARGET, options, actor)
end

function Disputes.Reopen(requestId, reason, actor)
  return Disputes.Resolve(requestId, Disputes.ACTIONS.REOPEN, { reason = reason }, actor)
end

function Disputes.BuildSafeView(request)
  request = request or {}
  local evidence = {}
  for _, item in ipairs(request.evidence or {}) do
    table.insert(evidence, {
      evidenceId = item.evidenceId,
      source = item.source,
      itemID = item.itemID,
      item = item.item,
      winner = item.winner and (isLocalIdentity(item.winner) and item.winner or nil) or nil,
      response = item.response,
      status = item.status,
      season = item.season,
      timestamp = item.timestamp,
      confidence = item.confidence,
      unavailableFields = copy(item.unavailableFields),
    })
  end
  local replies = {}
  for _, reply in ipairs(request.replies or {}) do
    table.insert(replies, { replyId = reply.replyId, author = reply.author, boundedText = reply.boundedText, createdAt = reply.createdAt })
  end
  local resolution = request.resolution and {
    action = request.resolution.action,
    reason = request.resolution.reason,
    changedBalance = request.resolution.changedBalance == true,
    createdAt = request.resolution.createdAt,
    targetCorrection = request.resolution.targetCorrection and {
      correctedItemID = request.resolution.targetCorrection.correctedItemID,
      correctedItem = request.resolution.targetCorrection.correctedItem,
      correctedPlayer = isLocalIdentity(request.resolution.targetCorrection.correctedPlayer)
        and request.resolution.targetCorrection.correctedPlayer or nil,
    } or nil,
  } or nil
  return {
    requestId = request.requestId,
    category = request.category,
    categoryLabel = request.categoryLabel,
    status = request.status,
    createdAt = request.createdAt,
    lastUpdatedAt = request.lastUpdatedAt,
    note = request.note,
    attachedContext = copy(request.attachedContext),
    evidence = evidence,
    question = request.question,
    replies = replies,
    resolution = resolution,
  }
end

function Disputes.BuildOfficerView(request)
  request = request or {}
  local result = copy(request)
  result.officerOnly = true
  result.guildScope = request.guildScope
  return result
end

function Disputes.GetTimeline(requestId, actor)
  local request, officer = canReadRequest(requestId, actor)
  if not request then return {}, officer end
  local timeline = {}
  for _, event in ipairs(request.timeline or {}) do
    if officer then
      table.insert(timeline, copy(event))
    else
      table.insert(timeline, {
        eventId = event.eventId,
        action = event.action,
        timestamp = event.timestamp,
        previousStatus = event.previousStatus,
        newStatus = event.newStatus,
        reason = (event.action == "created" or event.action == "player_reply" or event.action == "ask_information") and event.reason or nil,
      })
    end
  end
  return timeline
end

function Disputes.BuildReport(requestId, scope, actor)
  local request, officer = canReadRequest(requestId, actor)
  if not request then return nil, officer end
  scope = scope == "officer" and "officer" or "safe"
  if scope == "officer" and not officer then return nil, "GUILD_ADMIN_REQUIRED" end
  local view = scope == "officer" and Disputes.BuildOfficerView(request) or Disputes.BuildSafeView(request)
  local evidence = view.evidence and view.evidence[1] or {}
  local lines = {
    "Dibs review request " .. tostring(view.requestId),
    "Status: " .. tostring(view.status),
    "Category: " .. tostring(view.categoryLabel or view.category),
    "Created: " .. tostring(view.createdAt),
    "Player: " .. (scope == "officer" and tostring(view.player and view.player.name or "unknown") or "you"),
    "Item: " .. tostring(evidence.item or evidence.itemID or "unavailable"),
    "Source: " .. tostring(evidence.source or "unknown"),
    "Evidence confidence: " .. tostring(evidence.confidence or "unavailable"),
    "Resolution: " .. tostring(view.resolution and view.resolution.reason or "pending"),
  }
  if view.resolution and view.resolution.targetCorrection then
    local target = view.resolution.targetCorrection
    table.insert(lines, "Corrected item: " .. tostring(target.correctedItem or target.correctedItemID or "unchanged"))
    table.insert(lines, "Corrected player: " .. tostring(target.correctedPlayer or "unchanged"))
  end
  if scope == "officer" then
    table.insert(lines, "Timeline events: " .. tostring(#(view.timeline or {})))
  end
  return table.concat(lines, "\n")
end

function Disputes.GetCounts(actor)
  local list, reason = Disputes.ListRequests(actor, {})
  if reason and #list == 0 then return {}, reason end
  local counts = {}
  for _, request in ipairs(list) do counts[request.status] = (counts[request.status] or 0) + 1 end
  return counts
end

function Disputes.IsOfficer(actor)
  return isOfficer(actor)
end
