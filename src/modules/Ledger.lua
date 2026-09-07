local Dibs = _G.Dibs
Dibs.Ledger = Dibs.Ledger or {}

local VALID_ACTION_TYPES = {
  SEASON_ALLOCATION = true,
  DIB_GRANTED = true,
  DIB_USED = true,
  DIB_REFUNDED = true,
  DIB_REVOKED = true,
  DIB_ADMIN_ADJUSTMENT = true,
}

local function ensureState()
  Dibs.db = Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
  Dibs.db.ledger = Dibs.db.ledger or { transactions = {}, playerStates = {} }
  Dibs.db.ledger.transactions = Dibs.db.ledger.transactions or {}
  Dibs.db.ledger.playerStates = Dibs.db.ledger.playerStates or {}
  Dibs.db.ledger.awardTransactions = Dibs.db.ledger.awardTransactions or {}
end

local function getRosterPlayerName(playerName)
  local candidate = tostring(playerName or ""):match("^%s*(.-)%s*$")
  if candidate == "" or type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
    return candidate
  end

  local memberCount = GetNumGuildMembers()
  local count = tonumber(memberCount) or 0
  local candidateKey = string.lower(candidate)
  local candidateShortName = candidateKey:match("^([^-]+)")
  local shortMatches = {}
  for index = 1, count do
    local rosterName = GetGuildRosterInfo(index)
    if rosterName and rosterName ~= "" then
      local rosterKey = string.lower(tostring(rosterName))
      local rosterShortName = rosterKey:match("^([^-]+)")
      if rosterKey == candidateKey then
        return tostring(rosterName)
      end
      if not candidate:find("-", 1, true) and candidateShortName and rosterShortName == candidateShortName then
        table.insert(shortMatches, tostring(rosterName))
      end
    end
  end

  if #shortMatches == 1 then return shortMatches[1] end

  return candidate
end

local function normalizePlayerKey(playerName)
  return string.lower(getRosterPlayerName(playerName or Dibs.GetPlayerName()))
end

local function finiteNumber(value)
  local number = tonumber(value)
  return number ~= nil and number == number and math.abs(number) < math.huge and number ~= math.huge and number ~= -math.huge
end

local function ensurePlayerState(playerKey, seasonId)
  ensureState()
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  Dibs.db.ledger.playerStates[targetSeason] = Dibs.db.ledger.playerStates[targetSeason] or {}
  Dibs.db.ledger.playerStates[targetSeason][playerKey] = Dibs.db.ledger.playerStates[targetSeason][playerKey] or {
    allocation = 0,
    balance = 0,
    transactions = {},
  }
  return Dibs.db.ledger.playerStates[targetSeason][playerKey]
end

function Dibs.Ledger.GetPlayerState(playerName, seasonId)
  ensureState()
  local playerKey = normalizePlayerKey(playerName)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local state = Dibs.db.ledger.playerStates[targetSeason] and Dibs.db.ledger.playerStates[targetSeason][playerKey]
  if not state then
    return { allocation = 0, balance = 0, transactions = {} }
  end

  state.balance = Dibs.Ledger.GetBalance(playerName, targetSeason)
  return state
end

function Dibs.Ledger.GetBalance(playerName, seasonId)
  ensureState()
  local playerKey = normalizePlayerKey(playerName)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local state = Dibs.db.ledger.playerStates[targetSeason] and Dibs.db.ledger.playerStates[targetSeason][playerKey]
  if not state then
    return 0
  end

  local balance = tonumber(state.allocation) or 0
  for _, txId in ipairs(state.transactions) do
    local tx = Dibs.db.ledger.transactions[txId]
    if tx and tx.type ~= "SEASON_ALLOCATION" then
      balance = balance + (tonumber(tx.amount) or 0)
    end
  end

  state.balance = balance
  return balance
end

