--[[
Module: Dibs.CharacterEligibility
Layer: Domain policy
Purpose: Evaluate Curio/Tier Set eligibility across approved main/alt relationships.
Responsibilities: Policy, probation, exceptions, acquisitions, and review decisions.
Non-responsibilities: It never infers relationships or rewrites the ledger.
Dependencies: Ledger, Seasons, Permissions, Dibs.GetDB.
Blizzard events: None directly.  Internal events/messages: None emitted.
SavedVariables: db.characterEligibility and its versioned sub-tables.
RCLootCouncil: Eligibility may be queried while projecting candidate status.
Combat safety: Pure data evaluation.
Invariants: DIBS-RULE-010 and DIBS-RULE-011.
Related docs: docs/developer/data-model.md, docs/officer/configuration.md.
]]

local Dibs = _G.Dibs
Dibs.CharacterEligibility = Dibs.CharacterEligibility or {}
Dibs.Eligibility = Dibs.CharacterEligibility

local Eligibility = Dibs.CharacterEligibility

local VALID_FAMILIES = { TOKEN = true, TOKEN_SET = true }
local VALID_OUTCOMES = { allow = true, warn = true, review = true, downgrade = true, block = true }
local VALID_SCOPES = { SAME = true, ALL = true }
local VALID_MATCHING = { EXACT = true, FAMILY = true, SLOT = true, GROUP = true }

local DEFAULT_POLICIES = {
  TOKEN = {
    family = "TOKEN", enabled = true, matchingScope = "FAMILY", difficultyScope = "ALL",
    enforcementOutcome = "BLOCK", unknownDataBehavior = "REVIEW", completionThreshold = 4,
    higherTrackOutcome = "REVIEW", baselineTrack = 1, noNeedAllowed = true,
  },
  TOKEN_SET = {
    family = "TOKEN_SET", enabled = true, matchingScope = "GROUP", difficultyScope = "ALL",
    enforcementOutcome = "BLOCK", unknownDataBehavior = "REVIEW", roundRule = "LOWEST_PROGRESS",
    tierSetGroupMode = "CLASS_TOKEN", groups = {},
  },
}

local function copy(value)
  if Dibs.DeepCopy then return Dibs.DeepCopy(value) end
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end

local function now()
  return tonumber(type(time) == "function" and time() or 0) or 0
end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function lower(value)
  return string.lower(trim(value))
end

local function actorId(actor)
  if Dibs.Permissions and type(Dibs.Permissions.CanonicalPlayerId) == "function" then
    return Dibs.Permissions.CanonicalPlayerId(actor)
  end
  return lower(type(actor) == "table" and (actor.guid or actor.name or actor.playerName) or actor)
end

local function displayName(value)
  if type(value) == "table" then return tostring(value.name or value.playerName or value.guid or "") end
  return trim(value)
end

local function sameIdentity(first, second)
  local a, b = actorId(first), actorId(second)
  return a ~= nil and b ~= nil and lower(a) == lower(b)
end

local function ensureState()
  local db = Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
  db.characterEligibility = db.characterEligibility or {}
  local state = db.characterEligibility
  state.version = tonumber(state.version) or 1
  state.policies = state.policies or {}
  state.acquisitions = state.acquisitions or {}
  state.acquisitionIndex = state.acquisitionIndex or {}
  state.relationships = state.relationships or {}
  state.relationshipOrder = state.relationshipOrder or {}
  state.mainChanges = state.mainChanges or {}
  state.mainChangeOrder = state.mainChangeOrder or {}
  state.exceptions = state.exceptions or {}
  state.decisions = state.decisions or {}
  state.groups = state.groups or {}
  return state
end

local function currentSeason(seasonId)
  return seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
end

local function normalizeFamily(value)
  local key = string.upper(trim(value)):gsub("[%s%-]", "_")
  if key == "CURIO" or key == "CURIOS" or key == "CONTEXT_TOKEN" then return "TOKEN" end
  if key == "TIER_SET" or key == "TIERSET" or key == "ARMOR_TOKEN" then return "TOKEN_SET" end
  if key == "CATALYST" or key == "CATALYST_ITEMS" then return "CATALYST" end
  return VALID_FAMILIES[key] and key or nil
end

local function normalizeDifficulty(value)
  if Dibs.PreDibs and Dibs.PreDibs.NormalizeDifficulty then
    local result = Dibs.PreDibs.NormalizeDifficulty(value)
    if result and result ~= "UNKNOWN" then return result end
  end
  local key = string.upper(trim(value))
  if key == "LFR" or key == "LOOKING_FOR_RAID" then return "LFR" end
  if key == "NORMAL" then return "Normal" end
  if key == "HEROIC" then return "Heroic" end
  if key == "MYTHIC" then return "Mythic" end
  return "UNKNOWN"
