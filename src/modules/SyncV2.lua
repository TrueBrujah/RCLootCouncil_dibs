--[[
Module: Dibs.Sync V2 transport foundation (B04)
Purpose: bounded GUILD digests and WHISPER detail transfer without enabling a
distributed ledger. Hashes and sender checks are integrity/attribution signals,
not cryptographic authentication.
]]

local Dibs = _G.Dibs
local Sync = Dibs.Sync

local MAJOR, MINOR = 2, 0
local MAX_MESSAGES, MAX_TRANSFERS, MAX_CHUNKS, MAX_BYTES, MAX_INDEX = 256, 8, 16, 8192, 500
local TTL, HEARTBEAT = 30, 60
local TYPES = { HELLO = true, DIGEST = true, DETAIL_FETCH = true, TRANSFER_BEGIN = true, TRANSFER_CHUNK = true, TRANSFER_END = true, LEDGER_DIGEST = true }
local TERMINAL = { cancelled = true, invalidated = true, fulfilled = true }

local function copy(value) return Dibs.DeepCopy and Dibs.DeepCopy(value) or value end
local function trim(value) return type(value) == "string" and value:match("^%s*(.-)%s*$") or nil end
local function finiteInteger(value) return type(tonumber(value)) == "number" and tonumber(value) == math.floor(tonumber(value)) end

local function ensure()
  local db = Dibs.GetDB()
  db.sync = db.sync or {}
  local state = db.sync
  state.v2 = state.v2 or { schema = 1, protocolState = "LEGACY_LOCAL", requestIndex = {}, tombstones = {}, replay = {}, peers = {} }
  state.v2.requestIndex = state.v2.requestIndex or {}; state.v2.tombstones = state.v2.tombstones or {}
  state.v2.replay = state.v2.replay or {}; state.v2.peers = state.v2.peers or {}
  Dibs.runtime = Dibs.runtime or {}; Dibs.runtime.v2Transfers = Dibs.runtime.v2Transfers or {}
  return state.v2
end

