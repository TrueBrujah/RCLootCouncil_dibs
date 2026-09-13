--[[
Module: Dibs.Governance
Layer: Governance bootstrap
Purpose: Store explicit GM-only governance records before operational policy or
distributed-ledger behavior exists.
Responsibilities: POLICY_UNINITIALIZED state, GM adoption, parent/hash checks,
idempotency, and auditable conflicts.
Non-responsibilities: Operational policy, distributed award commits, ledger
sequencing, and RCLootCouncil integration.
Dependencies: Dibs.Identity current-roster authority boundary and Dibs.GetDB.
SavedVariables: db.governance (additive; schema 1).
]]

local Dibs = _G.Dibs
Dibs.Governance = Dibs.Governance or {}
local Governance = Dibs.Governance

local SCHEMA = 1
local GENESIS_HASH = "GENESIS"
local AUTHORITY_SCHEMA = 1
local MAX_AUTHORITY_AUDIT, MAX_PROPOSALS, MAX_ORPHANS = 100, 100, 100

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

local function authorityHash(kind, value)
  local text, total = canonicalText({ kind = kind, value = value }), 0
  for index = 1, #text do total = (total * 131 + text:byte(index)) % 2147483647 end
  return string.format("A5-%08x", total)
end

local function trim(value)
  if type(value) ~= "string" then return nil end
  value = value:match("^%s*(.-)%s*$")
  return value ~= "" and value or nil
end

local function boundedInsert(list, value, maximum)
  table.insert(list, value)
  while #list > maximum do table.remove(list, 1) end
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
    authority = { schema = AUTHORITY_SCHEMA, state = "LEGACY_LOCAL", proposals = {}, orphanedEvidence = {}, auditLog = {} },
  }
end

local function legacyAuthority()
  return { schema = AUTHORITY_SCHEMA, state = "LEGACY_LOCAL", proposals = {}, orphanedEvidence = {}, auditLog = {} }
end

local function authorityState(state)
  local authority = state.authority
  if type(authority) ~= "table" then authority = legacyAuthority(); state.authority = authority end
  if authority.schema ~= AUTHORITY_SCHEMA then authority = legacyAuthority(); state.authority = authority end
  if authority.state ~= "LEGACY_LOCAL" and authority.state ~= "ACTIVE" and authority.state ~= "HANDOFF_CLOSING"
    and authority.state ~= "COORDINATOR_UNAVAILABLE" and authority.state ~= "RECOVERY_PENDING" then
    authority = legacyAuthority(); state.authority = authority
  end
  if type(authority.proposals) ~= "table" then authority.proposals = {} end
  if type(authority.orphanedEvidence) ~= "table" then authority.orphanedEvidence = {} end
  if type(authority.auditLog) ~= "table" then authority.auditLog = {} end
  return authority
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
  authorityState(state)
  return state
end

local function isInteger(value)
  return type(value) == "number" and value == math.floor(value)
end

local function snapshot(value)
  if not Dibs.Identity or type(Dibs.Identity.CreateSnapshot) ~= "function" then return nil, "IDENTITY_UNAVAILABLE" end
  local result, reason = Dibs.Identity.CreateSnapshot(value)
  if not result then return nil, reason end
  return { memberKey = result.memberKey, displayName = result.displayName, guidWitness = result.guidWitness }
end

local function closureProjection(closure)
  return { schema = closure.schema, guildKey = closure.guildKey, previousEpoch = closure.previousEpoch,
    coordinator = closure.coordinator, finalSeq = closure.finalSeq, rootHash = closure.rootHash, closedAt = closure.closedAt }
end

local function validClosure(closure)
  if type(closure) ~= "table" or closure.schema ~= AUTHORITY_SCHEMA or closure.guildKey ~= Dibs.GetGuildKey()
    or not isInteger(closure.previousEpoch) or closure.previousEpoch < 1 or not isInteger(closure.finalSeq) or closure.finalSeq < 0
    or type(closure.coordinator) ~= "table" or type(closure.coordinator.memberKey) ~= "string"
    or not trim(closure.rootHash) or type(closure.closedAt) ~= "number" then return nil, "INVALID_PREDECESSOR_CLOSURE" end
  if closure.closureHash ~= authorityHash("CLOSURE", closureProjection(closure)) then return nil, "CLOSURE_HASH_MISMATCH" end
  return true
