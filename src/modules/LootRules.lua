local Dibs = _G.Dibs
Dibs.LootRules = Dibs.LootRules or {}

local SCHEMA_VERSION = 1
local DECISION_FIELDS = { adventureGuide = true, rclootcouncil = true }

local function supportedTypes()
  local optionsApi = Dibs.RCOptions
  if type(optionsApi) ~= "table" then
    return nil, "GUILD_LOOT_RULES_UNAVAILABLE"
  end
  local source
  if type(optionsApi.GetSupportedLootRuleTypeValues) == "function" then
    local ok, values = pcall(optionsApi.GetSupportedLootRuleTypeValues)
    if ok then source = values end
  else
    if type(optionsApi.GetLootTypeOptions) ~= "function" then
      return nil, "GUILD_LOOT_RULES_UNAVAILABLE"
    end
    local ok, options = pcall(optionsApi.GetLootTypeOptions)
    if not ok or type(options) ~= "table" or type(options.types) ~= "table" then
      return nil, "GUILD_LOOT_RULES_UNAVAILABLE"
    end
    source = options.types.values
  end
  if type(source) == "function" then
    ok, source = pcall(source)
    if not ok then return nil, "GUILD_LOOT_RULES_UNAVAILABLE" end
  end
  if type(source) ~= "table" then return nil, "GUILD_LOOT_RULES_UNAVAILABLE" end

  local keys, keySet = {}, {}
  for key in pairs(source) do
    if type(key) == "string" and key ~= "" then
      keys[#keys + 1] = key
      keySet[key] = true
    end
  end
  if #keys == 0 then return nil, "GUILD_LOOT_RULES_UNAVAILABLE" end
  table.sort(keys)
  return keys, keySet
end

local function hasOnlyKeys(value, allowed)
  for key in pairs(value) do
    if not allowed[key] then return false end
  end
  return true
end

local function defaultDecision(key, field)
  if field == "adventureGuide" and string.upper(key):gsub("[%s%-]", "_") == "COSMETIC" then
    return false
  end
  return true
end

function Dibs.LootRules.GetSupportedTypes()
  return supportedTypes()
end

function Dibs.LootRules.NormalizeSnapshot(snapshot)
  if type(snapshot) ~= "table" or not hasOnlyKeys(snapshot, { schemaVersion = true, types = true }) then
    return nil, "INVALID_GUILD_LOOT_RULES"
  end
  if snapshot.schemaVersion ~= SCHEMA_VERSION then
    return nil, "UNSUPPORTED_GUILD_LOOT_RULES_SCHEMA"
  end
  if type(snapshot.types) ~= "table" then return nil, "INVALID_GUILD_LOOT_RULES" end

  local keys, supported = supportedTypes()
  if not keys then return nil, supported end
  local normalized = { schemaVersion = SCHEMA_VERSION, types = {} }
  for key, value in pairs(snapshot.types) do
    if type(key) ~= "string" then return nil, "UNSUPPORTED_GUILD_LOOT_TYPE" end
    if type(value) ~= "table" or not hasOnlyKeys(value, { adventureGuide = true, rclootcouncil = true })
      or type(value.adventureGuide) ~= "boolean" or type(value.rclootcouncil) ~= "boolean" then
      return nil, "INVALID_GUILD_LOOT_RULE"
    end
    local targetKey = supported[key] and key or nil
    if not targetKey and Dibs.RCOptions.IsLootTypeCompatibilityKey
      and Dibs.RCOptions.IsLootTypeCompatibilityKey(key) then
      targetKey = false
    end
    if not targetKey and targetKey ~= false and Dibs.RCOptions.GetCanonicalLootTypeKey then
      local canonicalKey = Dibs.RCOptions.GetCanonicalLootTypeKey(key)
      if supported[canonicalKey] then targetKey = canonicalKey end
    end
    if targetKey == nil then return nil, "UNSUPPORTED_GUILD_LOOT_TYPE" end
    if targetKey ~= false then
      local existing = normalized.types[targetKey]
      if existing and (existing.adventureGuide ~= value.adventureGuide
        or existing.rclootcouncil ~= value.rclootcouncil) then
        return nil, "CONFLICTING_GUILD_LOOT_TYPE_ALIASES"
      end
      normalized.types[targetKey] = {
        adventureGuide = value.adventureGuide,
        rclootcouncil = value.rclootcouncil,
      }
    end
  end
  for key in pairs(supported) do
    if normalized.types[key] == nil then
      normalized.types[key] = {
        adventureGuide = defaultDecision(key, "adventureGuide"),
        rclootcouncil = defaultDecision(key, "rclootcouncil"),
      }
    end
  end
  return normalized
end

local function settings()
  local db = Dibs.GetDB and Dibs.GetDB() or {}
  db.settings = db.settings or {}
  return db.settings
end

function Dibs.LootRules.GetDraftSnapshot()
  local keys, keySet = supportedTypes()
  if not keys then return nil, keySet end
  local current = settings()
  local allowed = type(current.dibAllowedTypes) == "table" and current.dibAllowedTypes or {}
  local buttons = type(current.dibRCEnabledTypes) == "table" and current.dibRCEnabledTypes or {}
  local snapshot = { schemaVersion = SCHEMA_VERSION, types = {} }
  for _, key in ipairs(keys) do
    local adventureGuide = allowed[key]
    local rclootcouncil = buttons[key]
    if type(adventureGuide) ~= "boolean" then adventureGuide = defaultDecision(key, "adventureGuide") end
    if type(rclootcouncil) ~= "boolean" then rclootcouncil = defaultDecision(key, "rclootcouncil") end
    snapshot.types[key] = {
      adventureGuide = adventureGuide,
      rclootcouncil = rclootcouncil,
    }
  end
  return snapshot
end

function Dibs.LootRules.SetDraftValue(typeKey, field, value)
  if type(Dibs.Permissions) ~= "table" or type(Dibs.Permissions.IsGM) ~= "function" then
    return false, "GUILD_LOOT_RULES_AUTHORITY_UNAVAILABLE"
  end
  if Dibs.Permissions.IsGM() ~= true then return false, "CURRENT_GUILD_MASTER_REQUIRED" end
  if not DECISION_FIELDS[field] or type(value) ~= "boolean" then
    return false, "INVALID_GUILD_LOOT_RULE"
  end
  local _, keySet = supportedTypes()
  if not keySet then return false, "GUILD_LOOT_RULES_UNAVAILABLE" end
  if type(typeKey) ~= "string" or not keySet[typeKey] then
    return false, "UNSUPPORTED_GUILD_LOOT_TYPE"
  end
  local current = settings()
  local settingKey = field == "adventureGuide" and "dibAllowedTypes" or "dibRCEnabledTypes"
  current[settingKey] = type(current[settingKey]) == "table" and current[settingKey] or {}
  current[settingKey][typeKey] = value
  return true
end

function Dibs.LootRules.GetAuthoritySnapshot()
  if not (Dibs.Seasons and Dibs.Seasons.GetCatalogState and Dibs.Seasons.GetCatalogRecord) then
    return nil, "GUILD_LOOT_RULES_UNAVAILABLE"
  end
  local state = Dibs.Seasons.GetCatalogState()
  local revision = tonumber(state and state.catalogRevision) or 0
  if revision < 1 then return nil, "GUILD_LOOT_RULES_NOT_CONFIGURED" end
  local record = Dibs.Seasons.GetCatalogRecord(revision)
  local raw = record and record.guildConfiguration and record.guildConfiguration.guildLootRules
  if raw == nil then return nil, "GUILD_LOOT_RULES_NOT_CONFIGURED" end
  local normalized, reason = Dibs.LootRules.NormalizeSnapshot(raw)
  if not normalized then return nil, "GUILD_LOOT_RULES_INCOMPATIBLE", reason end
  return normalized, "GUILD_LOOT_RULES_READY", record
end

local function hasLocalDraft()
  local current = settings()
  return (type(current.dibAllowedTypes) == "table" and next(current.dibAllowedTypes) ~= nil)
    or (type(current.dibRCEnabledTypes) == "table" and next(current.dibRCEnabledTypes) ~= nil)
end

local function synchronizationIssue()
  if type(Dibs.Sync) ~= "table" then return nil end
  local synchronization = type(Dibs.Sync.GetSynchronizationStatus) == "function"
    and Dibs.Sync.GetSynchronizationStatus() or {}
  local mismatch = type(synchronization) == "table" and synchronization.lastAddonVersionMismatch
  if type(mismatch) == "table" and mismatch.reasonCode == "ADDON_UPDATE_REQUIRED" then
    return "GUILD_LOOT_RULES_INCOMPATIBLE", mismatch.reasonCode
  end

  local status = type(Dibs.Sync.GetStatus) == "function" and Dibs.Sync.GetStatus() or {}
  local reason = type(status) == "table" and (status.reason or status.reasonCode)
  if type(status) == "table" and (status.syncBehind == true or status.state == "SYNC_BEHIND")
    and type(reason) == "string" and reason:find("SEASON_CATALOG", 1, true) then
    return "GUILD_LOOT_RULES_SYNC_BEHIND", reason
  end
  return nil
end

function Dibs.LootRules.GetStatus()
  local keys, reason = supportedTypes()
  if not keys then return { status = "UNAVAILABLE", reasonCode = reason } end
  local synchronizationStatus, synchronizationReason = synchronizationIssue()
  if synchronizationStatus == "GUILD_LOOT_RULES_INCOMPATIBLE" then
    return { status = synchronizationStatus, reasonCode = synchronizationReason }
  end
  local authority, authorityStatus, detail = Dibs.LootRules.GetAuthoritySnapshot()
  if authority then
    if synchronizationStatus then
      return { status = synchronizationStatus, reasonCode = synchronizationReason }
    end
    return {
      status = "GUILD_LOOT_RULES_READY",
      catalogRevision = detail and detail.catalogRevision,
    }
  end
  if authorityStatus == "GUILD_LOOT_RULES_INCOMPATIBLE" then
    return { status = authorityStatus, reasonCode = detail }
  end
  if synchronizationStatus then
    return { status = synchronizationStatus, reasonCode = synchronizationReason }
  end
  if hasLocalDraft() then return { status = "LOCAL_LEGACY_ONLY" } end
  return { status = "GUILD_LOOT_RULES_NOT_CONFIGURED" }
end

local function currentGM()
  return Dibs.Permissions and type(Dibs.Permissions.IsGM) == "function"
    and Dibs.Permissions.IsGM() == true
end

local function changedTypes(nextSnapshot, currentSnapshot)
  local changed = {}
  for key, value in pairs(nextSnapshot.types) do
    local previous = currentSnapshot and currentSnapshot.types and currentSnapshot.types[key]
    if not previous or previous.adventureGuide ~= value.adventureGuide
      or previous.rclootcouncil ~= value.rclootcouncil then
      changed[#changed + 1] = key
    end
  end
  table.sort(changed)
  return changed
end

function Dibs.LootRules.HasDraftChanges()
  local authority = Dibs.LootRules.GetAuthoritySnapshot()
  if not authority then return false end
  local draft = Dibs.LootRules.GetDraftSnapshot()
  if not draft then return false end
  return #changedTypes(draft, authority) > 0
end

local function publish(snapshot, action)
  if not currentGM() then return false, "CURRENT_GUILD_MASTER_REQUIRED" end
  if not (Dibs.Seasons and Dibs.Seasons.PublishCatalog and Dibs.Seasons.RollbackCatalogPublication)
    or not (Dibs.Sync and Dibs.Sync.RegisterTransport and Dibs.Sync.AnnounceSeasonCatalog) then
    return false, "GUILD_LOOT_RULES_UNAVAILABLE"
  end
  if not Dibs.Sync.RegisterTransport() then return false, "SYNC_UNAVAILABLE" end
  local currentAuthority = Dibs.LootRules.GetAuthoritySnapshot()
  local changes = changedTypes(snapshot, currentAuthority)
  if #changes == 0 and currentAuthority then return true, "GUILD_LOOT_RULES_UNCHANGED" end

  local published, reason, record = Dibs.Seasons.PublishCatalog(
    Dibs.GetPlayerName and Dibs.GetPlayerName() or nil,
    action,
    { guildLootRules = snapshot, changedLootTypes = changes }
  )
  if not published then return false, reason end
  local announced, announceReason = Dibs.Sync.AnnounceSeasonCatalog()
  if not announced then
    Dibs.Seasons.RollbackCatalogPublication(record)
    return false, announceReason or "SYNC_UNAVAILABLE"
  end
  return true, "GUILD_LOOT_RULES_PUBLISHED", record
end

function Dibs.LootRules.Adopt()
  if not currentGM() then return false, "CURRENT_GUILD_MASTER_REQUIRED" end
  local currentAuthority, authorityStatus = Dibs.LootRules.GetAuthoritySnapshot()
  if currentAuthority then return false, "GUILD_LOOT_RULES_ALREADY_ADOPTED" end
  if authorityStatus ~= "GUILD_LOOT_RULES_NOT_CONFIGURED" then return false, authorityStatus end
  local draft, reason = Dibs.LootRules.GetDraftSnapshot()
  if not draft then return false, reason end
  return publish(draft, "GUILD_LOOT_RULES_ADOPT")
end

function Dibs.LootRules.PublishDraft()
  if not currentGM() then return false, "CURRENT_GUILD_MASTER_REQUIRED" end
  local currentAuthority, authorityStatus = Dibs.LootRules.GetAuthoritySnapshot()
  if not currentAuthority then
    return false, authorityStatus == "GUILD_LOOT_RULES_NOT_CONFIGURED"
      and "GUILD_LOOT_RULES_NOT_CONFIGURED" or authorityStatus
  end
  local draft, reason = Dibs.LootRules.GetDraftSnapshot()
  if not draft then return false, reason end
  return publish(draft, "GUILD_LOOT_RULES_PUBLISH")
end

function Dibs.LootRules.GetEffectiveValue(typeKey, field)
  if not DECISION_FIELDS[field] then return nil, "INVALID_GUILD_LOOT_DECISION" end
  local _, keySet = supportedTypes()
  if not keySet then return nil, "GUILD_LOOT_RULES_UNAVAILABLE" end
  if type(typeKey) ~= "string" or not keySet[typeKey] then
    return nil, "UNSUPPORTED_GUILD_LOOT_TYPE"
  end

  local authority, authorityStatus = Dibs.LootRules.GetAuthoritySnapshot()
  if authority then return authority.types[typeKey][field], "GUILD" end
  if authorityStatus ~= "GUILD_LOOT_RULES_NOT_CONFIGURED" then
    return nil, authorityStatus
  end
  local readiness = Dibs.LootRules.GetStatus()
  if readiness.status ~= "LOCAL_LEGACY_ONLY" and readiness.status ~= "GUILD_LOOT_RULES_NOT_CONFIGURED" then
    return nil, readiness.status
  end

  local draft, draftReason = Dibs.LootRules.GetDraftSnapshot()
  if not draft then return nil, draftReason end
  return draft.types[typeKey][field], "LOCAL_LEGACY_ONLY"
end