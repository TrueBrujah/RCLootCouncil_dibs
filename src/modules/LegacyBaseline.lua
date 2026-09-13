--[[
Module: Dibs.LegacyBaseline
Layer: Legacy reconciliation and recovery staging (B05a)
Purpose: Preserve divergent legacy evidence and create a GM-approved,
deterministic baseline without activating a coordinator or mutating history.
Non-responsibilities: Coordinator transitions, ledger epochs, AWARD_COMMIT,
RCLootCouncil award handling, or revival of legacy Pre-Dibs.
]]

local Dibs = _G.Dibs
Dibs.LegacyBaseline = Dibs.LegacyBaseline or {}
local M = Dibs.LegacyBaseline

local SCHEMA, MAX_EVIDENCE, MAX_SOURCES, MAX_DECISIONS, MAX_AUDIT, MAX_DEPTH = 1, 500, 50, 500, 50, 8
local DECISIONS = { INCLUDE = true, EXCLUDE = true, COMPENSATING_ADJUSTMENT = true, DEFER = true }
local SOURCE_TYPES = { LEDGER_TRANSACTION = true, PREDIB_REQUEST = true, MIGRATION_HISTORY = true, DIBS_RECONCILIATION = true }

local function copy(value) return Dibs.DeepCopy and Dibs.DeepCopy(value) or value end
local function trim(value)
  if type(value) ~= "string" then return nil end
  value = value:match("^%s*(.-)%s*$")
  return value ~= "" and value or nil
end
local function finite(value)
  return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function sortedKeys(value)
  local keys = {}
  for key in pairs(value or {}) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return type(a) .. ":" .. tostring(a) < type(b) .. ":" .. tostring(b) end)
  return keys