end

local function approvedBaseline(hash)
  local baseline = Dibs.LegacyBaseline and Dibs.LegacyBaseline.GetBaseline and Dibs.LegacyBaseline.GetBaseline()
  return baseline and baseline.legacyBaselineHash == hash
end

local function authorityContent(value, current)
  if value == nil then return nil end
  if type(value) ~= "table" or value.schema ~= AUTHORITY_SCHEMA or value.state ~= "ACTIVE" then return nil, "INVALID_AUTHORITY_STATE" end
  if not isInteger(value.ledgerEpoch) or value.ledgerEpoch < 1 or type(value.coordinator) ~= "table"
    or type(value.coordinator.memberKey) ~= "string" or type(value.coordinator.displayName) ~= "string"
    or type(value.transition) ~= "table" or type(value.transition.kind) ~= "string" then return nil, "INVALID_AUTHORITY_STATE" end
  local coordinator, coordinatorReason = snapshot(value.coordinator.displayName)
  if not coordinator or coordinator.memberKey ~= value.coordinator.memberKey then return nil, coordinatorReason or "INVALID_COORDINATOR_IDENTITY" end
  local requestedProtocol = value.protocolState or "CUTOVER_PREPARED"
  if requestedProtocol ~= "CUTOVER_PREPARED" and requestedProtocol ~= "V2_ENFORCED" then return nil, "INVALID_PROTOCOL_STATE" end
  local normalized = { schema = AUTHORITY_SCHEMA, state = "ACTIVE", coordinator = coordinator, ledgerEpoch = value.ledgerEpoch,
    transition = copy(value.transition), protocolState = requestedProtocol }
  local kind, prior = normalized.transition.kind, current or legacyAuthority()
  if Dibs.Sync and Dibs.Sync.IsSyncBehind and Dibs.Sync.IsSyncBehind() then return nil, "SYNC_BEHIND" end
  if kind == "INITIAL" then
    if prior.state ~= "LEGACY_LOCAL" or not trim(normalized.transition.baselineHash) or not approvedBaseline(normalized.transition.baselineHash) then return nil, "AUTHORITY_BASELINE_REQUIRED" end
  elseif kind == "NORMAL_HANDOFF" then
    local closure, reason = normalized.transition.parentClosure, nil
    if prior.state ~= "HANDOFF_CLOSING" then return nil, "HANDOFF_CLOSURE_REQUIRED" end
    if not closure then return nil, "HANDOFF_CLOSURE_REQUIRED" end
    local valid; valid, reason = validClosure(closure); if not valid then return nil, reason end
    if not prior.predecessorClosure or closure.closureHash ~= prior.predecessorClosure.closureHash then return nil, "CLOSURE_CONFLICT" end
    if closure.previousEpoch ~= prior.ledgerEpoch or closure.coordinator.memberKey ~= prior.coordinator.memberKey
      or normalized.ledgerEpoch ~= prior.ledgerEpoch + 1 or normalized.transition.parentClosureHash ~= closure.closureHash then return nil, "HANDOFF_PARENT_MISMATCH" end
    if requestedProtocol == "V2_ENFORCED" and prior.protocolState ~= "V2_ENFORCED" then return nil, "PROTOCOL_CUTOVER_REQUIRED" end
  elseif kind == "FORCED_RECOVERY" then
    if prior.state ~= "RECOVERY_PENDING" or normalized.ledgerEpoch ~= (prior.ledgerEpoch or 0) + 1 then return nil, "RECOVERY_PENDING_REQUIRED" end
    if not trim(normalized.transition.baselineHash) or not approvedBaseline(normalized.transition.baselineHash)
      or type(normalized.transition.recoveryAudit) ~= "table" or not trim(normalized.transition.recoveryAudit.reason) then return nil, "AUTHORITY_BASELINE_REQUIRED" end
  else
    return nil, "INVALID_AUTHORITY_TRANSITION"
  end
  normalized.transitionHash = authorityHash("TRANSITION", normalized)
  if value.transitionHash and value.transitionHash ~= normalized.transitionHash then return nil, "TRANSITION_HASH_MISMATCH" end
  return normalized
