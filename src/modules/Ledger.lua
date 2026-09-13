--[[
Module: Dibs.Ledger
Layer: Domain / append-only store
Purpose: Provide the single local command boundary for durable ledger mutation.
Responsibilities: Validate, canonicalize, append, and project local ledger transactions.
Non-responsibilities: Network replication, coordinator activation, epochs, and RCLootCouncil authority.
Dependencies: Identity, Permissions, Seasons.
SavedVariables: db.ledger.transactions, playerStates, awardTransactions, evidenceTransactions.

B03 boundary: every newly created transaction is LOCAL_CANONICAL and is
constructed detached, validated, hashed, replay-checked, then appended. Old
records stay LEGACY by absence of a classification; they are never rewritten.
]]

local Dibs = _G.Dibs
Dibs.Ledger = Dibs.Ledger or {}
local Ledger = Dibs.Ledger

local SCHEMA = 3
local CLASSIFICATION = "LOCAL_CANONICAL"
local VALID_ACTION_TYPES = {
  SEASON_ALLOCATION = true, DIB_GRANTED = true, DIB_USED = true,
  DIB_REFUNDED = true, DIB_REVOKED = true, DIB_ADMIN_ADJUSTMENT = true,
}

local ACTION_BY_PROTECTED_ACTION = {
  ["ledger.grant"] = "DIB_GRANTED", ["ledger.use"] = "DIB_USED",
  ["ledger.refund"] = "DIB_REFUNDED", ["ledger.adjust"] = "DIB_ADMIN_ADJUSTMENT",
}
local PROTECTED_ACTION_BY_TYPE = {
  DIB_GRANTED = "ledger.grant", DIB_USED = "ledger.use", DIB_REFUNDED = "ledger.refund",
  DIB_REVOKED = "ledger.adjust", DIB_ADMIN_ADJUSTMENT = "ledger.adjust", SEASON_ALLOCATION = "ledger.adjust",
}

local function copy(value) return Dibs.DeepCopy and Dibs.DeepCopy(value) or value end

local function ensureState()
  Dibs.db = Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
  Dibs.db.ledger = Dibs.db.ledger or { transactions = {}, playerStates = {} }
  local ledger = Dibs.db.ledger
  ledger.transactions = ledger.transactions or {}; ledger.playerStates = ledger.playerStates or {}
  ledger.awardTransactions = ledger.awardTransactions or {}; ledger.evidenceTransactions = ledger.evidenceTransactions or {}
  return ledger
end

local function trim(value)
  if type(value) ~= "string" then return nil end
  value = value:match("^%s*(.-)%s*$")
  return value ~= "" and value or nil
end

local function finiteNumber(value)
  local number = tonumber(value)
  return number ~= nil and number == number and math.abs(number) < math.huge
end

local function finiteInteger(value) return finiteNumber(value) and tonumber(value) == math.floor(tonumber(value)) end
local function normalizeLegacyPlayerKey(playerName) return string.lower(trim(tostring(playerName or "")) or "") end

local function ensurePlayerState(playerKey, seasonId)
  local ledger = ensureState()
  ledger.playerStates[seasonId] = ledger.playerStates[seasonId] or {}
  ledger.playerStates[seasonId][playerKey] = ledger.playerStates[seasonId][playerKey] or { allocation = 0, balance = 0, transactions = {} }
  return ledger.playerStates[seasonId][playerKey]
end

local function actionAmountIsValid(actionType, amount)
  if actionType == "DIB_GRANTED" or actionType == "DIB_REFUNDED" or actionType == "SEASON_ALLOCATION" then return amount > 0 end
  if actionType == "DIB_USED" or actionType == "DIB_REVOKED" then return amount < 0 end
  return actionType == "DIB_ADMIN_ADJUSTMENT" and amount ~= 0
end