-- Same type-tagged/key-sorted 31-bit content identity shape as B03. It is not a
-- signature and intentionally uses a V2 domain prefix to avoid cross-entity use.
local function serialize(value, seen)
  local kind = type(value)
  if kind == "nil" then return "z" end
  if kind == "boolean" then return value and "b1" or "b0" end
  if kind == "number" then if value ~= value or math.abs(value) == math.huge then return nil end; return "n" .. string.format("%.17g", value == 0 and 0 or value) end
  if kind == "string" then return "s" .. #value .. ":" .. value end
  if kind ~= "table" then return nil end
  seen = seen or {}; if seen[value] then return nil end; seen[value] = true
  local parts = {}
  for key, item in pairs(value) do
    local a, b = serialize(key, seen), serialize(item, seen)
    if not a or not b then seen[value] = nil; return nil end
    parts[#parts + 1] = a .. "=" .. b
  end
  seen[value] = nil; table.sort(parts); return "t{" .. table.concat(parts, ",") .. "}"
end
local function hashText(text)
  local value = 0
  for i = 1, #text do value = (value * 131 + text:byte(i)) % 2147483647 end
  return string.format("D3-V2-%08x", value)
end
local function hash(value) local text = serialize(value); return text and hashText(text) or nil end

local function status(code, extra)
  local state = ensure(); state.status = code
  local result = extra or {}; result.status = code; return result
end
local function transportReady()
  local ace = Dibs.Ace3
  return ace and ace.Has and ace.Has("comm") and ace.Has("serializer") and type(ace.SendComm) == "function" and type(ace.Deserialize) == "function"
end
local function localSnapshot()
  if not Dibs.Identity or not Dibs.Identity.CreateSnapshot then return nil end
  return Dibs.Identity.CreateSnapshot(Dibs.GetPlayerName())
end
local function member(sender)
  if not Dibs.Identity or not Dibs.Identity.ResolveRosterMember then return nil, "ROSTER_UNAVAILABLE" end
  local resolved = Dibs.Identity.ResolveRosterMember(sender)
  if resolved.status ~= "RESOLVED" then return nil, resolved.status end
  return resolved
end
local function localRole()
  return Dibs.Permissions and Dibs.Permissions.GetGuildRole and Dibs.Permissions.GetGuildRole(nil) or "player"
end
local function isAdmin(sender)
  local resolved = member(sender); return resolved and (resolved.role == "gm" or resolved.role == "officer") or false
end
local function expiry()
  local now = time(); local state = ensure()
  for key, record in pairs(state.replay) do if (record.at or 0) + TTL < now then state.replay[key] = nil end end
  for key, transfer in pairs(Dibs.runtime.v2Transfers or {}) do if transfer.expiresAt < now then Dibs.runtime.v2Transfers[key] = nil end end
end
local function boundMap(map, maximum)
  local values = {}; for key, value in pairs(map) do values[#values + 1] = { key = key, at = value.at or value.updatedAt or 0 } end
  table.sort(values, function(a, b) return a.at < b.at end)
  for i = 1, #values - maximum do map[values[i].key] = nil end
end
local function requestProjection(request)
  return { requestId = request.requestId, revision = tonumber(request.revision) or 1, status = request.status, playerName = request.playerName, itemID = tonumber(request.itemID), seasonId = request.seasonId, updatedAt = request.updatedAt, createdAt = request.createdAt }
end
local function requestHash(request) return hash(requestProjection(request)) end

function Sync.CalculateContentHash(value) return hash(value) end
function Sync.CalculateRequestHash(request) return requestHash(request) end

function Sync.GetStatus()
  local state = ensure()
  if not transportReady() or Sync.transportRegistered ~= true then return { state = "SYNC_UNAVAILABLE", protocolState = state.protocolState } end
  return { state = state.status or "SYNC_READY", protocolState = state.protocolState, syncBehind = state.syncBehind == true, reason = state.reason }
end
function Sync.IsSyncBehind() return ensure().syncBehind == true end
function Sync.MarkSyncBehind(reason)
  local state = ensure(); state.syncBehind, state.reason = true, reason or "SYNC_BEHIND"; return status("SYNC_BEHIND", { reasonCode = state.reason })
end
function Sync.ClearSyncBehind()
  local state = ensure(); state.syncBehind, state.reason = false, nil; return status("SYNC_READY")
end
function Sync.GetProtocolState() return ensure().protocolState end
function Sync.SetProtocolState(state)
  -- B04 represents state but cannot independently enable enforcement.
  if state == "V2_ENFORCED" then return false, "GOVERNANCE_CUTOVER_REQUIRED" end
  if state ~= "LEGACY_LOCAL" and state ~= "CUTOVER_PREPARED" then return false, "INVALID_PROTOCOL_STATE" end
  ensure().protocolState = state; return true, state
end

function Sync.BuildEnvelope(message)
  local snapshot = localSnapshot(); if not snapshot then return nil, "ROSTER_UNAVAILABLE" end
  message = copy(message or {}); if not TYPES[message.type] then return nil, "INVALID_MESSAGE_TYPE" end
  message.protocol = { major = MAJOR, minor = MINOR, capabilities = { digest = true, whisperDetail = true, requestTombstones = true, ledgerDigestOnly = true } }
  message.messageId = message.messageId or Dibs.NewId("v2msg")
  message.guildKey = Dibs.GetGuildKey(); message.senderNameRealm = snapshot.displayName; message.senderMemberKey = snapshot.memberKey
  return message
end
function Sync.Send(message, channel, target)
  if Sync.ContainsForbiddenLiveLootData and Sync.ContainsForbiddenLiveLootData(message) then return false, "FORBIDDEN_LIVE_LOOT_DATA" end
  if not transportReady() then status("SYNC_UNAVAILABLE"); return false, "SYNC_UNAVAILABLE" end
  local envelope, reason = Sync.BuildEnvelope(message); if not envelope then return false, reason end
  channel = channel or "GUILD"
  if channel ~= "GUILD" and channel ~= "WHISPER" then return false, "INVALID_SYNC_CHANNEL" end
  if channel == "WHISPER" and (not trim(target) or #target > 96) then return false, "INVALID_WHISPER_TARGET" end
  local sent = Dibs.Ace3.SendComm("DIBS", envelope, channel, target)
  if not sent then status("SYNC_UNAVAILABLE"); return false, "SYNC_UNAVAILABLE" end
  return true, envelope.messageId
end

function Sync.BuildRequestIndex()
  local state = ensure(); local index, tombstones = {}, {}
  local records = Dibs.PreDibs and Dibs.PreDibs.GetHistory and Dibs.PreDibs.GetHistory() or {}
  for _, request in ipairs(records) do
    local projection = requestProjection(request); projection.contentHash = requestHash(request); projection.terminal = TERMINAL[request.status] == true
    index[#index + 1] = projection
  end
  table.sort(index, function(a, b) if a.updatedAt == b.updatedAt then return a.requestId < b.requestId end return (a.updatedAt or 0) > (b.updatedAt or 0) end)
  while #index > MAX_INDEX do table.remove(index) end
  state.requestIndex, state.tombstones = {}, {}
  for _, entry in ipairs(index) do state.requestIndex[entry.requestId] = copy(entry); if entry.terminal then state.tombstones[entry.requestId] = copy(entry) end end
  return index
end
function Sync.BuildManifest()
  return { type = "DIGEST", entityType = "PREDIB_INDEX", entityId = "current", revision = 1, contentHash = hash(Sync.BuildRequestIndex()), index = Sync.BuildRequestIndex(), protocolState = Sync.GetProtocolState() }
end
function Sync.BuildLedgerDigest()
  -- Intent only: B04 neither serializes nor applies ledger events.
  return { type = "LEDGER_DIGEST", entityType = "LEDGER", entityId = Dibs.GetCurrentSeasonId() or "none", revision = 0, contentHash = "LOCAL_ONLY", nextSeq = nil, previousHash = nil }
end
function Sync.BuildGovernanceDigest()
  local record = Dibs.Governance and Dibs.Governance.GetCurrentRecord and Dibs.Governance.GetCurrentRecord()
  local state = Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState() or {}
  return {
    type = "DIGEST", entityType = "GOVERNANCE", entityId = tostring(state.revision or 0),
    revision = tonumber(state.revision) or 0, contentHash = state.hash or "GENESIS",
    parentHash = record and record.parentHash or nil, protocolState = Sync.GetProtocolState(),
  }
end

local function validateEnvelope(message, sender)
  if type(message) ~= "table" or not TYPES[message.type] or type(message.protocol) ~= "table" then return nil, "MALFORMED_ENVELOPE" end
  if tonumber(message.protocol.major) ~= MAJOR then return nil, "UNSUPPORTED_PROTOCOL_MAJOR" end
  if type(message.messageId) ~= "string" or #message.messageId < 1 or #message.messageId > 128 then return nil, "INVALID_MESSAGE_ID" end
  if message.guildKey ~= Dibs.GetGuildKey() then return nil, "GUILD_SCOPE_MISMATCH" end
  local resolved, why = member(sender); if not resolved then return nil, why end
  if message.senderMemberKey ~= resolved.memberKey or string.lower(tostring(message.senderNameRealm or "")) ~= resolved.memberKey then return nil, "SENDER_MISMATCH" end
  if message.type == "LEDGER_DIGEST" and (message.nextSeq ~= nil or message.previousHash ~= nil) then return resolved, "LEDGER_DETAIL_FORBIDDEN" end
  return resolved
end
local function replayKey(resolved, id) return resolved.memberKey .. "|" .. id end
local function markReplay(resolved, id)
  local state = ensure(); state.replay[replayKey(resolved, id)] = { at = time() }; boundMap(state.replay, MAX_MESSAGES)
end
local function localRequest(id)
  for _, request in ipairs(Dibs.PreDibs and Dibs.PreDibs.GetHistory and Dibs.PreDibs.GetHistory() or {}) do if request.requestId == id then return request end end
end

local function requestDetail(target, requestId)
  local request = localRequest(requestId); if not request then return false, "DETAIL_NOT_FOUND" end
  local owner = member(request.playerName); if not owner then return false, "REQUEST_OWNER_UNAVAILABLE" end
  return Sync.SendDetail("PREDIB_REQUEST", requestId, tonumber(request.revision) or 1, requestHash(request), request, target)
end
function Sync.SendDetail(entityType, entityId, revision, contentHash, payload, target)
  if entityType ~= "PREDIB_REQUEST" and entityType ~= "GOVERNANCE" then return false, "UNSUPPORTED_ENTITY" end
  if not transportReady() then return false, "SYNC_UNAVAILABLE" end
  local encoded = Dibs.Ace3.Serialize(payload); if type(encoded) ~= "string" or #encoded > MAX_BYTES then return false, "PAYLOAD_TOO_LARGE" end
  local transferId = Dibs.NewId("v2transfer"); local chunks = {}
  for offset = 1, #encoded, 480 do chunks[#chunks + 1] = encoded:sub(offset, offset + 479) end
  if #chunks < 1 or #chunks > MAX_CHUNKS then return false, "PAYLOAD_TOO_LARGE" end
  local rawHash = hash(encoded)
  local sent = Sync.Send({ type = "TRANSFER_BEGIN", transferId = transferId, entityType = entityType, entityId = entityId, revision = revision, contentHash = contentHash, payloadHash = rawHash, chunkCount = #chunks }, "WHISPER", target)
  if not sent then return false, "SYNC_UNAVAILABLE" end
  for index, chunk in ipairs(chunks) do if not Sync.Send({ type = "TRANSFER_CHUNK", transferId = transferId, chunkIndex = index, chunk = chunk }, "WHISPER", target) then return false, "SYNC_UNAVAILABLE" end end
  return Sync.Send({ type = "TRANSFER_END", transferId = transferId }, "WHISPER", target)
end

local function applyRequest(payload, transfer, sender)
  if type(payload) ~= "table" or payload.requestId ~= transfer.entityId or tonumber(payload.revision) ~= tonumber(transfer.revision) then return false, "ENTITY_IDENTITY_MISMATCH" end
  if requestHash(payload) ~= transfer.contentHash then return false, "CONTENT_HASH_MISMATCH" end
  local owner = member(payload.playerName); if not owner or owner.memberKey ~= sender.memberKey then return false, "OWNER_MISMATCH" end
  local existing = localRequest(payload.requestId)
  if existing then
    local currentRevision, incomingRevision = tonumber(existing.revision) or 1, tonumber(payload.revision) or 1
    local currentHash = requestHash(existing)
    if incomingRevision == currentRevision then return currentHash == transfer.contentHash, currentHash == transfer.contentHash and "IDEMPOTENT_REPLAY" or "REQUEST_CONFLICT" end
    if incomingRevision < currentRevision then return false, "STALE_REVISION" end
  end
  local applied, reason = Dibs.PreDibs.ApplyVerifiedSyncRecord and Dibs.PreDibs.ApplyVerifiedSyncRecord(payload, sender.displayName)
  if not applied then return false, reason end
  local state = ensure(); state.requestIndex[payload.requestId] = { requestId = payload.requestId, revision = payload.revision, contentHash = transfer.contentHash, terminal = TERMINAL[payload.status] == true, updatedAt = payload.updatedAt or time() }
  if TERMINAL[payload.status] then state.tombstones[payload.requestId] = copy(state.requestIndex[payload.requestId]) end
  return true, "APPLIED"
end

function Sync.Receive(message, sender)
  ensure(); expiry()
  if Sync.ContainsForbiddenLiveLootData and Sync.ContainsForbiddenLiveLootData(message) then return false, "FORBIDDEN_LIVE_LOOT_DATA" end
  local resolved, reason = validateEnvelope(message, sender)
  if not resolved or reason then if reason == "LEDGER_DETAIL_FORBIDDEN" then Sync.MarkSyncBehind(reason) end; return false, reason end
  local state = ensure(); local key = replayKey(resolved, message.messageId)
  if state.replay[key] then return true, "IDEMPOTENT_MESSAGE_REPLAY" end
  markReplay(resolved, message.messageId)
  state.peers[resolved.memberKey] = { at = time(), protocol = copy(message.protocol), protocolState = message.protocolState or "LEGACY_LOCAL" }
  if message.type == "HELLO" then
    if message.protocolState == "V2_ENFORCED" then return false, "PROTOCOL_LEGACY_READ_ONLY" end
    return true, "HELLO"
  end
  if message.type == "LEDGER_DIGEST" then
    -- A newer non-contiguous future ledger is represented only as a gap. B06
    -- will define commits; B04 must not accept or infer their balances.
    if message.revision and tonumber(message.revision) > 0 then Sync.MarkSyncBehind("LEDGER_GAP") end
    return true, "LEDGER_DIGEST_ONLY"
  end
  if message.type == "DIGEST" and message.entityType == "GOVERNANCE" then
    if resolved.role ~= "gm" or not finiteInteger(message.revision) or type(message.contentHash) ~= "string" then return false, "INVALID_GOVERNANCE_DIGEST" end
    local current = Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState() or { revision = 0, hash = "GENESIS" }
    if tonumber(message.revision) > (tonumber(current.revision) or 0) then
      Sync.MarkSyncBehind("GOVERNANCE_PARENT_MISSING")
      Sync.Send({ type = "DETAIL_FETCH", requests = { { entityType = "GOVERNANCE", entityId = tostring(message.revision), revision = message.revision, contentHash = message.contentHash, parentHash = message.parentHash } } }, "WHISPER", resolved.displayName)
      return true, "GOVERNANCE_DETAIL_REQUESTED"
    end
    if tonumber(message.revision) == (tonumber(current.revision) or 0) and message.contentHash ~= current.hash then return false, "GOVERNANCE_CONFLICT" end
    return true, "GOVERNANCE_CURRENT"
  end
  if message.type == "DIGEST" then
    if message.entityType ~= "PREDIB_INDEX" or type(message.index) ~= "table" or #message.index > MAX_INDEX then return false, "INVALID_DIGEST" end
    local needed = {}
    for _, entry in ipairs(message.index) do
      if type(entry) ~= "table" or type(entry.requestId) ~= "string" or not finiteInteger(entry.revision) or type(entry.contentHash) ~= "string" then return false, "INVALID_DIGEST" end
      local current = localRequest(entry.requestId)
      local currentRevision = current and (tonumber(current.revision) or 1) or 0
      if tonumber(entry.revision) > currentRevision then needed[#needed + 1] = { entityType = "PREDIB_REQUEST", entityId = entry.requestId, revision = entry.revision, contentHash = entry.contentHash } end
      if tonumber(entry.revision) == currentRevision and current and requestHash(current) ~= entry.contentHash then return false, "REQUEST_CONFLICT" end
    end
    if #needed > 0 then Sync.MarkSyncBehind("MISSING_DETAIL"); Sync.Send({ type = "DETAIL_FETCH", requests = needed }, "WHISPER", resolved.displayName) end
    return true, #needed > 0 and "DETAIL_REQUESTED" or "DIGEST_CURRENT"
  end
  if message.type == "DETAIL_FETCH" then
    if type(message.requests) ~= "table" or #message.requests > 32 then return false, "INVALID_FETCH" end
    for _, requested in ipairs(message.requests) do
      if requested.entityType == "PREDIB_REQUEST" and type(requested.entityId) == "string" then
        local request = localRequest(requested.entityId)
        if request and member(request.playerName) and member(request.playerName).memberKey == (localSnapshot() and localSnapshot().memberKey) then requestDetail(resolved.displayName, requested.entityId) end
      elseif requested.entityType == "GOVERNANCE" and localRole() == "gm" then
        local record = Dibs.Governance and Dibs.Governance.GetCurrentRecord and Dibs.Governance.GetCurrentRecord()
        if record and tonumber(record.governanceRevision) == tonumber(requested.revision) then
          Sync.SendDetail("GOVERNANCE", tostring(record.governanceRevision), record.governanceRevision, record.contentHash, record, resolved.displayName)
        end
      end
    end
    return true, "DETAIL_SENT"
  end
  if message.type == "TRANSFER_BEGIN" then
    if type(message.transferId) ~= "string" or #message.transferId > 128 or type(message.entityType) ~= "string" or type(message.entityId) ~= "string" or not finiteInteger(message.revision) or not finiteInteger(message.chunkCount) or message.chunkCount < 1 or message.chunkCount > MAX_CHUNKS or type(message.contentHash) ~= "string" or type(message.payloadHash) ~= "string" then return false, "INVALID_TRANSFER_BEGIN" end
    if message.entityType ~= "PREDIB_REQUEST" and message.entityType ~= "GOVERNANCE" then return false, "UNSUPPORTED_ENTITY" end
    local existing = Dibs.runtime.v2Transfers[message.transferId]
    if existing then
      if existing.sender == resolved.memberKey and existing.entityType == message.entityType and existing.entityId == message.entityId
        and tonumber(existing.revision) == tonumber(message.revision) and existing.contentHash == message.contentHash
        and existing.payloadHash == message.payloadHash and tonumber(existing.chunkCount) == tonumber(message.chunkCount) then
        return true, "IDEMPOTENT_TRANSFER_BEGIN"
      end
      return false, "TRANSFER_ID_CONFLICT"
    end
    local count = 0; for _ in pairs(Dibs.runtime.v2Transfers) do count = count + 1 end; if count >= MAX_TRANSFERS then return false, "TRANSFER_CAPACITY" end
    Dibs.runtime.v2Transfers[message.transferId] = { sender = resolved.memberKey, entityType = message.entityType, entityId = message.entityId, revision = message.revision, contentHash = message.contentHash, payloadHash = message.payloadHash, chunkCount = message.chunkCount, chunks = {}, totalBytes = 0, expiresAt = time() + TTL }
    return true, "TRANSFER_STARTED"
  end
  if message.type == "TRANSFER_CHUNK" then
    local transfer = Dibs.runtime.v2Transfers[message.transferId]; local index = tonumber(message.chunkIndex)
    if not transfer or transfer.sender ~= resolved.memberKey or not finiteInteger(index) or index < 1 or index > transfer.chunkCount or type(message.chunk) ~= "string" or #message.chunk > MAX_BYTES then return false, "INVALID_TRANSFER_CHUNK" end
    if transfer.chunks[index] and transfer.chunks[index] ~= message.chunk then Dibs.runtime.v2Transfers[message.transferId] = nil; return false, "CONFLICTING_CHUNK" end
    if not transfer.chunks[index] then transfer.totalBytes = transfer.totalBytes + #message.chunk end
    if transfer.totalBytes > MAX_BYTES then Dibs.runtime.v2Transfers[message.transferId] = nil; return false, "PAYLOAD_TOO_LARGE" end
    transfer.chunks[index] = message.chunk; return true, "CHUNK_ACCEPTED"
  end
  if message.type == "TRANSFER_END" then
    local transfer = Dibs.runtime.v2Transfers[message.transferId]; Dibs.runtime.v2Transfers[message.transferId] = nil
    if not transfer or transfer.sender ~= resolved.memberKey then return false, "INVALID_TRANSFER_END" end
    local chunks = {}; for i = 1, transfer.chunkCount do if not transfer.chunks[i] then return false, "MISSING_TRANSFER_CHUNK" end; chunks[#chunks + 1] = transfer.chunks[i] end
    local raw = table.concat(chunks); if hash(raw) ~= transfer.payloadHash then return false, "PAYLOAD_HASH_MISMATCH" end
    local payload = Dibs.Ace3.Deserialize(raw); if type(payload) ~= "table" then return false, "DESERIALIZE_FAILED" end
    if transfer.entityType == "PREDIB_REQUEST" then
      local ok, applyReason = applyRequest(payload, transfer, resolved); if ok and Sync.IsSyncBehind() then Sync.ClearSyncBehind() end; return ok, applyReason
    end
    if transfer.entityType == "GOVERNANCE" and Dibs.Governance and Dibs.Governance.ApplyRecord then return Dibs.Governance.ApplyRecord(payload, resolved.displayName) end
    return false, "UNSUPPORTED_ENTITY"
  end
  return false, "UNSUPPORTED_MESSAGE"
end

function Sync.OnAddonMessage(prefix, payload, channel, sender)
  if prefix ~= "DIBS" or type(payload) ~= "string" then return false, "INVALID_PREFIX" end
  if not transportReady() then status("SYNC_UNAVAILABLE"); return false, "SYNC_UNAVAILABLE" end
  local message = Dibs.Ace3.Deserialize(payload); if type(message) ~= "table" then return false, "PROTOCOL_LEGACY_READ_ONLY" end
  local guildOnly = message.type == "HELLO" or message.type == "DIGEST" or message.type == "LEDGER_DIGEST"
  if (guildOnly and channel ~= "GUILD") or (not guildOnly and channel ~= "WHISPER") then return false, "INVALID_TRANSPORT_CHANNEL" end
  return Sync.Receive(message, sender)
end
function Sync.RegisterTransport()
  if not transportReady() then Sync.transportRegistered = false; status("SYNC_UNAVAILABLE"); return false end
  if Sync.transportRegistered then return true end
  local registered = Dibs.Ace3.RegisterComm and Dibs.Ace3.RegisterComm("DIBS", Sync.OnAddonMessage)
  Sync.transportRegistered = registered == true; if not Sync.transportRegistered then status("SYNC_UNAVAILABLE") end; return Sync.transportRegistered
end
local function scheduleHeartbeat()
  if Sync.heartbeat or not (Dibs.Ace3 and Dibs.Ace3.ScheduleTimer) then return end
  Sync.heartbeat = Dibs.Ace3.ScheduleTimer(function()
    Sync.heartbeat = nil
    Sync.OnLifecycle("HEARTBEAT")
  end, HEARTBEAT)
end
function Sync.OnLifecycle(reason)
  if not Sync.RegisterTransport() then return false, "SYNC_UNAVAILABLE" end
  local digest = Sync.BuildManifest(); local sent = Sync.Send(digest, "GUILD")
  scheduleHeartbeat()
  return sent, digest
end
function Sync.OnRosterChanged()
  -- Core invalidates the B02a roster before this hook.  Do not synchronously
  -- rebuild it here: that would hide the invalidation from governance and
  -- permit a message send using a roster transition that has not yet settled.
  -- Queue a small settled-roster pass as the GUILD_ROSTER_UPDATE anti-entropy
  -- trigger; the recurring bounded heartbeat remains the fallback.
  Sync.rosterRefreshPending = true
  if not Sync.rosterRefreshTimer and Dibs.Ace3 and Dibs.Ace3.ScheduleTimer then
    Sync.rosterRefreshTimer = Dibs.Ace3.ScheduleTimer(function()
      Sync.rosterRefreshTimer = nil
      Sync.rosterRefreshPending = nil
      Sync.OnLifecycle("GUILD_ROSTER_SETTLED")
    end, 1)
  end
  return true, "ROSTER_REFRESH_PENDING"
end

return Sync