end

local function governanceContent(proposal, currentAuthority)
  proposal = proposal or {}
  if type(proposal) ~= "table" then return nil, "INVALID_GOVERNANCE_CONTENT" end
  if proposal.coordinator ~= nil or proposal.ledgerEpoch ~= nil or proposal.baseline ~= nil or proposal.protocolState == "V2_ENFORCED" then return nil, "FUTURE_GOVERNANCE_INACTIVE" end
  local futureInput = proposal.future or {}
  if type(futureInput) ~= "table" then return nil, "INVALID_FUTURE_GOVERNANCE" end
  if futureInput.cutover ~= nil then
    local cutover = futureInput.cutover
    if type(cutover) ~= "table" or cutover.schema ~= AUTHORITY_SCHEMA or cutover.state ~= "V2_ENFORCED" then return nil, "INVALID_CUTOVER" end
    local current = currentAuthority or legacyAuthority()
    local baselineHash = current.transition and current.transition.baselineHash
    if current.state ~= "ACTIVE" or not baselineHash or not approvedBaseline(baselineHash) then return nil, "AUTHORITY_BASELINE_REQUIRED" end
    if Dibs.Sync and Dibs.Sync.IsSyncBehind and Dibs.Sync.IsSyncBehind() then return nil, "SYNC_BEHIND" end
    local writers = cutover.writers or { current.coordinator and current.coordinator.displayName }
    local coordinatorListed = false
    for _, writer in ipairs(writers or {}) do
      local writerSnapshot = snapshot(writer)
      if writerSnapshot and current.coordinator and writerSnapshot.memberKey == current.coordinator.memberKey then coordinatorListed = true end
    end
    if not coordinatorListed then return nil, "WRITER_COMPATIBILITY_REQUIRED" end
    if Dibs.Sync and Dibs.Sync.CanEnforceV2 then
      local compatible, compatibleReason = Dibs.Sync.CanEnforceV2(writers)
      if not compatible then return nil, compatibleReason or "WRITER_COMPATIBILITY_REQUIRED" end
    end
    local authority = copy(current)
    authority.proposals, authority.orphanedEvidence, authority.auditLog = nil, nil, nil
    authority.protocolState = "V2_ENFORCED"
    return {
      officerAuthorityRule = copy(proposal.officerAuthorityRule or { kind = "CURRENT_ROSTER_RANK", maxRankIndex = 1 }),
      policyWriterRule = copy(proposal.policyWriterRule or { kind = "GOVERNANCE_ONLY" }),
      future = { coordinator = copy(authority.coordinator), ledgerEpoch = authority.ledgerEpoch, protocolState = "V2_ENFORCED",
        baseline = baselineHash, authority = authority, cutover = { schema = AUTHORITY_SCHEMA, state = "V2_ENFORCED", baselineHash = baselineHash, writers = copy(writers) } },
    }
  end
  if (futureInput.coordinator ~= nil or futureInput.ledgerEpoch ~= nil or futureInput.baseline ~= nil) and futureInput.authority == nil then return nil, "FUTURE_GOVERNANCE_INACTIVE" end
  if futureInput.protocolState == "V2_ENFORCED" and futureInput.authority == nil then return nil, "PROTOCOL_CUTOVER_NOT_AVAILABLE" end
  local authority, authorityReason = authorityContent(futureInput.authority, currentAuthority)
  if futureInput.authority ~= nil and not authority then return nil, authorityReason end
  local future = authority and { coordinator = copy(authority.coordinator), ledgerEpoch = authority.ledgerEpoch,
    protocolState = authority.protocolState, baseline = authority.transition.baselineHash, authority = authority }
    or { coordinator = nil, ledgerEpoch = nil, protocolState = "LEGACY_LOCAL", baseline = nil }
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

