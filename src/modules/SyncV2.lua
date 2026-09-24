--[[
Module: Dibs.Sync V2 transport foundation (B04)
Purpose: bounded GUILD digests and WHISPER detail transfer without enabling a
distributed ledger. Hashes and sender checks are integrity/attribution signals,
not cryptographic authentication.
]]

---@diagnostic disable: return-type-mismatch, redundant-return-value, assign-type-mismatch

local Dibs = _G.Dibs
local Sync = Dibs.Sync

local MAJOR, MINOR = 2, 0
local MAX_MESSAGES, MAX_TRANSFERS, MAX_CHUNKS, MAX_BYTES, MAX_INDEX, MAX_PROTOCOL_MISMATCHES = 256, 8, 16, 8192, 500, 10
local TTL, HEARTBEAT, MAX_VAULT_RETRIES = 300, 60, 3
local TYPES = { HELLO = true, DIGEST = true, DETAIL_FETCH = true, TRANSFER_BEGIN = true, TRANSFER_CHUNK = true, TRANSFER_END = true, TRANSFER_ACK = true, LEDGER_DIGEST = true, VAULT_DIGEST = true, VAULT_FETCH = true, VAULT_DETAIL = true, VAULT_ACK = true, AWARD_PROPOSAL_ACK = true, SYNC_PROBE = true, SYNC_PROBE_RESPONSE = true }
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
  state.v2.transferAcks = state.v2.transferAcks or {}
  state.v2.vaultPending = state.v2.vaultPending or {}; state.v2.protocolMismatches = state.v2.protocolMismatches or {}
  state.v2.addonVersionMismatches = state.v2.addonVersionMismatches or {}
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
local function localSyncDigests()
  local digests = {}
  local catalog = Dibs.Seasons and Dibs.Seasons.GetCatalogState and Dibs.Seasons.GetCatalogState() or {}
  digests.SEASON_CATALOG = { revision = tonumber(catalog.catalogRevision) or 0, contentHash = catalog.hash }
  local policy = Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetState and Dibs.OperationalPolicy.GetState() or {}
  digests.OPERATIONAL_POLICY = { revision = tonumber(policy.policyRevision) or 0, contentHash = policy.hash }
  local manifest = Sync.BuildManifest and Sync.BuildManifest() or {}
  digests.PREDIB_INDEX = { revision = tonumber(manifest.revision) or 0, contentHash = manifest.contentHash }
  local vault = Sync.BuildVaultDigest and Sync.BuildVaultDigest() or {}
  digests.VAULT_INDEX = { revision = tonumber(vault.revision) or 0, contentHash = vault.contentHash }
  local ledger = Sync.BuildLedgerDigest and Sync.BuildLedgerDigest() or {}
  digests.LEDGER = { revision = tonumber(ledger.revision) or 0, contentHash = ledger.contentHash }
  return digests
end
local function requestProjection(request)
  return { requestId = request.requestId, revision = tonumber(request.revision) or 1, status = request.status, playerName = request.playerName, itemID = tonumber(request.itemID), seasonId = request.seasonId, updatedAt = request.updatedAt, createdAt = request.createdAt }
end
local function requestHash(request) return hash(requestProjection(request)) end

function Sync.CalculateContentHash(value) return hash(value) end
function Sync.CalculateRequestHash(request) return requestHash(request) end
function Sync.GetAddonVersionCompatibility(remoteVersion)
  local localVersion, remote = parseAddonVersion(Dibs.VERSION), parseAddonVersion(remoteVersion)
  if not localVersion then return false, "LOCAL_ADDON_VERSION_INVALID" end
  if not remote then return nil, "REMOTE_ADDON_VERSION_UNKNOWN" end
  if localVersion.major == remote.major and localVersion.minor == remote.minor then return true, "ADDON_VERSION_COMPATIBLE" end
  return false, "ADDON_UPDATE_REQUIRED"
end

function Sync.BuildSyncProbeReport()
  local state = ensure()
  local governance = Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState() or {}
  local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState() or {}
  local baseline = Dibs.LegacyBaseline and Dibs.LegacyBaseline.GetBaseline and Dibs.LegacyBaseline.GetBaseline() or {}
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
function Sync.RepairPeer(target)
  if not target or target == "" then return false, "INVALID_WHISPER_TARGET" end
  if localRole() ~= "gm" then return false, "GUILD_MASTER_REQUIRED" end
  local baseline = Dibs.LegacyBaseline and Dibs.LegacyBaseline.GetBaseline and Dibs.LegacyBaseline.GetBaseline()
  if not baseline or not baseline.legacyBaselineHash then return false, "BASELINE_UNAVAILABLE" end
  return Sync.SendDetail("LEGACY_BASELINE", baseline.legacyBaselineHash, 1, baseline.legacyBaselineHash, baseline, target)
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
  return string.format(
    "%s role=%s protocol=%s behind=%s reason=%s governance=%s/%s baseline=%s authority=%s coordinator=%s policy=%s catalog=%s ledger=%s/%s epoch=%s",
    tostring(report.displayName or "unknown"), tostring(report.role or "unknown"), tostring(report.protocolState or "unknown"),
    tostring(report.syncBehind == true), tostring(report.syncReason or "none"), tostring(governance.revision or 0),
    tostring(governance.hash or "none"), tostring(report.baselineHash or "none"), tostring(authority.state or "unknown"),
    tostring(authority.coordinatorName or authority.coordinatorMemberKey or "none"), tostring(report.operationalPolicyRevision or 0),
    tostring(report.seasonCatalogRevision or 0), tostring(ledger.revision or 0), tostring(ledger.rootHash or "none"), tostring(ledger.epoch or "none")) .. suffix
end

function Sync.GetStatus()
  local state = ensure()
  if not transportReady() or Sync.transportRegistered ~= true then return { state = "SYNC_UNAVAILABLE", protocolState = state.protocolState } end
  return { state = state.status or "SYNC_READY", protocolState = state.protocolState, syncBehind = state.syncBehind == true, reason = state.reason }
