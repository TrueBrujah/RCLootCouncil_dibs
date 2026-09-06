local Dibs = _G.Dibs
Dibs.PreDibs = Dibs.PreDibs or {}

local VALID_ANNOUNCE_CHANNELS = {
  NONE = true,
  GUILD = true,
  OFFICER = true,
  RAID = true,
  RAID_WARNING = true,
  RAID_DIBS = true,
  PARTY = true,
  INSTANCE_CHAT = true,
  SAY = true,
  YELL = true,
}

local function normalizeChannel(value, fallback)
  local key = string.upper(tostring(value or ""))
  if VALID_ANNOUNCE_CHANNELS[key] then
    return key
  end
  return fallback or "NONE"
end

local function announcementDebug(message)
  if Dibs.PreDibs.announcementDebug and Dibs.DebugEnabled and Dibs.DebugEnabled("announce", 4) and Dibs.Message then
    Dibs.Message("[Announcement Debug] " .. tostring(message))
  end
end

local function isRaidDibsChannelAvailable()
  local clubId, streamId = Dibs.PreDibs.GetRaidDibsChannel()
  return clubId ~= nil and streamId ~= nil
end

function Dibs.PreDibs.GetRaidDibsChannel()
  local clubs = _G.C_Club
  if type(clubs) ~= "table" or type(clubs.GetSubscribedClubs) ~= "function" or type(clubs.GetStreams) ~= "function" then
    announcementDebug("C_Club API incomplet: GetSubscribedClubs/GetStreams manquant")
    return nil
  end
  local ok, subscribed = pcall(clubs.GetSubscribedClubs)
  if not ok or type(subscribed) ~= "table" then
    announcementDebug("GetSubscribedClubs a echoue ou n'a pas renvoye une table")
    return nil
  end
  local clubCount = 0
  for clubKey, club in pairs(subscribed) do
    clubCount = clubCount + 1
    local clubId
    if type(club) == "table" then
      clubId = club.clubId or club.clubID or club.clubIdentifier
    else
      clubId = club
    end
    if not clubId and (type(clubKey) == "number" or type(clubKey) == "string") then
      clubId = clubKey
    end
    announcementDebug("club[" .. tostring(clubKey) .. "] id=" .. tostring(clubId))
    local streamOk, streams = pcall(clubs.GetStreams, clubId)
    announcementDebug("GetStreams(" .. tostring(clubId) .. ") ok=" .. tostring(streamOk) .. " type=" .. type(streams))
    if streamOk and type(streams) == "table" then
      for streamKey, stream in pairs(streams) do
        local streamId = type(stream) == "table" and (stream.streamId or stream.streamID) or streamKey
        local streamName = type(stream) == "table" and (stream.name or stream.streamName) or stream
        streamName = string.lower(tostring(streamName or "")):match("^%s*(.-)%s*$")
        announcementDebug(" stream[" .. tostring(streamKey) .. "] id=" .. tostring(streamId) .. " name=" .. tostring(streamName))
        if streamId and streamName == "raid dibs" then
          announcementDebug("MATCH clubId=" .. tostring(clubId) .. " streamId=" .. tostring(streamId))
          return clubId, streamId
        end
      end
    end
  end
  announcementDebug("aucun stream Raid Dibs trouve; clubs inspectes=" .. tostring(clubCount))
  return nil
end

