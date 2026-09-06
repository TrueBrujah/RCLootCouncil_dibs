local Dibs = _G.Dibs
Dibs.Sync = Dibs.Sync or {}

local function ensureState()
  Dibs.db = Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
  Dibs.db.sync = Dibs.db.sync or { seenTransactions = {}, peerStates = {} }
  Dibs.db.sync.seenTransactions = Dibs.db.sync.seenTransactions or {}
  Dibs.db.sync.peerStates = Dibs.db.sync.peerStates or {}
  Dibs.runtime = Dibs.runtime or {}
  Dibs.runtime.syncTransfers = Dibs.runtime.syncTransfers or {}
end

local MESSAGE_TYPES = { HELLO = true, MANIFEST = true, FETCH = true, TRANSFER_BEGIN = true, TRANSFER_CHUNK = true, TRANSFER_END = true, REQUEST_ACK = true, REQUEST = true }
local MAX_CHUNKS, MAX_TRANSFER_BYTES, TRANSFER_TTL = 12, 4096, 30

local function canonicalSender(sender)
  if type(sender) ~= "string" then return nil end
  local value = sender:match("^%s*(.-)%s*$")
  if value == "" or #value > 64 then return nil end
  if Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId then
    return Dibs.Permissions.CanonicalPlayerId(value)
  end
  return string.lower(value)
end

local function senderIsGuildMember(sender)
  local senderId = canonicalSender(sender)
  if not senderId or type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then return false end
  local okCount, memberCount = pcall(GetNumGuildMembers, true)
  if not okCount then return false end
  for index = 1, tonumber(memberCount) or 0 do
    local ok, name = pcall(GetGuildRosterInfo, index)
    if ok and Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId(name) == senderId then return true end
  end
  return false
end

local function senderIsGuildAdmin(sender)
  if not Dibs.Permissions or not Dibs.Permissions.GetGuildRole then return false end
  local role = Dibs.Permissions.GetGuildRole(sender)
  return role == "gm" or role == "officer"
end

local function localIsGuildAdmin()
  if not Dibs.Permissions or type(Dibs.Permissions.GetGuildRole) ~= "function" then return false end
  local role = Dibs.Permissions.GetGuildRole(nil)
  return role == "gm" or role == "officer"
end

local function validGuildEnvelope(message, sender)
  local senderId = canonicalSender(sender)
  if not senderId or not senderIsGuildMember(sender) then return false end
  local dataBearing = message.type == "MANIFEST" or message.type == "FETCH" or message.type == "REQUEST"
    or message.type == "TRANSFER_BEGIN" or message.type == "TRANSFER_CHUNK" or message.type == "TRANSFER_END"
  if dataBearing and (type(message.guildKey) ~= "string" or not Dibs.GetGuildKey or message.guildKey ~= Dibs.GetGuildKey()) then return false end
  if message.guildKey and Dibs.GetGuildKey and message.guildKey ~= Dibs.GetGuildKey() then return false end
  if message.version ~= nil and tonumber(message.version) ~= tonumber(Dibs.PROTOCOL_VERSION or 1) then return false end
  if senderId == canonicalSender(Dibs.GetPlayerName and Dibs.GetPlayerName() or nil) and message.type ~= "HELLO" then return false end
  return true
end

local function requestOwnerMatches(request, sender)
  if not request or not sender then return false end
  local owner = Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId and Dibs.Permissions.CanonicalPlayerId(request.playerName)
  local senderId = canonicalSender(sender)
  return owner ~= nil and senderId ~= nil and string.lower(tostring(owner)) == string.lower(tostring(senderId))
end

local function expireTransfers()
  ensureState()
  local now = time()
  for transferId, transfer in pairs(Dibs.runtime.syncTransfers) do
    if (tonumber(transfer.expiresAt) or 0) < now then Dibs.runtime.syncTransfers[transferId] = nil end
  end
end