end
local function sortedValues(map)
  local values = {}
  for _, key in ipairs(sortedKeys(map)) do values[#values + 1] = copy(map[key]) end
  return values
end
local function count(map)
  local total = 0
  for _ in pairs(map or {}) do total = total + 1 end
  return total
end
local function hash(value)
  return Dibs.Sync and Dibs.Sync.CalculateContentHash and Dibs.Sync.CalculateContentHash(value) or nil
end
local function now() return Dibs.GetTimestamp and Dibs.GetTimestamp() or time() end

local function dataOnly(value, depth, seen)
  local kind = type(value)
  if kind == "nil" or kind == "boolean" or kind == "string" then return true end
  if kind == "number" then return finite(value) end
  if kind ~= "table" or depth > MAX_DEPTH then return false end
  seen = seen or {}
  if seen[value] then return false end
  seen[value] = true
  for key, item in pairs(value) do
    if not dataOnly(key, depth + 1, seen) or not dataOnly(item, depth + 1, seen) then seen[value] = nil; return false end
  end
  seen[value] = nil
  return true
end

local function defaultState()
  return {
    schema = SCHEMA, status = "LEGACY_PREPARED", evidence = {}, sources = {}, findings = {}, decisions = {},
    activeDecisionByEvidence = {}, baseline = nil, recoveries = {}, auditLog = {},
  }
end
local function ensure()
  local db = Dibs.GetDB()
  if type(db.legacyBaseline) ~= "table" then db.legacyBaseline = defaultState() end
  local state = db.legacyBaseline
  if state.schema ~= SCHEMA then state.schema = SCHEMA end
  if state.status ~= "LEGACY_PREPARED" and state.status ~= "BASELINE_APPROVED" then state.status = "LEGACY_PREPARED" end
  for _, key in ipairs({ "evidence", "sources", "findings", "decisions", "activeDecisionByEvidence", "recoveries", "auditLog" }) do
    if type(state[key]) ~= "table" then state[key] = {} end
  end
  if state.baseline ~= nil and type(state.baseline) ~= "table" then state.baseline = nil end
  return state
end

local function localSnapshot(actor, requireGM, requireAssistant)
  if not Dibs.Identity or not Dibs.Identity.CreateSnapshot then return nil, "IDENTITY_UNAVAILABLE" end
  local localIdentity, localReason = Dibs.Identity.CreateSnapshot(Dibs.GetPlayerName())
  if not localIdentity then return nil, localReason end
  local snapshot, reason = Dibs.Identity.CreateSnapshot(actor or Dibs.GetPlayerName())
  if not snapshot then return nil, reason end
  if snapshot.memberKey ~= localIdentity.memberKey then return nil, "LOCAL_ACTOR_REQUIRED" end
  local resolved = Dibs.Identity.ResolveRosterMember(snapshot.displayName)
  if not resolved or resolved.status ~= "RESOLVED" then return nil, resolved and resolved.status or "ROSTER_UNAVAILABLE" end
  if requireGM and resolved.rankIndex ~= 0 then return nil, "CURRENT_GUILD_MASTER_REQUIRED" end
  if requireAssistant and resolved.rankIndex ~= 0 and resolved.role ~= "officer" then return nil, "RECONCILIATION_ASSISTANT_REQUIRED" end
  return snapshot
end

local function governanceReady()
  local state = Dibs.Governance and Dibs.Governance.GetState and Dibs.Governance.GetState() or nil
  return state and state.status == "GOVERNANCE_ADOPTED"
end

local function canonicalIdentity(value)
  local original = trim(value)
  if not original then return { status = "MISSING_IDENTITY", original = nil, memberKey = nil } end
  local memberKey = Dibs.Identity and Dibs.Identity.CanonicalMemberKey and Dibs.Identity.CanonicalMemberKey(original) or nil
  if memberKey then return { status = "NAME_REALM", original = original, memberKey = memberKey } end
  return { status = "UNRESOLVED_LEGACY_IDENTITY", original = original, memberKey = nil }
end

local function sourceDescriptor(source)
  if type(source) ~= "table" then return nil, "INVALID_EVIDENCE_SOURCE" end
  local sourceId, sourceClient, sourceType = trim(source.sourceId), trim(source.sourceClient), trim(source.sourceType)
  if not sourceId or #sourceId > 160 or not sourceClient or #sourceClient > 160 or not SOURCE_TYPES[sourceType] then return nil, "INVALID_EVIDENCE_SOURCE" end
  if source.guildKey ~= nil and source.guildKey ~= Dibs.GetGuildKey() then return nil, "GUILD_SCOPE_MISMATCH" end
  local descriptor = {
    sourceId = sourceId, sourceClient = sourceClient, sourceType = sourceType, guildKey = Dibs.GetGuildKey(),
    sourceVersion = source.sourceVersion, complete = source.complete ~= false, provenance = copy(source.provenance),
  }
  if not dataOnly(descriptor, 0) then return nil, "INVALID_EVIDENCE_PROVENANCE" end
  descriptor.sourceHash = hash(descriptor)
  return descriptor
end

local function extractRecord(entry, fallbackType)
  local record, fallbackId = entry, nil
  if type(entry) == "table" and type(entry.record) == "table" then record, fallbackId = entry.record, entry.originalId end
  if type(record) ~= "table" or not dataOnly(record, 0) then return nil, nil, "INVALID_LEGACY_RECORD" end
  local originalId = trim(record.transactionId) or trim(record.requestId) or trim(record.id) or trim(fallbackId)
  if not originalId or #originalId > 160 then return nil, nil, "MISSING_LEGACY_RECORD_ID" end
  return record, originalId, nil
end

local function normalizeRecord(source, entry, strict)
  local record, originalId, reason = extractRecord(entry, source.sourceType)
  if not record then return nil, reason end
  local originalIdentity = record.memberKey or record.playerName or record.playerKey or record.ownerName
  local identity = canonicalIdentity(originalIdentity)
  local action = trim(record.actionType) or trim(record.type) or trim(record.action) or trim(record.status) or "UNKNOWN"
  local amount = tonumber(record.quantityDelta or record.amount)
  if amount ~= nil and not finite(amount) then return nil, "INVALID_LEGACY_AMOUNT" end
  local timestamp = tonumber(record.timestamp or record.createdAt or record.updatedAt)
  if timestamp ~= nil and not finite(timestamp) then return nil, "INVALID_LEGACY_TIMESTAMP" end
  local sourceRecord = copy(record)
  local sourceRecordHash = hash(sourceRecord)
  if not sourceRecordHash then return nil, "UNHASHABLE_LEGACY_RECORD" end
  local semantic = {
    sourceType = source.sourceType, identity = identity.memberKey or identity.original, action = action, amount = amount,
    seasonId = record.seasonId, awardRef = record.awardRef, evidenceRef = record.evidenceId, itemID = tonumber(record.itemID),
  }
  local normalized = {
    schema = SCHEMA, sourceId = source.sourceId, sourceClient = source.sourceClient, sourceType = source.sourceType,
    sourceVersion = source.sourceVersion, originalId = originalId, identity = identity, action = action, amount = amount,
    seasonId = record.seasonId, timestamp = timestamp, status = record.status, awardRef = record.awardRef,
    evidenceRef = record.evidenceId, itemID = tonumber(record.itemID), sourceRecord = sourceRecord,
    sourceRecordHash = sourceRecordHash,
  }
  normalized.contentHash = hash({ sourceType = normalized.sourceType, originalId = normalized.originalId, identity = normalized.identity,
    action = normalized.action, amount = normalized.amount, seasonId = normalized.seasonId, timestamp = normalized.timestamp,
    status = normalized.status, awardRef = normalized.awardRef, evidenceRef = normalized.evidenceRef, itemID = normalized.itemID,
    sourceRecordHash = normalized.sourceRecordHash })
  normalized.legacyIdHash = hash({ sourceType = normalized.sourceType, originalId = normalized.originalId })
  normalized.awardFingerprint = hash(semantic)
  normalized.evidenceId = "E5-" .. tostring(hash({ sourceId = source.sourceId, sourceClient = source.sourceClient,
    sourceType = source.sourceType, originalId = originalId, sourceRecordHash = sourceRecordHash }))
  if not normalized.contentHash or not normalized.legacyIdHash or not normalized.awardFingerprint then return nil, "UNHASHABLE_LEGACY_RECORD" end
  if strict then
    if identity.status == "MISSING_IDENTITY" then return nil, "MALFORMED_LEGACY_IDENTITY" end
    if source.sourceType == "LEDGER_TRANSACTION" and (action == "UNKNOWN" or amount == nil or amount == 0 or type(record.seasonId) ~= "string" or record.seasonId == "") then
      return nil, "INVALID_RECOVERY_TRANSACTION"
    end
    if source.sourceType == "PREDIB_REQUEST" and (type(record.playerName) ~= "string" or record.playerName == "" or not normalized.itemID or normalized.itemID <= 0
      or type(record.seasonId) ~= "string" or record.seasonId == "" or type(record.status) ~= "string" or tonumber(record.revision) == nil) then
      return nil, "INVALID_RECOVERY_PREDIB"
    end
  end
  if source.sourceType == "PREDIB_REQUEST" and (record.status == "pending" or record.status == "confirmed") then
    normalized.legacyPreDibState = "HISTORICAL_RECONFIRMATION_REQUIRED"
  end
  return normalized
end

local function boundedInsert(list, value, maximum)
  list[#list + 1] = value
  while #list > maximum do table.remove(list, 1) end
end

local function activeDecision(state, evidenceId)
  local id = state.activeDecisionByEvidence[evidenceId]
  return id and state.decisions[id] or nil
end

local function rebuildFindings(state)
  local findings, legacyGroups, awardGroups, sourceKeys = {}, {}, {}, {}
  for evidenceId, evidence in pairs(state.evidence) do
    legacyGroups[evidence.legacyIdHash] = legacyGroups[evidence.legacyIdHash] or {}
    legacyGroups[evidence.legacyIdHash][#legacyGroups[evidence.legacyIdHash] + 1] = evidenceId
    if evidence.sourceType == "LEDGER_TRANSACTION" and evidence.amount ~= nil then
      awardGroups[evidence.awardFingerprint] = awardGroups[evidence.awardFingerprint] or {}
      awardGroups[evidence.awardFingerprint][#awardGroups[evidence.awardFingerprint] + 1] = evidenceId
    end
    local sourceKey = evidence.legacyIdHash .. "|" .. evidence.contentHash
    sourceKeys[sourceKey] = sourceKeys[sourceKey] or {}
    sourceKeys[sourceKey][evidence.sourceId] = true
  end
  local function add(kind, evidenceIds, details)
    table.sort(evidenceIds)
    local findingId = "F5-" .. tostring(hash({ kind = kind, evidenceIds = evidenceIds, details = details }))
    local resolved = true
    for _, evidenceId in ipairs(evidenceIds) do if not activeDecision(state, evidenceId) then resolved = false; break end end
    findings[findingId] = { findingId = findingId, kind = kind, evidenceIds = evidenceIds, details = details, status = resolved and "DECIDED" or "OPEN" }
  end
  for _, evidenceId in ipairs(sortedKeys(state.evidence)) do
    local evidence = state.evidence[evidenceId]
    if evidence.identity.status ~= "NAME_REALM" then add("UNRESOLVED_IDENTITY", { evidenceId }, { identity = evidence.identity.original }) end
  end
  for legacyIdHash, evidenceIds in pairs(legacyGroups) do
    local contents, identities = {}, {}
    for _, evidenceId in ipairs(evidenceIds) do
      local evidence = state.evidence[evidenceId]
      contents[evidence.contentHash] = true
      identities[evidence.identity.memberKey or ("raw:" .. tostring(evidence.identity.original))] = true
    end
    if #evidenceIds > 1 and count(contents) == 1 then add("EXACT_DUPLICATE_EVIDENCE", copy(evidenceIds), { legacyIdHash = legacyIdHash }) end
    if count(contents) > 1 then add("LEGACY_ID_CONTENT_CONFLICT", copy(evidenceIds), { legacyIdHash = legacyIdHash }) end
    if count(identities) > 1 then add("LEGACY_IDENTITY_CONFLICT", copy(evidenceIds), { legacyIdHash = legacyIdHash }) end
  end
  for fingerprint, evidenceIds in pairs(awardGroups) do
    local legacyIds = {}
    for _, evidenceId in ipairs(evidenceIds) do legacyIds[state.evidence[evidenceId].legacyIdHash] = true end
    if count(legacyIds) > 1 then add("LIKELY_DUPLICATE_AWARD", copy(evidenceIds), { awardFingerprint = fingerprint }) end
  end
  for sourceKey, sources in pairs(sourceKeys) do
    if count(state.sources) > 1 and count(sources) < count(state.sources) then
      local ids = {}
      for evidenceId, evidence in pairs(state.evidence) do if evidence.legacyIdHash .. "|" .. evidence.contentHash == sourceKey then ids[#ids + 1] = evidenceId end end
      add("PEER_EVIDENCE_DIVERGENCE", ids, { observedSources = sortedKeys(sources), sourceCount = count(state.sources) })
    end
  end
  state.findings = findings
end

local function collectInto(state, sourceInput, records, strict)
  local source, sourceReason = sourceDescriptor(sourceInput)
  if not source then return nil, sourceReason end
  if type(records) ~= "table" then return nil, "INVALID_EVIDENCE_RECORDS" end
  if count(state.sources) >= MAX_SOURCES and not state.sources[source.sourceId] then return nil, "EVIDENCE_SOURCE_LIMIT_EXCEEDED" end
  local existingSource = state.sources[source.sourceId]
  if existingSource and existingSource.sourceHash ~= source.sourceHash then return nil, "SOURCE_PROVENANCE_CONFLICT" end
  local normalized = {}
  for index, entry in ipairs(records) do
    local evidence, reason = normalizeRecord(source, entry, strict)
    if not evidence then return nil, reason end
    normalized[#normalized + 1] = evidence
  end
  local newCount = 0
  for _, evidence in ipairs(normalized) do if not state.evidence[evidence.evidenceId] then newCount = newCount + 1 end end
  if count(state.evidence) + newCount > MAX_EVIDENCE then return nil, "EVIDENCE_LIMIT_EXCEEDED" end
  if not existingSource then
    existingSource = copy(source); existingSource.evidenceIds = {}; state.sources[source.sourceId] = existingSource
  end
  local added = {}
  for _, evidence in ipairs(normalized) do
    local existing = state.evidence[evidence.evidenceId]
    if existing then
      if existing.sourceRecordHash ~= evidence.sourceRecordHash then return nil, "EVIDENCE_ID_CONFLICT" end
    else
      state.evidence[evidence.evidenceId] = evidence
      existingSource.evidenceIds[#existingSource.evidenceIds + 1] = evidence.evidenceId
      added[#added + 1] = evidence.evidenceId
    end
  end
  table.sort(existingSource.evidenceIds)
  rebuildFindings(state)
  return added
end

local function baselineProjection(state)
  local included, excluded, adjustments, unresolved, effects, decisionSet = {}, {}, {}, {}, {}, {}
  local logicalIncluded = {}
  for _, evidenceId in ipairs(sortedKeys(state.evidence)) do
    local evidence, decision = state.evidence[evidenceId], activeDecision(state, evidenceId)
    if not decision then return nil, "RECONCILIATION_DECISION_REQUIRED" end
    if decision.decision == "DEFER" then return nil, "RECONCILIATION_UNRESOLVED" end
    decisionSet[#decisionSet + 1] = {
      evidenceId = evidenceId, decision = decision.decision, decisionId = decision.decisionId,
      reason = decision.reason, sourceEvidenceHash = decision.sourceEvidenceHash, adjustment = copy(decision.adjustment), includeOriginal = decision.includeOriginal == true,
    }
    local includeOriginal = decision.decision == "INCLUDE" or (decision.decision == "COMPENSATING_ADJUSTMENT" and decision.includeOriginal == true)
    if includeOriginal then
      included[#included + 1] = evidenceId
      if not logicalIncluded[evidence.contentHash] then
        logicalIncluded[evidence.contentHash] = true
        if evidence.sourceType == "LEDGER_TRANSACTION" and evidence.amount ~= nil then
          effects[#effects + 1] = { evidenceId = evidenceId, memberKey = evidence.identity.memberKey, playerName = evidence.identity.original,
            seasonId = evidence.seasonId, amount = evidence.amount, action = evidence.action, source = "LEGACY_EVIDENCE" }
        end
      end
    else
      excluded[#excluded + 1] = evidenceId
    end
    if decision.decision == "COMPENSATING_ADJUSTMENT" then
      local adjustment = copy(decision.adjustment)
      adjustments[#adjustments + 1] = { evidenceId = evidenceId, decisionId = decision.decisionId, adjustment = adjustment }
      effects[#effects + 1] = { evidenceId = evidenceId, memberKey = adjustment.memberKey, playerName = adjustment.playerName,
        seasonId = adjustment.seasonId, amount = adjustment.amount, action = "COMPENSATING_ADJUSTMENT", source = "RECONCILIATION" }
    end
    if evidence.legacyPreDibState then unresolved[#unresolved + 1] = { evidenceId = evidenceId, state = evidence.legacyPreDibState } end
  end
  table.sort(included); table.sort(excluded)
  table.sort(adjustments, function(a, b) return a.evidenceId < b.evidenceId end)
  table.sort(unresolved, function(a, b) return a.evidenceId < b.evidenceId end)
  table.sort(decisionSet, function(a, b) return a.evidenceId < b.evidenceId end)
  table.sort(effects, function(a, b) return tostring(a.evidenceId) < tostring(b.evidenceId) end)
  local states, unresolvedEffects = {}, {}
  for _, effect in ipairs(effects) do
    if effect.memberKey and type(effect.seasonId) == "string" then
      states[effect.seasonId] = states[effect.seasonId] or {}
      states[effect.seasonId][effect.memberKey] = (states[effect.seasonId][effect.memberKey] or 0) + effect.amount
    else
      unresolvedEffects[#unresolvedEffects + 1] = copy(effect)
    end
  end
  local sourceSummary = {}
  for _, sourceId in ipairs(sortedKeys(state.sources)) do
    local source = state.sources[sourceId]
    sourceSummary[#sourceSummary + 1] = { sourceId = source.sourceId, sourceClient = source.sourceClient, sourceType = source.sourceType,
      sourceVersion = source.sourceVersion, complete = source.complete, sourceHash = source.sourceHash, evidenceCount = #(source.evidenceIds or {}) }
  end
  local projection = {
    schema = SCHEMA, recordClass = "LEGACY_BASELINE", guildKey = Dibs.GetGuildKey(), sources = sourceSummary,
    includedEvidenceIds = included, excludedEvidenceIds = excluded, compensatingAdjustments = adjustments, decisions = decisionSet,
    playerSeasonState = states, unresolvedEffects = unresolvedEffects, historicalPreDibs = unresolved,
  }
  return projection
end

local function buildBaseline(state)
  local projection, reason = baselineProjection(state)
  if not projection then return nil, reason end
  local baselineHash = hash(projection)
  if not baselineHash then return nil, "UNHASHABLE_BASELINE" end
  local baseline = copy(projection)
  baseline.legacyBaselineHash = baselineHash
  return baseline
end

local function incompleteSources(state)
  for _, source in pairs(state.sources) do if source.complete == false then return true end end
  return false
end

function M.GetState() return copy(ensure()) end
function M.GetEvidence() return sortedValues(ensure().evidence) end
function M.GetFindings() return sortedValues(ensure().findings) end
function M.GetBaseline() return copy(ensure().baseline) end
function M.CalculateLegacyBaselineHash(content) return hash(content) end

-- Evidence collection is local and attributable, but does not grant canonical status.
function M.CollectEvidence(actor, source, records)
  local snapshot, reason = localSnapshot(actor, false, false)
  if not snapshot then return nil, reason end
  local state = ensure()
  local staged = copy(state)
  local added, collectReason = collectInto(staged, source, records)
  if not added then return nil, collectReason end
  staged.status = "LEGACY_PREPARED"
  staged.baseline = nil
  boundedInsert(staged.auditLog, { action = "EVIDENCE_COLLECTED", actor = copy(snapshot), sourceId = source.sourceId, added = #added, timestamp = now() }, MAX_AUDIT)
  Dibs.GetDB().legacyBaseline = staged
  return copy(added)
end

-- Collects the local Dibs-owned history only. RCLootCouncil history is deliberately excluded.
function M.CollectLocalEvidence(actor, sourceId)
  local db = Dibs.GetDB()
  local ledger, preDibs = db.ledger or {}, db.preDibs or {}
  local ledgerRecords, requestRecords = {}, {}
  for id, record in pairs(ledger.transactions or {}) do ledgerRecords[#ledgerRecords + 1] = { originalId = id, record = copy(record) } end
  for _, record in ipairs(preDibs.requests or {}) do requestRecords[#requestRecords + 1] = { originalId = record.requestId, record = copy(record) } end
  table.sort(ledgerRecords, function(a, b) return tostring(a.originalId) < tostring(b.originalId) end)
  table.sort(requestRecords, function(a, b) return tostring(a.originalId) < tostring(b.originalId) end)
  local client = Dibs.GetPlayerName()
  local first, reason = M.CollectEvidence(actor, { sourceId = (sourceId or "local") .. ":ledger", sourceClient = client,
    sourceType = "LEDGER_TRANSACTION", sourceVersion = db.version, guildKey = Dibs.GetGuildKey(), complete = true }, ledgerRecords)
  if not first then return nil, reason end
  local second, requestReason = M.CollectEvidence(actor, { sourceId = (sourceId or "local") .. ":predibs", sourceClient = client,
    sourceType = "PREDIB_REQUEST", sourceVersion = db.version, guildKey = Dibs.GetGuildKey(), complete = true }, requestRecords)
  if not second then return nil, requestReason end
  return { ledger = first, preDibs = second }
end

function M.RecordDecision(actor, evidenceId, decision, options)
  local snapshot, reason = localSnapshot(actor, false, true)
  if not snapshot then return nil, reason end
  local state = ensure(); evidenceId, decision, options = trim(evidenceId), trim(decision), options or {}
  if not evidenceId or not state.evidence[evidenceId] then return nil, "EVIDENCE_NOT_FOUND" end
  if not DECISIONS[decision] then return nil, "INVALID_RECONCILIATION_DECISION" end
  local previous = activeDecision(state, evidenceId)
  if previous and trim(options.supersedes) ~= previous.decisionId then return nil, "EXPLICIT_SUPERSESSION_REQUIRED" end
  local adjustment = nil
  if decision == "COMPENSATING_ADJUSTMENT" then
    local playerName, seasonId, amount = trim(options.playerName), trim(options.seasonId), tonumber(options.amount)
    local identity = canonicalIdentity(playerName)
    if identity.status ~= "NAME_REALM" or not seasonId or not finite(amount) or amount == 0 then return nil, "INVALID_COMPENSATING_ADJUSTMENT" end
    adjustment = { memberKey = identity.memberKey, playerName = playerName, seasonId = seasonId, amount = amount, reason = trim(options.adjustmentReason) or trim(options.reason) }
  end
  local sourceEvidence = state.evidence[evidenceId]
  local record = {
    schema = SCHEMA, evidenceId = evidenceId, decision = decision, sourceEvidenceHash = sourceEvidence.contentHash,
    actor = copy(snapshot), reason = trim(options.reason), adjustment = adjustment, includeOriginal = options.includeOriginal == true,
    supersedes = previous and previous.decisionId or nil, timestamp = now(),
  }
  record.decisionId = "D5-" .. tostring(hash({ evidenceId = record.evidenceId, decision = record.decision,
    sourceEvidenceHash = record.sourceEvidenceHash, actor = record.actor.memberKey, reason = record.reason, adjustment = record.adjustment,
    includeOriginal = record.includeOriginal, supersedes = record.supersedes }))
  local duplicate = state.decisions[record.decisionId]
  if duplicate then return copy(duplicate), "IDEMPOTENT_REPLAY" end
  if count(state.decisions) >= MAX_DECISIONS then return nil, "RECONCILIATION_DECISION_LIMIT_EXCEEDED" end
  state.decisions[record.decisionId] = record
  state.activeDecisionByEvidence[evidenceId] = record.decisionId
  rebuildFindings(state)
  state.status, state.baseline = "LEGACY_PREPARED", nil
  boundedInsert(state.auditLog, { action = "DECISION_RECORDED", decisionId = record.decisionId, evidenceId = evidenceId, actor = copy(snapshot), timestamp = now() }, MAX_AUDIT)
  return copy(record), "DECISION_RECORDED"
end

function M.PreviewBaseline()
  local baseline, reason = buildBaseline(ensure())
  if not baseline then return nil, reason end
  return copy(baseline)
end

function M.FinalizeBaseline(actor, options)
  options = options or {}
  if not governanceReady() then return nil, "GOVERNANCE_REQUIRED" end
  local snapshot, reason = localSnapshot(actor, true, false)
  if not snapshot then return nil, reason end
  local state = ensure()
  if incompleteSources(state) and options.acknowledgeIncompleteEvidence ~= true then return nil, "INCOMPLETE_EVIDENCE_ACKNOWLEDGEMENT_REQUIRED" end
  local baseline, baselineReason = buildBaseline(state)
  if not baseline then return nil, baselineReason end
  baseline.gmApproval = { memberKey = snapshot.memberKey, displayName = snapshot.displayName, approvedAt = now(), acknowledgement = options.acknowledgeIncompleteEvidence == true or nil }
  state.baseline, state.status = baseline, "BASELINE_APPROVED"
  boundedInsert(state.auditLog, { action = "BASELINE_APPROVED", actor = copy(snapshot), legacyBaselineHash = baseline.legacyBaselineHash, timestamp = now() }, MAX_AUDIT)
  return copy(baseline), "BASELINE_APPROVED"
end

local function recoveryProjection(package)
  return {
    schema = package.schema, recordClass = package.recordClass, guildKey = package.guildKey, source = package.source,
    expectedContext = package.expectedContext, baselineRelationship = package.baselineRelationship, evidenceSources = package.evidenceSources,
  }
end
function M.CalculateRecoveryContentHash(package)
  return type(package) == "table" and hash(recoveryProjection(package)) or nil
end

local function validateRecoveryPackage(package, context)
  context = context or {}
  if type(package) ~= "table" or package.schema ~= SCHEMA or package.recordClass ~= "LEGACY_RECOVERY_PACKAGE" then return nil, "UNSUPPORTED_RECOVERY_SCHEMA" end
  if package.guildKey ~= Dibs.GetGuildKey() then return nil, "GUILD_SCOPE_MISMATCH" end
  if type(package.source) ~= "table" or not trim(package.source.sourceId) or not trim(package.source.authorNameRealm) then return nil, "INVALID_RECOVERY_PROVENANCE" end
  if package.expectedContext ~= "LEGACY_LOCAL" and package.expectedContext ~= "CUTOVER_PREPARED" then return nil, "INVALID_RECOVERY_CONTEXT" end
  if type(package.evidenceSources) ~= "table" or #package.evidenceSources == 0 or #package.evidenceSources > MAX_SOURCES then return nil, "INCOMPLETE_RECOVERY_PACKAGE" end
  if type(package.audit) ~= "table" or not finite(tonumber(package.createdAt)) then return nil, "INVALID_RECOVERY_AUDIT" end
  if package.contentHash ~= M.CalculateRecoveryContentHash(package) then return nil, "RECOVERY_HASH_MISMATCH" end
  if context.sender then
    local sender = Dibs.Identity and Dibs.Identity.CreateSnapshot and Dibs.Identity.CreateSnapshot(context.sender)
    local author = Dibs.Identity and Dibs.Identity.CreateSnapshot and Dibs.Identity.CreateSnapshot(package.source.authorNameRealm)
    if not sender or not author or sender.memberKey ~= author.memberKey then return nil, "RECOVERY_SENDER_AUTHOR_MISMATCH" end
  end
  return true
end

-- Validates and normalizes the entire package into a detached state. It has no side effects.
function M.StageRecoveryPackage(package, context)
  local valid, reason = validateRecoveryPackage(package, context)
  if not valid then return nil, reason end
  local staged = copy(ensure())
  for _, sourcePackage in ipairs(package.evidenceSources) do
    if type(sourcePackage) ~= "table" then return nil, "INCOMPLETE_RECOVERY_PACKAGE" end
    local added, collectReason = collectInto(staged, sourcePackage.source, sourcePackage.records, true)
    if not added then return nil, collectReason end
  end
  staged.status, staged.baseline = "LEGACY_PREPARED", nil
  return { package = copy(package), packageHash = package.contentHash, stagedState = staged }
end

-- Applies a fully staged recovery in one replacement after a B01 safety backup.
function M.CommitRecoveryPackage(actor, staged, context)
  local snapshot, reason = localSnapshot(actor, false, true)
  if not snapshot then return nil, reason end
  if type(staged) ~= "table" or type(staged.package) ~= "table" then return nil, "RECOVERY_STAGE_REQUIRED" end
  local verified, stageReason = M.StageRecoveryPackage(staged.package, context)
  if not verified then return nil, stageReason end
  local current = ensure()
  if current.recoveries[verified.packageHash] then return { accepted = true, idempotentReplay = true, packageHash = verified.packageHash }, "IDEMPOTENT_RECOVERY" end
  local backup = Dibs.Backup and Dibs.Backup.Create and Dibs.Backup.Create("guild", "before-legacy-recovery:" .. verified.packageHash, actor)
  if not backup then return nil, "SAFETY_SNAPSHOT_FAILED" end
  local replacement = verified.stagedState
  replacement.recoveries[verified.packageHash] = { packageHash = verified.packageHash, source = copy(staged.package.source), receivedBy = copy(snapshot),
    receiptKind = context and context.sender and "REMOTE_B04_WHISPER" or "MANUAL_LOCAL_IMPORT", senderNameRealm = context and context.sender or nil,
    committedAt = now(), backupSnapshotId = backup.snapshotId }
  boundedInsert(replacement.auditLog, { action = "RECOVERY_COMMITTED", packageHash = verified.packageHash, actor = copy(snapshot), timestamp = now() }, MAX_AUDIT)
  Dibs.GetDB().legacyBaseline = replacement
  return { accepted = true, idempotentReplay = false, packageHash = verified.packageHash, backupSnapshotId = backup.snapshotId }, "RECOVERY_COMMITTED"
end

-- A package received through B04 transport remains runtime-only evidence until
-- a local, roster-validated assistant explicitly commits it.
function M.GetReceivedRecovery(packageHash)
  local pending = Dibs.runtime and Dibs.runtime.legacyRecoveryPackages and Dibs.runtime.legacyRecoveryPackages[packageHash]
  return pending and copy(pending) or nil
end
function M.CommitReceivedRecovery(actor, packageHash)
  local pending = M.GetReceivedRecovery(packageHash)
  if not pending then return nil, "RECOVERY_PACKAGE_NOT_FOUND" end
  return M.CommitRecoveryPackage(actor, pending.staged, { sender = pending.senderNameRealm })
end

-- Existing ImportExport full packages are legacy/diagnostic imports, never this authoritative recovery schema.
function M.ClassifyImportPackage(package)
  if type(package) ~= "table" then return nil, "INVALID_PACKAGE" end
  return { recoveryClass = "LEGACY_DIAGNOSTIC_ONLY", authoritativeRecovery = false, packageChecksum = package.checksum }
end

return M