function Dibs.Ledger.AddTransaction(record)
  ensureState()

  local tx = record or {}
  tx.transactionId = tx.transactionId or Dibs.NewId("tx")
  if Dibs.db.ledger.transactions[tx.transactionId] then
    Dibs.db.ledger.transactions[tx.transactionId].idempotentReplay = true
    return Dibs.db.ledger.transactions[tx.transactionId]
  end

  tx.type = tx.type or "DIB_ADMIN_ADJUSTMENT"
  tx.playerName = getRosterPlayerName(tx.playerName or tx.playerKey or Dibs.GetPlayerName())
  tx.playerKey = normalizePlayerKey(tx.playerName)
  tx.playerId = tx.playerId or (Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId(tx.playerName)) or tx.playerKey
  tx.seasonId = tx.seasonId or Dibs.GetCurrentSeasonId()
  tx.amount = tonumber(tx.amount) or 0
  tx.createdAt = tx.createdAt or time()
  tx.timestamp = tx.timestamp or tx.createdAt
  tx.reason = tx.reason or "No reason provided"
  tx.action = tx.action or tx.type
  tx.actorId = tx.actorId or tx.systemOrigin or "system:legacy"
  tx.playerRank = tx.playerRank ~= nil and tx.playerRank or ((Dibs.RankRules and Dibs.RankRules.GetPlayerRankInfo(tx.playerName or tx.playerKey).rankIndex) or 0)
  tx.playerRankIndex = tx.playerRankIndex ~= nil and tx.playerRankIndex or tx.playerRank
  local valid, reasonCode = Dibs.Ledger.ValidateTransaction(tx)
  if not valid then
    return nil, reasonCode
  end

  if tx.awardRef then
    local existingId = Dibs.db.ledger.awardTransactions[tostring(tx.awardRef)]
    if existingId then return Dibs.db.ledger.transactions[existingId] end
  end

  Dibs.db.ledger.transactions[tx.transactionId] = tx
  if tx.awardRef then
    local ref = tostring(tx.awardRef)
    Dibs.db.ledger.awardTransactions[ref] = tx.transactionId
  end

  local state = ensurePlayerState(tx.playerKey, tx.seasonId)
  table.insert(state.transactions, tx.transactionId)

  if tx.type == "SEASON_ALLOCATION" then
    state.allocation = (tonumber(state.allocation) or 0) + (tonumber(tx.amount) or 0)
  end

  state.balance = Dibs.Ledger.GetBalance(tx.playerName or tx.playerKey, tx.seasonId)
  return tx
end

function Dibs.Ledger.ValidateTransaction(record)
  ensureState()
  local tx = record or {}
  if type(tx.transactionId) ~= "string" or tx.transactionId == "" then
    return false, "MISSING_TRANSACTION_ID"
  end
  if not finiteNumber(tx.timestamp or tx.createdAt) then
    return false, "MISSING_TIMESTAMP"
  end
  if type(tx.seasonId) ~= "string" or tx.seasonId == "" then
    return false, "MISSING_SEASON_ID"
  end
  if not Dibs.Seasons or not Dibs.Seasons.GetById or not Dibs.Seasons.GetById(tx.seasonId) then
    return false, "SEASON_NOT_FOUND"
  end

  local hasGuid = type(tx.playerGuid) == "string" and tx.playerGuid ~= ""
  local hasPlayer = type(tx.playerName) == "string" and tx.playerName ~= ""
  if not hasGuid and not hasPlayer then
    return false, "MISSING_PLAYER_IDENTITY"
  end

  local actionType = tx.actionType or tx.type
  if type(actionType) ~= "string" or not VALID_ACTION_TYPES[actionType] then
    return false, "INVALID_ACTION_TYPE"
  end
  local amount = tonumber(tx.quantityDelta or tx.amount)
  if not finiteNumber(amount) or amount == 0 then
    return false, "MISSING_QUANTITY_DELTA"
  end
  if actionType == "DIB_ADMIN_ADJUSTMENT" and (type(tx.reason) ~= "string" or tx.reason == "") then
    return false, "MISSING_REASON"
  end

  if actionType == "DIB_GRANTED" or actionType == "DIB_REFUNDED" or actionType == "SEASON_ALLOCATION" then
    if amount <= 0 then return false, "INVALID_QUANTITY_SIGN" end
  elseif actionType == "DIB_USED" then
    if amount >= 0 then return false, "INVALID_QUANTITY_SIGN" end
  end

  if math.abs(amount) > 100000 then
    return false, "QUANTITY_OUT_OF_RANGE"
  end
  return true, nil