function Dibs.Sync.BuildManifest()
  local requests = {}
  for _, request in ipairs(Dibs.PreDibs and Dibs.PreDibs.GetActiveRequests() or {}) do
    table.insert(requests, { requestId = request.requestId, revision = tonumber(request.revision) or 1 })
  end
  return { version = Dibs.PROTOCOL_VERSION or 1, guildKey = Dibs.GetGuildKey and Dibs.GetGuildKey() or nil, type = "MANIFEST", senderId = Dibs.GetPlayerName(), requests = requests }
end

function Dibs.Sync.Send(message, channel, target)
  if type(message) ~= "table" or not MESSAGE_TYPES[message.type] or Dibs.Sync.ContainsForbiddenLiveLootData(message) then return false end
  if not message.version then message.version = Dibs.PROTOCOL_VERSION or 1 end
  if not message.guildKey and Dibs.GetGuildKey then message.guildKey = Dibs.GetGuildKey() end
  if Dibs.Ace3 and Dibs.Ace3.SendComm and Dibs.Ace3.SendComm("DIBS", message, channel or "RAID", target) then
    return true
  end
  local api = _G.C_ChatInfo
  if type(api) ~= "table" or type(api.SendAddonMessage) ~= "function" then return false end
  if message.request or message.requests or message.snapshot then return false end
  local payload = "DIBS1:" .. tostring(message.type)
  if message.requestId then payload = payload .. ":" .. tostring(message.requestId) .. ":" .. tostring(message.revision or 1) end
  return pcall(api.SendAddonMessage, "DIBS", payload, channel or "RAID", target) == true
end

