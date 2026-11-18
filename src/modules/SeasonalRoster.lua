--[[
Module: Dibs.SeasonalRoster
Layer: Domain / guild-scoped seasonal roster
Purpose: Own seasonal raid enrollment, roster projections, and administrative
  review while delegating identity, accounting, authority, and transport to
  their existing domain modules.
Non-responsibilities: Character relationship ownership, ledger accounting,
  synchronization transport, and UI rendering.
Dependencies: Dibs.CoreAPI, Seasons, CharacterEligibility, Ledger, Permissions,
  FeatureRegistry, and SyncV2.
SavedVariables: Additive seasonal-roster subtree in the active guild bucket.
Combat safety: Data operations only; UI refreshes remain caller-controlled.
]]

local Dibs = _G.Dibs
Dibs.SeasonalRoster = Dibs.SeasonalRoster or {}

local Roster = Dibs.SeasonalRoster

Roster.SCHEMA_VERSION = 2
Roster.SYNC_ENTITY = "SEASONAL_ROSTER"

local MAX_NAME_LENGTH, MAX_DESCRIPTION_LENGTH, MAX_CATEGORIES = 80, 500, 16
local MAX_CATEGORY_NAME_LENGTH = 60
local MAX_RAID_RULES_LENGTH = 8000
local MAX_PROMOTION_POLICY_LENGTH = 4000
local VALID_REGISTRATION_STATES = { DRAFT = true, OPEN = true, CLOSED = true }
local VALID_RAID_DIFFICULTIES = { NORMAL = true, HEROIC = true, MYTHIC = true }
local VALID_LIFECYCLE_STATES = {
  DRAFT = true, REGISTRATION_OPEN = true, REVIEW = true, READY = true,
  ACTIVE = true, COMPLETED = true, ARCHIVED = true,
}
local VALID_LIFECYCLE_TRANSITIONS = {
  DRAFT = { REGISTRATION_OPEN = true, REVIEW = true },
  REGISTRATION_OPEN = { REVIEW = true },
  REVIEW = { REGISTRATION_OPEN = true, READY = true },
  READY = {},
  ACTIVE = { COMPLETED = true },
  COMPLETED = { ARCHIVED = true },
  ARCHIVED = {},
}
local SEASON_ARCHIVE_GRACE_SECONDS = 7 * 24 * 60 * 60
local currentActorKey, getStore, categoryForEnrollment
local mutationPermission, operationReplay, validateEnrollmentInput, actorKey
local nextRecordId, operationIdValid, hash, recordHash, appendAudit, normalizeRankAllocationSnapshot
local publicProjectionCache, publicProjectionCacheOrder = {}, {}
local reconciliationPreviews = {}
local adoptionPreviewToken = {}
local L = Dibs.L or {}

Roster.DEFAULT_CATEGORY_CATALOG = {
  { id = "CORE_RAIDER", name = L.SEASONAL_ROSTER_STATUS_CORE_RAIDER or "Core Raider",
    description = L.SEASONAL_ROSTER_STATUS_CORE_RAIDER_DESCRIPTION or "Reliable progression player who performs their role, follows directives and mechanics, meets role damage or healing expectations, arrives on time, and helps others improve. Core Raiders have progression raid-spot priority and the guild-bank/repair benefits described by guild policy.", active = true },
  { id = "RAIDER", name = L.SEASONAL_ROSTER_STATUS_RAIDER or "Raider",
    description = L.SEASONAL_ROSTER_STATUS_RAIDER_DESCRIPTION or "Player who wants to raid, can arrive on time, and wants to improve. This is the former AotC signup choice.", active = true },
  { id = "MEMBER", name = L.SEASONAL_ROSTER_STATUS_MEMBER or "Member",
    description = L.SEASONAL_ROSTER_STATUS_MEMBER_DESCRIPTION or "Active guild member who participates in some raids or guild runs; after five months inactive, the guild may demote the member.", active = true },
  { id = "INITIATE", name = L.SEASONAL_ROSTER_STATUS_INITIATE or "Initiate",
    description = L.SEASONAL_ROSTER_STATUS_INITIATE_DESCRIPTION or "New guild member; after five months inactive, the guild may remove the member.", active = true },
  { id = "ALT_OFFICER_ALT", name = L.SEASONAL_ROSTER_STATUS_ALT or "Alt / Officer Alt",
    description = L.SEASONAL_ROSTER_STATUS_ALT_DESCRIPTION or "Alternate character of a guild member or Officer. It should not be removed unless its Main leaves the guild.", active = true },
}

local function defaultCategoryName(id)
  for _, entry in ipairs(Roster.DEFAULT_CATEGORY_CATALOG) do
    if entry.id == id then return entry.name, entry.description end
  end
  return id, ""
end

