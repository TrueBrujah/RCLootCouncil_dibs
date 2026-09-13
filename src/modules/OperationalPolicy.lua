--[[
Module: Dibs.OperationalPolicy
Layer: Guild operational policy
Purpose: Maintain the separately revisioned, allowlisted rules that officers
may change after explicit GM governance adoption.
Non-responsibilities: Governance, coordinator/epoch, canonical ledger, protocol
cutover, RCLootCouncil, and local presentation preferences.
]]

local Dibs = _G.Dibs
Dibs.OperationalPolicy = Dibs.OperationalPolicy or {}
local Policy = Dibs.OperationalPolicy

local SCHEMA, GENESIS_HASH = 1, "GENESIS"
local VALID_MODES = { WILD_OPEN = true, ENCOUNTER = true }

local function copy(value) return Dibs.DeepCopy and Dibs.DeepCopy(value) or value end
local function integer(value) return type(value) == "number" and value == math.floor(value) end

local function defaultState()
  return { schema = SCHEMA, status = "POLICY_UNINITIALIZED", policyRevision = 0, hash = GENESIS_HASH, records = {}, auditLog = {}, conflicts = {} }
end

local function ensureState()
  local db = Dibs.GetDB()
  if type(db.operationalPolicy) ~= "table" then db.operationalPolicy = defaultState() end
  local state = db.operationalPolicy
  if state.schema ~= SCHEMA then state.schema = SCHEMA end
  if state.status ~= "POLICY_UNINITIALIZED" and state.status ~= "POLICY_ADOPTED" then state.status = "POLICY_UNINITIALIZED" end
  if not integer(state.policyRevision) or state.policyRevision < 0 then state.policyRevision = 0 end
  if type(state.hash) ~= "string" or state.hash == "" then state.hash = GENESIS_HASH end
  state.records = type(state.records) == "table" and state.records or {}
  state.auditLog = type(state.auditLog) == "table" and state.auditLog or {}
  state.conflicts = type(state.conflicts) == "table" and state.conflicts or {}
  return state
end

local function canonicalHash(record)
  if not (Dibs.Sync and Dibs.Sync.CalculateContentHash) then return nil end
  return Dibs.Sync.CalculateContentHash({
    schema = record.schema, recordClass = record.recordClass, guildKey = record.guildKey,
    policyRevision = record.policyRevision, parentRevision = record.parentRevision,
    parentHash = record.parentHash, authorNameRealm = record.authorNameRealm,
    authorMemberKey = record.authorMemberKey, authorSnapshot = record.authorSnapshot,
    timestamp = record.timestamp, audit = record.audit, values = record.values,
  })
end

local function normalizedValues(values)
  if type(values) ~= "table" then return nil, "INVALID_POLICY_VALUES" end
  local result = {}
  for key, value in pairs(values) do
    if key == "allowPublicPreDibs" then
      if type(value) ~= "boolean" then return nil, "INVALID_POLICY_VALUE" end
      result.allowPublicPreDibs = value
    elseif key == "preDibModes" then
      if type(value) ~= "table" then return nil, "INVALID_POLICY_VALUE" end
      local modes = {}
      for seasonId, mode in pairs(value) do
        if (type(seasonId) ~= "string" and type(seasonId) ~= "number") or not VALID_MODES[tostring(mode)] then return nil, "INVALID_PREDIB_MODE" end
        modes[tostring(seasonId)] = tostring(mode)
      end
      result.preDibModes = modes
    else
      return nil, "POLICY_FIELD_FORBIDDEN"
    end
  end
  return result
end

local function mergeValues(current, patch)
  local result = copy(current or {})
  for key, value in pairs(patch or {}) do result[key] = copy(value) end
  return normalizedValues(result)
end

local function currentGovernance()
  if not (Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetCurrentRecord) then return nil, "GOVERNANCE_UNAVAILABLE" end
  local state, record = Dibs.Governance.GetState(), Dibs.Governance.GetCurrentRecord()
  if state.status ~= "GOVERNANCE_ADOPTED" or not record or record.contentHash ~= state.hash then return nil, "POLICY_UNINITIALIZED" end
  return record
end

local function currentMember(actor)
  if not (Dibs.Identity and Dibs.Identity.CreateSnapshot) then return nil, "IDENTITY_UNAVAILABLE" end
  return Dibs.Identity.CreateSnapshot(actor)
end

local function isCurrentGM(snapshot)
  if not (Dibs.Identity and Dibs.Identity.IsCurrentGuildMaster) then return false, "IDENTITY_UNAVAILABLE" end
  return Dibs.Identity.IsCurrentGuildMaster(snapshot)
end

