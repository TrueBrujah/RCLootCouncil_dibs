local Dibs = _G.Dibs
Dibs.Sync = Dibs.Sync or {}

local function ensureState()
  Dibs.db = Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
  Dibs.db.sync = Dibs.db.sync or { seenTransactions = {}, peerStates = {} }
  Dibs.db.sync.seenTransactions = Dibs.db.sync.seenTransactions or {}
  Dibs.db.sync.peerStates = Dibs.db.sync.peerStates or {}
end

function Dibs.Sync.MarkTransactionSeen(transactionId)
  ensureState()
  if transactionId then
    Dibs.db.sync.seenTransactions[tostring(transactionId)] = true
  end
  return true
end

function Dibs.Sync.HasSeenTransaction(transactionId)
  ensureState()
  return Dibs.db.sync.seenTransactions and Dibs.db.sync.seenTransactions[tostring(transactionId)] == true
end

function Dibs.Sync.RegisterPeer(peerId, state)
  ensureState()
  if not peerId then
    return nil
  end
  if Dibs.Sync.ContainsForbiddenLiveLootData and Dibs.Sync.ContainsForbiddenLiveLootData(state) then
    return nil
  end

  Dibs.db.sync.peerStates[peerId] = {
    lastSeen = time(),
    state = state or {},
  }

  return Dibs.db.sync.peerStates[peerId]
end

function Dibs.Sync.GetPeerState(peerId)
  ensureState()
  if not peerId then
    return nil
  end

  return Dibs.db.sync.peerStates[peerId]
end

function Dibs.Sync.GetDigest()
  ensureState()
  local txCount = 0
  local totalBalance = 0

  for _, tx in pairs(Dibs.db.ledger and Dibs.db.ledger.transactions or {}) do
    txCount = txCount + 1
    totalBalance = totalBalance + (tonumber(tx.amount) or 0)
  end

  return {
    protocol = Dibs.PROTOCOL_VERSION or 1,
    txCount = txCount,
    totalBalance = totalBalance,
    season = Dibs.GetCurrentSeasonId(),
    updatedAt = time(),
  }
end

function Dibs.Sync.SyncSnapshot()
  ensureState()
  local transactionFields = { "transactionId", "type", "playerKey", "playerId", "playerName", "seasonId", "amount", "createdAt", "reason", "source", "action", "actorId", "playerRank", "itemID", "itemLink", "awardRef" }
  local requestFields = { "requestId", "playerKey", "playerName", "itemID", "itemName", "seasonId", "status", "createdAt", "updatedAt", "confirmedAt", "fulfilledAt", "cancelledAt" }
  local function project(record, fields)
    local copy = {}
    for _, field in ipairs(fields) do
      if record[field] ~= nil then copy[field] = record[field] end
    end
    return copy
  end
  local transactions = {}
  for _, tx in ipairs(Dibs.Ledger and Dibs.Ledger.GetAllTransactions() or {}) do
    table.insert(transactions, project(tx, transactionFields))
  end
  local requests = {}
  for _, request in ipairs(Dibs.PreDibs and Dibs.PreDibs.GetHistory() or {}) do
    table.insert(requests, project(request, requestFields))
  end
  return {
    version = Dibs.VERSION,
    protocolVersion = Dibs.PROTOCOL_VERSION,
    season = Dibs.GetCurrentSeasonId(),
    transactions = transactions,
    preDibs = requests,
  }
end

function Dibs.Sync.ContainsForbiddenLiveLootData(value)
  local forbidden = { candidates = true, votes = true, responses = true, lootTable = true, session = true, currentSession = true }
  local function scan(node)
    if type(node) ~= "table" then return false end
    for key, item in pairs(node) do
      if forbidden[key] then return true end
      if type(item) == "table" and scan(item) then return true end
    end
    return false
  end
  return scan(value)
end

function Dibs.Sync.ApplySnapshot(snapshot)
  if type(snapshot) ~= "table" then
    return false
  end
  if Dibs.Sync.ContainsForbiddenLiveLootData(snapshot) then
    return false
  end

  if type(snapshot.transactions) == "table" then
    for _, tx in ipairs(snapshot.transactions) do
      if type(tx) == "table" and tx.transactionId then
        Dibs.Ledger.AddTransaction(tx)
      end
    end
  end

  if type(snapshot.preDibs) == "table" then
    for _, request in ipairs(snapshot.preDibs) do
      if type(request) == "table" and request.requestId then
        local exists = false
        for _, existing in ipairs((Dibs.db.preDibs and Dibs.db.preDibs.requests) or {}) do
          if existing.requestId == request.requestId then
            exists = true
            break
          end
        end
        if not exists then
          table.insert(Dibs.db.preDibs.requests, request)
        end
      end
    end
  end

  return true
end
