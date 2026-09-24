--[[
Module: Dibs.Seasons
Layer: Domain / persistence
Purpose: Manage the seasonal allocation boundary.
Responsibilities: Create, select, list, rename, and archive seasons.
Non-responsibilities: Rank amounts and ledger mutations are delegated to RankRules and Ledger.
Dependencies: Dibs.GetDB, Dibs.Permissions, time().
Blizzard events: None directly.  Internal events/messages: None emitted.
SavedVariables: db.seasons, db.currentSeasonId.
RCLootCouncil: None.
Combat safety: Pure data operations; callers still defer UI refreshes in combat.
Invariants: DIBS-RULE-005 and DIBS-RULE-006.
Related docs: docs/developer/data-model.md, docs/officer/configuration.md.
]]

local Dibs = _G.Dibs
Dibs.Seasons = Dibs.Seasons or {}

local CATALOG_SCHEMA, CATALOG_GENESIS_HASH = 1, "GENESIS"
local ensureState

local function copy(value)
  return Dibs.DeepCopy and Dibs.DeepCopy(value) or value
end

local GUILD_SETTING_KEYS = {
  "allowPublicPreDibs", "defaultAllocation", "officerMaxRankIndex", "officerRankIndices",
  "preDibAnnouncementChannel", "preDibOfficerAnnouncementChannel", "preDibAnnouncementTemplate",
  "raidReminderTemplate", "raidReminderMessage", "raidEntryDibPromptsEnabled", "dibAllowedTypes",
  "dibButtonTemplate", "dibRCEnabledTypes", "ejBlockedSubCategories", "installationMode",
}

local function guildConfiguration()
  ensureState()
  local settings, result = Dibs.db.settings or {}, {}
  for _, key in ipairs(GUILD_SETTING_KEYS) do
    if settings[key] ~= nil then result[key] = copy(settings[key]) end
  end
  local eligibility = Dibs.db.characterEligibility
  result.eligibilityPolicies = eligibility and copy(eligibility.policies or {}) or {}
  return result
end

local function applyGuildConfiguration(configuration)
  if type(configuration) ~= "table" then return end
  Dibs.db.settings = Dibs.db.settings or {}
  for _, key in ipairs(GUILD_SETTING_KEYS) do
    if configuration[key] ~= nil then Dibs.db.settings[key] = copy(configuration[key]) end
  end
  if type(configuration.eligibilityPolicies) == "table" then
    Dibs.db.characterEligibility = Dibs.db.characterEligibility or {}
    Dibs.db.characterEligibility.policies = copy(configuration.eligibilityPolicies)
  end
end

local function integer(value)
  return type(value) == "number" and value == math.floor(value)
end

local function catalogState()
  ensureState()
  if type(Dibs.db.seasonCatalog) ~= "table" then
    Dibs.db.seasonCatalog = { schema = CATALOG_SCHEMA, catalogRevision = 0, hash = CATALOG_GENESIS_HASH, records = {}, conflicts = {} }
  end
  local state = Dibs.db.seasonCatalog
  if state.schema ~= CATALOG_SCHEMA then state.schema = CATALOG_SCHEMA end
  if not integer(state.catalogRevision) or state.catalogRevision < 0 then state.catalogRevision = 0 end
  if type(state.hash) ~= "string" or state.hash == "" then state.hash = CATALOG_GENESIS_HASH end
  if type(state.records) ~= "table" then state.records = {} end
  if type(state.conflicts) ~= "table" then state.conflicts = {} end
  return state
end

