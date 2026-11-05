--[[
Module: Dibs.Sync V2 transport foundation (B04)
Purpose: bounded GUILD digests and shared detail transfer without enabling a
distributed ledger. Targeted WHISPER remains for private sync exceptions.
Hashes and sender checks are integrity/attribution signals, not cryptographic
authentication.
]]

---@diagnostic disable: return-type-mismatch, redundant-return-value, assign-type-mismatch

local Dibs = _G.Dibs
local Sync = Dibs.Sync

local MAJOR, MINOR = 2, 1
local MAX_MESSAGES, MAX_TRANSFERS, MAX_CHUNKS, MAX_BYTES, MAX_INDEX, MAX_PROTOCOL_MISMATCHES = 256, 8, 16, 8192, 500, 10
local LEDGER_BATCH_SIZE = 4
local PROPOSAL_RETRY_INTERVAL = 300
local AWARD_RESERVATION_PAGE_SIZE = 16
local CHANNEL_TEST_ACK_TIMEOUT = 20
local CHANNEL_TEST_RESULT_LIMIT = 30
local CHANNEL_TEST_PENDING_LIMIT = 16
local CHANNEL_TEST_RESPONSE_TTL = 120
local CHANNEL_TEST_PEER_WINDOW, CHANNEL_TEST_PEER_LIMIT = 60, 6
local TTL, HEARTBEAT, MAX_VAULT_RETRIES = 300, 60, 3
local MAX_CACHED_REQUEST_INDEXES = 8
local requestIndexCache, requestIndexCacheOrder = {}, {}
local vaultDigestSummaryCache = setmetatable({}, { __mode = "k" })
local LEDGER_DELETE_RETRY_INTERVAL = 300
local TYPES = { HELLO = true, DIGEST = true, DETAIL_FETCH = true, TRANSFER_BEGIN = true, TRANSFER_CHUNK = true, TRANSFER_END = true, TRANSFER_ACK = true, LEDGER_DIGEST = true, LEDGER_DELETE = true, VAULT_DIGEST = true, AWARD_RESERVATION_DIGEST = true, VAULT_FETCH = true, VAULT_DETAIL = true, VAULT_ACK = true, AWARD_PROPOSAL_ACK = true, LEDGER_OPERATION_PROPOSAL_ACK = true, SYNC_PROBE = true, SYNC_PROBE_RESPONSE = true }
TYPES.CHANNEL_TEST, TYPES.CHANNEL_TEST_ACK = true, true
TYPES.SYNC_REPAIR_REQUEST, TYPES.SYNC_REPAIR_ACK = true, true
local CHANNEL_TEST_CHANNELS = { GUILD = true, OFFICER = true, RAID = true, PARTY = true, INSTANCE_CHAT = true, WHISPER = true, CHANNEL = true }
local GUILD_DETAIL_ENTITIES = { GOVERNANCE = true, OPERATIONAL_POLICY = true, LEGACY_BASELINE = true, AUTHORITY_SIGNAL = true, AWARD_COMMIT = true, LEDGER_OPERATION_COMMIT = true, SEASON_CATALOG = true, LEDGER_CATALOG = true, LEDGER_BATCH = true }
local WHISPER_DETAIL_ENTITIES = { PREDIB_REQUEST = true, VAULT_DETAIL = true, LEGACY_RECOVERY_PACKAGE = true, AUTHORITY_ORPHAN = true, AWARD_PROPOSAL = true, LEDGER_OPERATION_PROPOSAL = true, REQUEST_MESSAGE = true }
local TRUSTED_RELAY_ENTITIES = { GOVERNANCE = true, OPERATIONAL_POLICY = true, SEASON_CATALOG = true, LEGACY_BASELINE = true }
local TERMINAL = { cancelled = true, invalidated = true, fulfilled = true }
local awardReservationGenerations = {}
local boundMap

