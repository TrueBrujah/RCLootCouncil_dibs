--[[
Module: Dibs.Governance
Layer: Governance bootstrap
Purpose: Store explicit GM-only governance records before operational policy or
distributed-ledger behavior exists.
Responsibilities: POLICY_UNINITIALIZED state, GM adoption, parent/hash checks,
idempotency, and auditable conflicts.
Non-responsibilities: Operational policy, coordinator activation, ledger epochs,
protocol-V2 transport, reconciliation, and RCLootCouncil integration.
Dependencies: Dibs.Identity current-roster authority boundary and Dibs.GetDB.
SavedVariables: db.governance (additive; schema 1).
]]

local Dibs = _G.Dibs
Dibs.Governance = Dibs.Governance or {}
local Governance = Dibs.Governance

local SCHEMA = 1
local GENESIS_HASH = "GENESIS"

local function copy(value)
  return Dibs.DeepCopy and Dibs.DeepCopy(value) or value
end

local function sortedKeys(value)
  local keys = {}
  for key in pairs(value or {}) do table.insert(keys, key) end
  table.sort(keys, function(a, b) return type(a) .. ":" .. tostring(a) < type(b) .. ":" .. tostring(b) end)
  return keys
end

local function canonicalText(value, seen)
  local valueType = type(value)
  if valueType ~= "table" then return valueType .. ":" .. tostring(value) end
  seen = seen or {}
  if seen[value] then return "table:<cycle>" end
  seen[value] = true
  local parts = {}
  for _, key in ipairs(sortedKeys(value)) do
    table.insert(parts, canonicalText(key, seen) .. "=" .. canonicalText(value[key], seen))
  end
  seen[value] = nil
  return "table:{" .. table.concat(parts, ",") .. "}"
end

local function contentHash(record)
  local canonical = {
    schema = record.schema,
    recordClass = record.recordClass,
    guildKey = record.guildKey,
    governanceRevision = record.governanceRevision,
    parentRevision = record.parentRevision,
    parentHash = record.parentHash,
    authorNameRealm = record.authorNameRealm,
    authorMemberKey = record.authorMemberKey,
    authorSnapshot = record.authorSnapshot,
    timestamp = record.timestamp,
    audit = record.audit,
    content = record.content,
  }
  local text, total = canonicalText(canonical), 0
  for index = 1, #text do total = (total * 131 + text:byte(index)) % 2147483647 end
  return string.format("G%08x", total)
end

local function defaultState()
  return {
    schema = SCHEMA,
    status = "POLICY_UNINITIALIZED",
    revision = 0,
    hash = GENESIS_HASH,
    records = {},
    auditLog = {},
    conflicts = {},
    aliases = { schema = 1, records = {} },
    future = { coordinator = nil, ledgerEpoch = nil, protocolState = "LEGACY_LOCAL", baseline = nil },
  }
end

local function ensureState()
  local db = Dibs.GetDB()
  if type(db.governance) ~= "table" then db.governance = defaultState() end
  local state = db.governance
  if state.schema ~= SCHEMA then state.schema = SCHEMA end
  if state.status ~= "POLICY_UNINITIALIZED" and state.status ~= "GOVERNANCE_ADOPTED" then state.status = "POLICY_UNINITIALIZED" end
  if type(state.revision) ~= "number" or state.revision < 0 then state.revision = 0 end
  if type(state.hash) ~= "string" or state.hash == "" then state.hash = GENESIS_HASH end
  if type(state.records) ~= "table" then state.records = {} end
  if type(state.auditLog) ~= "table" then state.auditLog = {} end
  if type(state.conflicts) ~= "table" then state.conflicts = {} end
  if type(state.aliases) ~= "table" then state.aliases = { schema = 1, records = {} } end
  if type(state.aliases.records) ~= "table" then state.aliases.records = {} end
  if type(state.future) ~= "table" then state.future = defaultState().future end
  state.future.coordinator = nil
  state.future.ledgerEpoch = nil
  state.future.protocolState = "LEGACY_LOCAL"
  state.future.baseline = nil
  return state
