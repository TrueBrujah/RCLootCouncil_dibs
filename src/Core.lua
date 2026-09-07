local addonName, RCLootCouncil_dibs = ...

RCLootCouncil_dibs = RCLootCouncil_dibs or {}
_G.RCLootCouncil_dibs = RCLootCouncil_dibs

Dibs = _G.Dibs or RCLootCouncil_dibs
_G.Dibs = Dibs

-- Keep the shared namespace explicit for editors and for Core's early guards.
-- Permissions.lua fills this table with the authoritative implementation once
-- the ordered module list reaches it; initializing it here is intentionally
-- side-effect free and preserves an existing table during reloads.
Dibs.Permissions = Dibs.Permissions or {}
Dibs.ProtectedActions = Dibs.ProtectedActions or {}
Dibs.PreDibs = Dibs.PreDibs or {}

Dibs.ADDON_NAME = addonName or "RCLootCouncil_dibs"
Dibs.MODULE_NAME = "RCLootCouncil_dibs"
Dibs.VERSION = "0.2.2-dev"
Dibs.PROTOCOL_VERSION = 1
Dibs.DEFAULT_DIBS_PER_RANK = 1
Dibs.SAVED_VARIABLE_NAME = "RCLootCouncil_dibsDB"

if Dibs ~= RCLootCouncil_dibs then
  RCLootCouncil_dibs = Dibs
  _G.RCLootCouncil_dibs = Dibs
end

local function deepcopy(value)
  if type(value) ~= "table" then
    return value
  end

  local copy = {}
  for key, item in pairs(value) do
    copy[key] = deepcopy(item)
  end
  return copy
end

local function mergeDefaults(target, defaults)
  if type(target) ~= "table" then
    target = {}
  end

  for key, value in pairs(defaults) do
    if type(value) == "table" and type(target[key]) == "table" then
      mergeDefaults(target[key], value)
    elseif target[key] == nil then
      target[key] = deepcopy(value)
    end
  end

  return target
end

local function normalizeGuildKey(realm, name)
  local value = string.lower(tostring(realm or "unknown-realm") .. ":" .. tostring(name or "unknown"))
  return (value:gsub("%s+", ""))
end

-- Isolates all Dibs data by guild so alts in different guilds never share seasons/ledger/requests.
function Dibs.GetGuildKey()
  local realm = type(GetRealmName) == "function" and GetRealmName() or "unknown-realm"
  if type(IsInGuild) == "function" and IsInGuild() and type(GetGuildInfo) == "function" then
    local guildName = GetGuildInfo("player")
    if guildName and guildName ~= "" then
      return normalizeGuildKey(realm, guildName)
    end
  end
  local playerName = Dibs.GetPlayerName and Dibs.GetPlayerName() or "unknown"
  return normalizeGuildKey(realm, "no-guild:" .. tostring(playerName))
end

local defaultDB = {
  version = 5,
  currentSeasonId = nil,
  seasons = {},
  rankRules = {},
  ledger = {
    transactions = {},
    playerStates = {},
    awardTransactions = {},
  },
  permissions = {
    adminEvents = {},
    activeStandaloneAdmins = {},
  },
  preDibs = {
    requests = {},
    modePolicies = {},
    acquisitions = {},
  },
  sync = {
    seenTransactions = {},
    peerStates = {},
  },
  settings = {
    language = "AUTO",
    debugLevels = { all = 1 },
    defaultAllocation = 1,
    officerMaxRankIndex = 1,
    officerRankIndices = {},
    installationMode = "AUTO",
    allowPublicPreDibs = true,
    preDibAnnouncementChannel = "GUILD",
    preDibOfficerAnnouncementChannel = "OFFICER",
    preDibAnnouncementTemplate = "[Dibs] %player requested %item (%difficulty) - %date %time",
    raidReminderTemplate = "[Dibs] Review your eligible Pre-Dibs before the encounter. [%date %time]",
    developerModeEnabled = false,
    defaultSyncInterval = 5,
    raidEntryDibPromptsEnabled = false,
    raidReminderMessage = "[Dibs] Review your eligible Pre-Dibs before the encounter.",
  },
}

local FLAT_ROOT_MARKERS = { "seasons", "preDibs", "ledger", "permissions", "settings" }

local function isFlatLegacyRoot(persisted)
  if type(persisted.guilds) == "table" then return false end
  for _, key in ipairs(FLAT_ROOT_MARKERS) do
    if type(persisted[key]) == "table" then return true end
  end
  return false
end