function Dibs.Sync.Receive(message, sender)
  ensureState()
  expireTransfers()
  if type(message) ~= "table" or not MESSAGE_TYPES[message.type] or Dibs.Sync.ContainsForbiddenLiveLootData(message) then return false end
  if not validGuildEnvelope(message, sender) then return false end
  if message.type == "REQUEST_ACK" then
    if not senderIsGuildAdmin(sender) then return false end
    local revision = tonumber(message.revision)
    if type(message.requestId) ~= "string" or #message.requestId < 1 or #message.requestId > 96
      or not revision or revision < 1 or revision > 1000000 or math.floor(revision) ~= revision then return false end
    return Dibs.PreDibs and Dibs.PreDibs.AcknowledgeDelivery and Dibs.PreDibs.AcknowledgeDelivery(message.requestId, revision, sender) ~= nil or false
  end
  if message.type == "MANIFEST" then
    if not localIsGuildAdmin() then return false end
    if type(message.requests) ~= "table" or #message.requests > 500 then return false end
    local fetch = {}
    for _, entry in ipairs(message.requests or {}) do
      local revision = type(entry) == "table" and tonumber(entry.revision) or nil
      if type(entry) ~= "table" or type(entry.requestId) ~= "string" or #entry.requestId < 1 or #entry.requestId > 96
        or not revision or revision < 1 or revision > 1000000 or math.floor(revision) ~= revision then return false end
      local localRequest = nil
      for _, request in ipairs(Dibs.PreDibs and Dibs.PreDibs.GetHistory() or {}) do if request.requestId == entry.requestId then localRequest = request break end end
      if not localRequest or (tonumber(localRequest.revision) or 1) < (tonumber(entry.revision) or 1) then table.insert(fetch, { requestId = entry.requestId, revision = entry.revision }) end
    end
    return { version = Dibs.PROTOCOL_VERSION or 1, guildKey = Dibs.GetGuildKey and Dibs.GetGuildKey() or nil, type = "FETCH", senderId = Dibs.GetPlayerName(), requests = fetch }
  end
  if message.type == "REQUEST" then
    if not localIsGuildAdmin() then return false end
    if not requestOwnerMatches(message.request, sender) then return false end
    return Dibs.PreDibs and Dibs.PreDibs.UpsertFromSync and Dibs.PreDibs.UpsertFromSync(message.request, sender) ~= nil or false
  end
  if message.type == "TRANSFER_BEGIN" then
    if not localIsGuildAdmin() then return false end
    local chunkCount = tonumber(message.chunkCount)
    if type(message.transferId) ~= "string" or #message.transferId < 1 or #message.transferId > 96
      or not chunkCount or math.floor(chunkCount) ~= chunkCount or chunkCount < 1 or chunkCount > MAX_CHUNKS then return false end
    local active = 0
    for _ in pairs(Dibs.runtime.syncTransfers) do active = active + 1 end
    if active >= 8 then return false end
    Dibs.runtime.syncTransfers[message.transferId] = { sender = canonicalSender(sender), chunkCount = chunkCount, chunks = {}, totalBytes = 0, expiresAt = time() + TRANSFER_TTL }
    return true
  end
  if message.type == "TRANSFER_CHUNK" then
    if not localIsGuildAdmin() then return false end
    local transfer = Dibs.runtime.syncTransfers[message.transferId]
    local index, chunk = tonumber(message.chunkIndex), message.chunk
    if not transfer or transfer.sender ~= canonicalSender(sender) or not index or math.floor(index) ~= index or index < 1 or index > transfer.chunkCount or type(chunk) ~= "string" or #chunk > MAX_TRANSFER_BYTES then return false end
    if transfer.chunks[index] == nil then transfer.totalBytes = transfer.totalBytes + #chunk end
    if transfer.totalBytes > MAX_CHUNKS * MAX_TRANSFER_BYTES then return false end
    transfer.chunks[index] = chunk
    return true
  end
  if message.type == "TRANSFER_END" then
    if not localIsGuildAdmin() then return false end
    local transfer = Dibs.runtime.syncTransfers[message.transferId]
    Dibs.runtime.syncTransfers[message.transferId] = nil
    if not transfer or transfer.sender ~= canonicalSender(sender) or type(message.request) ~= "table" or not requestOwnerMatches(message.request, sender) then return false end
    for index = 1, transfer.chunkCount do if transfer.chunks[index] == nil then return false end end
    return Dibs.PreDibs and Dibs.PreDibs.UpsertFromSync and Dibs.PreDibs.UpsertFromSync(message.request, sender) ~= nil or false
  end
  if message.type == "FETCH" then
    if not senderIsGuildAdmin(sender) then return false end
    if type(message.requests) ~= "table" or #message.requests > 500 then return false end
    for _, entry in ipairs(message.requests) do
      if type(entry) ~= "table" or type(entry.requestId) ~= "string" or #entry.requestId < 1 or #entry.requestId > 96 then return false end
    end
    local history = Dibs.PreDibs and Dibs.PreDibs.GetHistory and Dibs.PreDibs.GetHistory() or {}
    for _, entry in ipairs(message.requests) do
      for _, request in ipairs(history) do
        if request.requestId == entry.requestId and request.status ~= "fulfilled" then
          Dibs.Sync.Send({
            type = "REQUEST",
            request = request,
            version = Dibs.PROTOCOL_VERSION or 1,
          }, "WHISPER", sender)
          break
        end
      end
    end
  end
  return message.type == "HELLO" or message.type == "FETCH"
end

function Dibs.Sync.OnAddonMessage(prefix, payload, channel, sender)
  if prefix ~= "DIBS" or type(payload) ~= "string" then return false end
  if Dibs.Ace3 and Dibs.Ace3.Deserialize then
    local message = Dibs.Ace3.Deserialize(payload)
    if type(message) == "table" then
      local result = Dibs.Sync.Receive(message, sender)
      if type(result) == "table" then Dibs.Sync.Send(result, "WHISPER", sender) end
      return result
    end
  end
  local messageType, requestId, revision = payload:match("^DIBS1:([^:]+):?([^:]*):?([^:]*)$")
  if not MESSAGE_TYPES[messageType] then return false end
  return Dibs.Sync.Receive({ type = messageType, requestId = requestId ~= "" and requestId or nil, revision = tonumber(revision) }, sender)
end

function Dibs.Sync.RegisterTransport()
  if Dibs.Sync.transportRegistered then return true end
  if Dibs.Ace3 and Dibs.Ace3.RegisterComm and Dibs.Ace3.RegisterComm("DIBS", Dibs.Sync.OnAddonMessage) then
    Dibs.Sync.transportRegistered = true
    return true
  end
  return false
end