local function normalizeCatalogSeasons(seasons)
  if type(seasons) ~= "table" then return nil, "INVALID_SEASON_CATALOG" end
  local normalized = {}
  for seasonId, season in pairs(seasons) do
    if type(seasonId) ~= "string" or type(season) ~= "table" or season.id ~= seasonId
      or type(season.name) ~= "string" or season.name == "" or #season.name > 80
      or not integer(season.createdAt) or type(season.isActive) ~= "boolean" or type(season.isArchived) ~= "boolean"
      or (season.updatedAt ~= nil and not integer(season.updatedAt)) or (season.archivedAt ~= nil and not integer(season.archivedAt)) then
      return nil, "INVALID_SEASON_CATALOG"
    end
    normalized[seasonId] = {
      id = season.id, name = season.name, createdAt = season.createdAt, updatedAt = season.updatedAt,
      archivedAt = season.archivedAt, isActive = season.isActive, isArchived = season.isArchived,
    }
  end
  return normalized
end

local function catalogHash(record)
  if not (Dibs.Sync and Dibs.Sync.CalculateContentHash) then return nil end
  return Dibs.Sync.CalculateContentHash({
    schema = record.schema, recordClass = record.recordClass, guildKey = record.guildKey,
    catalogRevision = record.catalogRevision, parentRevision = record.parentRevision, parentHash = record.parentHash,
    authorNameRealm = record.authorNameRealm, authorMemberKey = record.authorMemberKey,
    authorSnapshot = record.authorSnapshot, timestamp = record.timestamp, audit = record.audit,
    currentSeasonId = record.currentSeasonId, seasons = record.seasons, rankRules = record.rankRules,
    guildConfiguration = record.guildConfiguration,
  })
end

