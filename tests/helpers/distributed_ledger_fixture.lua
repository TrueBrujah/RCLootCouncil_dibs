-- B00 architecture fixture only.  This module deliberately does not load or
-- emulate production Dibs code.  It describes the contracts future batches must
-- satisfy and gives tests deterministic network/partition controls.
local M = {}

local Scenario = {}
Scenario.__index = Scenario

local OPERATIONAL_KEYS = {
  preDibMode = true,
  requestAvailability = true,
  allowDebt = true,
}

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do result[key] = copy(item, seen) end
  return result
end

local function stableText(value)
  if type(value) ~= "table" then return tostring(value) end
  local keys, parts = {}, {}
  for key in pairs(value) do table.insert(keys, tostring(key)) end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local original = value[key]
    table.insert(parts, key .. "=" .. stableText(original))
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- A deterministic contract hash, intentionally not cryptography. Production
-- canonical serialization/hash selection belongs to B03/B04, not B00.
local function contractHash(value)
  local text = stableText(value)
  local total = 0
  for index = 1, #text do total = (total * 131 + text:byte(index)) % 2147483647 end
  return string.format("H%08x", total)
end

local function fullNameRealm(value)
  if type(value) ~= "string" or value == "" then return nil end
  local name, realm = value:match("^([^%-]+)%-(.+)$")
  if not name or not realm or name == "" or realm == "" then return nil end
  return string.lower(name .. "-" .. realm)
end

local function clientState(client)
  return client.state
end

local function eventHash(event)
  return contractHash({
    id = event.id,
    epoch = event.epoch,
    seq = event.seq,
    previousHash = event.previousHash,
    player = event.player,
    amount = event.amount,
    evidence = event.evidence,
  })
end

local function append(list, value)
  table.insert(list, value)
  return value
end

function M.createGuild(opts)
  opts = opts or {}
  local self = setmetatable({
    guildKey = opts.guildKey or "TestGuild-Realm",
    clients = {},
    raids = {},
    messages = {},
    nextMessageId = 0,
    partitions = {},
    governance = {
      status = "POLICY_UNINITIALIZED",
      revision = 0,
      hash = "GENESIS",
      policyRevision = 0,
      operationalHash = "GENESIS",
      ledgerEpoch = nil,
      coordinator = nil,
      protocolState = "LEGACY_LOCAL",
      baselineHash = nil,
    },
  }, Scenario)
  return self
end

function Scenario:createClient(opts)
  opts = opts or {}
  assert(fullNameRealm(opts.nameRealm), "client requires full Name-Realm identity")
  local key = fullNameRealm(opts.nameRealm)
  local client = {
    id = key,
    nameRealm = opts.nameRealm,
    wireIdentity = key,
    role = opts.role or "player",
    protocol = opts.protocol or "V2",
    guidWitness = opts.guidWitness,
    raid = nil,
    connected = true,
    state = {
      authorityState = "LOCAL_ONLY",
      ledgerEpoch = nil,
      coordinator = nil,
      lastSeq = 0,
      lastHash = "GENESIS",
      canonicalEvents = {},
      evidence = {},
      orphaned = {},
      pending = {},
      syncBehind = false,
      gaps = {},
      balance = 0,
      policyRevision = 0,
      governanceRevision = 0,
      protocolState = "LEGACY_LOCAL",
    },
  }
  self.clients[key] = client
  return client
end

function Scenario:getClient(identity)
  return self.clients[fullNameRealm(identity) or tostring(identity)]
end

function Scenario:createRaid(raidId, members)
  local raid = { id = tostring(raidId), members = {} }
  self.raids[raid.id] = raid
  for _, identity in ipairs(members or {}) do
    local client = assert(self:getClient(identity), "unknown raid client")
    client.raid = raid.id
    table.insert(raid.members, client.id)
  end
  return raid
end

function Scenario:connectClients(first, second)
  self.partitions[first .. "|" .. second] = nil
  self.partitions[second .. "|" .. first] = nil
