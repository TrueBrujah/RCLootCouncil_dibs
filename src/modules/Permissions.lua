local Dibs = _G.Dibs
Dibs.Permissions = Dibs.Permissions or {}

local function text(key, fallback) return (Dibs.L and Dibs.L[key]) or fallback end

local function isGuildAvailable()
  return IsInGuild and IsInGuild()
end

local function normalizeName(name)
  local value = tostring(name or ""):match("^%s*(.-)%s*$")
  if value == "" then return nil end
  if not value:find("-", 1, true) and type(GetRealmName) == "function" then
    local realm = tostring(GetRealmName() or ""):gsub("[%s%-]", "")
    if realm ~= "" then value = value .. "-" .. realm end
  end
  return string.lower(value)
end

function Dibs.Permissions.CanonicalPlayerId(actor)
  if type(actor) == "table" then
    if actor.guid and actor.guid ~= "" then return tostring(actor.guid) end
    actor = actor.name or actor.playerName
  end
  if actor == nil and type(UnitGUID) == "function" then
    local guid = UnitGUID("player")
    if guid then return tostring(guid) end
  end
  return normalizeName(actor or (Dibs.GetPlayerName and Dibs.GetPlayerName()))
end

local function ensurePermissionState()
  local db = Dibs.GetDB()
  db.permissions = db.permissions or { adminEvents = {}, activeStandaloneAdmins = {} }
  db.permissions.adminEvents = db.permissions.adminEvents or {}
  db.permissions.activeStandaloneAdmins = db.permissions.activeStandaloneAdmins or {}
  return db.permissions
end

local ADMIN_ACTIONS = {
  ["settings.modify"] = true,
  ["installation.mode.set"] = true,
  ["season.create"] = true,
  ["season.set"] = true,
  ["season.rename"] = true,
  ["season.archive"] = true,
  ["rank.set"] = true,
  ["ledger.grant"] = true,
  ["ledger.use"] = true,
  ["ledger.refund"] = true,
  ["ledger.adjust"] = true,
  ["admin.list"] = true,
  ["admin.appoint"] = true,
  ["admin.revoke"] = true,
  ["predib.mode.set"] = true,
}

local function sameIdentity(first, second)
  return first ~= nil and second ~= nil and string.lower(tostring(first)) == string.lower(tostring(second))
end

local function isCurrentActor(actor, actorId)
  local localId = Dibs.Permissions.CanonicalPlayerId(nil)
  if sameIdentity(actorId, localId) then return true end
  local suppliedName = actor
  if type(actor) == "table" then suppliedName = actor.name or actor.playerName end
  local currentName = Dibs.GetPlayerName and Dibs.GetPlayerName() or nil
  return normalizeName(suppliedName) ~= nil and sameIdentity(normalizeName(suppliedName), normalizeName(currentName))
end

local function getConfiguredOfficerLimit()
  local db = Dibs.GetDB and Dibs.GetDB() or {}
  local settings = db.settings or {}
  local limit = tonumber(settings.officerMaxRankIndex)
  if limit == nil then limit = 1 end
  return math.min(9, math.max(0, math.floor(limit)))
end

local function rankIsOfficer(rankIndex)
  local db = Dibs.GetDB and Dibs.GetDB() or {}
  local settings = db.settings or {}
  local configured = settings.officerRankIndices
  if type(configured) == "table" and next(configured) ~= nil then
    return configured[tostring(rankIndex)] == true or configured[rankIndex] == true
  end
  return tonumber(rankIndex) ~= nil and tonumber(rankIndex) > 0 and tonumber(rankIndex) <= getConfiguredOfficerLimit()
end

local function rosterRole(actor)
  local actorId = Dibs.Permissions.CanonicalPlayerId(actor)
  if not actorId or type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
    return nil, nil
  end
  local okCount, memberCount = pcall(GetNumGuildMembers, true)
  if not okCount then return nil, nil end
  for index = 1, tonumber(memberCount) or 0 do
    local ok, name, _, rankIndex = pcall(GetGuildRosterInfo, index)
    if ok and name and sameIdentity(normalizeName(name), actorId) then
      rankIndex = tonumber(rankIndex)
      if rankIndex == 0 then return "gm", rankIndex end
      if rankIsOfficer(rankIndex) then return "officer", rankIndex end
      return "player", rankIndex
    end
  end
  return nil, nil
end

function Dibs.Permissions.GetGuildRole(actor)
  if not isGuildAvailable() then return "player" end
  local role = rosterRole(actor)
  if role then return role end
  local actorId = Dibs.Permissions.CanonicalPlayerId(actor)
  local localId = Dibs.Permissions.CanonicalPlayerId(nil)
  if sameIdentity(actorId, localId) then
    if Dibs.Permissions.IsGM() then return "gm" end
    if Dibs.Permissions.IsOfficer() then return "officer" end
  end
  return "player"