local function localWriter(actor)
  if not (Dibs.Identity and Dibs.Identity.CreateSnapshot and Dibs.OperationalPolicy and Dibs.OperationalPolicy.CanWrite) then
    return nil, "SEASON_CATALOG_AUTHORITY_UNAVAILABLE"
  end
  local snapshot, reason = Dibs.Identity.CreateSnapshot(actor)
  if not snapshot then return nil, reason end
  local localSnapshot, localReason = Dibs.Identity.CreateSnapshot(Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
  if not localSnapshot then return nil, localReason end
  if snapshot.memberKey ~= localSnapshot.memberKey then return nil, "LOCAL_ACTOR_REQUIRED" end
  local allowed, allowedReason = Dibs.OperationalPolicy.CanWrite(snapshot.displayName)
  if not allowed then return nil, allowedReason end
  return snapshot
end

local function senderWriter(sender)
  if not (Dibs.Identity and Dibs.Identity.CreateSnapshot and Dibs.OperationalPolicy and Dibs.OperationalPolicy.CanWrite) then
    return nil, "SEASON_CATALOG_AUTHORITY_UNAVAILABLE"
  end
  local snapshot, reason = Dibs.Identity.CreateSnapshot(sender)
  if not snapshot then return nil, reason end
  local allowed, allowedReason = Dibs.OperationalPolicy.CanWrite(snapshot.displayName)
  if not allowed then return nil, allowedReason end
  return snapshot
end

local function validateCatalog(record)
  if type(record) ~= "table" or record.schema ~= CATALOG_SCHEMA or record.recordClass ~= "SEASON_CATALOG"
    or record.guildKey ~= Dibs.GetGuildKey() or not integer(record.catalogRevision) or record.catalogRevision < 1
    or not integer(record.parentRevision) or type(record.parentHash) ~= "string" or type(record.authorNameRealm) ~= "string"
    or type(record.authorMemberKey) ~= "string" or type(record.authorSnapshot) ~= "table"
    or record.authorSnapshot.memberKey ~= record.authorMemberKey or not integer(record.timestamp) or type(record.audit) ~= "table"
    or (record.currentSeasonId ~= nil and type(record.currentSeasonId) ~= "string") then
    return false, "INVALID_SEASON_CATALOG"
  end
  local seasons, seasonReason = normalizeCatalogSeasons(record.seasons)
  if not seasons then return false, seasonReason end
  if catalogHash(record) ~= record.contentHash then return false, "SEASON_CATALOG_HASH_MISMATCH" end
  return true
end

ensureState = function()
  Dibs.db = Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
  if type(Dibs.db.seasons) ~= "table" then
    Dibs.db.seasons = {}
  end
end

function Dibs.Seasons.Create(name)
  ensureState()

  local count = 0
  for _ in pairs(Dibs.db.seasons) do
    count = count + 1
  end

  local seasonName = name and name ~= "" and name or ("Season " .. tostring(count + 1))

  local function nextSeasonId()
    local candidate = nil
    if Dibs.NewId then
      candidate = Dibs.NewId("season")
    end
    if not candidate or candidate == "" then
      candidate = "season-" .. tostring(time()) .. "-" .. tostring(math.random(100000, 999999))
    end
    return tostring(candidate)
  end

  local seasonId = nextSeasonId()
  local guard = 0
  while Dibs.db.seasons[seasonId] and guard < 10 do
    seasonId = nextSeasonId()
    guard = guard + 1
  end

  if Dibs.db.seasons[seasonId] then
    seasonId = seasonId .. "-" .. tostring(time())
  end

  local season = {
    id = seasonId,
    name = seasonName,
    createdAt = time(),
    isActive = true,
    isArchived = false,
    note = "Created by Dibs",
  }

  Dibs.db.seasons[season.id] = season
  Dibs.db.currentSeasonId = season.id
  return season
end

function Dibs.Seasons.GetById(seasonId)
  ensureState()
  if not seasonId then
    return nil
  end

  return Dibs.db.seasons[seasonId]
end

function Dibs.Seasons.GetCurrent()
  ensureState()
  if Dibs.db.currentSeasonId and Dibs.db.seasons[Dibs.db.currentSeasonId] and not Dibs.db.seasons[Dibs.db.currentSeasonId].isArchived then
    return Dibs.db.seasons[Dibs.db.currentSeasonId]
  end

  if not next(Dibs.db.seasons) then
    return Dibs.Seasons.Create("Season 1")
  end
  for _, season in pairs(Dibs.db.seasons) do
    if not season.isArchived then
      Dibs.db.currentSeasonId = season.id
      return season
    end
  end

  Dibs.db.currentSeasonId = nil
  return nil
end

function Dibs.Seasons.GetOrCreateDefault()
  ensureState()

  if not next(Dibs.db.seasons) then
    return Dibs.Seasons.Create("Season 1")
  end

  return Dibs.Seasons.GetCurrent()
end

function Dibs.Seasons.SetCurrent(seasonId)
  ensureState()
  if Dibs.db.seasons[seasonId] and not Dibs.db.seasons[seasonId].isArchived then
    Dibs.db.currentSeasonId = seasonId
    return true
  end

  return false
end

function Dibs.Seasons.List(includeArchived)
  ensureState()
  local seasons = {}
  for _, season in pairs(Dibs.db.seasons) do
    if includeArchived or not season.isArchived then
      table.insert(seasons, season)
    end
  end

  table.sort(seasons, function(a, b)
    return (a.createdAt or 0) < (b.createdAt or 0)
  end)

  return seasons
end

function Dibs.Seasons.CreateSeason(name)
  return Dibs.Seasons.Create(name)
end

function Dibs.Seasons.SetActiveSeason(seasonId)
  local ok = Dibs.Seasons.SetCurrent(seasonId)
  if not ok then
    return nil
  end
  return Dibs.Seasons.GetById(seasonId)
end

function Dibs.Seasons.ListSeasons()
  return Dibs.Seasons.List()
end

function Dibs.Seasons.ArchiveSeason(seasonId)
  ensureState()
  local season = seasonId and Dibs.db.seasons[seasonId] or nil
  if not season then
    return nil
  end

  season.isArchived = true
  season.archivedAt = time()
  season.isActive = false
  if Dibs.db.currentSeasonId == seasonId then
    Dibs.db.currentSeasonId = nil
  end

  Dibs.Seasons.GetCurrent()
  return season
end

function Dibs.Seasons.RenameSeason(seasonId, newName)
  ensureState()
  local season = seasonId and Dibs.db.seasons[seasonId] or nil
  local name = tostring(newName or ""):match("^%s*(.-)%s*$")
  if not season or name == "" then
    return nil
  end
  season.name = name
  season.updatedAt = time()
  return season
end

function Dibs.Seasons.GetCatalogState()
  return copy(catalogState())
end

function Dibs.Seasons.GetGuildConfiguration()
  return guildConfiguration()
end

function Dibs.Seasons.GetCatalogRecord(revision)
  return copy(catalogState().records[tostring(revision)])
end

function Dibs.Seasons.CalculateCatalogHash(record)
  return catalogHash(record or {})
end

function Dibs.Seasons.PublishCatalog(actor, action)
  local author, authorReason = localWriter(actor)
  if not author then return false, authorReason end
  local state = catalogState()
  local seasons, seasonReason = normalizeCatalogSeasons(Dibs.db.seasons)
  if not seasons then return false, seasonReason end
  local record = {
    schema = CATALOG_SCHEMA, recordClass = "SEASON_CATALOG", guildKey = Dibs.GetGuildKey(),
    catalogRevision = state.catalogRevision + 1, parentRevision = state.catalogRevision, parentHash = state.hash,
    authorNameRealm = author.displayName, authorMemberKey = author.memberKey, authorSnapshot = copy(author),
    timestamp = Dibs.GetTimestamp and Dibs.GetTimestamp() or time(), audit = { action = action or "SEASON_CHANGE" },
    currentSeasonId = Dibs.db.currentSeasonId, seasons = seasons, rankRules = copy(Dibs.db.rankRules or {}),
    guildConfiguration = guildConfiguration(),
  }
  record.contentHash = catalogHash(record)
  if not record.contentHash then return false, "CANONICAL_HASH_UNAVAILABLE" end
  local applied, applyReason = Dibs.Seasons.ApplyCatalog(record, author.displayName)
  return applied, applyReason, applied and copy(record) or nil
end

function Dibs.Seasons.ApplyCatalog(record, sender)
  local valid, validationReason = validateCatalog(record)
  if not valid then return false, validationReason end
  local author, authorityReason = senderWriter(sender)
  if not author then return false, authorityReason end
  if author.memberKey ~= record.authorMemberKey then return false, "AUTHOR_SENDER_MISMATCH" end
  local state = catalogState()
  if record.catalogRevision == state.catalogRevision then
    if record.contentHash == state.hash then return true, "IDEMPOTENT_REPLAY", Dibs.Seasons.GetCatalogRecord(record.catalogRevision) end
    table.insert(state.conflicts, { revision = record.catalogRevision, existingHash = state.hash, conflictingHash = record.contentHash, receivedAt = Dibs.GetTimestamp and Dibs.GetTimestamp() or time() })
    return false, "SEASON_CATALOG_CONFLICT"
  end
  if record.catalogRevision < state.catalogRevision then return false, "STALE_SEASON_CATALOG" end
  if record.catalogRevision ~= state.catalogRevision + 1 or record.parentRevision ~= state.catalogRevision or record.parentHash ~= state.hash then
    return false, "SEASON_CATALOG_PARENT_MISSING"
  end
  local mergedSeasons = copy(Dibs.db.seasons)
  for seasonId, season in pairs(record.seasons) do mergedSeasons[seasonId] = copy(season) end
  Dibs.db.seasons = mergedSeasons
  if type(record.rankRules) == "table" then Dibs.db.rankRules = copy(record.rankRules) end
  applyGuildConfiguration(record.guildConfiguration)
  if record.currentSeasonId and Dibs.db.seasons[record.currentSeasonId] and not Dibs.db.seasons[record.currentSeasonId].isArchived then
    Dibs.db.currentSeasonId = record.currentSeasonId
  end
  state.catalogRevision, state.hash = record.catalogRevision, record.contentHash
  state.records[tostring(record.catalogRevision)] = copy(record)
  return true, "SEASON_CATALOG_APPLIED", copy(record)
end