local function rememberRequestIndexCache(ledgerId, entry)
  if requestIndexCache[ledgerId] == nil then
    if #requestIndexCacheOrder >= MAX_CACHED_REQUEST_INDEXES then
      local expired = table.remove(requestIndexCacheOrder, 1)
      requestIndexCache[expired] = nil
    end
    requestIndexCacheOrder[#requestIndexCacheOrder + 1] = ledgerId
  end
  requestIndexCache[ledgerId] = entry
end

local function bumpAwardReservationGeneration(memberKey)
  if type(memberKey) == "string" then
    awardReservationGenerations[memberKey] = (awardReservationGenerations[memberKey] or 0) + 1
  end
end

local function copy(value) return Dibs.DeepCopy and Dibs.DeepCopy(value) or value end
local function trim(value) return type(value) == "string" and value:match("^%s*(.-)%s*$") or nil end
local function finiteInteger(value) return type(tonumber(value)) == "number" and tonumber(value) == math.floor(tonumber(value)) end
local function detailChannel(entityType)
  if GUILD_DETAIL_ENTITIES[entityType] then return "GUILD" end
  if WHISPER_DETAIL_ENTITIES[entityType] then return "WHISPER" end
  return nil
end
local function detailFetchChannel(requests)
  if type(requests) ~= "table" or #requests == 0 then return nil end
  local channel
  for _, request in ipairs(requests) do
    local requestChannel = type(request) == "table" and detailChannel(request.entityType)
    if not requestChannel or (channel and channel ~= requestChannel) then return nil end
    channel = requestChannel
  end
  return channel
end
local function expectedTransportChannel(message, transfer)
  if message.type == "SYNC_REPAIR_REQUEST" then
    return message.scope == "GUILD" and "GUILD" or "WHISPER"
  end
  if message.type == "SYNC_REPAIR_ACK" then return "WHISPER" end
  if message.type == "CHANNEL_TEST_ACK" then
    if message.ackTransport == "WHISPER" then return "WHISPER" end
    if message.ackTransport ~= nil then return nil end
    return CHANNEL_TEST_CHANNELS[message.testChannel] and message.testChannel or nil
  end
  if message.type == "CHANNEL_TEST" then
    return CHANNEL_TEST_CHANNELS[message.testChannel] and message.testChannel or nil
  end
  if message.type == "HELLO" or message.type == "DIGEST" or message.type == "LEDGER_DIGEST"
    or message.type == "LEDGER_DELETE"
    or message.type == "VAULT_DIGEST" or message.type == "AWARD_RESERVATION_DIGEST" then
    return "GUILD"
  end
  if message.type == "DETAIL_FETCH" then return detailFetchChannel(message.requests) end
  if message.type == "TRANSFER_BEGIN" then return detailChannel(message.entityType) end
  if message.type == "TRANSFER_CHUNK" then return transfer and detailChannel(transfer.entityType) end
  if message.type == "TRANSFER_END" then
    if transfer and message.entityType ~= transfer.entityType then return nil end
    return detailChannel(transfer and transfer.entityType or message.entityType)
  end
  if message.type == "TRANSFER_ACK" then return detailChannel(message.entityType) end
  if message.type == "VAULT_FETCH" or message.type == "VAULT_DETAIL" or message.type == "VAULT_ACK"
    or message.type == "SYNC_PROBE" or message.type == "SYNC_PROBE_RESPONSE"
    or message.type == "AWARD_PROPOSAL_ACK" or message.type == "LEDGER_OPERATION_PROPOSAL_ACK" then return "WHISPER" end
  return nil
end
local function allowsLegacyWhisper(message, transfer)
  local capabilities = message.protocol and message.protocol.capabilities
  if type(capabilities) == "table" and capabilities.guildDetail == true then return false end
  if message.type == "DETAIL_FETCH" then return detailFetchChannel(message.requests) == "GUILD" end
  if message.type == "TRANSFER_BEGIN" then return GUILD_DETAIL_ENTITIES[message.entityType] == true end
  if message.type == "TRANSFER_CHUNK" then return transfer and GUILD_DETAIL_ENTITIES[transfer.entityType] == true or false end
  if message.type == "TRANSFER_END" then
    local entityType = transfer and transfer.entityType or message.entityType
    return (not transfer or message.entityType == transfer.entityType) and GUILD_DETAIL_ENTITIES[entityType] == true
  end
  if message.type == "TRANSFER_ACK" then return GUILD_DETAIL_ENTITIES[message.entityType] == true end
  return false
end

local function ensure(dbOverride)
  local db = type(dbOverride) == "table" and dbOverride or Dibs.GetDB()
  Dibs.db = db
  db.sync = db.sync or {}
  local state = db.sync
  state.v2 = state.v2 or { schema = 1, protocolState = "LEGACY_LOCAL", requestIndex = {}, tombstones = {}, replay = {}, peers = {} }
  state.v2.requestIndex = state.v2.requestIndex or {}; state.v2.tombstones = state.v2.tombstones or {}
  state.v2.replay = state.v2.replay or {}; state.v2.peers = state.v2.peers or {}
  state.v2.transferAcks = state.v2.transferAcks or {}
  state.v2.vaultPending = state.v2.vaultPending or {}; state.v2.protocolMismatches = state.v2.protocolMismatches or {}
  state.v2.awardReservations = state.v2.awardReservations or {}
  state.v2.awardReservationTombstones = state.v2.awardReservationTombstones or {}
  state.v2.awardReservations = state.v2.awardReservations or {}
  state.v2.awardReservationTombstones = state.v2.awardReservationTombstones or {}
  state.v2.addonVersionMismatches = state.v2.addonVersionMismatches or {}
  state.v2.predibPending = state.v2.predibPending or {}
  Dibs.runtime = Dibs.runtime or {}; Dibs.runtime.v2Transfers = Dibs.runtime.v2Transfers or {}
  return state.v2
end

-- Read the already-resolved active guild store on hot UI paths. Fall back to
-- ensure() whenever the current guild scope or Sync store is not established.
local function statusReadState()
  local currentGuildKey = type(Dibs.GetGuildKey) == "function" and Dibs.GetGuildKey() or nil
  local db = Dibs.db
  local sync = type(db) == "table" and db.sync
  local state = type(sync) == "table" and sync.v2
  if currentGuildKey and Dibs.currentGuildKey == currentGuildKey and type(state) == "table" then
    return state
  end
  return ensure()
end

local function trustedDigestKey(entityType, revision, contentHash)
  return table.concat({ tostring(entityType or ""), tostring(revision or ""), tostring(contentHash or "") }, "|")
end

local function trustedDigestStore()
  local localDB = Dibs.GetLocalDB and Dibs.GetLocalDB() or {}
  localDB.trustedSyncDigests = localDB.trustedSyncDigests or {}
  local guildKey = Dibs.GetGuildKey and Dibs.GetGuildKey() or "unknown"
  localDB.trustedSyncDigests[guildKey] = localDB.trustedSyncDigests[guildKey] or {}
  return localDB.trustedSyncDigests[guildKey]
end

local function rememberTrustedDigest(entityType, revision, contentHash, source)
  if not TRUSTED_RELAY_ENTITIES[entityType] or not finiteInteger(revision)
    or type(contentHash) ~= "string" or contentHash == "" then return false end
  local store = trustedDigestStore()
  store[trustedDigestKey(entityType, revision, contentHash)] = {
    entityType = entityType,
    revision = tonumber(revision),
    contentHash = contentHash,
    sourceMemberKey = source and source.memberKey,
    observedAt = time(),
  }
  boundMap(store, 128)
  return true
end

local function hasTrustedDigest(entityType, revision, contentHash)
  if not TRUSTED_RELAY_ENTITIES[entityType] then return false end
  return trustedDigestStore()[trustedDigestKey(entityType, revision, contentHash)] ~= nil
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
---@param text string
---@return string hash
local function hashText(text)
  local value = 0
  for i = 1, #text do value = (value * 131 + text:byte(i)) % 2147483647 end
  return string.format("D3-V2-%08x", value)
end
---@param text string
local function hashTextValue(text) return hashText(text) end
local function hash(value) local text = serialize(value); return text and hashTextValue(text) or nil end

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
local function routeForPeer(channel, target)
  if channel ~= "GUILD" or not target then return channel end
  local resolved = member(target)
  local peer = resolved and ensure().peers[resolved.memberKey]
  local capabilities = peer and peer.protocol and peer.protocol.capabilities
  if peer and (type(capabilities) ~= "table" or capabilities.guildDetail ~= true) then return "WHISPER" end
  return channel
end
local function sendDetailFetch(requests, target)
  local channel = detailFetchChannel(requests)
  if not channel then return false, "INVALID_DETAIL_FETCH_CHANNEL" end
  channel = routeForPeer(channel, target)
  return Sync.Send({ type = "DETAIL_FETCH", requests = requests }, channel, channel == "WHISPER" and target or nil)
end
local function localRole()
  return Dibs.Permissions and Dibs.Permissions.GetGuildRole and Dibs.Permissions.GetGuildRole(nil) or "player"
end
local function isAdmin(sender)
  local resolved = member(sender); return resolved and (resolved.role == "gm" or resolved.role == "officer") or false
end
local function isApprovedLedger(ledgerId)
  if type(ledgerId) ~= "string" or ledgerId == "" then return false end
  if ledgerId == "guild-primary" then return true end
  local ledger = Dibs.MultiLedger and Dibs.MultiLedger.GetLedgerById and Dibs.MultiLedger.GetLedgerById(ledgerId)
  return ledger ~= nil and ledger.status == "APPROVED"
    and Dibs.Governance and Dibs.Governance.IsLedgerApproved
    and Dibs.Governance.IsLedgerApproved(ledgerId) == true
end
local function expiry()
  local now = time(); local state = ensure()
  for key, record in pairs(state.replay) do if (record.at or 0) + TTL < now then state.replay[key] = nil end end
  for key, transfer in pairs(Dibs.runtime.v2Transfers or {}) do if transfer.expiresAt < now then Dibs.runtime.v2Transfers[key] = nil end end
end
boundMap = function(map, maximum)
  local values = {}; for key, value in pairs(map) do values[#values + 1] = { key = key, at = value.at or value.updatedAt or value.observedAt or 0 } end
  table.sort(values, function(a, b) return a.at < b.at end)
  for i = 1, #values - maximum do map[values[i].key] = nil end
end
local function rememberProtocolMismatch(sender, remoteMajor)
  local mismatches = ensure().protocolMismatches
  mismatches[#mismatches + 1] = {
    sender = trim(sender) or "unknown", localMajor = MAJOR, remoteMajor = tonumber(remoteMajor), timestamp = time(),
  }
  while #mismatches > MAX_PROTOCOL_MISMATCHES do table.remove(mismatches, 1) end
end
local function parseAddonVersion(value)
  if type(value) ~= "string" then return nil end
  local major, minor, patch = value:match("^(%d+)%.(%d+)%.(%d+)[%-+]?.*$")
  if not major then return nil end
  return { major = tonumber(major), minor = tonumber(minor), patch = tonumber(patch), raw = value }
end
local function rememberAddonVersionMismatch(sender, remoteVersion, reason)
  local mismatches = ensure().addonVersionMismatches
  mismatches[#mismatches + 1] = {
    sender = trim(sender) or "unknown", localVersion = Dibs.VERSION or "unknown", remoteVersion = remoteVersion,
    reasonCode = reason, timestamp = time(),
  }
  while #mismatches > MAX_PROTOCOL_MISMATCHES do table.remove(mismatches, 1) end
end
local function clearAddonVersionMismatch(sender)
  local mismatches = ensure().addonVersionMismatches
  local normalized = string.lower(tostring(sender or ""))
  for index = #mismatches, 1, -1 do
    if string.lower(tostring(mismatches[index].sender or "")) == normalized then table.remove(mismatches, index) end
  end
end
local function beginPeerStatusTiming()
  if Dibs.UIRenderStats and Dibs.UIRenderStats.IsEnabled and Dibs.UIRenderStats.IsEnabled()
    and type(_G.debugprofilestop) == "function" then
    return _G.debugprofilestop()
  end
end
local function recordPeerStatusTiming(name, startedAt)
  if startedAt and Dibs.UIRenderStats and Dibs.UIRenderStats.Record then
    Dibs.UIRenderStats.Record("Sync data", name, startedAt)
  end
end
local function localSyncDigests(dbOverride)
  local digests = {}
  local stateStartedAt = beginPeerStatusTiming()
  local catalog = Dibs.Seasons and Dibs.Seasons.GetCatalogSummary and Dibs.Seasons.GetCatalogSummary()
    or (Dibs.Seasons and Dibs.Seasons.GetCatalogState and Dibs.Seasons.GetCatalogState()) or {}
  digests.SEASON_CATALOG = { revision = tonumber(catalog.catalogRevision) or 0, contentHash = catalog.hash }
  local policy = Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetDigestSummary and Dibs.OperationalPolicy.GetDigestSummary()
    or (Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetState and Dibs.OperationalPolicy.GetState()) or {}
  digests.OPERATIONAL_POLICY = { revision = tonumber(policy.policyRevision) or 0, contentHash = policy.hash }
  recordPeerStatusTiming("local-catalog-policy", stateStartedAt)
  local activeLedgerStartedAt = beginPeerStatusTiming()
  local activeLedgerId = Dibs.MultiLedger and Dibs.MultiLedger.GetActiveLedgerId
    and Dibs.MultiLedger.GetActiveLedgerId(dbOverride) or "guild-primary"
  recordPeerStatusTiming("local-active-ledger-id", activeLedgerStartedAt)
  local requestStartedAt = beginPeerStatusTiming()
  local manifest = Sync.GetManifestDigestSummary and Sync.GetManifestDigestSummary(activeLedgerId)
    or (Sync.BuildManifest and Sync.BuildManifest(activeLedgerId)) or {}
  local predibKey = activeLedgerId == "guild-primary" and "PREDIB_INDEX"
    or ("PREDIB_INDEX:" .. tostring(activeLedgerId))
  digests[predibKey] = { revision = tonumber(manifest.revision) or 0, contentHash = manifest.contentHash }
  recordPeerStatusTiming("local-request-digest", requestStartedAt)
  local vaultStartedAt = beginPeerStatusTiming()
  local vault = Sync.GetVaultDigestSummary and Sync.GetVaultDigestSummary()
    or (Sync.BuildVaultDigest and Sync.BuildVaultDigest()) or {}
  digests.VAULT_INDEX = { revision = tonumber(vault.revision) or 0, contentHash = vault.contentHash }
  recordPeerStatusTiming("local-vault-digest", vaultStartedAt)
  local ledgerStartedAt = beginPeerStatusTiming()
  local ledger = Sync.BuildLedgerDigest and Sync.BuildLedgerDigest(activeLedgerId, dbOverride) or {}
  digests.LEDGER = { revision = tonumber(ledger.revision) or 0, contentHash = ledger.contentHash }
  recordPeerStatusTiming("local-ledger-digest", ledgerStartedAt)
  return digests
end
local function requestProjection(request)
  local projection = { requestId = request.requestId, revision = tonumber(request.revision) or 1, status = request.status, playerName = request.playerName, itemID = tonumber(request.itemID), seasonId = request.seasonId, updatedAt = request.updatedAt, createdAt = request.createdAt }
  local ledgerId = request.ledgerId or "guild-primary"
  if ledgerId ~= "guild-primary" then projection.ledgerId = ledgerId end
  return projection
end
local function requestHash(request) return hash(requestProjection(request)) end
local function ownerRequestProjection(request)
  local projection = requestProjection(request)
  for _, field in ipairs({ "itemName", "itemLink", "source", "modeAtCreation", "difficulty",
    "confirmedAt", "cancelledAt", "invalidatedAt", "fulfilledAt" }) do
    projection[field] = copy(request[field])
  end
  return projection
end

function Sync.CalculateContentHash(value) return hash(value) end
function Sync.CalculateRequestHash(request) return requestHash(request) end
function Sync.GetAddonVersionCompatibility(remoteVersion)
  local localVersion, remote = parseAddonVersion(Dibs.VERSION), parseAddonVersion(remoteVersion)
  if not localVersion then return false, "LOCAL_ADDON_VERSION_INVALID" end
  if not remote then return nil, "REMOTE_ADDON_VERSION_UNKNOWN" end
  if localVersion.major == remote.major and localVersion.minor == remote.minor then return true, "ADDON_VERSION_COMPATIBLE" end
  return false, "ADDON_UPDATE_REQUIRED"
end

function Sync.SendAwardProposalResult(proposalId, result, reasonCode, target)
  if type(proposalId) ~= "string" or proposalId == "" or (result ~= "STALE" and result ~= "REJECTED") then
    return false, "INVALID_PROPOSAL_RESULT"
  end
  local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
  local localMember = localSnapshot()
  if not authority or authority.state ~= "ACTIVE" or not localMember or not authority.coordinator
    or authority.coordinator.memberKey ~= localMember.memberKey then return false, "CURRENT_COORDINATOR_REQUIRED" end
  return Sync.Send({ type = "AWARD_PROPOSAL_ACK", proposalId = proposalId, result = result,
    reasonCode = reasonCode }, "WHISPER", target)
end

function Sync.BuildSyncProbeReport()
  local state = ensure()
  local governance = Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState() or {}
  local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState() or {}
  local baseline = Dibs.HistoricalBaseline and Dibs.HistoricalBaseline.GetBaseline and Dibs.HistoricalBaseline.GetBaseline() or {}
  local ledger = Dibs.Ledger and Dibs.Ledger.GetCanonicalState and Dibs.Ledger.GetCanonicalState() or {}
  local snapshot = localSnapshot() or {}
  local catalog = Dibs.Seasons and Dibs.Seasons.GetCatalogState and Dibs.Seasons.GetCatalogState() or {}
  local policy = Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetState and Dibs.OperationalPolicy.GetState() or {}
  return {
    addonVersion = Dibs.VERSION,
    memberKey = snapshot.memberKey,
    displayName = snapshot.displayName,
    role = localRole(),
    protocolState = state.protocolState,
    syncBehind = state.syncBehind == true,
    syncReason = state.reason,
    governance = { revision = tonumber(governance.revision) or 0, hash = governance.hash, status = governance.status },
    baselineHash = baseline.legacyBaselineHash,
    authority = {
      state = authority.state,
      ledgerEpoch = authority.ledgerEpoch,
      coordinatorMemberKey = authority.coordinator and authority.coordinator.memberKey,
      coordinatorName = authority.coordinator and authority.coordinator.displayName,
    },
    operationalPolicyRevision = tonumber(policy.policyRevision) or 0,
    seasonCatalogRevision = tonumber(catalog.catalogRevision) or 0,
    entityDigests = localSyncDigests(),
    ledger = {
      epoch = ledger.epoch,
      revision = (tonumber(ledger.nextSeq) or 1) - 1,
      rootHash = ledger.rootHash,
    },
  }
end
function Sync.ProbePeer(target)
  if not target or target == "" then return false, "INVALID_WHISPER_TARGET" end
  local snapshot = localSnapshot()
  if not snapshot or (localRole() ~= "gm" and localRole() ~= "officer") then return false, "OFFICER_REQUIRED" end
  return Sync.Send({ type = "SYNC_PROBE", requestId = Dibs.NewId("syncprobe") }, "WHISPER", target)
end
local function repairContextAllowed()
  if Dibs.DeveloperSandbox and Dibs.DeveloperSandbox.IsActive and Dibs.DeveloperSandbox.IsActive() then
    return false, "SANDBOX_ACTIVE"
  end
  if Dibs.IndependentRaid and Dibs.IndependentRaid.IsSessionActive and Dibs.IndependentRaid.IsSessionActive() then
    return false, "INDEPENDENT_RAID_ACTIVE"
  end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return false, "IN_COMBAT" end
  return true
end

local function repairState()
  Dibs.runtime = Dibs.runtime or {}
  Dibs.runtime.syncRepair = Dibs.runtime.syncRepair or { pending = {}, sentAt = {} }
  local state, now = Dibs.runtime.syncRepair, time()
  for id, request in pairs(state.pending) do
    if request.at + TTL < now then state.pending[id] = nil end
  end
  return state
end

local function requestRepair(target)
  local allowed, reason = repairContextAllowed()
  if not allowed then return false, reason end
  if not isAdmin(Dibs.GetPlayerName()) then return false, "OFFICER_REQUIRED" end
  local recipient
  if target then
    recipient, reason = member(target)
    if not recipient then return false, reason end
    if recipient.online ~= true then return false, "WHISPER_TARGET_OFFLINE" end
    if recipient.memberKey == (localSnapshot() or {}).memberKey then return false, "USE_LOCAL_REPAIR" end
    local peer = ensure().peers[recipient.memberKey]
    if peer and not (peer.protocol and peer.protocol.capabilities and peer.protocol.capabilities.guildRepair) then
      return false, "PEER_UPDATE_REQUIRED"
    end
  end
  local state, now = repairState(), time()
  local scopeKey = recipient and recipient.memberKey or "GUILD"
  if state.sentAt[scopeKey] and now - state.sentAt[scopeKey].at < HEARTBEAT then
    return false, "REPAIR_COOLDOWN"
  end
  local requestId = Dibs.NewId("syncrepair")
  local sent, sendReason = Sync.Send({ type = "SYNC_REPAIR_REQUEST", requestId = requestId,
    scope = recipient and "PEER" or "GUILD" }, recipient and "WHISPER" or "GUILD",
    recipient and recipient.displayName)
  if not sent then return false, sendReason end
  state.pending[requestId] = { at = now, target = recipient and recipient.memberKey }
  state.sentAt[scopeKey] = { at = now }
  boundMap(state.pending, 16)
  boundMap(state.sentAt, 64)
  if Dibs.DebugLogs and Dibs.DebugLogs.Add then
    Dibs.DebugLogs.Add("sync", 1, "Recovery requested by " .. Dibs.GetPlayerName() .. " for " .. scopeKey)
  end
  -- Advertise the source as well: the recipient may have no known gap yet.
  Sync.RequestResync()
  return true, requestId
end

function Sync.RepairPeer(target)
  if type(target) ~= "string" or trim(target) == "" then return false, "INVALID_WHISPER_TARGET" end
  return requestRepair(target)
end

---@doc.id sync.guild.recovery
---@doc.category synchronization
---@doc.since 0.8.10
---@doc.audience officer,gm
---@doc.scope guild
---@doc.audit false
---@doc.help-key UI_HELP_SYNC_GUILD_REPAIR
---@doc.label-key SYNC_GUILD_REPAIR_BUTTON
---@doc.reference-key DOC_SYNC_FIX_REFERENCE
function Sync.RepairGuild()
  return requestRepair()
end
function Sync.GetPeerSyncProbe(target)
  local resolved = member(target)
  local peer = resolved and ensure().peers[resolved.memberKey]
  if not peer or not peer.syncProbe then return nil end
  local probe = copy(peer.syncProbe)
  probe.transferAck = copy(peer.transferAck)
  return probe
end
function Sync.FormatSyncProbeReport(probe)
  local report = probe and probe.report or probe
  if type(report) ~= "table" then return "No synchronization probe response." end
  local governance = report.governance or {}; local authority = report.authority or {}; local ledger = report.ledger or {}
  local transferAck = probe and probe.transferAck
  local progress = transferAck and tonumber(transferAck.chunkCount) and tonumber(transferAck.chunkCount) > 0
    and string.format(" chunks=%d/%d", tonumber(transferAck.receivedChunks) or 0, tonumber(transferAck.chunkCount)) or ""
  local suffix = transferAck and string.format(" baselineAck=%s/%s%s", tostring(transferAck.result), tostring(transferAck.reasonCode or "none"), progress) or ""
  if probe and probe.repair then
    suffix = suffix .. " repair=" .. tostring(probe.repair.result) .. "/" .. tostring(probe.repair.reasonCode or "none")
  end
  return string.format(
    "%s role=%s protocol=%s behind=%s reason=%s governance=%s/%s baseline=%s authority=%s coordinator=%s policy=%s catalog=%s ledger=%s/%s epoch=%s",
    tostring(report.displayName or "unknown"), tostring(report.role or "unknown"), tostring(report.protocolState or "unknown"),
    tostring(report.syncBehind == true), tostring(report.syncReason or "none"), tostring(governance.revision or 0),
    tostring(governance.hash or "none"), tostring(report.baselineHash or "none"), tostring(authority.state or "unknown"),
    tostring(authority.coordinatorName or authority.coordinatorMemberKey or "none"), tostring(report.operationalPolicyRevision or 0),
    tostring(report.seasonCatalogRevision or 0), tostring(ledger.revision or 0), tostring(ledger.rootHash or "none"), tostring(ledger.epoch or "none")) .. suffix
end

---@doc.id sync.status
---@doc.category synchronization
---@doc.since 0.6.0
---@doc.changed 0.6.5
---@doc.audience player,officer,gm
---@doc.scope guild
---@doc.audit false
---@doc.help-key UI_HELP_SYNC_STATUS
---@doc.label-key DOC_SYNC_STATUS_LABEL
function Sync.GetStatus()
  local stateStartedAt = beginPeerStatusTiming()
  local state = ensure()
  local ready = transportReady() and Sync.transportRegistered == true
  local reasonStartedAt = beginPeerStatusTiming()
  local reasons = ready and Sync.GetSyncBehindReasons and Sync.GetSyncBehindReasons() or {}
  recordPeerStatusTiming("status-behind-reasons", reasonStartedAt)
  local result
  if not ready then
    result = { state = "SYNC_UNAVAILABLE", protocolState = state.protocolState }
  else
    result = { state = state.status or "SYNC_READY", protocolState = state.protocolState,
      syncBehind = state.syncBehind == true, reason = state.reason, reasons = reasons }
  end
  recordPeerStatusTiming("status-projection", stateStartedAt)
  return result
end
-- Compact status projection for read-only gates that need only scalar state.
-- Avoid copying mismatch details or constructing the described reason list.
function Sync.GetStatusSummary()
  local stateStartedAt = beginPeerStatusTiming()
  local readStartedAt = beginPeerStatusTiming()
  local state = statusReadState()
  recordPeerStatusTiming("status-summary-state-read", readStartedAt)
  local projectionStartedAt = beginPeerStatusTiming()
  local mismatches = type(state.addonVersionMismatches) == "table" and state.addonVersionMismatches or nil
  local mismatch = mismatches and mismatches[#mismatches]
  local ready = transportReady() and Sync.transportRegistered == true
  local result = {
    state = ready and (state.status or "SYNC_READY") or "SYNC_UNAVAILABLE",
    protocolState = state.protocolState,
    syncBehind = ready and state.syncBehind == true or false,
    reason = ready and state.reason or nil,
    lastAddonVersionMismatchReasonCode = mismatch and mismatch.reasonCode or nil,
  }
  recordPeerStatusTiming("status-summary-projection", projectionStartedAt)
  recordPeerStatusTiming("status-summary", stateStartedAt)
  return result
end
function Sync.GetSynchronizationStatus(dbOverride)
  local renderStartedAt = beginPeerStatusTiming()
  local governanceStartedAt = beginPeerStatusTiming()
  local governance = Dibs.Governance and Dibs.Governance.GetSynchronizationSummary
    and Dibs.Governance.GetSynchronizationSummary()
    or (Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState()) or {}
  recordPeerStatusTiming("synchronization-governance", governanceStartedAt)
  local catalogStartedAt = beginPeerStatusTiming()
  local catalog = Dibs.Seasons and Dibs.Seasons.GetCatalogSummary and Dibs.Seasons.GetCatalogSummary()
    or (Dibs.Seasons and Dibs.Seasons.GetCatalogState and Dibs.Seasons.GetCatalogState()) or {}
  recordPeerStatusTiming("synchronization-catalog", catalogStartedAt)
  local pending = tonumber(governance.pendingAwardProposals)
  if pending == nil then
    pending = 0
    local proposalsStartedAt = beginPeerStatusTiming()
    local proposals = Dibs.Governance and Dibs.Governance.GetAwardProposals and Dibs.Governance.GetAwardProposals() or {}
    for _, proposal in ipairs(proposals) do if proposal.status ~= "COMMITTED" then pending = pending + 1 end end
    recordPeerStatusTiming("synchronization-proposals", proposalsStartedAt)
  end
  local mismatchStartedAt = beginPeerStatusTiming()
  local syncState = statusReadState()
  local mismatches = type(syncState.protocolMismatches) == "table" and syncState.protocolMismatches or {}
  local lastProtocolMismatch = copy(mismatches[#mismatches])
  local versionMismatches = type(syncState.addonVersionMismatches) == "table" and syncState.addonVersionMismatches or {}
  local lastAddonVersionMismatch = copy(versionMismatches[#versionMismatches])
  recordPeerStatusTiming("synchronization-mismatches", mismatchStartedAt)
  local result = {
    governanceAdopted = governance.status == "GOVERNANCE_ADOPTED",
    operationalPolicyAdopted = Dibs.OperationalPolicy and Dibs.OperationalPolicy.IsAdopted
      and Dibs.OperationalPolicy.IsAdopted(dbOverride) == true,
    seasonCatalogRevision = tonumber(catalog.catalogRevision) or 0,
    pendingAwardProposals = pending,
    lastProtocolMismatch = lastProtocolMismatch,
    lastAddonVersionMismatch = lastAddonVersionMismatch,
  }
  recordPeerStatusTiming("synchronization-status", renderStartedAt)
  return result
end
---@doc.id sync.peer.status
---@doc.category synchronization
---@doc.since 0.6.5
---@doc.audience officer,gm
---@doc.scope guild
---@doc.audit false
---@doc.help-key UI_HELP_SYNC_PEER
---@doc.label-key DOC_SYNC_PEER_STATUS_LABEL
function Sync.GetPeerStatuses(rosterScope, options)
  local state, rows, now = ensure(), {}, time()
  local rosterStartedAt = beginPeerStatusTiming()
  options = type(options) == "table" and options or nil
  local roster = {}
  local groupCount = type(GetNumGroupMembers) == "function" and tonumber(GetNumGroupMembers()) or 0
  local inRaid = type(IsInRaid) == "function" and IsInRaid() == true
  local scope = type(rosterScope) == "string" and string.upper(rosterScope) or nil
  local useGroup = scope == "PARTY" or scope == "RAID" or scope == "GROUP"
  local useGuild = scope == "GUILD"
  if scope == nil then
    useGroup = groupCount > 0 and type(UnitFullName) == "function"
    useGuild = not useGroup
  end
  local matchingGroup = (scope == "PARTY" and groupCount > 0 and not inRaid)
    or (scope == "RAID" and groupCount > 0 and inRaid)
    or (scope == "GROUP" and groupCount > 0)
    or (scope == nil and useGroup)
  if useGroup and matchingGroup and type(UnitFullName) == "function" then
    for index = 1, groupCount do
      local unit = inRaid and ("raid" .. index) or (index == 1 and "player" or "party" .. (index - 1))
      local name, realm = UnitFullName(unit)
      if type(canaccessvalue) == "function" then
        if canaccessvalue(name) then
          if name then
            local memberName = tostring(name)
            if canaccessvalue(realm) then
              if realm and realm ~= "" then memberName = memberName .. "-" .. tostring(realm) end
            end
            local connected = type(UnitIsConnected) ~= "function" or UnitIsConnected(unit) == true
            roster[#roster + 1] = { name = memberName, online = connected, rankIndex = 0 }
          end
        end
      else
        if not name and type(UnitName) == "function" then name, realm = UnitName(unit) end
        if name then
          local connected = type(UnitIsConnected) ~= "function" or UnitIsConnected(unit) == true
          roster[#roster + 1] = { name = realm and realm ~= "" and (name .. "-" .. realm) or name, online = connected, rankIndex = 0 }
        end
      end
    end
  elseif useGuild and type(GetNumGuildMembers) == "function" and type(GetGuildRosterInfo) == "function" then
    local rosterCached = false
    local identity = Dibs.Identity
    local getRoster = identity and (identity.GetRosterSnapshot or identity.GetRosterMembers)
    if type(getRoster) == "function" then
      local ok, members = pcall(getRoster)
      if ok and type(members) == "table" then
        rosterCached = true
        roster = members
      end
    end
    if not rosterCached then
      local okCount, memberCount = pcall(GetNumGuildMembers, true)
      if not okCount then return rows end
      for index = 1, tonumber(memberCount) or 0 do
        local ok, name, _, rankIndex, _, _, _, _, _, online = pcall(GetGuildRosterInfo, index)
        if ok and type(name) == "string" and name ~= "" then
          roster[#roster + 1] = { name = name, online = online == true or online == 1 or online == "1", rankIndex = rankIndex }
        end
      end
    end
  end
  recordPeerStatusTiming("peer-roster-source", rosterStartedAt)
  local pageInfo
  local filteringStartedAt = beginPeerStatusTiming()
  if options then
    local query = string.lower(tostring(options.query or ""))
    local candidates = {}
    for _, entry in ipairs(roster) do
      local name = tostring(entry.name or entry.displayName or "")
      local rankName = tostring(entry.rankName or "")
      if name ~= "" and (query == "" or string.find(string.lower(name), query, 1, true)
        or string.find(string.lower(rankName), query, 1, true)) then
        local memberKey = entry.memberKey or string.lower(name)
        local peer = state.peers[memberKey]
        local lastSeen = peer and tonumber(peer.lastSeenAt or peer.at) or 0
        local detected = lastSeen > 0 and now - lastSeen <= (HEARTBEAT * 3)
        candidates[#candidates + 1] = {
          entry = entry,
          sortName = string.lower(tostring(entry.displayName or name)),
          online = entry.online == true or detected,
        }
      end
    end
    table.sort(candidates, function(first, second)
      if first.online ~= second.online then return first.online end
      return first.sortName < second.sortName
    end)
    local totalMatches = #candidates
    local pageSize = math.max(5, math.min(50, math.floor(tonumber(options.pageSize) or 20)))
    local totalPages = math.max(1, math.ceil(totalMatches / pageSize))
    local page = math.max(1, math.min(totalPages, math.floor(tonumber(options.page) or 1)))
    local firstIndex = (page - 1) * pageSize + 1
    roster = {}
    for index = firstIndex, math.min(totalMatches, firstIndex + pageSize - 1) do
      roster[#roster + 1] = candidates[index].entry
    end
    pageInfo = { page = page, pageSize = pageSize, totalMatches = totalMatches, totalPages = totalPages }
  end
  recordPeerStatusTiming("peer-filter-sort-page", filteringStartedAt)
  -- These local projections can hash or copy ledger-sized data. Build them
  -- once per roster render, not once for every guild or group member.
  local digestStartedAt = beginPeerStatusTiming()
  local localDigests = #roster > 0 and localSyncDigests(options and options.db) or {}
  local memberSnapshotStartedAt = beginPeerStatusTiming()
  local localMember = #roster > 0 and (localSnapshot() or {}) or {}
  recordPeerStatusTiming("local-member-snapshot", memberSnapshotStartedAt)
  local baselineHashStartedAt = beginPeerStatusTiming()
  local localBaselineHash
  if #roster > 0 and Dibs.HistoricalBaseline then
    if Dibs.HistoricalBaseline.GetBaselineHash then
      localBaselineHash = Dibs.HistoricalBaseline.GetBaselineHash(options and options.db)
    elseif Dibs.HistoricalBaseline.GetBaseline then
      local localBaseline = Dibs.HistoricalBaseline.GetBaseline()
      localBaselineHash = localBaseline and localBaseline.legacyBaselineHash
    end
  end
  recordPeerStatusTiming("local-baseline-hash", baselineHashStartedAt)
  local activeLedgerStartedAt = beginPeerStatusTiming()
  local activeLedgerId = Dibs.MultiLedger and Dibs.MultiLedger.GetActiveLedgerId
    and Dibs.MultiLedger.GetActiveLedgerId(options and options.db) or "guild-primary"
  recordPeerStatusTiming("peer-active-ledger-id", activeLedgerStartedAt)
  local predibKey = activeLedgerId == "guild-primary" and "PREDIB_INDEX"
    or ("PREDIB_INDEX:" .. tostring(activeLedgerId))
  recordPeerStatusTiming("local-digest-projection", digestStartedAt)
  local projectionStartedAt = beginPeerStatusTiming()
  for _, rosterEntry in ipairs(roster) do
    local name = rosterEntry.name or rosterEntry.displayName
    local online, rankIndex = rosterEntry.online, rosterEntry.rankIndex
    if type(name) == "string" and name ~= "" then
      -- The shared guild-roster snapshot already carries canonical identity
      -- fields. Reuse them instead of resolving every visible row again.
      local resolved = type(rosterEntry.memberKey) == "string" and rosterEntry.memberKey ~= ""
        and rosterEntry or member(name)
      local memberKey = resolved and resolved.memberKey or string.lower(name)
      local peer = state.peers[memberKey]
      local lastSeen = peer and tonumber(peer.lastSeenAt or peer.at) or 0
      local detected = lastSeen > 0 and now - lastSeen <= (HEARTBEAT * 3)
      local rosterOnline = online == true
      local effectiveOnline = rosterOnline or detected
      local compatibility, compatibilityReason = nil, "REMOTE_ADDON_VERSION_UNKNOWN"
      if peer and peer.addonVersion then compatibility, compatibilityReason = Sync.GetAddonVersionCompatibility(peer.addonVersion) end
      local syncStatus = "Unknown"
      local compared, behind, localBehind = 0, false, false
      for entityType, localDigest in pairs(localDigests) do
        local remoteDigest = peer and peer.entities and peer.entities[entityType]
        if remoteDigest then
          compared = compared + 1
          if remoteDigest.contentHash == localDigest.contentHash and tonumber(remoteDigest.revision) == tonumber(localDigest.revision) then
            -- This entity is converged.
          elseif (tonumber(remoteDigest.revision) or 0) < (tonumber(localDigest.revision) or 0) then
            behind = true
          else
            localBehind = true
          end
        end
      end
      if compared > 0 then syncStatus = behind and "Behind" or (localBehind and "Local behind" or "Up to date") end
      local remoteCatalog = peer and peer.entities and peer.entities.SEASON_CATALOG or {}
      local remotePolicy = peer and peer.entities and peer.entities.OPERATIONAL_POLICY or {}
      local remoteGovernance = peer and peer.entities and peer.entities.GOVERNANCE or {}
      local remotePredib = peer and peer.entities and peer.entities[predibKey] or {}
      local remoteVault = peer and peer.entities and peer.entities.VAULT_INDEX or {}
      local remoteLedger = peer and peer.entities and peer.entities.LEDGER or {}
      local isLocalMember = memberKey == localMember.memberKey
        or string.lower(tostring(resolved and resolved.displayName or name)) == string.lower(tostring(localMember.displayName or ""))
      local baselineStatus = "Unknown"
      if isLocalMember then
        baselineStatus = localBaselineHash and "Present" or "Missing"
      elseif peer and peer.baselineHash then
        baselineStatus = "Present"
      elseif peer and peer.transferAck and peer.transferAck.result == "APPLIED" then
        baselineStatus = "Present"
      elseif peer and peer.transferAck and peer.transferAck.result == "STARTED" then
        local receivedChunks = tonumber(peer.transferAck.receivedChunks) or 0
        local chunkCount = tonumber(peer.transferAck.chunkCount) or 0
        baselineStatus = chunkCount > 0 and string.format("Applying %d/%d", receivedChunks, chunkCount) or "Applying"
      elseif peer and peer.transferAck and peer.transferAck.result == "REJECTED" then
        local receivedChunks = tonumber(peer.transferAck.receivedChunks) or 0
        local chunkCount = tonumber(peer.transferAck.chunkCount) or 0
        local progress = chunkCount > 0 and string.format(" %d/%d", receivedChunks, chunkCount) or ""
        baselineStatus = "Rejected/" .. tostring(peer.transferAck.reasonCode or "unknown") .. progress
      elseif peer and peer.syncProbe then
        baselineStatus = "Missing"
      end
      if isLocalMember then syncStatus = Sync.IsSyncBehind() and "Behind" or "Up to date" end
      rows[#rows + 1] = {
        playerName = resolved and resolved.displayName or name,
        isLocal = isLocalMember == true,
        rankIndex = tonumber(rankIndex) or 0,
        online = effectiveOnline,
        rosterOnline = rosterOnline,
        presenceSource = detected and (rosterOnline and "ROSTER_AND_ADDON" or "ADDON_HEARTBEAT") or (rosterOnline and "ROSTER" or "NONE"),
        addonDetected = detected,
        addonStatus = detected and "Detected" or "No response",
        addonVersion = detected and (peer.addonVersion or "unknown") or "unknown",
        compatibility = compatibility == true and "Compatible" or (compatibility == false and "Update required" or "Unknown"),
        compatibilityReason = compatibilityReason,
        syncStatus = syncStatus,
        baselineStatus = baselineStatus,
        seasonCatalogRevision = tonumber(remoteCatalog.revision) or 0,
        policyRevision = tonumber(remotePolicy.revision) or 0,
        governanceRevision = tonumber(remoteGovernance.revision) or 0,
        predibRevision = tonumber(remotePredib.revision) or 0,
        vaultRevision = tonumber(remoteVault.revision) or 0,
        ledgerRevision = tonumber(remoteLedger.revision) or 0,
        lastSeenAt = lastSeen,
        protocolState = peer and peer.protocolState or "Unknown",
      }
    end
  end
  recordPeerStatusTiming("peer-row-projection", projectionStartedAt)
  local sortingStartedAt = beginPeerStatusTiming()
  table.sort(rows, function(a, b)
    if a.online ~= b.online then return a.online end
    return string.lower(a.playerName) < string.lower(b.playerName)
  end)
  recordPeerStatusTiming("peer-row-sort", sortingStartedAt)
  return rows, pageInfo or { page = 1, pageSize = #rows, totalMatches = #rows, totalPages = 1 }
end
local SYNC_BEHIND_REASON_TEXT = {
  LEDGER_GAP = "Guild ledger commits are missing on this client.",
  LEDGER_ENFORCEMENT_MISSING = "Another client uses the guild ledger, but guild rules are not active here yet.",
  CANONICAL_ROOT_CONFLICT = "The local guild ledger does not match the coordinator ledger.",
  LEDGER_DETAIL_FORBIDDEN = "A peer sent ledger details that are not allowed in a digest.",
  GOVERNANCE_PARENT_MISSING = "Guild governance records are missing on this client.",
  POLICY_PARENT_MISSING = "Guild policy history is missing on this client.",
  POLICY_CHAIN_MISSING = "A newer guild policy revision is missing on this client.",
  SEASON_CATALOG_PARENT_MISSING = "A newer season catalog revision is missing on this client.",
  POLICY_CONFLICT = "Guild policy histories disagree. Review is required; recovery cannot overwrite a conflicting history.",
  SEASON_CATALOG_CONFLICT = "Season catalog histories disagree. Review is required; recovery cannot overwrite a conflicting history.",
  GOVERNANCE_CONFLICT = "Guild governance histories disagree. Review is required; recovery cannot overwrite a conflicting history.",
  AUTHORITY_DETAIL_MISSING = "The current coordinator authority record is missing on this client.",
  MISSING_DETAIL = "Pre-Dibs request details are missing on this client.",
  VAULT_DETAIL_MISSING = "Vault acquisition details are missing on this client.",
  SYNC_BEHIND = "This client is behind for an unrecorded reason.",
}
-- Reasons that a recheck may clear once the tracked target is resolved.  Other
-- reasons cannot be verified locally and stay until resolved or force-cleared.
local VERIFIABLE_BEHIND_REASONS = {
  LEDGER_GAP = true, LEDGER_ENFORCEMENT_MISSING = true, GOVERNANCE_PARENT_MISSING = true,
  POLICY_PARENT_MISSING = true, POLICY_CHAIN_MISSING = true, SEASON_CATALOG_PARENT_MISSING = true,
  AUTHORITY_DETAIL_MISSING = true, MISSING_DETAIL = true, VAULT_DETAIL_MISSING = true,
}
local function behindReasons(state)
  if type(state.behindReasons) ~= "table" then state.behindReasons = {} end
  if state.syncBehind == true and next(state.behindReasons) == nil then
    state.behindReasons[state.reason or "SYNC_BEHIND"] = { markedAt = time(), firstMarkedAt = time() }
  end
  return state.behindReasons
end
local function latestBehindReason(reasons)
  local latestCode, latestAt
  for code, entry in pairs(reasons) do
    local at = tonumber(type(entry) == "table" and entry.markedAt) or 0
    if not latestCode or at > latestAt or (at == latestAt and code < latestCode) then latestCode, latestAt = code, at end
  end
  return latestCode
end
function Sync.IsSyncBehind(dbOverride) return ensure(dbOverride).syncBehind == true end
function Sync.MarkSyncBehind(reason)
  local state = ensure(); local code = reason or "SYNC_BEHIND"
  local reasons = behindReasons(state)
  local existing = reasons[code]
  reasons[code] = { markedAt = time(), firstMarkedAt = existing and existing.firstMarkedAt or time() }
  state.syncBehind, state.reason = true, code
  return status("SYNC_BEHIND", { reasonCode = code })
end
function Sync.ClearSyncBehind()
  local state = ensure(); state.syncBehind, state.reason, state.behindReasons = false, nil, {}; return status("SYNC_READY")
end
local function clearSyncBehindReasons(...)
  local state = ensure()
  if state.syncBehind ~= true then return false end
  local reasons, changed = behindReasons(state), false
  for index = 1, select("#", ...) do
    local code = select(index, ...)
    if code and reasons[code] then reasons[code] = nil; changed = true end
  end
  if next(reasons) == nil then Sync.ClearSyncBehind(); return true end
  state.reason = latestBehindReason(reasons)
  return changed
end
function Sync.DescribeSyncBehindReason(code)
  local key = tostring(code or "SYNC_BEHIND")
  local L = Dibs.L or {}
  return L["SYNC_BEHIND_REASON_" .. key] or SYNC_BEHIND_REASON_TEXT[key] or (SYNC_BEHIND_REASON_TEXT.SYNC_BEHIND .. " (" .. key .. ")")
end
function Sync.GetSyncBehindReasons()
  local state = ensure()
  local rows = {}
  if state.syncBehind ~= true then return rows end
  for code, entry in pairs(behindReasons(state)) do
    rows[#rows + 1] = {
      code = code, markedAt = tonumber(type(entry) == "table" and entry.markedAt) or 0,
      firstMarkedAt = tonumber(type(entry) == "table" and entry.firstMarkedAt) or 0,
      verifiable = VERIFIABLE_BEHIND_REASONS[code] == true,
      description = Sync.DescribeSyncBehindReason(code),
    }
  end
  table.sort(rows, function(a, b) return a.code < b.code end)
  return rows
end
local function requestAwardCommitBatch(recipient, ledgerTarget, firstSequence, lastSequence)
  local requests = {}
  local finalSequence = math.min(tonumber(lastSequence) or firstSequence, firstSequence + LEDGER_BATCH_SIZE - 1)
  for sequence = firstSequence, finalSequence do
    requests[#requests + 1] = {
      entityType = "AWARD_COMMIT",
      entityId = tostring(ledgerTarget.epoch) .. ":" .. tostring(sequence),
      revision = sequence, ledgerId = ledgerTarget.ledgerId,
    }
  end
  if #requests == 0 then return false, firstSequence - 1 end
  local sent, reason = sendDetailFetch(requests, recipient)
  return sent, sent and finalSequence or (firstSequence - 1), reason
end
local function rememberVaultRequests(requests, target)
  local state = ensure()
  for _, request in ipairs(requests or {}) do
    if type(request.acquisitionId) == "string" and type(target) == "string" then
      local current = state.vaultPending[request.acquisitionId] or { attempts = 0 }
      current.revision, current.contentHash, current.target = request.revision, request.contentHash, target
      state.vaultPending[request.acquisitionId] = current
    end
  end
end
local function clearVaultRequest(acquisitionId)
  ensure().vaultPending[acquisitionId] = nil
end
local function retryableRecords(records, maximum, attemptsOf)
  local retryable = {}
  for key, record in pairs(records or {}) do
    if (tonumber(attemptsOf(record)) or 0) < maximum then
      retryable[key] = record
    end
  end
  return retryable
end
local function retryVaultRequests()
  local state, grouped = ensure(), {}
  local pending = retryableRecords(state.vaultPending, MAX_VAULT_RETRIES, function(request) return request.attempts end)
  for acquisitionId, request in pairs(pending) do
    local target = request.target
    grouped[target] = grouped[target] or {}
    grouped[target][#grouped[target] + 1] = { acquisitionId = acquisitionId, revision = request.revision, contentHash = request.contentHash }
  end
  for target, requests in pairs(grouped) do
    if Sync.Send(Sync.BuildVaultFetch(requests), "WHISPER", target) then
      for _, request in ipairs(requests) do state.vaultPending[request.acquisitionId].attempts = (state.vaultPending[request.acquisitionId].attempts or 0) + 1 end
    end
  end
end
local function ledgerSyncState(state, ledgerId)
  state.ledgerSync = state.ledgerSync or {}
  state.ledgerSync[ledgerId] = state.ledgerSync[ledgerId] or {}
  return state.ledgerSync[ledgerId]
end
local function requestLedgerBatch(sender, state, target, localLast)
  local syncState = ledgerSyncState(state, target.ledgerId)
  local requestedThrough = tonumber(syncState.requestedThrough) or 0
  local requestedAt = tonumber(syncState.requestAt) or 0
  if localLast < requestedThrough and time() - requestedAt < HEARTBEAT then return false end
  local sent, through = requestAwardCommitBatch(sender, target, localLast + 1, target.lastSeq)
  if sent then
    syncState.requestedThrough = through
    syncState.requestAt = time()
    if target.ledgerId == "guild-primary" then
      state.ledgerRequestedThrough, state.ledgerRequestAt = through, syncState.requestAt
    end
  end
  return sent
end
local function clearResolvedLedgerGap(sender, ledgerId)
  local state = ensure()
  local syncState = state.ledgerSync and state.ledgerSync[ledgerId]
  local target = syncState and syncState.target
  if not target or not (Dibs.Ledger and Dibs.Ledger.GetCanonicalState) then return false end
  local current = Dibs.Ledger.GetCanonicalState(target.ledgerId)
  if tonumber(current.epoch) ~= tonumber(target.epoch) then return false end
  local localLast = tonumber(current.nextSeq or 1) - 1
  if localLast < tonumber(target.lastSeq) then
    requestLedgerBatch(sender, state, target, localLast)
    return false
  end
  if localLast == tonumber(target.lastSeq) and current.rootHash == target.rootHash then
    syncState = ledgerSyncState(state, target.ledgerId)
    syncState.target, syncState.requestedThrough, syncState.requestAt = nil, nil, nil
    if target.ledgerId == "guild-primary" then
      state.ledgerTarget, state.ledgerRequestedThrough, state.ledgerRequestAt = nil, nil, nil
    end
    Sync.AnnounceLedgerDigest(target.ledgerId)
    local pending = false
    for _, entry in pairs(state.ledgerSync or {}) do
      if entry.target then pending = true; break end
    end
    if not pending then clearSyncBehindReasons("LEDGER_GAP") end
    return true
  end
  Sync.MarkSyncBehind("CANONICAL_ROOT_CONFLICT")
  return false
end
local function requestNextRevision(entityType, target, currentRevision)
  local revision = (tonumber(currentRevision) or 0) + 1
  if not target or not target.source or revision > tonumber(target.revision) then return false end
  return sendDetailFetch({ { entityType = entityType, entityId = tostring(revision), revision = revision,
    contentHash = revision == tonumber(target.revision) and target.contentHash or nil } }, target.source)
end
local function rememberChainTarget(key, revision, contentHash, source, conflictReason)
  local state = ensure()
  local existing = state[key]
  if existing and tonumber(existing.revision) > tonumber(revision) then return existing end
  if existing and tonumber(existing.revision) == tonumber(revision) and existing.contentHash ~= contentHash then
    Sync.MarkSyncBehind(conflictReason)
    return nil
  end
  state[key] = { revision = revision, contentHash = contentHash, source = source }
  return state[key]
end
local function clearResolvedPolicyGap(requestMore)
  local state = ensure(); local target = state.policyTarget
  if not target or not (Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetState) then return false end
  local current = Dibs.OperationalPolicy.GetState()
  if tonumber(current.policyRevision) == tonumber(target.revision) and current.hash == target.contentHash then
    state.policyTarget = nil
    clearSyncBehindReasons("POLICY_PARENT_MISSING", "POLICY_CHAIN_MISSING")
    return true
  end
  if requestMore then requestNextRevision("OPERATIONAL_POLICY", target, current.policyRevision) end
  return false
end
local function clearResolvedSeasonCatalogGap(requestMore)
  local state, target = ensure(), ensure().seasonCatalogTarget
  if not target or not (Dibs.Seasons and Dibs.Seasons.GetCatalogState) then return false end
  local current = Dibs.Seasons.GetCatalogState()
  if tonumber(current.catalogRevision) == tonumber(target.revision) and current.hash == target.contentHash then
    state.seasonCatalogTarget = nil
    clearSyncBehindReasons("SEASON_CATALOG_PARENT_MISSING")
    return true
  end
  if requestMore then requestNextRevision("SEASON_CATALOG", target, current.catalogRevision) end
  return false
end
local function clearResolvedGovernanceGap()
  local governanceState = Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState() or {}
  local target = ensure().governanceTarget
  if not target or (tonumber(governanceState.revision) or 0) >= (tonumber(target.revision) or 0) then
    ensure().governanceTarget = nil
    clearSyncBehindReasons("GOVERNANCE_PARENT_MISSING")
  end
  if Dibs.Governance and Dibs.Governance.IsV2Enforced and Dibs.Governance.IsV2Enforced() then
    clearSyncBehindReasons("LEDGER_ENFORCEMENT_MISSING")
  end
end

-- Corroborated relay: when no authorized writer is online, a revision chain may be
-- adopted from ordinary members once RELAY_QUORUM distinct roster members announce
-- the same revision and hash. Relayed records are staged until the whole chain links
-- from local state to that hash, then applied with the original author's authority.
local RELAY_QUORUM, RELAY_TTL = 3, 900
local RELAY_CHAINS = {
  GOVERNANCE = {
    target = "governanceTarget", revisionField = "governanceRevision",
    parentReason = "GOVERNANCE_PARENT_MISSING", conflictReason = "GOVERNANCE_CONFLICT",
    current = function()
      local state = Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState() or {}
      return tonumber(state.revision) or 0, state.hash
    end,
    hash = function(record) return Dibs.Governance and Dibs.Governance.CalculateContentHash and Dibs.Governance.CalculateContentHash(record) end,
    apply = function(record) return Dibs.Governance.ApplyRecord(record, record.authorNameRealm) end,
    resolved = function() clearResolvedGovernanceGap() end,
  },
  OPERATIONAL_POLICY = {
    target = "policyTarget", revisionField = "policyRevision",
    parentReason = "POLICY_CHAIN_MISSING", conflictReason = "POLICY_CONFLICT",
    current = function()
      local state = Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetState and Dibs.OperationalPolicy.GetState() or {}
      return tonumber(state.policyRevision) or 0, state.hash
    end,
    hash = function(record) return Dibs.OperationalPolicy and Dibs.OperationalPolicy.CalculateContentHash and Dibs.OperationalPolicy.CalculateContentHash(record) end,
    apply = function(record) return Dibs.OperationalPolicy.ApplyRecord(record, record.authorNameRealm) end,
    resolved = function() clearResolvedPolicyGap(true) end,
  },
  SEASON_CATALOG = {
    target = "seasonCatalogTarget", revisionField = "catalogRevision",
    parentReason = "SEASON_CATALOG_PARENT_MISSING", conflictReason = "SEASON_CATALOG_CONFLICT",
    current = function()
      local state = Dibs.Seasons and Dibs.Seasons.GetCatalogState and Dibs.Seasons.GetCatalogState() or {}
      return tonumber(state.catalogRevision) or 0, state.hash
    end,
    hash = function(record) return Dibs.Seasons and Dibs.Seasons.CalculateCatalogHash and Dibs.Seasons.CalculateCatalogHash(record) end,
    apply = function(record) return Dibs.Seasons.ApplyCatalog(record, record.authorNameRealm) end,
    resolved = function() clearResolvedSeasonCatalogGap(true) end,
  },
}
local function relayRuntime()
  Dibs.runtime = Dibs.runtime or {}
  Dibs.runtime.syncRelay = Dibs.runtime.syncRelay or { votes = {}, staging = {} }
  local runtime, now = Dibs.runtime.syncRelay, time()
  for key, voters in pairs(runtime.votes) do
    for memberKey, at in pairs(voters) do if at + RELAY_TTL < now then voters[memberKey] = nil end end
    if next(voters) == nil then runtime.votes[key] = nil end
  end
  boundMap(runtime.votes, 64)
  return runtime
end
local function relayVoters(entityType, revision, contentHash)
  return relayRuntime().votes[trustedDigestKey(entityType, revision, contentHash)] or {}
end
local function requestRelayRevision(entityType, target, revision)
  if entityType == "GOVERNANCE" then
    return sendDetailFetch({ { entityType = "GOVERNANCE", entityId = tostring(target.revision), revision = target.revision,
      contentHash = target.contentHash, parentRevision = math.max(0, (tonumber(revision) or 1) - 1) } }, target.source)
  end
  return sendDetailFetch({ { entityType = entityType, entityId = tostring(revision), revision = revision,
    contentHash = revision == tonumber(target.revision) and target.contentHash or nil } }, target.source)
end
-- Handles a revision digest from a member who is not an authorized writer.
local function receiveRelayDigest(entityType, message, resolved, rejectReason)
  local chain = RELAY_CHAINS[entityType]
  local runtime = relayRuntime()
  local key = trustedDigestKey(entityType, message.revision, message.contentHash)
  runtime.votes[key] = runtime.votes[key] or {}
  runtime.votes[key][resolved.memberKey] = time()
  local count = 0
  for _ in pairs(runtime.votes[key]) do count = count + 1 end
  if count < RELAY_QUORUM then return false, rejectReason or "RELAY_CORROBORATION_PENDING" end
  local currentRevision, currentHash = chain.current()
  local revision = tonumber(message.revision)
  if revision == currentRevision then
    if message.contentHash ~= currentHash then
      Sync.MarkSyncBehind(chain.conflictReason)
      return false, chain.conflictReason
    end
    return true, "RELAY_CURRENT"
  end
  if revision < currentRevision then return true, "RELAY_STALE_IGNORED" end
  local state = ensure()
  local existing = state[chain.target]
  if existing and not existing.relay and tonumber(existing.revision) >= revision then return true, "RELAY_WRITER_TARGET_KEPT" end
  local target = rememberChainTarget(chain.target, revision, message.contentHash, resolved.displayName, chain.conflictReason)
  if not target then return false, chain.conflictReason end
  if target.revision == revision and target.contentHash == message.contentHash then
    target.relay = true
    target.source = resolved.displayName
    target.parentHash = message.parentHash
  end
  Sync.MarkSyncBehind(chain.parentReason)
  requestRelayRevision(entityType, target, currentRevision + 1)
  return true, "RELAY_DETAIL_REQUESTED"
end
local function relayChainAllows(entityType, revision, resolved)
  local chain = RELAY_CHAINS[entityType]
  local target = chain and ensure()[chain.target]
  if not target or not target.relay then return false end
  local currentRevision = chain.current()
  revision = tonumber(revision)
  if not revision or revision <= currentRevision or revision > tonumber(target.revision) then return false end
  return relayVoters(entityType, target.revision, target.contentHash)[resolved.memberKey] ~= nil
end
local function stageRelayRecord(entityType, payload, transfer)
  local chain = RELAY_CHAINS[entityType]
  local state, runtime = ensure(), relayRuntime()
  local target = state[chain.target]
  if not target or not target.relay then return false, "RELAY_TARGET_MISSING" end
  local revision = tonumber(payload[chain.revisionField])
  if revision ~= tonumber(transfer.revision) or payload.contentHash ~= transfer.contentHash
    or chain.hash(payload) ~= payload.contentHash then return false, "CONTENT_HASH_MISMATCH" end
  local staging = runtime.staging[entityType]
  if not staging or staging.targetHash ~= target.contentHash then
    staging = { targetHash = target.contentHash, records = {} }
    runtime.staging[entityType] = staging
  end
  staging.records[revision] = copy(payload)
  local currentRevision, previousHash = chain.current()
  previousHash = previousHash or "GENESIS"
  local finalRevision = tonumber(target.revision)
  for nextRevision = currentRevision + 1, finalRevision do
    local record = staging.records[nextRevision]
    if not record then
      -- Governance detail returns the whole chain, so one fetch per target suffices.
      local requestKey = entityType == "GOVERNANCE" and finalRevision or nextRevision
      staging.requestedAt = staging.requestedAt or {}
      if not staging.requestedAt[requestKey] or staging.requestedAt[requestKey] + 60 < time() then
        staging.requestedAt[requestKey] = time()
        requestRelayRevision(entityType, target, nextRevision)
      end
      return true, "RELAY_CHAIN_STAGED"
    end
    if record.parentHash ~= previousHash then
      runtime.staging[entityType] = nil
      return false, "RELAY_CHAIN_MISMATCH"
    end
    previousHash = record.contentHash
  end
  runtime.staging[entityType] = nil
  if previousHash ~= target.contentHash then return false, "RELAY_CHAIN_MISMATCH" end
  for nextRevision = currentRevision + 1, finalRevision do
    local ok, reason = chain.apply(staging.records[nextRevision])
    if not ok then
      if reason == chain.conflictReason then Sync.MarkSyncBehind(reason) end
      return false, reason
    end
  end
  chain.resolved()
  return true, "RELAY_CHAIN_ADOPTED"
end
function Sync.GetProtocolState() return ensure().protocolState end
---@doc.id sync.protocol.state
---@doc.category protocol
---@doc.since 0.6.0
---@doc.audience developer
---@doc.scope guild
---@doc.audit false
---@doc.help-key UI_HELP_TECHNICAL_DETAILS
---@doc.label-key DOC_SYNC_PROTOCOL_STATE_LABEL
---@doc.reference-key DOC_SYNC_PROTOCOL_STATE_REFERENCE
function Sync.SetProtocolState(state, governanceApproved)
  -- B04 represents state but cannot independently enable enforcement.
  if state == "V2_ENFORCED" and governanceApproved ~= true then return false, "GOVERNANCE_CUTOVER_REQUIRED" end
  if state ~= "LEGACY_LOCAL" and state ~= "CUTOVER_PREPARED" and state ~= "V2_ENFORCED" then return false, "INVALID_PROTOCOL_STATE" end
  ensure().protocolState = state; return true, state
end
function Sync.CanEnforceV2(writers, dbOverride)
  local localMember = localSnapshot(); if not localMember then return false, "ROSTER_UNAVAILABLE" end
  writers = writers or { localMember.displayName }
  if type(writers) ~= "table" or #writers < 1 or #writers > 32 then return false, "WRITER_COMPATIBILITY_REQUIRED" end
  local state = ensure(dbOverride)
  for _, writer in ipairs(writers) do
    local resolved, reason = member(writer); if not resolved then return false, reason end
    if resolved.memberKey ~= localMember.memberKey then
      local peer = state.peers[resolved.memberKey]
      if not peer or not peer.protocol or tonumber(peer.protocol.major) ~= MAJOR or not (peer.protocol.capabilities or {}).authoritySignals then
        return false, "WRITER_COMPATIBILITY_REQUIRED"
      end
    end
  end
  return true, "WRITER_COMPATIBLE"
end

function Sync.BuildEnvelope(message)
  local snapshot = localSnapshot(); if not snapshot then return nil, "ROSTER_UNAVAILABLE" end
  message = copy(message or {}); if not TYPES[message.type] then return nil, "INVALID_MESSAGE_TYPE" end
  message.protocol = { major = MAJOR, minor = MINOR,
    operationProtocolVersion = Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED == true and 1 or 0,
    capabilities = { digest = true, guildDetail = true, whisperDetail = true,
    requestTombstones = true, ledgerDigestOnly = true, ledgerScopedCommits = true, authoritySignals = true, requestDelivery = true,
    guildRepair = true, ledgerOperationCommit = Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED == true,
    ledgerOperationProposal = Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED == true,
    ledgerOperationProtocol = Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED == true and 1 or 0 } }
  message.messageId = message.messageId or Dibs.NewId("v2msg")
  message.guildKey = Dibs.GetGuildKey(); message.senderNameRealm = snapshot.displayName; message.senderMemberKey = snapshot.memberKey
  message.addonVersion = Dibs.VERSION
  return message
end
function Sync.Send(message, channel, target)
  if Dibs.IndependentRaid and Dibs.IndependentRaid.IsSessionActive and Dibs.IndependentRaid.IsSessionActive() then
    local effChannel = channel or "GUILD"
    if effChannel == "GUILD" or effChannel == "OFFICER" or effChannel == "RAID" then
      return false, "INDEPENDENT_RAID_ACTIVE"
    end
  end
  if type(message) ~= "table" then return false, "INVALID_SYNC_MESSAGE" end
  if message.type == "TRANSFER_BEGIN" then
    if not detailChannel(message.entityType) then return false, "UNSUPPORTED_ENTITY" end
    if (message.entityType == "LEDGER_OPERATION_COMMIT" or message.entityType == "LEDGER_OPERATION_PROPOSAL")
      and Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED ~= true then
      return false, "CANONICAL_DISPUTE_OPERATIONS_DISABLED"
    end
  end
  if Sync.ContainsForbiddenLiveLootData and Sync.ContainsForbiddenLiveLootData(message) then return false, "FORBIDDEN_LIVE_LOOT_DATA" end
  if not transportReady() then status("SYNC_UNAVAILABLE"); return false, "SYNC_UNAVAILABLE" end
  local envelope, reason = Sync.BuildEnvelope(message); if not envelope then return false, reason end
  channel = channel or "GUILD"
  local isChannelTest = message.type == "CHANNEL_TEST" or message.type == "CHANNEL_TEST_ACK"
  if channel ~= "GUILD" and channel ~= "WHISPER" and not (isChannelTest and CHANNEL_TEST_CHANNELS[channel]) then
    return false, "INVALID_SYNC_CHANNEL"
  end
  if channel == "WHISPER" then
    local targetName = trim(target)
    if not targetName or targetName == "" or #target > 96 then return false, "INVALID_WHISPER_TARGET" end
    local recipient, targetReason = member(targetName)
    if not recipient then return false, targetReason end
    if recipient.online ~= true then return false, "WHISPER_TARGET_OFFLINE" end
    -- Display realms may contain spaces; addon whispers require a qualified wire name.
    target = recipient.displayName:gsub("%s+", "")
  end
  if isChannelTest and channel == "CHANNEL"
    and (not finiteInteger(target) or tonumber(target) < 1) then return false, "INVALID_CUSTOM_CHANNEL_ID" end
  Sync.TraceOutgoing(channel, target, message.type)
  local sent, sendReason = Dibs.Ace3.SendComm("DIBS", envelope, channel, target, "BULK")
  if not sent then
    if sendReason and sendReason ~= "SYNC_UNAVAILABLE" then return false, sendReason end
    status("SYNC_UNAVAILABLE"); return false, "SYNC_UNAVAILABLE"
  end
  local state = ensure()
  if state.status == "SYNC_UNAVAILABLE" then
    status(state.syncBehind and "SYNC_BEHIND" or "SYNC_READY")
  end
  return true, envelope.messageId
end

local function channelTestState()
  Dibs.runtime = Dibs.runtime or {}
  Dibs.runtime.channelTests = Dibs.runtime.channelTests or { pending = {}, results = {}, responded = {}, peerWindows = {} }
  local state = Dibs.runtime.channelTests
  state.pending, state.results, state.responded, state.peerWindows = state.pending or {}, state.results or {},
    state.responded or {}, state.peerWindows or {}
  return state
end

local function markChannelTestResponded(senderKey, testId)
  local state, now = channelTestState(), time()
  for key, respondedAt in pairs(state.responded) do
    if now - (tonumber(respondedAt) or now) >= CHANNEL_TEST_RESPONSE_TTL then state.responded[key] = nil end
  end
  local key = tostring(senderKey) .. ":" .. tostring(testId)
  if state.responded[key] then return false end
  state.responded[key] = now
  local count, oldestKey, oldestAt = 0, nil, math.huge
  for responseKey, respondedAt in pairs(state.responded) do
    count = count + 1
    local timestamp = tonumber(respondedAt) or now
    if timestamp <= oldestAt then oldestKey, oldestAt = responseKey, timestamp end
  end
  if count > 128 and oldestKey then state.responded[oldestKey] = nil end
  return true
end

local function allowChannelTestResponse(senderKey)
  local state, now = channelTestState(), time()
  for key, window in pairs(state.peerWindows) do
    if now - (tonumber(window.startedAt) or now) >= CHANNEL_TEST_PEER_WINDOW then state.peerWindows[key] = nil end
  end
  local key = tostring(senderKey)
  local window = state.peerWindows[key]
  if not window then window = { startedAt = now, count = 0 }; state.peerWindows[key] = window end
  if window.count >= CHANNEL_TEST_PEER_LIMIT then return false end
  window.count = window.count + 1
  local count, oldestKey, oldestAt = 0, nil, math.huge
  for peerKey, peerWindow in pairs(state.peerWindows) do
    count = count + 1
    local timestamp = tonumber(peerWindow.startedAt) or now
    if timestamp <= oldestAt then oldestKey, oldestAt = peerKey, timestamp end
  end
  if count > 128 and oldestKey then state.peerWindows[oldestKey] = nil end
  return true
end

local function recordChannelTest(result)
  local state = channelTestState()
  if not result._recorded then
    state.results[#state.results + 1] = result
    result._recorded = true
    while #state.results > CHANNEL_TEST_RESULT_LIMIT do table.remove(state.results, 1) end
  end
  if Dibs.DebugLogs and type(Dibs.DebugLogs.Add) == "function" then
    Dibs.DebugLogs.Add("Sync", 3, string.format("CHANNEL_TEST direction=%s channel=%s status=%s peer=%s reason=%s",
      tostring(result.direction), tostring(result.channel), tostring(result.status),
      tostring(result.peer or "-"), tostring(result.reasonCode or "none")))
  end
  return result
end

local function refreshChannelTestUI()
  local playerUI = Dibs.PlayerUI
  if playerUI and type(playerUI.RefreshDiagnostics) == "function" then
    pcall(playerUI.RefreshDiagnostics)
  end
end

local function closeChannelTestWindow(state, testId, result)
  result.ackWindowOpen = false
  local acknowledged = false
  for _, responder in ipairs(result.responders or {}) do
    if responder.result == "RECEIVED" then acknowledged = true; break end
  end
  if acknowledged then
    result.status = "ACKNOWLEDGED"
    result.ackWindowClosed = true
  elseif #(result.responders or {}) > 0 then
    result.status = "REMOTE_REJECTED"
  else
    result.status = "NO_ACK"
    result.reasonCode = "NO_ACK_TIMEOUT_CAUSE_UNKNOWN"
  end
  state.pending[testId] = nil
  recordChannelTest(result)
end

function Sync.GetChannelTestAvailability(channel, target)
  if not CHANNEL_TEST_CHANNELS[channel] then return false, "UNSUPPORTED_TEST_CHANNEL" end
  if channel == "GUILD" or channel == "OFFICER" then
    if type(IsInGuild) ~= "function" or IsInGuild() ~= true then return false, "NOT_IN_GUILD" end
    if channel == "OFFICER" and localRole() ~= "gm" and localRole() ~= "officer" then
      return false, "OFFICER_CHAT_PERMISSION_REQUIRED"
    end
  elseif channel == "RAID" then
    if type(IsInRaid) ~= "function" or IsInRaid() ~= true then return false, "NOT_IN_RAID" end
  elseif channel == "PARTY" then
    if type(IsInGroup) ~= "function" or IsInGroup() ~= true then return false, "NOT_IN_PARTY" end
    if type(IsInRaid) == "function" and IsInRaid() == true then return false, "USE_RAID_CHANNEL" end
  elseif channel == "INSTANCE_CHAT" then
    if type(IsInGroup) ~= "function" or IsInGroup(_G.LE_PARTY_CATEGORY_INSTANCE) ~= true then
      return false, "NOT_IN_INSTANCE_GROUP"
    end
  elseif channel == "WHISPER" then
    if type(trim(target)) ~= "string" or trim(target) == "" then return false, "WHISPER_TARGET_REQUIRED" end
    local resolved, reason = member(trim(target))
    if not resolved then return false, "WHISPER_TARGET_NOT_IN_GUILD:" .. tostring(reason) end
    local localMember = localSnapshot()
    if localMember and resolved.memberKey == localMember.memberKey then return false, "WHISPER_TARGET_IS_SELF" end
    return true, nil, resolved.displayName
  elseif channel == "CHANNEL" then
    local channelName = trim(target)
    if not channelName then return false, "CUSTOM_CHANNEL_NAME_REQUIRED" end
    if type(GetChannelName) ~= "function" then return false, "CUSTOM_CHANNEL_API_UNAVAILABLE" end
    local channelId = tonumber(GetChannelName(channelName))
    if not channelId or channelId < 1 then return false, "CUSTOM_CHANNEL_NOT_JOINED" end
    return true, nil, channelId, channelName
  end
  return true
end

function Sync.GetChannelTestResults()
  local state = channelTestState()
  local now = time()
  for testId, result in pairs(state.pending) do
    if now - (tonumber(result.startedAt) or now) >= CHANNEL_TEST_ACK_TIMEOUT then
      closeChannelTestWindow(state, testId, result)
    end
  end
  local results = {}
  for _, result in ipairs(state.results) do results[#results + 1] = copy(result) end
  table.sort(results, function(a, b) return (tonumber(a.startedAt) or 0) > (tonumber(b.startedAt) or 0) end)
  while #results > CHANNEL_TEST_RESULT_LIMIT do table.remove(results) end
  return results
end

function Sync.StartChannelTest(channel, target)
  if not (Dibs.DeveloperMode and Dibs.DeveloperMode.IsEnabled and Dibs.DeveloperMode.IsEnabled()) then
    return false, "DEVELOPER_MODE_REQUIRED"
  end
  local role = localRole()
  if role ~= "gm" and role ~= "officer" and role ~= "player" then return false, "GUILD_MEMBER_REQUIRED" end
  if role == "player" and (type(IsInGuild) ~= "function" or IsInGuild() ~= true) then
    return false, "GUILD_MEMBER_REQUIRED"
  end
  local available, reason, resolvedTarget, channelName = Sync.GetChannelTestAvailability(channel, target)
  if not available then
    recordChannelTest({ direction = "SEND", channel = channel, status = "NOT_SENT", reasonCode = reason, startedAt = time() })
    return false, reason
  end
  local testState, pendingCount = channelTestState(), 0
  for _ in pairs(testState.pending) do pendingCount = pendingCount + 1 end
  if pendingCount >= CHANNEL_TEST_PENDING_LIMIT then
    local limitReason = "CHANNEL_TEST_PENDING_LIMIT"
    recordChannelTest({ direction = "SEND", channel = channel, status = "NOT_SENT",
      reasonCode = limitReason, startedAt = time() })
    return false, limitReason
  end
  local localMember = localSnapshot()
  if not localMember then return false, "LOCAL_IDENTITY_UNAVAILABLE" end
  local testId = Dibs.NewId("channel-test")
  local result = { testId = testId, direction = "SEND", channel = channel, target = resolvedTarget,
    channelName = channelName, sender = localMember.displayName, status = "WAITING_FOR_ACK", ackWindowOpen = true,
    reasonCode = "ACE_COMM_QUEUED_AWAITING_ACK", startedAt = time() }
  channelTestState().pending[testId] = result
  recordChannelTest(result)
  local sent, sendReason = Sync.Send({ type = "CHANNEL_TEST", testId = testId, testChannel = channel,
    channelName = channelName, startedAt = result.startedAt }, channel,
    (channel == "WHISPER" or channel == "CHANNEL") and resolvedTarget or nil)
  if not sent then
    result.status, result.reasonCode = "SEND_FAILED", sendReason or "ACE_COMM_SEND_FAILED"
    channelTestState().pending[testId] = nil
    recordChannelTest(result)
    return false, result.reasonCode
  end
  if Dibs.Ace3 and type(Dibs.Ace3.ScheduleTimer) == "function" then
    Dibs.Ace3.ScheduleTimer(function()
      local state = channelTestState()
      local pending = state.pending[testId]
      if not pending then return end
      closeChannelTestWindow(state, testId, pending)
      refreshChannelTestUI()
    end, CHANNEL_TEST_ACK_TIMEOUT)
  end
  return true, testId
end

function Sync.RunAllChannelTests(whisperTarget, customChannelName)
  local results = {}
  for _, channel in ipairs({ "GUILD", "OFFICER", "RAID", "PARTY", "INSTANCE_CHAT", "WHISPER", "CHANNEL" }) do
    local target = channel == "CHANNEL" and customChannelName or whisperTarget
    local available, reason = Sync.GetChannelTestAvailability(channel, target)
    if available then
      local sent, result = Sync.StartChannelTest(channel, target)
      results[#results + 1] = { channel = channel, sent = sent, result = result }
    else
      recordChannelTest({ direction = "SEND", channel = channel, status = "SKIPPED", reasonCode = reason, startedAt = time() })
      results[#results + 1] = { channel = channel, sent = false, result = reason }
    end
  end
  return results
end

function Sync.RunAvailableChannelTests()
  local channels = { "GUILD" }
  local role = localRole()
  if (role == "gm" or role == "officer") and IsInGuild and IsInGuild() then
    channels[#channels + 1] = "OFFICER"
  end
  if IsInGroup and IsInGroup(_G.LE_PARTY_CATEGORY_INSTANCE) == true then
    channels[#channels + 1] = "INSTANCE_CHAT"
  elseif IsInRaid and IsInRaid() == true then
    channels[#channels + 1] = "RAID"
  elseif IsInGroup and IsInGroup() == true then
    channels[#channels + 1] = "PARTY"
  end
  local results = {}
  for _, channel in ipairs(channels) do
    local available, reason = Sync.GetChannelTestAvailability(channel)
    if available then
      local sent, result = Sync.StartChannelTest(channel)
      results[#results + 1] = { channel = channel, sent = sent, result = result }
    else
      results[#results + 1] = { channel = channel, sent = false, result = reason }
    end
  end
  return results
end

local function requestScopeKey(ledgerId, requestId)
  return tostring(ledgerId or "guild-primary") .. "|" .. tostring(requestId)
end
local function buildRequestIndex(ledgerId, copyCachedIndex)
  local targetLedgerId = ledgerId
  if targetLedgerId == nil then
    targetLedgerId = (Dibs.MultiLedger and Dibs.MultiLedger.GetActiveLedgerId
      and Dibs.MultiLedger.GetActiveLedgerId()) or "guild-primary"
  end
  if not isApprovedLedger(targetLedgerId) then return nil, "LEDGER_NOT_APPROVED" end
  local historyRevision = Dibs.PreDibs and Dibs.PreDibs.GetHistoryRevision
    and Dibs.PreDibs.GetHistoryRevision(targetLedgerId)
  local state = ensure(); local index, tombstones = {}, {}
  local records, historyReason = {}, nil
  if Dibs.PreDibs and Dibs.PreDibs.GetHistory then
    records, historyReason = Dibs.PreDibs.GetHistory(targetLedgerId)
  end
  if not records then return nil, historyReason or "PREDIB_HISTORY_UNAVAILABLE" end
  local cached = requestIndexCache[targetLedgerId]
  if historyRevision ~= nil and cached and cached.revision == historyRevision and cached.records == records then
    return copyCachedIndex and copy(cached.index) or cached.index
  end
  for _, request in ipairs(records) do
    local projection = requestProjection(request); projection.contentHash = requestHash(request); projection.terminal = TERMINAL[request.status] == true
    index[#index + 1] = projection
  end
  table.sort(index, function(a, b) if a.updatedAt == b.updatedAt then return a.requestId < b.requestId end return (a.updatedAt or 0) > (b.updatedAt or 0) end)
  while #index > MAX_INDEX do table.remove(index) end
  for key, entry in pairs(state.requestIndex) do
    if (entry.ledgerId or "guild-primary") == targetLedgerId then state.requestIndex[key] = nil end
  end
  for key, entry in pairs(state.tombstones) do
    if (entry.ledgerId or "guild-primary") == targetLedgerId then state.tombstones[key] = nil end
  end
  for _, entry in ipairs(index) do
    local key = requestScopeKey(targetLedgerId, entry.requestId)
    state.requestIndex[key] = copy(entry)
    if entry.terminal then state.tombstones[key] = copy(entry) end
  end
  boundMap(state.requestIndex, MAX_INDEX)
  boundMap(state.tombstones, MAX_INDEX)
  if historyRevision ~= nil then
    rememberRequestIndexCache(targetLedgerId, {
      revision = historyRevision, records = records, index = index, contentHash = hash(index),
    })
  else
    requestIndexCache[targetLedgerId] = nil
  end
  return index
end
function Sync.BuildRequestIndex(ledgerId)
  return buildRequestIndex(ledgerId, true)
end
function Sync.BuildManifest(ledgerId)
  local targetLedgerId = ledgerId
  if targetLedgerId == nil then
    targetLedgerId = (Dibs.MultiLedger and Dibs.MultiLedger.GetActiveLedgerId
      and Dibs.MultiLedger.GetActiveLedgerId()) or "guild-primary"
  end
  local index, reason = Sync.BuildRequestIndex(targetLedgerId)
  if not index then return nil, reason end
  local cached = requestIndexCache[targetLedgerId]
  local historyRevision = Dibs.PreDibs and Dibs.PreDibs.GetHistoryRevision
    and Dibs.PreDibs.GetHistoryRevision(targetLedgerId)
  local manifest = { type = "DIGEST", entityType = "PREDIB_INDEX",
    entityId = targetLedgerId == "guild-primary" and "current" or targetLedgerId,
    revision = 1,
    contentHash = cached and cached.revision == historyRevision and cached.contentHash or hash(index),
    index = index, protocolState = Sync.GetProtocolState() }
  if targetLedgerId ~= "guild-primary" then manifest.ledgerId = targetLedgerId end
  return manifest
end
-- Synchronization status pages need only the compact revision and hash. Avoid
-- copying the full cached request index just to read those two scalar fields.
function Sync.GetManifestDigestSummary(ledgerId)
  local targetLedgerId = ledgerId
  if targetLedgerId == nil then
    targetLedgerId = (Dibs.MultiLedger and Dibs.MultiLedger.GetActiveLedgerId
      and Dibs.MultiLedger.GetActiveLedgerId()) or "guild-primary"
  end
  if not isApprovedLedger(targetLedgerId) then return nil, "LEDGER_NOT_APPROVED" end
  local historyRevision = Dibs.PreDibs and Dibs.PreDibs.GetHistoryRevisionFast
    and Dibs.PreDibs.GetHistoryRevisionFast(targetLedgerId)
  local cached = requestIndexCache[targetLedgerId]
  if historyRevision ~= nil and cached and cached.revision == historyRevision then
    return { revision = 1, contentHash = cached.contentHash }
  end
  local index, reason = buildRequestIndex(targetLedgerId, false)
  if not index then return nil, reason end
  cached = requestIndexCache[targetLedgerId]
  return {
    revision = 1,
    contentHash = cached and cached.contentHash or hash(index),
  }
end
function Sync.AnnounceRequestIndex(ledgerId)
  local manifest, reason = Sync.BuildManifest(ledgerId)
  if not manifest then return false, reason end
  return Sync.Send(manifest, "GUILD")
end
function Sync.AnnounceAllRequestIndexes()
  local ledgers = Dibs.MultiLedger and Dibs.MultiLedger.GetLedgers and Dibs.MultiLedger.GetLedgers() or {}
  local sentAny = false
  for _, ledger in ipairs(ledgers) do
    if ledger.status == "APPROVED" then
      local sent, reason = Sync.AnnounceRequestIndex(ledger.id)
      if not sent then return false, reason end
      sentAny = true
    end
  end
  return sentAny, sentAny and nil or "NO_APPROVED_LEDGERS"
end
function Sync.BuildLedgerDigest(targetLedgerId, dbOverride)
  local ledgerId = targetLedgerId or (Dibs.MultiLedger and Dibs.MultiLedger.GetActiveLedgerId and Dibs.MultiLedger.GetActiveLedgerId(dbOverride)) or "guild-primary"
  local authorityStartedAt = beginPeerStatusTiming()
  local authorityDigest = Dibs.Governance and Dibs.Governance.GetAuthorityDigestState
    and Dibs.Governance.GetAuthorityDigestState() or nil
  recordPeerStatusTiming("ledger-digest-authority", authorityStartedAt)
  local isV2Enforced = authorityDigest and authorityDigest.protocolState ~= nil
    and authorityDigest.protocolState == "V2_ENFORCED"
  if isV2Enforced == nil then
    isV2Enforced = Dibs.Governance and Dibs.Governance.IsV2Enforced and Dibs.Governance.IsV2Enforced()
  end
  if not isV2Enforced then
    local seasonStartedAt = beginPeerStatusTiming()
    local seasonId = Dibs.GetCurrentSeasonId(dbOverride) or "none"
    recordPeerStatusTiming("ledger-digest-current-season", seasonStartedAt)
    return { type = "LEDGER_DIGEST", entityType = "LEDGER", ledgerId = ledgerId, entityId = seasonId, revision = 0, contentHash = "LOCAL_ONLY" }
  end
  local getDigestState = Dibs.Ledger and (Dibs.Ledger.GetCanonicalDigestState or Dibs.Ledger.GetCanonicalState)
  local canonicalStartedAt = beginPeerStatusTiming()
  local state = getDigestState and getDigestState(ledgerId, authorityDigest) or {}
  recordPeerStatusTiming("ledger-digest-canonical-state", canonicalStartedAt)
  if not state then return nil, "LEDGER_NOT_APPROVED" end
  return { type = "LEDGER_DIGEST", entityType = "LEDGER", ledgerId = ledgerId, entityId = tostring(state.epoch or "none"), revision = tonumber(state.nextSeq or 1) - 1,
    contentHash = state.rootHash or "UNINITIALIZED", ledgerEpoch = state.epoch, lastSeq = tonumber(state.nextSeq or 1) - 1, rootHash = state.rootHash }
end
function Sync.BuildLedgerCatalogDigest()
  local ledgers = Dibs.MultiLedger and Dibs.MultiLedger.GetLedgers and Dibs.MultiLedger.GetLedgers() or {}
  local catalog = {}
  local totalRev = 0
  for _, l in ipairs(ledgers) do
    if l.status == "APPROVED" then
      local state = Dibs.Ledger and Dibs.Ledger.GetCanonicalState and Dibs.Ledger.GetCanonicalState(l.id) or {}
      local rev = tonumber(state.nextSeq or 1) - 1
      totalRev = totalRev + rev
      catalog[l.id] = {
        id = l.id,
        name = l.name,
        status = l.status,
        epoch = state.epoch or 1,
        revision = rev,
        rootHash = state.rootHash or "NONE",
        createdAt = l.createdAt,
        createdBy = l.createdBy,
        approvedAt = l.approvedAt or 0,
        approvedBy = l.approvedBy or "SYSTEM",
      }
    end
  end
  return {
    type = "DIGEST",
    entityType = "LEDGER_CATALOG",
    entityId = "catalog",
    revision = totalRev,
    contentHash = "CATALOG-" .. tostring(totalRev),
    ledgers = catalog,
  }
end
function Sync.BroadcastCatalogDigest()
  local digest = Sync.BuildLedgerCatalogDigest()
  if not digest then return false, "CATALOG_UNAVAILABLE" end
  if type(Sync.Send) ~= "function" then return false, "SYNC_UNAVAILABLE" end
  return Sync.Send(digest, "GUILD")
end
Dibs.SyncV2 = Dibs.SyncV2 or {}
Dibs.SyncV2.BroadcastCatalogDigest = Sync.BroadcastCatalogDigest
Dibs.SyncV2.Send = Sync.Send

function Sync.BroadcastPendingLedgerDeletions()
  local db = Dibs.GetDB and Dibs.GetDB()
  if not db then return false, "DB_UNAVAILABLE" end
  local tombstones = db.ledgerDeletionTombstones
  if type(tombstones) ~= "table" then return true end
  local now = time()
  for ledgerId, tombstone in pairs(tombstones) do
    if type(ledgerId) ~= "string" or ledgerId == "" or type(tombstone) ~= "table"
      or type(tombstone.deletedBy) ~= "string" or not finiteInteger(tombstone.deletedAt) then
      return false, "INVALID_LEDGER_DELETE_TOMBSTONE"
    end
    if not finiteInteger(tombstone.lastBroadcastAt)
      or now - tonumber(tombstone.lastBroadcastAt) >= LEDGER_DELETE_RETRY_INTERVAL then
      local send = Dibs.SyncV2 and Dibs.SyncV2.Send or Sync.Send
      if type(send) ~= "function" then return false, "SYNC_UNAVAILABLE" end
      local sent, reason = send({
        type = "LEDGER_DELETE",
        ledgerId = ledgerId,
        deletedBy = tombstone.deletedBy,
        timestamp = tombstone.deletedAt,
        name = tombstone.name,
      }, "GUILD")
      if not sent then return false, reason or "SYNC_UNAVAILABLE" end
      tombstone.lastBroadcastAt = now
    end
  end
  return true
end
Dibs.SyncV2.BroadcastPendingLedgerDeletions = Sync.BroadcastPendingLedgerDeletions

function Sync.BuildAuthorityDigest()
  local signal = Dibs.Governance and Dibs.Governance.BuildAuthoritySignal and Dibs.Governance.BuildAuthoritySignal()
  if not signal or signal.state == "LEGACY_LOCAL" then return nil end
  return { type = "DIGEST", entityType = "AUTHORITY", entityId = tostring(signal.ledgerEpoch or 0), revision = 1,
    contentHash = signal.contentHash, authorityState = signal.state, protocolState = Sync.GetProtocolState() }
end
function Sync.BuildGovernanceDigest()
  local record = Dibs.Governance and Dibs.Governance.GetCurrentRecord and Dibs.Governance.GetCurrentRecord()
  local state = Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState() or {}
  local baseline = Dibs.HistoricalBaseline and Dibs.HistoricalBaseline.GetBaseline and Dibs.HistoricalBaseline.GetBaseline() or {}
  return {
    type = "DIGEST", entityType = "GOVERNANCE", entityId = tostring(state.revision or 0),
    revision = tonumber(state.revision) or 0, contentHash = state.hash or "GENESIS",
    parentHash = record and record.parentHash or nil, baselineHash = baseline.legacyBaselineHash,
    protocolState = Sync.GetProtocolState(),
  }
end
function Sync.BuildOperationalPolicyDigest()
  local state = Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetState and Dibs.OperationalPolicy.GetState() or {}
  local record = Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetCurrentRecord and Dibs.OperationalPolicy.GetCurrentRecord()
  return {
    type = "DIGEST", entityType = "OPERATIONAL_POLICY", entityId = tostring(state.policyRevision or 0),
    revision = tonumber(state.policyRevision) or 0, contentHash = state.hash or "GENESIS",
    parentHash = record and record.parentHash or nil, parentRevision = record and record.parentRevision or nil,
    protocolState = Sync.GetProtocolState(),
  }
end
function Sync.BuildSeasonCatalogDigest()
  local state = Dibs.Seasons and Dibs.Seasons.GetCatalogState and Dibs.Seasons.GetCatalogState() or {}
  local record = Dibs.Seasons and Dibs.Seasons.GetCatalogRecord and Dibs.Seasons.GetCatalogRecord(state.catalogRevision)
  return {
    type = "DIGEST", entityType = "SEASON_CATALOG", entityId = tostring(state.catalogRevision or 0),
    revision = tonumber(state.catalogRevision) or 0, contentHash = state.hash or "GENESIS",
    parentHash = record and record.parentHash or nil, parentRevision = record and record.parentRevision or nil,
    protocolState = Sync.GetProtocolState(),
  }
end

local function vaultProjection(record)
  local projection = Dibs.PreDibs.ProjectVaultAcquisition(record, "player")
  projection.evidence = nil
  projection.originalEvidence = nil
  projection.review = nil
  projection.syncState = nil
  return projection
end

local function vaultHashProjection(record)
  -- The digest hashes a player-safe projection only. Do not deep-copy the
  -- evidence tree just to discard it immediately afterward; the serializer
  -- reads the retained values without mutating them.
  local projection = {}
  for key, value in pairs(record or {}) do
    if key ~= "evidence" and key ~= "originalEvidence" and key ~= "review"
      and key ~= "syncState" then
      projection[key] = value
    end
  end
  return projection
end

local function vaultHash(record)
  return hash(vaultHashProjection(record))
end

function Sync.BuildVaultDigest()
  local records = Dibs.PreDibs and Dibs.PreDibs.GetAcquisitions and Dibs.PreDibs.GetAcquisitions() or {}
  local entries = {}
  for _, record in ipairs(records) do
    entries[#entries + 1] = {
      acquisitionId = record.acquisitionId, revision = tonumber(record.revision) or 1,
      contentHash = vaultHash(record), playerName = record.playerName, itemID = tonumber(record.itemID),
      seasonId = record.seasonId, resetId = record.resetId, claimedAt = record.claimedAt,
      verificationState = record.verificationState,
      source = record.source, syncState = record.syncState,
    }
  end
  table.sort(entries, function(a, b) return tostring(a.acquisitionId) < tostring(b.acquisitionId) end)
  while #entries > MAX_INDEX do table.remove(entries) end
  return { type = "VAULT_DIGEST", entityType = "VAULT_INDEX", entityId = "current", revision = 1,
    contentHash = hash(entries), records = entries, entries = entries }
end

-- Status projections need only the digest scalars, not the full bounded
-- acquisition payload. Cache that summary until Pre-Dibs reports a mutation.
function Sync.GetVaultDigestSummary()
  local summaryStartedAt = beginPeerStatusTiming()
  local records, revision
  if Dibs.PreDibs and type(Dibs.PreDibs.GetAcquisitionsSnapshotFast) == "function" then
    records, revision = Dibs.PreDibs.GetAcquisitionsSnapshotFast()
  else
    records = Dibs.PreDibs and Dibs.PreDibs.GetAcquisitions
      and Dibs.PreDibs.GetAcquisitions() or {}
    revision = Dibs.PreDibs and Dibs.PreDibs.GetAcquisitionsRevision
      and Dibs.PreDibs.GetAcquisitionsRevision() or 0
  end
  records, revision = records or {}, revision or 0
  local cached = vaultDigestSummaryCache[records]
  if cached and cached.revision == revision then
    recordPeerStatusTiming("vault-digest-cache-hit", summaryStartedAt)
    return cached.summary
  end
  local digest = Sync.BuildVaultDigest()
  if type(digest) ~= "table" then
    recordPeerStatusTiming("vault-digest-cache-miss", summaryStartedAt)
    return digest
  end
  local summary = { revision = digest.revision, contentHash = digest.contentHash }
  vaultDigestSummaryCache[records] = { revision = revision, summary = summary }
  recordPeerStatusTiming("vault-digest-cache-miss", summaryStartedAt)
  return summary
end

local function reservationFromProposal(proposal, reservationState)
  local player = proposal and proposal.playerSnapshot
  local actor = proposal and proposal.actorSnapshot
  if type(proposal) ~= "table" or type(proposal.proposalId) ~= "string"
    or type(player) ~= "table" or type(player.memberKey) ~= "string"
    or type(actor) ~= "table" or type(actor.memberKey) ~= "string" then return nil end
  return {
    proposalId = proposal.proposalId,
    playerMemberKey = player.memberKey,
    actorMemberKey = actor.memberKey,
    awardRef = proposal.awardRef,
    evidenceId = proposal.evidenceId,
    ledgerId = type(proposal.ledgerId) == "string" and proposal.ledgerId ~= "" and proposal.ledgerId or nil,
    seasonId = type(proposal.seasonId) == "string" and proposal.seasonId or Dibs.GetCurrentSeasonId(),
    amount = math.abs(tonumber(proposal.amount) or 1),
    state = reservationState,
    updatedAt = tonumber(reservationState == "PENDING" and proposal.createdAt
      or proposal.resolvedAt or proposal.committedAt or proposal.createdAt) or time(),
  }
end

local function addReservationRecord(records, reservation)
  if type(reservation) ~= "table" or type(reservation.proposalId) ~= "string" then return end
  local current = records[reservation.proposalId]
  local incomingAt, currentAt = tonumber(reservation.updatedAt) or 0, tonumber(current and current.updatedAt) or 0
  if not current or incomingAt > currentAt or (incomingAt == currentAt and reservation.state == "RELEASED") then
    records[reservation.proposalId] = copy(reservation)
  end
end

function Sync.BuildAwardReservationDigest()
  local records = {}
  local proposals = Dibs.Governance and Dibs.Governance.GetAwardProposals and Dibs.Governance.GetAwardProposals() or {}
  for _, proposal in ipairs(proposals) do
    if (proposal.type == "AWARD" or proposal.type == "DIB_USED") and proposal.status ~= "COMMITTED" then
      addReservationRecord(records, reservationFromProposal(proposal, "PENDING"))
    end
  end
  local state = ensure()
  for _, reservation in pairs(state.awardReservations) do addReservationRecord(records, reservation) end
  local entries = {}
  for _, reservation in pairs(records) do entries[#entries + 1] = reservation end
  table.sort(entries, function(a, b) return a.proposalId < b.proposalId end)
  while #entries > MAX_INDEX do table.remove(entries) end
  return { type = "AWARD_RESERVATION_DIGEST", entityType = "AWARD_RESERVATION", entityId = "pending",
    revision = #entries, contentHash = hash(entries), records = entries }
end

function Sync.GetPendingAwardReservations()
  local reservations = {}
  for _, reservation in pairs(ensure().awardReservations) do
    if reservation.state == "PENDING" then reservations[#reservations + 1] = copy(reservation) end
  end
  return reservations
end

function Sync.GetAwardReservationGeneration(memberKey)
  return awardReservationGenerations[memberKey] or 0
end

function Sync.AnnounceAwardReservationDigest()
  local digest = Sync.BuildAwardReservationDigest()
  if #digest.records == 0 then return true, "NO_PENDING_AWARD_RESERVATIONS" end
  local pageCount = math.ceil(#digest.records / AWARD_RESERVATION_PAGE_SIZE)
  for pageIndex = 1, pageCount do
    local page = copy(digest)
    page.records = {}
    local first = (pageIndex - 1) * AWARD_RESERVATION_PAGE_SIZE + 1
    local last = math.min(#digest.records, first + AWARD_RESERVATION_PAGE_SIZE - 1)
    for index = first, last do page.records[#page.records + 1] = digest.records[index] end
    page.revision = pageIndex
    page.entityId = "pending:" .. tostring(pageIndex) .. ":" .. tostring(pageCount)
    page.contentHash = hash(page.records)
    local sent, reason = Sync.Send(page, "GUILD")
    if not sent then return false, reason end
  end
  return true, digest.contentHash
end

function Sync.ClearAwardReservation(proposalId, commit)
  if type(proposalId) ~= "string" or proposalId == "" then return false end
  local state = ensure()
  local reservation = state.awardReservations[proposalId]
  local transaction = type(commit) == "table" and commit.transaction or nil
  local tombstone = reservation or {
    proposalId = proposalId,
    playerMemberKey = transaction and transaction.memberKey,
    actorMemberKey = type(commit) == "table" and commit.coordinator and commit.coordinator.memberKey,
    seasonId = transaction and transaction.seasonId,
    amount = math.abs(tonumber(transaction and transaction.amount) or 1),
  }
  if type(tombstone.playerMemberKey) ~= "string" then return false end
  tombstone = copy(tombstone)
  tombstone.state, tombstone.updatedAt = "RELEASED", time()
  state.awardReservations[proposalId] = nil
  state.awardReservationTombstones[proposalId] = tombstone
  bumpAwardReservationGeneration(tombstone.playerMemberKey)
  boundMap(state.awardReservationTombstones, MAX_INDEX)
  return true
end

local function reservationHasCanonicalCommit(reservation)
  local ledger = Dibs.Ledger
  if not ledger then return false end
  if reservation.awardRef and ledger.GetTransactionForAward
    and ledger.GetTransactionForAward(reservation.awardRef) then return true end
  if reservation.evidenceId and ledger.GetTransactionForEvidence
    and ledger.GetTransactionForEvidence(reservation.evidenceId) then return true end
  return false
end

function Sync.BuildVaultFetch(requests)
  local bounded = {}
  for index, request in ipairs(type(requests) == "table" and requests or {}) do
    if index > 32 then break end
    bounded[#bounded + 1] = {
      acquisitionId = request.acquisitionId, revision = tonumber(request.revision) or 1,
      contentHash = request.contentHash,
    }
  end
  return { type = "VAULT_FETCH", requests = bounded }
end

function Sync.BuildVaultDetail(record)
  local payload = vaultProjection(record)
  return {
    type = "VAULT_DETAIL", acquisitionId = payload.acquisitionId,
    revision = tonumber(payload.revision) or 1, contentHash = vaultHash(payload),
    acquisition = payload, projection = "PLAYER", payload = payload,
  }
end

function Sync.BuildVaultAck(acquisitionId, revision, outcome, reasonCode)
  return { type = "VAULT_ACK", acquisitionId = acquisitionId, revision = tonumber(revision) or 1,
    result = outcome, outcome = outcome, reasonCode = reasonCode }
end

local function validateEnvelope(message, sender)
  if type(message) ~= "table" or not TYPES[message.type] or type(message.protocol) ~= "table" then return nil, "MALFORMED_ENVELOPE" end
  if type(message.messageId) ~= "string" or #message.messageId < 1 or #message.messageId > 128 then return nil, "INVALID_MESSAGE_ID" end
  if message.guildKey ~= Dibs.GetGuildKey() then return nil, "GUILD_SCOPE_MISMATCH" end
  local resolved, why = member(sender); if not resolved then return nil, why end
  if message.senderMemberKey ~= resolved.memberKey or string.lower(tostring(message.senderNameRealm or "")) ~= resolved.memberKey then return nil, "SENDER_MISMATCH" end
  if tonumber(message.protocol.major) ~= MAJOR then
    rememberProtocolMismatch(resolved.displayName, message.protocol.major)
    return nil, "UNSUPPORTED_PROTOCOL_MAJOR"
  end
  local compatible, compatibilityReason = Sync.GetAddonVersionCompatibility(message.addonVersion)
  if message.type == "TRANSFER_BEGIN" and message.entityType == "AWARD_PROPOSAL" and compatible ~= true then
    rememberAddonVersionMismatch(resolved.displayName, message.addonVersion, compatibilityReason or "REMOTE_ADDON_VERSION_UNKNOWN")
    return nil, compatibilityReason or "REMOTE_ADDON_VERSION_UNKNOWN"
  end
  if message.type == "TRANSFER_BEGIN" and message.entityType == "LEDGER_OPERATION_PROPOSAL" and compatible ~= true then
    rememberAddonVersionMismatch(resolved.displayName, message.addonVersion, compatibilityReason or "REMOTE_ADDON_VERSION_UNKNOWN")
    return nil, compatibilityReason or "REMOTE_ADDON_VERSION_UNKNOWN"
  end
  if compatible == false then
    rememberAddonVersionMismatch(resolved.displayName, message.addonVersion, compatibilityReason)
    return nil, compatibilityReason
  end
  clearAddonVersionMismatch(resolved.displayName)
  if compatible == nil then rememberAddonVersionMismatch(resolved.displayName, message.addonVersion, compatibilityReason) end
  if message.type == "LEDGER_DIGEST" and (message.nextSeq ~= nil or message.previousHash ~= nil) then return resolved, "LEDGER_DETAIL_FORBIDDEN" end
  return resolved
end
local function replayKey(resolved, id) return resolved.memberKey .. "|" .. id end
local function markReplay(resolved, id)
  local state = ensure(); state.replay[replayKey(resolved, id)] = { at = time() }; boundMap(state.replay, MAX_MESSAGES)
end
local function localRequest(id, ledgerId)
  local targetLedgerId = ledgerId or "guild-primary"
  if Dibs.PreDibs and Dibs.PreDibs.GetRequestById then
    return Dibs.PreDibs.GetRequestById(id, targetLedgerId)
  end
  for _, request in ipairs(Dibs.PreDibs and Dibs.PreDibs.GetHistory
    and Dibs.PreDibs.GetHistory(targetLedgerId) or {}) do
    if request.requestId == id then return request end
  end
end

local function requestDetail(target, requestId, ledgerId, ownerOnly)
  local request = localRequest(requestId, ledgerId); if not request then return false, "DETAIL_NOT_FOUND" end
  local owner = member(request.playerName); if not owner then return false, "REQUEST_OWNER_UNAVAILABLE" end
  local payload = ownerOnly and ownerRequestProjection(request) or request
  return Sync.SendDetail("PREDIB_REQUEST", requestId, tonumber(request.revision) or 1, requestHash(request), payload, target)
end
local PREDIB_FETCH_BATCH = 32
local function sendPredibFetches(requests, target)
  local sentAll = true
  for first = 1, #requests, PREDIB_FETCH_BATCH do
    local batch = {}
    for index = first, math.min(#requests, first + PREDIB_FETCH_BATCH - 1) do batch[#batch + 1] = requests[index] end
    if not Sync.Send({ type = "DETAIL_FETCH", requests = batch }, "WHISPER", target) then sentAll = false end
  end
  return sentAll
end
local function rememberPredibRequest(request, target)
  local pending = ensure().predibPending
  pending[requestScopeKey(request.ledgerId, request.entityId)] = { requestId = request.entityId, ledgerId = request.ledgerId,
    revision = request.revision, contentHash = request.contentHash, target = target, at = time() }
  boundMap(pending, MAX_INDEX)
end
local function prunePredibPending()
  local pending = ensure().predibPending
  for key, entry in pairs(pending) do
    local current = type(entry) == "table" and localRequest(entry.requestId, entry.ledgerId)
    if type(entry) ~= "table" or (current and (tonumber(current.revision) or 1) >= (tonumber(entry.revision) or 1)) then
      pending[key] = nil
    end
  end
  return next(pending) == nil
end
function Sync.SendDetail(entityType, entityId, revision, contentHash, payload, target)
  if entityType ~= "PREDIB_REQUEST" and entityType ~= "VAULT_DETAIL" and entityType ~= "GOVERNANCE" and entityType ~= "OPERATIONAL_POLICY" and entityType ~= "LEGACY_BASELINE" and entityType ~= "LEGACY_RECOVERY_PACKAGE" and entityType ~= "AUTHORITY_SIGNAL" and entityType ~= "AUTHORITY_ORPHAN" and entityType ~= "AWARD_COMMIT" and entityType ~= "LEDGER_OPERATION_COMMIT" and entityType ~= "LEDGER_OPERATION_PROPOSAL" and entityType ~= "AWARD_PROPOSAL" and entityType ~= "SEASON_CATALOG" and entityType ~= "REQUEST_MESSAGE" then return false, "UNSUPPORTED_ENTITY" end
  if (entityType == "LEDGER_OPERATION_COMMIT" or entityType == "LEDGER_OPERATION_PROPOSAL")
    and Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED ~= true then return false, "CANONICAL_DISPUTE_OPERATIONS_DISABLED" end
  if not transportReady() then return false, "SYNC_UNAVAILABLE" end
  local channel = detailChannel(entityType)
  if not channel then return false, "UNSUPPORTED_ENTITY" end
  channel = routeForPeer(channel, target)
  local recipient = channel == "WHISPER" and target or nil
  local encoded = Dibs.Ace3.Serialize(payload); if type(encoded) ~= "string" or #encoded > MAX_BYTES then return false, "PAYLOAD_TOO_LARGE" end
  local transferId = Dibs.NewId("v2transfer"); local chunks = {}
  for offset = 1, #encoded, 480 do chunks[#chunks + 1] = encoded:sub(offset, offset + 479) end
  if #chunks < 1 or #chunks > MAX_CHUNKS then return false, "PAYLOAD_TOO_LARGE" end
  local rawHash = hash(encoded)
  local ledgerId
  if (entityType == "AWARD_COMMIT" or entityType == "LEDGER_OPERATION_COMMIT" or entityType == "PREDIB_REQUEST") and type(payload) == "table" then
    ledgerId = payload.ledgerId
    if ledgerId == nil then ledgerId = "guild-primary" end
  end

  local sent, reason = Sync.Send({ type = "TRANSFER_BEGIN", transferId = transferId, entityType = entityType, entityId = entityId, revision = revision, contentHash = contentHash, payloadHash = rawHash, chunkCount = #chunks, ledgerId = ledgerId }, channel, recipient)
  if not sent then return false, reason end
  for index, chunk in ipairs(chunks) do
    sent, reason = Sync.Send({ type = "TRANSFER_CHUNK", transferId = transferId, chunkIndex = index, chunk = chunk }, channel, recipient)
    if not sent then return false, reason end
  end
  return Sync.Send({ type = "TRANSFER_END", transferId = transferId, entityType = entityType, entityId = entityId,
    revision = revision, contentHash = contentHash, ledgerId = ledgerId }, channel, recipient)
end

function Sync.RelayDisputeProposal(proposal)
  if Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED ~= true then return false, "CANONICAL_DISPUTE_OPERATIONS_DISABLED" end
  if type(proposal) ~= "table" or proposal.recordClass ~= "LEDGER_OPERATION_PROPOSAL"
    or type(proposal.proposalId) ~= "string" or proposal.status ~= "PENDING" then
    return false, "INVALID_DISPUTE_PROPOSAL"
  end
  local governance = Dibs.Governance
  local authority = governance and governance.GetAuthorityState and governance.GetAuthorityState()
  local localName = Dibs.GetPlayerName and Dibs.GetPlayerName()
  local localIdentity = localName and Dibs.Identity and Dibs.Identity.CreateSnapshot
    and Dibs.Identity.CreateSnapshot(localName)
  local coordinator = authority and authority.coordinator
  if not authority or authority.state ~= "ACTIVE" or not coordinator then return false, "COORDINATOR_UNKNOWN" end
  if not localIdentity or localIdentity.memberKey ~= proposal.proposer.memberKey then
    return false, "PROPOSER_IDENTITY_MISMATCH"
  end
  if coordinator.memberKey == localIdentity.memberKey then return false, "COORDINATOR_ALREADY_LOCAL" end
  if proposal.coordinator.memberKey ~= coordinator.memberKey or proposal.ledgerEpoch ~= authority.ledgerEpoch then
    return false, "STALE_AUTHORITY"
  end
  local _, attemptReason = governance.NoteDisputeProposalRelayAttempt(localName, proposal.proposalId)
  if attemptReason ~= "RELAY_PENDING" then return false, attemptReason or "RELAY_ATTEMPT_UNAVAILABLE" end
  return Sync.SendDetail("LEDGER_OPERATION_PROPOSAL", proposal.proposalId, 1,
    Sync.CalculateContentHash(proposal), proposal, coordinator.displayName)
end

function Sync.RetryPendingDisputeProposals()
  if Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED ~= true then return 0 end
  local governance = Dibs.Governance
  local localName = Dibs.GetPlayerName and Dibs.GetPlayerName()
  if not governance or type(governance.GetPendingDisputeProposals) ~= "function" or not localName then return 0 end
  local authority = governance.GetAuthorityState and governance.GetAuthorityState()
  local localIdentity = Dibs.Identity and Dibs.Identity.CreateSnapshot and Dibs.Identity.CreateSnapshot(localName)
  if not authority or authority.state ~= "ACTIVE" or not authority.coordinator or not localIdentity
    or authority.coordinator.memberKey == localIdentity.memberKey then return 0 end
  local pending = governance.GetPendingDisputeProposals(localName)
  local now, count = time(), 0
  for _, proposal in ipairs(pending or {}) do
    local changedCoordinator = proposal.coordinator.memberKey ~= authority.coordinator.memberKey
      or proposal.ledgerEpoch ~= authority.ledgerEpoch
    local alreadyAcknowledged = proposal.relayStatus == "RELAY_ACKED" and not changedCoordinator
    local due = now - (tonumber(proposal.relayAttemptAt) or 0) >= PROPOSAL_RETRY_INTERVAL
    if not alreadyAcknowledged and (changedCoordinator or due) then
      local ok = Sync.RelayDisputeProposal(proposal)
      if ok then count = count + 1 end
    end
  end
  return count
end

function Sync.GetRequestPeer(target)
  local resolved, reason = member(target)
  if not resolved then return nil, reason end
  if resolved.online ~= true then return nil, "WHISPER_TARGET_OFFLINE" end
  local peer = ensure().peers[resolved.memberKey]
  if not peer or not peer.protocol or not (peer.protocol.capabilities or {}).requestDelivery then
    return nil, "REQUEST_PEER_UNSUPPORTED"
  end
  return resolved
end

function Sync.GetRequestPeers()
  local result = {}
  for key in pairs(ensure().peers) do
    local resolved = Sync.GetRequestPeer(key)
    if resolved and (resolved.role == "gm" or resolved.role == "officer") then result[#result + 1] = resolved end
  end
  table.sort(result, function(a, b) return a.memberKey < b.memberKey end)
  while #result > 16 do table.remove(result) end
  return result
end

local function sendTransferAck(target, transfer, accepted, reason, channel)
  if not transfer or transfer.entityType ~= "LEGACY_BASELINE" then return end
  local result = accepted and (reason == "TRANSFER_STARTED" and "STARTED" or "APPLIED") or "REJECTED"
  local ackChannel = channel or "WHISPER"
  local ackTarget = ackChannel == "WHISPER" and target or nil
  Sync.Send({ type = "TRANSFER_ACK", transferId = transfer.transferId, entityType = transfer.entityType,
    entityId = transfer.entityId, result = result, reasonCode = reason,
    receivedChunks = tonumber(transfer.receivedChunks) or 0, chunkCount = tonumber(transfer.chunkCount) or 0 }, ackChannel, ackTarget)
end

-- B05a evidence transport: the receiving side stages this as non-canonical
-- runtime evidence. It never imports a ledger or finalizes a baseline itself.
function Sync.SendLegacyRecoveryPackage(package, target)
  if type(package) ~= "table" or type(package.contentHash) ~= "string" then return false, "INVALID_RECOVERY_PACKAGE" end
  return Sync.SendDetail("LEGACY_RECOVERY_PACKAGE", package.contentHash, 1, package.contentHash, package, target)
end
function Sync.SendAuthoritySignal(target)
  local signal = Dibs.Governance and Dibs.Governance.BuildAuthoritySignal and Dibs.Governance.BuildAuthoritySignal()
  if not signal or signal.state == "LEGACY_LOCAL" then return false, "AUTHORITY_INACTIVE" end
  return Sync.SendDetail("AUTHORITY_SIGNAL", tostring(signal.ledgerEpoch or 0), 1, signal.contentHash, signal, target)
end
function Sync.SendAuthorityOrphan(event, target)
  if type(event) ~= "table" then return false, "INVALID_ORPHANED_EVIDENCE" end
  local evidenceId = event.evidenceId or event.eventId or event.transactionId
  if type(evidenceId) ~= "string" then return false, "INVALID_ORPHANED_EVIDENCE" end
  return Sync.SendDetail("AUTHORITY_ORPHAN", evidenceId, 1, Sync.CalculateContentHash(event), event, target)
end
function Sync.SendAwardCommit(commit, target)
  if type(commit) ~= "table" or type(commit.commitHash) ~= "string" or not commit.ledgerEpoch or not commit.sequence then return false, "INVALID_AWARD_COMMIT" end
  return Sync.SendDetail("AWARD_COMMIT", tostring(commit.ledgerEpoch) .. ":" .. tostring(commit.sequence), commit.sequence, commit.commitHash, commit, target)
end
function Sync.SendOperationCommit(commit, target)
  if Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED ~= true then return false, "CANONICAL_DISPUTE_OPERATIONS_DISABLED" end
  if type(commit) ~= "table" or commit.recordClass ~= "LEDGER_OPERATION_COMMIT"
    or type(commit.commitHash) ~= "string" or not commit.ledgerEpoch or not commit.sequence then
    return false, "INVALID_OPERATION_COMMIT"
  end
  return Sync.SendDetail("LEDGER_OPERATION_COMMIT", tostring(commit.ledgerEpoch) .. ":" .. tostring(commit.sequence),
    commit.sequence, commit.commitHash, commit, target)
end

---@param proposal table Award proposal recorded by a non-coordinator officer.
---@return boolean sent Whether the relay attempt was dispatched (not whether it was acknowledged).
---@return string reasonCode Outcome reason.
function Sync.RelayAwardProposal(proposal)
  if type(proposal) ~= "table" or type(proposal.proposalId) ~= "string" then return false, "INVALID_PROPOSAL" end
  local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
  local coordinatorNameRealm = authority and authority.coordinator and authority.coordinator.displayName
  if not coordinatorNameRealm then return false, "COORDINATOR_UNKNOWN" end
  if Dibs.Governance.NoteProposalRelayAttempt then
    Dibs.Governance.NoteProposalRelayAttempt(proposal.proposalId, authority.coordinator.memberKey)
  end
  local hashValue = Sync.CalculateContentHash(proposal)
  return Sync.SendDetail("AWARD_PROPOSAL", proposal.proposalId, 1, hashValue, proposal, coordinatorNameRealm)
end

---Retries pending award proposals after timeout, or immediately after coordinator handoff.
---Safe to call repeatedly (e.g. from the heartbeat); a no-op when nothing is pending.
function Sync.RetryPendingAwardProposals()
  if not (Dibs.Governance and Dibs.Governance.GetRelayPendingProposals) then return 0 end
  local authority = Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
  local localMember = localSnapshot()
  if not authority or authority.state ~= "ACTIVE" or not authority.coordinator or not localMember
    or authority.coordinator.memberKey == localMember.memberKey then return 0 end
  local pending = Dibs.Governance.GetRelayPendingProposals()
  local retryable = {}
  local now = time()
  for _, proposal in ipairs(pending) do
    local lastAttempt = tonumber(proposal.relayAttemptAt) or 0
    local coordinatorChanged = proposal.coordinatorMemberKey ~= authority.coordinator.memberKey
    local alreadyAcknowledged = proposal.relayStatus == "RELAY_ACKED" and not coordinatorChanged
    if not alreadyAcknowledged and (coordinatorChanged or now - lastAttempt >= PROPOSAL_RETRY_INTERVAL) then
      retryable[#retryable + 1] = proposal
    end
  end
  local count = 0
  for _, proposal in ipairs(retryable) do
    Sync.RelayAwardProposal(proposal)
    count = count + 1
  end
  return count
end
function Sync.AnnounceAwardCommit(commit)
  if type(commit) ~= "table" then return false, "INVALID_AWARD_COMMIT" end
  local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
  local localMember = localSnapshot()
  if not authority or authority.state ~= "ACTIVE" or not localMember or not authority.coordinator
    or authority.coordinator.memberKey ~= localMember.memberKey then return false, "CURRENT_COORDINATOR_REQUIRED" end
  return Sync.Send({ type = "LEDGER_DIGEST", entityType = "LEDGER", ledgerId = commit.ledgerId or "guild-primary", entityId = tostring(commit.ledgerEpoch), revision = commit.sequence,
    contentHash = commit.commitHash, ledgerEpoch = commit.ledgerEpoch, lastSeq = commit.sequence, rootHash = commit.commitHash }, "GUILD")
end
function Sync.AnnounceOperationCommit(commit)
  if Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED ~= true then return false, "CANONICAL_DISPUTE_OPERATIONS_DISABLED" end
  local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
  local localMember = localSnapshot()
  if not authority or authority.state ~= "ACTIVE" or not localMember or not authority.coordinator
    or authority.coordinator.memberKey ~= localMember.memberKey then return false, "CURRENT_COORDINATOR_REQUIRED" end
  local sent, sendReason = Sync.SendOperationCommit(commit)
  if not sent then return false, sendReason end
  return Sync.Send({ type = "LEDGER_DIGEST", entityType = "LEDGER", ledgerId = commit.ledgerId or "guild-primary",
    entityId = tostring(commit.ledgerEpoch), revision = commit.sequence, contentHash = commit.commitHash,
    ledgerEpoch = commit.ledgerEpoch, lastSeq = commit.sequence, rootHash = commit.commitHash }, "GUILD")
end
function Sync.AnnounceLedgerDigest(targetLedgerId)
  local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
  if not (Dibs.Governance and Dibs.Governance.IsV2Enforced and Dibs.Governance.IsV2Enforced())
    or not authority or authority.state ~= "ACTIVE" then return false, "V2_AUTHORITY_UNAVAILABLE" end
  if targetLedgerId then
    local digest, reason = Sync.BuildLedgerDigest(targetLedgerId)
    if not digest then return false, reason end
    return Sync.Send(digest, "GUILD")
  end
  local sentAny = false
  for _, ledger in ipairs(Dibs.MultiLedger and Dibs.MultiLedger.GetLedgers and Dibs.MultiLedger.GetLedgers() or {}) do
    if ledger.status == "APPROVED" then
      local digest, reason = Sync.BuildLedgerDigest(ledger.id)
      if not digest then return false, reason end
      local sent, sendReason = Sync.Send(digest, "GUILD")
      if not sent then return false, sendReason end
      sentAny = true
    end
  end
  return sentAny, sentAny and nil or "NO_APPROVED_LEDGERS"
end

local function applyRequest(payload, transfer, sender)
  if type(payload) ~= "table" or payload.requestId ~= transfer.entityId or tonumber(payload.revision) ~= tonumber(transfer.revision) then return false, "ENTITY_IDENTITY_MISMATCH" end
  local ledgerId = transfer.ledgerId or "guild-primary"
  if payload.ledgerId ~= nil and payload.ledgerId ~= ledgerId then return false, "LEDGER_SCOPE_MISMATCH" end
  if ledgerId ~= "guild-primary" and payload.ledgerId ~= ledgerId then return false, "LEDGER_SCOPE_MISMATCH" end
  if requestHash(payload) ~= transfer.contentHash then return false, "CONTENT_HASH_MISMATCH" end
  local owner = member(payload.playerName)
  local localMember = localSnapshot()
  local recipientIsOwner = owner and localMember and owner.memberKey == localMember.memberKey
  local officerRelay = owner and owner.memberKey ~= sender.memberKey and isAdmin(sender.displayName)
    and (localRole() == "gm" or localRole() == "officer" or recipientIsOwner)
  if not owner or (owner.memberKey ~= sender.memberKey and not officerRelay) then return false, "OWNER_MISMATCH" end
  if officerRelay and recipientIsOwner and localRole() ~= "gm" and localRole() ~= "officer" then
    payload = ownerRequestProjection(payload)
  end
  local existing = localRequest(payload.requestId, ledgerId)
  if existing then
    local currentRevision, incomingRevision = tonumber(existing.revision) or 1, tonumber(payload.revision) or 1
    local currentHash = requestHash(existing)
    if incomingRevision == currentRevision then return currentHash == transfer.contentHash, currentHash == transfer.contentHash and "IDEMPOTENT_REPLAY" or "REQUEST_CONFLICT" end
    if incomingRevision < currentRevision then return false, "STALE_REVISION" end
  end
  local applied = false
  local reason = "SYNC_APPLY_UNAVAILABLE"
  if Dibs.PreDibs and Dibs.PreDibs.ApplyVerifiedSyncRecord then
    applied, reason = Dibs.PreDibs.ApplyVerifiedSyncRecord(payload, sender.displayName, ledgerId)
  end
  if not applied then return false, reason end
  local scopeKey = requestScopeKey(ledgerId, payload.requestId)
  local state = ensure()
  state.requestIndex[scopeKey] = { requestId = payload.requestId, ledgerId = ledgerId, revision = payload.revision, contentHash = transfer.contentHash, terminal = TERMINAL[payload.status] == true, updatedAt = payload.updatedAt or time() }
  if TERMINAL[payload.status] then state.tombstones[scopeKey] = copy(state.requestIndex[scopeKey]) end
  boundMap(state.requestIndex, MAX_INDEX)
  boundMap(state.tombstones, MAX_INDEX)
  return true, "APPLIED"
end

local function applyVaultDetail(payload, transfer, sender)
  if type(payload) ~= "table" or payload.acquisitionId ~= transfer.entityId
    or tonumber(payload.revision) ~= tonumber(transfer.revision) then
    return false, "ENTITY_IDENTITY_MISMATCH"
  end
  if payload.evidence ~= nil or payload.originalEvidence ~= nil or payload.review ~= nil then
    return false, "FORBIDDEN_PRIVATE_EVIDENCE"
  end
  if payload.guildKey and payload.guildKey ~= Dibs.GetGuildKey() then return false, "GUILD_SCOPE_MISMATCH" end
  local owner = member(payload.playerName)
  if not owner or (owner.memberKey ~= sender.memberKey and not isAdmin(sender.displayName)) then
    return false, "VAULT_AUTHORITY_REQUIRED"
  end
  if vaultHash(payload) ~= transfer.contentHash then return false, "CONTENT_HASH_MISMATCH" end
  local current = Dibs.PreDibs.GetVaultAcquisition and Dibs.PreDibs.GetVaultAcquisition(transfer.entityId)
  if current then
    local currentRevision = tonumber(current.revision) or 1
    if tonumber(transfer.revision) < currentRevision then return false, "STALE_REVISION" end
    if tonumber(transfer.revision) == currentRevision then
      if vaultHash(current) == transfer.contentHash then clearVaultRequest(transfer.entityId); return true, "IDEMPOTENT_REPLAY" end
      return false, "CONFLICT"
    end
  end
  local applied, applyReason = Dibs.PreDibs.ApplyVaultSyncRecord(payload)
  if not applied then return false, applyReason end
  clearVaultRequest(transfer.entityId)
  clearSyncBehindReasons("VAULT_DETAIL_MISSING")
  return true, applyReason
end

function Sync.Receive(message, sender, channel)
  ensure(); expiry()
  if Sync.ContainsForbiddenLiveLootData and Sync.ContainsForbiddenLiveLootData(message) then return false, "FORBIDDEN_LIVE_LOOT_DATA" end
  local resolved, reason = validateEnvelope(message, sender)
  if not resolved or reason then if reason == "LEDGER_DETAIL_FORBIDDEN" then Sync.MarkSyncBehind(reason) end; return false, reason end
  local state = ensure(); local key = replayKey(resolved, message.messageId)
  if state.replay[key] then return true, "IDEMPOTENT_MESSAGE_REPLAY" end
  markReplay(resolved, message.messageId)
  local peer = state.peers[resolved.memberKey] or {}
  peer.at = time()
  peer.lastSeenAt = peer.at
  peer.addonVersion = message.addonVersion
  peer.protocol = copy(message.protocol)
  peer.protocolState = message.protocolState or "LEGACY_LOCAL"
  if message.type == "DIGEST" or message.type == "LEDGER_DIGEST" or message.type == "VAULT_DIGEST"
    or message.type == "AWARD_RESERVATION_DIGEST" then
    peer.entities = peer.entities or {}
    local entityType = message.entityType or message.type
    local entityKey = entityType == "LEDGER" and (entityType .. ":" .. tostring(message.ledgerId or "guild-primary"))
      or (entityType == "PREDIB_INDEX" and message.ledgerId and (entityType .. ":" .. tostring(message.ledgerId)))
      or entityType
    peer.entities[entityKey] = { revision = tonumber(message.revision) or 0, contentHash = message.contentHash, at = peer.at }
  end
  state.peers[resolved.memberKey] = peer
  if message.type == "SYNC_REPAIR_REQUEST" then
    if type(message.requestId) ~= "string" or message.requestId == "" or #message.requestId > 128
      or (message.scope ~= "PEER" and message.scope ~= "GUILD") then return false, "INVALID_REPAIR_REQUEST" end
    if channel and channel ~= (message.scope == "GUILD" and "GUILD" or "WHISPER") then
      return false, "INVALID_SYNC_CHANNEL"
    end
    if not isAdmin(sender) then return false, "OFFICER_REQUIRED" end
    if resolved.memberKey == (localSnapshot() or {}).memberKey then return true, "SELF_REPAIR_IGNORED" end
    local allowed, repairReason = repairContextAllowed()
    local recovery, now = repairState(), time()
    if allowed and recovery.lastAcceptedAt and now - recovery.lastAcceptedAt < HEARTBEAT then
      allowed, repairReason = false, "REPAIR_COOLDOWN"
    end
    if allowed then
      recovery.lastAcceptedAt = now
      local _, started, startReason = Sync.RequestResync()
      if not started then allowed, repairReason = false, startReason or "SYNC_UNAVAILABLE" end
      Sync.RecheckSyncBehind()
    end
    return Sync.Send({ type = "SYNC_REPAIR_ACK", requestId = message.requestId,
      result = allowed and "STARTED" or "BLOCKED", reasonCode = repairReason,
      report = Sync.BuildSyncProbeReport() }, "WHISPER", resolved.displayName)
  end
  if message.type == "SYNC_REPAIR_ACK" then
    if channel and channel ~= "WHISPER" then return false, "INVALID_SYNC_CHANNEL" end
    local request = type(message.requestId) == "string" and repairState().pending[message.requestId]
    if not request or (request.target and request.target ~= resolved.memberKey) then
      return false, "UNSOLICITED_REPAIR_ACK"
    end
    if not isAdmin(Dibs.GetPlayerName()) then return false, "OFFICER_REQUIRED" end
    if (message.result ~= "STARTED" and message.result ~= "BLOCKED") or type(message.report) ~= "table"
      or (message.reasonCode ~= nil and type(message.reasonCode) ~= "string") then
      return false, "INVALID_REPAIR_ACK"
    end
    peer.syncProbe = { requestId = message.requestId, receivedAt = time(), report = copy(message.report),
      repair = { result = message.result, reasonCode = message.reasonCode } }
    peer.baselineHash = message.report.baselineHash
    state.peers[resolved.memberKey] = peer
    return true, "REPAIR_ACK_ACCEPTED"
  end
  if message.type == "SYNC_PROBE" then
    if type(message.requestId) ~= "string" or message.requestId == "" then return false, "INVALID_SYNC_PROBE" end
    return Sync.Send({ type = "SYNC_PROBE_RESPONSE", requestId = message.requestId, report = Sync.BuildSyncProbeReport() }, "WHISPER", resolved.displayName)
  end
  if message.type == "SYNC_PROBE_RESPONSE" then
    if type(message.requestId) ~= "string" or type(message.report) ~= "table" then return false, "INVALID_SYNC_PROBE_RESPONSE" end
    peer.syncProbe = { requestId = message.requestId, receivedAt = time(), report = copy(message.report) }
    peer.baselineHash = message.report.baselineHash
    if type(message.report.entityDigests) == "table" then peer.entities = copy(message.report.entityDigests) end
    state.peers[resolved.memberKey] = peer
    return true, "SYNC_PROBE_ACCEPTED"
  end
  if message.type == "TRANSFER_ACK" then
    if type(message.transferId) ~= "string" or message.entityType ~= "LEGACY_BASELINE"
      or (message.result ~= "APPLIED" and message.result ~= "REJECTED") then
      return false, "INVALID_TRANSFER_ACK"
    end
    peer.transferAck = { transferId = message.transferId, entityId = message.entityId,
      result = message.result, reasonCode = message.reasonCode, receivedChunks = tonumber(message.receivedChunks) or 0,
      chunkCount = tonumber(message.chunkCount) or 0, receivedAt = time() }
    state.peers[resolved.memberKey] = peer
    return true, "TRANSFER_ACK_ACCEPTED"
  end
  if message.type == "HELLO" then
    if message.protocolState == "V2_ENFORCED" then return false, "PROTOCOL_LEGACY_READ_ONLY" end
    return true, "HELLO"
  end
  if message.type == "CHANNEL_TEST" then
    local testId, testChannel = message.testId, message.testChannel
    local receivedChannel = channel or testChannel
    if type(testId) ~= "string" or testId == "" or #testId > 128
      or not CHANNEL_TEST_CHANNELS[testChannel] or not finiteInteger(message.startedAt) then
      return false, "INVALID_CHANNEL_TEST"
    end
    if receivedChannel ~= testChannel then
      recordChannelTest({ direction = "RECEIVE", channel = receivedChannel, peer = resolved.displayName,
        status = "REJECTED", reasonCode = "CHANNEL_MISMATCH_EXPECTED_" .. tostring(testChannel), startedAt = time() })
      return false, "CHANNEL_MISMATCH"
    end
    if testChannel == "CHANNEL" then
      if type(message.channelName) ~= "string" or type(GetChannelName) ~= "function" then
        recordChannelTest({ direction = "RECEIVE", channel = testChannel, channelName = message.channelName,
          peer = resolved.displayName, status = "REJECTED", reasonCode = "CUSTOM_CHANNEL_API_UNAVAILABLE", startedAt = time() })
        return false, "CUSTOM_CHANNEL_API_UNAVAILABLE"
      end
      local channelId = tonumber(GetChannelName(message.channelName))
      if not channelId or channelId < 1 then
        recordChannelTest({ direction = "RECEIVE", channel = testChannel, channelName = message.channelName,
          peer = resolved.displayName, status = "REJECTED", reasonCode = "CUSTOM_CHANNEL_NOT_JOINED", startedAt = time() })
        return false, "CUSTOM_CHANNEL_NOT_JOINED"
      end
    end
    if not (Dibs.DeveloperMode and Dibs.DeveloperMode.IsEnabled and Dibs.DeveloperMode.IsEnabled()) then
      recordChannelTest({ testId = testId, direction = "RECEIVE", channel = testChannel,
        peer = resolved.displayName, status = "IGNORED", reasonCode = "DEVELOPER_MODE_REQUIRED", startedAt = time() })
      refreshChannelTestUI()
      return false, "DEVELOPER_MODE_REQUIRED"
    end
    if not markChannelTestResponded(resolved.memberKey, testId) then
      return true, "CHANNEL_TEST_DUPLICATE"
    end
    if not allowChannelTestResponse(resolved.memberKey) then
      local reasonCode = "CHANNEL_TEST_RATE_LIMITED"
      recordChannelTest({ testId = testId, direction = "RECEIVE", channel = testChannel,
        peer = resolved.displayName, status = "RATE_LIMITED", reasonCode = reasonCode, startedAt = time() })
      return false, reasonCode
    end
    local sent, sendReason = Sync.Send({ type = "CHANNEL_TEST_ACK", testId = testId,
      testChannel = testChannel, ackTransport = "WHISPER", result = "RECEIVED",
      reasonCode = "CHANNEL_MESSAGE_VALIDATED" }, "WHISPER", resolved.displayName)
    recordChannelTest({ testId = testId, direction = "RECEIVE", channel = testChannel,
      peer = resolved.displayName, status = sent and "ACK_QUEUED" or "ACK_SEND_FAILED",
      reasonCode = sent and "CHANNEL_MESSAGE_VALIDATED" or (sendReason or "ACK_SEND_FAILED"), startedAt = time() })
    refreshChannelTestUI()
    return true, sent and "CHANNEL_TEST_ACK_QUEUED" or "CHANNEL_TEST_ACK_SEND_FAILED"
  end
  if message.type == "CHANNEL_TEST_ACK" then
    local testId = message.testId
    if type(testId) ~= "string" or testId == "" or #testId > 128
      or not CHANNEL_TEST_CHANNELS[message.testChannel]
      or (message.result ~= "RECEIVED" and message.result ~= "REJECTED")
      or type(message.reasonCode) ~= "string" then return false, "INVALID_CHANNEL_TEST_ACK" end
    if message.ackTransport == "WHISPER" then
      if channel ~= "WHISPER" then return false, "CHANNEL_MISMATCH" end
    elseif message.ackTransport ~= nil or (channel or message.testChannel) ~= message.testChannel then
      return false, "CHANNEL_MISMATCH"
    end
    local state = channelTestState()
    local pending = state.pending[testId]
    if not pending then return true, "CHANNEL_TEST_ACK_LATE_OR_UNKNOWN" end
    if pending.channel ~= message.testChannel then return false, "CHANNEL_TEST_ACK_WRONG_CHANNEL" end
    pending.responders = pending.responders or {}
    for _, responder in ipairs(pending.responders) do
      if responder.memberKey == resolved.memberKey then return true, "CHANNEL_TEST_ACK_DUPLICATE" end
    end
    pending.status = message.result == "RECEIVED" and "ACKNOWLEDGED" or "REMOTE_REJECTED"
    pending.reasonCode = message.reasonCode
    pending.responders[#pending.responders + 1] = { player = resolved.displayName, memberKey = resolved.memberKey,
      result = message.result, reasonCode = message.reasonCode, receivedAt = time() }
    recordChannelTest(pending)
    refreshChannelTestUI()
    return true, "CHANNEL_TEST_ACK_APPLIED"
  end
  if message.type == "AWARD_RESERVATION_DIGEST" then
    local entries = message.records
    if resolved.role ~= "gm" and resolved.role ~= "officer" then return false, "RESERVATION_SENDER_AUTHORITY_REQUIRED" end
    if type(entries) ~= "table" or #entries > MAX_INDEX or type(message.contentHash) ~= "string"
      or hash(entries) ~= message.contentHash then return false, "INVALID_AWARD_RESERVATION_DIGEST" end
    local validated, seen = {}, {}
    for _, entry in ipairs(entries) do
      if type(entry) ~= "table" or type(entry.proposalId) ~= "string" or entry.proposalId == ""
        or type(entry.playerMemberKey) ~= "string" or type(entry.actorMemberKey) ~= "string"
        or not finiteInteger(entry.amount) or tonumber(entry.amount) <= 0
        or type(entry.seasonId) ~= "string" or entry.seasonId == ""
        or entry.state ~= "PENDING" or not finiteInteger(entry.updatedAt)
        or seen[entry.proposalId] then return false, "INVALID_AWARD_RESERVATION_DIGEST" end
      if (entry.awardRef ~= nil and type(entry.awardRef) ~= "string")
        or (entry.evidenceId ~= nil and type(entry.evidenceId) ~= "string")
        or (entry.ledgerId ~= nil and (type(entry.ledgerId) ~= "string" or entry.ledgerId == "" or #entry.ledgerId > 64)) then
        return false, "INVALID_AWARD_RESERVATION_DIGEST"
      end
      local player = member(entry.playerMemberKey)
      local actor = member(entry.actorMemberKey)
      if not player or not actor or (actor.role ~= "gm" and actor.role ~= "officer") then
        return false, "INVALID_AWARD_RESERVATION_IDENTITY"
      end
      seen[entry.proposalId] = true
      validated[#validated + 1] = copy(entry)
    end
    for _, entry in ipairs(validated) do
      local tombstone = state.awardReservationTombstones[entry.proposalId]
      if not tombstone or tonumber(entry.updatedAt) > (tonumber(tombstone.updatedAt) or 0) then
        if reservationHasCanonicalCommit(entry) then
          Sync.ClearAwardReservation(entry.proposalId)
        else
          local existing = state.awardReservations[entry.proposalId]
          if not existing or tonumber(entry.updatedAt) >= (tonumber(existing.updatedAt) or 0) then
            local changed = not existing
              or existing.playerMemberKey ~= entry.playerMemberKey
              or existing.seasonId ~= entry.seasonId
              or existing.amount ~= entry.amount
              or existing.state ~= entry.state
            state.awardReservations[entry.proposalId] = entry
            if changed then
              if existing and existing.playerMemberKey ~= entry.playerMemberKey then
                bumpAwardReservationGeneration(existing.playerMemberKey)
              end
              bumpAwardReservationGeneration(entry.playerMemberKey)
            end
          end
        end
      end
    end
    boundMap(state.awardReservations, MAX_INDEX)
    return true, "AWARD_RESERVATIONS_APPLIED"
  end
  if message.type == "AWARD_PROPOSAL_ACK" then
    if type(message.proposalId) ~= "string" or message.proposalId == "" then return false, "INVALID_PROPOSAL_ACK" end
    local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
    if not authority or authority.state ~= "ACTIVE" or not authority.coordinator or authority.coordinator.memberKey ~= resolved.memberKey then
      return false, "CURRENT_COORDINATOR_REQUIRED"
    end
    if message.result == "STALE" or message.result == "REJECTED" then
      local resolvedProposal = Dibs.Governance and Dibs.Governance.ResolveAwardProposal
        and Dibs.Governance.ResolveAwardProposal(message.proposalId, message.result, message.reasonCode)
      if not resolvedProposal then return false, "PROPOSAL_TERMINAL_UPDATE_UNAVAILABLE" end
      return true, "PROPOSAL_" .. message.result
    end
    if message.result ~= nil and message.result ~= "RECEIVED" then return false, "INVALID_PROPOSAL_ACK_RESULT" end
    local acknowledged = false
    local acknowledgementReason = "PROPOSAL_ACK_UNAVAILABLE"
    if Dibs.Governance and Dibs.Governance.AckProposalRelay then
      local acknowledgement = { Dibs.Governance.AckProposalRelay(message.proposalId) }
      acknowledged, acknowledgementReason = acknowledgement[1], acknowledgement[2]
    end
    if not acknowledged then return false, acknowledgementReason or "PROPOSAL_ACK_UNAVAILABLE" end
    return true, "PROPOSAL_ACK_APPLIED"
  end
  if message.type == "LEDGER_OPERATION_PROPOSAL_ACK" then
    if Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED ~= true then return false, "CANONICAL_DISPUTE_OPERATIONS_DISABLED" end
    if type(message.proposalId) ~= "string" or message.proposalId == ""
      or message.result ~= "RECEIVED" then return false, "INVALID_OPERATION_PROPOSAL_ACK" end
    local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
    if not authority or authority.state ~= "ACTIVE" or not authority.coordinator
      or authority.coordinator.memberKey ~= resolved.memberKey then return false, "CURRENT_COORDINATOR_REQUIRED" end
    local localName = Dibs.GetPlayerName and Dibs.GetPlayerName()
    local acknowledged, acknowledgementReason = Dibs.Governance and Dibs.Governance.AcknowledgeDisputeProposal
      and Dibs.Governance.AcknowledgeDisputeProposal(localName, message.proposalId, resolved.memberKey)
    if not acknowledged then return false, acknowledgementReason or "PROPOSAL_ACK_UNAVAILABLE" end
    return true, "OPERATION_PROPOSAL_ACK_APPLIED"
  end
  if message.type == "VAULT_DIGEST" then
    local entries = message.records or message.entries
    if type(entries) ~= "table" or #entries > MAX_INDEX then return false, "INVALID_VAULT_DIGEST" end
    local needed = {}
    for _, entry in ipairs(entries) do
      if type(entry) ~= "table" or type(entry.acquisitionId) ~= "string"
        or not finiteInteger(entry.revision) or type(entry.contentHash) ~= "string" then
        return false, "INVALID_VAULT_DIGEST"
      end
      local current = Dibs.PreDibs.GetVaultAcquisition and Dibs.PreDibs.GetVaultAcquisition(entry.acquisitionId)
      local currentRevision = current and (tonumber(current.revision) or 1) or 0
      if tonumber(entry.revision) > currentRevision then
        needed[#needed + 1] = { acquisitionId = entry.acquisitionId, revision = entry.revision, contentHash = entry.contentHash }
        rememberVaultRequests({ needed[#needed] }, resolved.displayName)
      elseif tonumber(entry.revision) == currentRevision and current and vaultHash(current) ~= entry.contentHash then
        return false, "CONFLICT"
      else
        clearVaultRequest(entry.acquisitionId)
      end
    end
    if #needed > 0 then
      Sync.MarkSyncBehind("VAULT_DETAIL_MISSING")
      Sync.Send(Sync.BuildVaultFetch(needed), "WHISPER", resolved.displayName)
      return true, "VAULT_DETAIL_REQUESTED"
    end
    return true, "VAULT_DIGEST_CURRENT"
  end
  if message.type == "VAULT_FETCH" then
    if type(message.requests) ~= "table" or #message.requests > 32 then return false, "INVALID_VAULT_FETCH" end
    for _, request in ipairs(message.requests) do
      if type(request) ~= "table" or type(request.acquisitionId) ~= "string" or not finiteInteger(request.revision)
        or type(request.contentHash) ~= "string" then return false, "INVALID_VAULT_FETCH" end
      local record = Dibs.PreDibs.GetVaultAcquisition and Dibs.PreDibs.GetVaultAcquisition(request.acquisitionId)
      if record and (isAdmin(resolved.displayName) or member(record.playerName) and member(record.playerName).memberKey == resolved.memberKey) then
        Sync.SendDetail("VAULT_DETAIL", record.acquisitionId, tonumber(record.revision) or 1, vaultHash(record), record, resolved.displayName)
      end
    end
    return true, "VAULT_DETAIL_SENT"
  end
  if message.type == "VAULT_DETAIL" then
    local payload = message.acquisition or message.payload
    if type(payload) ~= "table" or type(message.acquisitionId) ~= "string"
      or payload.acquisitionId ~= message.acquisitionId or not finiteInteger(message.revision)
      or tonumber(payload.revision) ~= tonumber(message.revision) or type(message.contentHash) ~= "string" then
      return false, "INVALID_VAULT_DETAIL"
    end
    return applyVaultDetail(payload, { entityId = message.acquisitionId, revision = message.revision, contentHash = message.contentHash }, resolved)
  end
  if message.type == "VAULT_ACK" then
    if type(message.acquisitionId) ~= "string" or not finiteInteger(message.revision)
      or type(message.result or message.outcome) ~= "string" then
      return false, "INVALID_VAULT_ACK"
    end
    return true, "VAULT_ACK_ACCEPTED"
  end
  if message.type == "LEDGER_DIGEST" then
    if not (Dibs.Governance and Dibs.Governance.IsV2Enforced and Dibs.Governance.IsV2Enforced()) then
      if message.revision and tonumber(message.revision) > 0 then Sync.MarkSyncBehind("LEDGER_ENFORCEMENT_MISSING") end
      return true, "LEDGER_DIGEST_ONLY"
    end
    if not finiteInteger(message.ledgerEpoch) or not finiteInteger(message.lastSeq) or type(message.rootHash) ~= "string"
      or message.contentHash ~= message.rootHash then return false, "INVALID_LEDGER_DIGEST" end
    local ledgerId = message.ledgerId
    if ledgerId == nil then ledgerId = "guild-primary" end
    if not isApprovedLedger(ledgerId) then return false, "LEDGER_NOT_APPROVED" end
    local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
    if not authority or authority.state ~= "ACTIVE" or not authority.coordinator then return false, "AUTHORITY_UNAVAILABLE" end
    local localState = Dibs.Ledger and Dibs.Ledger.GetCanonicalState and Dibs.Ledger.GetCanonicalState(ledgerId) or {}
    if not localState then return false, "LEDGER_NOT_APPROVED" end
    if tonumber(message.ledgerEpoch) ~= tonumber(localState.epoch) then return false, "STALE_EPOCH" end
    if authority.coordinator.memberKey ~= resolved.memberKey then return true, "LEDGER_STATUS_ONLY" end
    local localLast = tonumber(localState.nextSeq or 1) - 1
    if tonumber(message.lastSeq) > localLast then
      local state = ensure()
      local target = { ledgerId = ledgerId, epoch = message.ledgerEpoch, lastSeq = message.lastSeq, rootHash = message.rootHash, source = resolved.displayName }
      ledgerSyncState(state, ledgerId).target = target
      if ledgerId == "guild-primary" then state.ledgerTarget = target end
      Sync.MarkSyncBehind("LEDGER_GAP")
      requestLedgerBatch(resolved.displayName, state, target, localLast)
      return true, "LEDGER_DETAIL_REQUESTED"
    end
    if tonumber(message.lastSeq) == localLast and message.rootHash ~= localState.rootHash then
      Sync.MarkSyncBehind("CANONICAL_ROOT_CONFLICT")
      return false, "CANONICAL_ROOT_CONFLICT"
    end
    return true, "LEDGER_CURRENT"
  end
  if message.type == "LEDGER_DELETE" then
    if resolved.role ~= "gm" then return false, "GUILD_MASTER_REQUIRED" end
    if type(message.ledgerId) ~= "string" or message.ledgerId == ""
      or type(message.deletedBy) ~= "string" or not finiteInteger(message.timestamp) then
      return false, "INVALID_LEDGER_DELETE"
    end
    if message.name ~= nil and (type(message.name) ~= "string" or message.name == "" or #message.name > 50) then
      return false, "INVALID_LEDGER_DELETE"
    end
    if message.deletedBy ~= resolved.displayName then return false, "SENDER_IDENTITY_MISMATCH" end
    if not (Dibs.Governance and type(Dibs.Governance.RecordLedgerDeletion) == "function") then
      return false, "AUDIT_UNAVAILABLE"
    end
    local recorded, recordReason = Dibs.Governance.RecordLedgerDeletion(
      resolved.displayName, message.ledgerId, message.name)
    if not recorded then return false, recordReason or "AUDIT_RECORD_FAILED" end
    local result = Dibs.MultiLedger and Dibs.MultiLedger.ApplyLedgerDeletion
      and Dibs.MultiLedger.ApplyLedgerDeletion(resolved.displayName, message.ledgerId, {
        timestamp = message.timestamp, deletedBy = message.deletedBy, name = message.name, verifiedTombstone = true,
      })
    if not result or not result.ok then return false, result and result.reasonCode or "LEDGER_DELETE_FAILED" end
    return true, "LEDGER_DELETED"
  end
  if message.type == "DIGEST" and message.entityType == "GOVERNANCE" then
    if not finiteInteger(message.revision) or type(message.contentHash) ~= "string" then return false, "INVALID_GOVERNANCE_DIGEST" end
    if resolved.role ~= "gm" then return receiveRelayDigest("GOVERNANCE", message, resolved, "INVALID_GOVERNANCE_DIGEST") end
    rememberTrustedDigest("GOVERNANCE", message.revision, message.contentHash, resolved)
    if type(message.baselineHash) == "string" and message.baselineHash ~= "" then
      rememberTrustedDigest("LEGACY_BASELINE", 1, message.baselineHash, resolved)
    end
    local current = Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState() or { revision = 0, hash = "GENESIS" }
    if tonumber(message.revision) > (tonumber(current.revision) or 0) then
      ensure().governanceTarget = { revision = message.revision, contentHash = message.contentHash, parentHash = message.parentHash, source = resolved.displayName }
      Sync.MarkSyncBehind("GOVERNANCE_PARENT_MISSING")
      sendDetailFetch({ { entityType = "GOVERNANCE", entityId = tostring(message.revision), revision = message.revision, contentHash = message.contentHash, parentHash = message.parentHash } }, resolved.displayName)
      return true, "GOVERNANCE_DETAIL_REQUESTED"
    end
    if tonumber(message.revision) == (tonumber(current.revision) or 0) and message.contentHash ~= current.hash then
      Sync.MarkSyncBehind("GOVERNANCE_CONFLICT")
      return false, "GOVERNANCE_CONFLICT"
    end
    local governanceTarget = ensure().governanceTarget
    if not governanceTarget or (tonumber(current.revision) or 0) >= (tonumber(governanceTarget.revision) or 0) then
      ensure().governanceTarget = nil
      clearSyncBehindReasons("GOVERNANCE_PARENT_MISSING")
    end
    local baseline = Dibs.HistoricalBaseline and Dibs.HistoricalBaseline.GetBaseline and Dibs.HistoricalBaseline.GetBaseline() or {}
    if message.baselineHash and baseline.legacyBaselineHash ~= message.baselineHash then
      sendDetailFetch({ {
        entityType = "LEGACY_BASELINE", entityId = message.baselineHash, revision = 1, contentHash = message.baselineHash,
      } }, resolved.displayName)
      return true, "LEGACY_BASELINE_REQUESTED"
    end
    return true, "GOVERNANCE_CURRENT"
  end
  if message.type == "DIGEST" and message.entityType == "OPERATIONAL_POLICY" then
    if not finiteInteger(message.revision) or type(message.contentHash) ~= "string" then return false, "INVALID_POLICY_DIGEST" end
    local writerAllowed = false
    local writerReason = "POLICY_WRITER_REQUIRED"
    if Dibs.OperationalPolicy and Dibs.OperationalPolicy.CanWrite then
      local authorization = { Dibs.OperationalPolicy.CanWrite(resolved.displayName) }
      writerAllowed, writerReason = authorization[1], authorization[2]
    end
    if not writerAllowed then return receiveRelayDigest("OPERATIONAL_POLICY", message, resolved, writerReason or "POLICY_WRITER_REQUIRED") end
    rememberTrustedDigest("OPERATIONAL_POLICY", message.revision, message.contentHash, resolved)
    local current = Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetState and Dibs.OperationalPolicy.GetState() or { policyRevision = 0, hash = "GENESIS" }
    if tonumber(message.revision) > (tonumber(current.policyRevision) or 0) then
      local target = rememberChainTarget("policyTarget", message.revision, message.contentHash, resolved.displayName, "POLICY_CONFLICT")
      if not target then return false, "POLICY_CONFLICT" end
      Sync.MarkSyncBehind("POLICY_CHAIN_MISSING")
      requestNextRevision("OPERATIONAL_POLICY", target, current.policyRevision)
      return true, "POLICY_DETAIL_REQUESTED"
    end
    if tonumber(message.revision) == (tonumber(current.policyRevision) or 0) and message.contentHash ~= current.hash then
      Sync.MarkSyncBehind("POLICY_CONFLICT")
      return false, "POLICY_CONFLICT"
    end
    return true, "POLICY_CURRENT"
  end
  if message.type == "DIGEST" and message.entityType == "LEDGER_CATALOG" then
    if resolved.role ~= "gm" then return false, "GUILD_MASTER_REQUIRED" end
    if type(message.ledgers) ~= "table" then return false, "INVALID_LEDGER_CATALOG" end
    for id, remoteLedger in pairs(message.ledgers) do
      if type(id) ~= "string" or type(remoteLedger) ~= "table" or remoteLedger.id ~= id
        or remoteLedger.status ~= "APPROVED" or type(remoteLedger.name) ~= "string"
        or not finiteInteger(remoteLedger.approvedAt) or type(remoteLedger.approvedBy) ~= "string"
        or not finiteInteger(remoteLedger.epoch) or not finiteInteger(remoteLedger.revision)
        or type(remoteLedger.rootHash) ~= "string" then
        return false, "INVALID_LEDGER_CATALOG"
      end
    end
    local db = Dibs.GetDB and Dibs.GetDB()
    if not db then return false, "DB_UNAVAILABLE" end
    db.ledgers = db.ledgers or {}
    db.ledgerDeletionTombstones = db.ledgerDeletionTombstones or {}
    for id, remoteLedger in pairs(message.ledgers) do
      if not db.ledgerDeletionTombstones[id]
        and type(remoteLedger) == "table" and remoteLedger.status == "APPROVED" then
        local approvalApplied, approvalReason = Dibs.Governance and Dibs.Governance.ApplyLedgerApproval
          and Dibs.Governance.ApplyLedgerApproval(resolved.displayName, remoteLedger)
        if not approvalApplied then return false, approvalReason or "LEDGER_APPROVAL_FAILED" end
        if id ~= "guild-primary" then
          local approved, approvalReason = Dibs.Governance.ApplyLedgerApproval
            and Dibs.Governance.ApplyLedgerApproval(resolved.displayName, remoteLedger)
          if not approved then return false, approvalReason or "LEDGER_APPROVAL_FAILED" end
        end
        if not db.ledgers[id] then
          db.ledgers[id] = {
            id = id,
            name = remoteLedger.name or id,
            status = "APPROVED",
            createdAt = remoteLedger.createdAt or time(),
            createdBy = remoteLedger.createdBy or "REMOTE",
            approvedAt = remoteLedger.approvedAt or time(),
            approvedBy = remoteLedger.approvedBy or resolved.displayName,
            isDefault = id == "guild-primary",
            transactions = {},
            playerStates = {},
            awardTransactions = {},
            evidenceTransactions = {},
            canonical = { schema = 1, epoch = remoteLedger.epoch, nextSeq = 1, rootHash = remoteLedger.rootHash, commits = {}, transactionIndex = {}, positions = {} },
          }
        elseif db.ledgers[id].status == "PROPOSED" then
          db.ledgers[id].status = "APPROVED"
          db.ledgers[id].approvedAt = remoteLedger.approvedAt or time()
          db.ledgers[id].approvedBy = remoteLedger.approvedBy or resolved.displayName
        end
      end
    end
    return true, "LEDGER_CATALOG_SYNCED"
  end
  if message.type == "DIGEST" and message.entityType == "SEASON_CATALOG" then
    if not finiteInteger(message.revision) or type(message.contentHash) ~= "string" then return false, "INVALID_SEASON_CATALOG_DIGEST" end
    local writerAllowed = false
    local writerReason = "POLICY_WRITER_REQUIRED"
    if Dibs.OperationalPolicy and Dibs.OperationalPolicy.CanWrite then
      writerAllowed, writerReason = Dibs.OperationalPolicy.CanWrite(resolved.displayName)
    end
    if not writerAllowed then return receiveRelayDigest("SEASON_CATALOG", message, resolved, writerReason or "POLICY_WRITER_REQUIRED") end
    rememberTrustedDigest("SEASON_CATALOG", message.revision, message.contentHash, resolved)
    local current = Dibs.Seasons and Dibs.Seasons.GetCatalogState and Dibs.Seasons.GetCatalogState() or { catalogRevision = 0, hash = "GENESIS" }
    if tonumber(message.revision) > (tonumber(current.catalogRevision) or 0) then
      local target = rememberChainTarget("seasonCatalogTarget", message.revision, message.contentHash, resolved.displayName, "SEASON_CATALOG_CONFLICT")
      if not target then return false, "SEASON_CATALOG_CONFLICT" end
      Sync.MarkSyncBehind("SEASON_CATALOG_PARENT_MISSING")
      requestNextRevision("SEASON_CATALOG", target, current.catalogRevision)
      return true, "SEASON_CATALOG_DETAIL_REQUESTED"
    end
    if tonumber(message.revision) == (tonumber(current.catalogRevision) or 0) and message.contentHash ~= current.hash then
      Sync.MarkSyncBehind("SEASON_CATALOG_CONFLICT")
      return false, "SEASON_CATALOG_CONFLICT"
    end
    return true, "SEASON_CATALOG_CURRENT"
  end
  if message.type == "DIGEST" and message.entityType == "AUTHORITY" then
    if not isAdmin(resolved.displayName) or type(message.contentHash) ~= "string" then return false, "INVALID_AUTHORITY_DIGEST" end
    local localSignal = Dibs.Governance and Dibs.Governance.BuildAuthoritySignal and Dibs.Governance.BuildAuthoritySignal()
    if not localSignal or localSignal.contentHash ~= message.contentHash then
      ensure().authorityTarget = { entityId = message.entityId, contentHash = message.contentHash, source = resolved.displayName }
      Sync.MarkSyncBehind("AUTHORITY_DETAIL_MISSING")
      sendDetailFetch({ { entityType = "AUTHORITY_SIGNAL", entityId = message.entityId, revision = 1, contentHash = message.contentHash } }, resolved.displayName)
      return true, "AUTHORITY_DETAIL_REQUESTED"
    end
    local authorityTarget = ensure().authorityTarget
    if not authorityTarget or authorityTarget.contentHash == message.contentHash then
      ensure().authorityTarget = nil
      clearSyncBehindReasons("AUTHORITY_DETAIL_MISSING")
    end
    return true, "AUTHORITY_CURRENT"
  end
  if message.type == "DIGEST" then
    if message.entityType ~= "PREDIB_INDEX" or type(message.index) ~= "table" or #message.index > MAX_INDEX
      or type(message.contentHash) ~= "string" or hash(message.index) ~= message.contentHash then return false, "INVALID_DIGEST" end
    local ledgerId = message.ledgerId or "guild-primary"
    if not isApprovedLedger(ledgerId) then return false, "LEDGER_NOT_APPROVED" end
    local needed = {}
    local localMember = localSnapshot()
    local senderIsAdmin = resolved.role == "gm" or resolved.role == "officer"
    local adminExchange = (resolved.role == "gm" or resolved.role == "officer")
      and (localRole() == "gm" or localRole() == "officer")
    for _, entry in ipairs(message.index) do
      if type(entry) ~= "table" or type(entry.requestId) ~= "string" or not finiteInteger(entry.revision)
        or type(entry.contentHash) ~= "string" or (entry.ledgerId ~= nil and entry.ledgerId ~= ledgerId)
        or (ledgerId ~= "guild-primary" and entry.ledgerId ~= ledgerId) then return false, "INVALID_DIGEST" end
    end
    local requestsById = Dibs.PreDibs and Dibs.PreDibs.GetHistoryLookup
      and Dibs.PreDibs.GetHistoryLookup(ledgerId) or nil
    if type(requestsById) ~= "table" then
      requestsById = {}
      for _, request in ipairs(Dibs.PreDibs and Dibs.PreDibs.GetHistory
        and Dibs.PreDibs.GetHistory(ledgerId) or {}) do
        if type(request) == "table" and type(request.requestId) == "string"
          and requestsById[request.requestId] == nil then
          requestsById[request.requestId] = request
        end
      end
    end
    for _, entry in ipairs(message.index) do
      local current = requestsById[entry.requestId]
      local currentRevision = current and (tonumber(current.revision) or 1) or 0
      if tonumber(entry.revision) > currentRevision then
        -- Only fetch details this sender will serve and this client will accept
        -- (owner, officer-to-officer relay, or restoring the recipient's own
        -- request from an Officer); otherwise the client would stay
        -- behind forever waiting for a detail that is never sent. Entries without
        -- an owner name keep the previous fetch behavior.
        local owner = type(entry.playerName) == "string" and member(entry.playerName) or nil
        local ownerRecovery = owner and localMember and owner.memberKey == localMember.memberKey and senderIsAdmin
        if entry.playerName == nil or (owner and (owner.memberKey == resolved.memberKey or adminExchange or ownerRecovery)) then
          needed[#needed + 1] = { entityType = "PREDIB_REQUEST", entityId = entry.requestId,
            ledgerId = ledgerId, revision = entry.revision, contentHash = entry.contentHash }
          rememberPredibRequest(needed[#needed], resolved.displayName)
        end
      end
      if tonumber(entry.revision) == currentRevision and current and requestHash(current) ~= entry.contentHash then return false, "REQUEST_CONFLICT" end
    end
    if #needed > 0 then Sync.MarkSyncBehind("MISSING_DETAIL"); sendPredibFetches(needed, resolved.displayName) end
    return true, #needed > 0 and "DETAIL_REQUESTED" or "DIGEST_CURRENT"
  end
  if message.type == "DETAIL_FETCH" then
    if type(message.requests) ~= "table" or #message.requests > 32 then return false, "INVALID_FETCH" end
    for _, requested in ipairs(message.requests) do
      if requested.entityType == "PREDIB_REQUEST" and type(requested.entityId) == "string" then
        local ledgerId = requested.ledgerId
        if ledgerId == nil then ledgerId = "guild-primary" end
        if not isApprovedLedger(ledgerId) then return false, "LEDGER_NOT_APPROVED" end
        local request = localRequest(requested.entityId, ledgerId)
        local owner = request and member(request.playerName)
        local localMember = localSnapshot()
        local ownerIsLocal = owner and localMember and owner.memberKey == localMember.memberKey
        local recipientIsOwner = owner and owner.memberKey == resolved.memberKey
        local localIsAdmin = localRole() == "gm" or localRole() == "officer"
        local officerRelay = (localRole() == "gm" or localRole() == "officer")
          and (resolved.role == "gm" or resolved.role == "officer")
        if request and owner and (ownerIsLocal or officerRelay or (localIsAdmin and recipientIsOwner)) then
          requestDetail(resolved.displayName, requested.entityId, ledgerId, recipientIsOwner and not isAdmin(resolved.displayName))
        end
      elseif requested.entityType == "GOVERNANCE" then
        local governanceState = Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState()
        local record = governanceState and governanceState.records and governanceState.records[tostring(requested.revision)]
        if record and tonumber(record.governanceRevision) == tonumber(requested.revision)
          and (not requested.contentHash or requested.contentHash == record.contentHash) then
          local baseline = Dibs.HistoricalBaseline and Dibs.HistoricalBaseline.GetBaseline and Dibs.HistoricalBaseline.GetBaseline()
          if baseline and baseline.legacyBaselineHash then
            Sync.SendDetail("LEGACY_BASELINE", baseline.legacyBaselineHash, 1, baseline.legacyBaselineHash, baseline, resolved.displayName)
          end
          local current = Dibs.Governance.GetState()
          local firstRevision = math.max(1, tonumber(requested.parentRevision) and tonumber(requested.parentRevision) + 1 or 1)
          for revision = firstRevision, tonumber(requested.revision) do
            local nextRecord = current.records and current.records[tostring(revision)]
            if not nextRecord then break end
            Sync.SendDetail("GOVERNANCE", tostring(nextRecord.governanceRevision), nextRecord.governanceRevision, nextRecord.contentHash, nextRecord, resolved.displayName)
          end
        end
      elseif requested.entityType == "LEGACY_BASELINE" then
        local baseline = Dibs.HistoricalBaseline and Dibs.HistoricalBaseline.GetBaseline and Dibs.HistoricalBaseline.GetBaseline()
        if baseline and baseline.legacyBaselineHash and (not requested.contentHash or requested.contentHash == baseline.legacyBaselineHash) then
          Sync.SendDetail("LEGACY_BASELINE", baseline.legacyBaselineHash, 1, baseline.legacyBaselineHash, baseline, resolved.displayName)
        end
      elseif requested.entityType == "OPERATIONAL_POLICY" and Dibs.OperationalPolicy then
        local record = Dibs.OperationalPolicy.GetRecord and Dibs.OperationalPolicy.GetRecord(requested.revision)
        if record and tonumber(record.policyRevision) == tonumber(requested.revision)
          and (not requested.contentHash or requested.contentHash == record.contentHash) then
          Sync.SendDetail("OPERATIONAL_POLICY", tostring(record.policyRevision), record.policyRevision, record.contentHash, record, resolved.displayName)
        end
      elseif requested.entityType == "SEASON_CATALOG" and Dibs.Seasons then
        local record = Dibs.Seasons.GetCatalogRecord and Dibs.Seasons.GetCatalogRecord(requested.revision)
        if record and tonumber(record.catalogRevision) == tonumber(requested.revision)
          and (not requested.contentHash or requested.contentHash == record.contentHash) then
          Sync.SendDetail("SEASON_CATALOG", tostring(record.catalogRevision), record.catalogRevision, record.contentHash, record, resolved.displayName)
        end
      elseif requested.entityType == "AUTHORITY_SIGNAL" and Dibs.Governance and Dibs.Governance.BuildAuthoritySignal then
        local signal = Dibs.Governance.BuildAuthoritySignal()
        if signal and signal.state ~= "LEGACY_LOCAL" and (localRole() == "gm" or (signal.coordinator and signal.coordinator.memberKey == (localSnapshot() or {}).memberKey)) then
          Sync.SendAuthoritySignal(resolved.displayName)
        end
      elseif (requested.entityType == "AWARD_COMMIT" or requested.entityType == "LEDGER_OPERATION_COMMIT")
        and Dibs.Ledger and Dibs.Ledger.GetCanonicalCommit then
        local epoch, sequence = tostring(requested.entityId or ""):match("^(%d+):(%d+)$")
        local ledgerId = requested.ledgerId or "guild-primary"
        local commit = isApprovedLedger(ledgerId) and epoch and sequence
          and Dibs.Ledger.GetCanonicalCommit(tonumber(epoch), tonumber(sequence), ledgerId)
        local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
        local localMember = localSnapshot()
        if commit and authority and authority.state == "ACTIVE" and localMember and authority.coordinator
          and authority.coordinator.memberKey == localMember.memberKey then
          if commit.recordClass == "LEDGER_OPERATION_COMMIT" then Sync.SendOperationCommit(commit, resolved.displayName)
          else Sync.SendAwardCommit(commit, resolved.displayName) end
        end
      end
    end
    return true, "DETAIL_SENT"
  end
  if message.type == "TRANSFER_BEGIN" then
    if type(message.transferId) ~= "string" or #message.transferId > 128 or type(message.entityType) ~= "string" or type(message.entityId) ~= "string" or not finiteInteger(message.revision) or not finiteInteger(message.chunkCount) or message.chunkCount < 1 or message.chunkCount > MAX_CHUNKS or type(message.contentHash) ~= "string" or type(message.payloadHash) ~= "string" then return false, "INVALID_TRANSFER_BEGIN" end
    if message.entityType ~= "PREDIB_REQUEST" and message.entityType ~= "VAULT_DETAIL" and message.entityType ~= "GOVERNANCE" and message.entityType ~= "OPERATIONAL_POLICY" and message.entityType ~= "LEGACY_BASELINE" and message.entityType ~= "LEGACY_RECOVERY_PACKAGE" and message.entityType ~= "AUTHORITY_SIGNAL" and message.entityType ~= "AUTHORITY_ORPHAN" and message.entityType ~= "AWARD_COMMIT" and message.entityType ~= "LEDGER_OPERATION_COMMIT" and message.entityType ~= "AWARD_PROPOSAL" and message.entityType ~= "LEDGER_OPERATION_PROPOSAL" and message.entityType ~= "SEASON_CATALOG" and message.entityType ~= "REQUEST_MESSAGE" then return false, "UNSUPPORTED_ENTITY" end
    if message.entityType == "LEDGER_OPERATION_COMMIT" then
      local capabilities = message.protocol and message.protocol.capabilities
      if Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED ~= true then return false, "CANONICAL_DISPUTE_OPERATIONS_DISABLED" end
      if type(capabilities) ~= "table" or capabilities.ledgerOperationCommit ~= true
        or tonumber(message.protocol.operationProtocolVersion) ~= 1
        or tonumber(capabilities.ledgerOperationProtocol) ~= 1 then return false, "OPERATION_PEER_UNSUPPORTED" end
    end
    if message.entityType == "LEDGER_OPERATION_PROPOSAL" then
      local capabilities = message.protocol and message.protocol.capabilities
      if Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED ~= true then return false, "CANONICAL_DISPUTE_OPERATIONS_DISABLED" end
      if type(capabilities) ~= "table" or capabilities.ledgerOperationProposal ~= true
        or tonumber(message.protocol.operationProtocolVersion) ~= 1
        or tonumber(capabilities.ledgerOperationProtocol) ~= 1 then return false, "OPERATION_PEER_UNSUPPORTED" end
    end
    local transferLedgerId
    if message.entityType == "AWARD_COMMIT" or message.entityType == "LEDGER_OPERATION_COMMIT" or message.entityType == "PREDIB_REQUEST" then
      transferLedgerId = message.ledgerId
      if transferLedgerId == nil then transferLedgerId = "guild-primary" end
      if not isApprovedLedger(transferLedgerId) then return false, "LEDGER_NOT_APPROVED" end
    end
    local trustedRelay, relayChain = false, false
    if message.entityType == "GOVERNANCE" and resolved.role ~= "gm" then
      relayChain = relayChainAllows(message.entityType, message.revision, resolved)
      trustedRelay = relayChain or hasTrustedDigest(message.entityType, message.revision, message.contentHash)
      if not trustedRelay then return false, "APPROVED_DIGEST_REQUIRED" end
    end
    if message.entityType == "OPERATIONAL_POLICY" then
      local writerAllowed = false
      local writerReason = "POLICY_WRITER_REQUIRED"
      if Dibs.OperationalPolicy and Dibs.OperationalPolicy.CanWrite then
        local authorization = { Dibs.OperationalPolicy.CanWrite(resolved.displayName) }
        writerAllowed, writerReason = authorization[1], authorization[2]
      end
      if not writerAllowed then
        relayChain = relayChainAllows(message.entityType, message.revision, resolved)
        trustedRelay = relayChain or hasTrustedDigest(message.entityType, message.revision, message.contentHash)
        if not trustedRelay then return false, writerReason or "POLICY_WRITER_REQUIRED" end
      end
    end
    if message.entityType == "LEGACY_BASELINE" and resolved.role ~= "gm" then
      trustedRelay = hasTrustedDigest(message.entityType, message.revision, message.contentHash)
      if not trustedRelay then return false, "GUILD_MASTER_REQUIRED" end
    end
    if message.entityType == "SEASON_CATALOG" then
      local writerAllowed = false
      local writerReason = "POLICY_WRITER_REQUIRED"
      if Dibs.OperationalPolicy and Dibs.OperationalPolicy.CanWrite then
        writerAllowed, writerReason = Dibs.OperationalPolicy.CanWrite(resolved.displayName)
      end
      if not writerAllowed then
        relayChain = relayChainAllows(message.entityType, message.revision, resolved)
        trustedRelay = relayChain or hasTrustedDigest(message.entityType, message.revision, message.contentHash)
        if not trustedRelay then return false, writerReason or "POLICY_WRITER_REQUIRED" end
      end
    end
    local existing = Dibs.runtime.v2Transfers[message.transferId]
    if existing then
      if existing.sender == resolved.memberKey and existing.entityType == message.entityType and existing.entityId == message.entityId
        and tonumber(existing.revision) == tonumber(message.revision) and existing.contentHash == message.contentHash
        and existing.payloadHash == message.payloadHash and tonumber(existing.chunkCount) == tonumber(message.chunkCount)
        and existing.ledgerId == transferLedgerId then
        return true, "IDEMPOTENT_TRANSFER_BEGIN"
      end
      return false, "TRANSFER_ID_CONFLICT"
    end
    local count = 0; for _ in pairs(Dibs.runtime.v2Transfers) do count = count + 1 end; if count >= MAX_TRANSFERS then return false, "TRANSFER_CAPACITY" end
    Dibs.runtime.v2Transfers[message.transferId] = { transferId = message.transferId, sender = resolved.memberKey,
      entityType = message.entityType, entityId = message.entityId, revision = message.revision,
      contentHash = message.contentHash, payloadHash = message.payloadHash, chunkCount = message.chunkCount,
      ledgerId = transferLedgerId,
      chunks = {}, receivedChunks = 0, totalBytes = 0, expiresAt = time() + TTL,
      trustedRelay = trustedRelay, relayChain = relayChain,
      operationCapability = message.entityType == "LEDGER_OPERATION_COMMIT"
        and message.protocol.capabilities.ledgerOperationCommit == true or false,
      operationProtocol = message.entityType == "LEDGER_OPERATION_COMMIT"
        and tonumber(message.protocol.capabilities.ledgerOperationProtocol) or nil,
      operationProposalCapability = message.entityType == "LEDGER_OPERATION_PROPOSAL"
        and message.protocol.capabilities.ledgerOperationProposal == true or false,
      operationProposalProtocol = message.entityType == "LEDGER_OPERATION_PROPOSAL"
        and tonumber(message.protocol.capabilities.ledgerOperationProtocol) or nil }
    return true, "TRANSFER_STARTED"
  end
  if message.type == "TRANSFER_CHUNK" then
    local transfer = Dibs.runtime.v2Transfers[message.transferId]; local index = tonumber(message.chunkIndex)
    if not transfer or transfer.sender ~= resolved.memberKey or not finiteInteger(index) or index < 1 or index > transfer.chunkCount or type(message.chunk) ~= "string" or #message.chunk > MAX_BYTES then return false, "INVALID_TRANSFER_CHUNK" end
    if transfer.chunks[index] and transfer.chunks[index] ~= message.chunk then Dibs.runtime.v2Transfers[message.transferId] = nil; return false, "CONFLICTING_CHUNK" end
    if not transfer.chunks[index] then transfer.totalBytes = transfer.totalBytes + #message.chunk; transfer.receivedChunks = transfer.receivedChunks + 1 end
    if transfer.totalBytes > MAX_BYTES then Dibs.runtime.v2Transfers[message.transferId] = nil; return false, "PAYLOAD_TOO_LARGE" end
    transfer.chunks[index] = message.chunk; return true, "CHUNK_ACCEPTED"
  end
  if message.type == "TRANSFER_END" then
    local transfer = Dibs.runtime.v2Transfers[message.transferId]; Dibs.runtime.v2Transfers[message.transferId] = nil
    if not transfer or transfer.sender ~= resolved.memberKey then return false, "INVALID_TRANSFER_END" end
    local transferLedgerId = message.ledgerId
    if transfer.entityType == "AWARD_COMMIT" or transfer.entityType == "LEDGER_OPERATION_COMMIT" or transfer.entityType == "PREDIB_REQUEST" then
      if transferLedgerId == nil then transferLedgerId = "guild-primary" end
    end
    if transfer.ledgerId ~= transferLedgerId then
      return false, "LEDGER_SCOPE_MISMATCH"
    end
    local chunks = {}; for i = 1, transfer.chunkCount do if not transfer.chunks[i] then return false, "MISSING_TRANSFER_CHUNK" end; chunks[#chunks + 1] = transfer.chunks[i] end
    local raw = table.concat(chunks); if hash(raw) ~= transfer.payloadHash then return false, "PAYLOAD_HASH_MISMATCH" end
    local payload = Dibs.Ace3.Deserialize(raw); if type(payload) ~= "table" then return false, "DESERIALIZE_FAILED" end
    if transfer.entityType == "PREDIB_REQUEST" then
      local ok, applyReason = applyRequest(payload, transfer, resolved)
      if ok then
        -- A verified detail exchange proves the peer transport recovered from a
        -- forbidden ledger digest; real ledger gaps keep their own reasons.
        clearSyncBehindReasons("LEDGER_DETAIL_FORBIDDEN")
        if prunePredibPending() then clearSyncBehindReasons("MISSING_DETAIL") end
      end
      return ok, applyReason
    end
    if transfer.entityType == "VAULT_DETAIL" then return applyVaultDetail(payload, transfer, resolved) end
    if transfer.relayChain and RELAY_CHAINS[transfer.entityType] then
      return stageRelayRecord(transfer.entityType, payload, transfer)
    end
    if transfer.entityType == "LEGACY_BASELINE" and Dibs.HistoricalBaseline and Dibs.HistoricalBaseline.ApplyApprovedBaseline then
      if payload.legacyBaselineHash ~= transfer.contentHash or transfer.entityId ~= payload.legacyBaselineHash then return false, "CONTENT_HASH_MISMATCH" end
      return Dibs.HistoricalBaseline.ApplyApprovedBaseline(payload)
    end
    if transfer.entityType == "GOVERNANCE" and Dibs.Governance and Dibs.Governance.ApplyRecord then
      if payload.contentHash ~= transfer.contentHash
        or transfer.entityId ~= tostring(payload.governanceRevision) then return false, "CONTENT_HASH_MISMATCH" end
      local sender = transfer.trustedRelay and payload.authorNameRealm or resolved.displayName
      local ok, applyReason = Dibs.Governance.ApplyRecord(payload, sender)
      if ok then
        local governanceState = Dibs.Governance.GetState and Dibs.Governance.GetState() or {}
        local governanceTarget = ensure().governanceTarget
        if not governanceTarget or (tonumber(governanceState.revision) or 0) >= (tonumber(governanceTarget.revision) or 0) then
          ensure().governanceTarget = nil
          clearSyncBehindReasons("GOVERNANCE_PARENT_MISSING")
        end
        if Dibs.Governance.IsV2Enforced and Dibs.Governance.IsV2Enforced() then
          clearSyncBehindReasons("LEDGER_ENFORCEMENT_MISSING")
        end
      end
      return ok, applyReason
    end
    if transfer.entityType == "OPERATIONAL_POLICY" and Dibs.OperationalPolicy and Dibs.OperationalPolicy.ApplyRecord then
      if payload.contentHash ~= transfer.contentHash
        or transfer.entityId ~= tostring(payload.policyRevision) then return false, "CONTENT_HASH_MISMATCH" end
      local sender = transfer.trustedRelay and payload.authorNameRealm or resolved.displayName
      local ok, applyReason = Dibs.OperationalPolicy.ApplyRecord(payload, sender)
      if not ok and applyReason == "POLICY_PARENT_MISSING" then
        local state = ensure()
        if not state.policyTarget or tonumber(transfer.revision) > tonumber(state.policyTarget.revision) then
          state.policyTarget = { revision = transfer.revision, contentHash = transfer.contentHash, source = resolved.displayName }
        end
        Sync.MarkSyncBehind(applyReason)
        local current = Dibs.OperationalPolicy.GetState()
        if tonumber(transfer.revision) == (tonumber(current.policyRevision) or 0) + 1 then
          Sync.MarkSyncBehind("POLICY_CONFLICT")
        else
          requestNextRevision("OPERATIONAL_POLICY", state.policyTarget, current.policyRevision)
        end
      elseif ok then clearResolvedPolicyGap(true)
      elseif applyReason == "POLICY_CONFLICT" then Sync.MarkSyncBehind(applyReason) end
      return ok, applyReason
    end
    if transfer.entityType == "SEASON_CATALOG" and Dibs.Seasons and Dibs.Seasons.ApplyCatalog then
      if payload.contentHash ~= transfer.contentHash or transfer.entityId ~= tostring(payload.catalogRevision) then return false, "CONTENT_HASH_MISMATCH" end
      local sender = transfer.trustedRelay and payload.authorNameRealm or resolved.displayName
      local ok, applyReason = Dibs.Seasons.ApplyCatalog(payload, sender)
      if not ok and applyReason == "SEASON_CATALOG_PARENT_MISSING" then
        local state = ensure()
        if not state.seasonCatalogTarget or tonumber(transfer.revision) > tonumber(state.seasonCatalogTarget.revision) then
          state.seasonCatalogTarget = { revision = transfer.revision, contentHash = transfer.contentHash, source = resolved.displayName }
        end
        Sync.MarkSyncBehind(applyReason)
        local current = Dibs.Seasons.GetCatalogState()
        if tonumber(transfer.revision) == (tonumber(current.catalogRevision) or 0) + 1 then
          Sync.MarkSyncBehind("SEASON_CATALOG_CONFLICT")
        else
          requestNextRevision("SEASON_CATALOG", state.seasonCatalogTarget, current.catalogRevision)
        end
      elseif ok then clearResolvedSeasonCatalogGap(true)
      elseif applyReason == "SEASON_CATALOG_CONFLICT" then Sync.MarkSyncBehind(applyReason) end
      return ok, applyReason
    end
    if transfer.entityType == "LEGACY_RECOVERY_PACKAGE" and Dibs.HistoricalBaseline and Dibs.HistoricalBaseline.StageRecoveryPackage then
      if payload.contentHash ~= transfer.contentHash or transfer.entityId ~= payload.contentHash then return false, "CONTENT_HASH_MISMATCH" end
      local staged, stageReason = Dibs.HistoricalBaseline.StageRecoveryPackage(payload, { sender = resolved.displayName })
      if not staged then return false, stageReason end
      Dibs.runtime = Dibs.runtime or {}; Dibs.runtime.legacyRecoveryPackages = Dibs.runtime.legacyRecoveryPackages or {}
      local pending = Dibs.runtime.legacyRecoveryPackages
      local pendingCount = 0; for _ in pairs(pending) do pendingCount = pendingCount + 1 end
      if not pending[payload.contentHash] and pendingCount >= MAX_TRANSFERS then return false, "RECOVERY_STAGE_CAPACITY" end
      pending[payload.contentHash] = { staged = staged, senderNameRealm = resolved.displayName, receivedAt = time() }
      return true, "RECOVERY_PENDING_REVIEW"
    end
    if transfer.entityType == "AUTHORITY_SIGNAL" and Dibs.Governance and Dibs.Governance.ApplyAuthoritySignal then
      if payload.contentHash ~= transfer.contentHash then return false, "CONTENT_HASH_MISMATCH" end
      local ok, applyReason = Dibs.Governance.ApplyAuthoritySignal(payload, resolved.displayName)
      if ok then
        ensure().authorityTarget = nil
        clearSyncBehindReasons("AUTHORITY_DETAIL_MISSING")
      end
      return ok, applyReason
    end
    if transfer.entityType == "AUTHORITY_ORPHAN" and Dibs.Governance and Dibs.Governance.ApplyOrphanedEvidence then
      if Sync.CalculateContentHash(payload) ~= transfer.contentHash or transfer.entityId ~= (payload.evidenceId or payload.eventId or payload.transactionId) then return false, "CONTENT_HASH_MISMATCH" end
      return Dibs.Governance.ApplyOrphanedEvidence(payload, resolved.displayName)
    end
    if transfer.entityType == "AWARD_COMMIT" and Dibs.Ledger and Dibs.Ledger.ApplyAwardCommit then
      local ledgerId = payload.ledgerId or "guild-primary"
      if ledgerId ~= transfer.ledgerId or payload.commitHash ~= transfer.contentHash
        or transfer.entityId ~= tostring(payload.ledgerEpoch) .. ":" .. tostring(payload.sequence) then return false, "CONTENT_HASH_MISMATCH" end
      local applied = Dibs.Ledger.ApplyAwardCommit(payload, resolved.displayName, ledgerId)
      if applied.accepted and not applied.idempotentReplay then clearResolvedLedgerGap(resolved.displayName, ledgerId) end
      return applied.accepted, applied.reasonCode
    end
    if transfer.entityType == "LEDGER_OPERATION_COMMIT" and Dibs.Ledger and Dibs.Ledger.ApplyDisputeOperationCommit then
      if Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED ~= true
        or transfer.operationCapability ~= true or transfer.operationProtocol ~= 1 then
        return false, "OPERATION_PEER_UNSUPPORTED"
      end
      if type(payload) ~= "table" or payload.commitHash ~= transfer.contentHash
        or transfer.entityId ~= tostring(payload.ledgerEpoch) .. ":" .. tostring(payload.sequence) then
        return false, "CONTENT_HASH_MISMATCH"
      end
      local applied = Dibs.Ledger.ApplyDisputeOperationCommit(payload, resolved.displayName, transfer.ledgerId)
      if applied.accepted and not applied.idempotentReplay then clearResolvedLedgerGap(resolved.displayName, transfer.ledgerId) end
      return applied.accepted, applied.reasonCode
    end
    if transfer.entityType == "AWARD_PROPOSAL" and Dibs.Governance and Dibs.Governance.ReceiveRelayedProposal then
      if transfer.entityId ~= payload.proposalId then return false, "ENTITY_IDENTITY_MISMATCH" end
      if Sync.CalculateContentHash(payload) ~= transfer.contentHash then return false, "CONTENT_HASH_MISMATCH" end
      local accepted, applyReason = Dibs.Governance.ReceiveRelayedProposal(payload, resolved.displayName)
      if accepted then
        Sync.AnnounceAwardReservationDigest()
        Sync.Send({ type = "AWARD_PROPOSAL_ACK", proposalId = payload.proposalId, result = "RECEIVED" }, "WHISPER", resolved.displayName)
        -- Season-allocation grants are deterministic rank rules, not a loot judgment call; commit immediately.
        if payload.type == "SEASON_ALLOCATION" and Dibs.Ledger and Dibs.Ledger.CommitAwardProposal then
          local committed = Dibs.Ledger.CommitAwardProposal(nil, payload.proposalId, {})
          if payload.reconciliation and committed and not committed.accepted then
            local terminalProposal = Dibs.Governance.GetAwardProposals and (function()
              for _, candidate in ipairs(Dibs.Governance.GetAwardProposals()) do
                if candidate.proposalId == payload.proposalId then return candidate end
              end
            end)()
            if terminalProposal and (terminalProposal.status == "STALE" or terminalProposal.status == "REJECTED") then
              Sync.SendAwardProposalResult(payload.proposalId, terminalProposal.status, terminalProposal.resolutionReason, resolved.displayName)
            end
          end
        end
      elseif payload.reconciliation then
        Sync.SendAwardProposalResult(payload.proposalId, "REJECTED", applyReason, resolved.displayName)
      end
      return accepted, applyReason
    end
    if transfer.entityType == "LEDGER_OPERATION_PROPOSAL" and Dibs.Governance and Dibs.Governance.ReceiveDisputeProposal then
      if Dibs.CANONICAL_OPERATIONS_RELEASE_ENABLED ~= true
        or transfer.operationProposalCapability ~= true or transfer.operationProposalProtocol ~= 1 then
        return false, "OPERATION_PEER_UNSUPPORTED"
      end
      if type(payload) ~= "table" or payload.recordClass ~= "LEDGER_OPERATION_PROPOSAL"
        or transfer.entityId ~= payload.proposalId or payload.status ~= "PENDING"
        or Sync.CalculateContentHash(payload) ~= transfer.contentHash then
        return false, "CONTENT_HASH_MISMATCH"
      end
      local accepted, applyReason = Dibs.Governance.ReceiveDisputeProposal(payload, resolved.displayName)
      if accepted then
        Sync.Send({ type = "LEDGER_OPERATION_PROPOSAL_ACK", proposalId = payload.proposalId,
          result = "RECEIVED" }, "WHISPER", resolved.displayName)
      end
      return accepted, applyReason
    end
    if transfer.entityType == "REQUEST_MESSAGE" and Dibs.RequestDelivery then
      if type(payload) ~= "table" or transfer.entityId ~= payload.operationId
        or Sync.CalculateContentHash(payload) ~= transfer.contentHash then return false, "CONTENT_HASH_MISMATCH" end
      if not (message.protocol.capabilities or {}).requestDelivery then return false, "REQUEST_PEER_UNSUPPORTED" end
      return Dibs.RequestDelivery.Receive(payload, resolved.displayName)
    end
    return false, "UNSUPPORTED_ENTITY"
  end
  return false, "UNSUPPORTED_MESSAGE"
end

function Sync.OnAddonMessage(prefix, payload, channel, sender)
  if prefix ~= "DIBS" or type(payload) ~= "string" then return false, "INVALID_PREFIX" end
  if not transportReady() then status("SYNC_UNAVAILABLE"); return false, "SYNC_UNAVAILABLE" end
  local message = Dibs.Ace3.Deserialize(payload); if type(message) ~= "table" then return false, "PROTOCOL_LEGACY_READ_ONLY" end
  Sync.TraceIncoming(prefix, channel, sender, message.type, #payload)
  local transfer = message.transferId and Dibs.runtime and Dibs.runtime.v2Transfers and Dibs.runtime.v2Transfers[message.transferId]
  if message.type == "TRANSFER_BEGIN" and message.entityType == "LEGACY_BASELINE" then
    transfer = { transferId = message.transferId, entityType = message.entityType, entityId = message.entityId }
  end
  local expectedChannel = expectedTransportChannel(message, transfer)
  local legacyWhisper = channel == "WHISPER" and expectedChannel == "GUILD" and allowsLegacyWhisper(message, transfer)
  if channel ~= expectedChannel and not legacyWhisper then
    if message.type == "CHANNEL_TEST" or message.type == "CHANNEL_TEST_ACK" then
      recordChannelTest({ direction = "RECEIVE", channel = channel, peer = sender, status = "REJECTED",
        reasonCode = "INVALID_TRANSPORT_CHANNEL_EXPECTED_" .. tostring(expectedChannel), startedAt = time() })
    end
    return false, "INVALID_TRANSPORT_CHANNEL"
  end
  local accepted, reason = Sync.Receive(message, sender, channel)
  if message.type == "TRANSFER_END" and not transfer and message.entityType == "LEGACY_BASELINE" then
    transfer = { transferId = message.transferId, entityType = message.entityType, entityId = message.entityId }
  end
  if transfer and transfer.entityType == "LEGACY_BASELINE"
    and (message.type == "TRANSFER_END" or (message.type == "TRANSFER_BEGIN" and not accepted)) then
    sendTransferAck(sender, transfer, accepted, reason, channel)
  end
  return accepted, reason
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
  if Dibs.RequestDelivery then Dibs.RequestDelivery.CheckReminders() end
  scheduleHeartbeat()
  if not Sync.RegisterTransport() then return false, "SYNC_UNAVAILABLE" end
  if Dibs.RequestDelivery then Dibs.RequestDelivery.Pump() end
  local now = time()
  if reason == "STARTUP" and Sync.startupLifecycleScheduled then
    return true, "STARTUP_COALESCED"
  end
  if reason == "GUILD_ROSTER_SETTLED" and Sync.lastLifecycleAt
    and now - Sync.lastLifecycleAt < 5 then
    return true, "ROSTER_LIFECYCLE_COALESCED"
  end
  if reason == "STARTUP" then Sync.startupLifecycleScheduled = true end
  Sync.lastLifecycleAt = now
  Sync.Send({ type = "HELLO", protocolState = Sync.GetProtocolState(), lifecycle = reason }, "GUILD")
  local sent, sendReason = Sync.AnnounceAllRequestIndexes()
  Sync.Send(Sync.BuildVaultDigest(), "GUILD")
  retryVaultRequests()
  local sendGovernedDigests = function()
    Sync.AnnounceGovernance()
    Sync.BroadcastCatalogDigest()
    Sync.BroadcastPendingLedgerDeletions()
    if Dibs.OperationalPolicy and Dibs.OperationalPolicy.IsAdopted and Dibs.OperationalPolicy.IsAdopted() then
      Sync.Send(Sync.BuildOperationalPolicyDigest(), "GUILD")
    end
    local catalogState = Dibs.Seasons and Dibs.Seasons.GetCatalogState and Dibs.Seasons.GetCatalogState() or {}
    if tonumber(catalogState.catalogRevision) and tonumber(catalogState.catalogRevision) > 0
      and Dibs.Seasons and Dibs.Seasons.GetCatalogRecord and Dibs.Seasons.CalculateCatalogHash
      and Dibs.Seasons.PublishCatalog then
      local currentRecord = Dibs.Seasons.GetCatalogRecord(catalogState.catalogRevision)
      if currentRecord then
        local currentConfiguration = Dibs.Seasons.GetGuildConfiguration and Dibs.Seasons.GetGuildConfiguration() or {}
        local currentHash = Sync.CalculateContentHash(currentConfiguration)
        local publishedHash = Sync.CalculateContentHash(currentRecord.guildConfiguration or {})
        if currentHash ~= publishedHash then Dibs.Seasons.PublishCatalog(Dibs.GetPlayerName and Dibs.GetPlayerName() or nil, "GUILD_CONFIGURATION_CHANGE") end
      end
    end
    if tonumber(catalogState.catalogRevision) and tonumber(catalogState.catalogRevision) > 0 then
      Sync.Send(Sync.BuildSeasonCatalogDigest(), "GUILD")
    end
    local authority = Sync.BuildAuthorityDigest()
    if authority then Sync.Send(authority, "GUILD") end
    local localMember = localSnapshot()
    local authorityState = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
    if Dibs.Governance and Dibs.Governance.IsV2Enforced and Dibs.Governance.IsV2Enforced()
      and authorityState and authorityState.state == "ACTIVE" and localMember then
      Sync.AnnounceLedgerDigest()
    end
  end
  local sendDeferredDetails = function()
    Sync.AnnounceAwardReservationDigest()
    Sync.RetryPendingAwardProposals()
    Sync.RetryPendingDisputeProposals()
  end
  if reason == "STARTUP" and Dibs.Ace3 and Dibs.Ace3.ScheduleTimer then
    Dibs.Ace3.ScheduleTimer(sendGovernedDigests, 1)
    Dibs.Ace3.ScheduleTimer(sendDeferredDetails, 2)
  else
    sendGovernedDigests()
    sendDeferredDetails()
  end
  return sent, sendReason
end
local function ledgerTargetResolved(target)
  if type(target) ~= "table" or not (Dibs.Ledger and Dibs.Ledger.GetCanonicalState) then return false end
  local current = Dibs.Ledger.GetCanonicalState(target.ledgerId)
  if type(current) ~= "table" or tonumber(current.epoch) ~= tonumber(target.epoch) then return false end
  local localLast = (tonumber(current.nextSeq) or 1) - 1
  local targetLast = tonumber(target.lastSeq) or 0
  return localLast > targetLast or (localLast == targetLast and current.rootHash == target.rootHash)
end
local function governanceTargetResolved(target)
  if type(target) ~= "table" then return true end
  local current = Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState() or {}
  return (tonumber(current.revision) or 0) >= (tonumber(target.revision) or 0)
end
local function authorityTargetResolved(target)
  if type(target) ~= "table" then return true end
  local signal = Dibs.Governance and Dibs.Governance.BuildAuthoritySignal and Dibs.Governance.BuildAuthoritySignal()
  return type(signal) == "table" and signal.contentHash == target.contentHash
end
-- Re-evaluates every recorded behind reason against local data and clears the
-- ones whose missing data has arrived. Never changes ledger or accounting data.
function Sync.RecheckSyncBehind()
  local state = ensure()
  local before = {}
  for _, row in ipairs(Sync.GetSyncBehindReasons()) do before[#before + 1] = row.code end
  if state.syncBehind ~= true then return { cleared = {}, remaining = {} } end
  clearResolvedPolicyGap()
  clearResolvedSeasonCatalogGap()
  local ledgerPending = false
  for ledgerId, entry in pairs(state.ledgerSync or {}) do
    if type(entry) == "table" and entry.target then
      if ledgerTargetResolved(entry.target) then
        entry.target, entry.requestedThrough, entry.requestAt = nil, nil, nil
        if ledgerId == "guild-primary" then state.ledgerTarget, state.ledgerRequestedThrough, state.ledgerRequestAt = nil, nil, nil end
      else
        ledgerPending = true
      end
    end
  end
  local vaultPending = next(state.vaultPending or {}) ~= nil
  local predibResolved = prunePredibPending()
  if governanceTargetResolved(state.governanceTarget) then state.governanceTarget = nil end
  if authorityTargetResolved(state.authorityTarget) then state.authorityTarget = nil end
  local toClear = {}
  if not ledgerPending then toClear[#toClear + 1] = "LEDGER_GAP" end
  if not state.policyTarget then toClear[#toClear + 1] = "POLICY_PARENT_MISSING"; toClear[#toClear + 1] = "POLICY_CHAIN_MISSING" end
  if not state.seasonCatalogTarget then toClear[#toClear + 1] = "SEASON_CATALOG_PARENT_MISSING" end
  if not vaultPending then toClear[#toClear + 1] = "VAULT_DETAIL_MISSING" end
  if predibResolved then toClear[#toClear + 1] = "MISSING_DETAIL" end
  if Dibs.Governance and Dibs.Governance.IsV2Enforced and Dibs.Governance.IsV2Enforced() then toClear[#toClear + 1] = "LEDGER_ENFORCEMENT_MISSING" end
  if not state.governanceTarget then toClear[#toClear + 1] = "GOVERNANCE_PARENT_MISSING" end
  if not state.authorityTarget then toClear[#toClear + 1] = "AUTHORITY_DETAIL_MISSING" end
  clearSyncBehindReasons((table.unpack or unpack)(toClear))
  local remaining, remainingSet = {}, {}
  for _, row in ipairs(Sync.GetSyncBehindReasons()) do remaining[#remaining + 1] = row.code; remainingSet[row.code] = true end
  local cleared = {}
  for _, code in ipairs(before) do if not remainingSet[code] then cleared[#cleared + 1] = code end end
  return { cleared = cleared, remaining = remaining }
end
-- Re-requests every tracked missing detail from the peer that announced it,
-- then runs a normal sync lifecycle so peers answer with fresh digests.
---@doc.id sync.repair
---@doc.category synchronization
---@doc.since 0.8.10
---@doc.audience player,officer,gm
---@doc.scope character-local
---@doc.audit false
---@doc.help-key UI_HELP_SYNC_FIX
---@doc.label-key SYNC_FIX_LABEL
---@doc.reference-key DOC_SYNC_FIX_REFERENCE
function Sync.RequestResync()
  local state, sent = ensure(), 0
  for _, entry in pairs(state.ledgerSync or {}) do
    local target = type(entry) == "table" and entry.target
    if target and target.source and Dibs.Ledger and Dibs.Ledger.GetCanonicalState then
      entry.requestAt = nil; entry.requestedThrough = nil
      local current = Dibs.Ledger.GetCanonicalState(target.ledgerId)
      if requestLedgerBatch(target.source, state, target, (tonumber(current and current.nextSeq) or 1) - 1) then sent = sent + 1 end
    end
  end
  local policy = state.policyTarget
  local policyState = Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetState and Dibs.OperationalPolicy.GetState() or {}
  if requestNextRevision("OPERATIONAL_POLICY", policy, policyState.policyRevision) then sent = sent + 1 end
  local catalog = state.seasonCatalogTarget
  local catalogState = Dibs.Seasons and Dibs.Seasons.GetCatalogState and Dibs.Seasons.GetCatalogState() or {}
  if requestNextRevision("SEASON_CATALOG", catalog, catalogState.catalogRevision) then sent = sent + 1 end
  local governance = state.governanceTarget
  if governance and governance.source and sendDetailFetch({ { entityType = "GOVERNANCE", entityId = tostring(governance.revision),
    revision = governance.revision, contentHash = governance.contentHash, parentHash = governance.parentHash } }, governance.source) then sent = sent + 1 end
  local authority = state.authorityTarget
  if authority and authority.source and sendDetailFetch({ { entityType = "AUTHORITY_SIGNAL", entityId = authority.entityId,
    revision = 1, contentHash = authority.contentHash } }, authority.source) then sent = sent + 1 end
  prunePredibPending()
  local grouped = {}
  for _, entry in pairs(state.predibPending or {}) do
    if type(entry) == "table" and type(entry.target) == "string" then
      grouped[entry.target] = grouped[entry.target] or {}
      grouped[entry.target][#grouped[entry.target] + 1] = { entityType = "PREDIB_REQUEST", entityId = entry.requestId,
        ledgerId = entry.ledgerId, revision = entry.revision, contentHash = entry.contentHash }
    end
  end
  for target, requests in pairs(grouped) do if sendPredibFetches(requests, target) then sent = sent + 1 end end
  for _, request in pairs(state.vaultPending or {}) do if type(request) == "table" then request.attempts = 0 end end
  retryVaultRequests()
  local started, reason = Sync.OnLifecycle("SYNC_REPAIR")
  return sent, started, reason
end
-- GM/Officer escape hatch for a stuck local "behind" flag. Only local tracking
-- state is reset; ledger and accounting data are untouched, and the next peer
-- digest marks this client behind again if data is still missing.
function Sync.ForceClearSyncBehind(actor, reason)
  local role = localRole()
  if role ~= "gm" and role ~= "officer" then return false, "OFFICER_REQUIRED" end
  local state = ensure()
  local reasons = {}
  for _, row in ipairs(Sync.GetSyncBehindReasons()) do reasons[#reasons + 1] = row.code end
  for _, entry in pairs(state.ledgerSync or {}) do
    if type(entry) == "table" then entry.target, entry.requestedThrough, entry.requestAt = nil, nil, nil end
  end
  state.ledgerTarget, state.ledgerRequestedThrough, state.ledgerRequestAt = nil, nil, nil
  state.policyTarget, state.seasonCatalogTarget, state.governanceTarget, state.authorityTarget = nil, nil, nil, nil
  state.predibPending = {}
  Sync.ClearSyncBehind()
  local actorName = actor or (Dibs.GetPlayerName and Dibs.GetPlayerName()) or "unknown"
  state.lastForcedClear = { actor = actorName, at = time(), reasons = reasons, reason = reason }
  if Dibs.DebugLogs and Dibs.DebugLogs.Add then
    Dibs.DebugLogs.Add("sync", 1, "Sync behind state force-cleared by " .. tostring(actorName) .. " (" .. table.concat(reasons, ", ") .. ")"
      .. (reason and (": " .. tostring(reason)) or ""))
  end
  return true, reasons
end
function Sync.AnnounceOperationalPolicy()
  if not (Dibs.OperationalPolicy and Dibs.OperationalPolicy.IsAdopted and Dibs.OperationalPolicy.IsAdopted()) then return false, "POLICY_UNINITIALIZED" end
  return Sync.Send(Sync.BuildOperationalPolicyDigest(), "GUILD")
end
function Sync.AnnounceGovernance()
  return Sync.Send(Sync.BuildGovernanceDigest(), "GUILD")
end
function Sync.AnnounceSeasonCatalog()
  local state = Dibs.Seasons and Dibs.Seasons.GetCatalogState and Dibs.Seasons.GetCatalogState() or {}
  if not tonumber(state.catalogRevision) or tonumber(state.catalogRevision) < 1 then return false, "SEASON_CATALOG_UNINITIALIZED" end
  return Sync.Send(Sync.BuildSeasonCatalogDigest(), "GUILD")
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