-- Type-tagged and key-sorted serialization is independent from B00's test-only
-- contract hash. It is deterministic content identity, not client authentication.
local function canonicalSerialize(value, seen)
  local kind = type(value)
  if kind == "nil" then return "z" end
  if kind == "boolean" then return value and "b1" or "b0" end
  if kind == "number" then
    if not finiteNumber(value) then return nil, "NON_FINITE_CANONICAL_VALUE" end
    if value == 0 then value = 0 end
    return "n" .. string.format("%.17g", value)
  end
  if kind == "string" then return "s" .. tostring(#value) .. ":" .. value end
  if kind ~= "table" then return nil, "UNSUPPORTED_CANONICAL_VALUE" end
  seen = seen or {}
  if seen[value] then return nil, "CYCLIC_CANONICAL_VALUE" end
  seen[value] = true
  local entries = {}
  for key, item in pairs(value) do
    local encodedKey, keyReason = canonicalSerialize(key, seen)
    local encodedValue, valueReason = canonicalSerialize(item, seen)
    if not encodedKey or not encodedValue then seen[value] = nil; return nil, keyReason or valueReason end
    table.insert(entries, encodedKey .. "=" .. encodedValue)
  end
  seen[value] = nil; table.sort(entries)
  return "t{" .. table.concat(entries, ",") .. "}"
end

-- Stable 31-bit polynomial hash. Each intermediate is representable exactly by
-- Lua's number type. This non-cryptographic hash detects differing content only.
local function contentHash(serialized)
  local hash = 0
  for index = 1, #serialized do hash = (hash * 131 + serialized:byte(index)) % 2147483647 end
  return string.format("D3-%08x", hash)
end

local function canonicalSnapshot(snapshot)
  return { memberKey = snapshot.memberKey, displayName = snapshot.displayName, guidWitness = snapshot.guidWitness }
end

local function canonicalContent(tx)
  return {
    schema = SCHEMA, recordClass = "LEDGER_TRANSACTION", classification = CLASSIFICATION,
    transactionId = tx.transactionId, actionType = tx.actionType, memberKey = tx.memberKey,
    identitySnapshot = canonicalSnapshot(tx.identitySnapshot), seasonId = tx.seasonId,
    amount = tx.amount, reason = tx.reason, source = tx.source,
    evidence = { evidenceId = tx.evidenceId, awardRef = tx.awardRef, itemID = tx.itemID, itemLink = tx.itemLink, sourceStatus = tx.sourceStatus, response = tx.response, reviewRequestId = tx.reviewRequestId, originalTransactionId = tx.originalTransactionId, correctionKey = tx.correctionKey, confirmation = tx.confirmation },
    actor = { actorId = tx.actorId, identitySnapshot = canonicalSnapshot(tx.actorSnapshot), authority = tx.context and tx.context.authority, action = tx.context and tx.context.action },
    debtPolicy = tx.debtPolicy,
  }
end

local function transactionCanonicalHash(tx)
  local serialized, reason = canonicalSerialize(canonicalContent(tx))
  if not serialized then return nil, reason end
  return contentHash(serialized), serialized
end

local function sameCanonicalContent(existing, candidate)
  return existing.classification == CLASSIFICATION and type(existing.canonicalContentHash) == "string"
    and existing.canonicalContentHash == candidate.canonicalContentHash
end

local function getCurrentBalance(memberKey, seasonId)
  local ledger = ensureState(); local state = ledger.playerStates[seasonId] and ledger.playerStates[seasonId][memberKey]
  if not state then return 0 end
  local balance = tonumber(state.allocation) or 0
  for _, transactionId in ipairs(state.transactions or {}) do
    local tx = ledger.transactions[transactionId]
    if tx and tx.type ~= "SEASON_ALLOCATION" then balance = balance + (tonumber(tx.amount) or 0) end
  end
  return balance
end

local function validateSeason(seasonId)
  if type(seasonId) ~= "string" or seasonId == "" then return false, "MISSING_SEASON_ID" end
  if not Dibs.Seasons or not Dibs.Seasons.GetById or not Dibs.Seasons.GetById(seasonId) then return false, "SEASON_NOT_FOUND" end
  return true
end

local function createMemberSnapshot(value)
  if not Dibs.Identity or type(Dibs.Identity.CreateSnapshot) ~= "function" then return nil, "IDENTITY_UNAVAILABLE" end
  local snapshot, reason = Dibs.Identity.CreateSnapshot(value)
  if not snapshot then return nil, reason or "INVALID_IDENTITY" end
  if type(snapshot.memberKey) ~= "string" or type(snapshot.displayName) ~= "string" then return nil, "INVALID_IDENTITY_SNAPSHOT" end
  return snapshot
end

local function authorize(context, actionType)
  context = context or {}
  if context.systemBootstrap == true then
    if actionType ~= "SEASON_ALLOCATION" then return nil, "BOOTSTRAP_ACTION_FORBIDDEN" end
    local actorSnapshot, snapshotReason = createMemberSnapshot(Dibs.GetPlayerName())
    if not actorSnapshot then return nil, snapshotReason end
    return { actorId = actorSnapshot.memberKey, actorSnapshot = actorSnapshot, authority = "local-bootstrap", action = "season.bootstrap", reasonCode = "SYSTEM_BOOTSTRAP" }
  end
  local protectedAction = context.action or ACTION_BY_PROTECTED_ACTION[context.protectedAction]
  if not protectedAction then
    if actionType == "DIB_GRANTED" then protectedAction = "ledger.grant"
    elseif actionType == "DIB_USED" then protectedAction = "ledger.use"
    elseif actionType == "DIB_REFUNDED" then protectedAction = "ledger.refund" else protectedAction = "ledger.adjust" end
  end
  if not Dibs.Permissions or type(Dibs.Permissions.Evaluate) ~= "function" then return nil, "AUTHORITY_UNAVAILABLE" end
  local actor = context.actor or Dibs.GetPlayerName()
  local decision = Dibs.Permissions.Evaluate(protectedAction, actor)
  if not decision or decision.allowed ~= true then return nil, decision and decision.reasonCode or "AUTHORITY_UNAVAILABLE" end
  local actorSnapshot, snapshotReason = createMemberSnapshot(actor)
  if not actorSnapshot then return nil, snapshotReason end
  return { actorId = decision.actorId or actorSnapshot.memberKey, actorSnapshot = actorSnapshot, authority = decision.authority, action = protectedAction, reasonCode = decision.reasonCode }
end

local function explicitDebtPolicy(context)
  local requested = context and context.debtPolicy
  if requested == nil and context and context.allowDebt == true then requested = { allowDebt = true, source = "LOCAL_EXPLICIT" } end
  if requested == nil then return { allowDebt = false, source = "DEFAULT_LOCAL" } end
  if type(requested) ~= "table" or requested.allowDebt ~= true then return nil, "INVALID_DEBT_POLICY" end
  local source = trim(requested.source)
  if not source then return nil, "INVALID_DEBT_POLICY" end
  return { allowDebt = true, source = source }
end

local function buildDetachedTransaction(context, input)
  input = input or {}; local actionType = input.actionType or input.type
  if type(actionType) ~= "string" or not VALID_ACTION_TYPES[actionType] then return nil, "INVALID_ACTION_TYPE" end
  local transactionId = trim(input.transactionId) or Dibs.NewId("tx")
  if #transactionId > 160 then return nil, "INVALID_TRANSACTION_ID" end
  local seasonId = input.seasonId or Dibs.GetCurrentSeasonId(); local seasonOK, seasonReason = validateSeason(seasonId)
  if not seasonOK then return nil, seasonReason end
  local amount = tonumber(input.quantityDelta or input.amount)
  if not finiteInteger(amount) or amount == 0 or math.abs(amount) > 100000 then return nil, "INVALID_AMOUNT" end
  if not actionAmountIsValid(actionType, amount) then return nil, "INVALID_QUANTITY_SIGN" end
  local snapshot, identityReason = createMemberSnapshot({ nameRealm = input.playerName or input.memberKey or input.playerKey, guidWitness = input.guidWitness or input.playerGuid })
  if not snapshot then return nil, identityReason end
  local authorization, authorizationReason = authorize(context, actionType)
  if not authorization then return nil, authorizationReason end
  if context and context.systemBootstrap == true and snapshot.memberKey ~= authorization.actorSnapshot.memberKey then
    return nil, "BOOTSTRAP_TARGET_MISMATCH"
  end
  local debtPolicy, debtReason = explicitDebtPolicy(context); if not debtPolicy then return nil, debtReason end
  local reason = trim(input.reason) or "No reason provided"
  local timestamp = tonumber(input.timestamp or input.createdAt) or (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time()
  if not finiteNumber(timestamp) then return nil, "MISSING_TIMESTAMP" end
  local tx = {
    schema = SCHEMA, recordClass = "LEDGER_TRANSACTION", classification = CLASSIFICATION,
    transactionId = transactionId, type = actionType, actionType = actionType, action = actionType,
    memberKey = snapshot.memberKey, playerKey = snapshot.memberKey, playerName = snapshot.displayName,
    identitySnapshot = copy(snapshot), playerGuid = snapshot.guidWitness, guidWitness = snapshot.guidWitness,
    seasonId = seasonId, amount = amount, quantityDelta = amount, reason = reason, source = trim(input.source) or "local",
    evidenceId = trim(input.evidenceId), awardRef = trim(input.awardRef), itemID = input.itemID, itemLink = input.itemLink,
    sourceStatus = input.sourceStatus, response = input.response, reviewRequestId = input.reviewRequestId,
    originalTransactionId = input.originalTransactionId, correctionKey = input.correctionKey,
    confirmation = input.confirmation == true or nil, createdAt = timestamp, timestamp = timestamp,
    actorId = authorization.actorId, actorSnapshot = copy(authorization.actorSnapshot),
    context = { authority = authorization.authority, action = authorization.action, authorization = authorization.reasonCode }, debtPolicy = debtPolicy,
  }
  local hash, hashReason = transactionCanonicalHash(tx); if not hash then return nil, hashReason end
  tx.canonicalContentHash = hash
  return tx
end

local function appendValidated(tx)
  local ledger = ensureState(); ledger.transactions[tx.transactionId] = tx
  if tx.awardRef then ledger.awardTransactions[tx.awardRef] = tx.transactionId end
  if tx.evidenceId then ledger.evidenceTransactions[tx.evidenceId] = tx.transactionId end
  local state = ensurePlayerState(tx.memberKey, tx.seasonId); table.insert(state.transactions, tx.transactionId)
  if tx.type == "SEASON_ALLOCATION" then state.allocation = (tonumber(state.allocation) or 0) + tx.amount end
  state.balance = getCurrentBalance(tx.memberKey, tx.seasonId)
  return tx
end

---@param context table Local caller context; it never represents a coordinator or epoch.
---@param record table Candidate transaction fields.
---@return table result `{accepted, idempotentReplay, value?, reasonCode?}`.
function Ledger.CommitLocalTransaction(context, record)
  local ledger = ensureState(); local input = record or {}; local inputId = trim(input.transactionId)
  local existing = inputId and ledger.transactions[inputId] or nil
  local tx, reason = buildDetachedTransaction(context or {}, input)
  if not tx then return { accepted = false, idempotentReplay = false, reasonCode = reason } end
  -- B05b fences local consumption while coordinator authority is unavailable,
  -- closing, or recovering. This is deliberately not a B06 distributed commit.
  if tx.type == "DIB_USED" and Dibs.Governance and Dibs.Governance.GetDibUseGate then
    local allowed, gateReason = Dibs.Governance.GetDibUseGate()
    if not allowed then
      local proposal = Dibs.Governance.RecordAwardProposal and Dibs.Governance.RecordAwardProposal(
        context and context.actor or Dibs.GetPlayerName(), input)
      return { accepted = false, idempotentReplay = false, reasonCode = gateReason, proposal = proposal }
    end
  end
  if existing then
    if sameCanonicalContent(existing, tx) then return { accepted = true, idempotentReplay = true, reasonCode = "IDEMPOTENT_REPLAY", value = copy(existing) } end
    return { accepted = false, idempotentReplay = false, reasonCode = "TRANSACTION_CONFLICT" }
  end
  if tx.type == "SEASON_ALLOCATION" and context and context.systemBootstrap == true then
    local state = ledger.playerStates[tx.seasonId] and ledger.playerStates[tx.seasonId][tx.memberKey]
    if state and (tonumber(state.allocation) or 0) ~= 0 then
      return { accepted = false, idempotentReplay = false, reasonCode = "SEASON_ALLOCATION_EXISTS" }
    end
  end
  if tx.type == "DIB_USED" and tx.debtPolicy.allowDebt ~= true and getCurrentBalance(tx.memberKey, tx.seasonId) + tx.amount < 0 then
    return { accepted = false, idempotentReplay = false, reasonCode = "INSUFFICIENT_BALANCE" }
  end
  return { accepted = true, idempotentReplay = false, reasonCode = "COMMITTED_LOCAL", value = copy(appendValidated(tx)) }
end

-- B03 equivalent of the future coordinator command. Explicitly local-only: no
-- coordinator, epoch, sequence, previous hash, or transport is accepted here.
function Ledger.CommitDibUse(context, awardEvidence)
  local evidence = copy(awardEvidence or {}); evidence.type, evidence.actionType = "DIB_USED", "DIB_USED"
  evidence.amount = -math.abs(tonumber(evidence.amount) or 1)
  return Ledger.CommitLocalTransaction(context, evidence)
end

-- Compatibility validation for imported/legacy records; it never upgrades them.
function Ledger.ValidateTransaction(record)
  local tx = record or {}
  if type(tx.transactionId) ~= "string" or tx.transactionId == "" then return false, "MISSING_TRANSACTION_ID" end
  if not finiteNumber(tx.timestamp or tx.createdAt) then return false, "MISSING_TIMESTAMP" end
  local seasonOK, seasonReason = validateSeason(tx.seasonId); if not seasonOK then return false, seasonReason end
  if type(tx.playerName) ~= "string" or tx.playerName == "" then return false, "MISSING_PLAYER_IDENTITY" end
  local actionType = tx.actionType or tx.type; if type(actionType) ~= "string" or not VALID_ACTION_TYPES[actionType] then return false, "INVALID_ACTION_TYPE" end
  local amount = tonumber(tx.quantityDelta or tx.amount)
  if not finiteNumber(amount) or amount == 0 then return false, "MISSING_QUANTITY_DELTA" end
  if not actionAmountIsValid(actionType, amount) then return false, "INVALID_QUANTITY_SIGN" end
  if math.abs(amount) > 100000 then return false, "QUANTITY_OUT_OF_RANGE" end
  return true
end

local function compatibilityContext(action, audit)
  return { action = audit and audit.action or PROTECTED_ACTION_BY_TYPE[action], actor = audit and (audit.actorName or audit.actor) or nil, debtPolicy = audit and audit.debtPolicy }
end

-- Deprecated compatibility facades. Each reaches the sole durable mutation command.
function Ledger.AppendTransaction(record, context) return Ledger.CommitLocalTransaction(context or compatibilityContext(nil, record), record) end
function Ledger.AddTransaction(record)
  local result = Ledger.CommitLocalTransaction(compatibilityContext(nil, record), record)
  return result.value, result.reasonCode
end

local function compatibilityMutation(action, playerName, amount, reason, source, seasonId, audit)
  local result = Ledger.CommitLocalTransaction(compatibilityContext(action, audit), {
    transactionId = audit and audit.transactionId, playerName = playerName or Dibs.GetPlayerName(), amount = amount, type = action,
    reason = reason, source = source, seasonId = seasonId, awardRef = audit and audit.awardRef, evidenceId = audit and audit.evidenceId,
    itemID = audit and audit.itemID, itemLink = audit and audit.itemLink, sourceStatus = audit and audit.sourceStatus,
    response = audit and audit.response, playerGuid = audit and audit.playerGuid, reviewRequestId = audit and audit.reviewRequestId,
    originalTransactionId = audit and audit.originalTransactionId, correctionKey = audit and audit.correctionKey,
    confirmation = audit and audit.confirmation,
  })
  return result.value, result.reasonCode
end

function Ledger.Grant(playerName, amount, reason, source, seasonId, audit)
  local numeric = amount == nil and 1 or tonumber(amount); if not finiteInteger(numeric) or numeric <= 0 then return nil, "INVALID_AMOUNT" end
  return compatibilityMutation("DIB_GRANTED", playerName, numeric, reason or "Dib granted", source or "system", seasonId or Dibs.GetCurrentSeasonId(), audit)
end
function Ledger.Use(playerName, amount, reason, source, seasonId, audit)
  local numeric = amount == nil and 1 or tonumber(amount); if not finiteInteger(numeric) or numeric <= 0 then return nil, "INVALID_AMOUNT" end
  return compatibilityMutation("DIB_USED", playerName, -numeric, reason or "Dib consumed", source or "system", seasonId or Dibs.GetCurrentSeasonId(), audit)
end
function Ledger.Refund(playerName, amount, reason, source, seasonId, audit)
  local numeric = amount == nil and 1 or tonumber(amount); if not finiteInteger(numeric) or numeric <= 0 then return nil, "INVALID_AMOUNT" end
  return compatibilityMutation("DIB_REFUNDED", playerName, numeric, reason or "Dib refunded", source or "system", seasonId or Dibs.GetCurrentSeasonId(), audit)
end
function Ledger.AdminAdjust(playerName, amount, reason, source, seasonId, audit)
  local numeric = tonumber(amount); if not finiteInteger(numeric) or numeric == 0 then return nil, "INVALID_AMOUNT" end
  return compatibilityMutation("DIB_ADMIN_ADJUSTMENT", playerName, numeric, reason or "Manual adjustment", source or "officer", seasonId or Dibs.GetCurrentSeasonId(), audit)
end
function Ledger.RecordHistoricalAward(playerName, seasonId, awardRef, evidenceId, reason, audit)
  audit = copy(audit or {}); audit.awardRef, audit.evidenceId = awardRef, evidenceId
  return Ledger.Use(playerName, 1, reason or "Historical RCLootCouncil award", "rclootcouncil_history", seasonId, audit)
end
function Ledger.RegisterSeasonAllocation(playerName, seasonId, amount, reason)
  local numeric = amount == nil and 1 or tonumber(amount); if not finiteInteger(numeric) or numeric <= 0 then return nil, "INVALID_AMOUNT" end
  local result = Ledger.CommitLocalTransaction({ systemBootstrap = true }, {
    playerName = playerName or Dibs.GetPlayerName(), amount = numeric, type = "SEASON_ALLOCATION",
    reason = reason or "Season allocation", source = "system", seasonId = seasonId or Dibs.GetCurrentSeasonId(),
  })
  return result.value, result.reasonCode
end

function Ledger.GetBalance(playerName, seasonId)
  local memberKey = Dibs.Identity and Dibs.Identity.CanonicalMemberKey and Dibs.Identity.CanonicalMemberKey(playerName) or nil
  return getCurrentBalance(memberKey or normalizeLegacyPlayerKey(playerName or Dibs.GetPlayerName()), seasonId or Dibs.GetCurrentSeasonId())
end
function Ledger.GetPlayerState(playerName, seasonId)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local memberKey = Dibs.Identity and Dibs.Identity.CanonicalMemberKey and Dibs.Identity.CanonicalMemberKey(playerName) or nil
  memberKey = memberKey or normalizeLegacyPlayerKey(playerName or Dibs.GetPlayerName())
  local ledger = ensureState(); local state = ledger.playerStates[targetSeason] and ledger.playerStates[targetSeason][memberKey]
  if not state then return { allocation = 0, balance = 0, transactions = {} } end
  local result = copy(state); result.balance = getCurrentBalance(memberKey, targetSeason); return result
end
function Ledger.GetTransactionForAward(awardRef)
  local ledger = ensureState(); local id = awardRef and ledger.awardTransactions[tostring(awardRef)]
  return id and copy(ledger.transactions[id]) or nil
end
function Ledger.GetTransactionForEvidence(evidenceId)
  local ledger = ensureState(); local id = evidenceId and ledger.evidenceTransactions[tostring(evidenceId)]
  return id and copy(ledger.transactions[id]) or nil
end
local function sortTransactions(list)
  table.sort(list, function(a, b)
    local first, second = a.createdAt or a.timestamp or 0, b.createdAt or b.timestamp or 0
    return first == second and tostring(a.transactionId) < tostring(b.transactionId) or first < second
  end)
end
function Ledger.GetHistory(playerName, seasonId)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local memberKey = Dibs.Identity and Dibs.Identity.CanonicalMemberKey and Dibs.Identity.CanonicalMemberKey(playerName) or nil
  memberKey = memberKey or normalizeLegacyPlayerKey(playerName); local ledger = ensureState(); local state = ledger.playerStates[targetSeason] and ledger.playerStates[targetSeason][memberKey]
  local history = {}; for _, id in ipairs(state and state.transactions or {}) do if ledger.transactions[id] then table.insert(history, copy(ledger.transactions[id])) end end
  sortTransactions(history); return history
end
function Ledger.GetAllTransactions()
  local list = {}; for _, tx in pairs(ensureState().transactions) do table.insert(list, copy(tx)) end; sortTransactions(list); return list
end
function Ledger.GetTransactions(seasonId, playerGuidOrName)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local memberKey = playerGuidOrName and (Dibs.Identity and Dibs.Identity.CanonicalMemberKey and Dibs.Identity.CanonicalMemberKey(playerGuidOrName) or normalizeLegacyPlayerKey(playerGuidOrName)) or nil
  local list = {}
  for _, tx in pairs(ensureState().transactions) do
    local matchesPlayer = not memberKey or tx.memberKey == memberKey or tx.playerKey == memberKey or normalizeLegacyPlayerKey(tx.playerName) == memberKey or tostring(tx.playerGuid or tx.playerId or "") == tostring(playerGuidOrName or "")
    if tx.seasonId == targetSeason and matchesPlayer then table.insert(list, copy(tx)) end
  end
  sortTransactions(list); return list
end
function Ledger.GetPlayerSeasonState(seasonId, playerGuidOrName)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId(); local playerName = playerGuidOrName or Dibs.GetPlayerName(); local transactions = Ledger.GetTransactions(targetSeason, playerName)
  if type(playerName) == "string" and playerName:match("^Player%-%d+%-") and transactions[1] and transactions[1].playerName then
    playerName = transactions[1].playerName
  end
  local delta = 0; for _, tx in ipairs(transactions) do if tx.type ~= "SEASON_ALLOCATION" then delta = delta + (tonumber(tx.amount) or 0) end end
  local state = Ledger.GetPlayerState(playerName, targetSeason)
  return { seasonId = targetSeason, playerGuid = tostring(playerGuidOrName or state.playerId or playerName), playerName = playerName, currentRankIndex = 0, baseAllocation = tonumber(state.allocation) or 0, transactionDelta = delta, remainingBalance = Ledger.GetBalance(playerName, targetSeason), historySummary = { count = #transactions }, lastComputedAt = time() }
end
function Ledger.CalculateCanonicalContentHash(record) return transactionCanonicalHash(record or {}) end

return Ledger
