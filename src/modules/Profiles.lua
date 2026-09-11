--[[
Module: Dibs.Profiles
Layer: Configuration store
Purpose: Save and activate named configuration projections.
Responsibilities: Create, copy, rename, preview, activate, reset, and delete profiles.
Non-responsibilities: Profiles do not alter ledger transactions or history.
Dependencies: Dibs.GetDB, ImportExport, Permissions.
Blizzard events: None directly.  Internal events/messages: None emitted.
SavedVariables: db.profiles and db.settings projection values.
RCLootCouncil: Profile projections may include compatible RC option values only.
Combat safety: Activation is data-only; UI refresh may be deferred.
Invariants: Persisted names remain stable for compatibility.
Related docs: docs/developer/saved-variables.md, docs/officer/configuration.md.
]]

local Dibs = _G.Dibs
Dibs.Profiles = Dibs.Profiles or {}
local M = Dibs.Profiles

local PRESENTATION_KEYS = { "uiScale", "windowWidth", "windowHeight", "defaultTab", "pageSize", "showTooltips", "theme" }
local POLICY_KEYS = { "defaultAllocation", "officerMaxRankIndex", "officerRankIndices", "installationMode", "allowPublicPreDibs", "dibAllowedTypes", "preDibAnnouncementChannel", "preDibOfficerAnnouncementChannel", "raidReminderMessage" }
local function clone(v) return Dibs.DeepCopy and Dibs.DeepCopy(v) or v end
local function scopeName(scope) return scope == "guild" and "guild" or "local" end
local function validName(name) return type(name) == "string" and name:match("^%s*(.-)%s*$") ~= "" and #name <= 60 end
local function safeData(value, depth)
  depth = (depth or 0) + 1; local kind = type(value)
  if depth > 12 or kind == "function" or kind == "userdata" or kind == "thread" then return false end
  if kind == "table" then for k, v in pairs(value) do if not safeData(k, depth) or not safeData(v, depth) then return false end end end
  return true
end
local function charKey()
  local realm = type(GetRealmName) == "function" and GetRealmName() or "unknown-realm"
  return (tostring(Dibs.GetPlayerName and Dibs.GetPlayerName() or "UnknownPlayer") .. "-" .. tostring(realm)):gsub("%s+", "")
end
local function ensure()
  local db = Dibs.GetDB(); db.profiles = db.profiles or {}; db.profiles["local"] = db.profiles["local"] or {}; db.profiles.guild = db.profiles.guild or {}; db.profiles.active = db.profiles.active or {}
  local localRoot = db.profiles["local"]
  -- Move pre-0.4 flat local profiles into the current character bucket once.
  if next(localRoot) then
    for name, value in pairs(localRoot) do
      if type(value) == "table" and value.profileId then
        local migrated = localRoot[charKey()] or {}; migrated[name] = value; localRoot[charKey()] = migrated; localRoot[name] = nil
      end
    end
  end
  localRoot[charKey()] = localRoot[charKey()] or {}
  return db, db.profiles
end
local function bucket(profiles, scope) return scope == "local" and profiles["local"][charKey()] or profiles.guild end
local function authorized(scope, actor)
  if scope == "local" then return true end
  return Dibs.Permissions and Dibs.Permissions.Can and Dibs.Permissions.Can("settings.modify", actor) == true
end
local function key(scope, name) return scopeName(scope) .. ":" .. tostring(name) end
local function selectedSettings(keys)
  local settings = Dibs.GetDB().settings or {}; local out = {}; for _, k in ipairs(keys) do if settings[k] ~= nil then out[k] = clone(settings[k]) end end; return out
end
local function audit(action, scope, name, reason, outcome, actor)
  local db = Dibs.GetDB(); db.auditLog = db.auditLog or {}; table.insert(db.auditLog, { auditId = Dibs.NewId("audit"), action = action, scope = scope, profile = name, actor = Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId and Dibs.Permissions.CanonicalPlayerId(actor) or Dibs.GetPlayerName(), createdAt = time(), outcome = outcome or "success", reason = reason })
end

function M.List(scope, actor)
  scope = scopeName(scope)
  if not authorized(scope, actor) then return {} end
  local db, profiles = ensure(); local entries = bucket(profiles, scope); local result = {}
  for name, profile in pairs(entries) do table.insert(result, clone(profile)) end
  table.sort(result, function(a, b) return tostring(a.name) < tostring(b.name) end); return result
end
function M.Get(name, scope)
  local _, profiles = ensure(); return clone(bucket(profiles, scopeName(scope))[name])