end

local function normalizeOutcome(value, fallback)
  local key = string.lower(trim(value))
  if VALID_OUTCOMES[key] then return key end
  return fallback or "review"
end

local function normalizeScope(value)
  local key = string.upper(trim(value))
  if key == "SAME_DIFFICULTY" then key = "SAME" end
  if key == "ALL_DIFFICULTIES" or key == "CROSS" or key == "CROSS_DIFFICULTY" then key = "ALL" end
  return VALID_SCOPES[key] and key or "ALL"
end

local function normalizeMatching(value, fallback)
  local key = string.upper(trim(value))
  return VALID_MATCHING[key] and key or (fallback or "FAMILY")
end

local function validSeason(seasonId)
  return seasonId and Dibs.Seasons and Dibs.Seasons.GetById and Dibs.Seasons.GetById(seasonId) ~= nil
end

local function appendAudit(action, actor, payload, reason)
  local db = Dibs.GetDB and Dibs.GetDB() or {}
  db.auditLog = db.auditLog or {}
  table.insert(db.auditLog, {
    eventId = Dibs.NewId and Dibs.NewId("eligibility-audit") or ("eligibility-audit-" .. tostring(now())),
    action = action, actorId = actorId(actor) or "unknown", createdAt = now(), reason = reason,
    seasonId = payload and payload.seasonId, family = payload and payload.family,
    relationshipId = payload and payload.relationshipId, changeId = payload and payload.changeId,
    acquisitionId = payload and payload.acquisitionId,
  })
  while #db.auditLog > 1000 do table.remove(db.auditLog, 1) end
end

local function defaultPolicy(family)
  return copy(DEFAULT_POLICIES[family])
end

local function sanitizePolicy(input, seasonId)
  local family = normalizeFamily(input and (input.family or input.dibsType))
  if not family or family == "CATALYST" then return nil, "INVALID_FAMILY" end
  local policy = defaultPolicy(family)
  for key, value in pairs(input or {}) do
    if key ~= "seasonId" and key ~= "family" and key ~= "dibsType" then policy[key] = copy(value) end
  end
  policy.family = family
  policy.seasonId = seasonId
  policy.enabled = input and input.enabled ~= false
  policy.matchingScope = normalizeMatching(policy.matchingScope, policy.matchingScope)
  policy.difficultyScope = normalizeScope(policy.difficultyScope)
  policy.enforcementOutcome = normalizeOutcome(policy.enforcementOutcome, "block")
  policy.unknownDataBehavior = string.upper(trim(policy.unknownDataBehavior)) == "BLOCK" and "BLOCK" or "REVIEW"
  if family == "TOKEN" then
    policy.completionThreshold = math.max(1, math.min(20, math.floor(tonumber(policy.completionThreshold) or 4)))
    policy.higherTrackOutcome = normalizeOutcome(policy.higherTrackOutcome, "review")
    policy.baselineTrack = tonumber(policy.baselineTrack) or 1
  else
    policy.roundRule = "LOWEST_PROGRESS"
    policy.tierSetGroupMode = "CLASS_TOKEN"
    local groups = {}
    for name, group in pairs(type(policy.groups) == "table" and policy.groups or {}) do
      local key = string.upper(trim(name))
      if key ~= "" then groups[key] = copy(group) end
    end
    policy.groups = groups
  end
  return policy
end

function Eligibility.GetPolicy(seasonId, family)
  local state = ensureState()
  local targetSeason = currentSeason(seasonId)
  local key = normalizeFamily(family)
  if not targetSeason or not key or key == "CATALYST" then return nil end
  state.policies[targetSeason] = state.policies[targetSeason] or {}
  local stored = state.policies[targetSeason][key]
  if not stored then
    stored = defaultPolicy(key)
    stored.seasonId = targetSeason
    state.policies[targetSeason][key] = stored
  end
  local result = defaultPolicy(key)
  for field, value in pairs(stored) do result[field] = copy(value) end
  result.family, result.seasonId = key, targetSeason
  return result
end