local function createRecord(actor, proposal, revision, parentRevision, parentHash, currentAuthority)
  local snapshot, authorityReason = currentGMSnapshot(actor)
  if not snapshot then return nil, authorityReason end
  local content, contentReason = governanceContent(proposal, currentAuthority)
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

local function validateRecordShape(record, currentAuthority)
  if type(record) ~= "table" or record.schema ~= SCHEMA or record.recordClass ~= "GOVERNANCE" then return false, "INVALID_GOVERNANCE_RECORD" end
  if record.guildKey ~= Dibs.GetGuildKey() then return false, "GUILD_SCOPE_MISMATCH" end
  if not isInteger(record.governanceRevision) or record.governanceRevision < 1 then return false, "INVALID_GOVERNANCE_REVISION" end
  if not isInteger(record.parentRevision) or type(record.parentHash) ~= "string" or type(record.authorNameRealm) ~= "string" or type(record.authorMemberKey) ~= "string" then return false, "INVALID_GOVERNANCE_PARENT" end
  if type(record.authorSnapshot) ~= "table" or record.authorSnapshot.memberKey ~= record.authorMemberKey then return false, "INVALID_AUTHOR_SNAPSHOT" end
  if type(record.timestamp) ~= "number" or type(record.audit) ~= "table" or type(record.content) ~= "table" then return false, "INVALID_GOVERNANCE_METADATA" end
  local content, reason = governanceContent(record.content, currentAuthority)
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
  return createRecord(actor, proposal, 1, 0, GENESIS_HASH, authorityState(state))
end

function Governance.CreateChangeRecord(actor, proposal)
  local state = ensureState()
  if state.status ~= "GOVERNANCE_ADOPTED" then return nil, "POLICY_UNINITIALIZED" end
  return createRecord(actor, proposal, state.revision + 1, state.revision, state.hash, authorityState(state))
end

function Governance.ApplyRecord(record, sender)
  local state = ensureState()
  local valid, validationReason = validateRecordShape(record, authorityState(state))
  if not valid then return false, validationReason end
  local senderSnapshot, authorityReason = currentGMSnapshot(sender)
  if not senderSnapshot then return false, authorityReason end
  if senderSnapshot.memberKey ~= record.authorMemberKey then return false, "AUTHOR_SENDER_MISMATCH" end

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
  if state.future.protocolState == "V2_ENFORCED" and Dibs.Sync and Dibs.Sync.SetProtocolState then
    Dibs.Sync.SetProtocolState("V2_ENFORCED", true)
  end
  if record.content.future.authority then
    local nextAuthority = copy(record.content.future.authority)
    local previous = authorityState(state)
    nextAuthority.proposals, nextAuthority.orphanedEvidence, nextAuthority.auditLog = previous.proposals, previous.orphanedEvidence, previous.auditLog
    state.authority = nextAuthority
    boundedInsert(state.authority.auditLog, { action = nextAuthority.transition.kind, transitionHash = nextAuthority.transitionHash,
      governanceRevision = record.governanceRevision, author = copy(record.authorSnapshot), timestamp = record.timestamp }, MAX_AUTHORITY_AUDIT)
  end
  table.insert(state.auditLog, {
    action = record.audit.action,
    revision = record.governanceRevision,
    hash = record.contentHash,
    author = copy(record.authorSnapshot),
    timestamp = record.timestamp,
  })
  return true, "ADOPTED", copy(record)
end

function Governance.GetAuthorityState()
  return copy(authorityState(ensureState()))
end

function Governance.IsV2Enforced()
  return ensureState().future and ensureState().future.protocolState == "V2_ENFORCED"
end