function Dibs.PreDibs.SetAnnouncementDebug(enabled, actor)
  if not Dibs.Permissions or type(Dibs.Permissions.Can) ~= "function"
    or not Dibs.Permissions.Can("settings.modify", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  Dibs.PreDibs.announcementDebug = enabled == true
  return Dibs.PreDibs.announcementDebug, nil
end

function Dibs.PreDibs.DebugRaidDibs()
  local previous = Dibs.PreDibs.announcementDebug
  Dibs.PreDibs.announcementDebug = true
  local clubId, streamId = Dibs.PreDibs.GetRaidDibsChannel()
  Dibs.Message("[Announcement Debug] resultat clubId=" .. tostring(clubId) .. " streamId=" .. tostring(streamId))
  Dibs.PreDibs.announcementDebug = previous
  return clubId, streamId
end

local function ensureRaidDibsChannel()
  local clubId, streamId = Dibs.PreDibs.GetRaidDibsChannel()
  if clubId and streamId then return clubId, streamId end
  return nil, "RAID_DIBS_UNAVAILABLE"
end

local function ensureState()
  Dibs.db = Dibs.GetDB and Dibs.GetDB() or (_G.DibsDB or {})
  Dibs.db.preDibs = Dibs.db.preDibs or { requests = {} }
  Dibs.db.preDibs.requests = Dibs.db.preDibs.requests or {}
  Dibs.db.preDibs.modePolicies = Dibs.db.preDibs.modePolicies or {}
  Dibs.db.preDibs.acquisitions = Dibs.db.preDibs.acquisitions or {}
  Dibs.db.settings = Dibs.db.settings or {}
  if Dibs.db.settings.allowPublicPreDibs == nil then
    Dibs.db.settings.allowPublicPreDibs = true
  end
  Dibs.db.settings.preDibAnnouncementChannel = normalizeChannel(Dibs.db.settings.preDibAnnouncementChannel, "GUILD")
  Dibs.db.settings.preDibOfficerAnnouncementChannel = normalizeChannel(Dibs.db.settings.preDibOfficerAnnouncementChannel, "OFFICER")
  if Dibs.db.settings.preDibAnnouncementTemplate == nil then
    Dibs.db.settings.preDibAnnouncementTemplate = DEFAULT_PREDIB_TEMPLATE
  end
  if Dibs.db.settings.raidReminderTemplate == nil then
    Dibs.db.settings.raidReminderTemplate = Dibs.db.settings.raidReminderMessage or DEFAULT_REMINDER_TEMPLATE
  end
end

local VALID_MODES = { WILD_OPEN = true, ENCOUNTER = true }
local DIFFICULTY_NAMES = { [14] = "Normal", [15] = "Heroic", [16] = "Mythic" }
local DEFAULT_PREDIB_TEMPLATE = "[Dibs] %player requested %item (%difficulty) - %date %time"
local DEFAULT_REMINDER_TEMPLATE = "[Dibs] Review your eligible Pre-Dibs before the encounter. [%date %time]"

local function formatDateTime(format, timestamp)
  if type(date) == "function" then
    return date(format, timestamp)
  end
  return tostring(timestamp or time())
end

local function templateValue(value)
  return tostring(value == nil and "" or value)
end

function Dibs.PreDibs.FormatAnnouncement(template, context)
  local value = tostring(template or "")
  local data = type(context) == "table" and context or {}
  local now = time()
  local values = {
    player = data.playerName or data.player or Dibs.GetPlayerName and Dibs.GetPlayerName() or "Unknown",
    item = data.itemName or (data.itemID and ("Item " .. tostring(data.itemID)) or "Unknown item"),
    itemID = data.itemID,
    difficulty = data.difficulty or "Unknown",
    mode = data.modeAtCreation or data.mode or "WILD_OPEN",
    status = data.status or "confirmed",
    season = data.seasonName or data.seasonId or "Unknown season",
    date = data.date or formatDateTime("%Y-%m-%d", now),
    time = data.time or formatDateTime("%H:%M:%S", now),
    requestID = data.requestId,
    source = data.source or "Pre-Dib",
    channel = data.channel or "",
  }
  return (value:gsub("%%([%w_]+)", function(key)
    if values[key] == nil then return "%" .. key end
    return templateValue(values[key])
  end))
end

function Dibs.PreDibs.NormalizeDifficulty(value)
  local numeric = tonumber(value)
  if numeric and DIFFICULTY_NAMES[numeric] then return DIFFICULTY_NAMES[numeric] end
  local label = string.lower(tostring(value or ""))
  if label == "normal" then return "Normal" end
  if label == "heroic" then return "Heroic" end
  if label == "mythic" then return "Mythic" end
  return "UNKNOWN"
end

local function samePlayer(first, second)
  if Dibs.Permissions and Dibs.Permissions.CanonicalPlayerId then
    local firstId = Dibs.Permissions.CanonicalPlayerId(first)
    local secondId = Dibs.Permissions.CanonicalPlayerId(second)
    if firstId and secondId then
      return firstId == secondId
    end
  end
  return string.lower(tostring(first or "")) == string.lower(tostring(second or ""))
end

local function requestContext(context)
  local value = type(context) == "table" and context or {}
  return {
    inRaid = value.inRaid == true,
    raidId = value.raidId or value.instanceId,
    itemRaidId = value.itemRaidId or value.raidId,
    isSupportedRaidLoot = value.isSupportedRaidLoot ~= false,
    source = value.source,
    difficulty = Dibs.PreDibs.NormalizeDifficulty(value.difficulty),
  }
end

local function ensureRuntimeState()
  Dibs.runtime = Dibs.runtime or {}
  Dibs.runtime.dev = Dibs.runtime.dev or {}
  Dibs.runtime.dev.requests = Dibs.runtime.dev.requests or {}
end

local function isChannelAvailable(channel)
  if channel == "NONE" then return false end
  if channel == "GUILD" or channel == "OFFICER" then
    return type(IsInGuild) == "function" and IsInGuild() == true
  end
  if channel == "RAID" then
    return type(IsInRaid) == "function" and IsInRaid() == true
  end
  if channel == "RAID_WARNING" then
    if type(IsInRaid) ~= "function" or IsInRaid() ~= true then return false end
    local isLeader = type(UnitIsGroupLeader) == "function" and UnitIsGroupLeader("player") == true
    local isAssistant = type(UnitIsGroupAssistant) == "function" and UnitIsGroupAssistant("player") == true
    return isLeader or isAssistant
  end
  if channel == "PARTY" then
    local inGroup = type(IsInGroup) == "function" and IsInGroup() == true
    local inRaid = type(IsInRaid) == "function" and IsInRaid() == true
    return inGroup and not inRaid
  end
  if channel == "INSTANCE_CHAT" then
    if type(IsInGroup) ~= "function" then return false end
    return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) == true
  end
  if channel == "RAID_DIBS" then
    return isRaidDibsChannelAvailable()
  end
  return true