end

local function isInteger(value)
  return type(value) == "number" and value == math.floor(value)
end

local function inactiveFuture(proposal)
  proposal = proposal or {}
  local future = proposal.future or {}
  if type(future) ~= "table" then return nil, "INVALID_FUTURE_GOVERNANCE" end
  if proposal.coordinator ~= nil or proposal.ledgerEpoch ~= nil or proposal.baseline ~= nil
    or future.coordinator ~= nil or future.ledgerEpoch ~= nil or future.baseline ~= nil
  then
    return nil, "FUTURE_GOVERNANCE_INACTIVE"
  end
  local protocol = proposal.protocolState or future.protocolState
  if protocol ~= nil and protocol ~= "LEGACY_LOCAL" then return nil, "PROTOCOL_CUTOVER_NOT_AVAILABLE" end
  return { coordinator = nil, ledgerEpoch = nil, protocolState = "LEGACY_LOCAL", baseline = nil }
end

local function governanceContent(proposal)
  proposal = proposal or {}
  if type(proposal) ~= "table" then return nil, "INVALID_GOVERNANCE_CONTENT" end
  local future, futureReason = inactiveFuture(proposal)
  if not future then return nil, futureReason end
  local officerRule = proposal.officerAuthorityRule or { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 }
  local writerRule = proposal.policyWriterRule or { kind = "GOVERNANCE_ONLY" }
  if type(officerRule) ~= "table" or type(writerRule) ~= "table" then return nil, "INVALID_GOVERNANCE_RULE" end
  return {
    officerAuthorityRule = copy(officerRule),
    policyWriterRule = copy(writerRule),
    future = future,
  }
end

local function currentGMSnapshot(actor)
  if not Dibs.Identity or type(Dibs.Identity.CreateSnapshot) ~= "function" then return nil, "IDENTITY_UNAVAILABLE" end
  local snapshot, reason = Dibs.Identity.CreateSnapshot(actor)
  if not snapshot then return nil, reason end
  local isGM, gmReason = Dibs.Identity.IsCurrentGuildMaster(snapshot)
  if not isGM then return nil, gmReason end
  return snapshot
end

local function createRecord(actor, proposal, revision, parentRevision, parentHash)
  local snapshot, authorityReason = currentGMSnapshot(actor)
  if not snapshot then return nil, authorityReason end
  local content, contentReason = governanceContent(proposal)
  if not content then return nil, contentReason end
  local timestamp = Dibs.GetTimestamp and Dibs.GetTimestamp() or time()
  local record = {
    schema = SCHEMA,
    recordClass = "GOVERNANCE",
    guildKey = Dibs.GetGuildKey(),
    governanceRevision = revision,
    parentRevision = parentRevision,
    parentHash = parentHash,
    authorNameRealm = snapshot.displayName,
    authorMemberKey = snapshot.memberKey,
    authorSnapshot = copy(snapshot),
    timestamp = timestamp,
    audit = { action = revision == 1 and "INITIAL_ADOPTION" or "GOVERNANCE_CHANGE", reason = proposal and proposal.reason or nil },
    content = content,
  }
  record.contentHash = contentHash(record)
  return record
end