end

function Scenario:partitionClients(first, second)
  local a = assert(self:getClient(first), "unknown first client")
  local b = assert(self:getClient(second), "unknown second client")
  self.partitions[a.id .. "|" .. b.id] = true
  self.partitions[b.id .. "|" .. a.id] = true
end

function Scenario:healPartition(first, second)
  self:connectClients(first, second)
end

function Scenario:disconnectClient(identity)
  local client = assert(self:getClient(identity), "unknown client")
  client.connected = false
  return client
end

function Scenario:reconnectClient(identity)
  local client = assert(self:getClient(identity), "unknown client")
  client.connected = true
  return client
end

function Scenario:send(senderIdentity, targetIdentity, payload, opts)
  opts = opts or {}
  local sender = assert(self:getClient(senderIdentity), "unknown sender")
  local target = assert(self:getClient(targetIdentity), "unknown target")
  self.nextMessageId = self.nextMessageId + 1
  local packet = {
    id = self.nextMessageId,
    sender = sender.id,
    target = target.id,
    payload = copy(payload),
    delayed = opts.delayed == true,
    dropped = opts.dropped == true,
    partitioned = self.partitions[sender.id .. "|" .. target.id] == true,
    delivered = false,
  }
  append(self.messages, packet)
  return packet
end

function Scenario:delay(packet)
  packet.delayed = true
  return packet
end

function Scenario:duplicate(packet)
  return self:send(packet.sender, packet.target, packet.payload, { delayed = packet.delayed })
end

function Scenario:drop(packet)
  packet.dropped = true
  return packet
end

function Scenario:reorder(first, second)
  local firstIndex, secondIndex
  for index, packet in ipairs(self.messages) do
    if packet == first then firstIndex = index end
    if packet == second then secondIndex = index end
  end
  assert(firstIndex and secondIndex, "packets must belong to scenario")
  self.messages[firstIndex], self.messages[secondIndex] = self.messages[secondIndex], self.messages[firstIndex]
end

function Scenario:deliver(packet)
  if packet.delivered or packet.dropped or packet.partitioned then return false, "NOT_DELIVERABLE" end
  local target = self.clients[packet.target]
  if not target or not target.connected then return false, "TARGET_OFFLINE" end
  packet.delivered = true
  return true, copy(packet.payload)
end

function Scenario:deliverNext()
  for _, packet in ipairs(self.messages) do
    if not packet.delivered and not packet.delayed and not packet.dropped and not packet.partitioned then
      local ok, result = self:deliver(packet)
      return ok, result, packet
    end
  end
  return false, "NO_DELIVERABLE_MESSAGE"
end

function Scenario:releaseDelayed(packet)
  packet.delayed = false
  return packet
end

function Scenario:inspectMessages()
  return copy(self.messages)
end

function Scenario:inspectCanonicalState(identity)
  local client = assert(self:getClient(identity), "unknown client")
  return copy(clientState(client))
end

function Scenario:inspectEvidenceState(identity)
  local client = assert(self:getClient(identity), "unknown client")
  return copy({ evidence = client.state.evidence, orphaned = client.state.orphaned })
end

function Scenario:resolveWireIdentity(value, guidWitness)
  local key = fullNameRealm(value)
  if key then
    return { memberKey = key, guidWitness = guidWitness, reason = nil }
  end
  return nil, "AMBIGUOUS_IDENTITY"
end