local function requireLocalActor(snapshot)
  local localSnapshot, reason = currentMember(Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
  if not localSnapshot then return nil, reason end
  if not snapshot or snapshot.memberKey ~= localSnapshot.memberKey then return nil, "LOCAL_ACTOR_REQUIRED" end
  return snapshot
end

local function writerAuthorized(actor)
  local governance, governanceReason = currentGovernance()
  if not governance then return nil, governanceReason end
  local snapshot, identityReason = currentMember(actor)
  if not snapshot then return nil, identityReason end
  local gm, gmReason = isCurrentGM(snapshot)
  if gm then return snapshot end
  if gmReason == "ROSTER_UNAVAILABLE" then return nil, gmReason end
  local rule = governance.content and governance.content.policyWriterRule
  if type(rule) ~= "table" or rule.kind == "GOVERNANCE_ONLY" then return nil, "POLICY_WRITER_REQUIRED" end
  if rule.kind ~= "CURRENT_ROSTER_RANK" or not integer(tonumber(rule.maxRankIndex)) then return nil, "POLICY_WRITER_RULE_UNSUPPORTED" end
  local member = Dibs.Identity.ResolveRosterMember(snapshot.displayName)
  local maximum = tonumber(rule.maxRankIndex)
  if not member or member.status ~= "RESOLVED" or type(member.rankIndex) ~= "number" or member.rankIndex < 0 or member.rankIndex > maximum then return nil, "POLICY_WRITER_REQUIRED" end
  return snapshot
end

local function createRecord(actor, values, revision, parentRevision, parentHash, action, reason, initial)
  local snapshot, authorityReason
  if initial then
    local governance, governanceReason = currentGovernance()
    if not governance then return nil, governanceReason end
    snapshot, authorityReason = currentMember(actor)
    if not snapshot then return nil, authorityReason end
    local gm, gmReason = isCurrentGM(snapshot)
    if not gm then return nil, gmReason end
  else
    snapshot, authorityReason = writerAuthorized(actor)
    if not snapshot then return nil, authorityReason end
  end
  snapshot, authorityReason = requireLocalActor(snapshot)
  if not snapshot then return nil, authorityReason end
  local allowed, valuesReason = normalizedValues(values)
  if not allowed then return nil, valuesReason end
  local record = {
    schema = SCHEMA, recordClass = "OPERATIONAL_POLICY", guildKey = Dibs.GetGuildKey(),
    policyRevision = revision, parentRevision = parentRevision, parentHash = parentHash,
    authorNameRealm = snapshot.displayName, authorMemberKey = snapshot.memberKey,
    authorSnapshot = copy(snapshot), timestamp = Dibs.GetTimestamp and Dibs.GetTimestamp() or time(),
    audit = { action = action, reason = reason }, values = allowed,
  }
  record.contentHash = canonicalHash(record)
  if not record.contentHash then return nil, "CANONICAL_HASH_UNAVAILABLE" end
  return record
end

local function validateShape(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA or record.recordClass ~= "OPERATIONAL_POLICY" then return false, "INVALID_POLICY_RECORD" end
  if record.guildKey ~= Dibs.GetGuildKey() then return false, "GUILD_SCOPE_MISMATCH" end
  if not integer(record.policyRevision) or record.policyRevision < 1 or not integer(record.parentRevision) or type(record.parentHash) ~= "string" then return false, "INVALID_POLICY_PARENT" end
  if type(record.authorNameRealm) ~= "string" or type(record.authorMemberKey) ~= "string" or type(record.authorSnapshot) ~= "table" or record.authorSnapshot.memberKey ~= record.authorMemberKey then return false, "INVALID_AUTHOR_SNAPSHOT" end
  if type(record.timestamp) ~= "number" or type(record.audit) ~= "table" then return false, "INVALID_POLICY_METADATA" end
  local values, reason = normalizedValues(record.values)
  if not values then return false, reason end
  if not (Dibs.Sync and Dibs.Sync.CalculateContentHash) or Dibs.Sync.CalculateContentHash(values) ~= Dibs.Sync.CalculateContentHash(record.values) then return false, "UNSUPPORTED_POLICY_FIELD" end
  if canonicalHash(record) ~= record.contentHash then return false, "POLICY_HASH_MISMATCH" end
  return true
end

function Policy.CalculateContentHash(record) return canonicalHash(record or {}) end
function Policy.GetState() return copy(ensureState()) end
function Policy.GetCurrentRecord()
  local state = ensureState(); return copy(state.records[tostring(state.policyRevision)])
end
function Policy.GetRecord(revision)
  return copy(ensureState().records[tostring(revision)])
end
function Policy.IsAdopted() return ensureState().status == "POLICY_ADOPTED" end
function Policy.GetValues()
  local record = Policy.GetCurrentRecord(); return record and copy(record.values) or nil
end
function Policy.GetPreDibMode(seasonId)
  local values = Policy.GetValues(); return values and values.preDibModes and values.preDibModes[tostring(seasonId)] or nil
end
function Policy.GetPublicPreDibsEnabled()
  local values = Policy.GetValues(); return values and values.allowPublicPreDibs
end
function Policy.CanWrite(actor)
  local snapshot, reason = writerAuthorized(actor); return snapshot ~= nil, reason
end

function Policy.CreateInitialRecord(actor, values, reason)
  local state = ensureState()
  if state.status ~= "POLICY_UNINITIALIZED" or state.policyRevision ~= 0 then return nil, "OPERATIONAL_POLICY_ALREADY_ADOPTED" end
  return createRecord(actor, values, 1, 0, GENESIS_HASH, "INITIAL_ADOPTION", reason, true)
end
function Policy.CreateChangeRecord(actor, patch, reason)
  local state = ensureState()
  if state.status ~= "POLICY_ADOPTED" then return nil, "POLICY_UNINITIALIZED" end
  local current = state.records[tostring(state.policyRevision)]
  local values, mergeReason = mergeValues(current and current.values, patch)
  if not values then return nil, mergeReason end
  return createRecord(actor, values, state.policyRevision + 1, state.policyRevision, state.hash, "POLICY_CHANGE", reason, false)
end

function Policy.ApplyRecord(record, sender)
  local valid, validationReason = validateShape(record)
  if not valid then return false, validationReason end
  local state = ensureState()
  local snapshot, authorityReason
  if state.status == "POLICY_UNINITIALIZED" and record.policyRevision == 1 then
    local governance, governanceReason = currentGovernance()
    if not governance then return false, governanceReason end
    snapshot, authorityReason = currentMember(sender)
    if snapshot then
      local gm, gmReason = isCurrentGM(snapshot)
      if not gm then snapshot, authorityReason = nil, gmReason end
    end
  else
    snapshot, authorityReason = writerAuthorized(sender)
  end
  if not snapshot then return false, authorityReason end
  if snapshot.memberKey ~= record.authorMemberKey then return false, "AUTHOR_SENDER_MISMATCH" end
  if record.policyRevision == state.policyRevision then
    if record.contentHash == state.hash then return true, "IDEMPOTENT_REPLAY", Policy.GetCurrentRecord() end
    table.insert(state.conflicts, { revision = record.policyRevision, existingHash = state.hash, conflictingHash = record.contentHash, receivedFrom = snapshot.memberKey, receivedAt = Dibs.GetTimestamp and Dibs.GetTimestamp() or time() })
    return false, "POLICY_CONFLICT"
  end
  if record.policyRevision < state.policyRevision then return false, "STALE_POLICY" end
  if record.policyRevision ~= state.policyRevision + 1 or record.parentRevision ~= state.policyRevision or record.parentHash ~= state.hash then return false, "POLICY_PARENT_MISSING" end
  if state.status == "POLICY_UNINITIALIZED" and (record.policyRevision ~= 1 or record.parentRevision ~= 0 or record.parentHash ~= GENESIS_HASH) then return false, "POLICY_PARENT_MISSING" end
  state.status, state.policyRevision, state.hash = "POLICY_ADOPTED", record.policyRevision, record.contentHash
  state.records[tostring(record.policyRevision)] = copy(record)
  table.insert(state.auditLog, { action = record.audit.action, revision = record.policyRevision, hash = record.contentHash, author = copy(record.authorSnapshot), timestamp = record.timestamp })
  return true, "ADOPTED", copy(record)
end

function Policy.AdoptInitial(actor, values, reason)
  local record, recordReason = Policy.CreateInitialRecord(actor, values, reason)
  if not record then return false, recordReason end
  local ok, applyReason, applied = Policy.ApplyRecord(record, actor)
  if ok and Dibs.Sync and Dibs.Sync.AnnounceOperationalPolicy then Dibs.Sync.AnnounceOperationalPolicy() end
  return ok, applyReason, applied
end
function Policy.Change(actor, patch, reason)
  local record, recordReason = Policy.CreateChangeRecord(actor, patch, reason)
  if not record then return false, recordReason end
  local ok, applyReason, applied = Policy.ApplyRecord(record, actor)
  if ok and Dibs.Sync and Dibs.Sync.AnnounceOperationalPolicy then Dibs.Sync.AnnounceOperationalPolicy() end
  return ok, applyReason, applied
end
function Policy.SetPreDibMode(seasonId, mode, actor)
  if (type(seasonId) ~= "string" and type(seasonId) ~= "number") or not VALID_MODES[tostring(mode)] then return nil, "INVALID_PREDIB_MODE" end
  local current = Policy.GetValues() or {}; local modes = copy(current.preDibModes or {}); modes[tostring(seasonId)] = tostring(mode)
  return Policy.Change(actor, { preDibModes = modes }, "PRE_DIB_MODE")
end
function Policy.SetPublicPreDibsEnabled(enabled, actor)
  if type(enabled) ~= "boolean" then return nil, "INVALID_POLICY_VALUE" end
  return Policy.Change(actor, { allowPublicPreDibs = enabled }, "PUBLIC_PREDIB_AVAILABILITY")
end

return Policy