end

local function sendAnnouncement(channel, message, raidDibsInfo)
  local normalized = normalizeChannel(channel, "NONE")
  announcementDebug("send channel=" .. tostring(channel) .. " normalized=" .. tostring(normalized))
  local ok
  if normalized == "RAID_DIBS" then
    local clubId = raidDibsInfo and raidDibsInfo.clubId
    local streamId = raidDibsInfo and raidDibsInfo.streamId
    if not clubId or not streamId then
      clubId, streamId = Dibs.PreDibs.GetRaidDibsChannel()
    end
    if not clubId or not streamId then
      announcementDebug("aucun club/stream resolu")
      return false, "RAID_DIBS_NOT_JOINED"
    end
    local api = _G.C_Club
    if type(api) ~= "table" or type(api.SendMessage) ~= "function" then
      announcementDebug("C_Club.SendMessage manquant")
      return false, "CLUB_API_UNAVAILABLE"
    end
    local callOk, result = pcall(api.SendMessage, clubId, streamId, tostring(message))
    announcementDebug("C_Club.SendMessage(" .. tostring(clubId) .. ", " .. tostring(streamId) .. ") ok=" .. tostring(callOk) .. " retour=" .. tostring(result))
    ok = callOk
  else
    if not isChannelAvailable(normalized) then
      announcementDebug("canal indisponible avant envoi")
      return false, "CHANNEL_UNAVAILABLE"
    end
    if type(SendChatMessage) ~= "function" then return false, "CHAT_API_UNAVAILABLE" end
    announcementDebug("SendChatMessage canal=" .. tostring(normalized))
    ok = pcall(SendChatMessage, tostring(message), normalized)
  end
  return ok == true, ok == true and nil or "CHAT_SEND_FAILED"
end