function Scenario:adoptGovernance(gmIdentity, record)
  local gm = assert(self:getClient(gmIdentity), "unknown GM")
  if gm.role ~= "gm" then return false, "GUILD_MASTER_REQUIRED" end
  if self.governance.status ~= "POLICY_UNINITIALIZED" then return false, "POLICY_ALREADY_ADOPTED" end
  if not record or record.parentHash ~= "GENESIS" or record.revision ~= 1 then return false, "INVALID_GOVERNANCE_PARENT" end
  if record.author ~= gm.id then return false, "GOVERNANCE_AUTHOR_MISMATCH" end
  local expected = contractHash(record.values or {})
  if record.hash ~= expected then return false, "GOVERNANCE_HASH_MISMATCH" end
  self.governance.status = "ADOPTED"
  self.governance.revision = record.revision
  self.governance.hash = record.hash
  self.governance.ledgerEpoch = record.ledgerEpoch
  self.governance.coordinator = record.coordinator
  self.governance.baselineHash = record.baselineHash
  for _, client in pairs(self.clients) do
    client.state.governanceRevision = record.revision
    client.state.ledgerEpoch = record.ledgerEpoch
    client.state.coordinator = record.coordinator
    client.state.lastHash = record.baselineHash or "GENESIS"
    client.state.protocolState = self.governance.protocolState
  end
  return true
end

function Scenario:applyGovernance(gmIdentity, record)
  local gm = assert(self:getClient(gmIdentity), "unknown GM")
  if gm.role ~= "gm" then return false, "GUILD_MASTER_REQUIRED" end
  if not record or record.author ~= gm.id then return false, "GOVERNANCE_AUTHOR_MISMATCH" end
  if record.revision ~= self.governance.revision + 1 or record.parentHash ~= self.governance.hash then
    return false, "GOVERNANCE_PARENT_MISMATCH"
  end
  if record.hash ~= contractHash(record.values or {}) then return false, "GOVERNANCE_HASH_MISMATCH" end
  self.governance.revision = record.revision
  self.governance.hash = record.hash
  if record.ledgerEpoch ~= nil then self.governance.ledgerEpoch = record.ledgerEpoch end
  if record.coordinator ~= nil then self.governance.coordinator = record.coordinator end
  if record.baselineHash ~= nil then self.governance.baselineHash = record.baselineHash end
  return true
end

function Scenario:applyOperationalPolicy(writerIdentity, record)
  local writer = assert(self:getClient(writerIdentity), "unknown writer")
  if writer.role ~= "gm" and writer.role ~= "officer" then return false, "OPERATIONAL_WRITER_REQUIRED" end
  if self.governance.status ~= "ADOPTED" then return false, "POLICY_UNINITIALIZED" end
  if not record or record.revision ~= self.governance.policyRevision + 1 then return false, "OPERATIONAL_REVISION_MISMATCH" end
  if record.parentHash ~= self.governance.operationalHash then return false, "OPERATIONAL_PARENT_MISMATCH" end
  for key in pairs(record.values or {}) do
    if not OPERATIONAL_KEYS[key] then return false, "GOVERNANCE_FIELD_FORBIDDEN" end
  end
  if record.hash ~= contractHash(record.values or {}) then return false, "OPERATIONAL_HASH_MISMATCH" end
  self.governance.policyRevision = record.revision
  self.governance.operationalHash = record.hash
  for _, client in pairs(self.clients) do client.state.policyRevision = record.revision end
  return true
end

function Scenario:enforceV2(gmIdentity, activeWriterIdentities, baselineHash)
  local gm = assert(self:getClient(gmIdentity), "unknown GM")
  if gm.role ~= "gm" then return false, "GUILD_MASTER_REQUIRED" end
  if not baselineHash or baselineHash ~= self.governance.baselineHash then return false, "BASELINE_REQUIRED" end
  for _, identity in ipairs(activeWriterIdentities or {}) do
    local writer = assert(self:getClient(identity), "unknown writer")
    if writer.protocol ~= "V2" then return false, "ACTIVE_WRITER_PROTOCOL_INCOMPATIBLE" end
  end
  self.governance.protocolState = "V2_ENFORCED"
  for _, client in pairs(self.clients) do client.state.protocolState = "V2_ENFORCED" end
  return true
end