end

function Dibs.Ledger.AppendTransaction(record)
  ensureState()
  local tx = record or {}
  local existing = tx.transactionId and Dibs.db.ledger.transactions[tx.transactionId] or nil
  if existing then
    existing.idempotentReplay = true
    return { accepted = true, idempotentReplay = true, value = existing }
  end

  local ok, reasonCode = Dibs.Ledger.ValidateTransaction(tx)
  if not ok then
    return { accepted = false, idempotentReplay = false, reasonCode = reasonCode }
  end

  tx.type = tx.type or tx.actionType
  tx.amount = tx.amount or tx.quantityDelta
  tx.createdAt = tx.createdAt or tx.timestamp
  tx.playerName = tx.playerName or tx.playerGuid
  tx.playerGuid = tx.playerGuid or tx.playerId

  local appended = Dibs.Ledger.AddTransaction(tx)
  appended.idempotentReplay = false
  return { accepted = appended ~= nil, idempotentReplay = false, value = appended }
end

local function mergeAudit(record, audit)
  for key, value in pairs(audit or {}) do record[key] = value end
  return record
end

function Dibs.Ledger.Grant(playerName, amount, reason, source, seasonId, audit)
  local numericAmount = amount == nil and 1 or tonumber(amount)
  if not finiteNumber(numericAmount) or numericAmount <= 0 then return nil, "INVALID_AMOUNT" end
  return Dibs.Ledger.AddTransaction(mergeAudit({
    playerName = playerName or Dibs.GetPlayerName(),
    amount = numericAmount,
    type = "DIB_GRANTED",
    reason = reason or "Dib granted",
    source = source or "system",
    seasonId = seasonId or Dibs.GetCurrentSeasonId(),
  }, audit))
end

function Dibs.Ledger.Use(playerName, amount, reason, source, seasonId, audit)
  local numericAmount = amount == nil and 1 or tonumber(amount)
  if not finiteNumber(numericAmount) or numericAmount <= 0 then return nil, "INVALID_AMOUNT" end
  return Dibs.Ledger.AddTransaction(mergeAudit({
    playerName = playerName or Dibs.GetPlayerName(),
    amount = -numericAmount,
    type = "DIB_USED",
    reason = reason or "Dib consumed",
    source = source or "system",
    seasonId = seasonId or Dibs.GetCurrentSeasonId(),
  }, audit))
end

function Dibs.Ledger.Refund(playerName, amount, reason, source, seasonId, audit)
  local numericAmount = amount == nil and 1 or tonumber(amount)
  if not finiteNumber(numericAmount) or numericAmount <= 0 then return nil, "INVALID_AMOUNT" end
  return Dibs.Ledger.AddTransaction(mergeAudit({
    playerName = playerName or Dibs.GetPlayerName(),
    amount = numericAmount,
    type = "DIB_REFUNDED",
    reason = reason or "Dib refunded",
    source = source or "system",
    seasonId = seasonId or Dibs.GetCurrentSeasonId(),
  }, audit))
end

function Dibs.Ledger.AdminAdjust(playerName, amount, reason, source, seasonId, audit)
  local numericAmount = tonumber(amount)
  if not finiteNumber(numericAmount) or numericAmount == 0 then return nil, "INVALID_AMOUNT" end
  return Dibs.Ledger.AddTransaction(mergeAudit({
    playerName = playerName or Dibs.GetPlayerName(),
    amount = numericAmount,
    type = "DIB_ADMIN_ADJUSTMENT",
    reason = reason or "Manual adjustment",
    source = source or "officer",
    seasonId = seasonId or Dibs.GetCurrentSeasonId(),
  }, audit))
end

function Dibs.Ledger.GetTransactionForAward(awardRef)
  ensureState()
  local txId = awardRef and Dibs.db.ledger.awardTransactions[tostring(awardRef)]
  return txId and Dibs.db.ledger.transactions[txId] or nil
end