function Governance.EnableV2(actor, writers)
  return Governance.Change(actor, { reason = "B06_V2_ENFORCED", future = { cutover = { schema = AUTHORITY_SCHEMA, state = "V2_ENFORCED", writers = copy(writers) } } })
end

function Governance.GetDibUseGate()
  local authority = authorityState(ensureState())
  if authority.state == "COORDINATOR_UNAVAILABLE" or authority.state == "RECOVERY_PENDING" or authority.state == "HANDOFF_CLOSING" then
    return false, authority.state
  end
  return true, authority.state
end

function Governance.BeginHandoff(actor, details)
  local state, authority = ensureState(), authorityState(ensureState())
  if authority.state ~= "ACTIVE" then return nil, "AUTHORITY_ACTIVE_REQUIRED" end
  local actorSnapshot, reason = snapshot(actor)
  if not actorSnapshot then return nil, reason end
  if actorSnapshot.memberKey ~= authority.coordinator.memberKey then return nil, "CURRENT_COORDINATOR_REQUIRED" end
  details = details or {}
  local closure = { schema = AUTHORITY_SCHEMA, guildKey = Dibs.GetGuildKey(), previousEpoch = authority.ledgerEpoch,
    coordinator = copy(authority.coordinator), finalSeq = tonumber(details.finalSeq), rootHash = trim(details.rootHash),
    closedAt = tonumber(details.closedAt) or (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time() }
  if not isInteger(closure.finalSeq) or closure.finalSeq < 0 or not closure.rootHash then return nil, "INVALID_PREDECESSOR_CLOSURE" end
  closure.closureHash = authorityHash("CLOSURE", closureProjection(closure))
  authority.state, authority.predecessorClosure = "HANDOFF_CLOSING", closure
  boundedInsert(authority.auditLog, { action = "HANDOFF_CLOSING", actor = actorSnapshot, closureHash = closure.closureHash, timestamp = closure.closedAt }, MAX_AUTHORITY_AUDIT)
  state.authority = authority
  return copy(closure), "HANDOFF_CLOSING"
end

function Governance.EnterRecoveryPending(actor, reason)
  local authority = authorityState(ensureState())
  if authority.state ~= "ACTIVE" and authority.state ~= "HANDOFF_CLOSING" and authority.state ~= "COORDINATOR_UNAVAILABLE" then return nil, "AUTHORITY_ACTIVE_REQUIRED" end
  local gm, gmReason = currentGMSnapshot(actor); if not gm then return nil, gmReason end
  authority.state = "RECOVERY_PENDING"
  authority.recoveryAudit = { requestedBy = copy(gm), reason = trim(reason) or "predecessor closure unavailable", requestedAt = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time() }
  boundedInsert(authority.auditLog, { action = "RECOVERY_PENDING", actor = copy(gm), timestamp = authority.recoveryAudit.requestedAt }, MAX_AUTHORITY_AUDIT)
  return copy(authority), "RECOVERY_PENDING"
end

function Governance.MarkCoordinatorUnavailable(actor, reason)
  local authority = authorityState(ensureState())
  if authority.state ~= "ACTIVE" then return nil, "AUTHORITY_ACTIVE_REQUIRED" end
  local gm, gmReason = currentGMSnapshot(actor); if not gm then return nil, gmReason end
  authority.state = "COORDINATOR_UNAVAILABLE"
  authority.unavailableAudit = { actor = copy(gm), reason = trim(reason) or "coordinator unavailable", timestamp = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time() }
  boundedInsert(authority.auditLog, { action = "COORDINATOR_UNAVAILABLE", actor = copy(gm), timestamp = authority.unavailableAudit.timestamp }, MAX_AUTHORITY_AUDIT)
  return copy(authority), "COORDINATOR_UNAVAILABLE"
end

function Governance.RecordAwardProposal(actor, details)
  local authority = authorityState(ensureState()); details = details or {}
  local target, targetReason = snapshot(details.playerName or details.memberKey or details.playerKey)
  if not target then return nil, targetReason end
  local actorSnapshot, actorReason = snapshot(actor); if not actorSnapshot then return nil, actorReason end
  local projection = { guildKey = Dibs.GetGuildKey(), player = target.memberKey, itemID = tonumber(details.itemID), itemLink = trim(details.itemLink),
    awardRef = trim(details.awardRef), evidenceId = trim(details.evidenceId), source = trim(details.source), context = trim(details.reason) }
  local proposalId = trim(details.proposalId) or ("AP5-" .. authorityHash("PROPOSAL", projection))
  local existing = authority.proposals[proposalId]
  if existing then return copy(existing), "IDEMPOTENT_PROPOSAL" end
  local proposal = { schema = AUTHORITY_SCHEMA, recordClass = "AWARD_PROPOSAL", proposalId = proposalId, status = "PENDING_RECONCILIATION",
    guildKey = Dibs.GetGuildKey(), playerSnapshot = target, itemID = projection.itemID, itemLink = projection.itemLink, awardRef = projection.awardRef,
    evidenceId = projection.evidenceId, source = projection.source, context = projection.context, actorSnapshot = actorSnapshot,
    createdAt = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time(), authorityState = authority.state }
  proposal.contentHash = authorityHash("PROPOSAL", proposal)
  if (function() local n=0; for _ in pairs(authority.proposals) do n=n+1 end; return n end)() >= MAX_PROPOSALS then return nil, "PROPOSAL_LIMIT_EXCEEDED" end
  authority.proposals[proposalId] = proposal
  boundedInsert(authority.auditLog, { action = "AWARD_PROPOSAL", proposalId = proposalId, timestamp = proposal.createdAt }, MAX_AUTHORITY_AUDIT)
  return copy(proposal), "PENDING_RECONCILIATION"
end

function Governance.GetAwardProposals()
  local values = {}; for _, proposal in pairs(authorityState(ensureState()).proposals) do values[#values + 1] = copy(proposal) end
  table.sort(values, function(a, b) return a.proposalId < b.proposalId end); return values
end

function Governance.GetOrphanedEvidence()
  local values = {}; for _, evidence in pairs(authorityState(ensureState()).orphanedEvidence) do values[#values + 1] = copy(evidence) end
  table.sort(values, function(a, b) return a.evidenceId < b.evidenceId end); return values
end

function Governance.ClassifyLateEvidence(event)
  local authority = authorityState(ensureState()); event = event or {}
  local identity = trim(event.evidenceId) or trim(event.eventId) or trim(event.transactionId)
  if not identity then return false, "EVIDENCE_ID_REQUIRED" end
  local baselineHash = authority.transition and authority.transition.baselineHash
  local baseline = Dibs.LegacyBaseline and Dibs.LegacyBaseline.GetBaseline and Dibs.LegacyBaseline.GetBaseline()
  if authority.state == "ACTIVE" and authority.transition and authority.transition.kind == "FORCED_RECOVERY"
    and baseline and baseline.legacyBaselineHash == baselineHash then
    for _, evidenceId in ipairs(baseline.includedEvidenceIds or {}) do if evidenceId == identity then return true, "KNOWN_BASELINE_EVIDENCE" end end
    local existing = authority.orphanedEvidence[identity]; if existing then return false, "ORPHANED_EVIDENCE" end
    if (function() local n=0; for _ in pairs(authority.orphanedEvidence) do n=n+1 end; return n end)() >= MAX_ORPHANS then return false, "ORPHAN_LIMIT_EXCEEDED" end
    authority.orphanedEvidence[identity] = { schema = AUTHORITY_SCHEMA, evidenceId = identity, status = "ORPHANED_EVIDENCE", event = copy(event), receivedAt = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time() }
    return false, "ORPHANED_EVIDENCE"
  end
  if authority.predecessorClosure and tonumber(event.epoch) == authority.predecessorClosure.previousEpoch and tonumber(event.seq) > authority.predecessorClosure.finalSeq then
    return false, "EVENT_BEYOND_CLOSED_FINAL_SEQ"
  end
  return false, "LATE_EVIDENCE_UNVERIFIED"
end

function Governance.ApplyOrphanedEvidence(event, sender)
  local senderSnapshot, senderReason = snapshot(sender); if not senderSnapshot then return false, senderReason end
  local accepted, reason = Governance.ClassifyLateEvidence(event)
  if reason == "ORPHANED_EVIDENCE" then
    local identity = trim(event and event.evidenceId) or trim(event and event.eventId) or trim(event and event.transactionId)
    local stored = identity and authorityState(ensureState()).orphanedEvidence[identity]
    if stored then stored.receivedFrom = copy(senderSnapshot) end
  end
  return accepted, reason
end

function Governance.BuildAuthoritySignal()
  local authority = authorityState(ensureState())
  local signal = { schema = AUTHORITY_SCHEMA, guildKey = Dibs.GetGuildKey(), state = authority.state,
    coordinator = copy(authority.coordinator), ledgerEpoch = authority.ledgerEpoch,
    predecessorClosure = copy(authority.predecessorClosure), recoveryAudit = copy(authority.recoveryAudit),
    transitionHash = authority.transitionHash }
  signal.contentHash = authorityHash("SIGNAL", signal)
  return signal
end

function Governance.ApplyAuthoritySignal(signal, sender)
  if type(signal) ~= "table" or signal.schema ~= AUTHORITY_SCHEMA or signal.guildKey ~= Dibs.GetGuildKey()
    or type(signal.contentHash) ~= "string" then return false, "INVALID_AUTHORITY_SIGNAL" end
  local expected = copy(signal); expected.contentHash = nil
  if signal.contentHash ~= authorityHash("SIGNAL", expected) then return false, "AUTHORITY_SIGNAL_HASH_MISMATCH" end
  local senderSnapshot, senderReason = snapshot(sender); if not senderSnapshot then return false, senderReason end
  local authority = authorityState(ensureState())
  if authority.state ~= "LEGACY_LOCAL" and (tonumber(signal.ledgerEpoch) ~= tonumber(authority.ledgerEpoch)
    or not authority.coordinator or type(signal.coordinator) ~= "table" or signal.coordinator.memberKey ~= authority.coordinator.memberKey) then
    return false, "STALE_AUTHORITY_SIGNAL"
  end
  if signal.state == "HANDOFF_CLOSING" then
    local valid, reason = validClosure(signal.predecessorClosure); if not valid then return false, reason end
    if authority.state == "HANDOFF_CLOSING" and authority.predecessorClosure and authority.predecessorClosure.closureHash == signal.predecessorClosure.closureHash then
      return true, "IDEMPOTENT_CLOSURE"
    end
    if authority.state ~= "ACTIVE" or not authority.coordinator or senderSnapshot.memberKey ~= authority.coordinator.memberKey
      or signal.predecessorClosure.coordinator.memberKey ~= authority.coordinator.memberKey then return false, "CURRENT_COORDINATOR_REQUIRED" end
    if authority.predecessorClosure and authority.predecessorClosure.closureHash ~= signal.predecessorClosure.closureHash then return false, "CLOSURE_CONFLICT" end
    authority.state, authority.predecessorClosure = "HANDOFF_CLOSING", copy(signal.predecessorClosure)
    return true, "HANDOFF_CLOSING"
  end
  if signal.state == "COORDINATOR_UNAVAILABLE" or signal.state == "RECOVERY_PENDING" then
    local gm, gmReason = currentGMSnapshot(sender); if not gm then return false, gmReason end
    if authority.state ~= "ACTIVE" and authority.state ~= "HANDOFF_CLOSING" and authority.state ~= "COORDINATOR_UNAVAILABLE" then return false, "AUTHORITY_ACTIVE_REQUIRED" end
    authority.state = signal.state
    authority.recoveryAudit = copy(signal.recoveryAudit)
    return true, signal.state
  end
  return false, "UNSUPPORTED_AUTHORITY_SIGNAL"
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