local function normalizeCategoryCatalog(catalog, legacyCategories)
  local source = catalog
  if source == nil then source = legacyCategories end
  if source == nil then source = Roster.DEFAULT_CATEGORY_CATALOG end
  if type(source) ~= "table" then return nil, nil, "INVALID_INPUT" end
  local count = 0
  for key in pairs(source) do
    if type(key) ~= "number" or key < 1 or key > MAX_CATEGORIES or key ~= math.floor(key) then
      return nil, nil, "INVALID_INPUT"
    end
    count = count + 1
  end
  if count > MAX_CATEGORIES or #source ~= count then return nil, nil, "INVALID_INPUT" end
  local normalized, activeIds, seen = {}, {}, {}
  for index, raw in ipairs(source) do
    local entry
    if type(raw) == "string" then
      local id = (raw == "AOTC" or raw == "AoTC" or raw == "AotC") and "RAIDER" or raw
      local name, description = defaultCategoryName(id)
      entry = { id = id, name = name, description = description, active = true, version = 1 }
    elseif type(raw) == "table" then
      entry = Dibs.DeepCopy(raw)
    else
      return nil, nil, "INVALID_INPUT"
    end
    local id = type(entry.id) == "string" and entry.id:match("^%s*(.-)%s*$") or nil
    local name = type(entry.name) == "string" and entry.name:match("^%s*(.-)%s*$") or nil
    local description = entry.description == nil and "" or entry.description
    local active = entry.active ~= false
    local version = entry.version == nil and 1 or entry.version
    if not id or #id < 1 or #id > 40 or not id:match("^[%w_%-]+$") or seen[id]
      or not name or #name < 1 or #name > MAX_CATEGORY_NAME_LENGTH
      or type(description) ~= "string" or #description > MAX_DESCRIPTION_LENGTH
      or type(version) ~= "number" or version ~= math.floor(version) or version < 1
      or version >= 2147483647 then return nil, nil, "INVALID_INPUT" end
    seen[id] = true
    normalized[index] = { id = id, name = name, description = description,
      active = active, order = index, version = version }
    if active then activeIds[#activeIds + 1] = id end
  end
  return normalized, activeIds
end

local function categoryById(config, categoryId, includeInactive)
  local catalog = type(config) == "table" and config.categoryCatalog
  if type(catalog) ~= "table" then
    catalog = select(1, normalizeCategoryCatalog(nil, config and config.categories or {})) or {}
  end
  for _, entry in ipairs(catalog) do
    if entry.id == categoryId and (includeInactive or entry.active ~= false) then return entry end
  end
  if categoryId == "AOTC" or categoryId == "AoTC" or categoryId == "AotC" then
    for _, entry in ipairs(catalog) do
      if entry.id == "RAIDER" and (includeInactive or entry.active ~= false) then return entry end
    end
  end
  return nil
end

function Roster.GetCategoryCatalog(seasonId, revision)
  local store, reason = getStore()
  if not store then return nil, reason end
  local season = store.seasons[seasonId]
  if type(season) ~= "table" then return nil, "SEASON_NOT_FOUND" end
  revision = tonumber(revision) or tonumber(season.currentRevision)
  local config = type(revision) == "number" and revision >= 0 and revision == math.floor(revision)
    and season.revisions and season.revisions[tostring(revision)]
  if type(config) ~= "table" then return nil, "SEASON_REVISION_NOT_FOUND" end
  local catalog = config.categoryCatalog or select(1, normalizeCategoryCatalog(nil, config.categories or {})) or {}
  return Dibs.DeepCopy(catalog), nil, revision
end

function Roster.GetCategoryCatalogHistory(seasonId, limit)
  local store, reason = getStore()
  if not store then return nil, reason end
  local decision = Dibs.Permissions and Dibs.Permissions.Evaluate
    and Dibs.Permissions.Evaluate("season.rules.publish")
  if not decision or decision.allowed ~= true then return nil, "GUILD_ADMIN_REQUIRED" end
  if type(seasonId) ~= "string" or #seasonId > 96 then return nil, "INVALID_INPUT" end
  local season = store.seasons[seasonId]
  if type(season) ~= "table" then return nil, "SEASON_NOT_FOUND" end
  limit = math.max(1, math.min(20, math.floor(tonumber(limit) or 10)))
  local latest = tonumber(season.currentRevision) or 0
  local history = {}
  for revision = latest, math.max(1, latest - limit + 1), -1 do
    local record = season.revisions and season.revisions[tostring(revision)]
    if type(record) == "table" then
      history[#history + 1] = { revision = revision, action = record.action,
        reason = record.changeReason or record.description or record.name,
        updatedAt = record.updatedAt, updatedBy = record.updatedBy,
        catalog = Dibs.DeepCopy(record.categoryCatalog
          or select(1, normalizeCategoryCatalog(nil, record.categories or {})) or {}) }
    end
  end
  return history
end

-- Officer-only, bounded audit view of immutable season configuration revisions.
-- Enrollment records and private notes are intentionally excluded.
function Roster.GetSeasonRevisionHistory(seasonId, limit)
  local store, reason = getStore()
  if not store then return nil, reason end
  local decision = Dibs.Permissions and Dibs.Permissions.Evaluate
    and Dibs.Permissions.Evaluate("season.draft.edit")
  if not decision or decision.allowed ~= true then return nil, "GUILD_ADMIN_REQUIRED" end
  if type(seasonId) ~= "string" or #seasonId > 96 then return nil, "INVALID_INPUT" end
  local season = store.seasons[seasonId]
  if type(season) ~= "table" then return nil, "SEASON_NOT_FOUND" end
  limit = math.max(1, math.min(20, math.floor(tonumber(limit) or 10)))
  local latest = tonumber(season.currentRevision) or 0
  local history = {}
  for revision = latest, math.max(1, latest - limit + 1), -1 do
    local record = season.revisions and season.revisions[tostring(revision)]
    if type(record) == "table" then
      history[#history + 1] = {
        revision = revision, action = tostring(record.action or "UNKNOWN"),
        reason = tostring(record.changeReason or record.description or record.name or ""),
        updatedAt = tonumber(record.updatedAt) or 0,
        updatedBy = tostring(record.updatedBy or "UNKNOWN"),
        rulesRevision = tonumber(record.rulesRevision) or 1,
        lifecycleState = record.lifecycleState and tostring(record.lifecycleState) or nil,
        registrationState = record.registrationState and tostring(record.registrationState) or nil,
      }
    end
  end
  return history
end

function Roster.GetDefaultCategoryCatalog()
  local catalog = Dibs.DeepCopy(Roster.DEFAULT_CATEGORY_CATALOG)
  local normalized = normalizeCategoryCatalog(catalog)
  return normalized
end

local CLASS_ARMOR = {
  MAGE = "CLOTH", PRIEST = "CLOTH", WARLOCK = "CLOTH",
  DEMONHUNTER = "LEATHER", DRUID = "LEATHER", MONK = "LEATHER", ROGUE = "LEATHER",
  EVOKER = "MAIL", HUNTER = "MAIL", SHAMAN = "MAIL",
  DEATHKNIGHT = "PLATE", PALADIN = "PLATE", WARRIOR = "PLATE",
}

local function bumpRosterRevision(season)
  season.rosterRevision = math.min(2147483647, (tonumber(season.rosterRevision) or 0) + 1)
end

local function rosterClass(character, rosterClasses)
  local key = Dibs.Identity and Dibs.Identity.CanonicalMemberKey
    and Dibs.Identity.CanonicalMemberKey(character)
  local resolved = key and rosterClasses[key]
  if not resolved then return nil, nil, "UNKNOWN" end
  local classFile = type(resolved.classFileName) == "string" and string.upper(resolved.classFileName) or nil
  return resolved.className, classFile, CLASS_ARMOR[classFile] or "UNKNOWN"
end

local function wholeNumber(value)
  return type(value) == "number" and value == value and value >= 0 and value < math.huge and value == math.floor(value)
end

categoryForEnrollment = function(season, enrollment, currentConfig)
  local categoryId = enrollment and enrollment.categoryId
  if not categoryId then return nil end
  local sourceRevision = tonumber(enrollment.categorySeasonRevision)
  if wholeNumber(sourceRevision) then
    local source = season.revisions and season.revisions[tostring(sourceRevision)]
    return type(source) == "table" and categoryById(source, categoryId, true) or nil
  end
  -- Pre-catalog enrollments had no status snapshot. Resolve the last published
  -- definition known at their creation time when the immutable history permits.
  local createdAt = tonumber(enrollment.createdAt)
  local selected, selectedAt
  local latest = tonumber(season.currentRevision) or 0
  for revision = 1, latest do
    local source = season.revisions and season.revisions[tostring(revision)]
    local timestamp = type(source) == "table" and tonumber(source.updatedAt)
    local descriptor = type(source) == "table" and categoryById(source, categoryId, true)
    if descriptor and (not createdAt or not timestamp or timestamp <= createdAt)
      and (not selectedAt or not timestamp or timestamp >= selectedAt) then
      selected, selectedAt = descriptor, timestamp
    end
  end
  return selected or categoryById(currentConfig or {}, categoryId, true)
end

getStore = function()
  local registry = Dibs.FeatureRegistry
  if not registry or type(registry.RequireEnabled) ~= "function" then return nil, "MODULE_DISABLED" end
  local enabled = registry.RequireEnabled("seasonalRoster", { silent = true })
  if enabled ~= true then return nil, "MODULE_DISABLED" end

  local status = Dibs.GetPersistenceStatus and Dibs.GetPersistenceStatus() or nil
  if type(status) ~= "table" or status.readOnly == true then return nil, "PERSISTENCE_READ_ONLY" end
  if type(IsInGuild) ~= "function" or not IsInGuild()
    or type(Dibs.GetGuildKey) ~= "function" then return nil, "GUILD_UNAVAILABLE" end

  local ok, db = pcall(Dibs.GetDB)
  if not ok or type(db) ~= "table" then return nil, "GUILD_UNAVAILABLE" end
  local store = db.seasonalRoster
  if type(store) ~= "table" or store.schema ~= Roster.SCHEMA_VERSION then
    return nil, "ROSTER_SCHEMA_UNSUPPORTED"
  end
  if type(store.seasons) ~= "table" or type(store.seasonAliases) ~= "table"
    or type(store.seasonAliases.records) ~= "table" or type(store.auditLog) ~= "table"
    or type(store.auditOperationIndex) ~= "table" or type(store.operations) ~= "table"
    or not wholeNumber(store.nextId) or store.nextId < 1 then
    return nil, "ROSTER_SCHEMA_UNSUPPORTED"
  end
  return store
end

function Roster.CheckReady()
  local store, reason = getStore()
  if not store then return false, reason end
  return true
end

-- Legacy Dibs seasons can exist before the guild creates its first seasonal
-- roster season. Allocation reconciliation is meaningful only after that
-- explicit season setup has happened.
function Roster.HasConfiguredSeason(dbOverride)
  local store
  if type(dbOverride) == "table" then
    store = dbOverride.seasonalRoster
    if type(store) ~= "table" or store.schema ~= Roster.SCHEMA_VERSION
      or type(store.seasons) ~= "table" then
      return false
    end
  else
    local reason
    store, reason = getStore()
    if not store then return nil, reason end
  end
  for _, season in pairs(store.seasons) do
    if type(season) == "table" and type(season.revisions) == "table"
      and type(season.revisions[tostring(tonumber(season.currentRevision) or "")]) == "table" then
      return true
    end
  end
  return false
end

local function seasonLifecycle(config, now)
  config = type(config) == "table" and config or {}
  now = tonumber(now) or ((Dibs.GetTimestamp and Dibs.GetTimestamp()) or time())
  local registrationStatus = config.registrationState
  if registrationStatus == "OPEN" then
    if (config.startAt and now >= config.startAt)
      or (config.endAt and now >= config.endAt)
      or (config.registrationEndAt and now >= config.registrationEndAt) then
      registrationStatus = "CLOSED"
    elseif config.registrationStartAt and now < config.registrationStartAt then
      registrationStatus = "SCHEDULED"
    end
  end
  local archiveAt = config.endAt and (config.endAt + SEASON_ARCHIVE_GRACE_SECONDS) or nil
  local seasonStatus = config.lifecycleState
  if seasonStatus == "REVIEW" or seasonStatus == "READY" then
    local db = Dibs.GetDB()
    local saved = db.seasonalRoster and db.seasonalRoster.seasons[config.seasonId]
    if saved and saved.activationAdopted == true then seasonStatus = "ACTIVE" end
  end
  if not VALID_LIFECYCLE_STATES[seasonStatus] then
    return {
      registrationStatus = registrationStatus,
      seasonStatus = nil,
      lifecycleState = nil,
      archiveAt = archiveAt,
      readOnly = true,
    }
  end
  if seasonStatus == "COMPLETED" and archiveAt and now >= archiveAt then
    seasonStatus = "ARCHIVED"
  elseif seasonStatus == "ACTIVE" and config.endAt and now >= config.endAt then
    seasonStatus = now >= archiveAt and "ARCHIVED" or "COMPLETED"
  end
  return {
    registrationStatus = registrationStatus,
    seasonStatus = seasonStatus,
    lifecycleState = seasonStatus,
    archiveAt = archiveAt,
    readOnly = seasonStatus == "ARCHIVED",
  }
end

local function seasonReadOnlyReason(config)
  local lifecycle = seasonLifecycle(config)
  if not lifecycle.readOnly then return nil end
  return lifecycle.seasonStatus == "ARCHIVED" and "SEASON_ARCHIVED" or "SEASON_READ_ONLY"
end

function Roster.GetSeasonLifecycle(seasonId, now)
  local store, reason = getStore()
  if not store then return nil, reason end
  local season = store.seasons[seasonId]
  if type(season) ~= "table" then return nil, "SEASON_NOT_FOUND" end
  local config = season.revisions and season.revisions[tostring(season.currentRevision)]
  if type(config) ~= "table" then return nil, "ROSTER_SCHEMA_UNSUPPORTED" end
  local lifecycle = seasonLifecycle(config, now)
  if config.lifecycleState == "ACTIVE" and season.activationAdopted ~= true then
    lifecycle.seasonStatus, lifecycle.lifecycleState = "READY", "READY"
  end
  lifecycle.seasonId = seasonId
  lifecycle.registrationStartAt = config.registrationStartAt
  lifecycle.registrationEndAt = config.registrationEndAt
  lifecycle.startAt = config.startAt
  lifecycle.endAt = config.endAt
  return lifecycle
end

function Roster.ValidateLifecycleTransition(fromState, toState, record, now)
  if not VALID_LIFECYCLE_STATES[fromState] or not VALID_LIFECYCLE_STATES[toState] then
    return false, "INVALID_TRANSITION"
  end
  if toState == "ACTIVE" then return false, "ACTIVATION_NOT_IMPLEMENTED" end
  if not VALID_LIFECYCLE_TRANSITIONS[fromState][toState] then return false, "INVALID_TRANSITION" end
  record = type(record) == "table" and record or {}
  now = tonumber(now) or ((Dibs.GetTimestamp and Dibs.GetTimestamp()) or time())
  if toState == "REGISTRATION_OPEN" then
    if not wholeNumber(record.startAt) or not wholeNumber(record.registrationStartAt) then
      return false, "SEASON_DATES_REQUIRED"
    end
    if now >= record.startAt or (record.endAt and now >= record.endAt) then
      return false, "SEASON_ENDED"
    end
    if record.registrationEndAt and now >= record.registrationEndAt then
      return false, "REGISTRATION_CLOSED"
    end
  elseif toState == "COMPLETED" then
    if record.startAt and now < record.startAt then return false, "SEASON_NOT_STARTED" end
    if record.endAt and now < record.endAt then return false, "SEASON_NOT_ENDED" end
  elseif toState == "ARCHIVED" then
    local archiveAt = record.endAt and record.endAt + SEASON_ARCHIVE_GRACE_SECONDS
    if not archiveAt or now < archiveAt then return false, "ARCHIVE_GRACE_PERIOD" end
  end
  return true
end

function Roster.ListSeasons()
  local store, reason = getStore()
  if not store then return nil, reason end
  local seasons = {}
  for seasonId, season in pairs(store.seasons) do
    local revision = type(season) == "table" and tonumber(season.currentRevision)
    local record = revision and season.revisions and season.revisions[tostring(revision)]
    if type(record) == "table" then
      local activeCount = 0
      for _, enrollment in pairs(season.enrollments or {}) do
        if type(enrollment) == "table" and enrollment.status == "ACTIVE" then activeCount = activeCount + 1 end
      end
      seasons[#seasons + 1] = { seasonId = seasonId, revision = revision, name = record.name,
        description = record.description, raidRules = record.raidRules or "",
        promotionPolicy = record.promotionPolicy or "", rulesRevision = record.rulesRevision or 1,
        registrationState = record.registrationState,
        persistedLifecycleState = record.lifecycleState,
    categories = Dibs.DeepCopy(record.categories or {}),
        categoryCatalog = Dibs.DeepCopy(record.categoryCatalog or select(1,
          normalizeCategoryCatalog(nil, record.categories or {})) or {}), enrollmentCount = activeCount,
        startAt = record.startAt, endAt = record.endAt,
        registrationStartAt = record.registrationStartAt, registrationEndAt = record.registrationEndAt,
        lifecycle = seasonLifecycle(record),
        raidSchedule = Dibs.DeepCopy(record.raidSchedule or {}),
        raidDifficulties = Dibs.DeepCopy(record.raidDifficulties or {}),
        noRankPolicy = Dibs.DeepCopy(record.noRankPolicy or { mode = "UNCONFIGURED" }),
        identitySeasonId = record.identitySeasonId }
    end
  end
  table.sort(seasons, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.seasonId < b.seasonId
  end)
  return seasons
end

function Roster.GetOwnEnrollments(seasonId)
  local store, reason = getStore()
  if not store then return nil, reason end
  local ownerKey, identityReason = currentActorKey()
  if not ownerKey then return nil, identityReason end
  local season = store.seasons[seasonId]
  if type(season) ~= "table" then return nil, "SEASON_NOT_FOUND" end
  local rows = {}
  for _, enrollment in pairs(season.enrollments or {}) do
    if type(enrollment) == "table" and enrollment.ownerCharacterKey == ownerKey
      and enrollment.status ~= "REMOVED" then
      rows[#rows + 1] = Dibs.DeepCopy(enrollment)
    end
  end
  table.sort(rows, function(a, b) return tostring(a.character) < tostring(b.character) end)
  return rows
end

function Roster.GetOwnEnrollment(seasonId)
  local rows, reason = Roster.GetOwnEnrollments(seasonId)
  if not rows then return nil, reason end
  if rows[1] then return rows[1] end
  return nil, "ENROLLMENT_NOT_FOUND"
end

function Roster.GetOfficerEnrollments(seasonId)
  local store, reason = getStore()
  if not store then return nil, reason end
  local decision = Dibs.Permissions and Dibs.Permissions.Evaluate
    and Dibs.Permissions.Evaluate("season.enrollment.review")
  if not decision or decision.allowed ~= true then return nil, "GUILD_ADMIN_REQUIRED" end
  local season = store.seasons[seasonId]
  if type(season) ~= "table" then return nil, "SEASON_NOT_FOUND" end
  local activeConfig = season.revisions and season.revisions[tostring(season.currentRevision)] or {}
  local rows = {}
  for _, enrollment in pairs(season.enrollments or {}) do
    if type(enrollment) == "table" then
      local category = categoryForEnrollment(season, enrollment, activeConfig)
      rows[#rows + 1] = { enrollmentId = enrollment.enrollmentId, character = enrollment.character,
        categoryId = enrollment.categoryId, categoryName = enrollment.categoryName or category and category.name
          or enrollment.categoryId,
        categoryDescription = enrollment.categoryDescription or category and category.description or "",
        categoryVersion = enrollment.categoryVersion or category and category.version or 1,
        primarySpec = enrollment.primarySpec,
        secondarySpec = enrollment.secondarySpec, roles = Dibs.DeepCopy(enrollment.roles or {}),
        requestedPath = enrollment.requestedPath or "STANDARD",
        corePromotionPolicyRevision = enrollment.corePromotionPolicyRevision,
        status = enrollment.status, revision = enrollment.revision,
        updatedAt = enrollment.updatedAt, updatedBy = enrollment.updatedBy }
    end
  end
  table.sort(rows, function(a, b) return tostring(a.character) < tostring(b.character) end)
  return rows
end

-- Read-only activation planning. The preview uses only approved enrollments,
-- the selected Main for each explicitly linked person, current guild ranks,
-- and explicit per-season allocations. It never initializes or changes rank
-- rules, the active season, or any ledger.
function Roster.PreviewActivation(seasonId, actor, purpose, baseline)
  local store, storeReason = getStore()
  if not store then return nil, storeReason end
  local allowed, permissionReason
  if purpose == adoptionPreviewToken then
    local resolved = Dibs.Identity.ResolveRosterMember(actor)
    allowed = resolved and resolved.status == "RESOLVED" and (resolved.role == "gm" or resolved.role == "officer")
    permissionReason = "GUILD_ADMIN_REQUIRED"
  else allowed, permissionReason = mutationPermission("season.activate", actor) end
  if not allowed then return nil, permissionReason end
  if type(seasonId) ~= "string" or #seasonId < 1 or #seasonId > 96 then return nil, "INVALID_INPUT" end
  local season = store.seasons[seasonId]
  if type(season) ~= "table" then return nil, "SEASON_NOT_FOUND" end
  local revision = baseline and baseline.dependencies.seasonRevision or tonumber(season.currentRevision)
  local config = revision and season.revisions and season.revisions[tostring(revision)]
  if type(config) ~= "table" then return nil, "ROSTER_SCHEMA_UNSUPPORTED" end

  local blockers, rows, excluded = {}, {}, {}
  local function block(code, character)
    blockers[#blockers + 1] = { code = code, character = character }
  end
  local lifecycle = config.lifecycleState
  local drift = purpose == "RECONCILIATION" and season.activationAdopted == true
  if not drift and lifecycle ~= "REVIEW" and lifecycle ~= "READY" then block("SEASON_NOT_IN_REVIEW") end
  if drift and seasonLifecycle(config).lifecycleState ~= "ACTIVE" then block("SEASON_NOT_ACTIVE") end
  if config.registrationState ~= "CLOSED" then block("REGISTRATION_NOT_CLOSED") end

  local rosterSnapshot, rosterReason = Dibs.Identity and Dibs.Identity.GetRosterSnapshot
    and Dibs.Identity.GetRosterSnapshot()
  local rosterState = Dibs.Identity and Dibs.Identity.GetRosterState and Dibs.Identity.GetRosterState()
  if type(rosterSnapshot) ~= "table" or type(rosterState) ~= "table" or rosterState.fresh ~= true then
    block("GUILD_ROSTER_UNAVAILABLE")
    rosterSnapshot = {}
  end
  local guildMembers = {}
  for _, member in ipairs(rosterSnapshot) do
    if type(member) == "table" and type(member.memberKey) == "string" then
      guildMembers[member.memberKey] = { rankIndex = tonumber(member.rankIndex), rankName = member.rankName }
    end
  end
  if purpose == adoptionPreviewToken then
    guildMembers = {}
    for _, snapshot in pairs(season.activationIdentities or {}) do
      if snapshot.rankIndex ~= nil then guildMembers[snapshot.mainCharacterKey] = {
        rankIndex = snapshot.rankIndex, rankName = snapshot.rankName } end
    end
  end

  local eligibility = Dibs.CharacterEligibility
  local db = Dibs.GetDB()
  local eligibilityState = type(db.characterEligibility) == "table" and db.characterEligibility or {}
  local eligibilityRevision = tonumber(eligibilityState.revision) or 0
  local identitySeasonId = config.identitySeasonId or seasonId
  local grouped, activeCount, approvedEnrollmentSnapshot = {}, 0, {}
  local enrollmentSource = season.enrollments or {}
  if baseline then
    enrollmentSource = {}
    for id, wantedRevision in pairs(baseline.enrollments) do
      enrollmentSource[id] = season.enrollmentRevisions and season.enrollmentRevisions[id]
        and season.enrollmentRevisions[id][tostring(wantedRevision)]
    end
  end
  for _, enrollment in pairs(enrollmentSource) do
    if type(enrollment) == "table" and enrollment.status == "ACTIVE"
      and (not drift or (season.activationCohort and season.activationCohort[enrollment.enrollmentId])) then
      activeCount = activeCount + 1
      approvedEnrollmentSnapshot[#approvedEnrollmentSnapshot + 1] = {
        enrollmentId = enrollment.enrollmentId, revision = tonumber(enrollment.revision) or 0,
        characterKey = enrollment.characterKey, categoryId = enrollment.categoryId,
        categoryVersion = enrollment.categoryVersion, primarySpec = enrollment.primarySpec,
        secondarySpec = enrollment.secondarySpec, roles = enrollment.roles,
        classFileName = enrollment.classFileName, armorType = enrollment.armorType,
      }
      local projection = eligibility and eligibility.GetPersonProjection
        and eligibility.GetPersonProjection(enrollment.character, identitySeasonId)
      if purpose == adoptionPreviewToken then
        for _, snapshot in pairs(season.activationIdentities or {}) do
          for _, memberKey in ipairs(snapshot.memberKeys) do
            if memberKey == enrollment.characterKey then
              projection = { groupId = snapshot.personGroupId, mainCharacterKey = snapshot.mainCharacterKey,
                memberKeys = snapshot.memberKeys }
            end
          end
        end
      end
      if type(projection) ~= "table" or type(projection.groupId) ~= "string" then
        block("PERSON_IDENTITY_UNAVAILABLE", enrollment.character)
      else
        local key = projection.groupId
        local group = grouped[key] or { mainKey = projection.mainCharacterKey or enrollment.characterKey,
          projection = projection, mainEnrollments = {}, active = {} }
        grouped[key] = group
        group.active[#group.active + 1] = enrollment
        if enrollment.characterKey == group.mainKey then
          group.mainEnrollments[#group.mainEnrollments + 1] = enrollment
        end
      end
    end
  end
  if activeCount == 0 then block("NO_APPROVED_PARTICIPANTS") end
  table.sort(approvedEnrollmentSnapshot, function(a, b)
    return tostring(a.enrollmentId or a.characterKey or "") < tostring(b.enrollmentId or b.characterKey or "")
  end)

  local allocationSnapshot = type(config.rankAllocationSnapshot) == "table"
    and config.rankAllocationSnapshot or nil
  local rankRules = allocationSnapshot and allocationSnapshot.rules or {}
  if not allocationSnapshot then block("RANK_ALLOCATION_NOT_PUBLISHED") end
  if allocationSnapshot and (allocationSnapshot.schema ~= 1
    or hash(rankRules) ~= allocationSnapshot.contentHash) then
    block("RANK_ALLOCATION_SNAPSHOT_INVALID")
    rankRules = {}
  end
  local ledger = Dibs.Ledger
  local activeLedgerId = ledger and ledger.GetActiveLedgerId and ledger.GetActiveLedgerId()
  local ledgerRevision = activeLedgerId and ledger.GetDataRevision and ledger.GetDataRevision(activeLedgerId) or 0
  -- Main/Alt balance review applies to the currently active season's legacy
  -- balances. The new season starts with its own allocation and must not
  -- silently inherit the prior season's balance.
  local balanceSeasonId = type(db.currentSeasonId) == "string" and db.currentSeasonId ~= ""
    and db.currentSeasonId or identitySeasonId
  local noRankPolicy = type(config.noRankPolicy) == "table" and config.noRankPolicy or { mode = "UNCONFIGURED" }
  local identities = {}
  local groupKeys = {}
  for key in pairs(grouped) do groupKeys[#groupKeys + 1] = key end
  table.sort(groupKeys)
  for _, groupKey in ipairs(groupKeys) do
    local group = grouped[groupKey]
    if #group.mainEnrollments ~= 1 then
      block(#group.mainEnrollments == 0 and "SELECTED_MAIN_NOT_APPROVED" or "DUPLICATE_MAIN_ENROLLMENT",
        group.active[1] and group.active[1].character)
    else
      local enrollment = group.mainEnrollments[1]
      local person = group.projection
      identities[#identities + 1] = { personGroupId = groupKey, mainCharacterKey = person.mainCharacterKey,
        memberKeys = Dibs.DeepCopy(person.memberKeys) }
      if not drift and purpose ~= adoptionPreviewToken and person and type(person.memberKeys) == "table" and #person.memberKeys > 1 then
        if not ledger or type(ledger.GetBalance) ~= "function"
          or type(ledger.GetPendingDibReservations) ~= "function" or not activeLedgerId then
          block("PERSON_BALANCE_SYNC_UNAVAILABLE", enrollment.character)
        else
          for _, memberKey in ipairs(person.memberKeys) do
            if memberKey ~= person.mainCharacterKey then
              local memberName = person.names and person.names[memberKey] or memberKey
              local balance = tonumber(ledger.GetBalance(memberName, balanceSeasonId, activeLedgerId))
              local reservations = tonumber(ledger.GetPendingDibReservations(memberName, balanceSeasonId, activeLedgerId))
              if balance == nil or balance ~= balance or math.abs(balance) == math.huge then
                block("PERSON_BALANCE_SYNC_UNAVAILABLE", enrollment.character)
              elseif reservations == nil or reservations ~= reservations or math.abs(reservations) == math.huge then
                block("PERSON_BALANCE_SYNC_UNAVAILABLE", enrollment.character)
              elseif reservations > 0 then
                block("PERSON_BALANCE_RESERVATIONS_PENDING", enrollment.character)
              elseif balance ~= 0 then
                block("PERSON_BALANCE_RECONCILIATION_REQUIRED", enrollment.character)
              end
            end
          end
        end
      end
      local member = guildMembers[enrollment.characterKey]
      local allocation, rankName, allocationSource
      if member then
        local rankIndex = member.rankIndex
        local rule = rankIndex and rankRules[tostring(rankIndex)]
        if not rule then
          block("RANK_ALLOCATION_UNCONFIGURED", enrollment.character)
        elseif rule.enabled ~= true then
          block("RANK_ALLOCATION_DISABLED", enrollment.character)
        elseif not wholeNumber(rule.allocation) or rule.allocation > 100000 then
          block("RANK_ALLOCATION_INVALID", enrollment.character)
        else
          allocation, rankName, allocationSource = rule.allocation, member.rankName or rule.rankName, "GUILD_RANK"
        end
      elseif noRankPolicy.mode == "EXCLUDE" then
        excluded[#excluded + 1] = { character = enrollment.character, reason = "NO_GUILD_RANK_EXCLUDED" }
      elseif noRankPolicy.mode == "FIXED" and wholeNumber(noRankPolicy.allocation)
        and noRankPolicy.allocation <= 100000 then
        allocation, allocationSource = noRankPolicy.allocation, "SEASON_NO_RANK_POLICY"
      elseif noRankPolicy.mode == "FIXED" then
        block("NO_RANK_POLICY_INVALID", enrollment.character)
      else
        block("NO_RANK_POLICY_UNCONFIGURED", enrollment.character)
      end
      if allocation ~= nil then
        rows[#rows + 1] = { character = enrollment.character, characterKey = enrollment.characterKey,
          categoryId = enrollment.categoryId, categoryVersion = enrollment.categoryVersion,
          personGroupId = groupKey, rankIndex = member and member.rankIndex or nil, rankName = rankName,
          allocation = allocation, allocationSource = allocationSource }
      end
      for _, alternate in ipairs(group.active) do
        if alternate.characterKey ~= enrollment.characterKey then
          excluded[#excluded + 1] = { character = alternate.character, reason = "ALT_NOT_COUNTED" }
        end
      end
    end
  end
  table.sort(rows, function(a, b) return a.characterKey < b.characterKey end)
  table.sort(excluded, function(a, b)
    if a.character ~= b.character then return a.character < b.character end
    return a.reason < b.reason
  end)
  table.sort(blockers, function(a, b)
    if a.code ~= b.code then return a.code < b.code end
    return tostring(a.character or "") < tostring(b.character or "")
  end)
  local currentSeasonConfigHash = type(config.contentHash) == "string" and config.contentHash or recordHash(config)
  local dependencies = {
    schema = 1, seasonId = seasonId, seasonRevision = revision,
    seasonConfigHash = currentSeasonConfigHash,
    rosterRevision = tonumber(season.rosterRevision) or 0,
    approvedRosterHash = hash(approvedEnrollmentSnapshot),
    allocationRowsHash = hash(rows), identityRevision = eligibilityRevision,
    identityHash = hash(identities),
    rosterGeneration = type(rosterState) == "table" and rosterState.generation or 0,
    guildRosterHash = hash((function()
      local ranks = {}
      for _, row in ipairs(rows) do ranks[row.characterKey] = { rankIndex = row.rankIndex, rankName = row.rankName } end
      return ranks
    end)()), rankRulesHash = hash(allocationSnapshot),
    noRankPolicyHash = hash(noRankPolicy), activeSeasonId = db.currentSeasonId,
    sourceLedgerId = activeLedgerId, sourceLedgerRevision = tonumber(ledgerRevision) or 0,
    balanceSeasonId = balanceSeasonId,
  }
  if not dependencies.seasonConfigHash or not dependencies.approvedRosterHash
    or not dependencies.allocationRowsHash or not dependencies.guildRosterHash
    or not dependencies.rankRulesHash or not dependencies.noRankPolicyHash then
    return nil, "HASH_UNAVAILABLE"
  end
  local fingerprint = hash({ dependencies = dependencies, rows = rows,
    excluded = excluded, blockers = blockers })
  if not fingerprint then return nil, "HASH_UNAVAILABLE" end
  return { seasonId = seasonId, seasonRevision = revision,
    rosterRevision = tonumber(season.rosterRevision) or 0,
    eligibilityRevision = eligibilityRevision,
    rosterGeneration = type(rosterState) == "table" and rosterState.generation or 0,
    sourceLedgerId = activeLedgerId, sourceLedgerRevision = tonumber(ledgerRevision) or 0,
    balanceSeasonId = balanceSeasonId,
    dependencies = dependencies,
    previewId = fingerprint, ready = #blockers == 0,
    participantCount = #rows, totalAllocation = (function()
      local total = 0
      for _, row in ipairs(rows) do total = total + row.allocation end
      return total
    end)(), rows = rows, excluded = excluded, blockers = blockers,
    lifecycleState = lifecycle, identities = identities, noRankPolicy = Dibs.DeepCopy(noRankPolicy),
    rankAllocationSnapshot = allocationSnapshot and Dibs.DeepCopy(allocationSnapshot) or nil }
end

-- Prepare a canonical, read-only activation artifact. This does not persist or
-- activate anything; it binds the approved roster and published allocation
-- snapshot to the exact revisions observed by PreviewActivation.
function Roster.PrepareActivationManifest(seasonId, previewId, operationId, actor)
  if not operationIdValid(operationId) then return nil, "INVALID_INPUT" end
  if type(previewId) ~= "string" or #previewId > 128 then return nil, "INVALID_INPUT" end
  local preview, previewReason = Roster.PreviewActivation(seasonId, actor)
  if not preview then return nil, previewReason end
  if not preview.ready then return nil, "ACTIVATION_BLOCKED", preview end
  if preview.previewId ~= previewId then return nil, "STALE_ACTIVATION_PREVIEW", preview end
  local preparedBy = actorKey(actor)
  if not preparedBy then return nil, "AUTHORITY_UNAVAILABLE" end
  local identity = {
    schema = 1, operationId = operationId, seasonId = seasonId,
    previewId = preview.previewId, preparedBy = preparedBy,
  }
  local manifestId = hash(identity)
  if not manifestId then return nil, "HASH_UNAVAILABLE" end
  local manifest = {
    schema = 1, recordClass = "SEASON_ACTIVATION_MANIFEST", state = "PREPARED",
    manifestId = manifestId, operationId = operationId, seasonId = seasonId,
    previewId = preview.previewId, dependencies = Dibs.DeepCopy(preview.dependencies),
    rows = Dibs.DeepCopy(preview.rows), excluded = Dibs.DeepCopy(preview.excluded),
    preparedBy = preparedBy,
  }
  manifest.contentHash = hash(manifest)
  if not manifest.contentHash then return nil, "HASH_UNAVAILABLE" end
  return manifest
end

-- Revalidate a prepared artifact against current authoritative inputs before a
-- future commit step. Callers must still implement the atomic ledger/manifest
-- publication; validation alone is not activation.
function Roster.ValidateActivationManifest(manifest, actor)
  if type(manifest) ~= "table" or manifest.schema ~= 1
    or manifest.recordClass ~= "SEASON_ACTIVATION_MANIFEST" or manifest.state ~= "PREPARED"
    or type(manifest.seasonId) ~= "string" or type(manifest.previewId) ~= "string"
    or not operationIdValid(manifest.operationId) or type(manifest.preparedBy) ~= "string"
    or type(manifest.dependencies) ~= "table" or type(manifest.rows) ~= "table"
    or type(manifest.excluded) ~= "table" then
    return false, "INVALID_ACTIVATION_MANIFEST"
  end
  local allowedFields = { schema = true, recordClass = true, state = true, manifestId = true,
    operationId = true, seasonId = true, previewId = true, dependencies = true, rows = true,
    excluded = true, preparedBy = true, contentHash = true }
  for key in pairs(manifest) do
    if not allowedFields[key] then return false, "INVALID_ACTIVATION_MANIFEST" end
  end
  local allowed, permissionReason = mutationPermission("season.activate", actor)
  if not allowed then return false, permissionReason end
  local candidate = Dibs.DeepCopy(manifest)
  local contentHash = candidate.contentHash
  candidate.contentHash = nil
  if type(contentHash) ~= "string" or hash(candidate) ~= contentHash then
    return false, "ACTIVATION_MANIFEST_HASH_MISMATCH"
  end
  local identityHash = hash({ schema = 1, operationId = manifest.operationId,
    seasonId = manifest.seasonId, previewId = manifest.previewId, preparedBy = manifest.preparedBy })
  if not identityHash or manifest.manifestId ~= identityHash then
    return false, "ACTIVATION_MANIFEST_ID_MISMATCH"
  end
  local boundPreviewId = hash({ dependencies = manifest.dependencies, rows = manifest.rows,
    excluded = manifest.excluded, blockers = {} })
  if not boundPreviewId or boundPreviewId ~= manifest.previewId then
    return false, "ACTIVATION_MANIFEST_CONTENT_MISMATCH"
  end
  local current, currentReason = Roster.PreviewActivation(manifest.seasonId, actor)
  if not current then return false, currentReason end
  if not current.ready then return false, "ACTIVATION_BLOCKED", current end
  if current.previewId ~= manifest.previewId then return false, "STALE_ACTIVATION_MANIFEST", current end
  return true, "ACTIVATION_MANIFEST_CURRENT", current
end

function Roster.AdminUpdateEnrollment(seasonId, enrollmentId, patch, expectedRevision, reason, operationId, actor)
  local store, storeReason = getStore()
  if not store then return { ok = false, code = storeReason } end
  local allowed, permissionReason = mutationPermission("season.enrollment.review", actor)
  if not allowed then return { ok = false, code = permissionReason } end
  reason = type(reason) == "string" and reason:match("^%s*(.-)%s*$") or ""
  if type(seasonId) ~= "string" or #seasonId > 96 or type(enrollmentId) ~= "string" or #enrollmentId > 96
    or type(patch) ~= "table" or not wholeNumber(expectedRevision) or not operationIdValid(operationId)
    or #reason < 1 or #reason > MAX_DESCRIPTION_LENGTH then
    return { ok = false, code = #reason < 1 and "REASON_REQUIRED" or "INVALID_INPUT" }
  end
  local authorKey = actorKey(actor)
  if not authorKey then return { ok = false, code = "AUTHORITY_UNAVAILABLE" } end
  local season = store.seasons[seasonId]
  local current = type(season) == "table" and season.enrollments and season.enrollments[enrollmentId]
  if type(current) ~= "table" then return { ok = false, code = "ENROLLMENT_NOT_FOUND" } end
  local activeConfig = season.revisions and season.revisions[tostring(season.currentRevision)]
  if type(activeConfig) ~= "table" then return { ok = false, code = "ROSTER_SCHEMA_UNSUPPORTED" } end
  local readOnlyReason = seasonReadOnlyReason(activeConfig)
  if readOnlyReason then return { ok = false, code = readOnlyReason } end
  if tonumber(current.revision) ~= expectedRevision or expectedRevision >= 2147483647 then
    if expectedRevision >= 2147483647 then return { ok = false, code = "INVALID_INPUT" } end
  end
  local config = season.revisions and season.revisions[tostring(season.currentRevision)]
  if type(config) ~= "table" then return { ok = false, code = "ROSTER_SCHEMA_UNSUPPORTED" } end
  local input = { character = patch.character or current.character, categoryId = patch.categoryId or current.categoryId,
    primarySpec = patch.primarySpec or current.primarySpec, secondarySpec = patch.secondarySpec,
    roles = patch.roles or current.roles, requestedPath = patch.requestedPath or current.requestedPath }
  if patch.secondarySpec == nil and patch.keepSecondarySpec == true then input.secondarySpec = current.secondarySpec end
  local valid, normalized = validateEnrollmentInput(input, config)
  if not valid then return { ok = false, code = normalized } end
  if normalized.categoryId == "CORE_RAIDER" and normalized.requestedPath ~= "CORE_PROGRESSION" then
    return { ok = false, code = "CORE_PROMOTION_NOT_ELIGIBLE" }
  end
  local nextStatus = patch.status == nil and current.status or patch.status
  if nextStatus ~= "PENDING_REVIEW" and nextStatus ~= "ACTIVE" and nextStatus ~= "REJECTED"
    and nextStatus ~= "WITHDRAWN" and nextStatus ~= "REMOVED" then
    return { ok = false, code = "INVALID_INPUT" }
  end
  local isCorePromotion = normalized.categoryId == "CORE_RAIDER" and current.categoryId ~= "CORE_RAIDER"
  if isCorePromotion and (current.status ~= "ACTIVE" or current.requestedPath ~= "CORE_PROGRESSION") then
    return { ok = false, code = "CORE_PROMOTION_NOT_ELIGIBLE" }
  end
  for id, candidate in pairs(season.enrollments or {}) do
    if id ~= enrollmentId and candidate.characterKey == normalized.characterKey
      and nextStatus ~= "REMOVED" and candidate.status ~= "REMOVED" then
      return { ok = false, code = "CHARACTER_ALREADY_ENROLLED" }
    end
  end
  local fingerprint = hash({ seasonId = seasonId, enrollmentId = enrollmentId, patch = {
      character = normalized.character, categoryId = normalized.categoryId, primarySpec = normalized.primarySpec,
      secondarySpec = normalized.secondarySpec, roles = normalized.roles, status = nextStatus },
    requestedPath = normalized.requestedPath,
    expectedRevision = expectedRevision, reason = reason, actorKey = authorKey })
  if not fingerprint then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local replay = operationReplay(store, operationId, fingerprint)
  if replay then return replay end
  if tonumber(current.revision) ~= expectedRevision then return { ok = false, code = "STALE_REVISION" } end
  local staged = Dibs.DeepCopy(store)
  local record = staged.seasons[seasonId].enrollments[enrollmentId]
  local previousHash, nextRevision = record.contentHash or "GENESIS", expectedRevision + 1
  record.character, record.characterKey = normalized.character, normalized.characterKey
  record.categoryId, record.categoryName = normalized.categoryId, normalized.categoryName
  record.categoryDescription, record.categoryVersion = normalized.categoryDescription, normalized.categoryVersion
  record.categorySeasonRevision = normalized.categorySeasonRevision
  record.requestedPath = normalized.requestedPath
  record.primarySpec, record.secondarySpec = normalized.primarySpec, normalized.secondarySpec
  record.roles, record.status = normalized.roles, nextStatus
  record.revision, record.parentRevision, record.parentHash = nextRevision, expectedRevision, previousHash
  record.updatedAt = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time()
  record.updatedBy, record.operationId, record.action, record.changeReason = authorKey, operationId,
    isCorePromotion and "CORE_PROMOTION_APPROVED" or "ENROLLMENT_ADMIN_CORRECTED", reason
  if isCorePromotion then
    record.corePromotionPolicyRevision = tonumber(activeConfig.rulesRevision) or 1
    record.corePromotionReviewedBy, record.corePromotionReviewedAt = authorKey, record.updatedAt
    record.corePromotionReason = reason
  end
  record.contentHash = recordHash(record)
  if not record.contentHash then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local targetSeason = staged.seasons[seasonId]
  bumpRosterRevision(targetSeason)
  targetSeason.enrollmentRevisions = targetSeason.enrollmentRevisions or {}
  targetSeason.enrollmentRevisions[enrollmentId] = targetSeason.enrollmentRevisions[enrollmentId] or {}
  targetSeason.enrollmentRevisions[enrollmentId][tostring(nextRevision)] = Dibs.DeepCopy(record)
  local audit, auditReason = appendAudit(staged, { operationId = operationId,
    action = record.action, actorKey = authorKey, seasonId = seasonId,
    recordId = enrollmentId, revision = nextRevision, reason = reason })
  if not audit then return { ok = false, code = auditReason } end
  staged.operations[operationId] = { fingerprint = fingerprint,
    result = { enrollmentId = enrollmentId, revision = nextRevision } }
  Dibs.GetDB().seasonalRoster = staged
  if Dibs.SyncV2 and Dibs.SyncV2.BroadcastSeasonalEnrollmentDigest then
    pcall(Dibs.SyncV2.BroadcastSeasonalEnrollmentDigest, seasonId, enrollmentId)
  end
  return { ok = true, value = enrollmentId, revision = nextRevision }
end

function Roster.GetPublicRosterPage(seasonId, options)
  local store, reason = getStore()
  if not store then return nil, reason end
  options = type(options) == "table" and options or {}
  if type(seasonId) ~= "string" or #seasonId > 96 then return nil, "INVALID_INPUT" end
  local season = store.seasons[seasonId]
  if type(season) ~= "table" then return nil, "SEASON_NOT_FOUND" end
  local config = season.revisions and season.revisions[tostring(season.currentRevision)] or {}
  local identitySeasonId = config.identitySeasonId
    or (Dibs.Seasons and Dibs.Seasons.GetById and Dibs.Seasons.GetById(seasonId) and seasonId)
    or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId())
  local pageSize = math.max(1, math.min(50, math.floor(tonumber(options.pageSize) or 20)))
  local page = math.max(1, math.floor(tonumber(options.page) or 1))
  local query = type(options.search) == "string" and string.lower(options.search:sub(1, 80)) or ""
  local categoryId = type(options.categoryId) == "string" and options.categoryId or nil
  local sortBy = options.sortBy == "category" and "category"
    or (options.sortBy == "class" and "class" or "character")
  local sortDirection = options.sortDirection == "DESC" and "DESC" or "ASC"
  local syncBehind = Dibs.Sync and Dibs.Sync.IsSyncBehind and Dibs.Sync.IsSyncBehind() == true
  local eligibilityRevision = Dibs.CharacterEligibility and Dibs.CharacterEligibility.GetRevision
    and Dibs.CharacterEligibility.GetRevision(identitySeasonId) or 0
  local rosterRevision = tonumber(season.rosterRevision) or 0
  local configRevision = tonumber(season.currentRevision) or 0
  local cacheKey = table.concat({ seasonId, tostring(configRevision), tostring(rosterRevision), tostring(eligibilityRevision),
    query, categoryId or "*", sortBy, sortDirection, syncBehind and "BEHIND" or "CURRENT" }, "|")
  local cached = publicProjectionCache[cacheKey]
  local rows, totals
  if cached then
    rows, totals = cached.rows, cached.totals
  else
    rows, totals = {}, { roles = { TANK = 0, HEALER = 0, DAMAGER = 0 }, categories = {},
      classes = {}, armor = {}, uniquePlayers = 0 }
    local compositionGroups = {}
    local rosterClasses = {}
    local rosterSnapshot = Dibs.Identity and Dibs.Identity.GetRosterSnapshot
      and Dibs.Identity.GetRosterSnapshot() or {}
    for _, member in ipairs(type(rosterSnapshot) == "table" and rosterSnapshot or {}) do
      if type(member) == "table" and type(member.memberKey) == "string" then
        rosterClasses[member.memberKey] = { className = member.className, classFileName = member.classFileName }
      end
    end
    for _, enrollment in pairs(season.enrollments or {}) do
      if type(enrollment) == "table" and enrollment.status == "ACTIVE"
        and (not categoryId or enrollment.categoryId == categoryId)
        and (query == "" or string.lower(tostring(enrollment.character or "")):find(query, 1, true)) then
        local className, classFileName, armorType = rosterClass(enrollment.character, rosterClasses)
        local identity = Dibs.CharacterEligibility and Dibs.CharacterEligibility.GetPersonProjection
          and Dibs.CharacterEligibility.GetPersonProjection(enrollment.character, identitySeasonId)
        local historicalCategory = categoryForEnrollment(season, enrollment, config)
        local row = { character = enrollment.character, characterKey = enrollment.characterKey,
          categoryId = enrollment.categoryId,
          requestedPath = enrollment.requestedPath or "STANDARD",
          categoryName = enrollment.categoryName or (historicalCategory or {}).name or enrollment.categoryId,
          categoryDescription = enrollment.categoryDescription
            or (historicalCategory or {}).description or "",
          categoryVersion = enrollment.categoryVersion
            or (historicalCategory or {}).version or 1,
          primarySpec = enrollment.primarySpec,
          secondarySpec = enrollment.secondarySpec, roles = Dibs.DeepCopy(enrollment.roles or {}),
          className = className, classFileName = classFileName, armorType = armorType,
          personGroupId = identity and identity.groupId, isSelectedMain = not identity or not identity.linked
            or identity.mainCharacterKey == enrollment.characterKey }
        rows[#rows + 1] = row
        local groupKey = identity and identity.groupId or ("character:" .. tostring(enrollment.characterKey))
        local previous = compositionGroups[groupKey]
        if row.isSelectedMain and not previous then
          compositionGroups[groupKey] = row
        elseif row.isSelectedMain and previous then
          -- Conflicting duplicate Main enrollments fail closed for composition;
          -- both remain visible in the public list for officer review.
          compositionGroups[groupKey] = { conflict = true }
        end
      end
    end
    for _, row in ipairs(rows) do
      totals.categories[row.categoryId] = (totals.categories[row.categoryId] or 0) + 1
    end
    for _, row in pairs(compositionGroups) do
      if row and not row.conflict then
        totals.uniquePlayers = totals.uniquePlayers + 1
        totals.classes[row.classFileName or "UNKNOWN"] = (totals.classes[row.classFileName or "UNKNOWN"] or 0) + 1
        totals.armor[row.armorType or "UNKNOWN"] = (totals.armor[row.armorType or "UNKNOWN"] or 0) + 1
        for _, role in ipairs(row.roles or {}) do totals.roles[role] = (totals.roles[role] or 0) + 1 end
      end
    end
    table.sort(rows, function(a, b)
      local left, right
      if sortBy == "category" then
        left, right = tostring(a.categoryId or ""), tostring(b.categoryId or "")
      elseif sortBy == "class" then
        left, right = tostring(a.className or "Unknown"), tostring(b.className or "Unknown")
      else
        left, right = tostring(a.character or ""), tostring(b.character or "")
      end
      left, right = string.lower(left), string.lower(right)
      if left ~= right then
        if sortDirection == "DESC" then return left > right end
        return left < right
      end
      local characterLeft, characterRight = string.lower(tostring(a.character or "")),
        string.lower(tostring(b.character or ""))
      if characterLeft ~= characterRight then return characterLeft < characterRight end
      return tostring(a.categoryId) < tostring(b.categoryId)
    end)
    publicProjectionCache[cacheKey] = { rows = rows, totals = totals }
    publicProjectionCacheOrder[#publicProjectionCacheOrder + 1] = cacheKey
    while #publicProjectionCacheOrder > 8 do
      local expired = table.remove(publicProjectionCacheOrder, 1)
      publicProjectionCache[expired] = nil
    end
  end
  local total = #rows
  local pages = math.max(1, math.ceil(total / pageSize))
  page = math.min(page, pages)
  local visible = {}
  local first = ((page - 1) * pageSize) + 1
  for index = first, math.min(total, first + pageSize - 1) do
    local row = rows[index]
    visible[#visible + 1] = { character = row.character, requestedPath = row.requestedPath,
      categoryId = row.categoryId,
      categoryName = row.categoryName, categoryDescription = row.categoryDescription,
      categoryVersion = row.categoryVersion,
      primarySpec = row.primarySpec, secondarySpec = row.secondarySpec,
      roles = Dibs.DeepCopy(row.roles or {}), className = row.className,
      classFileName = row.classFileName, armorType = row.armorType }
  end
  return { rows = visible, total = total, page = page, pages = pages, pageSize = pageSize,
    roles = Dibs.DeepCopy(totals.roles), categories = Dibs.DeepCopy(totals.categories),
    classes = Dibs.DeepCopy(totals.classes), armor = Dibs.DeepCopy(totals.armor),
    uniquePlayers = totals.uniquePlayers, rosterRevision = rosterRevision,
    eligibilityRevision = eligibilityRevision, status = syncBehind and "CATCHING_UP" or "READY",
    categoryCatalog = Dibs.DeepCopy(config.categoryCatalog or select(1,
      normalizeCategoryCatalog(nil, config.categories or {})) or {}),
    syncBehind = syncBehind, sortBy = sortBy, sortDirection = sortDirection }
end

-- Read-only reconciliation proposal. The currently selected Main's legacy
-- balance remains the target; other linked characters are shown individually
-- and are never silently summed into it.
function Roster.GetBalanceReconciliationPreview(seasonId, character, actor)
  local store, reason = getStore()
  if not store then return nil, reason end
  local permission, permissionReason = mutationPermission("season.reconcile", actor)
  if not permission then return nil, permissionReason end
  local season = store.seasons[seasonId]
  local config = type(season) == "table" and season.revisions
    and season.revisions[tostring(season.currentRevision)]
  if type(config) ~= "table" then return nil, "SEASON_NOT_FOUND" end
  if not VALID_LIFECYCLE_STATES[config.lifecycleState] then return nil, "SEASON_READ_ONLY" end
  local eligibility = Dibs.CharacterEligibility
  if not eligibility or type(eligibility.GetPersonProjection) ~= "function" then return nil, "IDENTITY_UNAVAILABLE" end
  local identitySeasonId = config.identitySeasonId
    or (Dibs.Seasons and Dibs.Seasons.GetById and Dibs.Seasons.GetById(seasonId) and seasonId)
    or Dibs.GetCurrentSeasonId()
  local person, identityReason = eligibility.GetPersonProjection(character, identitySeasonId)
  if not person then return nil, identityReason end
  if not person.linked then return nil, "RECONCILIATION_NOT_REQUIRED" end
  local ledger = Dibs.Ledger
  if not ledger or type(ledger.GetBalance) ~= "function" or type(ledger.GetActiveLedgerId) ~= "function" then
    return nil, "LEDGER_UNAVAILABLE"
  end
  local ledgerId = ledger.GetActiveLedgerId()
  local rows, mainBalance, pending = {}, nil, false
  for _, memberKey in ipairs(person.memberKeys) do
    local displayName = person.names and person.names[memberKey]
    if not displayName or displayName == "" then displayName = memberKey end
    local balance = tonumber(ledger.GetBalance(displayName, identitySeasonId, ledgerId))
    if not balance or balance ~= balance or math.abs(balance) == math.huge then return nil, "BALANCE_UNAVAILABLE" end
    local reservation = ledger.GetPendingDibReservations
      and tonumber(ledger.GetPendingDibReservations(displayName, identitySeasonId, ledgerId)) or 0
    if reservation > 0 then pending = true end
    rows[#rows + 1] = { characterKey = memberKey, character = displayName, balance = balance,
      pendingReservations = reservation }
    if memberKey == person.mainCharacterKey then mainBalance = balance end
  end
  if mainBalance == nil then return nil, "MAIN_BALANCE_UNAVAILABLE" end
  table.sort(rows, function(a, b) return a.characterKey < b.characterKey end)
  local adjustments = {}
  for _, row in ipairs(rows) do
    if row.characterKey ~= person.mainCharacterKey and row.balance ~= 0 then
      adjustments[#adjustments + 1] = { character = row.character, amount = -row.balance }
    end
  end
  local ledgerRevision = ledger.GetDataRevision and ledger.GetDataRevision(ledgerId) or 0
  local previewSnapshot = { schema = 1, guildKey = Dibs.GetGuildKey and Dibs.GetGuildKey() or "",
    seasonId = seasonId, identitySeasonId = identitySeasonId, ledgerId = ledgerId,
    personGroupId = person.groupId, mainCharacterKey = person.mainCharacterKey,
    sourceLedgerRevision = tonumber(ledgerRevision) or 0,
    eligibilityRevision = tonumber(person.revision) or 0, sourceBalances = rows,
    adjustments = adjustments }
  return { state = "RECONCILIATION_REQUIRED", seasonId = seasonId,
    identitySeasonId = identitySeasonId, ledgerId = ledgerId, personGroupId = person.groupId,
    mainCharacterKey = person.mainCharacterKey, sourceBalances = rows,
    resultingPersonBalance = mainBalance, adjustments = adjustments,
    sourceLedgerRevision = tonumber(ledgerRevision) or 0,
    eligibilityRevision = tonumber(person.revision) or 0,
    previewId = hash(previewSnapshot),
    pendingReservations = pending, requiresReason = true,
    activationSupported = false, activationBlockReason = "PERSON_BALANCE_SYNC_UNAVAILABLE" }
end

-- Apply one reviewed legacy correction at a time. Each adjustment is a single
-- append-only ledger transaction; callers must refresh the preview before
-- correcting another linked character. This avoids presenting a multi-row
-- partial operation as atomic when the ledger protocol commits one transaction
-- per message.
function Roster.ApplyLegacyBalanceCorrection(seasonId, character, expectedPreview, reason, operationId, confirmation, actor)
  local allowed, permissionReason = mutationPermission("season.reconcile", actor)
  if not allowed then return { ok = false, code = permissionReason } end
  if confirmation ~= true then return { ok = false, code = "CONFIRMATION_REQUIRED" } end
  reason = type(reason) == "string" and reason:match("^%s*(.-)%s*$") or ""
  if #reason < 3 or #reason > 300 then return { ok = false, code = "REASON_REQUIRED" } end
  if type(expectedPreview) ~= "table" or type(expectedPreview.previewId) ~= "string"
    or not operationIdValid(operationId) then return { ok = false, code = "INVALID_INPUT" } end
  local preview, previewReason = Roster.GetBalanceReconciliationPreview(seasonId, character, actor)
  if not preview then return { ok = false, code = previewReason } end
  if preview.previewId ~= expectedPreview.previewId
    or tonumber(preview.sourceLedgerRevision) ~= tonumber(expectedPreview.sourceLedgerRevision)
    or tonumber(preview.eligibilityRevision) ~= tonumber(expectedPreview.eligibilityRevision)
    or preview.mainCharacterKey ~= expectedPreview.mainCharacterKey
    or preview.personGroupId ~= expectedPreview.personGroupId
    or preview.ledgerId ~= expectedPreview.ledgerId then
    return { ok = false, code = "STALE_PREVIEW" }
  end
  if preview.pendingReservations then return { ok = false, code = "PENDING_DIB_RESERVATIONS" } end
  local targetKey = Dibs.Identity and Dibs.Identity.CanonicalMemberKey
    and Dibs.Identity.CanonicalMemberKey(character) or nil
  local target
  for _, row in ipairs(preview.sourceBalances) do
    if row.characterKey == targetKey then target = row; break end
  end
  if not target then return { ok = false, code = "CHARACTER_NOT_IN_PERSON_GROUP" } end
  if target.characterKey == preview.mainCharacterKey then return { ok = false, code = "MAIN_BALANCE_RETAINED" } end
  if target.balance == 0 then return { ok = false, code = "NO_CORRECTION_REQUIRED" } end
  if type(target.balance) ~= "number" or target.balance ~= target.balance
    or math.abs(target.balance) == math.huge or target.balance ~= math.floor(target.balance) then
    return { ok = false, code = "BALANCE_NOT_INTEGER" }
  end
  if not Dibs.ProtectedActions or type(Dibs.ProtectedActions.Execute) ~= "function" then
    return { ok = false, code = "PROTECTED_ACTION_UNAVAILABLE" }
  end
  local idHash = hash({ schema = 1, guildKey = Dibs.GetGuildKey and Dibs.GetGuildKey() or "",
    operationId = operationId, seasonId = seasonId, ledgerId = preview.ledgerId,
    memberKey = target.characterKey, amount = -target.balance })
  if not idHash then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local result = Dibs.ProtectedActions.Execute("ledger.adjust", actor, {
    playerName = target.character, amount = -target.balance,
    reason = "Main/Alt balance reconciliation: " .. reason,
    source = "MANUAL_ADMIN", seasonId = preview.identitySeasonId,
    confirmation = true, transactionId = "person-reconcile-" .. idHash,
  })
  if not result or result.ok ~= true then
    return { ok = false, code = result and result.decision and result.decision.reasonCode or "ADJUSTMENT_REJECTED",
      diagnostic = result and result.diagnostic }
  end
  local updatedPreview, updatedReason = Roster.GetBalanceReconciliationPreview(seasonId, character, actor)
  return { ok = true, code = "CORRECTION_APPENDED", transaction = result.value,
    preview = updatedPreview, previewReason = updatedReason }
end

local function registrationWindowError(input)
  if input.registrationStartAt and input.startAt and input.registrationStartAt >= input.startAt then
    return "REGISTRATION_MUST_PRECEDE_SEASON"
  end
  if input.registrationEndAt and input.endAt and input.registrationEndAt > input.endAt then
    return "REGISTRATION_EXCEEDS_SEASON_END"
  end
end

-- Strict chronology applies to new/draft writes, not immutable historical sync.
function Roster.ValidateSeasonInput(input, enforceRegistrationWindow)
  if type(input) ~= "table" then return false, "INVALID_INPUT" end
  local name = type(input.name) == "string" and input.name:match("^%s*(.-)%s*$") or nil
  if not name or name == "" or #name > MAX_NAME_LENGTH then return false, "INVALID_INPUT" end
  local registrationState = input.registrationState
  if registrationState ~= nil and (type(registrationState) ~= "string"
    or not VALID_REGISTRATION_STATES[registrationState]) then
    return false, "INVALID_INPUT"
  end
  local lifecycleState = input.lifecycleState
  if lifecycleState ~= nil and (type(lifecycleState) ~= "string"
    or not VALID_LIFECYCLE_STATES[lifecycleState]) then
    return false, "INVALID_INPUT"
  end
  local description = input.description
  if description ~= nil and (type(description) ~= "string" or #description > MAX_DESCRIPTION_LENGTH) then
    return false, "INVALID_INPUT"
  end
  local raidRules = input.raidRules == nil and "" or input.raidRules
  if type(raidRules) ~= "string" or #raidRules > MAX_RAID_RULES_LENGTH then return false, "INVALID_INPUT" end
  local promotionPolicy = input.promotionPolicy == nil and "" or input.promotionPolicy
  if type(promotionPolicy) ~= "string" or #promotionPolicy > MAX_PROMOTION_POLICY_LENGTH then
    return false, "INVALID_INPUT"
  end
  local noRankPolicyInput = input.noRankPolicy
  local noRankPolicy = { mode = "UNCONFIGURED" }
  if noRankPolicyInput ~= nil then
    if type(noRankPolicyInput) ~= "table" then return false, "INVALID_INPUT" end
    local mode = noRankPolicyInput.mode
    if mode == "EXCLUDE" then
      if noRankPolicyInput.allocation ~= nil then return false, "INVALID_INPUT" end
      noRankPolicy = { mode = "EXCLUDE" }
    elseif mode == "FIXED" then
      local allocation = noRankPolicyInput.allocation
      if not wholeNumber(allocation) or allocation > 100000 then return false, "INVALID_INPUT" end
      noRankPolicy = { mode = "FIXED", allocation = allocation }
    elseif mode ~= "UNCONFIGURED" or noRankPolicyInput.allocation ~= nil then
      return false, "INVALID_INPUT"
    end
  end
  local categoryCatalog, categories, categoryReason = normalizeCategoryCatalog(input.categoryCatalog, input.categories)
  if not categoryCatalog then return false, categoryReason end
  local raidDifficulties, seenDifficulties = {}, {}
  if input.raidDifficulties ~= nil then
    if type(input.raidDifficulties) ~= "table" then return false, "INVALID_INPUT" end
    local count = 0
    for key in pairs(input.raidDifficulties) do
      if type(key) ~= "number" or key < 1 or key > 3 or key ~= math.floor(key) then return false, "INVALID_INPUT" end
      count = count + 1
    end
    if count ~= #input.raidDifficulties then return false, "INVALID_INPUT" end
    for index = 1, count do
      if input.raidDifficulties[index] == nil then return false, "INVALID_INPUT" end
    end
    for _, difficulty in ipairs(input.raidDifficulties) do
      if not VALID_RAID_DIFFICULTIES[difficulty] or seenDifficulties[difficulty] then return false, "INVALID_INPUT" end
      seenDifficulties[difficulty] = true
      raidDifficulties[#raidDifficulties + 1] = difficulty
    end
  end
  -- identitySeasonId is accepted only for imported legacy records. Newly
  -- created seasons use their canonical seasonId for every domain.
  local identitySeasonId = input.identitySeasonId
  if identitySeasonId ~= nil and (type(identitySeasonId) ~= "string" or #identitySeasonId > 96) then
    return false, "INVALID_INPUT"
  end
  local function validTimestamp(value)
    return value == nil or (wholeNumber(value) and value <= 4102444800)
  end
  local startAt, endAt = input.startAt, input.endAt
  local registrationStartAt, registrationEndAt = input.registrationStartAt, input.registrationEndAt
  if not validTimestamp(startAt) or not validTimestamp(endAt)
    or not validTimestamp(registrationStartAt) or not validTimestamp(registrationEndAt)
    or (startAt and endAt and endAt < startAt)
    or (registrationStartAt and registrationEndAt and registrationEndAt < registrationStartAt) then
    return false, "INVALID_INPUT"
  end
  if enforceRegistrationWindow == true then
    local windowReason = registrationWindowError(input)
    if windowReason then return false, windowReason end
  end
  local raidSchedule, scheduleKeys = {}, {}
  if input.raidSchedule ~= nil then
    if type(input.raidSchedule) ~= "table" then return false, "INVALID_INPUT" end
    local count = 0
    for key in pairs(input.raidSchedule) do
      if type(key) ~= "number" or key < 1 or key > 7 or key ~= math.floor(key) then return false, "INVALID_INPUT" end
      count = count + 1
    end
    if count ~= #input.raidSchedule then return false, "INVALID_INPUT" end
    for index, entry in ipairs(input.raidSchedule) do
      if index > 7 or type(entry) ~= "table" then return false, "INVALID_INPUT" end
      local weekday, timeText = entry.weekday, entry.startTime
      local duration = entry.durationMinutes == nil and 180 or entry.durationMinutes
      local timezone = entry.timeZone == nil and "" or entry.timeZone
      local difficulty = entry.difficulty
      if difficulty == "" then difficulty = nil end
      if difficulty ~= nil and (type(difficulty) ~= "string" or not VALID_RAID_DIFFICULTIES[difficulty]) then
        return false, "INVALID_INPUT"
      end
      if not wholeNumber(weekday) or weekday < 1 or weekday > 7
        or type(timeText) ~= "string" or not timeText:match("^%d%d:%d%d$")
        or tonumber(timeText:sub(1, 2)) > 23 or tonumber(timeText:sub(4, 5)) > 59
        or not wholeNumber(duration) or duration < 30 or duration > 600
        or type(timezone) ~= "string" or #timezone > 64 then return false, "INVALID_INPUT" end
      local scheduleKey = tostring(weekday) .. "@" .. timeText
      if scheduleKeys[scheduleKey] then return false, "INVALID_INPUT" end
      scheduleKeys[scheduleKey] = true
      raidSchedule[index] = { weekday = weekday, startTime = timeText,
        durationMinutes = duration, timeZone = timezone, difficulty = difficulty }
    end
  end
  return true, {
    name = name,
    description = description,
    raidRules = raidRules,
    promotionPolicy = promotionPolicy,
    rulesRevision = wholeNumber(input.rulesRevision) and math.max(1, input.rulesRevision) or 1,
    registrationState = registrationState,
    lifecycleState = lifecycleState,
    categories = categories,
    categoryCatalog = categoryCatalog,
    identitySeasonId = identitySeasonId,
    startAt = startAt, endAt = endAt,
    registrationStartAt = registrationStartAt, registrationEndAt = registrationEndAt,
    raidSchedule = raidSchedule,
    raidDifficulties = raidDifficulties,
    noRankPolicy = noRankPolicy,
  }
end

function Roster.NextRevision(currentRevision, expectedRevision)
  if not wholeNumber(currentRevision) or not wholeNumber(expectedRevision) then return nil, "INVALID_INPUT" end
  if currentRevision ~= expectedRevision then return nil, "STALE_REVISION" end
  if currentRevision >= 2147483647 then return nil, "INVALID_INPUT" end
  return currentRevision + 1
end

nextRecordId = function(store, prefix)
  prefix = prefix or "roster"
  if type(prefix) ~= "string" or #prefix < 1 or #prefix > 24 or not prefix:match("^[%w_%-]+$") then
    return nil, "INVALID_INPUT"
  end
  local counter = store.nextId
  if not wholeNumber(counter) or counter < 1 or counter >= 2147483647 then return nil, "ROSTER_SCHEMA_UNSUPPORTED" end
  store.nextId = counter + 1
  return prefix .. "-" .. tostring(counter) .. "-" .. tostring((Dibs.GetTimestamp and Dibs.GetTimestamp()) or time())
end

function Roster.NewRecordId(prefix)
  local store, reason = getStore()
  if not store then return nil, reason end
  return nextRecordId(store, prefix)
end

operationIdValid = function(operationId)
  return type(operationId) == "string" and #operationId >= 1 and #operationId <= 128
    and operationId:match("^[%w_:%-%.]+$") ~= nil
end

hash = function(value)
  if Dibs.Sync and type(Dibs.Sync.CalculateContentHash) == "function" then
    return Dibs.Sync.CalculateContentHash(value)
  end
  return nil
end

recordHash = function(record)
  local canonical = Dibs.DeepCopy(record)
  canonical.contentHash = nil
  return hash(canonical)
end

normalizeRankAllocationSnapshot = function(rules)
  if type(rules) ~= "table" then return nil, "INVALID_INPUT" end
  local normalized, count = {}, 0
  for key, rule in pairs(rules) do
    local rankIndex = tonumber(key)
    if not wholeNumber(rankIndex) or rankIndex < 0 or rankIndex > 10
      or type(rule) ~= "table" or tonumber(rule.rankIndex) ~= rankIndex
      or not wholeNumber(rule.allocation) or rule.allocation < 0 or rule.allocation > 100000
      or type(rule.enabled) ~= "boolean" then
      return nil, "INVALID_INPUT"
    end
    if normalized[tostring(rankIndex)] then return nil, "INVALID_INPUT" end
    local rankName = type(rule.rankName) == "string" and rule.rankName or ("Rank " .. tostring(rankIndex))
    if #rankName > 96 then return nil, "INVALID_INPUT" end
    normalized[tostring(rankIndex)] = { rankIndex = rankIndex, rankName = rankName,
      allocation = rule.allocation, enabled = rule.enabled }
    count = count + 1
  end
  if count == 0 then return nil, "RANK_ALLOCATION_UNCONFIGURED" end
  return normalized
end

appendAudit = function(store, event)
  if type(event) ~= "table" or not operationIdValid(event.operationId)
    or type(event.action) ~= "string" or #event.action > 48
    or type(event.actorKey) ~= "string" or #event.actorKey > 128 then
    return nil, "INVALID_INPUT"
  end
  local fingerprint = hash(event)
  if not fingerprint then return nil, "HASH_UNAVAILABLE" end
  local previous = store.auditOperationIndex[event.operationId]
  if previous then
    local existing = store.auditLog[previous]
    if type(existing) == "table" and existing.fingerprint == fingerprint then
      return existing, "IDEMPOTENT_REPLAY"
    end
    return nil, "OPERATION_CONFLICT"
  end
  local eventId, idReason = nextRecordId(store, "roster-audit")
  if not eventId then return nil, idReason end
  local saved = {
    eventId = eventId,
    operationId = event.operationId,
    action = event.action,
    actorKey = event.actorKey,
    seasonId = event.seasonId,
    recordId = event.recordId,
    revision = event.revision,
    reason = event.reason,
    timestamp = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time(),
    fingerprint = fingerprint,
  }
  store.auditLog[#store.auditLog + 1] = saved
  store.auditOperationIndex[event.operationId] = #store.auditLog
  return saved
end

mutationPermission = function(action, actor)
  if not Dibs.Permissions or type(Dibs.Permissions.Evaluate) ~= "function" then return false, "AUTHORITY_UNAVAILABLE" end
  local decision = Dibs.Permissions.Evaluate(action, actor)
  if not decision or decision.allowed ~= true then
    return false, decision and decision.reasonCode == "GUILD_ADMIN_REQUIRED" and "GUILD_ADMIN_REQUIRED" or "PERMISSION_DENIED"
  end
  return true
end

actorKey = function(actor)
  local identity = Dibs.Identity
  local name = actor
  if type(actor) == "table" then name = actor.nameRealm or actor.displayName or actor.name or actor.playerName end
  if name == nil and Dibs.GetPlayerName then name = Dibs.GetPlayerName() end
  return identity and identity.CanonicalMemberKey and identity.CanonicalMemberKey(name) or nil
end

currentActorKey = function()
  local identity = Dibs.Identity
  local name = Dibs.GetPlayerName and Dibs.GetPlayerName()
  if not identity or type(identity.CreateSnapshot) ~= "function" or type(name) ~= "string" then
    return nil, "AUTHORITY_UNAVAILABLE"
  end
  local snapshot, reason = identity.CreateSnapshot(name)
  if type(snapshot) ~= "table" or type(snapshot.memberKey) ~= "string" then
    return nil, reason or "AUTHORITY_UNAVAILABLE"
  end
  return snapshot.memberKey
end

validateEnrollmentInput = function(input, season)
  if type(input) ~= "table" then return false, "INVALID_INPUT" end
  local character = type(input.character) == "string" and input.character:match("^%s*(.-)%s*$") or nil
  local characterKey = character and Dibs.Identity and Dibs.Identity.CanonicalMemberKey(character)
  if not characterKey or #characterKey > 96 then return false, "INVALID_INPUT" end
  local categoryId = input.categoryId
  if type(categoryId) ~= "string" or #categoryId > 40 then return false, "INVALID_INPUT" end
  local category = categoryById(season, categoryId, false)
  if not category then return false, "INVALID_INPUT" end
  local requestedPath = input.requestedPath or "STANDARD"
  if requestedPath ~= "STANDARD" and requestedPath ~= "CORE_PROGRESSION" and requestedPath ~= "CASUAL" then
    return false, "INVALID_INPUT"
  end
  local function validSpec(spec, optional)
    if spec == nil and optional then return true end
    return type(spec) == "string" and #spec > 0 and #spec <= 40 and spec:match("^[%w_%-]+$") ~= nil
  end
  if not validSpec(input.primarySpec, false) or not validSpec(input.secondarySpec, true) then return false, "INVALID_INPUT" end
  if type(input.roles) ~= "table" or #input.roles < 1 or #input.roles > 3 then return false, "INVALID_INPUT" end
  local validRoles, roles = { TANK = true, HEALER = true, DAMAGER = true }, {}
  for _, role in ipairs(input.roles) do
    if not validRoles[role] or roles[role] then return false, "INVALID_INPUT" end
    roles[role] = true
  end
  local normalizedRoles = {}
  for role in pairs(roles) do normalizedRoles[#normalizedRoles + 1] = role end
  table.sort(normalizedRoles)
  return true, { character = Dibs.Identity.NormalizeDisplayName(character), characterKey = characterKey,
    categoryId = categoryId, categoryVersion = category.version or 1,
    categoryName = category.name or categoryId, categoryDescription = category.description or "",
    categorySeasonRevision = season.revision,
    requestedPath = requestedPath,
    primarySpec = input.primarySpec, secondarySpec = input.secondarySpec,
    roles = normalizedRoles }
end

operationReplay = function(store, operationId, fingerprint)
  local existing = store.operations[operationId]
  if not existing then return nil end
  if existing.fingerprint == fingerprint then
    return { ok = true, value = existing.result.seasonId or existing.result.enrollmentId,
      revision = existing.result.revision, idempotent = true }
  end
  return { ok = false, code = "OPERATION_CONFLICT" }
end

function Roster.CreateSeason(input, operationId, actor)
  local store, storeReason = getStore()
  if not store then return { ok = false, code = storeReason } end
  local allowed, permissionReason = mutationPermission("season.create", actor)
  if not allowed then return { ok = false, code = permissionReason } end
  if type(input) ~= "table" or not operationIdValid(operationId) then
    return { ok = false, code = "INVALID_INPUT" }
  end
  local createInput = Dibs.DeepCopy(input)
  if createInput.registrationState == nil then createInput.registrationState = "DRAFT" end
  if createInput.lifecycleState == nil then createInput.lifecycleState = "DRAFT" end
  local valid, config = Roster.ValidateSeasonInput(createInput)
  if not valid then return { ok = false, code = config } end
  if config.lifecycleState == "ACTIVE" then
    return { ok = false, code = "ACTIVATION_NOT_IMPLEMENTED" }
  end
  if config.lifecycleState ~= "DRAFT" or config.registrationState ~= "DRAFT" then
    return { ok = false, code = "INITIAL_STATE_MUST_BE_DRAFT" }
  end
  if not config.startAt or not config.registrationStartAt then
    return { ok = false, code = "SEASON_DATES_REQUIRED" }
  end
  local authorKey = actorKey(actor)
  if not authorKey then return { ok = false, code = "AUTHORITY_UNAVAILABLE" } end
  local fingerprint = hash({ config = config, actorKey = authorKey })
  if not fingerprint then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local existing = store.operations[operationId]
  if existing then
    if existing.fingerprint == fingerprint then
      return { ok = true, value = existing.result.seasonId, revision = existing.result.revision, idempotent = true }
    end
    return { ok = false, code = "OPERATION_CONFLICT" }
  end

  local windowReason = registrationWindowError(config)
  if windowReason then return { ok = false, code = windowReason } end
  local staged = Dibs.DeepCopy(store)
  local seasonId, idReason = nextRecordId(staged, "season")
  if not seasonId then return { ok = false, code = idReason } end
  if not Dibs.Seasons or type(Dibs.Seasons.CreateDraft) ~= "function" then
    return { ok = false, code = "SEASON_SERVICE_UNAVAILABLE" }
  end
  local memberKey = authorKey
  local record = {
    seasonId = seasonId, revision = 1, parentRevision = 0, parentHash = "GENESIS",
    action = "SEASON_CREATED", operationId = operationId,
    name = config.name, description = config.description, raidRules = config.raidRules,
    promotionPolicy = config.promotionPolicy, rulesRevision = config.rulesRevision,
    registrationState = config.registrationState,
    lifecycleState = config.lifecycleState,
    categories = config.categories, categoryCatalog = config.categoryCatalog,
    identitySeasonId = seasonId,
    startAt = config.startAt, endAt = config.endAt,
    registrationStartAt = config.registrationStartAt, registrationEndAt = config.registrationEndAt,
    raidSchedule = config.raidSchedule,
    raidDifficulties = config.raidDifficulties,
    noRankPolicy = config.noRankPolicy,
    updatedAt = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time(),
    updatedBy = memberKey,
  }
  record.contentHash = recordHash(record)
  if not record.contentHash then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local season = { seasonId = seasonId, currentRevision = 1, rosterRevision = 0,
    revisions = { ["1"] = record }, enrollments = {}, enrollmentRevisions = {} }
  local audit, auditReason = appendAudit(staged, {
    operationId = operationId, action = "SEASON_CREATED", actorKey = memberKey,
    seasonId = seasonId, revision = 1, reason = config.description or config.name,
  })
  if not audit then return { ok = false, code = auditReason } end
  staged.seasons[seasonId] = season
  staged.operations[operationId] = { fingerprint = fingerprint, result = { seasonId = seasonId, revision = 1 } }
  local db = Dibs.GetDB()
  local nativeSeason = Dibs.Seasons.CreateDraft(config.name, seasonId)
  if not nativeSeason then return { ok = false, code = "SEASON_ID_CONFLICT" } end
  db.seasonalRoster = staged
  if Dibs.SyncV2 and Dibs.SyncV2.BroadcastSeasonalRosterDigest then
    pcall(Dibs.SyncV2.BroadcastSeasonalRosterDigest, seasonId)
  end
  return { ok = true, value = seasonId, revision = 1 }
end

-- Draft edits create a new immutable season revision. They never switch the
-- active Dibs season or touch a ledger.
function Roster.UpdateDraft(seasonId, patch, expectedRevision, operationId, reason, actor)
  local store, storeReason = getStore()
  if not store then return { ok = false, code = storeReason } end
  local allowed, permissionReason = mutationPermission("season.draft.edit", actor)
  if not allowed then return { ok = false, code = permissionReason } end
  reason = type(reason) == "string" and reason:match("^%s*(.-)%s*$") or ""
  if type(seasonId) ~= "string" or #seasonId > 96 or type(patch) ~= "table"
    or not wholeNumber(expectedRevision) or not operationIdValid(operationId)
    or #reason < 1 or #reason > MAX_DESCRIPTION_LENGTH then
    return { ok = false, code = #reason < 1 and "REASON_REQUIRED" or "INVALID_INPUT" }
  end
  local authorKey = actorKey(actor)
  if not authorKey then return { ok = false, code = "AUTHORITY_UNAVAILABLE" } end
  local season = store.seasons[seasonId]
  if type(season) ~= "table" then return { ok = false, code = "SEASON_NOT_FOUND" } end
  local currentRevision = tonumber(season.currentRevision)
  local current = season.revisions and season.revisions[tostring(currentRevision)]
  if type(current) ~= "table" then return { ok = false, code = "ROSTER_SCHEMA_UNSUPPORTED" } end
  if not VALID_LIFECYCLE_STATES[current.lifecycleState] then
    return { ok = false, code = "SEASON_READ_ONLY" }
  end
  if current.lifecycleState ~= "DRAFT" then return { ok = false, code = "DRAFT_ONLY" } end

  local input = {
    name = current.name, description = current.description, raidRules = current.raidRules,
    promotionPolicy = current.promotionPolicy, rulesRevision = current.rulesRevision,
    registrationState = current.registrationState, lifecycleState = current.lifecycleState,
    categories = current.categories, categoryCatalog = current.categoryCatalog,
    startAt = current.startAt, endAt = current.endAt,
    registrationStartAt = current.registrationStartAt,
    registrationEndAt = current.registrationEndAt, raidSchedule = current.raidSchedule,
    raidDifficulties = current.raidDifficulties,
    noRankPolicy = current.noRankPolicy,
  }
  local allowedFields = { name = true, description = true, startAt = true, endAt = true,
    registrationStartAt = true, registrationEndAt = true, raidSchedule = true, raidDifficulties = true, raidRules = true,
    promotionPolicy = true, categoryCatalog = true, categories = true, noRankPolicy = true }
  for key, value in pairs(patch) do
    if not allowedFields[key] then return { ok = false, code = "PATCH_FIELD_FORBIDDEN" } end
    input[key] = Dibs.DeepCopy(value)
    if value == false and (key == "endAt" or key == "registrationEndAt") then input[key] = nil end
  end
  local valid, normalized = Roster.ValidateSeasonInput(input)
  if not valid then return { ok = false, code = normalized } end
  if not normalized.startAt or not normalized.registrationStartAt then
    return { ok = false, code = "SEASON_DATES_REQUIRED" }
  end
  local fingerprint = hash({ seasonId = seasonId, patch = patch, expectedRevision = expectedRevision,
    reason = reason, actorKey = authorKey })
  if not fingerprint then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local replay = operationReplay(store, operationId, fingerprint)
  if replay then return replay end
  local windowReason = registrationWindowError(normalized)
  if windowReason then return { ok = false, code = windowReason } end
  local nextRevision, revisionReason = Roster.NextRevision(currentRevision, expectedRevision)
  if not nextRevision then return { ok = false, code = revisionReason } end

  local staged = Dibs.DeepCopy(store)
  season = staged.seasons[seasonId]
  current = season.revisions[tostring(currentRevision)]
  local record = Dibs.DeepCopy(current)
  record.revision, record.parentRevision, record.parentHash = nextRevision, currentRevision, current.contentHash
  record.action, record.operationId, record.changeReason = "SEASON_DRAFT_UPDATED", operationId, reason
  record.name, record.description, record.raidRules = normalized.name, normalized.description, normalized.raidRules
  record.promotionPolicy = normalized.promotionPolicy
  if normalized.raidRules ~= (current.raidRules or "")
    or normalized.promotionPolicy ~= (current.promotionPolicy or "")
    or hash(normalized.noRankPolicy) ~= hash(current.noRankPolicy or { mode = "UNCONFIGURED" }) then
    record.rulesRevision = math.min(2147483646, (tonumber(current.rulesRevision) or 1) + 1)
  end
  record.categories, record.categoryCatalog = normalized.categories, normalized.categoryCatalog
  record.startAt, record.endAt = normalized.startAt, normalized.endAt
  record.registrationStartAt, record.registrationEndAt = normalized.registrationStartAt, normalized.registrationEndAt
  record.raidSchedule = normalized.raidSchedule
  record.raidDifficulties = normalized.raidDifficulties
  record.noRankPolicy = normalized.noRankPolicy
  record.updatedAt, record.updatedBy = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time(), authorKey
  record.contentHash = recordHash(record)
  if not record.contentHash then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local audit, auditReason = appendAudit(staged, { operationId = operationId,
    action = record.action, actorKey = authorKey, seasonId = seasonId,
    revision = nextRevision, reason = reason })
  if not audit then return { ok = false, code = auditReason } end
  season.revisions[tostring(nextRevision)], season.currentRevision = record, nextRevision
  staged.operations[operationId] = { fingerprint = fingerprint,
    result = { seasonId = seasonId, revision = nextRevision } }
  Dibs.GetDB().seasonalRoster = staged
  if Dibs.SyncV2 and Dibs.SyncV2.BroadcastSeasonalRosterDigest then
    pcall(Dibs.SyncV2.BroadcastSeasonalRosterDigest, seasonId)
  end
  return { ok = true, value = seasonId, revision = nextRevision }
end

-- Publish revised raid rules/Core criteria without reopening or rewriting old
-- enrollment decisions. The configuration revision and rulesRevision are both
-- immutable references that clients can display and synchronize.
function Roster.PublishSeasonPolicy(seasonId, patch, expectedRevision, operationId, reason, actor)
  local store, storeReason = getStore()
  if not store then return { ok = false, code = storeReason } end
  local allowed, permissionReason = mutationPermission("season.rules.publish", actor)
  if not allowed then return { ok = false, code = permissionReason } end
  reason = type(reason) == "string" and reason:match("^%s*(.-)%s*$") or ""
  if type(seasonId) ~= "string" or #seasonId > 96 or type(patch) ~= "table"
    or not wholeNumber(expectedRevision) or not operationIdValid(operationId)
    or #reason < 1 or #reason > MAX_DESCRIPTION_LENGTH then
    return { ok = false, code = #reason < 1 and "REASON_REQUIRED" or "INVALID_INPUT" }
  end
  for key in pairs(patch) do
    if key ~= "raidRules" and key ~= "promotionPolicy" then
      return { ok = false, code = "PATCH_FIELD_FORBIDDEN" }
    end
  end
  local authorKey = actorKey(actor)
  if not authorKey then return { ok = false, code = "AUTHORITY_UNAVAILABLE" } end
  local season = store.seasons[seasonId]
  local currentRevision = type(season) == "table" and tonumber(season.currentRevision)
  local current = currentRevision and season.revisions and season.revisions[tostring(currentRevision)]
  if type(current) ~= "table" then return { ok = false, code = "SEASON_NOT_FOUND" } end
  if not VALID_LIFECYCLE_STATES[current.lifecycleState] then
    return { ok = false, code = "SEASON_READ_ONLY" }
  end
  if current.lifecycleState == "COMPLETED" or current.lifecycleState == "ARCHIVED" then
    return { ok = false, code = "SEASON_READ_ONLY" }
  end
  local input = {
    name = current.name, description = current.description, raidRules = current.raidRules,
    promotionPolicy = current.promotionPolicy, rulesRevision = current.rulesRevision,
    registrationState = current.registrationState, lifecycleState = current.lifecycleState,
    categories = current.categories, categoryCatalog = current.categoryCatalog,
    identitySeasonId = current.identitySeasonId, startAt = current.startAt, endAt = current.endAt,
    registrationStartAt = current.registrationStartAt, registrationEndAt = current.registrationEndAt,
    raidSchedule = current.raidSchedule,
  }
  for key, value in pairs(patch) do input[key] = Dibs.DeepCopy(value) end
  local valid, normalized = Roster.ValidateSeasonInput(input)
  if not valid then return { ok = false, code = normalized } end
  local fingerprint = hash({ seasonId = seasonId, patch = patch, expectedRevision = expectedRevision,
    reason = reason, actorKey = authorKey })
  if not fingerprint then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local replay = operationReplay(store, operationId, fingerprint)
  if replay then return replay end
  local revision, revisionReason = Roster.NextRevision(currentRevision, expectedRevision)
  if not revision then return { ok = false, code = revisionReason } end
  local rulesChanged = normalized.raidRules ~= (current.raidRules or "")
    or normalized.promotionPolicy ~= (current.promotionPolicy or "")
  if not rulesChanged then
    return { ok = true, value = seasonId, revision = currentRevision, unchanged = true }
  end

  local staged = Dibs.DeepCopy(store)
  season = staged.seasons[seasonId]
  current = season.revisions[tostring(currentRevision)]
  local record = Dibs.DeepCopy(current)
  record.revision, record.parentRevision, record.parentHash = revision, currentRevision, current.contentHash
  record.action, record.operationId, record.changeReason = "SEASON_POLICY_PUBLISHED", operationId, reason
  record.raidRules, record.promotionPolicy = normalized.raidRules, normalized.promotionPolicy
  if rulesChanged then record.rulesRevision = math.min(2147483646, (tonumber(current.rulesRevision) or 1) + 1) end
  record.updatedAt, record.updatedBy = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time(), authorKey
  record.contentHash = recordHash(record)
  if not record.contentHash then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local audit, auditReason = appendAudit(staged, { operationId = operationId,
    action = record.action, actorKey = authorKey, seasonId = seasonId,
    revision = revision, reason = reason })
  if not audit then return { ok = false, code = auditReason } end
  season.revisions[tostring(revision)], season.currentRevision = record, revision
  staged.operations[operationId] = { fingerprint = fingerprint,
    result = { seasonId = seasonId, revision = revision } }
  Dibs.GetDB().seasonalRoster = staged
  publicProjectionCache, publicProjectionCacheOrder = {}, {}
  if Dibs.SyncV2 and Dibs.SyncV2.BroadcastSeasonalRosterDigest then
    pcall(Dibs.SyncV2.BroadcastSeasonalRosterDigest, seasonId)
  end
  return { ok = true, value = seasonId, revision = revision }
end

-- Capture locally edited rank values into the immutable, synchronized season
-- revision used by activation. Later local edits cannot silently change a
-- published preview on one officer's client.
function Roster.PublishRankAllocations(seasonId, expectedRevision, operationId, reason, actor)
  local store, storeReason = getStore()
  if not store then return { ok = false, code = storeReason } end
  local allowed, permissionReason = mutationPermission("season.allocation.configure", actor)
  if not allowed then return { ok = false, code = permissionReason } end
  reason = type(reason) == "string" and reason:match("^%s*(.-)%s*$") or ""
  if type(seasonId) ~= "string" or #seasonId < 1 or #seasonId > 96
    or not wholeNumber(expectedRevision) or not operationIdValid(operationId)
    or #reason < 1 or #reason > MAX_DESCRIPTION_LENGTH then
    return { ok = false, code = #reason < 1 and "REASON_REQUIRED" or "INVALID_INPUT" }
  end
  local authorKey = actorKey(actor)
  if not authorKey then return { ok = false, code = "AUTHORITY_UNAVAILABLE" } end
  local season = store.seasons[seasonId]
  local currentRevision = type(season) == "table" and tonumber(season.currentRevision)
  local current = currentRevision and season.revisions and season.revisions[tostring(currentRevision)]
  if type(current) ~= "table" then return { ok = false, code = "SEASON_NOT_FOUND" } end
  if current.registrationState ~= "CLOSED"
    or (current.lifecycleState ~= "REVIEW" and current.lifecycleState ~= "READY" and current.lifecycleState ~= "ACTIVE") then
    return { ok = false, code = "SEASON_NOT_IN_REVIEW" }
  end
  local db = Dibs.GetDB()
  local stagedRules = type(db.rankRules) == "table" and db.rankRules[seasonId] or nil
  local rules, rulesReason = normalizeRankAllocationSnapshot(stagedRules)
  if not rules then return { ok = false, code = rulesReason } end
  local rulesHash = hash(rules)
  if not rulesHash then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local fingerprint = hash({ seasonId = seasonId, rules = rules, expectedRevision = expectedRevision,
    reason = reason, actorKey = authorKey })
  if not fingerprint then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local replay = operationReplay(store, operationId, fingerprint)
  if replay then return replay end
  local revision, revisionReason = Roster.NextRevision(currentRevision, expectedRevision)
  if not revision then return { ok = false, code = revisionReason } end
  local priorHash = current.rankAllocationSnapshot and current.rankAllocationSnapshot.contentHash
  if priorHash == rulesHash then
    return { ok = true, value = seasonId, revision = currentRevision, unchanged = true }
  end
  local staged = Dibs.DeepCopy(store)
  season = staged.seasons[seasonId]
  current = season.revisions[tostring(currentRevision)]
  local record = Dibs.DeepCopy(current)
  record.revision, record.parentRevision, record.parentHash = revision, currentRevision, current.contentHash
  record.action, record.operationId, record.changeReason = "SEASON_ALLOCATION_PUBLISHED", operationId, reason
  record.rankAllocationSnapshot = { schema = 1, rules = rules, contentHash = rulesHash }
  record.updatedAt, record.updatedBy = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time(), authorKey
  record.contentHash = recordHash(record)
  if not record.contentHash then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local audit, auditReason = appendAudit(staged, { operationId = operationId,
    action = record.action, actorKey = authorKey, seasonId = seasonId,
    revision = revision, reason = reason })
  if not audit then return { ok = false, code = auditReason } end
  season.revisions[tostring(revision)], season.currentRevision = record, revision
  staged.operations[operationId] = { fingerprint = fingerprint,
    result = { seasonId = seasonId, revision = revision } }
  Dibs.GetDB().seasonalRoster = staged
  publicProjectionCache, publicProjectionCacheOrder = {}, {}
  if Dibs.SyncV2 and Dibs.SyncV2.BroadcastSeasonalRosterDigest then
    pcall(Dibs.SyncV2.BroadcastSeasonalRosterDigest, seasonId)
  end
  return { ok = true, value = seasonId, revision = revision }
end

-- Copy configurable roster settings only. Season identity, dates, lifecycle,
-- enrollments, approvals and every ledger record remain owned by the target.
function Roster.CopySeasonSettings(sourceSeasonId, targetSeasonId, expectedRevision, operationId, reason, actor)
  local store, storeReason = getStore()
  if not store then return { ok = false, code = storeReason } end
  local source = type(sourceSeasonId) == "string" and store.seasons[sourceSeasonId]
  local target = type(targetSeasonId) == "string" and store.seasons[targetSeasonId]
  if type(source) ~= "table" or type(target) ~= "table" then return { ok = false, code = "SEASON_NOT_FOUND" } end
  if sourceSeasonId == targetSeasonId then return { ok = false, code = "INVALID_INPUT" } end
  local sourceConfig = source.revisions and source.revisions[tostring(source.currentRevision)]
  local targetConfig = target.revisions and target.revisions[tostring(target.currentRevision)]
  if type(sourceConfig) ~= "table" or type(targetConfig) ~= "table" then
    return { ok = false, code = "ROSTER_SCHEMA_UNSUPPORTED" }
  end
  if targetConfig.lifecycleState ~= "DRAFT" then return { ok = false, code = "DRAFT_ONLY" } end
  return Roster.UpdateDraft(targetSeasonId, {
    description = sourceConfig.description,
    raidRules = sourceConfig.raidRules,
    promotionPolicy = sourceConfig.promotionPolicy,
    categoryCatalog = Dibs.DeepCopy(sourceConfig.categoryCatalog or {}),
    raidSchedule = Dibs.DeepCopy(sourceConfig.raidSchedule or {}),
    raidDifficulties = Dibs.DeepCopy(sourceConfig.raidDifficulties or {}),
    noRankPolicy = Dibs.DeepCopy(sourceConfig.noRankPolicy or { mode = "UNCONFIGURED" }),
  }, expectedRevision, operationId, reason, actor)
end

function Roster.UpdateCategoryCatalog(seasonId, catalog, expectedRevision, reason, operationId, actor)
  local store, storeReason = getStore()
  if not store then return { ok = false, code = storeReason } end
  local allowed, permissionReason = mutationPermission("season.rules.publish", actor)
  if not allowed then return { ok = false, code = permissionReason } end
  reason = type(reason) == "string" and reason:match("^%s*(.-)%s*$") or ""
  if type(seasonId) ~= "string" or #seasonId > 96 or not wholeNumber(expectedRevision)
    or not operationIdValid(operationId) or #reason < 1 or #reason > MAX_DESCRIPTION_LENGTH then
    return { ok = false, code = #reason < 1 and "REASON_REQUIRED" or "INVALID_INPUT" }
  end
  local authorKey = actorKey(actor)
  if not authorKey then return { ok = false, code = "AUTHORITY_UNAVAILABLE" } end
  local normalizedCatalog, activeIds, catalogReason = normalizeCategoryCatalog(catalog)
  if not normalizedCatalog then return { ok = false, code = catalogReason } end
  local season = store.seasons[seasonId]
  if type(season) ~= "table" then return { ok = false, code = "SEASON_NOT_FOUND" } end
  local currentRevision = tonumber(season.currentRevision)
  local current = season.revisions and season.revisions[tostring(currentRevision)]
  if type(current) ~= "table" then return { ok = false, code = "ROSTER_SCHEMA_UNSUPPORTED" } end
  local readOnlyReason = seasonReadOnlyReason(current)
  if readOnlyReason or seasonLifecycle(current).seasonStatus == "COMPLETED" then
    return { ok = false, code = readOnlyReason or "SEASON_READ_ONLY" }
  end

  -- Deleted descriptors remain in the published catalog as inactive so old
  -- enrollments continue to resolve to a stable, historical label.
  local previousCatalog = current.categoryCatalog
    or select(1, normalizeCategoryCatalog(nil, current.categories or {})) or {}
  local previousById = {}
  for _, entry in ipairs(previousCatalog) do previousById[entry.id] = entry end
  local included = {}
  for _, entry in ipairs(normalizedCatalog) do
    included[entry.id] = true
    local previous = previousById[entry.id]
    if previous then
      local changed = entry.name ~= previous.name or entry.description ~= (previous.description or "")
        or entry.active ~= (previous.active ~= false) or entry.order ~= previous.order
      entry.version = changed and math.min(2147483646, (tonumber(previous.version) or 1) + 1)
        or (tonumber(previous.version) or 1)
    else
      entry.version = 1
    end
  end
  for _, entry in ipairs(previousCatalog) do
    if not included[entry.id] then
      normalizedCatalog[#normalizedCatalog + 1] = { id = entry.id, name = entry.name,
        description = entry.description or "", active = false, order = #normalizedCatalog + 1,
        version = math.min(2147483646, (tonumber(entry.version) or 1) + (entry.active == false and 0 or 1)) }
    end
  end
  activeIds = {}
  local changed = #normalizedCatalog ~= #previousCatalog
  for index, entry in ipairs(normalizedCatalog) do
    if entry.active then activeIds[#activeIds + 1] = entry.id end
    local previous = previousCatalog[index]
    if not previous or entry.id ~= previous.id or entry.name ~= previous.name
      or entry.description ~= (previous.description or "") or entry.active ~= (previous.active ~= false)
      or entry.order ~= previous.order then changed = true end
  end
  local fingerprint = hash({ seasonId = seasonId, catalog = normalizedCatalog,
    expectedRevision = expectedRevision, reason = reason, actorKey = authorKey })
  if not fingerprint then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local replay = operationReplay(store, operationId, fingerprint)
  if replay then return replay end
  local revision, revisionReason = Roster.NextRevision(currentRevision, expectedRevision)
  if not revision then return { ok = false, code = revisionReason } end
  if not changed then return { ok = true, value = seasonId, revision = currentRevision, unchanged = true } end

  local staged = Dibs.DeepCopy(store)
  season = staged.seasons[seasonId]
  current = season.revisions[tostring(currentRevision)]
  local record = Dibs.DeepCopy(current)
  record.revision, record.parentRevision, record.parentHash = revision, currentRevision, current.contentHash
  record.action, record.operationId, record.changeReason = "CATEGORY_CATALOG_UPDATED", operationId, reason
  record.categories, record.categoryCatalog = activeIds, normalizedCatalog
  record.updatedAt, record.updatedBy = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time(), authorKey
  record.contentHash = recordHash(record)
  if not record.contentHash then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local audit, auditReason = appendAudit(staged, { operationId = operationId,
    action = record.action, actorKey = authorKey, seasonId = seasonId, revision = revision, reason = reason })
  if not audit then return { ok = false, code = auditReason } end
  season.revisions[tostring(revision)], season.currentRevision = record, revision
  staged.operations[operationId] = { fingerprint = fingerprint,
    result = { seasonId = seasonId, revision = revision } }
  Dibs.GetDB().seasonalRoster = staged
  publicProjectionCache, publicProjectionCacheOrder = {}, {}
  if Dibs.SyncV2 and Dibs.SyncV2.BroadcastSeasonalRosterDigest then
    pcall(Dibs.SyncV2.BroadcastSeasonalRosterDigest, seasonId)
  end
  return { ok = true, value = seasonId, revision = revision }
end

function Roster.SetRegistrationState(seasonId, nextState, expectedRevision, operationId, reason, actor)
  local store, storeReason = getStore()
  if not store then return { ok = false, code = storeReason } end
  local allowed, permissionReason = mutationPermission("season.registration.manage", actor)
  if not allowed then return { ok = false, code = permissionReason } end
  if type(seasonId) ~= "string" or #seasonId > 96 or not VALID_REGISTRATION_STATES[nextState]
    or not operationIdValid(operationId) or type(reason) ~= "string" or #reason < 1 or #reason > MAX_DESCRIPTION_LENGTH then
    return { ok = false, code = "INVALID_INPUT" }
  end
  local authorKey = actorKey(actor)
  if not authorKey then return { ok = false, code = "AUTHORITY_UNAVAILABLE" } end
  local fingerprint = hash({ seasonId = seasonId, state = nextState, expectedRevision = expectedRevision,
    reason = reason, actorKey = authorKey })
  if not fingerprint then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local existing = store.operations[operationId]
  if existing then
    if existing.fingerprint == fingerprint then
      return { ok = true, value = existing.result.seasonId, revision = existing.result.revision, idempotent = true }
    end
    return { ok = false, code = "OPERATION_CONFLICT" }
  end
  local season = store.seasons[seasonId]
  if type(season) ~= "table" then return { ok = false, code = "SEASON_NOT_FOUND" } end
  local currentRevision = season.currentRevision
  local revision, revisionReason = Roster.NextRevision(currentRevision, expectedRevision)
  if not revision then return { ok = false, code = revisionReason } end
  local current = season.revisions[tostring(currentRevision)]
  if type(current) ~= "table" then return { ok = false, code = "ROSTER_SCHEMA_UNSUPPORTED" } end
  if not VALID_LIFECYCLE_STATES[current.lifecycleState] then
    return { ok = false, code = "SEASON_READ_ONLY" }
  end
  local fromLifecycle = season.activationAdopted == true and current.lifecycleState == "REVIEW"
    and "ACTIVE" or current.lifecycleState
  local toLifecycle = nextState == "OPEN" and "REGISTRATION_OPEN" or "REVIEW"
  local now = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time()
  if nextState == "OPEN" then
    local windowReason = registrationWindowError(current)
    if windowReason then return { ok = false, code = windowReason } end
  end
  local transitionAllowed, transitionReason = Roster.ValidateLifecycleTransition(fromLifecycle, toLifecycle, current, now)
  if not transitionAllowed then return { ok = false, code = transitionReason } end
  if nextState == "OPEN" then
    if current.registrationStartAt and now < current.registrationStartAt then
      return { ok = false, code = "REGISTRATION_NOT_OPEN" }
    end
  end
  local staged = Dibs.DeepCopy(store)
  season = staged.seasons[seasonId]
  current = season.revisions[tostring(currentRevision)]
  local record = Dibs.DeepCopy(current)
  record.revision, record.parentRevision, record.parentHash = revision, currentRevision, current.contentHash
  record.action, record.operationId, record.changeReason = "REGISTRATION_STATE_CHANGED", operationId, reason
  record.registrationState = nextState
  record.lifecycleState = nextState == "OPEN" and "REGISTRATION_OPEN" or "REVIEW"
  record.updatedAt = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time()
  record.updatedBy = authorKey
  record.contentHash = recordHash(record)
  if not record.contentHash then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local audit, auditReason = appendAudit(staged, {
    operationId = operationId, action = "REGISTRATION_STATE_CHANGED", actorKey = record.updatedBy,
    seasonId = seasonId, revision = revision, reason = reason,
  })
  if not audit then return { ok = false, code = auditReason } end
  season.revisions[tostring(revision)] = record
  season.currentRevision = revision
  staged.operations[operationId] = { fingerprint = fingerprint, result = { seasonId = seasonId, revision = revision } }
  local db = Dibs.GetDB()
  db.seasonalRoster = staged
  if Dibs.SyncV2 and Dibs.SyncV2.BroadcastSeasonalRosterDigest then
    pcall(Dibs.SyncV2.BroadcastSeasonalRosterDigest, seasonId)
  end
  return { ok = true, value = seasonId, revision = revision }
end

function Roster.CompleteSeason(seasonId, expectedRevision, operationId, reason, actor)
  local store, storeReason = getStore()
  if not store then return { ok = false, code = storeReason } end
  local allowed, permissionReason = mutationPermission("season.complete", actor)
  if not allowed then return { ok = false, code = permissionReason } end
  reason = type(reason) == "string" and reason:match("^%s*(.-)%s*$") or ""
  if type(seasonId) ~= "string" or #seasonId > 96 or not wholeNumber(expectedRevision)
    or not operationIdValid(operationId) or #reason < 1 or #reason > MAX_DESCRIPTION_LENGTH then
    return { ok = false, code = #reason < 1 and "REASON_REQUIRED" or "INVALID_INPUT" }
  end
  local authorKey = actorKey(actor)
  if not authorKey then return { ok = false, code = "AUTHORITY_UNAVAILABLE" } end
  local fingerprint = hash({ seasonId = seasonId, expectedRevision = expectedRevision,
    reason = reason, actorKey = authorKey, action = "SEASON_COMPLETED" })
  if not fingerprint then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local existing = store.operations[operationId]
  if existing then
    if existing.fingerprint == fingerprint then
      return { ok = true, value = existing.result.seasonId, revision = existing.result.revision, idempotent = true }
    end
    return { ok = false, code = "OPERATION_CONFLICT" }
  end
  local season = store.seasons[seasonId]
  if type(season) ~= "table" then return { ok = false, code = "SEASON_NOT_FOUND" } end
  local currentRevision = season.currentRevision
  local revision, revisionReason = Roster.NextRevision(currentRevision, expectedRevision)
  if not revision then return { ok = false, code = revisionReason } end
  local current = season.revisions and season.revisions[tostring(currentRevision)]
  if type(current) ~= "table" then return { ok = false, code = "ROSTER_SCHEMA_UNSUPPORTED" } end
  local now = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time()
  if not VALID_LIFECYCLE_STATES[current.lifecycleState] then
    return { ok = false, code = "SEASON_READ_ONLY" }
  end
  local fromLifecycle = season.activationAdopted == true
    and (current.lifecycleState == "REVIEW" or current.lifecycleState == "READY") and "ACTIVE" or current.lifecycleState
  local transitionAllowed, transitionReason = Roster.ValidateLifecycleTransition(fromLifecycle, "COMPLETED", current, now)
  if not transitionAllowed then return { ok = false, code = transitionReason } end
  local staged = Dibs.DeepCopy(store)
  season = staged.seasons[seasonId]
  local record = Dibs.DeepCopy(current)
  record.revision, record.parentRevision, record.parentHash = revision, currentRevision, current.contentHash
  record.action, record.operationId, record.changeReason = "SEASON_COMPLETED", operationId, reason
  record.endAt, record.registrationState = now, "CLOSED"
  record.lifecycleState = "COMPLETED"
  record.updatedAt, record.updatedBy = now, authorKey
  record.contentHash = recordHash(record)
  if not record.contentHash then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local audit, auditReason = appendAudit(staged, { operationId = operationId,
    action = "SEASON_COMPLETED", actorKey = authorKey, seasonId = seasonId,
    revision = revision, reason = reason })
  if not audit then return { ok = false, code = auditReason } end
  season.revisions[tostring(revision)], season.currentRevision = record, revision
  staged.operations[operationId] = { fingerprint = fingerprint,
    result = { seasonId = seasonId, revision = revision } }
  Dibs.GetDB().seasonalRoster = staged
  if Dibs.SyncV2 and Dibs.SyncV2.BroadcastSeasonalRosterDigest then
    pcall(Dibs.SyncV2.BroadcastSeasonalRosterDigest, seasonId)
  end
  return { ok = true, value = seasonId, revision = revision }
end

function Roster.UpsertOwnEnrollment(seasonId, input, expectedRevision, operationId)
  local store, storeReason = getStore()
  if not store then return { ok = false, code = storeReason } end
  if type(seasonId) ~= "string" or #seasonId > 96 or not operationIdValid(operationId) then
    return { ok = false, code = "INVALID_INPUT" }
  end
  local ownerKey, identityReason = currentActorKey()
  if not ownerKey then return { ok = false, code = identityReason } end
  local season = store.seasons[seasonId]
  if type(season) ~= "table" then return { ok = false, code = "SEASON_NOT_FOUND" } end
  local config = season.revisions and season.revisions[tostring(season.currentRevision)]
  if type(config) ~= "table" then return { ok = false, code = "ROSTER_SCHEMA_UNSUPPORTED" } end
  local readOnlyReason = seasonReadOnlyReason(config)
  if readOnlyReason then return { ok = false, code = readOnlyReason } end
  local registrationStatus = seasonLifecycle(config).registrationStatus
  if registrationStatus == "SCHEDULED" then return { ok = false, code = "REGISTRATION_NOT_OPEN" } end
  if registrationStatus ~= "OPEN" then return { ok = false, code = "REGISTRATION_CLOSED" } end
  local valid, normalized = validateEnrollmentInput(input, config)
  if not valid then return { ok = false, code = normalized } end

  local enrollmentId = input.enrollmentId
  local current
  if enrollmentId ~= nil then
    if type(enrollmentId) ~= "string" or #enrollmentId > 96 then return { ok = false, code = "INVALID_INPUT" } end
    current = season.enrollments and season.enrollments[enrollmentId]
    if type(current) ~= "table" then return { ok = false, code = "ENROLLMENT_NOT_FOUND" } end
    if current.ownerCharacterKey ~= ownerKey then return { ok = false, code = "OWNER_MISMATCH" } end
  else
    for id, candidate in pairs(season.enrollments or {}) do
      if type(candidate) == "table" and candidate.characterKey == normalized.characterKey then
        if candidate.ownerCharacterKey ~= ownerKey then return { ok = false, code = "OWNER_MISMATCH" } end
        if expectedRevision == nil or expectedRevision == 0 then
          local createFingerprint = hash({ seasonId = seasonId, input = normalized, enrollmentId = nil,
            expectedRevision = 0, ownerCharacterKey = ownerKey })
          local replay = createFingerprint and operationReplay(store, operationId, createFingerprint)
          if replay then return replay end
          return { ok = false, code = "CHARACTER_ALREADY_ENROLLED" }
        end
        enrollmentId, current = id, candidate
        break
      end
    end
  end
  if normalized.categoryId == "CORE_RAIDER" and (not current or current.categoryId ~= "CORE_RAIDER"
    or normalized.requestedPath ~= "CORE_PROGRESSION") then
    return { ok = false, code = "CORE_PROMOTION_NOT_ELIGIBLE" }
  end
  for id, candidate in pairs(season.enrollments or {}) do
    if id ~= enrollmentId and type(candidate) == "table" and candidate.characterKey == normalized.characterKey
      and candidate.status ~= "REMOVED" then
      return { ok = false, code = "CHARACTER_ALREADY_ENROLLED" }
    end
  end

  local currentRevision = current and tonumber(current.revision) or 0
  local expected = expectedRevision == nil and 0 or expectedRevision
  if not wholeNumber(currentRevision) or not wholeNumber(expected) then return { ok = false, code = "STALE_REVISION" } end
  local fingerprint = hash({ seasonId = seasonId, input = normalized, enrollmentId = enrollmentId,
    expectedRevision = expected, ownerCharacterKey = ownerKey })
  if not fingerprint then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local replay = operationReplay(store, operationId, fingerprint)
  if replay then return replay end
  if (current and currentRevision ~= expected) or (not current and expected ~= 0) then
    return { ok = false, code = "STALE_REVISION" }
  end

  local staged = Dibs.DeepCopy(store)
  local stagedSeason = staged.seasons[seasonId]
  if not enrollmentId then
    local id, idReason = nextRecordId(staged, "enrollment")
    if not id then return { ok = false, code = idReason } end
    enrollmentId = id
  end
  local now = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time()
  local previousHash = current and current.contentHash or "GENESIS"
  local record = current and Dibs.DeepCopy(current) or { enrollmentId = enrollmentId, seasonId = seasonId,
    ownerCharacterKey = ownerKey, createdAt = now, status = "PENDING_REVIEW" }
  record.characterKey, record.character = normalized.characterKey, normalized.character
  record.categoryId, record.categoryName = normalized.categoryId, normalized.categoryName
  record.categoryDescription, record.categoryVersion = normalized.categoryDescription, normalized.categoryVersion
  record.categorySeasonRevision = normalized.categorySeasonRevision
  record.requestedPath = normalized.requestedPath
  record.primarySpec, record.secondarySpec = normalized.primarySpec, normalized.secondarySpec
  record.roles, record.revision = normalized.roles, currentRevision + 1
  record.updatedAt, record.updatedBy, record.operationId = now, ownerKey, operationId
  record.parentRevision, record.parentHash = currentRevision, previousHash
  record.action = "ENROLLMENT_UPSERT"
  record.contentHash = recordHash(record)
  if not record.contentHash then return { ok = false, code = "HASH_UNAVAILABLE" } end
  stagedSeason.enrollments[enrollmentId] = record
  bumpRosterRevision(stagedSeason)
  stagedSeason.enrollmentRevisions = stagedSeason.enrollmentRevisions or {}
  stagedSeason.enrollmentRevisions[enrollmentId] = stagedSeason.enrollmentRevisions[enrollmentId] or {}
  stagedSeason.enrollmentRevisions[enrollmentId][tostring(record.revision)] = Dibs.DeepCopy(record)
  local audit, auditReason = appendAudit(staged, { operationId = operationId,
    action = current and "ENROLLMENT_UPDATED" or "ENROLLMENT_CREATED", actorKey = ownerKey,
    seasonId = seasonId, recordId = enrollmentId, revision = record.revision, reason = "PLAYER_SELF_SERVICE" })
  if not audit then return { ok = false, code = auditReason } end
  staged.operations[operationId] = { fingerprint = fingerprint,
    result = { enrollmentId = enrollmentId, revision = record.revision } }
  Dibs.GetDB().seasonalRoster = staged
  if Dibs.SyncV2 and Dibs.SyncV2.BroadcastSeasonalEnrollmentDigest then
    pcall(Dibs.SyncV2.BroadcastSeasonalEnrollmentDigest, seasonId, enrollmentId)
  end
  return { ok = true, value = enrollmentId, revision = record.revision }
end

function Roster.WithdrawOwnEnrollment(seasonId, enrollmentId, expectedRevision, operationId)
  local store, storeReason = getStore()
  if not store then return { ok = false, code = storeReason } end
  if type(seasonId) ~= "string" or #seasonId > 96 or type(enrollmentId) ~= "string"
    or #enrollmentId > 96 or not wholeNumber(expectedRevision) or not operationIdValid(operationId) then
    return { ok = false, code = "INVALID_INPUT" }
  end
  local ownerKey, identityReason = currentActorKey()
  if not ownerKey then return { ok = false, code = identityReason } end
  local season = store.seasons[seasonId]
  if type(season) ~= "table" then return { ok = false, code = "SEASON_NOT_FOUND" } end
  local config = season.revisions and season.revisions[tostring(season.currentRevision)]
  if type(config) ~= "table" then return { ok = false, code = "ROSTER_SCHEMA_UNSUPPORTED" } end
  local readOnlyReason = seasonReadOnlyReason(config)
  if readOnlyReason then return { ok = false, code = readOnlyReason } end
  local registrationStatus = seasonLifecycle(config).registrationStatus
  if registrationStatus == "SCHEDULED" then return { ok = false, code = "REGISTRATION_NOT_OPEN" } end
  if registrationStatus ~= "OPEN" then return { ok = false, code = "REGISTRATION_CLOSED" } end
  local current = season.enrollments and season.enrollments[enrollmentId]
  if type(current) ~= "table" then return { ok = false, code = "ENROLLMENT_NOT_FOUND" } end
  if current.ownerCharacterKey ~= ownerKey then return { ok = false, code = "OWNER_MISMATCH" } end
  local fingerprint = hash({ seasonId = seasonId, enrollmentId = enrollmentId,
    expectedRevision = expectedRevision, ownerCharacterKey = ownerKey, action = "WITHDRAW" })
  if not fingerprint then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local replay = operationReplay(store, operationId, fingerprint)
  if replay then return replay end
  if current.revision ~= expectedRevision then return { ok = false, code = "STALE_REVISION" } end

  local staged = Dibs.DeepCopy(store)
  local record = staged.seasons[seasonId].enrollments[enrollmentId]
  local previousHash = record.contentHash or "GENESIS"
  record.status, record.revision = "WITHDRAWN", record.revision + 1
  record.updatedAt, record.updatedBy, record.operationId = (Dibs.GetTimestamp and Dibs.GetTimestamp()) or time(), ownerKey, operationId
  record.parentRevision, record.parentHash = record.revision - 1, previousHash
  record.action = "ENROLLMENT_WITHDRAWN"
  bumpRosterRevision(staged.seasons[seasonId])
  record.contentHash = nil
  record.contentHash = recordHash(record)
  if not record.contentHash then return { ok = false, code = "HASH_UNAVAILABLE" } end
  staged.seasons[seasonId].enrollmentRevisions = staged.seasons[seasonId].enrollmentRevisions or {}
  staged.seasons[seasonId].enrollmentRevisions[enrollmentId] = staged.seasons[seasonId].enrollmentRevisions[enrollmentId] or {}
  staged.seasons[seasonId].enrollmentRevisions[enrollmentId][tostring(record.revision)] = Dibs.DeepCopy(record)
  local audit, auditReason = appendAudit(staged, { operationId = operationId, action = "ENROLLMENT_WITHDRAWN",
    actorKey = ownerKey, seasonId = seasonId, recordId = enrollmentId, revision = record.revision,
    reason = "PLAYER_WITHDRAWAL" })
  if not audit then return { ok = false, code = auditReason } end
  staged.operations[operationId] = { fingerprint = fingerprint,
    result = { enrollmentId = enrollmentId, revision = record.revision } }
  Dibs.GetDB().seasonalRoster = staged
  if Dibs.SyncV2 and Dibs.SyncV2.BroadcastSeasonalEnrollmentDigest then
    pcall(Dibs.SyncV2.BroadcastSeasonalEnrollmentDigest, seasonId, enrollmentId)
  end
  return { ok = true, value = enrollmentId, revision = record.revision }
end

function Roster.GetCurrentRevision(seasonId)
  local store, reason = getStore()
  if not store then return nil, reason end
  local season = store.seasons[seasonId]
  if type(season) ~= "table" then return 0, "SEASON_NOT_FOUND", "GENESIS" end
  local revision = tonumber(season.currentRevision)
  local record = revision and season.revisions and season.revisions[tostring(revision)]
  if not wholeNumber(revision) or type(record) ~= "table" then return nil, "ROSTER_SCHEMA_UNSUPPORTED" end
  return revision, nil, record.contentHash
end

function Roster.GetSyncRevision(seasonId, revision)
  local store, reason = getStore()
  if not store then return nil, reason end
  if type(seasonId) ~= "string" or #seasonId > 96 or not wholeNumber(tonumber(revision)) then return nil, "INVALID_INPUT" end
  local season = store.seasons[seasonId]
  local record = type(season) == "table" and season.revisions and season.revisions[tostring(revision)]
  if type(record) ~= "table" then return nil, "SEASON_REVISION_NOT_FOUND" end
  return Dibs.DeepCopy(record)
end

function Roster.GetSyncDigests()
  local store, reason = getStore()
  if not store then return nil, reason end
  local ids = {}
  for seasonId in pairs(store.seasons) do ids[#ids + 1] = seasonId end
  table.sort(ids)
  local digests = {}
  for _, seasonId in ipairs(ids) do
    local season = store.seasons[seasonId]
    local revision = type(season) == "table" and tonumber(season.currentRevision)
    local record = revision and season.revisions and season.revisions[tostring(revision)]
    if wholeNumber(revision) and type(record) == "table" and type(record.contentHash) == "string" then
      digests[#digests + 1] = { seasonId = seasonId, revision = revision, contentHash = record.contentHash }
    end
    for enrollmentId, enrollment in pairs(type(season) == "table" and season.enrollments or {}) do
      if type(enrollment) == "table" and wholeNumber(tonumber(enrollment.revision))
        and type(enrollment.contentHash) == "string" then
        digests[#digests + 1] = { seasonId = seasonId, enrollmentId = enrollmentId,
          ownerCharacterKey = enrollment.ownerCharacterKey, revision = enrollment.revision,
          contentHash = enrollment.contentHash }
      end
    end
  end
  return digests
end

local function parseEnrollmentEntityId(entityId)
  if type(entityId) ~= "string" then return nil end
  local seasonId, enrollmentId = entityId:match("^([^#]+)#([^#]+)$")
  if not seasonId or #seasonId > 96 or #enrollmentId > 96 then return nil end
  return seasonId, enrollmentId
end

function Roster.GetSyncEntityState(entityId)
  local store, reason = getStore()
  if not store then return nil, reason end
  local seasonId, enrollmentId = parseEnrollmentEntityId(entityId)
  if enrollmentId then
    local season = store.seasons[seasonId]
    local enrollment = type(season) == "table" and season.enrollments and season.enrollments[enrollmentId]
    if type(enrollment) ~= "table" then return 0, "ENROLLMENT_NOT_FOUND", "GENESIS" end
    return enrollment.revision, nil, enrollment.contentHash
  end
  return Roster.GetCurrentRevision(entityId)
end

function Roster.GetSyncEntityRevision(entityId, revision)
  local store, reason = getStore()
  if not store then return nil, reason end
  local seasonId, enrollmentId = parseEnrollmentEntityId(entityId)
  if enrollmentId then
    if not wholeNumber(tonumber(revision)) then return nil, "INVALID_INPUT" end
    local season = store.seasons[seasonId]
    local history = type(season) == "table" and season.enrollmentRevisions
      and season.enrollmentRevisions[enrollmentId]
    local record = type(history) == "table" and history[tostring(revision)]
    return type(record) == "table" and Dibs.DeepCopy(record) or nil, "ENROLLMENT_REVISION_NOT_FOUND"
  end
  return Roster.GetSyncRevision(entityId, revision)
end

function Roster.IsEnrollmentEntity(entityId)
  return parseEnrollmentEntityId(entityId) ~= nil
end

function Roster.ApplySyncRevision(record, sender, transfer)
  local store, storeReason = getStore()
  if not store then return false, storeReason end
  if type(record) ~= "table" or type(transfer) ~= "table" then return false, "INVALID_ROSTER_REVISION" end
  local resolved = Dibs.Identity and Dibs.Identity.ResolveRosterMember and Dibs.Identity.ResolveRosterMember(sender)
  if type(resolved) ~= "table" or resolved.status ~= "RESOLVED" then return false, "AUTHORITY_UNAVAILABLE" end
  local enrollmentSeasonId, enrollmentId = parseEnrollmentEntityId(transfer.entityId)
  if enrollmentId then
    if type(record.seasonId) ~= "string" or record.seasonId ~= enrollmentSeasonId
      or record.enrollmentId ~= enrollmentId or tonumber(record.revision) ~= tonumber(transfer.revision)
      or record.contentHash ~= transfer.contentHash or transfer.entityType ~= Roster.SYNC_ENTITY
      or not operationIdValid(record.operationId) or not wholeNumber(record.updatedAt)
      or (record.action ~= "ENROLLMENT_UPSERT" and record.action ~= "ENROLLMENT_WITHDRAWN"
        and record.action ~= "ENROLLMENT_ADMIN_CORRECTED" and record.action ~= "CORE_PROMOTION_APPROVED")
      or type(record.ownerCharacterKey) ~= "string" or #record.ownerCharacterKey > 96
      or type(record.updatedBy) ~= "string" then return false, "INVALID_ENROLLMENT_REVISION" end
    local isAdminCorrection = record.action == "ENROLLMENT_ADMIN_CORRECTED"
      or record.action == "CORE_PROMOTION_APPROVED"
    if isAdminCorrection then
      if resolved.role ~= "gm" and resolved.role ~= "officer" then return false, "GUILD_ADMIN_REQUIRED" end
      if record.updatedBy ~= resolved.memberKey or type(record.changeReason) ~= "string"
        or #record.changeReason < 1 or #record.changeReason > MAX_DESCRIPTION_LENGTH then
        return false, "INVALID_ENROLLMENT_REVISION"
      end
    else
      if resolved.memberKey ~= record.ownerCharacterKey and resolved.role ~= "gm" and resolved.role ~= "officer" then
        return false, "ENROLLMENT_OWNER_MISMATCH"
      end
      if record.updatedBy ~= record.ownerCharacterKey and resolved.role ~= "gm" and resolved.role ~= "officer" then
        return false, "ENROLLMENT_ACTOR_MISMATCH"
      end
    end
    local season = store.seasons[enrollmentSeasonId]
    if type(season) ~= "table" then return false, "SEASON_NOT_FOUND" end
    local config = season.revisions and season.revisions[tostring(season.currentRevision)]
    if type(config) ~= "table" then return false, "ROSTER_SCHEMA_UNSUPPORTED" end
    if not VALID_LIFECYCLE_STATES[config.lifecycleState] then return false, "SEASON_READ_ONLY" end
    local validInput = Roster.ValidateSeasonInput({ name = config.name, description = config.description,
      registrationState = config.registrationState, categories = config.categories,
      categoryCatalog = config.categoryCatalog or (config.categories == nil and {} or nil),
      raidRules = config.raidRules, promotionPolicy = config.promotionPolicy,
      rulesRevision = config.rulesRevision,
      identitySeasonId = config.identitySeasonId, startAt = config.startAt,
      endAt = config.endAt, registrationStartAt = config.registrationStartAt,
    registrationEndAt = config.registrationEndAt, raidSchedule = config.raidSchedule,
    raidDifficulties = config.raidDifficulties, raidRules = config.raidRules })
    if not validInput then return false, "ROSTER_SCHEMA_UNSUPPORTED" end
    if recordHash(record) ~= record.contentHash then return false, "CONTENT_HASH_MISMATCH" end
    local current = season.enrollments and season.enrollments[enrollmentId]
    local currentRevision = type(current) == "table" and tonumber(current.revision) or 0
    if tonumber(record.revision) <= currentRevision then
      local known = season.enrollmentRevisions and season.enrollmentRevisions[enrollmentId]
        and season.enrollmentRevisions[enrollmentId][tostring(record.revision)]
      if known and known.contentHash == record.contentHash then return true, "IDEMPOTENT_REPLAY" end
      if tonumber(record.revision) < currentRevision then return true, "STALE_ROSTER_REVISION" end
      return false, "ROSTER_CONFLICT"
    end
    local parentHash = current and current.contentHash or "GENESIS"
    if tonumber(record.revision) ~= currentRevision + 1 then return false, "ROSTER_PARENT_MISSING" end
    if record.parentRevision ~= currentRevision or record.parentHash ~= parentHash then return false, "ROSTER_PARENT_MISMATCH" end
    local enrollmentConfig = config
    local categoryRevision = tonumber(record.categorySeasonRevision)
    if wholeNumber(categoryRevision) then
      enrollmentConfig = season.revisions and season.revisions[tostring(categoryRevision)]
      if type(enrollmentConfig) ~= "table" then return false, "ROSTER_PARENT_MISSING" end
    elseif not categoryById(config, record.categoryId, true) then
      -- Legacy enrollments did not store their source revision. Find the
      -- latest known season definition that still explains their old ID.
      for revision = tonumber(season.currentRevision) or 0, 1, -1 do
        local candidate = season.revisions and season.revisions[tostring(revision)]
        if type(candidate) == "table" and categoryById(candidate, record.categoryId, true) then
          enrollmentConfig = candidate
          break
        end
      end
    end
    local normalizedOK, normalized = validateEnrollmentInput({ character = record.character,
      categoryId = record.categoryId, primarySpec = record.primarySpec,
      secondarySpec = record.secondarySpec, roles = record.roles,
      requestedPath = record.requestedPath }, enrollmentConfig)
    local validStatus = record.action == "ENROLLMENT_WITHDRAWN" and record.status == "WITHDRAWN"
      or record.action == "ENROLLMENT_ADMIN_CORRECTED"
        and (record.status == "PENDING_REVIEW" or record.status == "ACTIVE" or record.status == "REJECTED"
          or record.status == "WITHDRAWN" or record.status == "REMOVED")
      or record.action == "CORE_PROMOTION_APPROVED" and record.status == "ACTIVE"
      or record.action == "ENROLLMENT_UPSERT" and (record.status == "ACTIVE" or record.status == "PENDING_REVIEW")
    if not normalizedOK or normalized.characterKey ~= record.characterKey or not validStatus
      or normalized.requestedPath ~= (record.requestedPath or "STANDARD")
      or record.categoryName ~= nil and record.categoryName ~= normalized.categoryName
      or record.categoryDescription ~= nil and record.categoryDescription ~= normalized.categoryDescription
      or record.categoryVersion ~= nil and record.categoryVersion ~= normalized.categoryVersion
      or categoryRevision ~= nil and categoryRevision ~= normalized.categorySeasonRevision then
      return false, "INVALID_ENROLLMENT_REVISION"
    end
    if record.action == "CORE_PROMOTION_APPROVED"
      and (record.categoryId ~= "CORE_RAIDER" or record.requestedPath ~= "CORE_PROGRESSION"
        or not wholeNumber(record.corePromotionPolicyRevision)
        or record.corePromotionReviewedBy ~= record.updatedBy
        or not wholeNumber(record.corePromotionReviewedAt)
        or type(record.corePromotionReason) ~= "string" or #record.corePromotionReason < 1
        or #record.corePromotionReason > MAX_DESCRIPTION_LENGTH) then
      return false, "INVALID_ENROLLMENT_REVISION"
    end
    local knownOperation = store.operations[record.operationId]
    if knownOperation then
      if knownOperation.fingerprint == record.contentHash then return true, "IDEMPOTENT_REPLAY" end
      return false, "OPERATION_CONFLICT"
    end
    local staged = Dibs.DeepCopy(store)
    local stagedSeason = staged.seasons[enrollmentSeasonId]
    stagedSeason.enrollments = stagedSeason.enrollments or {}
    stagedSeason.enrollmentRevisions = stagedSeason.enrollmentRevisions or {}
    stagedSeason.enrollmentRevisions[enrollmentId] = stagedSeason.enrollmentRevisions[enrollmentId] or {}
    stagedSeason.enrollments[enrollmentId] = Dibs.DeepCopy(record)
    bumpRosterRevision(stagedSeason)
    stagedSeason.enrollmentRevisions[enrollmentId][tostring(record.revision)] = Dibs.DeepCopy(record)
    local event, eventReason = appendAudit(staged, { operationId = record.operationId,
      action = record.action, actorKey = record.updatedBy, seasonId = enrollmentSeasonId,
      recordId = enrollmentId, revision = record.revision,
      reason = isAdminCorrection and record.changeReason or "PLAYER_SELF_SERVICE" })
    if not event then return false, eventReason end
    staged.operations[record.operationId] = { fingerprint = record.contentHash,
      result = { enrollmentId = enrollmentId, revision = record.revision } }
    Dibs.GetDB().seasonalRoster = staged
    return true, "ADOPTED"
  end
  if resolved.role ~= "gm" and resolved.role ~= "officer" then return false, "GUILD_ADMIN_REQUIRED" end
  if type(record.seasonId) ~= "string" or #record.seasonId > 96
    or record.seasonId ~= transfer.entityId or tonumber(record.revision) ~= tonumber(transfer.revision)
    or record.contentHash ~= transfer.contentHash or transfer.entityType ~= Roster.SYNC_ENTITY
    or not operationIdValid(record.operationId) or record.updatedBy ~= resolved.memberKey
    or (record.action ~= "SEASON_CREATED" and record.action ~= "SEASON_DRAFT_UPDATED"
      and record.action ~= "REGISTRATION_STATE_CHANGED"
      and record.action ~= "SEASON_COMPLETED" and record.action ~= "SEASON_ARCHIVED" and record.action ~= "CATEGORY_CATALOG_UPDATED"
      and record.action ~= "SEASON_POLICY_PUBLISHED" and record.action ~= "SEASON_ALLOCATION_PUBLISHED")
    or not wholeNumber(record.updatedAt) then return false, "INVALID_ROSTER_REVISION" end
  local valid, normalizedConfig = Roster.ValidateSeasonInput({ name = record.name, description = record.description,
    registrationState = record.registrationState, categories = record.categories,
    categoryCatalog = record.categoryCatalog or (record.categories == nil and {} or nil),
    raidRules = record.raidRules, promotionPolicy = record.promotionPolicy,
    rulesRevision = record.rulesRevision,
    identitySeasonId = record.identitySeasonId, startAt = record.startAt,
    endAt = record.endAt, registrationStartAt = record.registrationStartAt,
    registrationEndAt = record.registrationEndAt, raidSchedule = record.raidSchedule,
    raidDifficulties = record.raidDifficulties,
    noRankPolicy = record.noRankPolicy,
    lifecycleState = record.lifecycleState })
  if not valid or normalizedConfig.identitySeasonId ~= record.identitySeasonId
    or record.lifecycleState ~= nil and normalizedConfig.lifecycleState ~= record.lifecycleState
    or normalizedConfig.startAt ~= record.startAt or normalizedConfig.endAt ~= record.endAt
    or normalizedConfig.registrationStartAt ~= record.registrationStartAt
    or normalizedConfig.registrationEndAt ~= record.registrationEndAt
    or Dibs.Sync.CalculateContentHash(normalizedConfig.categories) ~= Dibs.Sync.CalculateContentHash(record.categories or {})
    or Dibs.Sync.CalculateContentHash(normalizedConfig.categoryCatalog)
      ~= Dibs.Sync.CalculateContentHash(record.categoryCatalog or normalizedConfig.categoryCatalog)
    or Dibs.Sync.CalculateContentHash(normalizedConfig.raidSchedule) ~= Dibs.Sync.CalculateContentHash(record.raidSchedule or {})
    or Dibs.Sync.CalculateContentHash(normalizedConfig.raidDifficulties)
      ~= Dibs.Sync.CalculateContentHash(record.raidDifficulties or {})
    or normalizedConfig.raidRules ~= (record.raidRules or "")
    or normalizedConfig.promotionPolicy ~= (record.promotionPolicy or "")
    or normalizedConfig.rulesRevision ~= (record.rulesRevision or 1) then
    return false, "INVALID_ROSTER_REVISION"
  end
  if record.noRankPolicy ~= nil and Dibs.Sync.CalculateContentHash(normalizedConfig.noRankPolicy)
    ~= Dibs.Sync.CalculateContentHash(record.noRankPolicy) then return false, "INVALID_ROSTER_REVISION" end
  if record.rankAllocationSnapshot ~= nil then
    local snapshot = record.rankAllocationSnapshot
    local normalizedRules = type(snapshot) == "table" and normalizeRankAllocationSnapshot(snapshot.rules)
    if type(snapshot) ~= "table" or snapshot.schema ~= 1 or not normalizedRules
      or Dibs.Sync.CalculateContentHash(normalizedRules) ~= snapshot.contentHash
      or Dibs.Sync.CalculateContentHash(normalizedRules) ~= Dibs.Sync.CalculateContentHash(snapshot.rules) then
      return false, "INVALID_ROSTER_REVISION"
    end
  end
  if record.action == "SEASON_ALLOCATION_PUBLISHED" and not record.rankAllocationSnapshot then
    return false, "INVALID_ROSTER_REVISION"
  end
  if record.action == "SEASON_CREATED" and (tonumber(record.revision) ~= 1 or record.parentRevision ~= 0 or record.parentHash ~= "GENESIS") then
    return false, "INVALID_ROSTER_REVISION"
  end
  if (record.action == "SEASON_DRAFT_UPDATED" or record.action == "REGISTRATION_STATE_CHANGED" or record.action == "SEASON_COMPLETED"
    or record.action == "CATEGORY_CATALOG_UPDATED" or record.action == "SEASON_POLICY_PUBLISHED"
    or record.action == "SEASON_ALLOCATION_PUBLISHED")
    and (not wholeNumber(record.parentRevision) or type(record.parentHash) ~= "string"
      or type(record.changeReason) ~= "string" or #record.changeReason < 1 or #record.changeReason > MAX_DESCRIPTION_LENGTH) then
    return false, "INVALID_ROSTER_REVISION"
  end
  if record.action == "SEASON_COMPLETED" and (not wholeNumber(record.endAt)
    or record.registrationState ~= "CLOSED") then return false, "INVALID_ROSTER_REVISION" end
  if recordHash(record) ~= record.contentHash then return false, "CONTENT_HASH_MISMATCH" end

  local currentSeason = store.seasons[record.seasonId]
  local currentRevision = type(currentSeason) == "table" and tonumber(currentSeason.currentRevision) or 0
  if currentRevision and tonumber(record.revision) <= currentRevision then
    local existing = currentSeason.revisions and currentSeason.revisions[tostring(record.revision)]
    if existing and existing.contentHash == record.contentHash then return true, "IDEMPOTENT_REPLAY" end
    if tonumber(record.revision) < currentRevision then return true, "STALE_ROSTER_REVISION" end
    return false, "ROSTER_CONFLICT"
  end
  if tonumber(record.revision) ~= (currentRevision or 0) + 1 then return false, "ROSTER_PARENT_MISSING" end
  local expectedParent = currentRevision == 0 and "GENESIS"
    or (currentSeason.revisions[tostring(currentRevision)] or {}).contentHash
  if record.parentRevision ~= currentRevision or record.parentHash ~= expectedParent then return false, "ROSTER_PARENT_MISMATCH" end
  local previousConfig = currentRevision > 0 and currentSeason.revisions[tostring(currentRevision)] or nil
  if currentRevision > 0 and type(previousConfig) ~= "table" then return false, "ROSTER_SCHEMA_UNSUPPORTED" end
  if currentRevision > 0 and not VALID_LIFECYCLE_STATES[previousConfig.lifecycleState] then
    return false, "SEASON_READ_ONLY"
  end
  if record.action == "SEASON_CREATED" then
    if record.lifecycleState ~= "DRAFT" or record.registrationState ~= "DRAFT"
      or not record.startAt or not record.registrationStartAt then
      return false, "INVALID_ROSTER_REVISION"
    end
  elseif record.action == "SEASON_DRAFT_UPDATED" then
    if previousConfig.lifecycleState ~= "DRAFT" or record.lifecycleState ~= "DRAFT"
      or record.registrationState ~= "DRAFT" then return false, "INVALID_TRANSITION" end
  elseif record.action == "REGISTRATION_STATE_CHANGED" then
    local fromLifecycle = previousConfig.lifecycleState
    local toLifecycle = record.registrationState == "OPEN" and "REGISTRATION_OPEN"
      or record.registrationState == "CLOSED" and "REVIEW" or nil
    local transitionAllowed = toLifecycle and Roster.ValidateLifecycleTransition(
      fromLifecycle, toLifecycle, previousConfig, record.updatedAt)
    if not transitionAllowed or record.lifecycleState ~= toLifecycle then return false, "INVALID_TRANSITION" end
  elseif record.action == "SEASON_COMPLETED" then
    local fromLifecycle = currentSeason.activationAdopted == true
      and (previousConfig.lifecycleState == "REVIEW" or previousConfig.lifecycleState == "READY")
      and "ACTIVE" or previousConfig.lifecycleState
    local transitionAllowed = Roster.ValidateLifecycleTransition(
      fromLifecycle, "COMPLETED", previousConfig, record.updatedAt)
    if not transitionAllowed or record.lifecycleState ~= "COMPLETED"
      or record.endAt ~= record.updatedAt then return false, "INVALID_TRANSITION" end
  elseif record.action == "SEASON_ARCHIVED" then
    local transitionAllowed = Roster.ValidateLifecycleTransition(previousConfig.lifecycleState, "ARCHIVED", previousConfig, record.updatedAt)
    if not transitionAllowed or record.lifecycleState ~= "ARCHIVED" then return false, "INVALID_TRANSITION" end
  elseif record.action == "SEASON_POLICY_PUBLISHED" then
    local immutableFields = { "name", "description", "registrationState", "lifecycleState", "identitySeasonId",
      "startAt", "endAt", "registrationStartAt", "registrationEndAt" }
    for _, field in ipairs(immutableFields) do
      if record[field] ~= previousConfig[field] then return false, "INVALID_ROSTER_REVISION" end
    end
    if Dibs.Sync.CalculateContentHash(record.raidSchedule or {})
        ~= Dibs.Sync.CalculateContentHash(previousConfig.raidSchedule or {})
      or Dibs.Sync.CalculateContentHash(record.categoryCatalog or {})
        ~= Dibs.Sync.CalculateContentHash(previousConfig.categoryCatalog or {})
      or Dibs.Sync.CalculateContentHash(record.categories or {})
        ~= Dibs.Sync.CalculateContentHash(previousConfig.categories or {})
      or tonumber(record.rulesRevision) ~= (tonumber(previousConfig.rulesRevision) or 1) + 1
      or (record.raidRules or "") == (previousConfig.raidRules or "")
        and (record.promotionPolicy or "") == (previousConfig.promotionPolicy or "") then
      return false, "INVALID_ROSTER_REVISION"
    end
  elseif record.action == "SEASON_ALLOCATION_PUBLISHED" then
    local immutableFields = { "name", "description", "registrationState", "lifecycleState", "identitySeasonId",
      "startAt", "endAt", "registrationStartAt", "registrationEndAt" }
    for _, field in ipairs(immutableFields) do
      if record[field] ~= previousConfig[field] then return false, "INVALID_ROSTER_REVISION" end
    end
    if (record.lifecycleState ~= "REVIEW" and record.lifecycleState ~= "READY")
      or record.registrationState ~= "CLOSED"
      or Dibs.Sync.CalculateContentHash(record.raidSchedule or {})
        ~= Dibs.Sync.CalculateContentHash(previousConfig.raidSchedule or {})
      or Dibs.Sync.CalculateContentHash(record.raidDifficulties or {})
        ~= Dibs.Sync.CalculateContentHash(previousConfig.raidDifficulties or {})
      or Dibs.Sync.CalculateContentHash(record.categoryCatalog or {})
        ~= Dibs.Sync.CalculateContentHash(previousConfig.categoryCatalog or {})
      or Dibs.Sync.CalculateContentHash(record.categories or {})
        ~= Dibs.Sync.CalculateContentHash(previousConfig.categories or {})
      or (record.raidRules or "") ~= (previousConfig.raidRules or "")
      or (record.promotionPolicy or "") ~= (previousConfig.promotionPolicy or "")
      or Dibs.Sync.CalculateContentHash(record.noRankPolicy or { mode = "UNCONFIGURED" })
        ~= Dibs.Sync.CalculateContentHash(previousConfig.noRankPolicy or { mode = "UNCONFIGURED" }) then
      return false, "INVALID_ROSTER_REVISION"
    end
  end
  local knownOperation = store.operations[record.operationId]
  if knownOperation then
    if knownOperation.fingerprint == record.contentHash then return true, "IDEMPOTENT_REPLAY" end
    return false, "OPERATION_CONFLICT"
  end

  local staged = Dibs.DeepCopy(store)
  local stagedSeason = staged.seasons[record.seasonId]
  if not stagedSeason then stagedSeason = { seasonId = record.seasonId, currentRevision = 0, revisions = {}, enrollments = {} } end
  local copiedRecord = Dibs.DeepCopy(record)
  stagedSeason.revisions[tostring(record.revision)] = copiedRecord
  stagedSeason.currentRevision = record.revision
  staged.seasons[record.seasonId] = stagedSeason
  local auditReason = (record.action == "SEASON_DRAFT_UPDATED" or record.action == "REGISTRATION_STATE_CHANGED" or record.action == "SEASON_COMPLETED"
    or record.action == "CATEGORY_CATALOG_UPDATED" or record.action == "SEASON_POLICY_PUBLISHED"
    or record.action == "SEASON_ALLOCATION_PUBLISHED")
    and record.changeReason or (record.description or record.name)
  local event, eventReason = appendAudit(staged, { operationId = record.operationId, action = record.action,
    actorKey = record.updatedBy, seasonId = record.seasonId, revision = record.revision, reason = auditReason })
  if not event then return false, eventReason end
  staged.operations[record.operationId] = { fingerprint = record.contentHash,
    result = { seasonId = record.seasonId, revision = record.revision } }
  if record.action == "SEASON_CREATED" then
    if not Dibs.Seasons or type(Dibs.Seasons.CreateDraft) ~= "function" then return false, "SEASON_SERVICE_UNAVAILABLE" end
    local nativeSeason = Dibs.Seasons.GetById(record.seasonId)
    if nativeSeason then
      if nativeSeason.name ~= record.name then return false, "SEASON_ID_CONFLICT" end
    elseif not Dibs.Seasons.CreateDraft(record.name, record.seasonId) then
      return false, "SEASON_ID_CONFLICT"
    end
  end
  Dibs.GetDB().seasonalRoster = staged
  return true, "ADOPTED"
end

-- Completion services keep staging detached from SavedVariables. The compact
-- activation entity references independently transported immutable identities.
local function confirmed(value)
  return value == true or (type(value) == "table" and value.confirmed == true)
end

local function activationAuthority(sender)
  local allowed, reason = mutationPermission("season.activate", sender)
  if not allowed then return nil, reason end
  local state = Dibs.Governance and Dibs.Governance.GetAuthorityState()
  if not state or state.state ~= "ACTIVE" or not state.coordinator
    or state.coordinator.memberKey ~= actorKey(sender) then return nil, "CURRENT_COORDINATOR_REQUIRED" end
  return state
end

local function activationCohort(season)
  local cohort = {}
  for id, enrollment in pairs(season.enrollments or {}) do
    if enrollment.status == "ACTIVE" then cohort[id] = true end
  end
  return cohort
end

local function notifyActivation(seasonId, batch)
  if batch then pcall(Dibs.Ledger.NotifySeasonAllocationBatch, batch) end
  publicProjectionCache, publicProjectionCacheOrder = {}, {}
  if Dibs.SyncV2 and Dibs.SyncV2.BroadcastSeasonalRosterDigest then
    pcall(Dibs.SyncV2.BroadcastSeasonalRosterDigest, seasonId)
  end
  if Dibs.SyncV2 and Dibs.SyncV2.BroadcastSeasonActivationDigest then
    pcall(Dibs.SyncV2.BroadcastSeasonActivationDigest, seasonId)
  end
end

function Roster.ActivateSeason(seasonId, previewId, expectedRevision, operationId, reason, actor, confirmation)
  local store, storeReason = getStore()
  if not store then return { ok = false, code = storeReason } end
  local authority, authorityReason = activationAuthority(actor or Dibs.GetPlayerName())
  if not authority then return { ok = false, code = authorityReason } end
  if not confirmed(confirmation) then return { ok = false, code = "CONFIRMATION_REQUIRED" } end
  if not operationIdValid(operationId) or not wholeNumber(expectedRevision)
    or type(reason) ~= "string" or not reason:match("%S") or #reason > 500 then
    return { ok = false, code = "REASON_REQUIRED" }
  end
  local fingerprint = hash({ action = "SEASON_ACTIVATED", seasonId = seasonId, previewId = previewId,
    expectedRevision = expectedRevision, reason = reason, actorKey = actorKey(actor) })
  if not fingerprint then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local replay = operationReplay(store, operationId, fingerprint)
  if replay then return replay end
  local season = store.seasons[seasonId]
  if not season then return { ok = false, code = "SEASON_NOT_FOUND" } end
  if season.currentRevision ~= expectedRevision then return { ok = false, code = "STALE_REVISION" } end
  if season.activationManifest then return { ok = false, code = "SEASON_ALREADY_ACTIVE" } end
  local prepared, prepareReason = Roster.PrepareActivationManifest(seasonId, previewId, operationId, actor)
  if not prepared then return { ok = false, code = prepareReason } end
  local valid, validReason, preview = Roster.ValidateActivationManifest(prepared, actor)
  if not valid then return { ok = false, code = validReason } end
  local db = Dibs.GetDB()
  local batch, batchReason = Dibs.Ledger.PrepareSeasonAllocationBatch(seasonId, preview.rows,
    operationId, actor, reason, preview.sourceLedgerRevision, "INITIALIZE")
  if not batch then return { ok = false, code = batchReason } end
  local staged = Dibs.DeepCopy(db)
  staged.ledgers[batch.ledgerId], staged.ledger = batch.ledger, batch.ledger
  local savedSeason = staged.seasonalRoster.seasons[seasonId]
  savedSeason.activationIdentities = {}
  local references = {}
  for _, identity in ipairs(preview.identities) do
    local entityId = "identity:" .. seasonId .. ":" .. identity.personGroupId
    local snapshot = { schema = 1, recordClass = "SEASON_IDENTITY", guildKey = Dibs.GetGuildKey(),
      seasonId = seasonId, entityId = entityId, revision = 1, personGroupId = identity.personGroupId,
      mainCharacterKey = identity.mainCharacterKey, memberKeys = Dibs.DeepCopy(identity.memberKeys),
      authorKey = actorKey(actor) }
    for _, row in ipairs(preview.rows) do
      if row.characterKey == identity.mainCharacterKey then
        snapshot.rankIndex, snapshot.rankName = row.rankIndex, row.rankName
      end
    end
    snapshot.contentHash = recordHash(snapshot)
    if not snapshot.contentHash then return { ok = false, code = "HASH_UNAVAILABLE" } end
    local encodedIdentity = Dibs.Ace3 and Dibs.Ace3.Serialize and Dibs.Ace3.Serialize(snapshot)
    if #entityId > 194 or type(encodedIdentity) ~= "string" or #encodedIdentity > 8192 then
      return { ok = false, code = "SEASON_IDENTITY_TOO_LARGE" }
    end
    savedSeason.activationIdentities[entityId] = snapshot
    references[#references + 1] = { entityType = "SEASON_IDENTITY", entityId = entityId,
      revision = 1, contentHash = snapshot.contentHash }
  end
  table.sort(references, function(a, b) return a.entityId < b.entityId end)
  local dependencies = Dibs.DeepCopy(preview.dependencies)
  -- These are local optimistic concurrency tokens, never remote identities.
  dependencies.rosterGeneration, dependencies.identityRevision = nil, nil
  dependencies.sourceLedgerRevision = nil
  local canonical = batch.ledger.canonical
  local manifest = { schema = 1, recordClass = "SEASON_ACTIVATION_MANIFEST", state = "COMMITTED",
    guildKey = Dibs.GetGuildKey(), seasonId = seasonId, revision = 1, operationId = operationId,
    manifestId = prepared.manifestId, preparedBy = actorKey(actor), committedAt = Dibs.GetTimestamp(),
    dependencies = dependencies, identities = references, enrollments = {},
    ledger = { ledgerId = batch.ledgerId, epoch = canonical.epoch, sequence = canonical.nextSeq - 1,
      rootHash = canonical.rootHash } }
  for id, enrollment in pairs(savedSeason.enrollments) do
    if enrollment.status == "ACTIVE" then manifest.enrollments[id] = enrollment.revision end
  end
  manifest.contentHash = recordHash(manifest)
  if not manifest.contentHash then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local wireManifest = Dibs.Sync and Dibs.Sync._activationTransport
    and Dibs.Sync._activationTransport.compactManifest(manifest) or manifest
  local encoded = Dibs.Ace3 and Dibs.Ace3.Serialize and Dibs.Ace3.Serialize(wireManifest)
  if type(encoded) ~= "string" or #encoded > 8192 then return { ok = false, code = "ACTIVATION_MANIFEST_TOO_LARGE" } end
  savedSeason.activationManifest, savedSeason.activationAdopted = manifest, true
  savedSeason.activationCohort = activationCohort(savedSeason)
  local audit, auditReason = appendAudit(staged.seasonalRoster, { operationId = operationId,
    action = "SEASON_ACTIVATED", actorKey = actorKey(actor), seasonId = seasonId,
    revision = expectedRevision, reason = reason })
  if not audit then return { ok = false, code = auditReason } end
  staged.seasonalRoster.operations[operationId] = { fingerprint = fingerprint,
    result = { seasonId = seasonId, revision = expectedRevision, manifestId = manifest.manifestId } }
  for id, native in pairs(staged.seasons) do native.isActive = id == seasonId end
  staged.seasons[seasonId].isDraft = false
  staged.currentSeasonId = seasonId
  valid, validReason = Roster.ValidateActivationManifest(prepared, actor)
  if not valid then return { ok = false, code = validReason } end
  valid, validReason = Dibs.Ledger.ValidateSeasonAllocationBatch(batch, actor)
  if not valid then return { ok = false, code = validReason } end
  local committed, commitReason = Dibs.Seasons.CommitSeasonGuildBucket(db, staged)
  if not committed then return { ok = false, code = commitReason } end
  notifyActivation(seasonId, batch)
  return { ok = true, value = seasonId, revision = expectedRevision, manifestId = manifest.manifestId }
end

function Roster.GetActivationManifest(seasonId)
  local store, reason = getStore()
  if not store then return nil, reason end
  local season = store.seasons[seasonId]
  return season and season.activationAdopted == true and Dibs.DeepCopy(season.activationManifest) or nil
end
Roster.GetActivationSyncPayload = Roster.GetActivationManifest

function Roster.GetActivationManifestState(seasonId)
  local manifest, reason = Roster.GetActivationManifest(seasonId)
  return manifest and manifest.revision or 0, reason, manifest and manifest.contentHash or nil
end

function Roster.GetActivationIdentitySyncPayload(entityId)
  local store, reason = getStore()
  if not store then return nil, reason end
  for _, season in pairs(store.seasons) do
    local snapshot = season.activationIdentities and season.activationIdentities[entityId]
    if snapshot then return Dibs.DeepCopy(snapshot) end
  end
end

function Roster.ApplyActivationIdentitySyncPayload(snapshot, sender)
  local store, reason = getStore()
  if not store then return false, reason end
  local resolved = Dibs.Identity.ResolveRosterMember(sender)
  if not resolved or resolved.status ~= "RESOLVED" or (resolved.role ~= "gm" and resolved.role ~= "officer") then
    return false, "GUILD_ADMIN_REQUIRED"
  end
  if type(snapshot) ~= "table" or snapshot.schema ~= 1 or snapshot.recordClass ~= "SEASON_IDENTITY"
    or snapshot.guildKey ~= Dibs.GetGuildKey() or snapshot.revision ~= 1
    or type(snapshot.authorKey) ~= "string" or type(snapshot.personGroupId) ~= "string"
    or #snapshot.personGroupId > 128 or type(snapshot.memberKeys) ~= "table"
    or #snapshot.memberKeys < 1 or #snapshot.memberKeys > 100
    or snapshot.entityId ~= "identity:" .. tostring(snapshot.seasonId) .. ":" .. tostring(snapshot.personGroupId)
    or recordHash(snapshot) ~= snapshot.contentHash then return false, "INVALID_SEASON_IDENTITY" end
  local found, seen = false, {}
  for _, key in ipairs(snapshot.memberKeys) do
    if type(key) ~= "string" or #key > 96 or seen[key]
      or Dibs.Identity.CanonicalMemberKey(key) ~= key then return false, "INVALID_SEASON_IDENTITY" end
    seen[key], found = true, found or key == snapshot.mainCharacterKey
  end
  if not found then return false, "INVALID_SEASON_IDENTITY" end
  local governance = Dibs.Governance.GetAuthorityState()
  local knownAuthor = governance and governance.coordinator and governance.coordinator.memberKey == snapshot.authorKey
  if not knownAuthor then
    for _, ledger in pairs(Dibs.GetDB().ledgers or {}) do
      for _, commit in pairs((ledger.canonical or {}).commits or {}) do
        if commit.coordinator and commit.coordinator.memberKey == snapshot.authorKey then knownAuthor = true; break end
      end
      if knownAuthor then break end
    end
  end
  if not knownAuthor then return false, "IDENTITY_AUTHOR_NOT_CANONICAL_WRITER" end
  local season = store.seasons[snapshot.seasonId]
  if not season then return false, "SEASON_NOT_FOUND" end
  local existing = season.activationIdentities and season.activationIdentities[snapshot.entityId]
  if existing then return existing.contentHash == snapshot.contentHash,
    existing.contentHash == snapshot.contentHash and "IDEMPOTENT_REPLAY" or "SEASON_IDENTITY_CONFLICT" end
  local staged = Dibs.DeepCopy(store)
  season = staged.seasons[snapshot.seasonId]
  season.activationIdentities = season.activationIdentities or {}
  season.activationIdentities[snapshot.entityId] = Dibs.DeepCopy(snapshot)
  Dibs.GetDB().seasonalRoster = staged
  return true, "ADOPTED"
end

local function missingActivationDependencies(manifest, sender)
  local store = getStore()
  local season = store and store.seasons[manifest.seasonId]
  local missing, deps = {}, manifest.dependencies
  local config = season and season.revisions[tostring(deps.seasonRevision)]
  if not config or config.contentHash ~= deps.seasonConfigHash then
    missing[#missing + 1] = { entityType = Roster.SYNC_ENTITY, entityId = manifest.seasonId,
      revision = deps.seasonRevision, contentHash = deps.seasonConfigHash }
  end
  for _, reference in ipairs(manifest.identities) do
    local entityId = reference.entityId
    local snapshot = season and season.activationIdentities and season.activationIdentities[entityId]
    if not snapshot or snapshot.contentHash ~= reference.contentHash then missing[#missing + 1] = {
      entityType = reference.entityType, entityId = entityId,
      revision = reference.revision, contentHash = reference.contentHash } end
  end
  for id, revision in pairs(manifest.enrollments) do
    local enrollment = season and season.enrollmentRevisions and season.enrollmentRevisions[id]
      and season.enrollmentRevisions[id][tostring(revision)]
    if not enrollment then missing[#missing + 1] = {
      entityType = Roster.SYNC_ENTITY, entityId = manifest.seasonId .. "#" .. id,
      revision = revision } end
  end
  local ledger = manifest.ledger
  local db = Dibs.GetDB()
  local localLedger = db.ledgers and db.ledgers[ledger.ledgerId]
  local canonical = localLedger and localLedger.canonical
  local commit = canonical and canonical.commits[tostring(ledger.epoch) .. ":" .. tostring(ledger.sequence)]
  if commit and (not commit.coordinator or commit.coordinator.memberKey ~= manifest.preparedBy
    or not commit.transaction or not commit.transaction.reconciliation
    or commit.transaction.reconciliation.operationId ~= manifest.operationId
    or commit.transaction.source ~= "seasonal_activation") then return nil, "ACTIVATION_AUTHOR_MISMATCH" end
  if not canonical or (not commit and (canonical.epoch ~= ledger.epoch
      or canonical.nextSeq - 1 ~= ledger.sequence or canonical.rootHash ~= ledger.rootHash))
    or (commit and commit.commitHash ~= ledger.rootHash) then
    missing[#missing + 1] = { entityType = "LEDGER", entityId = ledger.ledgerId,
      revision = ledger.sequence, contentHash = ledger.rootHash }
  end
  if #missing > 0 then return missing end
  if not commit then
    local authority = Dibs.Governance.GetAuthorityState()
    if not authority or authority.ledgerEpoch ~= ledger.epoch
      or not authority.coordinator or authority.coordinator.memberKey ~= manifest.preparedBy then
      return nil, "ACTIVATION_AUTHOR_MISMATCH"
    end
  end
  local preview, reason = Roster.PreviewActivation(manifest.seasonId, sender, adoptionPreviewToken, manifest)
  if not preview then return nil, reason end
  for _, key in ipairs({ "seasonConfigHash", "approvedRosterHash", "identityHash", "guildRosterHash",
    "rankRulesHash", "noRankPolicyHash", "allocationRowsHash" }) do
    if preview.dependencies[key] ~= deps[key] then
      return { { entityType = Roster.SYNC_ENTITY, entityId = manifest.seasonId,
        revision = deps.seasonRevision, contentHash = deps.seasonConfigHash, dependency = key } }
    end
  end
  return {}
end

function Roster.GetActivationMissingDependencies(seasonId)
  local store, reason = getStore()
  if not store then return {}, reason end
  local season = store.seasons[seasonId]
  local pending = season and season.pendingActivation
  if not pending then return {} end
  return missingActivationDependencies(pending.manifest, pending.sender)
end

function Roster.ApplyActivationManifest(manifest, sender, transfer)
  local store, reason = getStore()
  if not store then return false, reason end
  local resolved = Dibs.Identity.ResolveRosterMember(sender)
  if not resolved or resolved.status ~= "RESOLVED" or (resolved.role ~= "gm" and resolved.role ~= "officer") then
    return false, "GUILD_ADMIN_REQUIRED"
  end
  if type(manifest) ~= "table" or manifest.schema ~= 1 or manifest.state ~= "COMMITTED"
    or manifest.recordClass ~= "SEASON_ACTIVATION_MANIFEST" or manifest.guildKey ~= Dibs.GetGuildKey()
    or type(manifest.seasonId) ~= "string" or #manifest.seasonId > 96 or manifest.revision ~= 1
    or not operationIdValid(manifest.operationId) or type(manifest.preparedBy) ~= "string"
    or type(manifest.identities) ~= "table" or #manifest.identities > 1000
    or type(manifest.enrollments) ~= "table"
    or type(manifest.dependencies) ~= "table" or type(manifest.ledger) ~= "table"
    or not wholeNumber(manifest.dependencies.seasonRevision) or type(manifest.dependencies.seasonConfigHash) ~= "string"
    or not wholeNumber(manifest.ledger.sequence) or not wholeNumber(manifest.ledger.epoch)
    or type(manifest.ledger.rootHash) ~= "string" or recordHash(manifest) ~= manifest.contentHash then
    return false, "INVALID_ACTIVATION_MANIFEST"
  end
  if manifest.rows ~= nil or manifest.transactions ~= nil then return false, "INVALID_ACTIVATION_MANIFEST" end
  local seenIdentities, previousEntityId = {}, nil
  for _, reference in ipairs(manifest.identities) do
    if type(reference) ~= "table" or reference.entityType ~= "SEASON_IDENTITY"
      or type(reference.entityId) ~= "string" or #reference.entityId < 1 or #reference.entityId > 194
      or reference.revision ~= 1 or type(reference.contentHash) ~= "string"
      or #reference.contentHash < 1 or #reference.contentHash > 128 or seenIdentities[reference.entityId]
      or (previousEntityId and reference.entityId <= previousEntityId) then
      return false, "INVALID_ACTIVATION_MANIFEST"
    end
    seenIdentities[reference.entityId], previousEntityId = true, reference.entityId
  end
  count = 0
  for id, revision in pairs(manifest.enrollments) do
    count = count + 1
    if count > 1000 or type(id) ~= "string" or #id > 96 or not wholeNumber(revision) then
      return false, "INVALID_ACTIVATION_MANIFEST" end
  end
  if transfer and (transfer.entityId ~= manifest.seasonId or transfer.contentHash ~= manifest.contentHash
    or tonumber(transfer.revision) ~= manifest.revision) then return false, "INVALID_ACTIVATION_MANIFEST" end
  local season = store.seasons[manifest.seasonId]
  if not season then return false, "SEASON_NOT_FOUND" end
  local prior = season.activationManifest or (season.pendingActivation and season.pendingActivation.manifest)
  if prior and prior.contentHash ~= manifest.contentHash then return false, "ACTIVATION_CONFLICT" end
  if season.activationAdopted then return true, "IDEMPOTENT_REPLAY" end
  local missing, missingReason = missingActivationDependencies(manifest, sender)
  if not missing then return false, missingReason end
  local db, staged = Dibs.GetDB(), Dibs.DeepCopy(Dibs.GetDB())
  local target = staged.seasonalRoster.seasons[manifest.seasonId]
  if #missing > 0 then
    target.pendingActivation = { manifest = Dibs.DeepCopy(manifest), sender = sender }
    local committed, commitReason = Dibs.Seasons.CommitSeasonGuildBucket(db, staged)
    return committed, committed and "ACTIVATION_STAGED" or commitReason
  end
  target.activationManifest, target.activationAdopted, target.pendingActivation = Dibs.DeepCopy(manifest), true, nil
  target.activationCohort = activationCohort(target)
  local current = staged.seasonalRoster.seasons[staged.currentSeasonId]
  local currentManifest = current and current.activationManifest
  local historical = currentManifest and currentManifest.ledger.ledgerId == manifest.ledger.ledgerId
    and (currentManifest.ledger.epoch > manifest.ledger.epoch or
      (currentManifest.ledger.epoch == manifest.ledger.epoch and currentManifest.ledger.sequence > manifest.ledger.sequence))
  if historical then
    local committed, commitReason = Dibs.Seasons.CommitSeasonGuildBucket(db, staged)
    return committed, committed and "ACTIVATION_HISTORICAL" or commitReason
  end
  for id, native in pairs(staged.seasons) do native.isActive = id == manifest.seasonId end
  staged.seasons[manifest.seasonId].isDraft = false
  staged.currentSeasonId = manifest.seasonId
  local committed, commitReason = Dibs.Seasons.CommitSeasonGuildBucket(db, staged)
  if committed then notifyActivation(manifest.seasonId) end
  return committed, committed and "ACTIVATION_ADOPTED" or commitReason
end
Roster.ApplyActivationSyncPayload = Roster.ApplyActivationManifest

function Roster.RetryPendingActivation()
  local store, reason = getStore()
  if not store then return false, reason end
  local pending = {}
  for _, season in pairs(store.seasons) do
    if season.pendingActivation then pending[#pending + 1] = Dibs.DeepCopy(season.pendingActivation) end
  end
  local adopted = 0
  for _, entry in ipairs(pending) do
    local ok, status = Roster.ApplyActivationManifest(entry.manifest, entry.sender)
    if ok and status == "ACTIVATION_ADOPTED" then adopted = adopted + 1 end
  end
  return true, "ACTIVATION_RETRIED", adopted
end
Roster.RetryPendingActivations = Roster.RetryPendingActivation

function Roster.PreviewSeasonReconciliation(seasonId, actor)
  local allowed, reason = mutationPermission("season.reconcile", actor)
  if not allowed then return nil, reason end
  local preview, previewReason = Roster.PreviewActivation(seasonId, actor, "RECONCILIATION")
  if not preview then return nil, previewReason end
  local season = Dibs.GetDB().seasonalRoster.seasons[seasonId]
  if not season.activationAdopted then return nil, "SEASON_NOT_ACTIVE" end
  for _, row in ipairs(preview.rows) do
    row.assignedAllocation = Dibs.Ledger.GetPlayerAllocation(row.character, seasonId)
    row.delta = row.allocation - row.assignedAllocation
  end
  preview.kind = "SEASONAL_ALLOCATION_DRIFT"
  preview.previewId = hash({ kind = preview.kind, dependencies = preview.dependencies,
    rows = preview.rows, blockers = preview.blockers })
  reconciliationPreviews[preview.previewId] = { seasonId = seasonId }
  -- The cache is advisory and bounded; apply always recomputes dependencies.
  local count = 0
  for key in pairs(reconciliationPreviews) do
    count = count + 1
    if count > 16 then reconciliationPreviews[key] = nil end
  end
  return preview
end

function Roster.ApplySeasonReconciliation(actor, previewId, expectedRevisions, operationId, reason, confirmation)
  local store, storeReason = getStore()
  if not store then return { ok = false, code = storeReason } end
  local allowed, permissionReason = mutationPermission("season.reconcile", actor)
  if not allowed then return { ok = false, code = permissionReason } end
  if not confirmed(confirmation) then return { ok = false, code = "CONFIRMATION_REQUIRED" } end
  if type(expectedRevisions) ~= "table" or not operationIdValid(operationId)
    or type(reason) ~= "string" or not reason:match("%S") or #reason > 500 then
    return { ok = false, code = "INVALID_INPUT" }
  end
  local seasonId = expectedRevisions.seasonId or (reconciliationPreviews[previewId] or {}).seasonId
  local fingerprint = hash({ action = "SEASON_RECONCILED", previewId = previewId,
    expectedRevisions = expectedRevisions, actorKey = actorKey(actor), reason = reason })
  if not fingerprint then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local replay = operationReplay(store, operationId, fingerprint)
  if replay then return replay end
  local preview, previewReason = Roster.PreviewSeasonReconciliation(seasonId, actor)
  if not preview then return { ok = false, code = previewReason } end
  if not preview.ready then return { ok = false, code = "RECONCILIATION_BLOCKED" } end
  if preview.previewId ~= previewId or preview.seasonRevision ~= expectedRevisions.seasonRevision
    or preview.rosterRevision ~= expectedRevisions.rosterRevision
    or preview.sourceLedgerRevision ~= expectedRevisions.sourceLedgerRevision then
    return { ok = false, code = "STALE_RECONCILIATION_PREVIEW" }
  end
  local batch, batchReason = Dibs.Ledger.PrepareSeasonAllocationBatch(seasonId, preview.rows,
    operationId, actor, reason, preview.sourceLedgerRevision, "DRIFT")
  if not batch then return { ok = false, code = batchReason } end
  local db = Dibs.GetDB()
  local staged = Dibs.DeepCopy(db)
  staged.ledgers[batch.ledgerId], staged.ledger = batch.ledger, batch.ledger
  local audit, auditReason = appendAudit(staged.seasonalRoster, { operationId = operationId,
    action = "SEASON_RECONCILED", actorKey = actorKey(actor), seasonId = seasonId,
    revision = preview.seasonRevision, reason = reason })
  if not audit then return { ok = false, code = auditReason } end
  staged.seasonalRoster.operations[operationId] = { fingerprint = fingerprint,
    result = { seasonId = seasonId, revision = preview.seasonRevision } }
  local current = Roster.PreviewSeasonReconciliation(seasonId, actor)
  if not current or current.previewId ~= previewId then return { ok = false, code = "STALE_RECONCILIATION_PREVIEW" } end
  local valid, validationReason = Dibs.Ledger.ValidateSeasonAllocationBatch(batch, actor)
  if not valid then return { ok = false, code = validationReason } end
  local committed, commitReason = Dibs.Seasons.CommitSeasonGuildBucket(db, staged)
  if not committed then return { ok = false, code = commitReason } end
  notifyActivation(seasonId, batch)
  return { ok = true, value = seasonId, revision = preview.seasonRevision, affectedCount = #batch.commits }
end

function Roster.ArchiveSeason(seasonId, expectedRevision, operationId, reason, actor)
  local store, storeReason = getStore()
  if not store then return { ok = false, code = storeReason } end
  local allowed, permissionReason = mutationPermission("season.draft.edit", actor)
  if not allowed then return { ok = false, code = permissionReason } end
  if not operationIdValid(operationId) or type(reason) ~= "string" or not reason:match("%S")
    or #reason > 500 then return { ok = false, code = "REASON_REQUIRED" } end
  local fingerprint = hash({ action = "SEASON_ARCHIVED", seasonId = seasonId,
    expectedRevision = expectedRevision, reason = reason, actorKey = actorKey(actor) })
  local replay = operationReplay(store, operationId, fingerprint)
  if replay then return replay end
  local season = store.seasons[seasonId]
  if not season then return { ok = false, code = "SEASON_NOT_FOUND" } end
  local revision, revisionReason = Roster.NextRevision(season.currentRevision, expectedRevision)
  if not revision then return { ok = false, code = revisionReason } end
  local current = season.revisions[tostring(season.currentRevision)]
  local valid, validationReason = Roster.ValidateLifecycleTransition(current.lifecycleState, "ARCHIVED", current)
  if not valid then return { ok = false, code = validationReason } end
  local staged = Dibs.DeepCopy(store)
  local record = Dibs.DeepCopy(current)
  record.parentRevision, record.parentHash, record.revision = season.currentRevision, current.contentHash, revision
  record.action, record.operationId, record.changeReason = "SEASON_ARCHIVED", operationId, reason
  record.lifecycleState, record.updatedAt, record.updatedBy = "ARCHIVED", Dibs.GetTimestamp(), actorKey(actor)
  record.contentHash = recordHash(record)
  if not record.contentHash then return { ok = false, code = "HASH_UNAVAILABLE" } end
  local audit, auditReason = appendAudit(staged, { operationId = operationId, action = record.action,
    actorKey = actorKey(actor), seasonId = seasonId, revision = revision, reason = reason })
  if not audit then return { ok = false, code = auditReason } end
  staged.seasons[seasonId].revisions[tostring(revision)] = record
  staged.seasons[seasonId].currentRevision = revision
  staged.operations[operationId] = { fingerprint = fingerprint, result = { seasonId = seasonId, revision = revision } }
  Dibs.GetDB().seasonalRoster = staged
  notifyActivation(seasonId)
  return { ok = true, value = seasonId, revision = revision }
end

-- Disabled history deliberately avoids getStore: it is a public allowlist
-- projection and never creates or repairs SavedVariables.
function Roster.GetPreservedHistory(actor)
  if type(IsInGuild) ~= "function" or not IsInGuild() then return nil, "GUILD_UNAVAILABLE" end
  local db = Dibs.GetDB()
  local store = db.seasonalRoster
  local result = {}
  local role = Dibs.Permissions and Dibs.Permissions.GetGuildRole(actor or Dibs.GetPlayerName())
  local admin = (role == "gm" or role == "officer") and actorKey(actor) == actorKey(Dibs.GetPlayerName())
  for id, season in pairs(type(store) == "table" and store.seasons or {}) do
    local config = season.revisions and season.revisions[tostring(season.currentRevision)]
    if config then
      local entry = { seasonId = id, revision = season.currentRevision, name = config.name,
        raidRules = config.raidRules, promotionPolicy = config.promotionPolicy,
        lifecycle = seasonLifecycle(config), revisionHistory = {} }
      for rev = math.max(1, season.currentRevision - 49), season.currentRevision do
        local record = season.revisions[tostring(rev)]
        if record then entry.revisionHistory[#entry.revisionHistory + 1] = { revision = rev,
          action = record.action, updatedAt = record.updatedAt, lifecycleState = record.lifecycleState,
          raidRules = record.raidRules, promotionPolicy = record.promotionPolicy } end
        if record and admin then
          local summary = entry.revisionHistory[#entry.revisionHistory]
          summary.updatedBy, summary.reason = record.updatedBy, record.changeReason
        end
      end
      result[#result + 1] = entry
    end
  end
  table.sort(result, function(a, b) return a.seasonId < b.seasonId end)
  return result
end
Roster.ListSeasonsReadOnly = Roster.GetPreservedHistory

function Roster.GetSeasonIdentityReview(seasonId, actor)
  local store, reason = getStore()
  if not store then return nil, reason end
  if not store.seasons[seasonId] then return nil, "SEASON_NOT_FOUND" end
  local state = Dibs.GetDB().characterEligibility or {}
  local actorIdentity = actorKey(actor)
  local localIdentity = actorKey(Dibs.GetPlayerName())
  if actorIdentity ~= localIdentity then return nil, "OWNER_MISMATCH" end
  local role = Dibs.Permissions.GetGuildRole(actor)
  local admin = role == "gm" or role == "officer"
  local result = { revision = tonumber(state.revision) or 0, relationships = {}, mainChanges = {} }
  for _, record in pairs(state.relationships or {}) do
    if record.seasonId == seasonId and (admin or record.declaredBy == actorIdentity) then
      result.relationships[#result.relationships + 1] = Dibs.DeepCopy(record)
    end
  end
  for _, record in pairs(state.mainChanges or {}) do
    if record.seasonId == seasonId and (admin or record.requestedBy == actorIdentity) then
      result.mainChanges[#result.mainChanges + 1] = Dibs.DeepCopy(record)
    end
  end
  return result
end

local function identityMutation(kind, seasonId, input, expectedRevision, operationId, actor, decision, reason)
  local store, storeReason = getStore()
  if not store then return { ok = false, code = storeReason } end
  local season = store.seasons[seasonId]
  if not season then return { ok = false, code = "SEASON_NOT_FOUND" } end
  local config = season.revisions[tostring(season.currentRevision)]
  if seasonReadOnlyReason(config) or config.lifecycleState == "COMPLETED" then
    return { ok = false, code = "SEASON_READ_ONLY" }
  end
  actor = actor or Dibs.GetPlayerName()
  if actorKey(actor) ~= actorKey(Dibs.GetPlayerName()) then return { ok = false, code = "OWNER_MISMATCH" } end
  if not operationIdValid(operationId) or not wholeNumber(expectedRevision) then return { ok = false, code = "INVALID_INPUT" } end
  local fingerprint = hash({ kind = kind, seasonId = seasonId, input = input, expectedRevision = expectedRevision,
    actor = actorKey(actor), decision = decision, reason = reason })
  local existing = store.operations[operationId]
  if existing then
    if existing.fingerprint ~= fingerprint then return { ok = false, code = "OPERATION_CONFLICT" } end
    local result = Dibs.DeepCopy(existing.result)
    result.ok, result.idempotent = true, true
    return result
  end
  local db = Dibs.GetDB()
  if (tonumber((db.characterEligibility or {}).revision) or 0) ~= expectedRevision then
    return { ok = false, code = "STALE_REVISION" }
  end
  local eligibility, record, recordReason = Dibs.CharacterEligibility
  if kind == "DECLARE" or kind == "REQUEST_MAIN" then
    if type(input) ~= "table" then return { ok = false, code = "INVALID_INPUT" } end
    local options = Dibs.DeepCopy(input)
    options.seasonId = seasonId
    if kind == "DECLARE" then record, recordReason = eligibility.DeclareRelationship(options, actor)
    else record, recordReason = eligibility.RequestMainChange(options, actor) end
  else
    local state = db.characterEligibility or {}
    local current = kind == "REVIEW_LINK" and (state.relationships or {})[input] or (state.mainChanges or {})[input]
    if not current or current.seasonId ~= seasonId then return { ok = false, code = "IDENTITY_RECORD_NOT_FOUND" } end
    if type(reason) ~= "string" or not reason:match("%S") or #reason > 500 then return { ok = false, code = "REASON_REQUIRED" } end
    if kind == "REVIEW_LINK" then record, recordReason = eligibility.ReviewRelationship(input, decision, actor, reason)
    elseif decision == "approved" then record, recordReason = eligibility.ApproveMainChange(input,
      { reason = reason, probationDuration = 14 * 86400, outcome = "block" }, actor)
    elseif decision == "rejected" then record, recordReason = eligibility.RejectMainChange(input, actor, reason)
    else return { ok = false, code = "INVALID_MAIN_CHANGE_STATUS" } end
  end
  if not record then return { ok = false, code = recordReason } end
  local result = { value = record.relationshipId or record.changeId,
    revision = (Dibs.GetDB().characterEligibility or {}).revision or expectedRevision, record = record }
  store.operations[operationId] = { fingerprint = fingerprint, result = Dibs.DeepCopy(result) }
  result.ok = true
  return result
end

function Roster.DeclareRelationship(seasonId, input, revision, operationId, actor)
  return identityMutation("DECLARE", seasonId, input, revision, operationId, actor)
end
function Roster.RequestMainChange(seasonId, input, revision, operationId, actor)
  return identityMutation("REQUEST_MAIN", seasonId, input, revision, operationId, actor)
end
function Roster.ReviewRelationship(seasonId, id, decision, revision, operationId, reason, actor)
  return identityMutation("REVIEW_LINK", seasonId, id, revision, operationId, actor, decision, reason)
end
function Roster.ReviewMainChange(seasonId, id, decision, revision, operationId, reason, actor)
  return identityMutation("REVIEW_MAIN", seasonId, id, revision, operationId, actor, decision, reason)
end
Roster.DeclareSeasonRelationship = Roster.DeclareRelationship
Roster.ReviewSeasonRelationship = Roster.ReviewRelationship
Roster.RequestSeasonMainChange = Roster.RequestMainChange
Roster.ReviewSeasonMainChange = Roster.ReviewMainChange