end
function Sync.GetSynchronizationStatus()
  local governance = Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState() or {}
  local catalog = Dibs.Seasons and Dibs.Seasons.GetCatalogState and Dibs.Seasons.GetCatalogState() or {}
  local proposals = Dibs.Governance and Dibs.Governance.GetAwardProposals and Dibs.Governance.GetAwardProposals() or {}
  local pending = 0
  for _, proposal in ipairs(proposals) do if proposal.status ~= "COMMITTED" then pending = pending + 1 end end
  local mismatches = ensure().protocolMismatches
  return {
    governanceAdopted = governance.status == "GOVERNANCE_ADOPTED",
    operationalPolicyAdopted = Dibs.OperationalPolicy and Dibs.OperationalPolicy.IsAdopted and Dibs.OperationalPolicy.IsAdopted() == true,
    seasonCatalogRevision = tonumber(catalog.catalogRevision) or 0,
    pendingAwardProposals = pending,
    lastProtocolMismatch = copy(mismatches[#mismatches]),
    lastAddonVersionMismatch = copy(ensure().addonVersionMismatches[#ensure().addonVersionMismatches]),
  }
end
function Sync.GetPeerStatuses()
  local state, rows, now = ensure(), {}, time()
  local roster = {}
  local groupCount = type(GetNumGroupMembers) == "function" and tonumber(GetNumGroupMembers()) or 0
  if groupCount > 0 and type(UnitFullName) == "function" then
    for index = 1, groupCount do
      local unit = IsInRaid and IsInRaid() and ("raid" .. index) or (index == 1 and "player" or "party" .. (index - 1))
      local name, realm = UnitFullName(unit)
      if not name and type(UnitName) == "function" then name, realm = UnitName(unit) end
      if name then
        local connected = type(UnitIsConnected) ~= "function" or UnitIsConnected(unit) == true
        roster[#roster + 1] = { name = realm and realm ~= "" and (name .. "-" .. realm) or name, online = connected, rankIndex = 0 }
      end
    end
  elseif type(GetNumGuildMembers) == "function" and type(GetGuildRosterInfo) == "function" then
    local okCount, memberCount = pcall(GetNumGuildMembers, true)
    if not okCount then return rows end
    for index = 1, tonumber(memberCount) or 0 do
      local ok, name, _, rankIndex, _, _, _, online = pcall(GetGuildRosterInfo, index)
      if ok and type(name) == "string" and name ~= "" then
        roster[#roster + 1] = { name = name, online = online == true or online == 1 or online == "1", rankIndex = rankIndex }
      end
    end
  end
  for _, rosterEntry in ipairs(roster) do
    local name, online, rankIndex = rosterEntry.name, rosterEntry.online, rosterEntry.rankIndex
    if type(name) == "string" and name ~= "" then
      local resolved = member(name)
      local memberKey = resolved and resolved.memberKey or string.lower(name)
      local peer = state.peers[memberKey]
      local lastSeen = peer and tonumber(peer.lastSeenAt or peer.at) or 0
      local detected = lastSeen > 0 and now - lastSeen <= (HEARTBEAT * 3)
      local compatibility, compatibilityReason = nil, "REMOTE_ADDON_VERSION_UNKNOWN"
      if peer and peer.addonVersion then compatibility, compatibilityReason = Sync.GetAddonVersionCompatibility(peer.addonVersion) end
      local syncStatus = "Unknown"
      local compared, behind, localBehind = 0, false, false
      local localDigests = localSyncDigests()
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
      local remotePredib = peer and peer.entities and peer.entities.PREDIB_INDEX or {}
      local remoteVault = peer and peer.entities and peer.entities.VAULT_INDEX or {}
      local remoteLedger = peer and peer.entities and peer.entities.LEDGER or {}
      local localMember = localSnapshot() or {}
      local isLocalMember = memberKey == localMember.memberKey
        or string.lower(tostring(resolved and resolved.displayName or name)) == string.lower(tostring(localMember.displayName or ""))
      local localBaseline = Dibs.LegacyBaseline and Dibs.LegacyBaseline.GetBaseline and Dibs.LegacyBaseline.GetBaseline() or {}
      local baselineStatus = "Unknown"
      if isLocalMember then
        baselineStatus = localBaseline.legacyBaselineHash and "Present" or "Missing"
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
        rankIndex = tonumber(rankIndex) or 0,
        online = online == true,
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
  table.sort(rows, function(a, b)
    if a.online ~= b.online then return a.online end
    return string.lower(a.playerName) < string.lower(b.playerName)
  end)
  return rows
end
function Sync.IsSyncBehind() return ensure().syncBehind == true end
function Sync.MarkSyncBehind(reason)
  local state = ensure(); state.syncBehind, state.reason = true, reason or "SYNC_BEHIND"; return status("SYNC_BEHIND", { reasonCode = state.reason })
end
function Sync.ClearSyncBehind()
  local state = ensure(); state.syncBehind, state.reason = false, nil; return status("SYNC_READY")
end
local function requestAwardCommitBatch(target, epoch, firstSequence, lastSequence)
  local requests = {}
  local finalSequence = math.min(tonumber(lastSequence) or firstSequence, firstSequence + 31)
  for sequence = firstSequence, finalSequence do
    requests[#requests + 1] = { entityType = "AWARD_COMMIT", entityId = tostring(epoch) .. ":" .. tostring(sequence), revision = sequence }
  end
  if #requests == 0 then return false, firstSequence - 1 end
  local sent, reason = Sync.Send({ type = "DETAIL_FETCH", requests = requests }, "WHISPER", target)
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
local function clearResolvedLedgerGap(sender)
  local state, target = ensure(), ensure().ledgerTarget
  if not target or not (Dibs.Ledger and Dibs.Ledger.GetCanonicalState) then return false end
  local current = Dibs.Ledger.GetCanonicalState()
  if tonumber(current.epoch) ~= tonumber(target.epoch) then return false end
  local localLast = tonumber(current.nextSeq or 1) - 1
  if localLast < tonumber(target.lastSeq) then
    local requestedThrough = tonumber(state.ledgerRequestedThrough) or 0
    if localLast >= requestedThrough then
      local sent, through = requestAwardCommitBatch(sender, target.epoch, localLast + 1, target.lastSeq)
      if sent then state.ledgerRequestedThrough = through end
    end
    return false
  end
  if localLast == tonumber(target.lastSeq) and current.rootHash == target.rootHash then
    state.ledgerTarget = nil
    state.ledgerRequestedThrough = nil
    Sync.AnnounceLedgerDigest()
    if state.syncBehind and state.reason == "LEDGER_GAP" then Sync.ClearSyncBehind() end
    return true
  end
  Sync.MarkSyncBehind("CANONICAL_ROOT_CONFLICT")
  return false
end
local function clearResolvedPolicyGap()
  local state = ensure(); local target = state.policyTarget
  if not target or not (Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetState) then return false end
  local current = Dibs.OperationalPolicy.GetState()
  if tonumber(current.policyRevision) == tonumber(target.revision) and current.hash == target.contentHash then
    state.policyTarget = nil
    if state.syncBehind and (state.reason == "POLICY_PARENT_MISSING" or state.reason == "POLICY_CHAIN_MISSING") then Sync.ClearSyncBehind() end
    return true
  end
  return false
end
local function clearResolvedSeasonCatalogGap()
  local state, target = ensure(), ensure().seasonCatalogTarget
  if not target or not (Dibs.Seasons and Dibs.Seasons.GetCatalogState) then return false end
  local current = Dibs.Seasons.GetCatalogState()
  if tonumber(current.catalogRevision) == tonumber(target.revision) and current.hash == target.contentHash then
    state.seasonCatalogTarget = nil
    if state.syncBehind and state.reason == "SEASON_CATALOG_PARENT_MISSING" then Sync.ClearSyncBehind() end
    return true
  end
  return false
end
function Sync.GetProtocolState() return ensure().protocolState end
function Sync.SetProtocolState(state, governanceApproved)
  -- B04 represents state but cannot independently enable enforcement.
  if state == "V2_ENFORCED" and governanceApproved ~= true then return false, "GOVERNANCE_CUTOVER_REQUIRED" end
  if state ~= "LEGACY_LOCAL" and state ~= "CUTOVER_PREPARED" and state ~= "V2_ENFORCED" then return false, "INVALID_PROTOCOL_STATE" end
  ensure().protocolState = state; return true, state
end
function Sync.CanEnforceV2(writers)
  local localMember = localSnapshot(); if not localMember then return false, "ROSTER_UNAVAILABLE" end
  writers = writers or { localMember.displayName }
  if type(writers) ~= "table" or #writers < 1 or #writers > 32 then return false, "WRITER_COMPATIBILITY_REQUIRED" end
  local state = ensure()
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
  message.protocol = { major = MAJOR, minor = MINOR, capabilities = { digest = true, whisperDetail = true, requestTombstones = true, ledgerDigestOnly = true, authoritySignals = true } }
  message.messageId = message.messageId or Dibs.NewId("v2msg")
  message.guildKey = Dibs.GetGuildKey(); message.senderNameRealm = snapshot.displayName; message.senderMemberKey = snapshot.memberKey
  message.addonVersion = Dibs.VERSION
  return message
end
function Sync.Send(message, channel, target)
  if Sync.ContainsForbiddenLiveLootData and Sync.ContainsForbiddenLiveLootData(message) then return false, "FORBIDDEN_LIVE_LOOT_DATA" end
  if not transportReady() then status("SYNC_UNAVAILABLE"); return false, "SYNC_UNAVAILABLE" end
  local envelope, reason = Sync.BuildEnvelope(message); if not envelope then return false, reason end
  channel = channel or "GUILD"
  if channel ~= "GUILD" and channel ~= "WHISPER" then return false, "INVALID_SYNC_CHANNEL" end
  if channel == "WHISPER" and (not trim(target) or #target > 96) then return false, "INVALID_WHISPER_TARGET" end
  Sync.TraceOutgoing(channel, target, message.type)
  local sent = Dibs.Ace3.SendComm("DIBS", envelope, channel, target, "BULK")
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
function Sync.AnnounceRequestIndex()
  return Sync.Send(Sync.BuildManifest(), "GUILD")
end
function Sync.BuildLedgerDigest()
  if not (Dibs.Governance and Dibs.Governance.IsV2Enforced and Dibs.Governance.IsV2Enforced()) then
    return { type = "LEDGER_DIGEST", entityType = "LEDGER", entityId = Dibs.GetCurrentSeasonId() or "none", revision = 0, contentHash = "LOCAL_ONLY" }
  end
  local state = Dibs.Ledger and Dibs.Ledger.GetCanonicalState and Dibs.Ledger.GetCanonicalState() or {}
  return { type = "LEDGER_DIGEST", entityType = "LEDGER", entityId = tostring(state.epoch or "none"), revision = tonumber(state.nextSeq or 1) - 1,
    contentHash = state.rootHash or "UNINITIALIZED", ledgerEpoch = state.epoch, lastSeq = tonumber(state.nextSeq or 1) - 1, rootHash = state.rootHash }
end
function Sync.BuildAuthorityDigest()
  local signal = Dibs.Governance and Dibs.Governance.BuildAuthoritySignal and Dibs.Governance.BuildAuthoritySignal()
  if not signal or signal.state == "LEGACY_LOCAL" then return nil end
  return { type = "DIGEST", entityType = "AUTHORITY", entityId = tostring(signal.ledgerEpoch or 0), revision = 1,
    contentHash = signal.contentHash, authorityState = signal.state, protocolState = Sync.GetProtocolState() }
end
function Sync.BuildGovernanceDigest()
  local record = Dibs.Governance and Dibs.Governance.GetCurrentRecord and Dibs.Governance.GetCurrentRecord()
  local state = Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState() or {}
  local baseline = Dibs.LegacyBaseline and Dibs.LegacyBaseline.GetBaseline and Dibs.LegacyBaseline.GetBaseline() or {}
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

local function vaultHash(record)
  return hash(vaultProjection(record))
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
local function localRequest(id)
  for _, request in ipairs(Dibs.PreDibs and Dibs.PreDibs.GetHistory and Dibs.PreDibs.GetHistory() or {}) do if request.requestId == id then return request end end
end

local function requestDetail(target, requestId)
  local request = localRequest(requestId); if not request then return false, "DETAIL_NOT_FOUND" end
  local owner = member(request.playerName); if not owner then return false, "REQUEST_OWNER_UNAVAILABLE" end
  return Sync.SendDetail("PREDIB_REQUEST", requestId, tonumber(request.revision) or 1, requestHash(request), request, target)
end
function Sync.SendDetail(entityType, entityId, revision, contentHash, payload, target)
  if entityType ~= "PREDIB_REQUEST" and entityType ~= "VAULT_DETAIL" and entityType ~= "GOVERNANCE" and entityType ~= "OPERATIONAL_POLICY" and entityType ~= "LEGACY_BASELINE" and entityType ~= "LEGACY_RECOVERY_PACKAGE" and entityType ~= "AUTHORITY_SIGNAL" and entityType ~= "AUTHORITY_ORPHAN" and entityType ~= "AWARD_COMMIT" and entityType ~= "AWARD_PROPOSAL" and entityType ~= "SEASON_CATALOG" then return false, "UNSUPPORTED_ENTITY" end
  if not transportReady() then return false, "SYNC_UNAVAILABLE" end
  local encoded = Dibs.Ace3.Serialize(payload); if type(encoded) ~= "string" or #encoded > MAX_BYTES then return false, "PAYLOAD_TOO_LARGE" end
  local transferId = Dibs.NewId("v2transfer"); local chunks = {}
  for offset = 1, #encoded, 480 do chunks[#chunks + 1] = encoded:sub(offset, offset + 479) end
  if #chunks < 1 or #chunks > MAX_CHUNKS then return false, "PAYLOAD_TOO_LARGE" end
  local rawHash = hash(encoded)
  local sent = Sync.Send({ type = "TRANSFER_BEGIN", transferId = transferId, entityType = entityType, entityId = entityId, revision = revision, contentHash = contentHash, payloadHash = rawHash, chunkCount = #chunks }, "WHISPER", target)
  if not sent then return false, "SYNC_UNAVAILABLE" end
  for index, chunk in ipairs(chunks) do if not Sync.Send({ type = "TRANSFER_CHUNK", transferId = transferId, chunkIndex = index, chunk = chunk }, "WHISPER", target) then return false, "SYNC_UNAVAILABLE" end end
  return Sync.Send({ type = "TRANSFER_END", transferId = transferId, entityType = entityType, entityId = entityId,
    revision = revision, contentHash = contentHash }, "WHISPER", target)
end

local function sendTransferAck(target, transfer, accepted, reason)
  if not transfer or transfer.entityType ~= "LEGACY_BASELINE" then return end
  local result = accepted and (reason == "TRANSFER_STARTED" and "STARTED" or "APPLIED") or "REJECTED"
  Sync.Send({ type = "TRANSFER_ACK", transferId = transfer.transferId, entityType = transfer.entityType,
    entityId = transfer.entityId, result = result, reasonCode = reason,
    receivedChunks = tonumber(transfer.receivedChunks) or 0, chunkCount = tonumber(transfer.chunkCount) or 0 }, "WHISPER", target)
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

---@param proposal table Award proposal recorded by a non-coordinator officer.
---@return boolean sent Whether the relay attempt was dispatched (not whether it was acknowledged).
---@return string reasonCode Outcome reason.
function Sync.RelayAwardProposal(proposal)
  if type(proposal) ~= "table" or type(proposal.proposalId) ~= "string" then return false, "INVALID_PROPOSAL" end
  local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
  local coordinatorNameRealm = authority and authority.coordinator and authority.coordinator.displayName
  if not coordinatorNameRealm then return false, "COORDINATOR_UNKNOWN" end
  if Dibs.Governance.NoteProposalRelayAttempt then Dibs.Governance.NoteProposalRelayAttempt(proposal.proposalId) end
  local hashValue = Sync.CalculateContentHash(proposal)
  return Sync.SendDetail("AWARD_PROPOSAL", proposal.proposalId, 1, hashValue, proposal, coordinatorNameRealm)
end

---Retries delivery of any locally pending (not-yet-acked) award proposals.
---Safe to call repeatedly (e.g. from the heartbeat); a no-op when nothing is pending.
function Sync.RetryPendingAwardProposals()
  if not (Dibs.Governance and Dibs.Governance.GetRelayPendingProposals) then return 0 end
  local pending = Dibs.Governance.GetRelayPendingProposals()
  local retryable = {}
  for index, proposal in ipairs(pending) do retryable[index] = proposal end
  retryable = retryableRecords(retryable, 5, function(proposal) return proposal.relayAttempts end)
  local count = 0
  for _, proposal in pairs(retryable) do Sync.RelayAwardProposal(proposal) end
  for _ in pairs(retryable) do count = count + 1 end
  return count
end
function Sync.AnnounceAwardCommit(commit)
  if type(commit) ~= "table" then return false, "INVALID_AWARD_COMMIT" end
  local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
  local localMember = localSnapshot()
  if not authority or authority.state ~= "ACTIVE" or not localMember or not authority.coordinator
    or authority.coordinator.memberKey ~= localMember.memberKey then return false, "CURRENT_COORDINATOR_REQUIRED" end
  return Sync.Send({ type = "LEDGER_DIGEST", entityType = "LEDGER", entityId = tostring(commit.ledgerEpoch), revision = commit.sequence,
    contentHash = commit.commitHash, ledgerEpoch = commit.ledgerEpoch, lastSeq = commit.sequence, rootHash = commit.commitHash }, "GUILD")
end
function Sync.AnnounceLedgerDigest()
  local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
  if not (Dibs.Governance and Dibs.Governance.IsV2Enforced and Dibs.Governance.IsV2Enforced())
    or not authority or authority.state ~= "ACTIVE" then return false, "V2_AUTHORITY_UNAVAILABLE" end
  return Sync.Send(Sync.BuildLedgerDigest(), "GUILD")
end

local function applyRequest(payload, transfer, sender)
  if type(payload) ~= "table" or payload.requestId ~= transfer.entityId or tonumber(payload.revision) ~= tonumber(transfer.revision) then return false, "ENTITY_IDENTITY_MISMATCH" end
  if requestHash(payload) ~= transfer.contentHash then return false, "CONTENT_HASH_MISMATCH" end
  local owner = member(payload.playerName)
  local officerRelay = owner and owner.memberKey ~= sender.memberKey and isAdmin(sender.displayName)
    and (localRole() == "gm" or localRole() == "officer")
  if not owner or (owner.memberKey ~= sender.memberKey and not officerRelay) then return false, "OWNER_MISMATCH" end
  local existing = localRequest(payload.requestId)
  if existing then
    local currentRevision, incomingRevision = tonumber(existing.revision) or 1, tonumber(payload.revision) or 1
    local currentHash = requestHash(existing)
    if incomingRevision == currentRevision then return currentHash == transfer.contentHash, currentHash == transfer.contentHash and "IDEMPOTENT_REPLAY" or "REQUEST_CONFLICT" end
    if incomingRevision < currentRevision then return false, "STALE_REVISION" end
  end
  local applied = false
  local reason = "SYNC_APPLY_UNAVAILABLE"
  if Dibs.PreDibs and Dibs.PreDibs.ApplyVerifiedSyncRecord then
    applied, reason = Dibs.PreDibs.ApplyVerifiedSyncRecord(payload, sender.displayName)
  end
  if not applied then return false, reason end
  local state = ensure(); state.requestIndex[payload.requestId] = { requestId = payload.requestId, revision = payload.revision, contentHash = transfer.contentHash, terminal = TERMINAL[payload.status] == true, updatedAt = payload.updatedAt or time() }
  if TERMINAL[payload.status] then state.tombstones[payload.requestId] = copy(state.requestIndex[payload.requestId]) end
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
  if Sync.IsSyncBehind() and ensure().reason == "VAULT_DETAIL_MISSING" then Sync.ClearSyncBehind() end
  return true, applyReason
end

function Sync.Receive(message, sender)
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
  if message.type == "DIGEST" or message.type == "LEDGER_DIGEST" or message.type == "VAULT_DIGEST" then
    peer.entities = peer.entities or {}
    local entityType = message.entityType or message.type
    peer.entities[entityType] = { revision = tonumber(message.revision) or 0, contentHash = message.contentHash, at = peer.at }
  end
  state.peers[resolved.memberKey] = peer
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
  if message.type == "AWARD_PROPOSAL_ACK" then
    if type(message.proposalId) ~= "string" or message.proposalId == "" then return false, "INVALID_PROPOSAL_ACK" end
    local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
    if not authority or authority.state ~= "ACTIVE" or not authority.coordinator or authority.coordinator.memberKey ~= resolved.memberKey then
      return false, "CURRENT_COORDINATOR_REQUIRED"
    end
    local acknowledged = false
    local acknowledgementReason = "PROPOSAL_ACK_UNAVAILABLE"
    if Dibs.Governance and Dibs.Governance.AckProposalRelay then
      local acknowledgement = { Dibs.Governance.AckProposalRelay(message.proposalId) }
      acknowledged, acknowledgementReason = acknowledgement[1], acknowledgement[2]
    end
    if not acknowledged then return false, acknowledgementReason or "PROPOSAL_ACK_UNAVAILABLE" end
    return true, "PROPOSAL_ACK_APPLIED"
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
      if message.revision and tonumber(message.revision) > 0 then Sync.MarkSyncBehind("LEDGER_GAP") end
      return true, "LEDGER_DIGEST_ONLY"
    end
    if not finiteInteger(message.ledgerEpoch) or not finiteInteger(message.lastSeq) or type(message.rootHash) ~= "string" then return false, "INVALID_LEDGER_DIGEST" end
    local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
    if not authority or authority.state ~= "ACTIVE" or not authority.coordinator then return false, "AUTHORITY_UNAVAILABLE" end
    local localState = Dibs.Ledger and Dibs.Ledger.GetCanonicalState and Dibs.Ledger.GetCanonicalState() or {}
    if tonumber(message.ledgerEpoch) ~= tonumber(localState.epoch) then return false, "STALE_EPOCH" end
    if authority.coordinator.memberKey ~= resolved.memberKey then return true, "LEDGER_STATUS_ONLY" end
    local localLast = tonumber(localState.nextSeq or 1) - 1
    if tonumber(message.lastSeq) > localLast then
      local state = ensure(); state.ledgerTarget = { epoch = message.ledgerEpoch, lastSeq = message.lastSeq, rootHash = message.rootHash }
      Sync.MarkSyncBehind("LEDGER_GAP")
      local requestedThrough = tonumber(state.ledgerRequestedThrough) or 0
      if localLast >= requestedThrough then
        local sent, through = requestAwardCommitBatch(resolved.displayName, message.ledgerEpoch, localLast + 1, message.lastSeq)
        if sent then state.ledgerRequestedThrough = through end
      end
      return true, "LEDGER_DETAIL_REQUESTED"
    end
    if tonumber(message.lastSeq) == localLast and message.rootHash ~= localState.rootHash then return false, "CANONICAL_ROOT_CONFLICT" end
    return true, "LEDGER_CURRENT"
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
    local baseline = Dibs.LegacyBaseline and Dibs.LegacyBaseline.GetBaseline and Dibs.LegacyBaseline.GetBaseline() or {}
    if message.baselineHash and baseline.legacyBaselineHash ~= message.baselineHash then
      Sync.Send({ type = "DETAIL_FETCH", requests = { {
        entityType = "LEGACY_BASELINE", entityId = message.baselineHash, revision = 1, contentHash = message.baselineHash,
      } } }, "WHISPER", resolved.displayName)
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
    if not writerAllowed then return false, writerReason or "POLICY_WRITER_REQUIRED" end
    local current = Dibs.OperationalPolicy and Dibs.OperationalPolicy.GetState and Dibs.OperationalPolicy.GetState() or { policyRevision = 0, hash = "GENESIS" }
    if tonumber(message.revision) > (tonumber(current.policyRevision) or 0) then
      local state = ensure(); state.policyTarget = { revision = message.revision, contentHash = message.contentHash }
      Sync.MarkSyncBehind("POLICY_CHAIN_MISSING")
      Sync.Send({ type = "DETAIL_FETCH", requests = { { entityType = "OPERATIONAL_POLICY", entityId = tostring(message.revision), revision = message.revision, contentHash = message.contentHash, parentHash = message.parentHash, parentRevision = message.parentRevision } } }, "WHISPER", resolved.displayName)
      return true, "POLICY_DETAIL_REQUESTED"
    end
    if tonumber(message.revision) == (tonumber(current.policyRevision) or 0) and message.contentHash ~= current.hash then return false, "POLICY_CONFLICT" end
    return true, "POLICY_CURRENT"
  end
  if message.type == "DIGEST" and message.entityType == "SEASON_CATALOG" then
    if not finiteInteger(message.revision) or type(message.contentHash) ~= "string" then return false, "INVALID_SEASON_CATALOG_DIGEST" end
    local writerAllowed = false
    local writerReason = "POLICY_WRITER_REQUIRED"
    if Dibs.OperationalPolicy and Dibs.OperationalPolicy.CanWrite then
      writerAllowed, writerReason = Dibs.OperationalPolicy.CanWrite(resolved.displayName)
    end
    if not writerAllowed then return false, writerReason or "POLICY_WRITER_REQUIRED" end
    local current = Dibs.Seasons and Dibs.Seasons.GetCatalogState and Dibs.Seasons.GetCatalogState() or { catalogRevision = 0, hash = "GENESIS" }
    if tonumber(message.revision) > (tonumber(current.catalogRevision) or 0) then
      local state = ensure(); state.seasonCatalogTarget = { revision = message.revision, contentHash = message.contentHash }
      Sync.MarkSyncBehind("SEASON_CATALOG_PARENT_MISSING")
      Sync.Send({ type = "DETAIL_FETCH", requests = { { entityType = "SEASON_CATALOG", entityId = tostring(message.revision), revision = message.revision, contentHash = message.contentHash, parentHash = message.parentHash, parentRevision = message.parentRevision } } }, "WHISPER", resolved.displayName)
      return true, "SEASON_CATALOG_DETAIL_REQUESTED"
    end
    if tonumber(message.revision) == (tonumber(current.catalogRevision) or 0) and message.contentHash ~= current.hash then return false, "SEASON_CATALOG_CONFLICT" end
    return true, "SEASON_CATALOG_CURRENT"
  end
  if message.type == "DIGEST" and message.entityType == "AUTHORITY" then
    if not isAdmin(resolved.displayName) or type(message.contentHash) ~= "string" then return false, "INVALID_AUTHORITY_DIGEST" end
    local localSignal = Dibs.Governance and Dibs.Governance.BuildAuthoritySignal and Dibs.Governance.BuildAuthoritySignal()
    if not localSignal or localSignal.contentHash ~= message.contentHash then
      Sync.MarkSyncBehind("AUTHORITY_DETAIL_MISSING")
      Sync.Send({ type = "DETAIL_FETCH", requests = { { entityType = "AUTHORITY_SIGNAL", entityId = message.entityId, revision = 1, contentHash = message.contentHash } } }, "WHISPER", resolved.displayName)
      return true, "AUTHORITY_DETAIL_REQUESTED"
    end
    return true, "AUTHORITY_CURRENT"
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
        local owner = request and member(request.playerName)
        local localMember = localSnapshot()
        local ownerIsLocal = owner and localMember and owner.memberKey == localMember.memberKey
        local officerRelay = (localRole() == "gm" or localRole() == "officer")
          and (resolved.role == "gm" or resolved.role == "officer")
        if request and owner and (ownerIsLocal or officerRelay) then requestDetail(resolved.displayName, requested.entityId) end
      elseif requested.entityType == "GOVERNANCE" and localRole() == "gm" then
        local governanceState = Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState()
        local record = governanceState and governanceState.records and governanceState.records[tostring(requested.revision)]
        if record and tonumber(record.governanceRevision) == tonumber(requested.revision) then
          local baseline = Dibs.LegacyBaseline and Dibs.LegacyBaseline.GetBaseline and Dibs.LegacyBaseline.GetBaseline()
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
      elseif requested.entityType == "LEGACY_BASELINE" and localRole() == "gm" then
        local baseline = Dibs.LegacyBaseline and Dibs.LegacyBaseline.GetBaseline and Dibs.LegacyBaseline.GetBaseline()
        if baseline and baseline.legacyBaselineHash and (not requested.contentHash or requested.contentHash == baseline.legacyBaselineHash) then
          Sync.SendDetail("LEGACY_BASELINE", baseline.legacyBaselineHash, 1, baseline.legacyBaselineHash, baseline, resolved.displayName)
        end
      elseif requested.entityType == "OPERATIONAL_POLICY" and Dibs.OperationalPolicy then
        local allowed = Dibs.OperationalPolicy.CanWrite and Dibs.OperationalPolicy.CanWrite(nil)
        local record = Dibs.OperationalPolicy.GetRecord and Dibs.OperationalPolicy.GetRecord(requested.revision)
        if allowed and record and tonumber(record.policyRevision) == tonumber(requested.revision) then
          Sync.SendDetail("OPERATIONAL_POLICY", tostring(record.policyRevision), record.policyRevision, record.contentHash, record, resolved.displayName)
        end
      elseif requested.entityType == "SEASON_CATALOG" and Dibs.Seasons then
        local allowed = Dibs.OperationalPolicy and Dibs.OperationalPolicy.CanWrite and Dibs.OperationalPolicy.CanWrite(nil)
        local record = Dibs.Seasons.GetCatalogRecord and Dibs.Seasons.GetCatalogRecord(requested.revision)
        if allowed and record and tonumber(record.catalogRevision) == tonumber(requested.revision) then
          Sync.SendDetail("SEASON_CATALOG", tostring(record.catalogRevision), record.catalogRevision, record.contentHash, record, resolved.displayName)
        end
      elseif requested.entityType == "AUTHORITY_SIGNAL" and Dibs.Governance and Dibs.Governance.BuildAuthoritySignal then
        local signal = Dibs.Governance.BuildAuthoritySignal()
        if signal and signal.state ~= "LEGACY_LOCAL" and (localRole() == "gm" or (signal.coordinator and signal.coordinator.memberKey == (localSnapshot() or {}).memberKey)) then
          Sync.SendAuthoritySignal(resolved.displayName)
        end
      elseif requested.entityType == "AWARD_COMMIT" and Dibs.Ledger and Dibs.Ledger.GetCanonicalCommit then
        local epoch, sequence = tostring(requested.entityId or ""):match("^(%d+):(%d+)$")
        local commit = epoch and sequence and Dibs.Ledger.GetCanonicalCommit(tonumber(epoch), tonumber(sequence))
        local authority = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
        local localMember = localSnapshot()
        if commit and authority and authority.state == "ACTIVE" and localMember and authority.coordinator
          and authority.coordinator.memberKey == localMember.memberKey then Sync.SendAwardCommit(commit, resolved.displayName) end
      end
    end
    return true, "DETAIL_SENT"
  end
  if message.type == "TRANSFER_BEGIN" then
    if type(message.transferId) ~= "string" or #message.transferId > 128 or type(message.entityType) ~= "string" or type(message.entityId) ~= "string" or not finiteInteger(message.revision) or not finiteInteger(message.chunkCount) or message.chunkCount < 1 or message.chunkCount > MAX_CHUNKS or type(message.contentHash) ~= "string" or type(message.payloadHash) ~= "string" then return false, "INVALID_TRANSFER_BEGIN" end
    if message.entityType ~= "PREDIB_REQUEST" and message.entityType ~= "VAULT_DETAIL" and message.entityType ~= "GOVERNANCE" and message.entityType ~= "OPERATIONAL_POLICY" and message.entityType ~= "LEGACY_BASELINE" and message.entityType ~= "LEGACY_RECOVERY_PACKAGE" and message.entityType ~= "AUTHORITY_SIGNAL" and message.entityType ~= "AUTHORITY_ORPHAN" and message.entityType ~= "AWARD_COMMIT" and message.entityType ~= "AWARD_PROPOSAL" and message.entityType ~= "SEASON_CATALOG" then return false, "UNSUPPORTED_ENTITY" end
    if message.entityType == "OPERATIONAL_POLICY" then
      local writerAllowed = false
      local writerReason = "POLICY_WRITER_REQUIRED"
      if Dibs.OperationalPolicy and Dibs.OperationalPolicy.CanWrite then
        local authorization = { Dibs.OperationalPolicy.CanWrite(resolved.displayName) }
        writerAllowed, writerReason = authorization[1], authorization[2]
      end
      if not writerAllowed then return false, writerReason or "POLICY_WRITER_REQUIRED" end
    end
    if message.entityType == "LEGACY_BASELINE" and resolved.role ~= "gm" then return false, "GUILD_MASTER_REQUIRED" end
    if message.entityType == "SEASON_CATALOG" then
      local writerAllowed = false
      local writerReason = "POLICY_WRITER_REQUIRED"
      if Dibs.OperationalPolicy and Dibs.OperationalPolicy.CanWrite then
        writerAllowed, writerReason = Dibs.OperationalPolicy.CanWrite(resolved.displayName)
      end
      if not writerAllowed then return false, writerReason or "POLICY_WRITER_REQUIRED" end
    end
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
    Dibs.runtime.v2Transfers[message.transferId] = { transferId = message.transferId, sender = resolved.memberKey,
      entityType = message.entityType, entityId = message.entityId, revision = message.revision,
      contentHash = message.contentHash, payloadHash = message.payloadHash, chunkCount = message.chunkCount,
      chunks = {}, receivedChunks = 0, totalBytes = 0, expiresAt = time() + TTL }
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
    local chunks = {}; for i = 1, transfer.chunkCount do if not transfer.chunks[i] then return false, "MISSING_TRANSFER_CHUNK" end; chunks[#chunks + 1] = transfer.chunks[i] end
    local raw = table.concat(chunks); if hash(raw) ~= transfer.payloadHash then return false, "PAYLOAD_HASH_MISMATCH" end
    local payload = Dibs.Ace3.Deserialize(raw); if type(payload) ~= "table" then return false, "DESERIALIZE_FAILED" end
    if transfer.entityType == "PREDIB_REQUEST" then
      local ok, applyReason = applyRequest(payload, transfer, resolved); if ok and Sync.IsSyncBehind() then Sync.ClearSyncBehind() end; return ok, applyReason
    end
    if transfer.entityType == "VAULT_DETAIL" then return applyVaultDetail(payload, transfer, resolved) end
    if transfer.entityType == "LEGACY_BASELINE" and Dibs.LegacyBaseline and Dibs.LegacyBaseline.ApplyApprovedBaseline then
      if payload.legacyBaselineHash ~= transfer.contentHash or transfer.entityId ~= payload.legacyBaselineHash then return false, "CONTENT_HASH_MISMATCH" end
      return Dibs.LegacyBaseline.ApplyApprovedBaseline(payload)
    end
    if transfer.entityType == "GOVERNANCE" and Dibs.Governance and Dibs.Governance.ApplyRecord then
      local ok, applyReason = Dibs.Governance.ApplyRecord(payload, resolved.displayName)
      if ok and Sync.IsSyncBehind() then Sync.ClearSyncBehind() end
      return ok, applyReason
    end
    if transfer.entityType == "OPERATIONAL_POLICY" and Dibs.OperationalPolicy and Dibs.OperationalPolicy.ApplyRecord then
      local ok, applyReason = Dibs.OperationalPolicy.ApplyRecord(payload, resolved.displayName)
      if not ok and applyReason == "POLICY_PARENT_MISSING" then
        local state = ensure()
        state.policyTarget = state.policyTarget or { revision = transfer.revision, contentHash = transfer.contentHash }
        Sync.MarkSyncBehind(applyReason)
        if type(payload) == "table" and finiteInteger(payload.parentRevision) and type(payload.parentHash) == "string" then
          Sync.Send({ type = "DETAIL_FETCH", requests = { { entityType = "OPERATIONAL_POLICY", entityId = tostring(payload.parentRevision), revision = payload.parentRevision, contentHash = payload.parentHash } } }, "WHISPER", resolved.displayName)
        end
      elseif ok then clearResolvedPolicyGap() end
      return ok, applyReason
    end
    if transfer.entityType == "SEASON_CATALOG" and Dibs.Seasons and Dibs.Seasons.ApplyCatalog then
      if payload.contentHash ~= transfer.contentHash or transfer.entityId ~= tostring(payload.catalogRevision) then return false, "CONTENT_HASH_MISMATCH" end
      local ok, applyReason = Dibs.Seasons.ApplyCatalog(payload, resolved.displayName)
      if not ok and applyReason == "SEASON_CATALOG_PARENT_MISSING" then
        local state = ensure()
        state.seasonCatalogTarget = { revision = transfer.revision, contentHash = transfer.contentHash }
        Sync.MarkSyncBehind(applyReason)
        Sync.Send({ type = "DETAIL_FETCH", requests = { { entityType = "SEASON_CATALOG", entityId = tostring(payload.parentRevision), revision = payload.parentRevision, contentHash = payload.parentHash } } }, "WHISPER", resolved.displayName)
      elseif ok then clearResolvedSeasonCatalogGap() end
      return ok, applyReason
    end
    if transfer.entityType == "LEGACY_RECOVERY_PACKAGE" and Dibs.LegacyBaseline and Dibs.LegacyBaseline.StageRecoveryPackage then
      if payload.contentHash ~= transfer.contentHash or transfer.entityId ~= payload.contentHash then return false, "CONTENT_HASH_MISMATCH" end
      local staged, stageReason = Dibs.LegacyBaseline.StageRecoveryPackage(payload, { sender = resolved.displayName })
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
      if ok and Sync.IsSyncBehind() then Sync.ClearSyncBehind() end
      return ok, applyReason
    end
    if transfer.entityType == "AUTHORITY_ORPHAN" and Dibs.Governance and Dibs.Governance.ApplyOrphanedEvidence then
      if Sync.CalculateContentHash(payload) ~= transfer.contentHash or transfer.entityId ~= (payload.evidenceId or payload.eventId or payload.transactionId) then return false, "CONTENT_HASH_MISMATCH" end
      return Dibs.Governance.ApplyOrphanedEvidence(payload, resolved.displayName)
    end
    if transfer.entityType == "AWARD_COMMIT" and Dibs.Ledger and Dibs.Ledger.ApplyAwardCommit then
      if payload.commitHash ~= transfer.contentHash or transfer.entityId ~= tostring(payload.ledgerEpoch) .. ":" .. tostring(payload.sequence) then return false, "CONTENT_HASH_MISMATCH" end
      local applied = Dibs.Ledger.ApplyAwardCommit(payload, resolved.displayName)
      if applied.accepted and not applied.idempotentReplay then clearResolvedLedgerGap(resolved.displayName) end
      return applied.accepted, applied.reasonCode
    end
    if transfer.entityType == "AWARD_PROPOSAL" and Dibs.Governance and Dibs.Governance.ReceiveRelayedProposal then
      if transfer.entityId ~= payload.proposalId then return false, "ENTITY_IDENTITY_MISMATCH" end
      if Sync.CalculateContentHash(payload) ~= transfer.contentHash then return false, "CONTENT_HASH_MISMATCH" end
      local accepted, applyReason = Dibs.Governance.ReceiveRelayedProposal(payload, resolved.displayName)
      if accepted then
        Sync.Send({ type = "AWARD_PROPOSAL_ACK", proposalId = payload.proposalId }, "WHISPER", resolved.displayName)
        -- Season-allocation grants are deterministic rank rules, not a loot judgment call; commit immediately.
        if payload.type == "SEASON_ALLOCATION" and Dibs.Ledger and Dibs.Ledger.CommitAwardProposal then
          Dibs.Ledger.CommitAwardProposal(nil, payload.proposalId, {})
        end
      end
      return accepted, applyReason
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
  local guildOnly = message.type == "HELLO" or message.type == "DIGEST" or message.type == "LEDGER_DIGEST" or message.type == "VAULT_DIGEST"
  if (guildOnly and channel ~= "GUILD") or (not guildOnly and channel ~= "WHISPER") then return false, "INVALID_TRANSPORT_CHANNEL" end
  local transfer = message.transferId and Dibs.runtime and Dibs.runtime.v2Transfers and Dibs.runtime.v2Transfers[message.transferId]
  if message.type == "TRANSFER_BEGIN" and message.entityType == "LEGACY_BASELINE" then
    transfer = { transferId = message.transferId, entityType = message.entityType, entityId = message.entityId }
  end
  local accepted, reason = Sync.Receive(message, sender)
  if message.type == "TRANSFER_END" and not transfer and message.entityType == "LEGACY_BASELINE" then
    transfer = { transferId = message.transferId, entityType = message.entityType, entityId = message.entityId }
  end
  if transfer and transfer.entityType == "LEGACY_BASELINE"
    and (message.type == "TRANSFER_END" or (message.type == "TRANSFER_BEGIN" and not accepted)) then
    sendTransferAck(sender, transfer, accepted, reason)
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
  if not Sync.RegisterTransport() then return false, "SYNC_UNAVAILABLE" end
  Sync.Send({ type = "HELLO", protocolState = Sync.GetProtocolState(), lifecycle = reason }, "GUILD")
  local digest = Sync.BuildManifest(); local sent = Sync.Send(digest, "GUILD")
  Sync.Send(Sync.BuildVaultDigest(), "GUILD")
  retryVaultRequests()
  Sync.AnnounceGovernance()
  local sendGovernedDigests = function()
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
  end
  if Dibs.Ace3 and Dibs.Ace3.ScheduleTimer then Dibs.Ace3.ScheduleTimer(sendGovernedDigests, 1) else sendGovernedDigests() end
  local authority = Sync.BuildAuthorityDigest()
  if authority then Sync.Send(authority, "GUILD") end
  local localMember = localSnapshot()
  local authorityState = Dibs.Governance and Dibs.Governance.GetAuthorityState and Dibs.Governance.GetAuthorityState()
  if Dibs.Governance and Dibs.Governance.IsV2Enforced and Dibs.Governance.IsV2Enforced()
    and authorityState and authorityState.state == "ACTIVE" and localMember then
    Sync.AnnounceLedgerDigest()
  end
  Sync.RetryPendingAwardProposals()
  scheduleHeartbeat()
  return sent, digest
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
