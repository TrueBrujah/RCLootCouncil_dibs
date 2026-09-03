local Dibs = _G.Dibs
Dibs.Ledger = Dibs.Ledger or {}

local function ensureState()
  Dibs.db = Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
  Dibs.db.ledger = Dibs.db.ledger or { transactions = {}, playerStates = {} }
  Dibs.db.ledger.transactions = Dibs.db.ledger.transactions or {}
  Dibs.db.ledger.playerStates = Dibs.db.ledger.playerStates or {}
  Dibs.db.ledger.awardTransactions = Dibs.db.ledger.awardTransactions or {}
end

local function normalizePlayerKey(playerName)
  return string.lower(playerName or Dibs.GetPlayerName())
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
  tx.type = tx.type or "DIB_ADMIN_ADJUSTMENT"
  tx.playerKey = normalizePlayerKey(tx.playerName or tx.playerKey or Dibs.GetPlayerName())
  tx.playerId = tx.playerId or (Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId(tx.playerName or tx.playerKey)) or tx.playerKey
  tx.seasonId = tx.seasonId or Dibs.GetCurrentSeasonId()
  tx.amount = tonumber(tx.amount) or 0
  tx.createdAt = tx.createdAt or time()
  tx.reason = tx.reason or "No reason provided"
  tx.action = tx.action or tx.type
  tx.actorId = tx.actorId or tx.systemOrigin or "system:legacy"
  tx.playerRank = tx.playerRank ~= nil and tx.playerRank or ((Dibs.RankRules and Dibs.RankRules.GetPlayerRankInfo(tx.playerName or tx.playerKey).rankIndex) or 0)

  if Dibs.db.ledger.transactions[tx.transactionId] then
    return Dibs.db.ledger.transactions[tx.transactionId]
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

local function mergeAudit(record, audit)
  for key, value in pairs(audit or {}) do record[key] = value end
  return record
end

function Dibs.Ledger.Grant(playerName, amount, reason, source, seasonId, audit)
  return Dibs.Ledger.AddTransaction(mergeAudit({
    playerName = playerName or Dibs.GetPlayerName(),
    amount = tonumber(amount) or 1,
    type = "DIB_GRANTED",
    reason = reason or "Dib granted",
    source = source or "system",
    seasonId = seasonId or Dibs.GetCurrentSeasonId(),
  }, audit))
end

function Dibs.Ledger.Use(playerName, amount, reason, source, seasonId, audit)
  return Dibs.Ledger.AddTransaction(mergeAudit({
    playerName = playerName or Dibs.GetPlayerName(),
    amount = -(tonumber(amount) or 1),
    type = "DIB_USED",
    reason = reason or "Dib consumed",
    source = source or "system",
    seasonId = seasonId or Dibs.GetCurrentSeasonId(),
  }, audit))
end

function Dibs.Ledger.Refund(playerName, amount, reason, source, seasonId, audit)
  return Dibs.Ledger.AddTransaction(mergeAudit({
    playerName = playerName or Dibs.GetPlayerName(),
    amount = tonumber(amount) or 1,
    type = "DIB_REFUNDED",
    reason = reason or "Dib refunded",
    source = source or "system",
    seasonId = seasonId or Dibs.GetCurrentSeasonId(),
  }, audit))
end

function Dibs.Ledger.AdminAdjust(playerName, amount, reason, source, seasonId, audit)
  return Dibs.Ledger.AddTransaction(mergeAudit({
    playerName = playerName or Dibs.GetPlayerName(),
    amount = tonumber(amount) or 0,
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
  return Dibs.Ledger.AddTransaction({
    playerName = playerName or Dibs.GetPlayerName(),
    amount = tonumber(amount) or 0,
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