local function ensureDB()
  local dbName = Dibs.SAVED_VARIABLE_NAME or "RCLootCouncil_dibsDB"
  local persisted = _G[dbName]

  if type(persisted) ~= "table" and type(_G.DibsDB) == "table" then
    persisted = _G.DibsDB
  end

  if type(persisted) ~= "table" then
    persisted = {}
  end

  if isFlatLegacyRoot(persisted) then
    local guildKey = Dibs.GetGuildKey()
    local legacy = persisted
    persisted = { schemaVersion = 6, guilds = { [guildKey] = legacy } }
  end

  persisted.schemaVersion = persisted.schemaVersion or 6
  persisted.guilds = persisted.guilds or {}

  local guildKey = Dibs.GetGuildKey()
  Dibs.currentGuildKey = guildKey
  persisted.guilds[guildKey] = persisted.guilds[guildKey] or {}

  Dibs.db = persisted.guilds[guildKey]
  mergeDefaults(Dibs.db, defaultDB)
  if (tonumber(Dibs.db.version) or 0) < 2 then
    Dibs.db.permissions = Dibs.db.permissions or { adminEvents = {}, activeStandaloneAdmins = {} }
    Dibs.db.permissions.adminEvents = Dibs.db.permissions.adminEvents or {}
    Dibs.db.permissions.activeStandaloneAdmins = Dibs.db.permissions.activeStandaloneAdmins or {}
    Dibs.db.ledger = Dibs.db.ledger or { transactions = {}, playerStates = {}, awardTransactions = {} }
    Dibs.db.ledger.awardTransactions = Dibs.db.ledger.awardTransactions or {}
    Dibs.db.version = 2
  end
  if (tonumber(Dibs.db.version) or 0) < 3 then
    Dibs.db.preDibs = Dibs.db.preDibs or { requests = {}, modePolicies = {} }
    Dibs.db.preDibs.requests = Dibs.db.preDibs.requests or {}
    Dibs.db.preDibs.modePolicies = Dibs.db.preDibs.modePolicies or {}
    for _, request in ipairs(Dibs.db.preDibs.requests) do
      request.revision = math.max(1, tonumber(request.revision) or 1)
      request.modeAtCreation = request.modeAtCreation or "WILD_OPEN"
      request.delivery = request.delivery or { state = "PENDING" }
    end
    Dibs.db.version = 3
  end
  if (tonumber(Dibs.db.version) or 0) < 4 then
    Dibs.db.preDibs = Dibs.db.preDibs or { requests = {}, modePolicies = {}, acquisitions = {} }
    Dibs.db.preDibs.requests = Dibs.db.preDibs.requests or {}
    Dibs.db.preDibs.acquisitions = Dibs.db.preDibs.acquisitions or {}
    for _, request in ipairs(Dibs.db.preDibs.requests) do
      request.difficulty = request.difficulty or "UNKNOWN"
    end
    Dibs.db.version = 4
  end
  if (tonumber(Dibs.db.version) or 0) < 5 then
    Dibs.db.preDibs = Dibs.db.preDibs or { requests = {}, modePolicies = {}, acquisitions = {} }
    Dibs.db.preDibs.requests = Dibs.db.preDibs.requests or {}
    for _, request in ipairs(Dibs.db.preDibs.requests) do
      if request.difficulty == nil or request.difficulty == "" or request.difficulty == "UNKNOWN" then
        request.difficulty = "Normal"
      end
    end
    Dibs.db.version = 5
  end
  _G[dbName] = persisted
  _G.DibsDB = Dibs.db
end

function Dibs.GetDB()
  ensureDB()
  return Dibs.db
end

Dibs.CoreAPI = Dibs.CoreAPI or {}

local function coreActorIsLocal(actor)
  if actor == nil then return true end
  if not Dibs.Permissions or type(Dibs.Permissions.CanonicalPlayerId) ~= "function" then return false end
  local actorId = Dibs.Permissions.CanonicalPlayerId(actor)
  local localId = Dibs.Permissions.CanonicalPlayerId(nil)
  local localName = Dibs.GetPlayerName and Dibs.GetPlayerName() or nil
  local localNameId = Dibs.Permissions.CanonicalPlayerId(localName)
  return actorId ~= nil and (
    (localId ~= nil and string.lower(tostring(actorId)) == string.lower(tostring(localId)))
      or (localNameId ~= nil and string.lower(tostring(actorId)) == string.lower(tostring(localNameId)))
  )
end

local function coreActorCanViewAll(actor)
  if not Dibs.Permissions or type(Dibs.Permissions.GetGuildRole) ~= "function" then return false end
  if not coreActorIsLocal(actor) then return false end
  local role = Dibs.Permissions.GetGuildRole(actor)
  return role == "gm" or role == "officer"
end

local function coreActorMatchesPlayer(actor, player)
  if not Dibs.Permissions or type(Dibs.Permissions.CanonicalPlayerId) ~= "function" then return false end
  if actor == nil then actor = Dibs.GetPlayerName and Dibs.GetPlayerName() or nil end
  local actorId = Dibs.Permissions.CanonicalPlayerId(actor)
  local playerId = Dibs.Permissions.CanonicalPlayerId(player)
  return actorId ~= nil and playerId ~= nil and string.lower(tostring(actorId)) == string.lower(tostring(playerId))
end

function Dibs.CoreAPI.createSeason(request)
  local payload = request or {}
  local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute
    and Dibs.ProtectedActions.Execute("season.create", payload.actor or payload.actorIdentity, payload)
  return result and result.ok and result.value or nil
end