end

function Dibs.Permissions.IsOfficer()
  if not isGuildAvailable() then
    return false
  end

  if IsGuildLeader and IsGuildLeader() then
    return true
  end

  if type(GetNumGuildMembers) == "function" and type(GetGuildRosterInfo) == "function" then
    local playerName = normalizeName(Dibs.GetPlayerName and Dibs.GetPlayerName() or "")
    local okCount, memberCount = pcall(GetNumGuildMembers, true)
    memberCount = okCount and tonumber(memberCount) or 0
    for index = 1, memberCount do
      local name, _, rankIndex = GetGuildRosterInfo(index)
      if sameIdentity(normalizeName(name), playerName) then
        return rankIsOfficer(rankIndex)
      end
    end
  end
  return false
end

function Dibs.Permissions.CanSendReminder()
  if type(IsInRaid) ~= "function" or IsInRaid() ~= true then return false, "REMINDER_REQUIRES_RAID" end
  if Dibs.Permissions.IsGM() or Dibs.Permissions.IsOfficer() then return true end
  if type(UnitIsGroupLeader) == "function" and UnitIsGroupLeader("player") then return true end
  if Dibs.RCLootCouncil and type(Dibs.RCLootCouncil.GetAvailability) == "function"
    and type(Dibs.RCLootCouncil.EvaluateAuthority) == "function" then
    local ok, availability = pcall(Dibs.RCLootCouncil.GetAvailability)
    if ok and availability == "operational" then
      local evaluated, decision = pcall(Dibs.RCLootCouncil.EvaluateAuthority, "award.finalize", nil)
      if evaluated and type(decision) == "table" and decision.allowed == true then return true end
    end
  end
  return false, "REMINDER_NOT_AUTHORIZED"
end

function Dibs.Permissions.IsGM()
  if not isGuildAvailable() then
    return false
  end

  return IsGuildLeader and IsGuildLeader() or false
end

function Dibs.Permissions.IsStandaloneAdmin(actor)
  local id = Dibs.Permissions.CanonicalPlayerId(actor)
  return id ~= nil and ensurePermissionState().activeStandaloneAdmins[id] ~= nil
end

function Dibs.Permissions.GetInstallationMode()
  local db = Dibs.GetDB and Dibs.GetDB() or {}
  local mode = db.settings and string.upper(tostring(db.settings.installationMode or "AUTO")) or "AUTO"
  if mode == "RCLOOTCOUNCIL" then mode = "RCLootCouncil" end
  if mode ~= "AUTO" and mode ~= "STANDALONE" and mode ~= "RCLootCouncil" then
    mode = "AUTO"
  end
  return mode
end

function Dibs.Permissions.SetInstallationMode(mode, actor)
  local normalized = string.upper(tostring(mode or ""))
  if normalized == "RCLOOTCOUNCIL" then normalized = "RCLootCouncil" end
  if normalized ~= "AUTO" and normalized ~= "STANDALONE" and normalized ~= "RCLootCouncil" then
    return nil, "INVALID_INSTALLATION_MODE"
  end
  local decision = Dibs.Permissions.Evaluate("installation.mode.set", actor)
  if not decision.allowed then return nil, decision.reasonCode end
  local db = Dibs.GetDB()
  db.settings.installationMode = normalized
  return normalized
end

function Dibs.Permissions.EvaluateStandalone(actionId, actor)
  local actorId = Dibs.Permissions.CanonicalPlayerId(actor)
  if not actorId then return { allowed = false, authority = "none", availability = "absent", actionId = actionId, reasonCode = "INVALID_ACTOR", diagnostic = text("AUTHORITY_INVALID_ACTOR", "Unable to identify the actor.") } end
  if isCurrentActor(actor, actorId) and Dibs.Permissions.IsGM() then
    return { allowed = true, authority = "guild", availability = "absent", actionId = actionId, actorId = actorId, role = "gm", reasonCode = "GUILD_MASTER", diagnostic = text("AUTHORITY_STANDALONE_GUILD_MASTER", "Authorized as guild master.") }
  end
  if isCurrentActor(actor, actorId) and Dibs.Permissions.IsOfficer() then
    return { allowed = true, authority = "guild", availability = "absent", actionId = actionId, actorId = actorId, role = "officer", reasonCode = "GUILD_OFFICER", diagnostic = text("AUTHORITY_GUILD_OFFICER", "Authorized as guild officer.") }
  end
  return { allowed = false, authority = "guild", availability = "absent", actionId = actionId, actorId = actorId, reasonCode = "GUILD_ADMIN_REQUIRED", diagnostic = text("AUTHORITY_STANDALONE_NOT_AUTHORIZED", "Only the guild master or an officer may perform this Dibs action.") }
