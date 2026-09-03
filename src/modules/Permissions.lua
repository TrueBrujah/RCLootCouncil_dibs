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

function Dibs.Permissions.IsOfficer()
  if not isGuildAvailable() then
    return false
  end

  if IsGuildLeader and IsGuildLeader() then
    return true
  end

  return false
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

function Dibs.Permissions.EvaluateStandalone(actionId, actor)
  local actorId = Dibs.Permissions.CanonicalPlayerId(actor)
  if not actorId then return { allowed = false, authority = "none", availability = "absent", actionId = actionId, reasonCode = "INVALID_ACTOR", diagnostic = text("AUTHORITY_INVALID_ACTOR", "Unable to identify the actor.") } end
  if Dibs.Permissions.IsGM() and actorId == Dibs.Permissions.CanonicalPlayerId(nil) then
    return { allowed = true, authority = "standalone", availability = "absent", actionId = actionId, actorId = actorId, reasonCode = "STANDALONE_GUILD_MASTER", diagnostic = text("AUTHORITY_STANDALONE_GUILD_MASTER", "Authorized as guild master.") }
  end
  if Dibs.Permissions.IsStandaloneAdmin(actor) then
    return { allowed = true, authority = "standalone", availability = "absent", actionId = actionId, actorId = actorId, reasonCode = "STANDALONE_APPOINTED_ADMIN", diagnostic = text("AUTHORITY_STANDALONE_APPOINTED_ADMIN", "Authorized as a Dibs administrator.") }
  end
  return { allowed = false, authority = "standalone", availability = "absent", actionId = actionId, actorId = actorId, reasonCode = "STANDALONE_NOT_AUTHORIZED", diagnostic = text("AUTHORITY_STANDALONE_NOT_AUTHORIZED", "You are not authorized to perform this Dibs action.") }
end

function Dibs.Permissions.Evaluate(actionId, actor)
  if type(actionId) ~= "string" or actionId == "" then
    return { allowed = false, authority = "none", actionId = actionId, reasonCode = "INVALID_ACTION", diagnostic = "Unknown protected action." }
  end
  if Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetAvailability then
    local ok, availability = pcall(Dibs.RCLootCouncil.GetAvailability)
    if not ok then availability = "degraded" end
    if availability ~= "absent" then
      local success, decision = pcall(Dibs.RCLootCouncil.EvaluateAuthority, actionId, actor)
      if success and type(decision) == "table" and type(decision.allowed) == "boolean" then return decision end
      return { allowed = false, authority = "rclootcouncil", availability = "degraded", actionId = actionId, actorId = Dibs.Permissions.CanonicalPlayerId(actor), reasonCode = "RC_AUTHORITY_UNVERIFIABLE", diagnostic = text("AUTHORITY_RC_UNVERIFIABLE", "RCLootCouncil authority could not be verified.") }
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
  if not Dibs.Permissions.IsGM() or decision.actorId ~= Dibs.Permissions.CanonicalPlayerId(nil) then
    return nil, { allowed = false, authority = decision.authority, availability = decision.availability, reasonCode = "GUILD_MASTER_REQUIRED", diagnostic = text("STANDALONE_ADMIN_GM_ONLY", "Only the guild master can manage Dibs administrators.") }
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