function Dibs.PreDibs.SendTestAnnouncement(channel, audience, actor)
  if not Dibs.Permissions or type(Dibs.Permissions.Can) ~= "function"
    or not Dibs.Permissions.Can("settings.modify", actor) then
    return false, "GUILD_ADMIN_REQUIRED"
  end
  ensureState()
  local normalized = normalizeChannel(channel, "NONE")
  announcementDebug("bouton test audience=" .. tostring(audience) .. " channel=" .. tostring(channel) .. " normalized=" .. tostring(normalized))
  local raidDibsInfo
  if normalized == "RAID_DIBS" then
    local clubId, streamIdOrReason = ensureRaidDibsChannel()
    if not clubId then return false, streamIdOrReason end
    raidDibsInfo = { clubId = clubId, streamId = streamIdOrReason }
  end
  local message = Dibs.PreDibs.FormatAnnouncement(
    Dibs.db.settings.preDibAnnouncementTemplate or DEFAULT_PREDIB_TEMPLATE,
    {
      playerName = Dibs.GetPlayerName and Dibs.GetPlayerName() or "Player-Realm",
      itemName = "Example item",
      itemID = 12345,
      difficulty = "Mythic",
      modeAtCreation = "WILD_OPEN",
      status = "confirmed",
      source = tostring(audience or "Announcement") .. " channel test",
    }
  )
  return sendAnnouncement(normalized, "[Dibs Test] " .. message, raidDibsInfo)
end

local function buildAnnouncementMessage(request)
  ensureState()
  local template = Dibs.db.settings.preDibAnnouncementTemplate or DEFAULT_PREDIB_TEMPLATE
  return Dibs.PreDibs.FormatAnnouncement(template, request)
end

local function announcePreDib(request)
  ensureState()
  if type(request) ~= "table" then return end
  local message = buildAnnouncementMessage(request)
  local publicChannel = normalizeChannel(Dibs.db.settings.preDibAnnouncementChannel, "GUILD")
  local officerChannel = normalizeChannel(Dibs.db.settings.preDibOfficerAnnouncementChannel, "OFFICER")
  local sent = {}
  if publicChannel ~= "NONE" and not sent[publicChannel] then
    sendAnnouncement(publicChannel, message)
    sent[publicChannel] = true
  end
  if officerChannel ~= "NONE" and not sent[officerChannel] then
    sendAnnouncement(officerChannel, message)
    sent[officerChannel] = true
  end
end

local function logPreDibToRCLootCouncil(request, sourceLabel)
  if not (Dibs and Dibs.RCLootCouncil and type(Dibs.RCLootCouncil.LogPreDibRequest) == "function") then
    return false
  end
  local ok = pcall(Dibs.RCLootCouncil.LogPreDibRequest, request, sourceLabel)
  return ok == true
end

local function isRequestActive(request)
  return request.status ~= "fulfilled" and request.status ~= "cancelled" and request.status ~= "invalidated"
end

local VALID_STATUS_TRANSITIONS = {
  pending = { confirmed = true, cancelled = true, invalidated = true },
  confirmed = { cancelled = true, invalidated = true, fulfilled = true },
}

local function findActiveRequest(playerName, itemID, seasonId, difficulty)
  local targetPlayer = tostring(playerName or Dibs.GetPlayerName())
  local targetItem = tonumber(itemID) or 0
  local targetSeason = seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
  local targetDifficulty = Dibs.PreDibs.NormalizeDifficulty(difficulty)
  for _, request in ipairs(Dibs.db.preDibs.requests) do
    if tonumber(request.itemID) == targetItem
      and tostring(request.playerName or "") == targetPlayer
      and request.seasonId == targetSeason
      and Dibs.PreDibs.NormalizeDifficulty(request.difficulty) == targetDifficulty
      and isRequestActive(request)
    then
      return request
    end
  end
  return nil
end

function Dibs.PreDibs.IsPublicEnabled()
  ensureState()
  return Dibs.db.settings.allowPublicPreDibs ~= false
end

function Dibs.PreDibs.GetModePolicy(seasonId)
  ensureState()
  local targetSeason = seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
  local policy = targetSeason and Dibs.db.preDibs.modePolicies[targetSeason] or nil
  if type(policy) ~= "table" then
    return { seasonId = targetSeason, mode = "WILD_OPEN" }
  end
  return policy
end