function Scenario:activateCoordinator(identity, epoch, baselineHash)
  local client = assert(self:getClient(identity), "unknown coordinator")
  local state = client.state
  if state.syncBehind then return false, "SYNC_BEHIND" end
  if self.governance.protocolState ~= "V2_ENFORCED" then return false, "V2_NOT_ENFORCED" end
  if epoch ~= self.governance.ledgerEpoch or baselineHash ~= self.governance.baselineHash then
    return false, "GOVERNANCE_EPOCH_MISMATCH"
  end
  state.authorityState = "ACTIVE"
  state.ledgerEpoch = epoch
  state.coordinator = client.id
  state.lastSeq = 0
  state.lastHash = baselineHash
  self.governance.coordinator = client.id
  return true
end

function Scenario:appendCommit(identity, event)
  local client = assert(self:getClient(identity), "unknown coordinator")
  local state = client.state
  if state.authorityState ~= "ACTIVE" or state.coordinator ~= client.id then return false, "NOT_ACTIVE_COORDINATOR" end
  if state.syncBehind then return false, "SYNC_BEHIND" end
  if event.epoch ~= state.ledgerEpoch then return false, "STALE_OR_FUTURE_EPOCH" end
  if event.seq ~= state.lastSeq + 1 then return false, "SEQUENCE_GAP" end
  if event.previousHash ~= state.lastHash then return false, "PREVIOUS_HASH_MISMATCH" end
  if event.contentHash ~= eventHash(event) then return false, "CONTENT_HASH_MISMATCH" end
  append(state.canonicalEvents, copy(event))
  state.lastSeq = event.seq
  state.lastHash = event.contentHash
  state.balance = state.balance + (tonumber(event.amount) or 0)
  return true
end

function Scenario:receiveLedger(identity, event)
  local client = assert(self:getClient(identity), "unknown receiver")
  local state = client.state
  if event.epoch < (state.ledgerEpoch or 0) then
    append(state.orphaned, { event = copy(event), reason = "LATE_EXCLUDED_EPOCH" })
    return false, "ORPHANED_EVIDENCE"
  end
  if event.epoch ~= state.ledgerEpoch then
    state.syncBehind = true
    append(state.gaps, { reason = "EPOCH_MISMATCH", event = copy(event) })
    return false, "SYNC_BEHIND"
  end
  if event.seq <= state.lastSeq then
    for _, existing in ipairs(state.canonicalEvents) do
      if existing.id == event.id and existing.contentHash == event.contentHash then return true, "IDEMPOTENT_REPLAY" end
    end
    return false, "LEDGER_CONFLICT"
  end
  if event.seq ~= state.lastSeq + 1 or event.previousHash ~= state.lastHash then
    state.syncBehind = true
    append(state.gaps, { expectedSeq = state.lastSeq + 1, event = copy(event) })
    append(state.pending, copy(event))
    return false, "SYNC_BEHIND"
  end
  if event.contentHash ~= eventHash(event) then return false, "CONTENT_HASH_MISMATCH" end
  append(state.canonicalEvents, copy(event))
  state.lastSeq = event.seq
  state.lastHash = event.contentHash
  state.balance = state.balance + (tonumber(event.amount) or 0)
  return true
end

function Scenario:beginRecovery(identity)
  local client = assert(self:getClient(identity), "unknown client")
  client.state.authorityState = "RECOVERY_PENDING"
  client.state.coordinator = nil
  return true
end

function Scenario:markCoordinatorUnavailable(identity)
  local client = assert(self:getClient(identity), "unknown client")
  client.state.authorityState = "COORDINATOR_UNAVAILABLE"
  client.state.coordinator = nil
  return true
end

function Scenario:recordAwardProposal(identity, proposal)
  local client = assert(self:getClient(identity), "unknown client")
  if client.state.authorityState ~= "RECOVERY_PENDING" and client.state.authorityState ~= "COORDINATOR_UNAVAILABLE" then
    return false, "COORDINATOR_AVAILABLE"
  end
  local evidence = copy(proposal or {})
  evidence.status = "PENDING_RECONCILIATION"
  append(client.state.evidence, evidence)
  return true, evidence