function Dibs.Ledger.RegisterSeasonAllocation(playerName, seasonId, amount, reason)
  local numericAmount = amount == nil and 1 or tonumber(amount)
  if not finiteNumber(numericAmount) or numericAmount <= 0 then return nil, "INVALID_AMOUNT" end
  return Dibs.Ledger.AddTransaction({
    playerName = playerName or Dibs.GetPlayerName(),
    amount = numericAmount,
    type = "SEASON_ALLOCATION",
    reason = reason or "Season allocation",
    source = "system",
    seasonId = seasonId or Dibs.GetCurrentSeasonId(),
  })
end

function Dibs.Ledger.GetHistory(playerName, seasonId)
  ensureState()
  local playerKey = normalizePlayerKey(playerName)
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local state = Dibs.db.ledger.playerStates[targetSeason] and Dibs.db.ledger.playerStates[targetSeason][playerKey]
  if not state then
    return {}
  end

  local history = {}
  for _, txId in ipairs(state.transactions or {}) do
    local tx = Dibs.db.ledger.transactions[txId]
    if tx then
      table.insert(history, tx)
    end
  end

  return history
end

function Dibs.Ledger.GetAllTransactions()
  ensureState()
  local list = {}
  for _, tx in pairs(Dibs.db.ledger.transactions) do
    table.insert(list, tx)
  end

  table.sort(list, function(a, b)
    return (a.createdAt or 0) < (b.createdAt or 0)
  end)

  return list
end

function Dibs.Ledger.GetTransactions(seasonId, playerGuidOrName)
  ensureState()
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local playerKey = playerGuidOrName and normalizePlayerKey(playerGuidOrName) or nil
  local history = {}

  for _, tx in pairs(Dibs.db.ledger.transactions) do
    local matchesSeason = tx.seasonId == targetSeason
    local matchesPlayer = playerKey == nil
      or normalizePlayerKey(tx.playerName or tx.playerKey) == playerKey
      or string.lower(tostring(tx.playerGuid or tx.playerId or "")) == string.lower(tostring(playerGuidOrName or ""))
    if matchesSeason and matchesPlayer then
      table.insert(history, tx)
    end
  end

  table.sort(history, function(a, b)
    return (a.createdAt or a.timestamp or 0) < (b.createdAt or b.timestamp or 0)
  end)

  return history
end

function Dibs.Ledger.GetPlayerSeasonState(seasonId, playerGuidOrName)
  ensureState()
  local targetSeason = seasonId or Dibs.GetCurrentSeasonId()
  local playerName = playerGuidOrName or Dibs.GetPlayerName()
  local playerKey = normalizePlayerKey(playerName)
  local token = tostring(playerGuidOrName or "")
  if token ~= "" and string.find(token, "Player%-", 1, false) == 1 then
    local byGuid = Dibs.Ledger.GetTransactions(targetSeason, token)
    if #byGuid > 0 and byGuid[1].playerName then
      playerName = byGuid[1].playerName
      playerKey = normalizePlayerKey(playerName)
    end
  end
  local txs = Dibs.Ledger.GetTransactions(targetSeason, playerGuidOrName)
  local transactionDelta = 0

  for _, tx in ipairs(txs) do
    if tx.type ~= "SEASON_ALLOCATION" then
      transactionDelta = transactionDelta + (tonumber(tx.amount) or tonumber(tx.quantityDelta) or 0)
    end
  end

  local state = Dibs.Ledger.GetPlayerState(playerName, targetSeason)
  local rankInfo = Dibs.RankRules and Dibs.RankRules.GetPlayerRankInfo and Dibs.RankRules.GetPlayerRankInfo(playerName) or { rankIndex = 0 }
  local baseAllocation = tonumber(state.allocation) or 0
  local projectedBalance = Dibs.Ledger.GetBalance(playerName, targetSeason)
  return {
    seasonId = targetSeason,
    playerGuid = tostring(playerGuidOrName or state.playerId or playerKey),
    playerName = playerName,
    currentRankIndex = rankInfo.rankIndex,
    baseAllocation = tonumber(baseAllocation) or 0,
    transactionDelta = transactionDelta,
    remainingBalance = projectedBalance,
    historySummary = { count = #txs },
    lastComputedAt = time(),
  }
end