function Dibs.CoreAPI.setActiveSeason(request)
  local payload = request or {}
  local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute
    and Dibs.ProtectedActions.Execute("season.set", payload.actor or payload.actorIdentity, payload)
  return result and result.ok and { activeSeasonId = result.value } or nil
end

function Dibs.CoreAPI.listSeasons(request)
  if not coreActorCanViewAll(request and (request.actor or request.actorIdentity) or nil) then
    return { seasons = {}, reasonCode = "OFFICER_SCOPE_REQUIRED" }
  end
  local seasons = Dibs.Seasons and Dibs.Seasons.ListSeasons and Dibs.Seasons.ListSeasons() or {}
  return { seasons = seasons }
end

function Dibs.CoreAPI.setRankAllocation(request)
  local payload = request or {}
  local result = Dibs.ProtectedActions and Dibs.ProtectedActions.Execute
    and Dibs.ProtectedActions.Execute("rank.set", payload.actor or payload.actorIdentity, payload)
  local rule = result and result.ok and result.value
  local reasonCode = result and result.reasonCode
  return rule and {
    seasonId = payload.seasonId,
    rankIndex = rule.rankIndex,
    allocation = rule.allocation,
    rankName = rule.rankName,
  } or { reasonCode = reasonCode }
end

function Dibs.CoreAPI.getRankAllocation(request)
  local payload = request or {}
  if not coreActorCanViewAll(payload.actor or payload.actorIdentity) then
    return nil, "OFFICER_SCOPE_REQUIRED"
  end
  local rule = Dibs.RankRules and Dibs.RankRules.GetRankAllocation and Dibs.RankRules.GetRankAllocation(payload.seasonId, payload.rankIndex) or nil
  return rule and {
    allocation = rule.allocation,
    rankName = rule.rankName,
  } or nil
end

function Dibs.CoreAPI.appendTransaction(request)
  local payload = request or {}
  if not Dibs.Ledger or not Dibs.Ledger.AppendTransaction then
    return { accepted = false, reasonCode = "LEDGER_UNAVAILABLE" }
  end
  local actionByType = {
    DIB_GRANTED = "ledger.grant",
    DIB_USED = "ledger.use",
    DIB_REFUNDED = "ledger.refund",
    DIB_REVOKED = "ledger.adjust",
    DIB_ADMIN_ADJUSTMENT = "ledger.adjust",
    SEASON_ALLOCATION = "ledger.adjust",
  }
  local actionId = actionByType[payload.actionType or payload.type] or "ledger.adjust"
  local actor = payload.actor or payload.actorIdentity
  local decision = Dibs.Permissions and Dibs.Permissions.Evaluate and Dibs.Permissions.Evaluate(actionId, actor)
  if not decision or decision.allowed ~= true then
    return { accepted = false, idempotentReplay = false, reasonCode = decision and decision.reasonCode or "AUTHORITY_UNAVAILABLE" }
  end
  local transaction = {}
  for key, value in pairs(payload) do
    if key ~= "actor" and key ~= "actorIdentity" then transaction[key] = value end
  end
  transaction.actorId = transaction.actorId or decision.actorId
  return Dibs.Ledger.AppendTransaction(transaction)
end