---@param input DibsEligibilityPolicy|table Policy fields plus season/family.
---@param actor string|nil Officer actor identity.
---@return DibsEligibilityPolicy|nil policy
---@return string|nil reasonCode
-- Side effects: Persists a versioned season/family eligibility policy.
function Eligibility.SetPolicy(input, actor)
  local targetSeason = currentSeason(input and input.seasonId)
  if not validSeason(targetSeason) then return nil, "SEASON_NOT_FOUND" end
  if not Dibs.Permissions or not Dibs.Permissions.Can or not Dibs.Permissions.Can("eligibility.policy.set", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  local policy, reason = sanitizePolicy(input or {}, targetSeason)
  if not policy then return nil, reason end
  local state = ensureState()
  state.policies[targetSeason] = state.policies[targetSeason] or {}
  policy.updatedAt, policy.updatedBy = now(), actorId(actor)
  state.policies[targetSeason][policy.family] = policy
  appendAudit("eligibility.policy.set", actor, policy, input and input.reason or "Policy updated")
  return copy(policy)
end

function Eligibility.NormalizeFamily(value)
  return normalizeFamily(value)
end

function Eligibility.GetPlayerGroup(playerName, seasonId)
  local state = ensureState()
  local targetSeason = currentSeason(seasonId)
  local character = actorId(playerName or (Dibs.GetPlayerName and Dibs.GetPlayerName() or nil))
  if not character then return nil end
  for _, relationshipId in ipairs(state.relationshipOrder) do
    local relationship = state.relationships[relationshipId]
    if relationship and relationship.seasonId == targetSeason and relationship.status == "approved"
      and (relationship.mainCharacterId == character or relationship.altCharacterId == character)
    then
      return relationship.playerGroupId
    end
  end
  for _, changeId in ipairs(state.mainChangeOrder) do
    local change = state.mainChanges[changeId]
    if change and change.seasonId == targetSeason and change.status == "approved"
      and (change.oldMainId == character or change.newMainId == character)
    then
      return change.playerGroupId
    end
  end
  return "character:" .. tostring(character)
end

local function relationshipForCharacter(character, seasonId)
  local state = ensureState()
  local id, targetSeason = actorId(character), currentSeason(seasonId)
  for _, relationshipId in ipairs(state.relationshipOrder) do
    local relationship = state.relationships[relationshipId]
    if relationship and relationship.seasonId == targetSeason and relationship.status == "approved"
      and (relationship.mainCharacterId == id or relationship.altCharacterId == id)
    then return relationship end
  end
  return nil
end

---@param input table Main/alt relationship declaration.
---@param actor string|nil Declaring player identity.
---@return table|nil relationship Pending relationship record.
---@return string|nil reasonCode
function Eligibility.DeclareRelationship(input, actor)
  local options = type(input) == "table" and input or {}
  local targetSeason = currentSeason(options.seasonId)
  if not validSeason(targetSeason) then return nil, "SEASON_NOT_FOUND" end
  local declaringActor = actor or options.declaredBy or Dibs.GetPlayerName()
  local main = actorId(options.mainCharacterId or options.mainCharacter or options.main)
  local alt = actorId(options.altCharacterId or options.altCharacter or options.alt)
  if not main or not alt or main == alt then return nil, "INVALID_RELATIONSHIP" end
  if options.playerName and not sameIdentity(declaringActor, options.playerName) then return nil, "OWNER_MISMATCH" end
  local state = ensureState()
  for _, relationshipId in ipairs(state.relationshipOrder) do
    local existing = state.relationships[relationshipId]
    if existing and existing.seasonId == targetSeason and existing.mainCharacterId == main and existing.altCharacterId == alt
      and existing.status ~= "rejected" and existing.status ~= "suspended"
    then return copy(existing) end
  end
  local relationship = {
    relationshipId = Dibs.NewId and Dibs.NewId("relationship") or ("relationship-" .. tostring(now())),
    seasonId = targetSeason, guildKey = Dibs.GetGuildKey and Dibs.GetGuildKey() or "unknown",
    mainCharacterId = main, mainCharacterName = displayName(options.mainCharacter or options.main),
    altCharacterId = alt, altCharacterName = displayName(options.altCharacter or options.alt),
    playerGroupId = options.playerGroupId or ("group:" .. tostring(main)), status = "pending",
    declaredBy = actorId(declaringActor), declaredAt = now(), reason = options.reason,
  }
  state.relationships[relationship.relationshipId] = relationship
  table.insert(state.relationshipOrder, relationship.relationshipId)
  return copy(relationship)
end

---@param relationshipId string Relationship record ID.
---@param decision string Approval/rejection decision.
---@param actor string Officer reviewer.
---@param reason string|nil Review reason.
---@return table|nil relationship Reviewed record.
---@return string|nil reasonCode
function Eligibility.ReviewRelationship(relationshipId, decision, actor, reason)
  if not Dibs.Permissions or not Dibs.Permissions.Can or not Dibs.Permissions.Can("eligibility.relationship.review", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  local state = ensureState()
  local relationship = state.relationships[tostring(relationshipId)]
  local status = string.lower(trim(type(decision) == "table" and decision.status or decision))
  if not relationship then return nil, "RELATIONSHIP_NOT_FOUND" end
  if status ~= "approved" and status ~= "rejected" and status ~= "suspended" then return nil, "INVALID_RELATIONSHIP_STATUS" end
  local detail = type(decision) == "table" and decision.reason or reason
  if (status == "rejected" or status == "suspended") and trim(detail) == "" then return nil, "REASON_REQUIRED" end
  relationship.status, relationship.reviewedBy, relationship.reviewedAt, relationship.reviewReason = status, actorId(actor), now(), detail
  appendAudit("eligibility.relationship." .. status, actor, relationship, detail)
  return copy(relationship)
end

Eligibility.ApproveRelationship = function(id, actor) return Eligibility.ReviewRelationship(id, "approved", actor) end
Eligibility.RejectRelationship = function(id, actor, reason) return Eligibility.ReviewRelationship(id, "rejected", actor, reason) end

function Eligibility.ListRelationships(actor, seasonId)
  if not Dibs.Permissions or not Dibs.Permissions.GetGuildRole then return {} end
  local role = Dibs.Permissions.GetGuildRole(actor)
  if role ~= "gm" and role ~= "officer" then return {}, "GUILD_ADMIN_REQUIRED" end
  local state, result = ensureState(), {}
  local targetSeason = currentSeason(seasonId)
  for _, relationshipId in ipairs(state.relationshipOrder) do
    local relationship = state.relationships[relationshipId]
    if relationship and relationship.seasonId == targetSeason then table.insert(result, copy(relationship)) end
  end
  table.sort(result, function(a, b) return (a.declaredAt or 0) > (b.declaredAt or 0) end)
  return result
end

function Eligibility.ListMainChanges(actor, seasonId)
  if not Dibs.Permissions or not Dibs.Permissions.GetGuildRole then return {} end
  local role = Dibs.Permissions.GetGuildRole(actor)
  if role ~= "gm" and role ~= "officer" then return {}, "GUILD_ADMIN_REQUIRED" end
  local state, result = ensureState(), {}
  local targetSeason = currentSeason(seasonId)
  for _, changeId in ipairs(state.mainChangeOrder) do
    local change = state.mainChanges[changeId]
    if change and change.seasonId == targetSeason then table.insert(result, copy(change)) end
  end
  table.sort(result, function(a, b) return (a.requestedAt or 0) > (b.requestedAt or 0) end)
  return result
end

function Eligibility.GetRelationshipStatus(playerName, seasonId)
  local state, targetSeason, id = ensureState(), currentSeason(seasonId), actorId(playerName or Dibs.GetPlayerName())
  local result = {}
  for _, relationshipId in ipairs(state.relationshipOrder) do
    local relationship = state.relationships[relationshipId]
    if relationship and relationship.seasonId == targetSeason and (relationship.mainCharacterId == id or relationship.altCharacterId == id) then
      table.insert(result, copy(relationship))
    end
  end
  return result
end

function Eligibility.RequestMainChange(input, actor)
  local options = type(input) == "table" and input or {}
  local targetSeason = currentSeason(options.seasonId)
  if not validSeason(targetSeason) then return nil, "SEASON_NOT_FOUND" end
  local oldMain = actorId(options.oldMainId or options.oldMain or options.mainCharacter or actor or Dibs.GetPlayerName())
  local newMain = actorId(options.newMainId or options.newMain)
  if not oldMain or not newMain or oldMain == newMain then return nil, "INVALID_MAIN_CHANGE" end
  local group = Eligibility.GetPlayerGroup(oldMain, targetSeason)
  local state = ensureState()
  for _, changeId in ipairs(state.mainChangeOrder) do
    local existing = state.mainChanges[changeId]
    if existing and existing.seasonId == targetSeason and existing.playerGroupId == group and (existing.status == "pending" or existing.status == "approved") then
      return nil, "MAIN_CHANGE_ALREADY_ACTIVE"
    end
  end
  local request = {
    changeId = Dibs.NewId and Dibs.NewId("main-change") or ("main-change-" .. tostring(now())),
    seasonId = targetSeason, playerGroupId = group, oldMainId = oldMain, newMainId = newMain,
    oldMainName = displayName(options.oldMain or options.mainCharacter or actor or Dibs.GetPlayerName()),
    newMainName = displayName(options.newMain),
    status = "pending", requestedBy = actorId(actor or Dibs.GetPlayerName()), requestedAt = now(), reason = options.reason,
  }
  state.mainChanges[request.changeId] = request
  table.insert(state.mainChangeOrder, request.changeId)
  return copy(request)
end

function Eligibility.ApproveMainChange(changeId, options, actor)
  if not Dibs.Permissions or not Dibs.Permissions.Can or not Dibs.Permissions.Can("eligibility.main.review", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  local state = ensureState()
  local change = state.mainChanges[tostring(changeId)]
  if not change then return nil, "MAIN_CHANGE_NOT_FOUND" end
  local settings = type(options) == "table" and options or {}
  if change.status == "approved" and settings.force ~= true then return copy(change) end
  local effectiveAt = tonumber(settings.effectiveAt) or now()
  local duration = tonumber(settings.probationDuration) or 14 * 24 * 60 * 60
  duration = math.max(0, math.min(365 * 24 * 60 * 60, math.floor(duration)))
  change.status, change.effectiveAt, change.probationEndsAt = "approved", effectiveAt, effectiveAt + duration
  change.outcome = normalizeOutcome(settings.outcome or "block", "block")
  change.approverId, change.approverName, change.approvalReason = actorId(actor), displayName(actor), settings.reason or change.reason
  appendAudit("eligibility.main.approve", actor, change, change.approvalReason)
  return copy(change)
end

function Eligibility.GetProbation(playerName, seasonId)
  local state, targetSeason, group = ensureState(), currentSeason(seasonId), Eligibility.GetPlayerGroup(playerName, seasonId)
  local current = now()
  for _, changeId in ipairs(state.mainChangeOrder) do
    local change = state.mainChanges[changeId]
    if change and change.seasonId == targetSeason and change.playerGroupId == group and change.status == "approved"
      and tonumber(change.probationEndsAt) and current < tonumber(change.probationEndsAt)
    then return copy(change) end
  end
  return nil
end

function Eligibility.CreateProbationException(options, actor)
  local settings = type(options) == "table" and options or {}
  if not Dibs.Permissions or not Dibs.Permissions.Can or not Dibs.Permissions.Can("eligibility.exception.create", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  local state = ensureState()
  local change = state.mainChanges[tostring(settings.changeId or "")]
  if not change or change.status ~= "approved" then return nil, "MAIN_CHANGE_NOT_FOUND" end
  local reason = trim(settings.reason)
  if reason == "" then return nil, "REASON_REQUIRED" end
  local limit = tonumber(settings.awardLimit)
  local expires = tonumber(settings.expiresAt)
  if (not limit or limit < 1) and (not expires or expires <= now()) then return nil, "EXCEPTION_BOUND_REQUIRED" end
  local exception = {
    exceptionId = Dibs.NewId and Dibs.NewId("probation-exception") or ("probation-exception-" .. tostring(now())),
    changeId = change.changeId, seasonId = change.seasonId, playerGroupId = change.playerGroupId,
    scope = string.upper(trim(settings.scope or "MAIN_SPEC")), awardLimit = limit and math.floor(limit) or nil,
    awardsUsed = 0, expiresAt = expires, reason = reason, approverId = actorId(actor), status = "active", createdAt = now(),
  }
  state.exceptions[exception.exceptionId] = exception
  appendAudit("eligibility.exception.create", actor, exception, reason)
  return copy(exception)
end

function Eligibility.GetAcquisitions(playerName, seasonId, family, actor)
  local state, targetSeason, key, result = ensureState(), currentSeason(seasonId), normalizeFamily(family), {}
  if actor and Dibs.Permissions and Dibs.Permissions.GetGuildRole then
    local role = Dibs.Permissions.GetGuildRole(actor)
    if role ~= "gm" and role ~= "officer" and not sameIdentity(actor, playerName) then return {}, "PLAYER_SCOPE_REQUIRED" end
  end
  local group = Eligibility.GetPlayerGroup(playerName, targetSeason)
  for _, acquisition in ipairs(state.acquisitions) do
    if acquisition and acquisition.seasonId == targetSeason and (not key or acquisition.family == key)
      and acquisition.playerGroupId == group then table.insert(result, copy(acquisition)) end
  end
  table.sort(result, function(a, b) return (a.acquiredAt or 0) > (b.acquiredAt or 0) end)
  return result
end

local function acquisitionMatches(acquisition, targetSeason, group, family, policy, context)
  if not acquisition or acquisition.seasonId ~= targetSeason or acquisition.playerGroupId ~= group or acquisition.family ~= family then return false end
  if policy.difficultyScope == "SAME" and normalizeDifficulty(acquisition.difficulty) ~= normalizeDifficulty(context.difficulty) then return false end
  if policy.matchingScope == "EXACT" and tonumber(acquisition.itemID) ~= tonumber(context.itemID) then return false end
  if policy.matchingScope == "SLOT" and trim(acquisition.slot) ~= trim(context.slot) then return false end
  if policy.matchingScope == "GROUP" and trim(acquisition.tokenGroup) ~= trim(context.tokenGroup) then return false end
  return true
end

local function uniqueProgress(records, family)
  local seen, count, maxTrack = {}, 0, 0
  for _, record in ipairs(records) do
    local key = family == "TOKEN" and (trim(record.slot) ~= "" and trim(record.slot) or tostring(record.itemID))
      or (trim(record.tokenGroup) .. "|" .. tostring(record.itemID))
    if not seen[key] then seen[key], count = true, count + 1 end
    local track = tonumber(record.upgradeTrack or record.track) or 0
    local label = string.upper(trim(record.upgradeTrack or record.track))
    if label == "MYTHIC" then track = math.max(track, 3) elseif label == "HEROIC" then track = math.max(track, 2) end
    maxTrack = math.max(maxTrack, track)
  end
  return count, maxTrack
end

local function inferFamily(context)
  local value = context and (context.family or context.semanticFamily or context.dibsType or context.lootFamily or context.responseType)
  local family = normalizeFamily(value)
  if family then return family end
  if Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetItemSemanticFamily then
    return normalizeFamily(Dibs.RCLootCouncil.GetItemSemanticFamily(context and context.itemID, context and context.responseType))
  end
  return nil
end

local function isMainSpecContext(context)
  if context.isMainSpec == true then return true end
  local response = string.lower(tostring(context.responseType or context.response or ""))
  return response:find("main", 1, true) ~= nil or response:find("need", 1, true) ~= nil
end

local function exceptionFor(change, context)
  local state, current = ensureState(), now()
  for _, exception in pairs(state.exceptions) do
    if exception and exception.changeId == change.changeId and exception.status == "active"
      and (not exception.expiresAt or current <= exception.expiresAt)
      and (not exception.awardLimit or (tonumber(exception.awardsUsed) or 0) < exception.awardLimit)
      and (exception.scope == "ANY_PROTECTED" or not isMainSpecContext(context) or exception.scope == "MAIN_SPEC")
    then return exception end
  end
  return nil
end

local function buildDecision(context, playerName, seasonId, outcome, reasonCode, explanation, extra)
  local decision = {
    decisionId = Dibs.NewId and Dibs.NewId("eligibility") or ("eligibility-" .. tostring(now())),
    seasonId = seasonId, family = inferFamily(context or {}), playerName = displayName(playerName),
    outcome = normalizeOutcome(outcome, "review"), reasonCode = reasonCode, explanation = explanation,
    createdAt = now(), itemID = tonumber(context and context.itemID),
  }
  for key, value in pairs(extra or {}) do decision[key] = copy(value) end
  local state = ensureState()
  table.insert(state.decisions, decision)
  while #state.decisions > 500 do table.remove(state.decisions, 1) end
  return decision
end

---@param context table Item and difficulty context.
---@param playerName string Player identity.
---@param seasonId string Season scope.
---@return table decision Explainable eligibility outcome and reason.
function Eligibility.Evaluate(context, playerName, seasonId)
  local input = type(context) == "table" and context or {}
  local targetSeason = currentSeason(seasonId or input.seasonId)
  local family = inferFamily(input)
  if not targetSeason or not validSeason(targetSeason) then
    return buildDecision(input, playerName, targetSeason, "review", "SEASON_NOT_FOUND", "No active Dibs season is available.")
  end
  if family == "CATALYST" then
    return buildDecision(input, playerName, targetSeason, "block", "CATALYST_PERSONAL", "Catalyst progress is personal and cannot use Dibs.", { family = family })
  end
  if not family then
    return buildDecision(input, playerName, targetSeason, "review", "UNKNOWN_FAMILY", "The loot family could not be identified; Officer review is required.")
  end
  local policy = Eligibility.GetPolicy(targetSeason, family)
  if not policy or policy.enabled ~= true then
    return buildDecision(input, playerName, targetSeason, "block", "FAMILY_DISABLED", "This protected loot family is disabled by the active season policy.", { family = family })
  end
  local group = Eligibility.GetPlayerGroup(playerName, targetSeason)
  local state, records = ensureState(), {}
  for _, acquisition in ipairs(state.acquisitions) do
    if acquisitionMatches(acquisition, targetSeason, group, family, policy, input) then table.insert(records, acquisition) end
  end
  local probation = Eligibility.GetProbation(playerName, targetSeason)
  local probationException
  if probation and isMainSpecContext(input) then
    probationException = exceptionFor(probation, input)
    if not probationException then
      return buildDecision(input, playerName, targetSeason, probation.outcome or "block", "MAIN_CHANGE_PROBATION",
        "Main-spec protected loot is restricted during the active main-change probation (until " .. tostring(probation.probationEndsAt) .. ").",
        { family = family, playerGroupId = group, probation = probation })
    end
  end
  local decisionExtra = function(extra)
    extra = extra or {}
    extra.probation = probation
    extra.probationException = probationException
    return extra
  end
  if family == "TOKEN" then
    local count, maxTrack = uniqueProgress(records, family)
    local threshold = tonumber(policy.completionThreshold) or 4
    local currentTrack = tonumber(input.upgradeTrack or input.track) or 0
    local trackLabel = string.upper(trim(input.upgradeTrack or input.track))
    if trackLabel == "MYTHIC" then currentTrack = math.max(currentTrack, 3) elseif trackLabel == "HEROIC" then currentTrack = math.max(currentTrack, 2) end
    if count >= threshold then
      if currentTrack > maxTrack and currentTrack > (tonumber(policy.baselineTrack) or 1) then
        return buildDecision(input, playerName, targetSeason, policy.higherTrackOutcome, "CURIO_HIGHER_TRACK",
          "Curio baseline is complete; this higher upgrade track follows the configured policy.",
          decisionExtra({ family = family, playerGroupId = group, progress = count, threshold = threshold, round = count + 1, acquisitions = records }))
      end
      return buildDecision(input, playerName, targetSeason, policy.enforcementOutcome, "CURIO_COMPLETE",
        "Curio completion threshold reached under the active season policy.",
        decisionExtra({ family = family, playerGroupId = group, progress = count, threshold = threshold, round = count + 1, acquisitions = records }))
    end
    return buildDecision(input, playerName, targetSeason, "allow", "CURIO_ROUND_OPEN",
      "Curio is eligible in the current round.", decisionExtra({ family = family, playerGroupId = group, progress = count, threshold = threshold, round = count + 1, acquisitions = records }))
  end

  local tokenGroup = string.upper(trim(input.tokenGroup or input.classTokenGroup or ""))
  local groupPolicy = policy.groups and policy.groups[tokenGroup]
  if not groupPolicy then
    return buildDecision(input, playerName, targetSeason, "review", "TIER_SET_GROUP_UNKNOWN", "The Tier Set class/token group is not configured; Officer review is required.", { family = family, tokenGroup = tokenGroup })
  end
  local ownCount = uniqueProgress(records, family)
  local minimum = ownCount
  local participants = groupPolicy and (groupPolicy.participants or groupPolicy.eligiblePlayers or groupPolicy.players or groupPolicy.members) or nil
  if type(participants) == "table" and #participants > 0 then
    minimum = math.huge
    for _, participant in ipairs(participants) do
      local participantGroup = Eligibility.GetPlayerGroup(participant, targetSeason)
      local participantRecords = {}
      for _, acquisition in ipairs(state.acquisitions) do
        if acquisition.seasonId == targetSeason and acquisition.playerGroupId == participantGroup and acquisition.family == family
          and trim(acquisition.tokenGroup) == tokenGroup
        then table.insert(participantRecords, acquisition) end
      end
      local progress = uniqueProgress(participantRecords, family)
      if progress < minimum then minimum = progress end
    end
    if minimum == math.huge then minimum = 0 end
  end
  if ownCount > minimum then
    return buildDecision(input, playerName, targetSeason, policy.enforcementOutcome, "TIER_SET_ROUND_PRIORITY",
      "Another eligible member is at a lower Tier Set round; normal priority is reserved for that round.",
      decisionExtra({ family = family, playerGroupId = group, tokenGroup = tokenGroup, progress = ownCount, round = minimum + 1, acquisitions = records }))
  end
  return buildDecision(input, playerName, targetSeason, "allow", "TIER_SET_ROUND_OPEN",
    "Tier Set token is eligible in the current lowest-progress round.",
    decisionExtra({ family = family, playerGroupId = group, tokenGroup = tokenGroup, progress = ownCount, round = minimum + 1, acquisitions = records }))
end

Eligibility.GetEligibility = Eligibility.Evaluate
Eligibility.IsEligible = function(context, playerName, seasonId)
  local decision = Eligibility.Evaluate(context, playerName, seasonId)
  return decision.outcome == "allow" or decision.outcome == "warn", decision
end

---@param record table Acquisition/evidence record.
---@param actor string|nil Officer/system actor.
---@param internal boolean|nil Internal trusted call marker.
---@return table|nil acquisition Stored acquisition.
---@return string|nil reasonCode
-- Side effects: Persists immutable acquisition evidence for future eligibility checks.
function Eligibility.RecordAcquisition(record, actor, internal)
  local input = type(record) == "table" and record or {}
  if internal ~= true and (not Dibs.Permissions or not Dibs.Permissions.Can or not Dibs.Permissions.Can("eligibility.history.add", actor)) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  local family = normalizeFamily(input.family or input.dibsType or input.semanticFamily)
  if family == "CATALYST" then return nil, "CATALYST_PERSONAL" end
  if not family or not input.playerName and not input.characterName then return nil, "INVALID_ACQUISITION" end
  if internal ~= true and input.confirmation ~= true then return nil, "CONFIRMATION_REQUIRED" end
  local targetSeason = currentSeason(input.seasonId)
  if not validSeason(targetSeason) then return nil, "SEASON_NOT_FOUND" end
  local state = ensureState()
  local identity = input.awardRef or input.evidenceId
  if identity and state.acquisitionIndex[tostring(identity)] then
    local existing = state.acquisitions[state.acquisitionIndex[tostring(identity)]]
    if existing then existing.idempotentReplay = true; return copy(existing) end
  end
  local characterName = input.characterName or input.playerName
  local acquisition = {
    acquisitionId = Dibs.NewId and Dibs.NewId("acquisition") or ("acquisition-" .. tostring(now())),
    seasonId = targetSeason, family = family, itemID = tonumber(input.itemID), itemLink = input.itemLink,
    itemName = input.itemName, difficulty = normalizeDifficulty(input.difficulty), slot = input.slot,
    tokenGroup = input.tokenGroup and string.upper(trim(input.tokenGroup)) or (input.classTokenGroup and string.upper(trim(input.classTokenGroup)) or nil), classID = input.classID,
    upgradeTrack = input.upgradeTrack or input.track, characterId = input.characterId or actorId(characterName),
    characterName = displayName(characterName), playerGroupId = input.playerGroupId or Eligibility.GetPlayerGroup(characterName, targetSeason),
    source = input.source or (internal and "rclootcouncil" or "officer"), awardRef = input.awardRef,
    evidenceId = input.evidenceId, acquiredAt = tonumber(input.acquiredAt) or now(), actorId = actorId(actor) or (internal and "rclootcouncil" or "unknown"),
    reason = input.reason or "Confirmed protected-loot acquisition",
  }
  if not acquisition.itemID or acquisition.itemID <= 0 then return nil, "INVALID_ITEM" end
  table.insert(state.acquisitions, acquisition)
  local index = #state.acquisitions
  if acquisition.awardRef then state.acquisitionIndex[tostring(acquisition.awardRef)] = index end
  if acquisition.evidenceId then state.acquisitionIndex[tostring(acquisition.evidenceId)] = index end
  appendAudit("eligibility.acquisition.record", actor, acquisition, acquisition.reason)
  return copy(acquisition)
end

function Eligibility.ConsumeException(decision)
  local state = ensureState()
  local probation = decision and decision.probation
  if not probation then return false end
  local exception = decision.probationException and state.exceptions[decision.probationException.exceptionId]
  if exception and (exception.status ~= "active" or (exception.expiresAt and now() > exception.expiresAt)
    or (exception.awardLimit and (tonumber(exception.awardsUsed) or 0) >= exception.awardLimit)) then
    exception = nil
  end
  exception = exception or exceptionFor(probation, decision)
  if not exception then return false end
  exception.awardsUsed = (tonumber(exception.awardsUsed) or 0) + 1
  if exception.awardLimit and exception.awardsUsed >= exception.awardLimit then exception.status = "consumed" end
  appendAudit("eligibility.exception.consume", decision.playerName, exception, exception.reason)
  return true
end

function Eligibility.GetSummary(playerName, seasonId)
  local targetSeason, name = currentSeason(seasonId), playerName or Dibs.GetPlayerName()
  local result = { seasonId = targetSeason, playerName = displayName(name), groupId = Eligibility.GetPlayerGroup(name, targetSeason), probation = Eligibility.GetProbation(name, targetSeason), policies = {} }
  for _, family in ipairs({ "TOKEN", "TOKEN_SET" }) do result.policies[family] = Eligibility.GetPolicy(targetSeason, family) end
  result.acquisitions = Eligibility.GetAcquisitions(name, targetSeason, nil)
  result.relationships = Eligibility.GetRelationshipStatus(name, targetSeason)
  return result
end