end

function Scenario:recordLegacyEvidence(identity, record)
  local client = assert(self:getClient(identity), "unknown client")
  local evidence = copy(record or {})
  evidence.immutable = true
  append(client.state.evidence, evidence)
  return evidence
end

function Scenario:closeHandoff(identity)
  local client = assert(self:getClient(identity), "unknown coordinator")
  local state = client.state
  if state.authorityState ~= "ACTIVE" or state.coordinator ~= client.id then return nil, "NOT_ACTIVE_COORDINATOR" end
  state.authorityState = "HANDOFF_CLOSING"
  return {
    previousEpoch = state.ledgerEpoch,
    finalSeq = state.lastSeq,
    rootHash = state.lastHash,
  }
end

function Scenario:activateNormalHandoff(gmIdentity, targetIdentity, closure, nextEpoch)
  local gm = assert(self:getClient(gmIdentity), "unknown GM")
  local target = assert(self:getClient(targetIdentity), "unknown target")
  if gm.role ~= "gm" then return false, "GUILD_MASTER_REQUIRED" end
  if not closure or not closure.previousEpoch or closure.finalSeq == nil or not closure.rootHash then return false, "CLOSURE_REQUIRED" end
  if nextEpoch ~= closure.previousEpoch + 1 then return false, "EPOCH_TRANSITION_INVALID" end
  if target.state.syncBehind then return false, "SYNC_BEHIND" end
  target.state.authorityState = "ACTIVE"
  target.state.ledgerEpoch = nextEpoch
  target.state.coordinator = target.id
  target.state.lastSeq = 0
  target.state.lastHash = closure.rootHash
  self.governance.ledgerEpoch = nextEpoch
  self.governance.coordinator = target.id
  self.governance.baselineHash = closure.rootHash
  return true
end

function Scenario:approveForcedRecovery(gmIdentity, targetIdentity, baseline, nextEpoch, auditDecisions)
  local gm = assert(self:getClient(gmIdentity), "unknown GM")
  local target = assert(self:getClient(targetIdentity), "unknown target")
  if gm.role ~= "gm" then return false, "GUILD_MASTER_REQUIRED" end
  if target.state.authorityState ~= "RECOVERY_PENDING" then return false, "RECOVERY_PENDING_REQUIRED" end
  if type(baseline) ~= "table" or type(baseline.hash) ~= "string" or type(baseline.peerEvidence) ~= "table" or #baseline.peerEvidence == 0 or type(auditDecisions) ~= "table" or #auditDecisions == 0 then
    return false, "RECOVERY_BASELINE_REQUIRED"
  end
  if nextEpoch ~= (target.state.ledgerEpoch or 0) + 1 then return false, "EPOCH_TRANSITION_INVALID" end
  target.state.authorityState = "ACTIVE"
  target.state.ledgerEpoch = nextEpoch
  target.state.coordinator = target.id
  target.state.lastSeq = 0
  target.state.lastHash = baseline.hash
  -- The approved baseline is the pre-epoch history; this fixture retains only
  -- events appended after the newly activated epoch in canonicalEvents.
  target.state.canonicalEvents = {}
  target.state.syncBehind = false
  self.governance.ledgerEpoch = nextEpoch
  self.governance.coordinator = target.id
  self.governance.baselineHash = baseline.hash
  self.governance.recoveryAudit = copy(auditDecisions)
  return true
end

function Scenario:advanceAuthorityState(identity, state)
  local client = assert(self:getClient(identity), "unknown client")
  client.state.authorityState = state
  return client.state.authorityState
end

function M.makeLedgerEvent(fields)
  local event = copy(fields or {})
  event.contentHash = eventHash(event)
  return event
end

function M.contractHash(value)
  return contractHash(value)
end

return M