local function validateRecordShape(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA or record.recordClass ~= "GOVERNANCE" then return false, "INVALID_GOVERNANCE_RECORD" end
  if record.guildKey ~= Dibs.GetGuildKey() then return false, "GUILD_SCOPE_MISMATCH" end
  if not isInteger(record.governanceRevision) or record.governanceRevision < 1 then return false, "INVALID_GOVERNANCE_REVISION" end
  if not isInteger(record.parentRevision) or type(record.parentHash) ~= "string" or type(record.authorNameRealm) ~= "string" or type(record.authorMemberKey) ~= "string" then return false, "INVALID_GOVERNANCE_PARENT" end
  if type(record.authorSnapshot) ~= "table" or record.authorSnapshot.memberKey ~= record.authorMemberKey then return false, "INVALID_AUTHOR_SNAPSHOT" end
  if type(record.timestamp) ~= "number" or type(record.audit) ~= "table" or type(record.content) ~= "table" then return false, "INVALID_GOVERNANCE_METADATA" end
  local content, reason = governanceContent(record.content)
  if not content then return false, reason end
  if canonicalText(content) ~= canonicalText(record.content) then return false, "UNSUPPORTED_GOVERNANCE_FIELD" end
  if record.contentHash ~= contentHash(record) then return false, "GOVERNANCE_HASH_MISMATCH" end
  return true
end

function Governance.CalculateContentHash(record)
  return contentHash(record or {})
end

function Governance.GetState()
  return copy(ensureState())
end

function Governance.GetCurrentRecord()
  local state = ensureState()
  return state.records[tostring(state.revision)] and copy(state.records[tostring(state.revision)]) or nil
end

function Governance.CreateInitialRecord(actor, proposal)
  local state = ensureState()
  if state.status ~= "POLICY_UNINITIALIZED" or state.revision ~= 0 then return nil, "GOVERNANCE_ALREADY_ADOPTED" end
  return createRecord(actor, proposal, 1, 0, GENESIS_HASH)
end

function Governance.CreateChangeRecord(actor, proposal)
  local state = ensureState()
  if state.status ~= "GOVERNANCE_ADOPTED" then return nil, "POLICY_UNINITIALIZED" end
  return createRecord(actor, proposal, state.revision + 1, state.revision, state.hash)
end

function Governance.ApplyRecord(record, sender)
  local valid, validationReason = validateRecordShape(record)
  if not valid then return false, validationReason end
  local senderSnapshot, authorityReason = currentGMSnapshot(sender)
  if not senderSnapshot then return false, authorityReason end
  if senderSnapshot.memberKey ~= record.authorMemberKey then return false, "AUTHOR_SENDER_MISMATCH" end

  local state = ensureState()
  if record.governanceRevision == state.revision then
    if record.contentHash == state.hash then return true, "IDEMPOTENT_REPLAY", copy(state.records[tostring(state.revision)]) end
    table.insert(state.conflicts, {
      revision = record.governanceRevision,
      existingHash = state.hash,
      conflictingHash = record.contentHash,
      receivedFrom = senderSnapshot.memberKey,
      receivedAt = Dibs.GetTimestamp and Dibs.GetTimestamp() or time(),
    })
    return false, "GOVERNANCE_CONFLICT"
  end

  if record.governanceRevision ~= state.revision + 1
    or record.parentRevision ~= state.revision
    or record.parentHash ~= state.hash
  then
    return false, "GOVERNANCE_PARENT_MISMATCH"
  end
  if state.status == "POLICY_UNINITIALIZED" and (record.governanceRevision ~= 1 or record.parentRevision ~= 0 or record.parentHash ~= GENESIS_HASH) then
    return false, "GOVERNANCE_PARENT_MISMATCH"
  end

  state.status = "GOVERNANCE_ADOPTED"
  state.revision = record.governanceRevision
  state.hash = record.contentHash
  state.records[tostring(record.governanceRevision)] = copy(record)
  state.future = copy(record.content.future)
  table.insert(state.auditLog, {
    action = record.audit.action,
    revision = record.governanceRevision,
    hash = record.contentHash,
    author = copy(record.authorSnapshot),
    timestamp = record.timestamp,
  })
  return true, "ADOPTED", copy(record)
end

function Governance.AdoptInitial(actor, proposal)
  local record, reason = Governance.CreateInitialRecord(actor, proposal)
  if not record then return false, reason end
  return Governance.ApplyRecord(record, actor)
end

function Governance.Change(actor, proposal)
  local record, reason = Governance.CreateChangeRecord(actor, proposal)
  if not record then return false, reason end
  return Governance.ApplyRecord(record, actor)
end

return Governance