function Dibs.Sync.OnRosterChanged()
  local manifest = Dibs.Sync.BuildManifest()
  Dibs.Sync.Send(manifest, "RAID")
  if not Dibs.Sync.recoveryRetry and Dibs.Ace3 and Dibs.Ace3.ScheduleTimer then
    Dibs.Sync.recoveryRetry = Dibs.Ace3.ScheduleTimer(function()
      Dibs.Sync.recoveryRetry = nil
      Dibs.Sync.Send(Dibs.Sync.BuildManifest(), "RAID")
    end, 2)
  end
  return manifest
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
  if not localIsGuildAdmin() then
    return nil, "OFFICER_SCOPE_REQUIRED"
  end
  ensureState()
  if not peerId then
    return nil
  end

  return Dibs.db.sync.peerStates[peerId]
end

function Dibs.Sync.GetDigest()
  if not localIsGuildAdmin() then
    return { protocol = Dibs.PROTOCOL_VERSION or 1, txCount = 0, totalBalance = 0, season = nil, updatedAt = time(), reasonCode = "OFFICER_SCOPE_REQUIRED" }
  end
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
  if not localIsGuildAdmin() then
    return {
      version = Dibs.VERSION,
      protocolVersion = Dibs.PROTOCOL_VERSION,
      season = nil,
      transactions = {},
      preDibs = {},
      reasonCode = "OFFICER_SCOPE_REQUIRED",
    }
  end
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

function Dibs.Sync.ApplySnapshot(snapshot, actor)
  if not localIsGuildAdmin() then
    return false, "GUILD_ADMIN_REQUIRED"
  end
  if type(snapshot) ~= "table" then
    return false
  end
  if Dibs.Sync.ContainsForbiddenLiveLootData(snapshot) then
    return false
  end

  if snapshot.protocolVersion and tonumber(snapshot.protocolVersion) ~= tonumber(Dibs.PROTOCOL_VERSION or 1) then
    return false
  end
  if type(snapshot.transactions) == "table" and #snapshot.transactions > 10000 then return false end
  if type(snapshot.preDibs) == "table" and #snapshot.preDibs > 10000 then return false end

  if type(snapshot.transactions) == "table" then
    for _, tx in ipairs(snapshot.transactions) do
      if type(tx) ~= "table" or not tx.transactionId then return false end
      local valid = Dibs.Ledger.ValidateTransaction and Dibs.Ledger.ValidateTransaction(tx)
      if valid ~= true then return false end
    end
    for _, tx in ipairs(snapshot.transactions) do
      local result = Dibs.Ledger.AppendTransaction(tx)
      if not result or result.accepted ~= true then return false end
    end
  end

  if type(snapshot.preDibs) == "table" then
    local db = Dibs.GetDB()
    db.preDibs = db.preDibs or { requests = {} }
    db.preDibs.requests = db.preDibs.requests or {}
    for _, request in ipairs(snapshot.preDibs) do
      if type(request) ~= "table" or type(request.requestId) ~= "string" or #request.requestId > 96
        or type(request.playerName) ~= "string" or #request.playerName > 64
        or not tonumber(request.itemID) or tonumber(request.itemID) <= 0
        or type(request.seasonId) ~= "string" or type(request.status) ~= "string"
        or (request.status ~= "pending" and request.status ~= "confirmed" and request.status ~= "cancelled" and request.status ~= "invalidated" and request.status ~= "fulfilled")
      then return false end
      local found
      for _, existing in ipairs(db.preDibs.requests) do
        if existing.requestId == request.requestId then found = existing break end
      end
      if not found then
        table.insert(db.preDibs.requests, request)
      elseif (tonumber(request.revision) or 1) > (tonumber(found.revision) or 1) then
        if found.playerName ~= request.playerName or tonumber(found.itemID) ~= tonumber(request.itemID) or found.seasonId ~= request.seasonId then
          return false
        end
        for key, value in pairs(request) do
          if key ~= "playerName" and key ~= "itemID" and key ~= "seasonId" and key ~= "createdAt" then found[key] = value end
        end
      end
    end
  end

  return true
end