end

function Dibs.Permissions.Evaluate(actionId, actor)
  if type(actionId) ~= "string" or actionId == "" then
    return { allowed = false, authority = "none", actionId = actionId, reasonCode = "INVALID_ACTION", diagnostic = "Unknown protected action." }
  end
  local actorId = Dibs.Permissions.CanonicalPlayerId(actor)
  local isLocal = isCurrentActor(actor, actorId)

  if ADMIN_ACTIONS[actionId] then
    if isLocal and Dibs.Permissions.IsGM() then
      return { allowed = true, authority = "guild", availability = "local", actionId = actionId, actorId = actorId, role = "gm", reasonCode = "GUILD_MASTER", diagnostic = text("AUTHORITY_STANDALONE_GUILD_MASTER", "Authorized as guild master.") }
    end
    if isLocal and Dibs.Permissions.IsOfficer() then
      return { allowed = true, authority = "guild", availability = "local", actionId = actionId, actorId = actorId, role = "officer", reasonCode = "GUILD_OFFICER", diagnostic = text("AUTHORITY_GUILD_OFFICER", "Authorized as guild officer.") }
    end
    return { allowed = false, authority = "guild", availability = "local", actionId = actionId, actorId = actorId, reasonCode = "GUILD_ADMIN_REQUIRED", diagnostic = text("AUTHORITY_STANDALONE_NOT_AUTHORIZED", "Only the guild master or an officer may perform this Dibs action.") }
  end

  if actionId == "award.finalize" and Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetAvailability then
    local ok, availability = pcall(Dibs.RCLootCouncil.GetAvailability)
    if not ok then availability = "degraded" end
    local mode = Dibs.Permissions.GetInstallationMode()
    if mode == "RCLootCouncil" or (mode == "AUTO" and availability == "operational") then
      if availability == "operational" then
        local success, decision = pcall(Dibs.RCLootCouncil.EvaluateAuthority, actionId, actor)
        if success and type(decision) == "table" and type(decision.allowed) == "boolean" then return decision end
      end
      return { allowed = false, authority = "rclootcouncil", availability = availability, actionId = actionId, actorId = actorId, reasonCode = "RC_AUTHORITY_UNVERIFIABLE", diagnostic = text("AUTHORITY_RC_UNVERIFIABLE", "RCLootCouncil authority could not be verified.") }
    end
  end
  return Dibs.Permissions.EvaluateStandalone(actionId, actor)
end

function Dibs.Permissions.Can(actionId, actor)
  return Dibs.Permissions.Evaluate(actionId, actor).allowed == true
end

function Dibs.Permissions.CanManageDibs()
  return Dibs.Permissions.Can("ledger.adjust")
end

function Dibs.Permissions.ChangeStandaloneAdmin(target, appoint, actor, reason, existingDecision)
  local decision = existingDecision or Dibs.Permissions.Evaluate(appoint and "admin.appoint" or "admin.revoke", actor)
  if not decision.allowed then return nil, decision end
  if not Dibs.Permissions.IsGM() and not Dibs.Permissions.IsOfficer() then
    return nil, { allowed = false, authority = decision.authority, availability = decision.availability, reasonCode = "GUILD_ADMIN_REQUIRED", diagnostic = text("AUTHORITY_STANDALONE_NOT_AUTHORIZED", "Only the guild master or an officer may manage Dibs administrators.") }
  end
  if not isCurrentActor(actor, decision.actorId) then
    return nil, { allowed = false, authority = decision.authority, availability = decision.availability, reasonCode = "GUILD_ADMIN_REQUIRED", diagnostic = text("AUTHORITY_STANDALONE_NOT_AUTHORIZED", "Only the local guild master or officer may manage Dibs administrators.") }
  end
  local targetId = Dibs.Permissions.CanonicalPlayerId(target)
  if not targetId then return nil, { allowed = false, reasonCode = "INVALID_ACTOR", diagnostic = "Unable to identify the administrator." } end
  local state = ensurePermissionState()
  local event = { eventId = Dibs.NewId("admin"), adminId = targetId, adminName = type(target) == "table" and target.name or tostring(target), action = appoint and "APPOINTED" or "REVOKED", actorId = decision.actorId, createdAt = time(), reason = reason }
  table.insert(state.adminEvents, event)
  if appoint then state.activeStandaloneAdmins[targetId] = { playerName = event.adminName, appointedBy = event.actorId, appointedAt = event.createdAt } else state.activeStandaloneAdmins[targetId] = nil end
  return event, decision
end

function Dibs.Permissions.GetRole()
  if Dibs.Permissions.IsGM() then
    return "gm"
  end

  if Dibs.Permissions.IsOfficer() then
    return "officer"
  end

  return "player"
end