function Dibs.CoreAPI.getTransactions(request)
  local payload = request or {}
  local actor = payload.actor or payload.actorIdentity
  local requestedPlayer = payload.playerGuid or payload.playerName
  if not coreActorCanViewAll(actor) then
    requestedPlayer = requestedPlayer or (Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
    if not coreActorMatchesPlayer(actor, requestedPlayer) then
      return { transactions = {}, reasonCode = "PLAYER_SCOPE_REQUIRED" }
    end
  end
  local transactions = Dibs.Ledger and Dibs.Ledger.GetTransactions and Dibs.Ledger.GetTransactions(payload.seasonId, requestedPlayer) or {}
  return { transactions = transactions }
end

function Dibs.CoreAPI.getPlayerSeasonState(request)
  local payload = request or {}
  local actor = payload.actor or payload.actorIdentity
  local requestedPlayer = payload.playerGuid or payload.playerName
  if not coreActorCanViewAll(actor) then
    requestedPlayer = requestedPlayer or (Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
    if not coreActorMatchesPlayer(actor, requestedPlayer) then
      return nil, "PLAYER_SCOPE_REQUIRED"
    end
  end
  return Dibs.Ledger and Dibs.Ledger.GetPlayerSeasonState and Dibs.Ledger.GetPlayerSeasonState(payload.seasonId, requestedPlayer)
end

function Dibs.CoreAPI.canExecuteAuthoritativeAction(request)
  local payload = request or {}
  local decision = Dibs.Permissions and Dibs.Permissions.Evaluate and Dibs.Permissions.Evaluate(payload.actionId, payload.actor)
  if not decision then
    return { allowed = false, authoritySource = "none", reasonCode = "AUTHORITY_UNAVAILABLE" }
  end
  return {
    allowed = decision.allowed == true,
    authoritySource = decision.authority,
    reasonCode = decision.reasonCode,
  }
end

function Dibs.NewId(prefix)
  local timestamp = tostring(time() or 0)
  local randomPart = tostring(math.random(100000, 999999))
  return (prefix or "dibs") .. "-" .. timestamp .. "-" .. randomPart
end

function Dibs.GetCurrentSeasonId()
  ensureDB()
  if Dibs.db.currentSeasonId and Dibs.db.currentSeasonId ~= "" then
    return Dibs.db.currentSeasonId
  end

  if Dibs.Seasons and Dibs.Seasons.GetOrCreateDefault then
    local season = Dibs.Seasons.GetOrCreateDefault()
    if season then
      Dibs.db.currentSeasonId = season.id
    end
  end

  return Dibs.db.currentSeasonId
end

function Dibs.GetPlayerName()
  return UnitName("player") or "UnknownPlayer"
end

function Dibs.GetTimestamp()
  return time()
end

function Dibs.Message(text)
  local value = tostring(text or "")
  local module, level = value:match("^%[([^%]]+)%]%s*"), nil
  if module then
    local suffix = module:match("[Dd]ebug")
    level = suffix and 4 or 1
  else
    module, level = "core", 1
  end
  if Dibs.DebugLogs and Dibs.DebugLogs.Add then Dibs.DebugLogs.Add(module, level, value) end
  if Dibs.DebugEnabled and not Dibs.DebugEnabled(module, level) then return end
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage("|cff8b5cf6Dibs|r " .. value)
  end
end

function Dibs.DebugEnabled(module, level)
  local settings = Dibs.GetDB and Dibs.GetDB().settings or {}
  local levels = settings.debugLevels or { all = 1 }
  local threshold = tonumber(levels[module])
  if threshold == nil then threshold = tonumber(levels.all) or 1 end
  return (tonumber(threshold) or 0) >= (tonumber(level) or 1)
end

function Dibs.SetDebugLevel(module, level, actor)
  if not Dibs.Permissions or type(Dibs.Permissions.Can) ~= "function"
    or not Dibs.Permissions.Can("settings.modify", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  module = string.lower(tostring(module or "all"))
  level = math.max(0, math.min(5, tonumber(level) or 0))
  local settings = Dibs.GetDB().settings
  settings.debugLevels = settings.debugLevels or {}
  settings.debugLevels[module] = level
  return level, nil
end

function Dibs.GetDebugLevels()
  return Dibs.GetDB().settings.debugLevels or { all = 1 }
end

function Dibs.BuildDebugReport()
  local levels = Dibs.GetDebugLevels()
  local clubId, streamId = nil, nil
  if Dibs.PreDibs and Dibs.PreDibs.GetRaidDibsChannel then
    clubId, streamId = Dibs.PreDibs.GetRaidDibsChannel()
  end
  local rc = Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetLocalStatus and Dibs.RCLootCouncil.GetLocalStatus() or nil
  local vote = Dibs.RCLootCouncil and Dibs.RCLootCouncil.GetVotingIntegrationStatus and Dibs.RCLootCouncil.GetVotingIntegrationStatus() or {}
  local lines = {
    "Dibs debug report",
    "Version: " .. tostring(Dibs.VERSION),
    "Framework: " .. Dibs.GetFrameworkStatus(),
    "RCLootCouncil: " .. tostring(rc and (rc.diagnostic or rc.status or "available") or "absent") .. " reason=" .. tostring(rc and rc.reasonCode or "RC_ABSENT"),
    "RCLootCouncil capabilities: " .. tostring(rc and rc.capabilities and (rc.capabilities.masterLooter and "masterLooter " or "") .. (rc.capabilities.awardCallback and "awardCallback " or "") .. (rc.capabilities.awardIdentity and "awardIdentity" or "none") or "none"),
    "Voting frame: module=" .. tostring(vote.moduleFound) .. " AddColumn=" .. tostring(vote.addColumn) .. " scrollCols=" .. tostring(vote.scrollColumns) .. " count=" .. tostring(vote.scrollColumnCount) .. " hasDibs=" .. tostring(vote.scrollHasDibs) .. " renderedDibs=" .. tostring(vote.renderedHasDibs) .. " DibsColumn=" .. tostring(vote.dibsColumnInstalled),
    "Season: " .. tostring(Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or "none"),
    "Raid Dibs: " .. (clubId and ("available clubId=" .. tostring(clubId) .. " streamId=" .. tostring(streamId)) or "unavailable"),
    "Debug levels: all=" .. tostring(levels.all or 1) .. " announce=" .. tostring(levels.announce or "inherit") .. " sync=" .. tostring(levels.sync or "inherit") .. " ui=" .. tostring(levels.ui or "inherit") .. " encounter_journal=" .. tostring(levels.encounter_journal or "inherit"),
  }
  return table.concat(lines, "\n")
end

function Dibs.GetFrameworkStatus()
  local ace3 = Dibs.Ace3
  local libraries = ace3 and ace3.libs or {}
  local function enabled(name)
    return libraries and libraries[name] and "yes" or "no"
  end
  return "Ace3: GUI=" .. enabled("gui") ..
    " | Config=" .. enabled("config") ..
    " | Comm=" .. enabled("comm") ..
    " | Event=" .. enabled("event") ..
    " | Timer=" .. enabled("timer")
end

function Dibs.ApplyDefaultRules()
  ensureDB()
  local season = Dibs.Seasons and Dibs.Seasons.GetOrCreateDefault()
  if not season then
    return
  end

  for rankIndex = 0, 5 do
    local rules = Dibs.RankRules and Dibs.RankRules.GetRulesForSeason(season.id) or {}
    local existing = rules[tostring(rankIndex)]
    if existing == nil then
      Dibs.RankRules.SetAllocation(season.id, rankIndex, "Rank " .. tostring(rankIndex), 1)
    end
  end

  local playerState = Dibs.Ledger and Dibs.Ledger.GetPlayerState(Dibs.GetPlayerName(), season.id)
  if playerState and (tonumber(playerState.allocation) or 0) == 0 then
    Dibs.Ledger.RegisterSeasonAllocation(Dibs.GetPlayerName(), season.id, 1, "Initial season allocation")
  end
end

function Dibs.HandleSlashCommand(msg)
  local command = (msg or ""):match("^%s*(.-)%s*$")
  local action = command:match("^(%S+)") or ""
  local rest = command:match("^%S+%s+(.+)$") or ""
  local args = {}
  for token in string.gmatch(command, "%S+") do
    table.insert(args, token)
  end

  if action == "debug" then
    local module = string.lower(args[2] or "all")
    if module == "logs" then
      if Dibs.DebugLogs and Dibs.DebugLogs.Open then Dibs.DebugLogs.Open() end
      return
    end
    if module == "report" then
      Dibs.Message(Dibs.BuildDebugReport())
      return
    end
    local level = tonumber(args[3])
    if level == nil or level < 0 or level > 5 then
      Dibs.Message("Usage: /dibs debug <module|all> 0-5")
      return
    end
    local applied, reason = Dibs.SetDebugLevel(module, level)
    if applied == nil then
      Dibs.Message("Only the guild master or an officer may change Dibs settings (" .. tostring(reason) .. ").")
    else
      Dibs.Message("Debug level " .. module .. " = " .. tostring(applied))
    end
    return
  end

  if action == "" or action == "help" then
    Dibs.Message("Dibs commands: /dibs help | /dibs status | /dibs balance | /dibs ui | /dibs options | /dibs officer | /dibs grant <player> <amount> | /dibs use <player> <amount> | /dibs pre <itemID> [itemName] | /dibs season create [name] | /dibs season set <id> | /dibs rank set <index> <amount> [name]")
    Dibs.Message("Developer commands (Developer Mode required): /dibs dev on | /dibs dev off | /dibs dev status | /dibs testitem <itemID>")
    Dibs.Message("Debug commands: /dibs ejdebug | /dibs ejsub list|scan|matrix|apply recommended|block <SUB>|allow <SUB>|clear | /dibs announce debug on|off|scan")
    return
  end

  if action == "status" then
    Dibs.Message(Dibs.GetFrameworkStatus())
    return
  end

  if action == "announce" then
    local mode = args[2] or "scan"
    if mode == "debug" then
      local enabled = string.lower(args[3] or "off") == "on"
      local applied, reason = Dibs.PreDibs.SetAnnouncementDebug(enabled)
      if applied == nil then
        Dibs.Message("Only the guild master or an officer may change Dibs settings (" .. tostring(reason) .. ").")
      else
        Dibs.Message("Announcement debug " .. (applied and "ON" or "OFF") .. ".")
      end
    elseif mode == "scan" then
      if Dibs.PreDibs and Dibs.PreDibs.DebugRaidDibs then
        Dibs.PreDibs.DebugRaidDibs()
      else
        Dibs.Message("Announcement debug is unavailable.")
      end
    else
      Dibs.Message("Usage: /dibs announce debug on|off|scan")
    end
    return
  end

  if action == "ejdebug" then
    if Dibs.EncounterJournal and Dibs.EncounterJournal.DumpVisibleLootDebug then
      Dibs.EncounterJournal.DumpVisibleLootDebug()
    else
      Dibs.Message("Encounter Journal debug is unavailable.")
    end
    return
  end

  if action == "ejsub" then
    if Dibs.EncounterJournal and Dibs.EncounterJournal.HandleSubCategorySlash then
      Dibs.EncounterJournal.HandleSubCategorySlash(rest)
    else
      Dibs.Message("Encounter Journal sub-category controls are unavailable.")
    end
    return
  end

  if action == "dev" then
    if Dibs.DeveloperMode and Dibs.DeveloperMode.HandleDevSlash then
      Dibs.DeveloperMode.HandleDevSlash(args)
    else
      Dibs.Message("Developer mode module unavailable.")
    end
    return
  end

  if action == "testitem" then
    if Dibs.DeveloperMode and Dibs.DeveloperMode.HandleTestItemSlash then
      Dibs.DeveloperMode.HandleTestItemSlash(rest)
    else
      Dibs.Message("Developer mode module unavailable.")
    end
    return
  end

  if action == "balance" then
    local season = Dibs.Seasons and Dibs.Seasons.GetCurrent() or nil
    local balance = Dibs.Ledger and Dibs.Ledger.GetBalance(Dibs.GetPlayerName(), season and season.id) or 0
    Dibs.Message("Current balance: " .. tostring(balance))
    return
  end

  if action == "options" then
    if Dibs.RCOptions and Dibs.RCOptions.Open then Dibs.RCOptions.Open() end
    return
  end

  if action == "ui" then
    if Dibs.PlayerUI and Dibs.PlayerUI.Show then
      Dibs.PlayerUI.Show()
    end
    return
  end

  if action == "officer" then
    if Dibs.OfficerUI and Dibs.OfficerUI.Show then
      Dibs.OfficerUI.Show()
    end
    return
  end

  if action == "grant" then
    if not Dibs.Permissions or not Dibs.Permissions.CanManageDibs() then
      Dibs.Message("You do not have permission to grant Dibs.")
      return
    end

    local playerName = args[2]
    local amount = tonumber(args[3]) or 1
    local result = Dibs.ProtectedActions.Execute("ledger.grant", nil, { playerName = playerName, amount = amount, reason = "Officer grant", source = "slash" })
    Dibs.Message(result.ok and ("Granted " .. tostring(amount) .. " Dibs to " .. tostring(playerName)) or result.diagnostic)
    return
  end

  if action == "use" then
    if not Dibs.Permissions or not Dibs.Permissions.CanManageDibs() then
      Dibs.Message("You do not have permission to consume Dibs.")
      return
    end

    local playerName = args[2]
    local amount = tonumber(args[3]) or 1
    local result = Dibs.ProtectedActions.Execute("ledger.use", nil, { playerName = playerName, amount = amount, reason = "Officer consumption", source = "slash" })
    Dibs.Message(result.ok and ("Consumed " .. tostring(amount) .. " Dibs from " .. tostring(playerName)) or result.diagnostic)
    return
  end

  if action == "pre" then
    local itemID = tonumber(args[2]) or 0
    local itemName = table.concat(args, " ", 3)
    local payloadName = itemName ~= "" and itemName or "Item " .. tostring(itemID)
    local request, reason
    if Dibs.PreDibs and Dibs.PreDibs.CreatePublic and Dibs.PreDibs.IsPublicEnabled and Dibs.PreDibs.IsPublicEnabled() then
      request, reason = Dibs.PreDibs.CreatePublic(Dibs.GetPlayerName(), itemID, payloadName, Dibs.GetCurrentSeasonId(), "slash")
    else
      request = Dibs.PreDibs.Create(Dibs.GetPlayerName(), itemID, payloadName, Dibs.GetCurrentSeasonId())
    end

    if request then
      Dibs.Message("Pre-Dib created for item " .. tostring(itemID) .. " (status: " .. tostring(request.status) .. ")")
    else
      Dibs.Message(reason == "PUBLIC_PRE_DIBS_DISABLED" and "Public pre-dibs are disabled." or "A valid item ID is required.")
    end
    return
  end

  if action == "vault" then
    local record, reason = Dibs.PreDibs and Dibs.PreDibs.RecordVaultAcquisition and Dibs.PreDibs.RecordVaultAcquisition(Dibs.GetPlayerName(), args[2], args[3]) or nil, "ACQUISITIONS_UNAVAILABLE"
    if record then
      Dibs.Message("Vault acquisition recorded for item " .. tostring(record.itemID) .. " (" .. tostring(record.difficulty) .. ").")
    else
      Dibs.Message(reason == "INVALID_ITEM" and "A valid item ID is required." or "Unable to record Vault acquisition.")
    end
    return
  end

  if action == "predibmode" then
    local result = Dibs.ProtectedActions.Execute("predib.mode.set", nil, { seasonId = Dibs.GetCurrentSeasonId(), mode = args[2], source = "slash" })
    Dibs.Message(result.ok and ("Pre-Dib mode: " .. tostring(result.value.mode)) or (result.diagnostic or "Unable to change Pre-Dib mode."))
    return
  end

  if action == "mode" then
    local mode = args[2] or "AUTO"
    local result = Dibs.ProtectedActions.Execute("installation.mode.set", nil, { mode = mode, source = "slash" })
    Dibs.Message(result.ok and ("Installation mode: " .. tostring(result.value)) or (result.diagnostic or "Unable to change installation mode."))
    return
  end

  if action == "remind" then
    local ok, reason = Dibs.RaidRelay and Dibs.RaidRelay.SendReminder and Dibs.RaidRelay.SendReminder(rest) or false, "REMINDER_UNAVAILABLE"
    Dibs.Message(ok and "Dib reminder sent." or (reason or "Unable to send Dib reminder."))
    return
  end

  if action == "admin" then
    local mode, target = args[2] or "list", args[3]
    if mode == "list" then
      local result = Dibs.ProtectedActions.Execute("admin.list", nil, {})
      if not result.ok then Dibs.Message(result.diagnostic) return end
      local names = {}
      for _, admin in ipairs(result.value) do table.insert(names, tostring(admin.playerName)) end
      table.sort(names)
      Dibs.Message("Standalone Dibs administrators: " .. (#names > 0 and table.concat(names, ", ") or "none"))
      return
    end
    local actionId = mode == "add" and "admin.appoint" or (mode == "remove" and "admin.revoke" or nil)
    if not actionId or not target then Dibs.Message("Usage: /dibs admin list|add|remove <Name-Realm>") return end
    local result = Dibs.ProtectedActions.Execute(actionId, nil, { target = target, reason = "Slash command" })
    Dibs.Message(result.ok and ("Standalone administrator updated: " .. target) or result.diagnostic)
    return
  end

  if action == "season" then
    local mode = args[2] or "show"
    if mode == "create" then
      local name = table.concat(args, " ", 3)
       local result = Dibs.ProtectedActions.Execute("season.create", nil, { name = name ~= "" and name or nil })
       local season = result.value
      if season then
        Dibs.Message("Created season: " .. tostring(season.name) .. " (" .. tostring(season.id) .. ")")
      else
        Dibs.Message("Failed to create season.")
      end
      return
    end

    if mode == "set" then
      local seasonId = args[3]
       local result = Dibs.ProtectedActions.Execute("season.set", nil, { seasonId = seasonId })
       if result.ok then
        Dibs.Message("Current season set to: " .. tostring(seasonId))
      else
        Dibs.Message("Season not found: " .. tostring(seasonId))
      end
      return
    end

    if mode == "list" then
      local list = Dibs.Seasons and Dibs.Seasons.List() or {}
      local currentSeasonId = Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil
      local text = "Seasons: "
      for _, season in ipairs(list) do
        local marker = season.id == currentSeasonId and " [ACTIVE]" or ""
        text = text .. tostring(season.name) .. " (" .. tostring(season.id) .. ")" .. marker .. ", "
      end
      Dibs.Message(text)
      return
    end

    local season = Dibs.Seasons and Dibs.Seasons.GetCurrent()
    Dibs.Message("Current season: " .. tostring(season and season.name or "None") .. " (" .. tostring(season and season.id or "none") .. ")")
    return
  end

  if action == "rcopts" then
    if Dibs.RCOptions and Dibs.RCOptions.EnsureRegistered then
      local ok = Dibs.RCOptions.EnsureRegistered(10)
      Dibs.Message(ok and "RC options registration confirmed." or "RC options registration retry started.")
    else
      Dibs.Message("RC options integration module is unavailable.")
    end
    return
  end

  if action == "rank" then
    local mode = args[2] or "list"
    if mode == "set" then
      local rankIndex = tonumber(args[3]) or 0
      local allocation = tonumber(args[4]) or 1
      local rankName = table.concat(args, " ", 5)
       if Dibs.ProtectedActions then
         local result = Dibs.ProtectedActions.Execute("rank.set", nil, { seasonId = Dibs.GetCurrentSeasonId(), rankIndex = rankIndex, rankName = rankName ~= "" and rankName or "Rank " .. tostring(rankIndex), allocation = allocation })
         local rule = result.value
         if not result.ok then Dibs.Message(result.diagnostic) return end
        Dibs.Message("Rank " .. tostring(rankIndex) .. " set to " .. tostring(rule.allocation) .. " Dibs")
      end
      return
    end

    if mode == "list" then
      local season = Dibs.Seasons and Dibs.Seasons.GetCurrent() or nil
      local rules = Dibs.RankRules and Dibs.RankRules.GetRulesForSeason(season and season.id or Dibs.GetCurrentSeasonId()) or {}
      local text = "Rank rules: "
      local items = {}
      for _, rule in pairs(rules) do
        table.insert(items, "R" .. tostring(rule.rankIndex) .. "=" .. tostring(rule.allocation))
      end
      table.sort(items)
      text = text .. table.concat(items, ", ")
      Dibs.Message(text)
      return
    end
  end

  Dibs.Message("Unknown Dibs command. Use /dibs help.")
end

function Dibs.SetupSlashCommands()
  if _G.SlashCmdList then
    _G.SlashCmdList["DIBS"] = function(msg)
      Dibs.HandleSlashCommand(msg)
    end
    _G.SLASH_DIBS1 = "/dibs"
    _G.SLASH_DIBS2 = "/dib"
    _G.SLASH_DIBS3 = "/dids"
  end
end

-- Keep /dibs available even when an optional integration initializes later.
Dibs.SetupSlashCommands()

function Dibs.RegisterOptionsPanel()
  local rcLoaded = false
  if type(C_AddOns) == "table" and type(C_AddOns.IsAddOnLoaded) == "function" then
    local first, second = C_AddOns.IsAddOnLoaded("RCLootCouncil")
    rcLoaded = (second == true or first == true)
  end
  if not rcLoaded then
    rcLoaded = type(_G.RCLootCouncil) == "table"
  end

  -- When RCLootCouncil is present, Dibs registers under its options tree via integrations/RCLootCouncilOptions.lua.
  if rcLoaded then
    return nil
  end

  if _G.DibsOptionsPanel then
    return _G.DibsOptionsPanel
  end

  local panel = CreateFrame("Frame", "DibsOptionsPanel", UIParent)
  panel.name = "Dibs"

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Dibs")

  local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  subtitle:SetWidth(520)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetText("Use this panel to open Dibs windows quickly. Commands: /dibs ui, /dibs officer.")

  local openPlayerButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  openPlayerButton:SetSize(140, 24)
  openPlayerButton:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
  openPlayerButton:SetText("Open Player UI")
  openPlayerButton:SetScript("OnClick", function()
    if Dibs.PlayerUI and Dibs.PlayerUI.Toggle then
      Dibs.PlayerUI.Toggle(true)
    end
  end)

  local openOfficerButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  openOfficerButton:SetSize(140, 24)
  openOfficerButton:SetPoint("LEFT", openPlayerButton, "RIGHT", 12, 0)
  openOfficerButton:SetText("Open Officer UI")
  openOfficerButton:SetScript("OnClick", function()
    if Dibs.OfficerUI and Dibs.OfficerUI.Toggle then
      Dibs.OfficerUI.Toggle(true)
    end
  end)

  if _G.Settings and type(_G.Settings.RegisterCanvasLayoutCategory) == "function"
    and type(_G.Settings.RegisterAddOnCategory) == "function" then
    local category = _G.Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    _G.Settings.RegisterAddOnCategory(category)
  end

  _G.DibsOptionsPanel = panel
  return panel
end

function Dibs.Initialize()
  if Dibs.initialized then
    return true
  end

  ensureDB()

  if Dibs.Seasons and Dibs.Seasons.GetOrCreateDefault then
    Dibs.Seasons.GetOrCreateDefault()
  end

  if Dibs.RankRules then
    Dibs.ApplyDefaultRules()
  end

  if Dibs.PlayerUI and Dibs.PlayerUI.CreateWindow then
    Dibs.PlayerUI.CreateWindow()
  end

  if Dibs.OfficerUI and Dibs.OfficerUI.CreateWindow then
    Dibs.OfficerUI.CreateWindow()
  end

  if Dibs.RCLootCouncil and Dibs.RCLootCouncil.Initialize then
    Dibs.RCLootCouncil.Initialize()
  end

  if Dibs.EncounterJournal and Dibs.EncounterJournal.AddActionIfAvailable then
    Dibs.EncounterJournal.AddActionIfAvailable()
  end

  if Dibs.Sync and Dibs.Sync.RegisterTransport then
    Dibs.Sync.RegisterTransport()
  end

  Dibs.SetupSlashCommands()
  Dibs.RegisterOptionsPanel()
  if Dibs.RCOptions and Dibs.RCOptions.EnsureRegistered then
    Dibs.RCOptions.EnsureRegistered(120)
  end
  Dibs.initialized = true
  Dibs.Message("Dibs initialized")
  return true
end

local eventFrame = CreateFrame("Frame")
local function onRuntimeEvent(event, ...)
  if event == "PLAYER_LOGIN" then
    Dibs.Initialize()
    -- Core initialization must never depend on the optional adapter.  A late
    -- RCLootCouncil load is rechecked after Dibs is ready, while Standalone
    -- mode still receives the normal database, UI, and slash-command setup.
    if Dibs.RCLootCouncil and Dibs.RCLootCouncil.TryUseRCModule then
      Dibs.RCLootCouncil.TryUseRCModule()
    end
    return
  end
  if event == "CHAT_MSG_ADDON" and Dibs.Sync and Dibs.Sync.OnAddonMessage then return Dibs.Sync.OnAddonMessage(...) end
  if event == "GROUP_ROSTER_UPDATE" and Dibs.Sync and Dibs.Sync.OnRosterChanged then Dibs.Sync.OnRosterChanged() end
  if Dibs.RaidPrompts and Dibs.RaidPrompts.OnEvent then Dibs.RaidPrompts.OnEvent(event) end
end

function Dibs.SetupRuntimeEvents()
  if Dibs.runtimeEventsRegistered then return true end
  local events = { "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED" }
  local usingAceEvent = Dibs.Ace3 and Dibs.Ace3.RegisterEvent
  if usingAceEvent then
    for _, event in ipairs(events) do Dibs.Ace3.RegisterEvent(event, onRuntimeEvent) end
    if not (Dibs.Sync and Dibs.Sync.RegisterTransport and Dibs.Sync.RegisterTransport()) then
      Dibs.Ace3.RegisterEvent("CHAT_MSG_ADDON", onRuntimeEvent)
    end
  else
    for _, event in ipairs(events) do eventFrame:RegisterEvent(event) end
    eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    eventFrame:SetScript("OnEvent", function(_, event, ...) return onRuntimeEvent(event, ...) end)
  end
  Dibs.runtimeEventsRegistered = true
  return true
end

ensureDB()