end
---@param name string Profile name.
---@param scope string|nil Profile scope.
---@param options table|nil Settings projection.
---@param actor string Officer actor identity.
---@return DibsProfile|nil profile
---@return string|nil reasonCode
function M.Create(name, scope, options, actor)
  scope = scopeName(scope); name = tostring(name or ""):match("^%s*(.-)%s*$"); if not validName(name) then return nil, "INVALID_PROFILE_NAME" end
  if not authorized(scope, actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local db, profiles = ensure(); local entries = bucket(profiles, scope); if entries[name] then return nil, "PROFILE_EXISTS" end
  options = options or {}; if not safeData(options.presentation) or not safeData(options.authoritativePolicy) then return nil, "UNSAFE_PROFILE_DATA" end
  local profile = { profileId = Dibs.NewId("profile"), name = name, scope = scope, ownerScope = scope == "guild" and Dibs.currentGuildKey or charKey(), presentation = clone(options.presentation or selectedSettings(PRESENTATION_KEYS)), authoritativePolicy = scope == "guild" and clone(options.authoritativePolicy or selectedSettings(POLICY_KEYS)) or nil, schemaVersion = 1, createdAt = time(), updatedAt = time(), active = false }
  entries[name] = profile; audit("profile_create", scope, name, nil, "success", actor); return clone(profile)
end
function M.Copy(source, target, scope, actor)
  local profile = M.Get(source, scope); if not profile then return nil, "PROFILE_NOT_FOUND" end
  return M.Create(target, scope, { presentation = profile.presentation, authoritativePolicy = profile.authoritativePolicy }, actor)
end
function M.Rename(oldName, newName, scope, actor)
  scope = scopeName(scope); newName = tostring(newName or ""):match("^%s*(.-)%s*$"); if not validName(newName) then return nil, "INVALID_PROFILE_NAME" end
  if not authorized(scope, actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local db, profiles = ensure(); local entries = bucket(profiles, scope); local profile = entries[oldName]; if not profile then return nil, "PROFILE_NOT_FOUND" end; if entries[newName] then return nil, "PROFILE_EXISTS" end
  entries[oldName] = nil; profile.name = newName; profile.updatedAt = time(); entries[newName] = profile; if profiles.active[key(scope, oldName)] then profiles.active[key(scope, oldName)] = nil; profiles.active[key(scope, newName)] = true end
  audit("profile_rename", scope, newName, nil, "success", actor); return clone(profile)
end
---@param name string Profile name.
---@param scope string|nil Profile scope.
---@return table|nil preview Settings diff/validation preview.
---@return string|nil reasonCode
function M.PreviewActivation(name, scope)
  scope = scopeName(scope); local db, profiles = ensure(); local profile = bucket(profiles, scope)[name]; if not profile then return nil, "PROFILE_NOT_FOUND" end
  local changes = {}; for k, v in pairs(profile.authoritativePolicy or {}) do if tostring((db.settings or {})[k]) ~= tostring(v) then changes[#changes + 1] = k end end
  return { profile = clone(profile), policyChanges = changes, requiresConfirmation = scope == "guild" and #changes > 0 }
end
---@param name string Profile name.
---@param scope string|nil Profile scope.
---@param actor string Officer actor identity.
---@param confirmation boolean Explicit confirmation.
---@return DibsProfile|nil profile Activated profile.
---@return string|nil reasonCode
-- Side effects: Updates active configuration projection; ledger history is unchanged.
function M.Activate(name, scope, actor, confirmation)
  scope = scopeName(scope); if not authorized(scope, actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local db, profiles = ensure(); local entries = bucket(profiles, scope); local profile = entries[name]; if not profile then return nil, "PROFILE_NOT_FOUND" end
  local activationPreview = M.PreviewActivation(name, scope)
  if activationPreview and activationPreview.requiresConfirmation and confirmation ~= true then return nil, "POLICY_CONFIRM_REQUIRED", activationPreview end
  if profile.authoritativePolicy and scope == "guild" then
    db.settings = db.settings or {}; for k, v in pairs(profile.authoritativePolicy) do if k ~= "permissions" then db.settings[k] = clone(v) end end
  end
  db.settings = db.settings or {}
  for k, v in pairs(profile.presentation or {}) do db.settings[k] = clone(v) end
  profiles.active[key(scope, name)] = true; profile.active = true; profile.updatedAt = time(); audit("profile_activate", scope, name, nil, "success", actor); return clone(profile)
end
function M.Reset(name, scope, actor)
  scope = scopeName(scope); if not authorized(scope, actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local db, profiles = ensure(); local entries = bucket(profiles, scope); local profile = entries[name]; if not profile then return nil, "PROFILE_NOT_FOUND" end
  if scope == "guild" and profile.authoritativePolicy then
    if Dibs.Backup and Dibs.Backup.Create then Dibs.Backup.Create("guild", "before-profile-reset", actor) end
    profile.authoritativePolicy = selectedSettings(POLICY_KEYS)
  end
  profile.presentation = selectedSettings(PRESENTATION_KEYS); profile.updatedAt = time(); audit("profile_reset", scope, name, nil, "success", actor); return clone(profile)
end
function M.Delete(name, scope, actor)
  scope = scopeName(scope); if not authorized(scope, actor) then return nil, "GUILD_ADMIN_REQUIRED" end
  local db, profiles = ensure(); local entries = bucket(profiles, scope); if not entries[name] then return nil, "PROFILE_NOT_FOUND" end
  if scope == "guild" and Dibs.Backup and Dibs.Backup.Create then Dibs.Backup.Create("guild", "before-profile-delete", actor) end
  entries[name] = nil; profiles.active[key(scope, name)] = nil; audit("profile_delete", scope, name, nil, "success", actor); return true
end
function M.GetActive(scope)
  local _, profiles = ensure(); scope = scopeName(scope); for name, p in pairs(bucket(profiles, scope)) do if p.active or profiles.active[key(scope, name)] then return clone(p) end end; return nil
end
function M.SetActive(name, scope, actor, confirmation) return M.Activate(name, scope, actor, confirmation) end

return M