function Dibs.PreDibs.SetModePolicy(seasonId, mode, actor)
  ensureState()
  if type(Dibs.Permissions) ~= "table" or type(Dibs.Permissions.Can) ~= "function"
    or not Dibs.Permissions.Can("settings.modify", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  local targetSeason = seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
  local normalized = string.upper(tostring(mode or ""))
  if not targetSeason then return nil, "NO_ACTIVE_SEASON" end
  if not VALID_MODES[normalized] then return nil, "INVALID_PREDIB_MODE" end
  local policy = { seasonId = targetSeason, mode = normalized, changedAt = time(), changedBy = actor or (Dibs.GetPlayerName and Dibs.GetPlayerName() or "Unknown") }
  Dibs.db.preDibs.modePolicies[targetSeason] = policy
  return policy
end

function Dibs.PreDibs.ValidatePublicRequest(itemID, seasonId, context)
  local targetItem = tonumber(itemID)
  if not targetItem or targetItem <= 0 then return nil, "INVALID_ITEM" end
  local policy = Dibs.PreDibs.GetModePolicy(seasonId)
  local validation = requestContext(context)
  if validation.isSupportedRaidLoot ~= true then return nil, "UNSUPPORTED_RAID_LOOT", policy, validation end
  if policy.mode == "ENCOUNTER" then
    if validation.inRaid ~= true then return nil, "ENCOUNTER_REQUIRES_RAID", policy, validation end
    if not validation.raidId or validation.raidId ~= validation.itemRaidId then return nil, "ENCOUNTER_RAID_MISMATCH", policy, validation end
  end
  return true, nil, policy, validation
end

function Dibs.PreDibs.GetAnnouncementSettings()
  ensureState()
  return {
    publicChannel = normalizeChannel(Dibs.db.settings.preDibAnnouncementChannel, "GUILD"),
    officerChannel = normalizeChannel(Dibs.db.settings.preDibOfficerAnnouncementChannel, "OFFICER"),
  }
end

function Dibs.PreDibs.SetAnnouncementChannels(publicChannel, officerChannel, actor)
  ensureState()
  if type(Dibs.Permissions) ~= "table" or type(Dibs.Permissions.Can) ~= "function"
    or not Dibs.Permissions.Can("settings.modify", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  Dibs.db.settings.preDibAnnouncementChannel = normalizeChannel(publicChannel, "GUILD")
  Dibs.db.settings.preDibOfficerAnnouncementChannel = normalizeChannel(officerChannel, "OFFICER")
  return Dibs.PreDibs.GetAnnouncementSettings()
end

function Dibs.PreDibs.GetAnnouncementTemplates()
  ensureState()
  return {
    preDib = tostring(Dibs.db.settings.preDibAnnouncementTemplate or DEFAULT_PREDIB_TEMPLATE),
    reminder = tostring(Dibs.db.settings.raidReminderTemplate or DEFAULT_REMINDER_TEMPLATE),
  }
end

function Dibs.PreDibs.SetAnnouncementTemplates(preDibTemplate, reminderTemplate, actor)
  ensureState()
  if type(Dibs.Permissions) ~= "table" or type(Dibs.Permissions.Can) ~= "function"
    or not Dibs.Permissions.Can("settings.modify", actor) then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  if preDibTemplate ~= nil then
    Dibs.db.settings.preDibAnnouncementTemplate = tostring(preDibTemplate)
  end
  if reminderTemplate ~= nil then
    Dibs.db.settings.raidReminderTemplate = tostring(reminderTemplate)
    Dibs.db.settings.raidReminderMessage = tostring(reminderTemplate)
  end
  return Dibs.PreDibs.GetAnnouncementTemplates()
end

function Dibs.PreDibs.Create(playerName, itemID, itemName, seasonId)
  ensureState()
  if not tonumber(itemID) or tonumber(itemID) <= 0 then return nil end

  local targetSeason = seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
  if targetSeason == nil or targetSeason == "" then
    return nil, "NO_ACTIVE_SEASON"
  end

  local request = {
    requestId = Dibs.NewId("predib"),
    playerName = playerName or Dibs.GetPlayerName(),
    itemID = tonumber(itemID) or 0,
    itemName = itemName or "Unknown item",
    seasonId = targetSeason,
    status = "pending",
    createdAt = time(),
    updatedAt = time(),
    difficulty = "UNKNOWN",
  }

  table.insert(Dibs.db.preDibs.requests, request)
  return request
end

function Dibs.PreDibs.CreatePublic(playerName, itemID, itemName, seasonId, source, context)
  ensureState()
  if Dibs.PreDibs.IsPublicEnabled() ~= true then
    return nil, "PUBLIC_PRE_DIBS_DISABLED"
  end

  local targetItem = tonumber(itemID)
  if not targetItem or targetItem <= 0 then
    return nil, "INVALID_ITEM"
  end

  local targetSeason = seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
  if targetSeason == nil or targetSeason == "" then
    return nil, "NO_ACTIVE_SEASON"
  end

  local accepted, validationReason, policy, validation = Dibs.PreDibs.ValidatePublicRequest(targetItem, targetSeason, context)
  if accepted ~= true then return nil, validationReason end

  local existing = findActiveRequest(playerName, targetItem, targetSeason, validation.difficulty)
  if existing then
    if existing.status ~= "confirmed" then
      existing.status = "confirmed"
      existing.confirmedAt = time()
      existing.updatedAt = existing.confirmedAt
      existing.revision = (tonumber(existing.revision) or 1) + 1
      existing.source = source or existing.source or "public"
      announcePreDib(existing)
      logPreDibToRCLootCouncil(existing, source)
    end
    return existing
  end

  local now = time()
  local request = {
    requestId = Dibs.NewId("predib"),
    playerName = playerName or Dibs.GetPlayerName(),
    itemID = targetItem,
    itemName = itemName or ("Item " .. tostring(targetItem)),
    seasonId = targetSeason,
    status = "confirmed",
    source = source or "public",
    createdAt = now,
    updatedAt = now,
    confirmedAt = now,
    revision = 1,
    modeAtCreation = policy.mode,
    validationContext = validation,
    difficulty = validation.difficulty,
    delivery = { state = "PENDING" },
  }

  table.insert(Dibs.db.preDibs.requests, request)
  announcePreDib(request)
  logPreDibToRCLootCouncil(request, source)
  return request
end

function Dibs.PreDibs.CreateTest(playerName, itemID, itemName, seasonId, source, context)
  ensureState()
  ensureRuntimeState()

  local targetItem = tonumber(itemID)
  if not targetItem or targetItem <= 0 then
    return nil, "INVALID_ITEM"
  end

  local now = time()
  local request = {
    requestId = Dibs.NewId("predibtest"),
    playerName = playerName or Dibs.GetPlayerName(),
    itemID = targetItem,
    itemName = itemName or ("Item " .. tostring(targetItem)),
    seasonId = seasonId or Dibs.GetCurrentSeasonId(),
    status = "confirmed",
    source = source or "DEV",
    isTest = true,
    createdAt = now,
    updatedAt = now,
    confirmedAt = now,
    context = context,
  }

  table.insert(Dibs.runtime.dev.requests, request)
  return request
end

function Dibs.PreDibs.GetTestHistory()
  ensureRuntimeState()
  return Dibs.runtime.dev.requests
end

function Dibs.PreDibs.UpdateStatus(requestId, status)
  ensureState()

  for _, request in ipairs(Dibs.db.preDibs.requests) do
    if request.requestId == requestId then
      if VALID_STATUS_TRANSITIONS[request.status] == nil
        or VALID_STATUS_TRANSITIONS[request.status][status] ~= true
      then
        return nil, "INVALID_STATUS_TRANSITION"
      end
      request.status = status
      request.updatedAt = time()
      request.revision = (tonumber(request.revision) or 1) + 1
      if status == "confirmed" and request.confirmedAt == nil then
        request.confirmedAt = request.updatedAt
        announcePreDib(request)
        logPreDibToRCLootCouncil(request)
      elseif status == "fulfilled" and request.fulfilledAt == nil then
        request.fulfilledAt = request.updatedAt
      elseif status == "cancelled" and request.cancelledAt == nil then
        request.cancelledAt = request.updatedAt
      end
      return request
    end
  end

  return nil
end

function Dibs.PreDibs.UpsertFromSync(incoming, senderName)
  ensureState()
  local incomingItemId = type(incoming) == "table" and tonumber(incoming.itemID) or nil
  local incomingRevision = type(incoming) == "table" and (incoming.revision == nil and 1 or tonumber(incoming.revision)) or nil
  if type(incoming) ~= "table" or type(incoming.requestId) ~= "string" or #incoming.requestId < 1 or #incoming.requestId > 96
    or type(incoming.playerName) ~= "string" or #incoming.playerName < 1 or #incoming.playerName > 96
    or not incomingItemId or incomingItemId <= 0 or math.floor(incomingItemId) ~= incomingItemId
    or (type(incoming.seasonId) ~= "string" and type(incoming.seasonId) ~= "number")
    or not incomingRevision or incomingRevision < 1 or incomingRevision > 1000000 or math.floor(incomingRevision) ~= incomingRevision then
    return nil, "INVALID_REQUEST"
  end
  local validIncomingStatus = incoming.status == "pending" or incoming.status == "confirmed"
    or incoming.status == "cancelled" or incoming.status == "invalidated"
  if type(incoming.status) ~= "string" or not validIncomingStatus then
    return nil, "INVALID_STATUS"
  end
  if senderName and not samePlayer(senderName, incoming.playerName) then
    return nil, "OWNER_MISMATCH"
  end
  if incoming.status == "fulfilled" then return nil, "UNTRUSTED_FULFILLMENT" end
  for _, existing in ipairs(Dibs.db.preDibs.requests) do
    if existing.requestId == incoming.requestId then
      if incomingRevision <= (tonumber(existing.revision) or 1) then return nil, "STALE_REVISION" end
      if not samePlayer(existing.playerName, incoming.playerName) then
        return nil, "IMMUTABLE_FIELD_MISMATCH"
      end
      if existing.status ~= incoming.status and (not VALID_STATUS_TRANSITIONS[existing.status] or VALID_STATUS_TRANSITIONS[existing.status][incoming.status] ~= true) then
        return nil, "INVALID_STATUS_TRANSITION"
      end
       for key, value in pairs(incoming) do
         if key ~= "playerName" and key ~= "itemID" and key ~= "seasonId" and key ~= "modeAtCreation"
           and key ~= "createdAt" and key ~= "delivery" then existing[key] = value end
      end
      return existing
    end
  end
  if incoming.status ~= "pending" and incoming.status ~= "confirmed" then
    return nil, "MISSING_ORIGINAL_REQUEST"
  end
  incoming.revision = incomingRevision
  -- Delivery acknowledgement is local officer metadata; an owner-supplied
  -- sync record can never claim that an officer received it.
  incoming.delivery = { state = "PENDING" }
  table.insert(Dibs.db.preDibs.requests, incoming)
  return incoming
end

function Dibs.PreDibs.AcknowledgeDelivery(requestId, revision, officerName)
  ensureState()
  local numericRevision = tonumber(revision)
  if type(requestId) ~= "string" or #requestId < 1 or #requestId > 96
    or not numericRevision or numericRevision < 1 or numericRevision > 1000000 or math.floor(numericRevision) ~= numericRevision then
    return nil, "INVALID_REVISION"
  end
  if type(Dibs.Permissions) ~= "table" or type(Dibs.Permissions.GetGuildRole) ~= "function" then
    return nil, "GUILD_ADMIN_REQUIRED"
  end
  local role = Dibs.Permissions.GetGuildRole(officerName)
  if role ~= "gm" and role ~= "officer" then return nil, "GUILD_ADMIN_REQUIRED" end
  for _, request in ipairs(Dibs.db.preDibs.requests) do
    if request.requestId == requestId and numericRevision <= (tonumber(request.revision) or 1) then
      request.delivery = { state = "ACKNOWLEDGED", lastAcknowledgedRevision = numericRevision, acknowledgedBy = officerName, acknowledgedAt = time() }
      return request
    end
  end
  return nil, "UNKNOWN_REQUEST"
end

function Dibs.PreDibs.Confirm(requestId)
  return Dibs.PreDibs.UpdateStatus(requestId, "confirmed")
end

function Dibs.PreDibs.Cancel(requestId)
  return Dibs.PreDibs.UpdateStatus(requestId, "cancelled")
end

function Dibs.PreDibs.CancelForPlayer(requestId, playerName)
  ensureState()
  local player = playerName or (Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
  for _, request in ipairs(Dibs.db.preDibs.requests) do
    if request.requestId == requestId then
      if not samePlayer(request.playerName, player) then
        return nil, "NOT_REQUEST_OWNER"
      end
      if not isRequestActive(request) then
        return nil, "INVALID_STATUS_TRANSITION"
      end
      return Dibs.PreDibs.Cancel(requestId)
    end
  end
  return nil, "UNKNOWN_REQUEST"
end

function Dibs.PreDibs.Invalidate(requestId)
  return Dibs.PreDibs.UpdateStatus(requestId, "invalidated")
end

function Dibs.PreDibs.Fulfill(requestId)
  return Dibs.PreDibs.UpdateStatus(requestId, "fulfilled")
end

function Dibs.PreDibs.GetActiveRequests(playerName)
  ensureState()
  local active = {}
  for _, request in ipairs(Dibs.db.preDibs.requests) do
    if request.playerName == (playerName or Dibs.GetPlayerName()) and isRequestActive(request) then
      table.insert(active, request)
    end
  end
  return active
end

function Dibs.PreDibs.GetRequestsForItem(itemID)
  ensureState()
  local list = {}
  local targetItem = tonumber(itemID) or 0
  for _, request in ipairs(Dibs.db.preDibs.requests) do
    if tonumber(request.itemID) == targetItem then
      table.insert(list, request)
    end
  end
  return list
end

function Dibs.PreDibs.GetConfirmedRequestForPlayer(playerName, itemID, seasonId, difficulty)
  ensureState()
  local targetPlayer = playerName or Dibs.GetPlayerName()
  local targetSeason = seasonId or (Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil)
  local requests = Dibs.PreDibs.GetRequestsForItem(itemID)
  for _, request in ipairs(requests) do
    if samePlayer(request.playerName, targetPlayer)
      and request.seasonId == targetSeason
      and request.status == "confirmed"
      and (difficulty == nil or Dibs.PreDibs.NormalizeDifficulty(request.difficulty) == Dibs.PreDibs.NormalizeDifficulty(difficulty))
    then
      return request
    end
  end
  return nil
end

function Dibs.PreDibs.RecordVaultAcquisition(playerName, itemID, difficulty)
  ensureState()
  local targetItem = tonumber(itemID)
  if not targetItem or targetItem <= 0 then return nil, "INVALID_ITEM" end
  local player = playerName or (Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
  if not player or player == "" then return nil, "INVALID_PLAYER" end
  local normalizedDifficulty = Dibs.PreDibs.NormalizeDifficulty(difficulty)
  for _, record in ipairs(Dibs.db.preDibs.acquisitions) do
    if samePlayer(record.playerName, player) and tonumber(record.itemID) == targetItem
      and record.source == "VAULT" and Dibs.PreDibs.NormalizeDifficulty(record.difficulty) == normalizedDifficulty then
      return record
    end
  end
  local record = {
    acquisitionId = Dibs.NewId("vault"), playerName = player, itemID = targetItem,
    difficulty = normalizedDifficulty, source = "VAULT", acquiredAt = time(),
    seasonId = Dibs.GetCurrentSeasonId and Dibs.GetCurrentSeasonId() or nil,
  }
  table.insert(Dibs.db.preDibs.acquisitions, record)
  return record
end

function Dibs.PreDibs.GetAcquisitionsForItem(itemID)
  ensureState()
  local records, targetItem = {}, tonumber(itemID) or 0
  for _, record in ipairs(Dibs.db.preDibs.acquisitions) do
    if tonumber(record.itemID) == targetItem then table.insert(records, record) end
  end
  return records
end

function Dibs.PreDibs.GetAcquisitionsForPlayer(playerName)
  ensureState()
  local records, player = {}, playerName or (Dibs.GetPlayerName and Dibs.GetPlayerName() or nil)
  for _, record in ipairs(Dibs.db.preDibs.acquisitions) do
    if samePlayer(record.playerName, player) then table.insert(records, record) end
  end
  return records
end

function Dibs.PreDibs.GetAcquisitions()
  ensureState()
  return Dibs.db.preDibs.acquisitions
end

function Dibs.PreDibs.GetConfirmedRequestsForItem(itemID)
  ensureState()
  local list = {}
  for _, request in ipairs(Dibs.PreDibs.GetRequestsForItem(itemID)) do
    if request.status == "confirmed" then
      table.insert(list, request)
    end
  end
  return list
end

function Dibs.PreDibs.HasConfirmedRequestsForItem(itemID)
  return #Dibs.PreDibs.GetConfirmedRequestsForItem(itemID) > 0
end

function Dibs.PreDibs.GetHistory()
  ensureState()
  return Dibs.db.preDibs.requests
end
